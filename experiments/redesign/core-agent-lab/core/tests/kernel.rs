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

fn fixture(script_text:&str,extra:&[&str])->std::path::PathBuf {
    let root=std::env::temp_dir().join(format!("core-agent-check-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::SeqCst)));
    fs::create_dir(&root).unwrap();let script=root.join("script");fs::write(&script,script_text).unwrap();let dir=root.join("store");
    let output=Command::new(env!("CARGO_BIN_EXE_muyon-core-agent-lab")).args(["start","--dir"]).arg(&dir).arg("--script").arg(script).args(extra).output().unwrap();
    assert!(output.status.success(),"{}",String::from_utf8_lossy(&output.stderr));dir
}
fn command(dir:&std::path::Path,verb:&str,extra:&[&str])->String {
    let output=Command::new(env!("CARGO_BIN_EXE_muyon-core-agent-lab")).args([verb,"--dir"]).arg(dir).args(extra).output().unwrap();
    assert!(output.status.success(),"{}",String::from_utf8_lossy(&output.stderr));String::from_utf8(output.stdout).unwrap()
}
const SCRIPT:&str="tool\tc1\tfixture.record\t6869\nanswer\t7b7b746f6f6c5f726573756c747d7d\n";
#[test]
fn lost_response_reopens_lookup_only_and_preserves_original_receipt(){
    let dir=fixture(SCRIPT,&["--tool-behavior","lose-response"]);
    assert!(command(&dir,"run",&[]).contains("status=outcome_unknown\n"));
    let physical=fs::read_to_string(dir.join("effects.db")).unwrap();
    let again=command(&dir,"run",&[]);assert!(again.contains("model_calls=1\n"));assert!(again.contains("status=outcome_unknown\n"));
    assert!(command(&dir,"lookup",&[]).contains("receipt=r-i-1\n"));
    let done=command(&dir,"run",&[]);assert!(done.contains("status=completed\n"));
    let expected=muyon_core_agent_lab::hex("receipt=r-i-1;value=hi");assert!(done.contains(&format!("answer_hex={expected}\n")));
    assert_eq!(fs::read_to_string(dir.join("effects.db")).unwrap(),physical);
}
#[test]
fn physical_binding_replay_returns_original_and_altered_binding_conflicts(){
    use muyon_core_agent_lab::store::{Binding,FixtureTool,ToolPort,EffectStore};
    let dir=fixture("answer\t\n",&[]);let mut tool=FixtureTool{dir:dir.clone()};
    let binding=Binding{invocation:"i-test".into(),task:"t-test".into(),attempt:"a-test".into(),turn:1,scope:"fixture".into(),value:"actual".into()};
    let original=tool.execute_once(&binding).unwrap();assert_eq!(tool.execute_once(&binding).unwrap(),original);
    let mut changed=binding.clone();changed.value="altered".into();assert!(tool.execute_once(&changed).is_err());
    changed=binding.clone();changed.scope="other".into();assert!(tool.execute_once(&changed).is_err());
    changed=binding.clone();changed.attempt="stale".into();assert!(tool.lookup(&changed).is_err());
    assert_eq!(EffectStore::load(&dir).unwrap().receipts.len(),1);
}
#[test]
fn exhausted_budget_survives_reopen_and_does_not_request_followup(){
    let dir=fixture(SCRIPT,&["--max-steps","1"]);let first=command(&dir,"run",&[]);
    assert!(first.contains("status=budget_exhausted\n"));assert!(first.contains("model_calls=1\n"));assert!(first.contains("effects=1\n"));
    assert_eq!(command(&dir,"run",&[]),first);
}
#[test]
fn confirmation_is_current_exact_pending_and_does_not_override_hard_denial(){
    let dir=fixture(SCRIPT,&["--mode","ask-every-time"]);let waiting=command(&dir,"run",&[]);
    assert!(waiting.contains("status=waiting\n"));assert!(waiting.contains("effects=0\n"));
    assert_eq!(command(&dir,"run",&[]),waiting);
    let denied=command(&dir,"run",&["--confirmed","true","--revoked","true"]);assert!(denied.contains("status=denied\n"));assert!(denied.contains("effects=0\n"));
    let dir=fixture(SCRIPT,&["--mode","ask-every-time"]);command(&dir,"run",&[]);
    let done=command(&dir,"run",&["--confirmed","true"]);assert!(done.contains("status=completed\n"));assert!(done.contains("confirmations=1\n"));
}
#[test]
fn cancellation_before_dispatch_and_after_commit_preserves_truth(){
    let before=fixture(SCRIPT,&[]);command(&before,"cancel",&[]);let out=command(&before,"run",&[]);assert!(out.contains("effects=0\n"));assert!(out.contains("model_calls=0\n"));
    let after=fixture(SCRIPT,&["--tool-behavior","lose-response"]);command(&after,"run",&[]);let cancelled=command(&after,"cancel",&[]);
    assert!(cancelled.contains("receipt=r-i-1\n"));assert!(cancelled.contains("effects=1\n"));assert!(cancelled.contains("status=cancelled\n"));assert!(command(&after,"run",&[]).contains("model_calls=1\n"));
}
#[test]
fn malformed_or_model_authority_script_is_rejected(){
    use muyon_core_agent_lab::model::ScriptedProvider;
    for script in ["tool\tc1\tfixture.record\t61\tapproved=true\n","tool\tc1\tfixture.alias\t61\n","tool\tc1\tfixture.record\tf\n","tool\tc1\tfixture.record\tff\n","tool\tc1\tfixture.record\n","answer\t61\textra\n","partial\tc1\n"] {assert!(ScriptedProvider::parse(script).is_err(),"{script}");}
}
#[test]
fn corrupt_or_absent_original_evidence_never_replays_unknown(){
    let dir=fixture(SCRIPT,&["--tool-behavior","lose-response"]);command(&dir,"run",&[]);
    fs::write(dir.join("effects.db"),"corrupt\n").unwrap();assert!(command(&dir,"lookup",&[]).contains("status=outcome_unknown\n"));
    assert!(command(&dir,"run",&[]).contains("model_calls=1\n"));
    fs::rename(dir.join("effects.db"),dir.join("preserved-corrupt.db")).unwrap();assert!(command(&dir,"lookup",&[]).contains("status=outcome_unknown\n"));assert!(command(&dir,"run",&[]).contains("effects=unknown\n"));assert!(!dir.join("effects.db").exists());
}
#[test]
fn duplicate_provider_reference_cannot_mint_second_invocation(){
    let dir=fixture("tool\tc1\tfixture.record\t61\ntool\tc1\tfixture.record\t62\n",&[]);let out=command(&dir,"run",&[]);assert!(out.contains("status=failed\n"));assert!(out.contains("effects=1\n"));assert!(out.contains("value_hex=61\n"));assert!(out.contains("reason=binding_conflict\n"));
}
#[test]
fn provider_failure_and_definite_tool_failure_never_fabricate_success(){
    let dir=fixture("fail\tunavailable\n",&[]);let out=command(&dir,"run",&[]);assert!(out.contains("status=failed\n"));assert!(out.contains("effects=0\n"));
    let dir=fixture(SCRIPT,&["--tool-behavior","fail"]);let out=command(&dir,"run",&[]);assert!(out.contains("status=failed\n"));assert!(out.contains("effects=0\n"));assert!(out.contains("receipt=\n"));
}
#[test]
fn cached_completed_projection_cannot_replace_original_evidence(){
    let dir=fixture(SCRIPT,&[]);assert!(command(&dir,"run",&[]).contains("status=completed\n"));
    fs::write(dir.join("effects.db"),"damaged\n").unwrap();
    let inspect=command(&dir,"inspect",&[]);assert!(inspect.contains("status=outcome_unknown\n"));assert!(inspect.contains("effects=unknown\n"));
    let run=command(&dir,"run",&[]);assert!(run.contains("status=outcome_unknown\n"));assert!(run.contains("model_calls=2\n"));
}
#[test]
fn resume_confirmation_requires_an_existing_exact_pending_invocation(){
    let dir=fixture(SCRIPT,&["--mode","ask-every-time"]);
    let output=Command::new(env!("CARGO_BIN_EXE_muyon-core-agent-lab")).args(["run","--dir"]).arg(&dir).args(["--confirmed","true"]).output().unwrap();
    assert!(!output.status.success(),"a resume confirmation must not preauthorize an unseen model call");
    let before=command(&dir,"inspect",&[]);assert!(before.contains("model_calls=0\n"));assert!(before.contains("effects=0\n"));
    assert!(command(&dir,"run",&[]).contains("status=waiting\n"));
    assert!(command(&dir,"run",&["--confirmed","true"]).contains("status=completed\n"));
}
#[test]
fn restoring_receipt_preserves_completed_control_barrier(){
    let dir=fixture("tool\tc1\tfixture.record\t6869\nanswer\t646f6e65\ntool\tc2\tfixture.record\t6c61746572\nanswer\t6c61746572\n",&[]);
    let done=command(&dir,"run",&[]);assert!(done.contains("status=completed\n"));assert!(done.contains("model_calls=2\n"));
    let physical=fs::read_to_string(dir.join("effects.db")).unwrap();
    fs::rename(dir.join("effects.db"),dir.join("preserved-effects.db")).unwrap();
    assert!(command(&dir,"run",&[]).contains("status=outcome_unknown\n"));
    fs::rename(dir.join("preserved-effects.db"),dir.join("effects.db")).unwrap();
    assert!(command(&dir,"lookup",&[]).contains("status=completed\n"));
    assert_eq!(command(&dir,"run",&[]),done);assert_eq!(fs::read_to_string(dir.join("effects.db")).unwrap(),physical);
}
#[test]
fn restoring_receipt_preserves_call_budget_barrier(){
    let dir=fixture("tool\tc1\tfixture.record\t6869\nanswer\t\n",&["--max-calls","1"]);
    let stopped=command(&dir,"run",&[]);assert!(stopped.contains("status=budget_exhausted\n"));assert!(stopped.contains("model_calls=1\n"));
    fs::rename(dir.join("effects.db"),dir.join("preserved-effects.db")).unwrap();
    assert!(command(&dir,"run",&[]).contains("status=outcome_unknown\n"));
    fs::rename(dir.join("preserved-effects.db"),dir.join("effects.db")).unwrap();
    assert!(command(&dir,"lookup",&[]).contains("status=budget_exhausted\n"));
    assert_eq!(command(&dir,"run",&[]),stopped);
}
#[test]
fn repeated_provider_reference_replays_original_receipt_without_permission_consumption(){
    let dir=fixture("tool\tc1\tfixture.record\t6869\ntool\tc1\tfixture.record\t6869\nanswer\t7b7b746f6f6c5f726573756c747d7d\n",&["--mode","ask-every-time","--confirmed","true"]);
    let done=command(&dir,"run",&[]);assert!(done.contains("status=completed\n"));assert!(done.contains("effects=1\n"));assert!(done.contains("model_calls=3\n"));assert!(done.contains("confirmations=1\n"));assert!(done.contains("receipt=r-i-1\n"));
    assert!(done.contains(&format!("answer_hex={}\n",muyon_core_agent_lab::hex("receipt=r-i-1;value=hi"))));
}
#[test]
fn repeated_reference_mapping_survives_unknown_and_restart(){
    let dir=fixture("tool\tc1\tfixture.record\t6869\ntool\tc1\tfixture.record\t6869\nanswer\t7b7b746f6f6c5f726573756c747d7d\n",&["--tool-behavior","lose-response"]);
    let unknown=command(&dir,"run",&[]);assert!(unknown.contains("status=outcome_unknown\n"));assert_eq!(command(&dir,"run",&[]),unknown);
    let physical=fs::read_to_string(dir.join("effects.db")).unwrap();command(&dir,"lookup",&[]);
    let done=command(&dir,"run",&[]);assert!(done.contains("status=completed\n"));assert!(done.contains("model_calls=3\n"));assert!(done.contains("receipt=r-i-1\n"));assert_eq!(fs::read_to_string(dir.join("effects.db")).unwrap(),physical);
}

#[test]
fn tool_result_context_budget_is_admitted_before_first_effect_or_confirmation(){
    let dir=fixture(SCRIPT,&["--max-context","40","--mode","ask-every-time","--confirmed","true"]);
    let stopped=command(&dir,"run",&[]);assert!(stopped.contains("status=budget_exhausted\n"));assert!(stopped.contains("effects=0\n"));assert!(stopped.contains("confirmations=0\n"));assert!(stopped.contains("model_calls=1\n"));assert!(stopped.contains("receipt=\n"));
    assert_eq!(command(&dir,"run",&[]),stopped);
}
