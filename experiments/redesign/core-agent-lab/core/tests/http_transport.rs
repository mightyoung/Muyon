use muyon_core_agent_lab::{http_transport::{LoopbackHttpConfig, LoopbackHttpTransport},
    model::{ProviderControl, ModelEvent}, wire_sse::Decoder, Result};
use std::{io::{Read, Write}, net::{TcpListener, SocketAddr}, sync::{Arc,
    atomic::{AtomicBool, AtomicUsize, Ordering}}, thread, time::{Duration, Instant}};

struct Server {
    address: SocketAddr,
    accepted: Arc<AtomicUsize>,
    stop: Arc<AtomicBool>,
    worker: Option<thread::JoinHandle<()>>,
}
impl Server {
    fn start(response: Vec<u8>) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let address = listener.local_addr().unwrap();
        let accepted = Arc::new(AtomicUsize::new(0));
        let stop = Arc::new(AtomicBool::new(false));
        let (seen, done) = (accepted.clone(), stop.clone());
        let worker = thread::spawn(move || {
            while !done.load(Ordering::SeqCst) {
                match listener.accept() {
                    Ok((mut socket, _)) => {
                        seen.fetch_add(1, Ordering::SeqCst);
                        socket.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
                        let mut request = Vec::new();
                        let mut buffer = [0; 2048];
                        loop {
                            match socket.read(&mut buffer) {
                                Ok(0) | Err(_) => break,
                                Ok(n) => request.extend_from_slice(&buffer[..n]),
                            }
                            if let Some(end) = request.windows(4).position(|v| v == b"\r\n\r\n") {
                                let header = std::str::from_utf8(&request[..end]).unwrap();
                                let size = header.lines().find_map(|l| l.strip_prefix("Content-Length: "))
                                    .unwrap().parse::<usize>().unwrap();
                                if request.len() >= end + 4 + size { break; }
                            }
                        }
                        let _ = socket.write_all(&response);
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => thread::yield_now(),
                    Err(e) => panic!("synthetic listener: {e}"),
                }
            }
        });
        Self { address, accepted, stop, worker: Some(worker) }
    }
    fn transport(&self) -> LoopbackHttpTransport {
        LoopbackHttpTransport::new(LoopbackHttpConfig { address: self.address,
            idle_timeout: Duration::from_secs(2), total_timeout: Duration::from_secs(4),
            max_response_bytes: 73728 }).unwrap()
    }
}
impl Drop for Server {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        self.worker.take().unwrap().join().unwrap();
    }
}
struct Control { remaining: u64, sent: usize, received: usize, cancelled: bool }
impl Default for Control {
    fn default() -> Self { Self { remaining: 200000, sent: 0, received: 0, cancelled: false } }
}
impl ProviderControl for Control {
    fn poll(&mut self) -> Result<()> { if self.cancelled { Err("wire_cancelled".into()) } else { Ok(()) } }
    fn remaining(&self) -> u64 { self.remaining }
    fn charge(&mut self, sent: bool, bytes: usize) -> Result<()> {
        if bytes as u64 > self.remaining { return Err("wire_total_limit".into()); }
        self.remaining -= bytes as u64;
        if sent { self.sent += bytes; } else { self.received += bytes; }
        Ok(())
    }
    fn checkpoint(&mut self, _: &str) -> Result<()> { Ok(()) }
}
fn response(body: &[u8]) -> Vec<u8> {
    let mut out = format!("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len()).into_bytes();
    out.extend_from_slice(body); out
}
const ANSWER: &[u8] = b"data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"synthetic\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n";

#[test]
fn actual_loopback_http_returns_sse_without_changing_exact_reviewed_payload() {
    let server = Server::start(response(ANSWER));
    let mut control = Control::default();
    let mut reviews = 0;
    let body = server.transport().exchange(b"{\"synthetic\":true}", &mut control, &mut |bytes| {
        assert_eq!(bytes, b"{\"synthetic\":true}"); reviews += 1; Ok(())
    }).unwrap_or_else(|e| panic!("HTTP_LOOPBACK_TRANSPORT_RED: {e}"));
    assert_eq!(body, ANSWER);
    assert!(reviews >= 3);
    assert!(control.sent > b"{\"synthetic\":true}".len());
    assert_eq!(control.received, response(ANSWER).len());
    assert_eq!(server.accepted.load(Ordering::SeqCst), 1);
    let mut decoder = Decoder::new();
    for byte in body { decoder.feed(byte).unwrap(); }
    assert_eq!(decoder.finish().unwrap().event, ModelEvent::Answer("synthetic".into()));
}

#[test]
fn remote_addresses_are_rejected_before_any_connection() {
    let config = LoopbackHttpConfig { address: "192.0.2.1:80".parse().unwrap(),
        idle_timeout: Duration::from_secs(1), total_timeout: Duration::from_secs(2),
        max_response_bytes: 1024 };
    assert!(matches!(LoopbackHttpTransport::new(config), Err(e) if e == "http_loopback_config"));
}

#[test]
fn cancellation_and_insufficient_budget_send_zero_bytes() {
    let server = Server::start(response(ANSWER));
    let mut cancelled = Control { cancelled: true, ..Control::default() };
    assert_eq!(server.transport().exchange(b"{}", &mut cancelled, &mut |_| Ok(())).unwrap_err(), "wire_cancelled");
    let mut limited = Control { remaining: 1, ..Control::default() };
    assert_eq!(server.transport().exchange(b"{}", &mut limited, &mut |_| Ok(())).unwrap_err(), "wire_total_limit");
    assert_eq!(cancelled.sent + limited.sent, 0);
    assert_eq!(server.accepted.load(Ordering::SeqCst), 0);
}

#[test]
fn final_review_after_connect_prevents_first_request_byte() {
    let server = Server::start(response(ANSWER));
    let mut control = Control::default();
    let mut reviews = 0;
    let error = server.transport().exchange(b"{}", &mut control, &mut |_| {
        reviews += 1;
        if reviews >= 2 { Err("projection_revoked".into()) } else { Ok(()) }
    }).unwrap_err();
    assert_eq!(error, "projection_revoked");
    assert_eq!(control.sent, 0);
}

#[test]
fn truncated_http_response_is_an_error_with_one_send_and_no_retry() {
    let mut partial = response(ANSWER);
    partial.truncate(partial.len() - 10);
    let server = Server::start(partial);
    let mut control = Control::default();
    assert_eq!(server.transport().exchange(b"{}", &mut control, &mut |_| Ok(())).unwrap_err(), "http_response_truncated");
    assert_eq!(server.accepted.load(Ordering::SeqCst), 1);
    assert!(control.sent > 0);
}

#[test]
fn partial_sse_never_becomes_a_tool_event() {
    let partial = b"data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"fixture__record\",\"arguments\":\"{\\\"value\\\":\\\"x\\\"}\"}}]}}]}\n\n";
    let server = Server::start(response(partial));
    let bytes = server.transport().exchange(b"{}", &mut Control::default(), &mut |_| Ok(())).unwrap();
    let mut decoder = Decoder::new();
    for byte in bytes { decoder.feed(byte).unwrap(); }
    assert_eq!(decoder.finish().unwrap_err(), "wire_stream_truncated");
    assert_eq!(server.accepted.load(Ordering::SeqCst), 1);
}
