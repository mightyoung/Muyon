use muyon_core_agent_lab::{authorize, Decision, Mode};
use std::{fs, process::Command, sync::atomic::{AtomicU64, Ordering}};
static NEXT: AtomicU64 = AtomicU64::new(0);
#[test]
fn full_allow_high_risk_needs_no_confirmation() {
    assert_eq!(authorize(Mode::FullAllow, true, false, true), Decision::Permit);
}
#[test]
fn auto_low_risk_is_permitted() {
    assert_eq!(authorize(Mode::Auto, false, false, true), Decision::Permit);
}
#[test]
fn read_only_and_hard_gates_deny() {
    assert_eq!(authorize(Mode::ReadOnly, false, true, true), Decision::Denied);
    assert_eq!(authorize(Mode::FullAllow, true, true, false), Decision::Denied);
}
#[test]
fn actual_loop_commits_once_and_followup_uses_tool_result() {
    let root = std::env::temp_dir().join(format!("core-agent-test-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
    fs::create_dir(&root).unwrap();
    let script = root.join("script");
    fs::write(&script, "tool\tc1\tfixture.record\t68656c6c6f\nanswer\t7b7b746f6f6c5f726573756c747d7d\n").unwrap();
    let store = root.join("store");
    let bin = env!("CARGO_BIN_EXE_muyon-core-agent-lab");
    let start = Command::new(bin).args(["start", "--dir"]).arg(&store).arg("--script").arg(&script).output().unwrap();
    assert!(start.status.success(), "{}", String::from_utf8_lossy(&start.stderr));
    let run = Command::new(bin).args(["run", "--dir"]).arg(&store).output().unwrap();
    let out = String::from_utf8(run.stdout).unwrap();
    assert!(run.status.success(), "{}", String::from_utf8_lossy(&run.stderr));
    assert!(out.contains("status=completed\n"), "{out}");
    assert!(out.contains("effects=1\n"), "{out}");
    let physical = fs::read_to_string(store.join("effects.db")).unwrap();
    assert!(physical.contains("value\t68656c6c6f\n"), "{physical}");
    let second = Command::new(bin).args(["run", "--dir"]).arg(&store).output().unwrap();
    assert!(second.status.success());
    assert_eq!(fs::read_to_string(store.join("effects.db")).unwrap(), physical);
    assert!(out.contains("model_calls=2\n"), "{out}");
    assert!(!out.contains("answer_hex=\n"), "{out}");
}
