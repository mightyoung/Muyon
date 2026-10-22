use muyon_core_agent_lab::{http_transport::{LoopbackHttpConfig, LoopbackHttpTransport},
    agent::{Agent, State, Limits, Hooks}, model::{Provider, ProviderControl, ModelEvent, ModelRequest, NativeMessage}, wire_sse::Decoder, Result};
use std::{io::{Read, Write}, net::{TcpListener, SocketAddr}, sync::{Arc,
    atomic::{AtomicBool, AtomicUsize, Ordering}, Mutex}, thread, time::Duration};

struct Server {
    address: SocketAddr,
    accepted: Arc<AtomicUsize>,
    requests: Arc<Mutex<Vec<Vec<u8>>>>,
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
        let requests = Arc::new(Mutex::new(Vec::new()));
        let captured = requests.clone();
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
                        captured.lock().unwrap().push(request);
                        if response.is_empty() {
                            while !done.load(Ordering::SeqCst) { thread::yield_now(); }
                        } else { let _ = socket.write_all(&response); }
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => thread::yield_now(),
                    Err(e) => panic!("synthetic listener: {e}"),
                }
            }
        });
        Self { address, accepted, requests, stop, worker: Some(worker) }
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
struct Control { remaining: u64, sent: usize, received: usize, cancelled: bool, cancel_after_send: bool }
impl Default for Control {
    fn default() -> Self { Self { remaining: 200000, sent: 0, received: 0, cancelled: false, cancel_after_send: false } }
}
impl ProviderControl for Control {
    fn poll(&mut self) -> Result<()> { if self.cancelled || self.cancel_after_send && self.sent > 0 { Err("wire_cancelled".into()) } else { Ok(()) } }
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
    let requests = server.requests.lock().unwrap();
    assert_eq!(requests.len(), 1);
    let request = &requests[0];
    let offset = request.windows(4).position(|v| v == b"\r\n\r\n").unwrap() + 4;
    assert_eq!(&request[offset..], b"{\"synthetic\":true}");
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

#[test]
fn cancellation_and_revocation_after_send_stop_before_response_admission() {
    let server = Server::start(response(ANSWER));
    let mut control = Control { cancel_after_send: true, ..Control::default() };
    assert_eq!(server.transport().exchange(b"{}", &mut control, &mut |_| Ok(())).unwrap_err(), "wire_cancelled");
    assert!(control.sent > 0); assert_eq!(control.received, 0);
    let mut control = Control::default();
    let mut reviews = 0;
    assert_eq!(server.transport().exchange(b"{}", &mut control, &mut |_| {
        reviews += 1;
        if reviews >= 3 { Err("projection_revoked".into()) } else { Ok(()) }
    }).unwrap_err(), "projection_revoked");
    assert!(control.sent > 0); assert_eq!(control.received, 0);
}

#[test]
fn response_budget_exhaustion_counts_actual_bytes_without_retry() {
    let server = Server::start(response(ANSWER));
    let mut measured = Control::default();
    server.transport().exchange(b"{}", &mut measured, &mut |_| Ok(())).unwrap();
    let mut limited = Control { remaining: measured.sent as u64 + 1, ..Control::default() };
    assert_eq!(server.transport().exchange(b"{}", &mut limited, &mut |_| Ok(())).unwrap_err(), "wire_total_limit");
    assert_eq!(limited.remaining, 0); assert_eq!(limited.received, 1);
    assert_eq!(limited.sent, measured.sent);
    assert_eq!(server.accepted.load(Ordering::SeqCst), 2);
}

#[test]
fn idle_and_total_deadlines_bound_an_open_synthetic_stream() {
    for total in [false, true] {
        let server = Server::start(Vec::new());
        let mut transport = LoopbackHttpTransport::new(LoopbackHttpConfig {
            address: server.address, idle_timeout: Duration::from_millis(25),
            total_timeout: Duration::from_millis(if total { 25 } else { 250 }), max_response_bytes: 73728,
        }).unwrap();
        let error = transport.exchange(b"{}", &mut Control::default(), &mut |_| Ok(())).unwrap_err();
        assert_eq!(error, if total { "http_total_timeout" } else { "http_idle_timeout" });
        assert_eq!(server.accepted.load(Ordering::SeqCst), 1);
    }
}

#[test]
fn ambiguous_framing_redirect_and_response_limit_are_rejected() {
    for (raw, expected) in [
        (b"HTTP/1.1 302 Found\r\nContent-Type: text/event-stream\r\nContent-Length: 0\r\n\r\n".as_slice(), "http_status"),
        (b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n".as_slice(), "http_response_framing"),
        (b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n".as_slice(), "http_response_framing"),
        (b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: 90000\r\n\r\n".as_slice(), "http_response_limit"),
    ] {
        let server = Server::start(raw.to_vec());
        assert_eq!(server.transport().exchange(b"{}", &mut Control::default(), &mut |_| Ok(())).unwrap_err(), expected);
        assert_eq!(server.accepted.load(Ordering::SeqCst), 1);
    }
}

struct HttpProvider { transport: LoopbackHttpTransport, calls: usize }
impl Provider for HttpProvider {
    fn respond(&mut self, _: &ModelRequest, _: usize) -> Result<ModelEvent> { Err("control_required".into()) }
    fn respond_controlled(&mut self, _: &ModelRequest, _: usize, _: &[NativeMessage], control: &mut dyn ProviderControl) -> Result<ModelEvent> {
        self.calls += 1;
        let body = self.transport.exchange(b"{}", control, &mut |_| Ok(()))?;
        let mut decoder = Decoder::new();
        for byte in body { decoder.feed(byte)?; }
        Ok(decoder.finish()?.event)
    }
}

#[test]
fn existing_agent_unknown_and_evidence_hold_never_enter_http_provider() {
    let server = Server::start(response(ANSWER));
    for evidence_hold in [false, true] {
        let mut state = State::runtime("synthetic".into(), "scope".into(), Limits::default()).unwrap();
        state.status = "outcome_unknown".into();
        state.unresolved = !evidence_hold; state.evidence_hold = evidence_hold;
        let before = state.context.clone();
        let mut agent = Agent { dir: std::env::temp_dir().join("core-http-unknown-must-not-write"), state };
        let mut provider = HttpProvider { transport: server.transport(), calls: 0 };
        agent.run_with_provider(&mut provider, &Hooks::default()).unwrap();
        assert_eq!(provider.calls, 0); assert_eq!(agent.state.counters.calls, 0);
        assert_eq!(agent.state.status, "outcome_unknown"); assert_eq!(agent.state.context, before);
    }
    assert_eq!(server.accepted.load(Ordering::SeqCst), 0);
}
