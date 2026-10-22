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


fn ready_at(base:u64)->(Transaction,HostFacts,Candidate) {
 let mut b=binding();b.document=document("project-a",base);let f=facts(&b);let mut t=Transaction::new(b.clone()).unwrap();
 for op in [Command::Inspect,Command::Read,Command::Propose,Command::Preview] {t.execute(op,Some(&f)).unwrap();}
 let c=Candidate{binding:b.clone(),..candidate()};
 t.execute(Command::ApplyCopy{confirmation:Confirmation{binding:b,authority:f.authority.clone().unwrap()},candidate:Some(c.clone())},Some(&f)).unwrap();
 t.execute(Command::Validate(Some(Validation{candidate:c.clone(),..validation()})),Some(&f)).unwrap();(t,f,c)
}
fn result_at(t:&mut Transaction,f:&HostFacts,c:&Candidate,base:u64,next:u64,recover:bool)->Result<(),Error> {
 let r=CommitReceipt{binding:t.binding().clone(),candidate:c.clone(),previous_revision:Revision::new(base),committed_revision:Revision::new(next),cas_succeeded:true,durable:true};
 t.execute(if recover {Command::RecoverCommit(Some(r))}else{Command::Commit(Some(r))},Some(f))
}
#[test] fn numeric_grid_all_routes_accept_only_exact_successor() {
 let mut checked=0;
 for base in 0..=12 {for next in 0..=13 {for route in 0..3 {
  let(mut t,mut f,c)=ready_at(base);
  if route==1 {t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();}
  if route==2 {t.execute(Command::Cancel,Some(&f)).unwrap();}
  if route>0 {f.authority.as_mut().unwrap().generation=Revision::new(2);f.authority.as_mut().unwrap().owner_epoch="new-epoch".into();f.permissions=vec![DocumentOperation::Inspect];f.current_revision=Revision::new(99);}
  let before=t.state();let result=result_at(&mut t,&f,&c,base,next,route>0);
  if next==base+1 {assert_eq!(result,Ok(()));assert_eq!(t.state(),State::Committed);}
  else {assert_eq!(result,Err(Error::Binding));assert_eq!(t.state(),before);assert_eq!(t.candidate(),Some(&c));assert_eq!(result_at(&mut t,&f,&c,base,base+1,route>0),Ok(()));}
  checked+=1;
 }}}
 println!("independent numeric grid: {checked} cases (plus valid retry after every rejected observation)");
}
#[test] fn max_edges_all_routes_never_wrap_or_skip() {
 let mut checked=0;
 for (base,next,ok) in [(u64::MAX-1,u64::MAX,true),(u64::MAX-2,u64::MAX,false),(u64::MAX,0,false),(u64::MAX,1,false),(u64::MAX,u64::MAX,false)] {
  for route in 0..3 {let(mut t,f,c)=ready_at(base);if route==1 {t.execute(Command::OutcomeUnknown,Some(&f)).unwrap();}if route==2 {t.execute(Command::Cancel,Some(&f)).unwrap();}let before=t.state();let result=result_at(&mut t,&f,&c,base,next,route>0);if ok {assert_eq!(result,Ok(()));}else {assert_eq!(result,Err(Error::Binding));assert_eq!(t.state(),before);assert_eq!(t.candidate(),Some(&c));}checked+=1;}
 }
 println!("independent overflow/skip edges: {checked} cases");
}
#[test] fn rejected_revision_cannot_export_or_create_rollback() {
 let(mut t,f,c)=ready_at(9);assert_eq!(result_at(&mut t,&f,&c,9,2,false),Err(Error::Binding));
 let e=ExportReceipt{binding:t.binding().clone(),candidate:c,revision:Revision::new(2),export_id:"exp".into(),durable:true};assert_eq!(t.execute(Command::Export(Some(e)),Some(&f)),Err(Error::State));
 let mut next=t.binding().clone();next.intent_id="rollback-new".into();next.document=document("project-a",2);next.rollback_target=Some(Revision::new(9));assert_eq!(t.rollback(next).unwrap_err(),Error::State);
}
