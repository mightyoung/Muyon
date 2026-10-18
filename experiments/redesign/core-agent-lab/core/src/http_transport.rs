//! Bounded loopback-only synthetic HTTP transport. No live endpoint support.
use crate::{model::ProviderControl, Result};
use std::{io::{Read, Write}, net::{SocketAddr, TcpStream}, time::{Duration, Instant}};

#[derive(Clone, Debug)]
pub struct LoopbackHttpConfig {
    pub address: SocketAddr,
    pub idle_timeout: Duration,
    pub total_timeout: Duration,
    /// Total HTTP response bytes, including its headers.
    pub max_response_bytes: usize,
}

pub struct LoopbackHttpTransport { config: LoopbackHttpConfig }
impl LoopbackHttpTransport {
    pub fn new(config: LoopbackHttpConfig) -> Result<Self> {
        if !config.address.ip().is_loopback() || config.address.port() == 0
            || config.idle_timeout.is_zero() || config.total_timeout.is_zero()
            || config.total_timeout > Duration::from_secs(30)
            || config.idle_timeout > config.total_timeout
            || config.max_response_bytes == 0 || config.max_response_bytes > 73728 {
            return Err("http_loopback_config".into());
        }
        Ok(Self { config })
    }

    /// `review` must recheck current authority for these exact body bytes.
    /// Caller owns durable admission/accounting; this transport never retries.
    pub fn exchange(&mut self, payload: &[u8], control: &mut dyn ProviderControl,
        review: &mut dyn FnMut(&[u8]) -> Result<()>) -> Result<Vec<u8>> {
        control.poll()?;
        if payload.is_empty() || payload.len() > 65536 { return Err("http_request_limit".into()); }
        let mut request = format!("POST /v1/chat/completions HTTP/1.1\r\nHost: {}\r\nContent-Type: application/json\r\nAccept: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            self.config.address, payload.len()).into_bytes();
        request.extend_from_slice(payload);
        if request.len() as u64 > control.remaining() { return Err("wire_total_limit".into()); }
        let start = Instant::now();
        review(payload)?;
        // One bounded connection attempt, to a numeric loopback address only.
        let mut socket = TcpStream::connect_timeout(&self.config.address,
            self.config.total_timeout.min(Duration::from_millis(50)))
            .map_err(|_| "http_connect")?;
        socket.set_nonblocking(true).map_err(|_| "http_socket_setup")?;
        let mut active = start;
        let mut written = 0;
        let mut response = Vec::new();
        let mut framing: Option<(usize, Option<usize>)> = None;
        let mut buffer = [0; 4096];
        loop {
            control.poll()?;
            review(payload)?;
            if start.elapsed() >= self.config.total_timeout { return Err("http_total_timeout".into()); }
            if active.elapsed() >= self.config.idle_timeout { return Err("http_idle_timeout".into()); }
            let mut progress = false;
            if written < request.len() {
                let cap = (request.len() - written).min(4096)
                    .min(usize::try_from(control.remaining()).unwrap_or(usize::MAX));
                if cap == 0 { return Err("wire_total_limit".into()); }
                match socket.write(&request[written..written + cap]) {
                    Ok(0) => return Err("http_write_closed".into()),
                    Ok(n) => { control.charge(true, n)?; written += n; progress = true; },
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {},
                    Err(_) => return Err("http_write".into()),
                }
                // Re-enter the control/review boundary before any other I/O.
                if progress { active = Instant::now(); }
                else { std::thread::sleep(Duration::from_millis(1)); }
                continue;
            }
            if let Some((offset, Some(length))) = framing {
                if response.len() >= offset + length {
                    if response.len() != offset + length { return Err("http_response_framing".into()); }
                    return Ok(response[offset..].to_vec());
                }
            }
            let cap = buffer.len().min(self.config.max_response_bytes - response.len())
                .min(usize::try_from(control.remaining()).unwrap_or(usize::MAX));
            let eof = if cap == 0 {
                // Peek consumes no additional bytes at an exact budget boundary.
                match socket.peek(&mut buffer[..1]) {
                    Ok(0) => true,
                    Ok(_) => return Err(if response.len() == self.config.max_response_bytes {
                        "http_response_limit" } else { "wire_total_limit" }.into()),
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => false,
                    Err(_) => return Err("http_read".into()),
                }
            } else {
                match socket.read(&mut buffer[..cap]) {
                    Ok(0) => true,
                    Ok(n) => {
                        control.charge(false, n)?;
                        response.extend_from_slice(&buffer[..n]);
                        progress = true;
                        if framing.is_none() { framing = parse_header(&response, self.config.max_response_bytes)?; }
                        false
                    },
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => false,
                    Err(_) => return Err("http_read".into()),
                }
            };
            if eof {
                return match framing {
                    Some((offset, length)) if length.is_none_or(|n| response.len() == offset + n) => Ok(response[offset..].to_vec()),
                    _ => Err("http_response_truncated".into()),
                };
            }
            if progress { active = Instant::now(); }
            else { std::thread::sleep(Duration::from_millis(1)); }
        }
    }
}

/// The synthetic contract supports Content-Length or connection-close framing.
/// Chunked transfer, redirects, upgrades and ambiguous headers are rejected.
fn parse_header(bytes: &[u8], max_response: usize) -> Result<Option<(usize, Option<usize>)>> {
    let Some(end) = bytes.windows(4).position(|v| v == b"\r\n\r\n") else {
        if bytes.len() >= 8192 { return Err("http_header_limit".into()); }
        return Ok(None);
    };
    let offset = end + 4;
    if offset > 8192 { return Err("http_header_limit".into()); }
    let header = std::str::from_utf8(&bytes[..end]).map_err(|_| "http_header")?;
    let mut lines = header.split("\r\n");
    let mut status = lines.next().ok_or("http_status")?.splitn(3, ' ');
    if !matches!(status.next(), Some("HTTP/1.0" | "HTTP/1.1")) || status.next() != Some("200") {
        return Err("http_status".into());
    }
    let mut length = None;
    let mut content_type = false;
    for line in lines {
        let (name, value) = line.split_once(':').ok_or("http_header")?;
        if name.is_empty() || !name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
            || value.bytes().any(|b| b.is_ascii_control() || !b.is_ascii()) { return Err("http_header".into()); }
        let value = value.trim();
        match name.to_ascii_lowercase().as_str() {
            "content-length" => {
                if length.is_some() || value.is_empty() || !value.bytes().all(|b| b.is_ascii_digit()) {
                    return Err("http_response_framing".into());
                }
                let n: usize = value.parse().map_err(|_| "http_response_limit")?;
                if n > max_response.saturating_sub(offset) { return Err("http_response_limit".into()); }
                length = Some(n);
            },
            "content-type" => {
                if content_type || !value.split(';').next().unwrap_or("").trim().eq_ignore_ascii_case("text/event-stream") {
                    return Err("http_content_type".into());
                }
                content_type = true;
            },
            "transfer-encoding" | "upgrade" => return Err("http_response_framing".into()),
            _ => {},
        }
    }
    if !content_type { return Err("http_content_type".into()); }
    Ok(Some((offset, length)))
}
