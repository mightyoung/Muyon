#[path = "/workspace/Muyon/crates/muyon-core/src/document_edit/mod.rs"]
mod document_edit;
use document_edit::*;

fn binding() -> Binding {
    Binding {
        document_id: "doc".into(),
        scope: "project-a".into(),
        source_revision: "r1".into(),
        patch_digest: [7; 32],
        intent_id: "intent-1".into(),
        rollback_target: None,
    }
}
fn facts(b: &Binding) -> HostFacts {
    HostFacts {
        binding: b.clone(),
        current_revision: b.source_revision.clone(),
        authority: Some(Authority {
            grant_id: "grant".into(),
            generation: 1,
            owner_epoch: "owner".into(),
        }),
        active: true,
    }
}
fn candidate() -> Candidate {
    Candidate {
        binding: binding(),
        id: "copy-1".into(),
        digest: [8; 32],
        immutable_copy: true,
    }
}
fn validation() -> Validation {
    Validation {
        candidate: candidate(),
        reopened: true,
        structure: true,
        semantics: true,
        render_comparison: true,
        unsupported_preserved: true,
        formula: FormulaStatus::NotApplicable,
    }
}
fn previewed() -> Transaction {
    let mut t = Transaction::new(binding()).unwrap();
    let f = facts(t.binding());
    t.execute(Command::Inspect, Some(&f)).unwrap();
    t.execute(Command::Read, Some(&f)).unwrap();
    t.execute(Command::Propose, Some(&f)).unwrap();
    t.execute(Command::Preview, Some(&f)).unwrap();
    t
}
fn applied() -> Transaction {
    let mut t = previewed();
    let f = facts(t.binding());
    t.execute(
        Command::ApplyCopy {
            confirmation: Confirmation {
                binding: t.binding().clone(),
                authority: f.authority.clone().unwrap(),
            },
            candidate: Some(candidate()),
        },
        Some(&f),
    )
    .unwrap();
    t
}
fn validated() -> Transaction {
    let mut t = applied();
    let f = facts(t.binding());
    t.execute(Command::Validate(Some(validation())), Some(&f))
        .unwrap();
    t
}
fn receipt(b: &Binding) -> CommitReceipt {
    CommitReceipt {
        binding: b.clone(),
        candidate: candidate(),
        previous_revision: b.source_revision.clone(),
        committed_revision: "r2".into(),
        cas_succeeded: true,
        durable: true,
    }
}


fn awaiting() -> Transaction {
 let mut t=previewed();let f=facts(t.binding());
 t.execute(Command::AwaitApply(Confirmation{binding:t.binding().clone(),authority:f.authority.clone().unwrap()}),Some(&f)).unwrap();t
}
#[test] fn candidate_binding_all_dimensions_rejected() {
 for field in 0..6 {
  let mut t=previewed();let f=facts(t.binding());let mut c=candidate();
  match field {0=>c.binding.document_id="other".into(),1=>c.binding.source_revision="r0".into(),2=>c.binding.scope="other".into(),3=>c.binding.patch_digest=[42;32],4=>c.binding.intent_id="other".into(),_=>c.binding.rollback_target=Some("r0".into())}
  assert_eq!(t.execute(Command::ApplyCopy{confirmation:Confirmation{binding:t.binding().clone(),authority:f.authority.clone().unwrap()},candidate:Some(c)},Some(&f)),Err(Error::Binding));
  assert_eq!(t.state(),State::Previewed);
 }
}
#[test] fn validation_report_binding_cannot_be_reused() {
 let mut t=applied();let f=facts(t.binding());let mut v=validation();v.candidate.binding.intent_id="old-intent".into();
 assert_eq!(t.execute(Command::Validate(Some(v)),Some(&f)),Err(Error::Binding));assert_eq!(t.state(),State::Candidate);
}
#[test] fn commit_query_recovery_does_not_reauthorize_export() {
 let mut t=validated();let mut f=facts(t.binding());
 t.execute(Command::Cancel,Some(&f)).unwrap();t.execute(Command::Cancel,Some(&f)).unwrap();
 f.authority.as_mut().unwrap().generation+=1;f.authority.as_mut().unwrap().owner_epoch="new-epoch".into();f.current_revision="r3".into();
 t.execute(Command::RecoverCommit(Some(receipt(t.binding()))),Some(&f)).unwrap();assert_eq!(t.state(),State::Committed);assert!(t.cancel_requested());
 let e=ExportReceipt{binding:t.binding().clone(),candidate:candidate(),revision:"r2".into(),export_id:"export".into(),durable:true};
 assert_eq!(t.execute(Command::Export(Some(e)),Some(&f)),Err(Error::Authority));
}
#[test] fn apply_query_recovery_does_not_reauthorize_validate() {
 let mut t=awaiting();let mut f=facts(t.binding());t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();
 f.authority.as_mut().unwrap().generation+=1;
 t.execute(Command::RecoverApply(Some(candidate())),Some(&f)).unwrap();assert_eq!(t.state(),State::Candidate);
 assert_eq!(t.execute(Command::Validate(Some(validation())),Some(&f)),Err(Error::Authority));
}
#[test] fn recover_phases_cannot_be_swapped() {
 let mut t=validated();let f=facts(t.binding());t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();
 assert_eq!(t.execute(Command::RecoverApply(Some(candidate())),Some(&f)),Err(Error::State));assert_eq!(t.state(),State::Unknown);
 let mut t=awaiting();t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();
 assert_eq!(t.execute(Command::RecoverCommit(Some(receipt(t.binding()))),Some(&f)),Err(Error::State));assert_eq!(t.state(),State::Unknown);
}
#[test] fn cancelled_apply_preserves_copy_but_no_work_resumes() {
 let mut t=awaiting();let mut f=facts(t.binding());t.execute(Command::Cancel,Some(&f)).unwrap();t.execute(Command::Cancel,Some(&f)).unwrap();
 t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();t.execute(Command::Cancel,Some(&f)).unwrap();
 f.authority.as_mut().unwrap().generation+=1;t.execute(Command::RecoverApply(Some(candidate())),Some(&f)).unwrap();
 assert!(t.cancel_requested());assert_eq!(t.state(),State::Cancelled);assert_eq!(t.candidate(),Some(&candidate()));
 let old=facts(t.binding());assert_eq!(t.execute(Command::Validate(Some(validation())),Some(&old)),Err(Error::State));
 assert_eq!(t.execute(Command::Commit(Some(receipt(t.binding()))),Some(&old)),Err(Error::State));
}
#[test] fn revoked_cancel_and_cross_binding_cancel() {
 let mut t=awaiting();let mut f=facts(t.binding());f.authority=None;f.active=false;f.current_revision.clear();
 t.execute(Command::Cancel,Some(&f)).unwrap();assert!(t.cancel_requested());assert_eq!(t.state(),State::Applying);
 let mut t=awaiting();f.binding.scope="other".into();assert_eq!(t.execute(Command::Cancel,Some(&f)),Err(Error::Binding));assert!(!t.cancel_requested());
}
