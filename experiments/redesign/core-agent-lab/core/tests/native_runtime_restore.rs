use muyon_core_agent_lab::{agent::{Agent, Limits, State}, model::NativeMessage, store};
use std::{path::PathBuf, sync::atomic::{AtomicUsize, Ordering}};
static NEXT: AtomicUsize = AtomicUsize::new(0);
fn directory() -> PathBuf {
    let dir = std::env::temp_dir().join(format!("muyon-runtime-restore-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
    store::create_dir(&dir).unwrap(); dir
}
fn runtime() -> State {
    let mut state = State::runtime("question".into(), "scope".into(), Limits::default()).unwrap();
    state.wire_counters.sent = 8; state.wire_counters.received = 13;
    state.counters.total = 29; state.status = "outcome_unknown".into(); state.reason = "model_ledger_failed".into();
    state
}
fn rejects(encoded: &str) {
    let dir = directory(); store::atomic(&dir, "task.db", encoded).unwrap();
    assert!(State::load(&dir).is_err(), "invalid host state must fail closed");
}
#[test]
fn native_host_metered_terminal_reopens_with_original_identity_and_counters() {
    let dir = directory(); let state = runtime(); state.save(&dir).unwrap();
    let opened = Agent::open(&dir).unwrap();
    assert_eq!(opened.state.status, "outcome_unknown"); assert_eq!(opened.state.reason, "model_ledger_failed");
    assert_eq!(opened.state.task, state.task); assert_eq!(opened.state.attempt, state.attempt);
    assert_eq!(opened.state.wire_counters.sent, 8); assert_eq!(opened.state.wire_counters.received, 13);
}
#[test]
fn native_host_discriminator_rejects_script_config_history_and_pending_call() {
    let state = runtime();
    // Each candidate has the host marker but violates a distinct closed shape.
    let mut script = state.clone(); script.script = "answer nope".into(); rejects(&script.encode());
    rejects(&state.encode().replace("wire_config_hex\t\n", "wire_config_hex\t61\n"));
    let mut history = state.clone(); history.native.push(NativeMessage::User("forged".into())); rejects(&history.encode());
    let mut pending = state.clone(); pending.pending_call_ref = "forged".into(); rejects(&pending.encode());
    rejects(&state.encode().replace("provider\tnative-host\n", "provider\tscript\n"));
    rejects(&state.encode().replace("provider\tnative-host\n", "provider\tunknown-host\n"));
}
#[test]
fn native_host_discriminator_rejects_unaccounted_or_over_budget_wire_bytes() {
    let mut state = runtime(); state.counters.total = 20; rejects(&state.encode());
    state.counters.total = state.limits.total + 1; state.wire_counters.sent = state.limits.total; state.wire_counters.received = 1;
    rejects(&state.encode());
    rejects(&runtime().encode().replace("wire_total_bytes\t21\n", "wire_total_bytes\t20\n"));
}
