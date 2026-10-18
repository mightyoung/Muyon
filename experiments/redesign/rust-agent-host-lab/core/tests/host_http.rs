//! Numeric loopback fixtures only; no plugin enrollment or real provider.
use muyon_core_agent_lab::{agent::{Agent, Hooks, Limits, State}, http_transport::LoopbackHttpConfig, Result};
use muyon_plugin_contract_lab::{parse, Json};
use muyon_rust_agent_host_lab::{model_gateway::{LoopbackEndpoint, ModelGateway}, *};
use std::{io::{Read, Write}, net::{TcpListener, TcpStream}, path::PathBuf, rc::Rc,
    sync::{Arc, atomic::{AtomicBool, AtomicUsize, Ordering}}, thread, time::Duration};
static SERIAL: AtomicUsize = AtomicUsize::new(0);
struct Authority(Arc<AtomicBool>);
impl AuthoritySource for Authority {
    fn snapshot(&self) -> Result<AuthoritySnapshot> {
        Ok(AuthoritySnapshot { read: parse(b"{}").unwrap(), model_allowed: !self.0.load(Ordering::SeqCst), profile: "offline-fixture".into() })
    }
}
struct Review(Arc<AtomicBool>);
impl PurposeReview for Review {
    fn review(&self, _: &Json, _: &Json, _: &str) -> Result<()> {
        if self.0.load(Ordering::SeqCst) { Err("native_cancelled".into()) } else { Ok(()) }
    }
    fn mask_answer(&self, text: &str) -> Result<String> { Ok(text.replace("SECRET", "[redacted]")) }
}
fn setup(revoked: Arc<AtomicBool>, cancelled: Arc<AtomicBool>) -> (SharedSession, Agent) {
    let dir = std::env::temp_dir().join(format!("muyon-host-http-{}-{}", std::process::id(), SERIAL.fetch_add(1, Ordering::SeqCst)));
    let plugin = PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").expect("real plugin child binary"));
    let session = NativeSession::create(&dir, &plugin, Rc::new(Authority(revoked)), Rc::new(Review(cancelled)), "synthetic question").unwrap();
    let agent = Agent { dir, state: State::runtime("synthetic question".into(), "synthetic-scope".into(), Limits::default()).unwrap() };
    (session, agent)
}
fn read_request(socket: &mut TcpStream) -> Vec<u8> {
    socket.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
    let mut data = Vec::new();
    let mut byte = [0];
    loop {
        if socket.read(&mut byte).unwrap_or(0) == 0 { return data; }
        data.push(byte[0]);
        if let Some(end) = data.windows(4).position(|w| w == b"\r\n\r\n") {
            let header = std::str::from_utf8(&data[..end]).unwrap();
            let length: usize = header.lines().find_map(|s| s.strip_prefix("Content-Length: ")).unwrap().parse().unwrap();
            if data.len() == end + 4 + length { return data; }
        }
    }
}
fn gateway(session: &SharedSession, listener: &TcpListener) -> ModelGateway {
    let endpoint = LoopbackEndpoint::new(session.clone(), LoopbackHttpConfig { address: listener.local_addr().unwrap(), idle_timeout: Duration::from_millis(500), total_timeout: Duration::from_secs(2), max_response_bytes: 73728 }).unwrap();
    ModelGateway::new(session.clone(), Box::new(endpoint))
}
fn drive(agent: &mut Agent, gateway: &mut ModelGateway, session: &SharedSession) {
    agent.run_with_runtime_ports(gateway, &mut RuntimePorts { session: session.clone() }, &Hooks::default()).unwrap();
}
fn flags() -> (Arc<AtomicBool>, Arc<AtomicBool>) { (Arc::new(AtomicBool::new(false)), Arc::new(AtomicBool::new(false))) }
const SSE: &str = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"SECRET complete\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n";
#[test]
fn loopback_answer_uses_gateway_review_and_shared_durable_budget() {
    let (revoked, cancelled) = flags(); let (session, mut agent) = setup(revoked, cancelled);
    let listener = TcpListener::bind("127.0.0.1:0").unwrap(); let mut gateway = gateway(&session, &listener);
    let server = thread::spawn(move || { let (mut socket, _) = listener.accept().unwrap(); let request = read_request(&mut socket); let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\n\r\n{}", SSE.len(), SSE); socket.write_all(response.as_bytes()).unwrap(); (request, response.len()) });
    drive(&mut agent, &mut gateway, &session); let (request, received) = server.join().unwrap();
    assert_eq!(Agent::open(&agent.dir).unwrap().state.status, "completed");
    assert_eq!(agent.state.status, "completed"); assert_eq!(agent.state.answer, "[redacted] complete");
    assert_eq!(agent.state.wire_counters.sent, request.len() as u64); assert_eq!(agent.state.wire_counters.received, received as u64);
    assert_eq!(agent.state.counters.total, "synthetic question".len() as u64 + request.len() as u64 + received as u64 + agent.state.answer.len() as u64);
    let persisted = std::fs::read_to_string(agent.dir.join("task.db")).unwrap(); assert!(persisted.contains(&format!("wire_sent_bytes\t{}\n", request.len()))); assert!(persisted.contains("provider_inflight\tfalse\n"));
    let ledger = std::fs::read_to_string(agent.dir.join("outbound.db")).unwrap(); assert!(ledger.contains("sent"));
}
#[test]
fn loopback_truncation_cancellation_and_revocation_never_resend() {
    for mode in ["truncated", "cancelled", "revoked"] {
        let (revoked, cancelled) = flags(); let (session, mut agent) = setup(revoked.clone(), cancelled.clone());
        let listener = TcpListener::bind("127.0.0.1:0").unwrap(); let mut gateway = gateway(&session, &listener);
        let server = thread::spawn(move || { let (mut socket, _) = listener.accept().unwrap(); let request = read_request(&mut socket); assert!(!request.is_empty()); match mode { "cancelled" => cancelled.store(true, Ordering::SeqCst), "revoked" => revoked.store(true, Ordering::SeqCst), _ => { socket.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: 999\r\n\r\ndata: ").unwrap(); } } thread::sleep(Duration::from_millis(30)); listener });
        drive(&mut agent, &mut gateway, &session); let listener = server.join().unwrap();
        assert_ne!(agent.state.status, "completed", "{mode}"); assert!(agent.state.wire_counters.sent > 0, "{mode}");
        let sent = agent.state.wire_counters.sent; drive(&mut agent, &mut gateway, &session); assert_eq!(agent.state.wire_counters.sent, sent);
        listener.set_nonblocking(true).unwrap(); assert!(listener.accept().is_err(), "{mode}: second connection");
        assert!(std::fs::read_to_string(agent.dir.join("outbound.db")).unwrap().contains("failed"));
    }
}
#[test]
fn loopback_budget_and_initial_authority_refuse_before_socket_bytes() {
    for revoke in [false, true] {
        let (revoked, cancelled) = flags(); revoked.store(revoke, Ordering::SeqCst); let (session, mut agent) = setup(revoked, cancelled);
        if !revoke { agent.state.limits.total = 32; }
        let listener = TcpListener::bind("127.0.0.1:0").unwrap(); let mut gateway = gateway(&session, &listener);
        drive(&mut agent, &mut gateway, &session); assert_ne!(agent.state.status, "completed"); assert_eq!(agent.state.wire_counters.sent, 0);
        listener.set_nonblocking(true).unwrap(); assert!(listener.accept().is_err());
    }
}
#[test]
fn loopback_unknown_inflight_crash_blocks_same_state_retry() {
    use muyon_core_agent_lab::model::ProviderControl;
    use muyon_rust_agent_host_lab::model_gateway::OfflineEndpoint;
    struct CrashAfterExchange(LoopbackEndpoint);
    impl OfflineEndpoint for CrashAfterExchange {
        fn exchange(&mut self, payload: &[u8], control: &mut dyn ProviderControl) -> Result<Vec<u8>> {
            let response = self.0.exchange(payload, control)?;
            assert!(!response.is_empty());
            panic!("synthetic crash after provider received request, before gateway completion")
        }
    }
    let (revoked, cancelled) = flags(); let (session, mut agent) = setup(revoked, cancelled);
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = LoopbackEndpoint::new(session.clone(), LoopbackHttpConfig { address: listener.local_addr().unwrap(), idle_timeout: Duration::from_millis(500), total_timeout: Duration::from_secs(2), max_response_bytes: 73728 }).unwrap();
    let mut gateway = ModelGateway::new(session.clone(), Box::new(CrashAfterExchange(endpoint)));
    let server = thread::spawn(move || { let (mut socket, _) = listener.accept().unwrap(); let request = read_request(&mut socket); assert!(!request.is_empty()); let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\n\r\n{}", SSE.len(), SSE); socket.write_all(response.as_bytes()).unwrap(); listener });
    let crash = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| drive(&mut agent, &mut gateway, &session)));
    let listener = server.join().unwrap(); assert!(crash.is_err()); assert!(agent.state.wire_counters.inflight);
    let persisted = std::fs::read_to_string(agent.dir.join("task.db")).unwrap(); assert!(persisted.contains("provider_inflight\ttrue\n"));
    let sent = agent.state.wire_counters.sent; drive(&mut agent, &mut gateway, &session);
    assert_eq!(agent.state.status, "outcome_unknown"); assert_eq!(agent.state.reason, "wire_interrupted"); assert_eq!(agent.state.wire_counters.sent, sent);
    listener.set_nonblocking(true).unwrap(); assert!(listener.accept().is_err());
    let ledger = std::fs::read_to_string(agent.dir.join("outbound.db")).unwrap(); assert!(ledger.contains("begin")); assert!(!ledger.contains("sent")); assert!(!ledger.contains("failed"));
}
#[test]
fn loopback_receive_budget_stops_partial_response_without_retry() {
    let (revoked, cancelled) = flags(); let (session, mut agent) = setup(revoked, cancelled);
    agent.state.limits.total = 1024;
    let listener = TcpListener::bind("127.0.0.1:0").unwrap(); let mut gateway = gateway(&session, &listener);
    let server = thread::spawn(move || {
        let (mut socket, _) = listener.accept().unwrap(); let request = read_request(&mut socket); assert!(!request.is_empty());
        let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: 2000\r\n\r\n{}", "x".repeat(2000));
        let _ = socket.write_all(response.as_bytes()); listener
    });
    drive(&mut agent, &mut gateway, &session); let listener = server.join().unwrap();
    assert_ne!(agent.state.status, "completed"); assert!(agent.state.wire_counters.sent > 0); assert!(agent.state.wire_counters.received > 0);
    assert_eq!(agent.state.counters.total, agent.state.limits.total);
    assert_eq!(agent.state.status, "budget_exhausted");
    assert_eq!(agent.state.reason, "host_budget");
    let sent = agent.state.wire_counters.sent; drive(&mut agent, &mut gateway, &session); assert_eq!(agent.state.wire_counters.sent, sent);
    listener.set_nonblocking(true).unwrap(); assert!(listener.accept().is_err());
    assert!(std::fs::read_to_string(agent.dir.join("outbound.db")).unwrap().contains("failed"));
}
#[test]
fn loopback_mismatched_session_refuses_before_ledger_or_connection() {
    let (revoked_a, cancelled_a) = flags();
    let (session_a, mut agent) = setup(revoked_a, cancelled_a);
    let (revoked_b, cancelled_b) = flags();
    let (session_b, _) = setup(revoked_b, cancelled_b);
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = LoopbackEndpoint::new(session_b, LoopbackHttpConfig {
        address: listener.local_addr().unwrap(), idle_timeout: Duration::from_millis(20),
        total_timeout: Duration::from_millis(50), max_response_bytes: 73728,
    }).unwrap();
    let mut gateway = ModelGateway::new(session_a.clone(), Box::new(endpoint));
    drive(&mut agent, &mut gateway, &session_a);
    listener.set_nonblocking(true).unwrap();
    assert!(listener.accept().is_err(), "mismatched session must never connect");
    assert_eq!(agent.state.wire_counters.sent, 0);
    assert_eq!(agent.state.wire_counters.received, 0);
    assert_eq!(session_a.borrow().model_sends, 0);
    assert!(!agent.dir.join("outbound.db").exists());
}
