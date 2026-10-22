use contract::{Revision, Scope};
use documents::{
    CapabilityMatrix, CapabilityStatus, DocumentFormat, DocumentOperation, DocumentRef,
};
use muyon_core::{contract, documents};
#[path = "/workspace/Muyon/crates/muyon-core/src/document_edit/mod.rs"]
mod document_edit;
use document_edit::*;

fn document(project: &str, revision: u64) -> DocumentRef {
    DocumentRef::new(
        Scope {
            workspace_id: "workspace".into(),
            project_id: Some(project.into()),
        },
        "doc",
        Revision::new(revision),
        DocumentFormat::Docx,
    )
    .unwrap()
}
fn binding() -> Binding {
    Binding {
        document: document("project-a", 1),
        patch_digest: [7; 32],
        intent_id: "intent-1".into(),
        rollback_target: None,
    }
}
fn facts(b: &Binding) -> HostFacts {
    // Synthetic capability facts for contract tests, never installed engine proof.
    let mut capabilities = CapabilityMatrix::default();
    for op in [
        DocumentOperation::Inspect,
        DocumentOperation::ReadText,
        DocumentOperation::Render,
        DocumentOperation::StructuredEdit,
        DocumentOperation::Validate,
        DocumentOperation::Export,
    ] {
        capabilities.set(b.document.format(), op, CapabilityStatus::Supported);
    }
    HostFacts {
        permissions: vec![
            DocumentOperation::Inspect,
            DocumentOperation::ReadText,
            DocumentOperation::Render,
            DocumentOperation::StructuredEdit,
            DocumentOperation::Validate,
            DocumentOperation::Export,
        ],
        capabilities,
        binding: b.clone(),
        current_revision: b.document.revision().clone(),
        authority: Some(Authority {
            grant_id: "grant".into(),
            generation: Revision::new(1),
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
        previous_revision: b.document.revision().clone(),
        committed_revision: Revision::new(2),
        cas_succeeded: true,
        durable: true,
    }
}


fn altered_doc(field:usize)->DocumentRef {
 let mut scope=binding().document.scope().clone();let mut id="doc";let mut rev=Revision::new(1);let mut fmt=DocumentFormat::Docx;
 match field {0=>scope.workspace_id="other".into(),1=>scope.project_id=None,2=>scope.project_id=Some("other".into()),3=>id="other",4=>rev=Revision::new(2),_=>fmt=DocumentFormat::Xlsx}
 DocumentRef::new(scope,id,rev,fmt).unwrap()
}
#[test] fn full_current_identity_and_candidate_binding_are_exact() {
 for field in 0..6 {
  let mut t=previewed();let mut f=facts(t.binding());f.binding.document=altered_doc(field);
  assert_eq!(t.execute(Command::Cancel,Some(&f)),Err(Error::Binding));assert!(!t.cancel_requested());
  let f=facts(t.binding());let mut c=candidate();c.binding.document=altered_doc(field);
  assert_eq!(t.execute(Command::ApplyCopy{confirmation:Confirmation{binding:t.binding().clone(),authority:f.authority.clone().unwrap()},candidate:Some(c)},Some(&f)),Err(Error::Binding));
  assert_eq!(t.state(),State::Previewed);
 }
}
#[test] fn each_gated_status_and_default_matrix_close_read_and_write() {
 for s in [CapabilityStatus::Unknown,CapabilityStatus::Unsupported,CapabilityStatus::NeedsLicense,CapabilityStatus::NeedsNetwork,CapabilityStatus::ReadOnly] {
  let mut t=previewed();let mut f=facts(t.binding());f.capabilities.set(DocumentFormat::Docx,DocumentOperation::StructuredEdit,s);
  assert_eq!(t.execute(Command::AwaitApply(Confirmation{binding:t.binding().clone(),authority:f.authority.clone().unwrap()}),Some(&f)),Err(Error::Capability));
 }
 let mut t=Transaction::new(binding()).unwrap();let mut f=facts(t.binding());f.capabilities=CapabilityMatrix::default();assert_eq!(t.execute(Command::Inspect,Some(&f)),Err(Error::Capability));
 f.capabilities.set(DocumentFormat::Xlsx,DocumentOperation::Inspect,CapabilityStatus::Supported);assert_eq!(t.execute(Command::Inspect,Some(&f)),Err(Error::Capability));
 f.capabilities.set(DocumentFormat::Docx,DocumentOperation::Inspect,CapabilityStatus::ReadOnly);t.execute(Command::Inspect,Some(&f)).unwrap();
}
#[test] fn local_unknown_and_cancel_survive_all_authority_removal() {
 let mut t=validated();let mut f=facts(t.binding());f.authority=None;f.active=false;f.permissions.clear();f.capabilities=CapabilityMatrix::default();
 t.execute(Command::Cancel,Some(&f)).unwrap();t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();t.execute(Command::Cancel,Some(&f)).unwrap();
 assert_eq!(t.state(),State::Unknown);assert!(t.cancel_requested());assert_eq!(t.execute(Command::RecoverCommit(Some(receipt(t.binding()))),Some(&f)),Err(Error::Authority));
}
#[test] fn new_inspect_authority_recovers_original_commit_but_not_exports() {
 let mut t=validated();let mut f=facts(t.binding());t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();
 f.authority.as_mut().unwrap().generation=Revision::new(3);f.authority.as_mut().unwrap().owner_epoch="other".into();f.permissions=vec![DocumentOperation::Inspect];f.capabilities=CapabilityMatrix::default();
 assert_eq!(t.execute(Command::RecoverCommit(Some(receipt(t.binding()))),Some(&f)),Err(Error::Capability));
 f.capabilities.set(DocumentFormat::Docx,DocumentOperation::Inspect,CapabilityStatus::ReadOnly);t.execute(Command::RecoverCommit(Some(receipt(t.binding()))),Some(&f)).unwrap();assert_eq!(t.state(),State::Committed);
 let e=ExportReceipt{binding:t.binding().clone(),candidate:candidate(),revision:Revision::new(2),export_id:"exp".into(),durable:true};assert_eq!(t.execute(Command::Export(Some(e)),Some(&f)),Err(Error::Authority));
}
#[test] fn recovered_cancelled_apply_preserves_candidate_and_stops() {
 let mut t=previewed();let mut f=facts(t.binding());t.execute(Command::AwaitApply(Confirmation{binding:t.binding().clone(),authority:f.authority.clone().unwrap()}),Some(&f)).unwrap();
 t.execute(Command::Cancel,Some(&f)).unwrap();f.authority=None;f.active=false;f.permissions.clear();f.capabilities=CapabilityMatrix::default();t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();
 let mut f=facts(t.binding());f.authority.as_mut().unwrap().generation=Revision::new(2);f.permissions=vec![DocumentOperation::Inspect];f.capabilities=CapabilityMatrix::default();f.capabilities.set(DocumentFormat::Docx,DocumentOperation::Inspect,CapabilityStatus::Supported);
 assert_eq!(t.execute(Command::RecoverCommit(Some(receipt(t.binding()))),Some(&f)),Err(Error::State));t.execute(Command::RecoverApply(Some(candidate())),Some(&f)).unwrap();assert_eq!(t.state(),State::Cancelled);assert_eq!(t.candidate(),Some(&candidate()));
 let old=facts(t.binding());assert_eq!(t.execute(Command::Validate(Some(validation())),Some(&old)),Err(Error::State));assert_eq!(t.execute(Command::Commit(Some(receipt(t.binding()))),Some(&old)),Err(Error::State));
}
#[test] fn validation_candidate_binding_and_commit_receipt_remain_exact() {
 let mut t=applied();let f=facts(t.binding());let mut v=validation();v.candidate.binding.document=altered_doc(5);assert_eq!(t.execute(Command::Validate(Some(v)),Some(&f)),Err(Error::Binding));
 let mut t=validated();t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();let mut r=receipt(t.binding());r.binding.document=altered_doc(0);assert_eq!(t.execute(Command::RecoverCommit(Some(r)),Some(&f)),Err(Error::Binding));assert_eq!(t.state(),State::Unknown);
}
