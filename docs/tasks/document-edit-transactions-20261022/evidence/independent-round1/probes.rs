#[path = "/workspace/Muyon/crates/muyon-core/src/document_edit/mod.rs"]
mod document_edit;
use document_edit::*;

fn binding() -> Binding {
    Binding { document_id: "doc".into(), scope: "project-a".into(), source_revision: "r1".into(), patch_digest: [7;32], intent_id: "intent-1".into(), rollback_target: None }
}
fn facts(b: &Binding) -> HostFacts {
    HostFacts { binding: b.clone(), current_revision: b.source_revision.clone(), authority: Some(Authority { grant_id: "grant".into(), generation: 1, owner_epoch: "owner".into() }), active: true }
}
fn candidate() -> Candidate {
    Candidate { id: "copy-1".into(), digest: [8;32], immutable_copy: true }
}
fn validation() -> Validation {
    Validation { candidate: candidate(), reopened: true, structure: true, semantics: true, render_comparison: true, unsupported_preserved: true, formula: FormulaStatus::NotApplicable }
}
fn previewed() -> Transaction {
    let mut t=Transaction::new(binding()).unwrap(); let f=facts(t.binding());
    t.execute(Command::Inspect, Some(&f)).unwrap();
    t.execute(Command::Read, Some(&f)).unwrap();
    t.execute(Command::Propose, Some(&f)).unwrap();
    t.execute(Command::Preview, Some(&f)).unwrap(); t
}
fn applied() -> Transaction {
    let mut t=previewed();let f=facts(t.binding());
    t.execute(Command::ApplyCopy { confirmation: Confirmation { binding: t.binding().clone(), authority: f.authority.clone().unwrap() }, candidate: Some(candidate()) }, Some(&f)).unwrap();t
}
fn validated() -> Transaction {
    let mut t=applied(); let f=facts(t.binding());
    t.execute(Command::Validate(Some(validation())),Some(&f)).unwrap();t
}
fn receipt(b: &Binding) -> CommitReceipt {
    CommitReceipt { binding:b.clone(), candidate:candidate(), previous_revision:b.source_revision.clone(), committed_revision:"r2".into(), cas_succeeded:true, durable:true }
}


#[test]
fn old_candidate_and_validation_accept_new_patch_and_intent() {
    let old_candidate = candidate();
    let old_validation = validation();
    let mut b = binding(); b.intent_id = "new-intent".into(); b.patch_digest = [42;32];
    let f = facts(&b); let mut t = Transaction::new(b.clone()).unwrap();
    for c in [Command::Inspect, Command::Read, Command::Propose, Command::Preview] { t.execute(c, Some(&f)).unwrap(); }
    t.execute(Command::ApplyCopy { confirmation: Confirmation { binding:b, authority:f.authority.clone().unwrap() }, candidate:Some(old_candidate) },Some(&f)).unwrap();
    t.execute(Command::Validate(Some(old_validation)),Some(&f)).unwrap();
    println!("old output/report accepted for new intent and patch: {:?}",t.state());
    assert_eq!(t.state(),State::Validated);
}
#[test]
fn cancel_before_late_commit_loses_outcome() {
    let mut t=validated(); let f=facts(t.binding()); let r=receipt(t.binding());
    t.execute(Command::Cancel,Some(&f)).unwrap();
    let late=t.execute(Command::Commit(Some(r)),Some(&f));
    let unknown=t.execute(Command::OutcomeUnknown,Some(&f));
    println!("cancel before late durable receipt: {late:?}; mark unknown: {unknown:?}; state {:?}",t.state());
    assert_eq!(late,Err(Error::State));assert_eq!(unknown,Err(Error::State));
}
#[test]
fn renewed_authority_blocks_original_intent_recovery_and_cancel() {
    let mut t=validated(); let mut f=facts(t.binding()); let r=receipt(t.binding());
    t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();
    f.authority.as_mut().unwrap().generation += 1;
    let recovery=t.execute(Command::RecoverCommit(Some(r)),Some(&f));
    let cancel=t.execute(Command::Cancel,Some(&f));
    println!("renewed live grant: recover {recovery:?}; cancel {cancel:?}; state {:?}; cancel_requested {}",t.state(),t.cancel_requested());
    assert_eq!(recovery,Err(Error::Authority));assert_eq!(cancel,Err(Error::Authority));
}
