//! Real loopback IO and fresh test processes; no production fault hooks or providers.
use super::*;
use crate::model_gateway::{LoopbackEndpoint, ModelGateway, OfflineEndpoint};
use muyon_core_agent_lab::{
    agent::{Hooks, Limits}, http_transport::LoopbackHttpConfig, model::ProviderControl, store,
};
use std::{io::{Read, Write}, net::{SocketAddr, TcpListener, TcpStream}, path::PathBuf,
    process::Command, sync::atomic::{AtomicUsize, Ordering}, thread, time::{Duration, Instant}};
static NEXT: AtomicUsize = AtomicUsize::new(0);
const SSE: &str = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"complete\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n";
struct Authority;
impl AuthoritySource for Authority {
    fn snapshot(&self) -> Result<AuthoritySnapshot> {
        Ok(AuthoritySnapshot { read: Json::Object(BTreeMap::new()), model_allowed: true, profile: "offline-fixture".into() })
    }
}
struct Review;
impl PurposeReview for Review {
    fn review(&self, _: &Json, _: &Json, _: &str) -> Result<()> { Ok(()) }
    fn mask_answer(&self, text: &str) -> Result<String> { Ok(text.into()) }
}
fn directory() -> PathBuf {
    let dir = std::env::temp_dir().join(format!("muyon-http-recovery-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
    store::create_dir(&dir).unwrap();
    dir
}
fn session(native: NativeStore) -> SharedSession {
    NativeSession::from_parts(native, Box::new(InProcessCatalog::new()), Rc::new(Authority), Rc::new(Review), "synthetic question")
}
fn endpoint(session: &SharedSession, address: SocketAddr) -> LoopbackEndpoint {
    LoopbackEndpoint::new(session.clone(), LoopbackHttpConfig {
        address, idle_timeout: Duration::from_millis(500), total_timeout: Duration::from_secs(2), max_response_bytes: 73728,
    }).unwrap()
}
fn drive(agent: &mut Agent, provider: &mut ModelGateway, session: &SharedSession) {
    agent.run_with_runtime_ports(provider, &mut RuntimePorts { session: session.clone() }, &Hooks::default()).unwrap();
}
fn ledger(dir: &Path) -> Vec<u8> {
    let bytes = std::fs::read(dir.join("outbound.db")).unwrap();
    let value = muyon_plugin_contract_lab::parse(&bytes).unwrap();
    assert_eq!(field(&value, "status").unwrap(), &string("begin"));
    bytes
}
fn read_request(socket: &mut TcpStream) -> Vec<u8> {
    socket.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
    let mut bytes = Vec::new();
    loop {
        let mut byte = [0];
        assert_eq!(socket.read(&mut byte).unwrap(), 1, "complete request must reach server");
        bytes.push(byte[0]);
        if let Some(end) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
            let head = std::str::from_utf8(&bytes[..end]).unwrap();
            let len: usize = head.lines().find_map(|l| l.strip_prefix("Content-Length: ")).unwrap().parse().unwrap();
            if bytes.len() == end + 4 + len { return bytes; }
        }
    }
}
fn serve_once(listener: TcpListener) -> thread::JoinHandle<(TcpListener, usize, usize)> {
    listener.set_nonblocking(true).unwrap();
    thread::spawn(move || {
        let deadline = Instant::now() + Duration::from_secs(5);
        let mut socket = loop {
            match listener.accept() {
                Ok((socket, _)) => break socket,
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock && Instant::now() < deadline => thread::sleep(Duration::from_millis(2)),
                result => panic!("first real connection required: {result:?}"),
            }
        };
        socket.set_nonblocking(false).unwrap();
        let request = read_request(&mut socket);
        let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\n\r\n{}", SSE.len(), SSE);
        socket.write_all(response.as_bytes()).unwrap();
        (listener, request.len(), response.len())
    })
}
struct AfterIo {
    inner: LoopbackEndpoint,
    dir: PathBuf,
    mode: String,
}
impl OfflineEndpoint for AfterIo {
    fn validate_session(&self, session: &SharedSession) -> Result<()> { self.inner.validate_session(session) }
    fn exchange(&mut self, payload: &[u8], control: &mut dyn ProviderControl) -> Result<Vec<u8>> {
        let response = self.inner.exchange(payload, control)?;
        assert!(!response.is_empty());
        if self.mode == "crash" { std::process::exit(73); }
        let name = if self.mode == "journal" { "task.db" } else { "outbound.db" };
        let target = self.dir.join(name);
        let original = self.dir.join(format!("{name}.before-failure"));
        // Preserve every original byte; an actual invalid filesystem target makes
        // store::atomic fail, independently of permissions or the executing uid.
        std::fs::rename(&target, &original).unwrap();
        std::fs::create_dir(&target).unwrap();
        if self.mode == "journal" {
            let error = control.checkpoint("post_io_journal").unwrap_err();
            assert_eq!(error, "wire_journal");
            std::fs::remove_dir(&target).unwrap();
            std::fs::rename(&original, &target).unwrap();
            Err(error)
        } else if self.mode == "failed_ledger" {
            // Failed durable completion takes precedence over this late stop.
            store::atomic(&self.dir, "cancel.request", "CORE_CANCEL_V1\n").unwrap();
            assert_eq!(control.poll().unwrap_err(), "wire_cancelled");
            Err("wire_cancelled".into())
        } else { Ok(response) }
    }
}
fn child(dir: &Path, address: SocketAddr, mode: &str) -> std::process::Output {
    Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "http_recovery_tests::http_recovery_child", "--nocapture"])
        .env("MUYON_HTTP_RECOVERY_DIR", dir).env("MUYON_HTTP_RECOVERY_ADDRESS", address.to_string())
        .env("MUYON_HTTP_RECOVERY_MODE", mode).output().unwrap()
}
#[test]
fn http_recovery_child() {
    let Some(dir) = std::env::var_os("MUYON_HTTP_RECOVERY_DIR") else { return; };
    let dir = PathBuf::from(dir);
    let address: SocketAddr = std::env::var("MUYON_HTTP_RECOVERY_ADDRESS").unwrap().parse().unwrap();
    let mode = std::env::var("MUYON_HTTP_RECOVERY_MODE").unwrap();
    println!("http_recovery_child pid={} mode={} dir={}", std::process::id(), mode, dir.display());
    if mode.starts_with("recover_") {
        let before = ledger(&dir);
        let mut agent = Agent::open(&dir).unwrap();
        let expected = if mode == "recover_crash" { ("outcome_unknown", "wire_interrupted") } else { ("outcome_unknown", "model_ledger_failed") };
        assert_eq!((agent.state.status.as_str(), agent.state.reason.as_str()), expected);
        let sent = agent.state.wire_counters.sent;
        let received = agent.state.wire_counters.received;
        assert!(sent > 0 && received > 0);
        let original = std::fs::read_to_string(dir.join("original-identity")).unwrap();
        assert_eq!(format!("{}\n{}\n", agent.state.task, agent.state.attempt), original);
        let session = session(NativeStore::open(&dir).unwrap());
        let mut provider = ModelGateway::new(session.clone(), Box::new(endpoint(&session, address)));
        drive(&mut agent, &mut provider, &session);
        assert_eq!((agent.state.status.as_str(), agent.state.reason.as_str()), expected);
        assert_eq!(agent.state.wire_counters.sent, sent);
        assert_eq!(agent.state.wire_counters.received, received);
        assert_eq!(format!("{}\n{}\n", agent.state.task, agent.state.attempt), original);
        drive(&mut agent, &mut provider, &session);
        let reopened = Agent::open(&dir).unwrap();
        assert_eq!((reopened.state.status.as_str(), reopened.state.reason.as_str()), expected);
        assert_eq!(format!("{}\n{}\n", reopened.state.task, reopened.state.attempt), original);
        assert_eq!(session.borrow().model_sends, 0);
        assert_eq!(ledger(&dir), before, "unknown begin evidence must remain byte-identical");
        return;
    }
    let session = session(NativeStore::initialize_private(&dir).unwrap());
    let mut agent = Agent { dir: dir.clone(), state: State::runtime("synthetic question".into(), "synthetic-scope".into(), Limits::default()).unwrap() };
    store::atomic(&dir, "original-identity", &format!("{}\n{}\n", agent.state.task, agent.state.attempt)).unwrap();
    let inner = endpoint(&session, address);
    let mut provider = ModelGateway::new(session.clone(), Box::new(AfterIo { inner, dir: dir.clone(), mode }));
    drive(&mut agent, &mut provider, &session);
    assert_eq!(agent.state.status, "outcome_unknown");
    assert_eq!(agent.state.reason, "model_ledger_failed");
    assert!(agent.state.wire_counters.sent > 0 && agent.state.wire_counters.received > 0);
    assert!(agent.state.answer.is_empty(), "no success may escape failed ledger completion");
}
fn cross_process(mode: &str) {
    let dir = directory();
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let server = serve_once(listener);
    let output = child(&dir, address, mode);
    let (listener, sent, received) = server.join().unwrap();
    if mode == "crash" { assert_eq!(output.status.code(), Some(73)); }
    else {
        // Restore the exact begin ledger after checking completion really failed.
        assert!(dir.join("outbound.db").is_dir());
        std::fs::remove_dir(dir.join("outbound.db")).unwrap();
        std::fs::rename(dir.join("outbound.db.before-failure"), dir.join("outbound.db")).unwrap();
        assert!(output.status.success(), "{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
    }
    let before = ledger(&dir);
    let state = State::load(&dir).unwrap();
    assert_eq!(format!("{}\n{}\n", state.task, state.attempt), std::fs::read_to_string(dir.join("original-identity")).unwrap());
    assert_eq!(state.wire_counters.sent, sent as u64);
    assert_eq!(state.wire_counters.received, received as u64);
    assert_eq!(state.wire_counters.inflight, mode == "crash");
    let recovery = child(&dir, address, if mode == "crash" { "recover_crash" } else { "recover_ledger" });
    assert!(recovery.status.success(), "{}{}", String::from_utf8_lossy(&recovery.stdout), String::from_utf8_lossy(&recovery.stderr));
    assert_eq!(ledger(&dir), before);
    println!("{}{}evidence_dir={} mode={} sent={} received={} original_identity={:?}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&recovery.stdout), dir.display(), mode, sent, received, std::fs::read_to_string(dir.join("original-identity")).unwrap());
    assert_eq!(listener.accept().unwrap_err().kind(), std::io::ErrorKind::WouldBlock, "no automatic resend after new-process recovery");
}
#[test]
fn loopback_cross_process_crash_preserves_unknown_begin_without_resend() { cross_process("crash"); }
#[test]
fn loopback_post_io_sent_ledger_failure_recovers_unknown_without_resend() { cross_process("sent_ledger"); }
#[test]
fn loopback_post_io_failed_ledger_overrides_cancel_and_recovers_unknown_without_resend() { cross_process("failed_ledger"); }
#[test]
fn loopback_post_io_wire_journal_is_unknown_without_resend() {
    let dir = directory();
    let session = session(NativeStore::initialize_private(&dir).unwrap());
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap();
    let server = serve_once(listener);
    let inner = endpoint(&session, address);
    let mut provider = ModelGateway::new(session.clone(), Box::new(AfterIo { inner, dir: dir.clone(), mode: "journal".into() }));
    let mut agent = Agent { dir: dir.clone(), state: State::runtime("synthetic question".into(), "synthetic-scope".into(), Limits::default()).unwrap() };
    drive(&mut agent, &mut provider, &session);
    let (listener, sent, received) = server.join().unwrap();
    assert_eq!((agent.state.status.as_str(), agent.state.reason.as_str()), ("outcome_unknown", "wire_journal"));
    assert_eq!(agent.state.wire_counters.sent, sent as u64);
    assert_eq!(agent.state.wire_counters.received, received as u64);
    assert_eq!(State::load(&dir).unwrap().status, "outcome_unknown");
    drive(&mut agent, &mut provider, &session);
    assert_eq!(session.borrow().model_sends, 1);
    assert_eq!(listener.accept().unwrap_err().kind(), std::io::ErrorKind::WouldBlock);
}
