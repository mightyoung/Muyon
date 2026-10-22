//! Original synthetic bytes only; no Office engine, model, network or user files.
use muyon_core::{
    blobs::BlobKind,
    business::BusinessStore,
    contract::*,
    document_edit::{
        edited_candidates::*,
        engine_protocol::{prepare_request_trusted, NumericCellEdit, PreparedEngineRequest},
        gateway::DocumentEditGateway,
        Binding, Confirmation,
    },
    documents::{DocumentAccess, DocumentFormat, DocumentOperation, DocumentRef},
};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
const SYNTHETIC: &[u8] = b"original synthetic copy bytes; no Office engine acceptance";
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "muyon-edited-candidate-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn path(&self) -> PathBuf {
        self.0.join("store.sqlite")
    }
    fn reopen(&self, epoch: &str) -> BusinessStore {
        BusinessStore::open_existing(&self.path(), "workspace", epoch).unwrap()
    }
    fn store(&self) -> BusinessStore {
        self.store_with_format(DocumentFormat::Xlsx)
    }
    fn store_with_format(&self, format: DocumentFormat) -> BusinessStore {
        BusinessStore::initialize(&self.path(), "workspace").unwrap();
        let s = self.reopen("epoch-1");
        let mut c = CommandEnvelope {
            protocol_version: 1,
            business_version: 1,
            intent_id: "create-project".into(),
            scope: Scope {
                workspace_id: "workspace".into(),
                project_id: Some("project".into()),
            },
            expected_revision: Revision::new(0),
            authority: AuthorityBinding {
                grant_id: "business-project".into(),
                generation: Revision::new(1),
                owner_epoch: "epoch-1".into(),
            },
            plan_id: "plan-project".into(),
            plan_digest: "0".repeat(64),
            command: Operation::ProjectCreate {
                project_id: "project".into(),
                name: "Synthetic local test".into(),
            },
        };
        c.plan_digest = c.expected_plan_digest().unwrap();
        s.issue_grant_trusted(&c, None).unwrap();
        assert_eq!(s.execute(&c).unwrap().status, ExecutionStatus::Committed);
        s.initialize_documents_trusted().unwrap();
        let upload = s.begin_upload("project").unwrap();
        s.append_chunk(&upload.upload_id, SYNTHETIC).unwrap();
        let blob = s
            .finish_blob(&upload.upload_id, BlobKind::Document)
            .unwrap();
        s.register_document_trusted("project", "document", "Synthetic", format, &blob)
            .unwrap();
        s
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn reference(revision: u64) -> DocumentRef {
    DocumentRef::new(
        Scope {
            workspace_id: "workspace".into(),
            project_id: Some("project".into()),
        },
        "document",
        Revision::new(revision),
        DocumentFormat::Xlsx,
    )
    .unwrap()
}
fn access(
    s: &BusinessStore,
    revision: u64,
    id: &str,
    generation: u64,
    epoch: &str,
) -> DocumentAccess {
    let a = DocumentAccess {
        document: reference(revision),
        authority: AuthorityBinding {
            grant_id: id.into(),
            generation: Revision::new(generation),
            owner_epoch: epoch.into(),
        },
    };
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64;
    s.issue_document_grant_trusted(
        &a.document,
        &a.authority,
        &[
            DocumentOperation::Inspect,
            DocumentOperation::ReadText,
            DocumentOperation::StructuredEdit,
            DocumentOperation::Validate,
            DocumentOperation::Export,
        ],
        now + 20_000,
    )
    .unwrap();
    a
}

fn request(s: &BusinessStore, a: &DocumentAccess, intent: &str) -> PreparedEngineRequest {
    prepare_request_trusted(
        &s.read_document(a).unwrap(),
        intent,
        NumericCellEdit {
            sheet: "Synthetic".into(),
            cell: "A1".into(),
            expected: "2".into(),
            replacement: "5".into(),
        },
    )
    .unwrap()
}
fn confirmed(
    g: &EditedCandidateJournal<'_>,
    p: &PreparedEngineRequest,
    a: &DocumentAccess,
) -> Binding {
    let b = g.prepare(p, a).unwrap().binding;
    g.confirm_trusted(
        p,
        a,
        &Confirmation {
            binding: b.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    b
}
const DIFFERENT: &[u8] = b"original synthetic changed bytes, not an Office engine output";

use muyon_core::sqlite::Db;
fn physical(f:&Fixture)->Vec<(String,Vec<u8>)> {let root=PathBuf::from(format!("{}.blobs",f.path().display()));let mut v=Vec::new();for dir in ["objects","staging"] {for e in fs::read_dir(root.join(dir)).unwrap(){let e=e.unwrap();v.push((format!("{dir}/{:?}",e.file_name()),fs::read(e.path()).unwrap()));}}v.sort();v}
fn counts(db:&Db)->Vec<Vec<Option<String>>> {db.query("SELECT (SELECT COUNT(*) FROM blob_uploads),(SELECT COUNT(*) FROM blobs),(SELECT COUNT(*) FROM blob_references),(SELECT COUNT(*) FROM document_revisions)",&[]).unwrap()}
#[test] fn unpublished_delivery_requires_reconfirmation_deadline_and_no_cancel() {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let g=EditedCandidateJournal::initialize_trusted(&s).unwrap();let p=request(&s,&a,"delivery");let b=confirmed(&g,&p,&a);g.stage_candidate_trusted(&b,&a,DIFFERENT).unwrap();
 let fresh=access(&s,1,"fresh",1,"epoch-1");assert_eq!(g.candidate_bytes(&b,&fresh).unwrap_err(),ContractError::InvalidAuthority);assert!(g.lookup_original(&b,&fresh).unwrap().candidate.is_some());let p=request(&s,&fresh,"delivery");g.confirm_trusted(&p,&fresh,&Confirmation{binding:b.clone(),authority:fresh.authority.clone()}).unwrap();assert_eq!(g.candidate_bytes(&b,&fresh).unwrap(),DIFFERENT);assert_eq!(g.candidate_bytes(&b,&a).unwrap_err(),ContractError::InvalidAuthority);
 let db=Db::open(f.path().to_str().unwrap(),false,false).unwrap();db.exec("UPDATE edit_candidate_intents SET expires_ms='0' WHERE intent_id='delivery'",&[]).unwrap();assert_eq!(g.candidate_bytes(&b,&fresh).unwrap_err(),ContractError::InvalidAuthority);assert!(g.lookup_original(&b,&fresh).unwrap().candidate.is_some());
 g.confirm_trusted(&p,&fresh,&Confirmation{binding:b.clone(),authority:fresh.authority.clone()}).unwrap();g.cancel_trusted(&b).unwrap();assert_eq!(g.candidate_bytes(&b,&fresh).unwrap_err(),ContractError::Cancelled);assert!(g.lookup_original(&b,&fresh).unwrap().candidate.is_some());
}
#[test] fn expiry_column_is_real_and_tail_rolls_back_stage_to_unknown() {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let g=EditedCandidateJournal::initialize_trusted(&s).unwrap();let p=request(&s,&a,"tail");let b=confirmed(&g,&p,&a);let db=Db::open(f.path().to_str().unwrap(),false,false).unwrap();
 assert!(db.query("PRAGMA table_info(document_grants)",&[]).unwrap().iter().any(|r|r[1].as_deref()==Some("expires_at_ms")));
 db.exec("CREATE TRIGGER real_expiry AFTER UPDATE OF candidate_hex ON edit_candidate_intents WHEN NEW.candidate_hex IS NOT NULL BEGIN UPDATE document_grants SET expires_at_ms='0' WHERE grant_id='original'; SELECT CASE WHEN (SELECT expires_at_ms FROM document_grants WHERE grant_id='original')='0' THEN 1 ELSE RAISE(ABORT,'expiry mutation failed') END; END",&[]).unwrap();
 assert_eq!(g.stage_candidate_trusted(&b,&a,DIFFERENT).unwrap_err(),ContractError::Unknown);let v=g.lookup_original(&b,&a).unwrap();assert_eq!(v.state,EditedCandidateState::Unknown);assert!(v.candidate.is_none());assert_eq!(s.read_document(&a).unwrap().document.revision(),&Revision::new(1));let fresh=access(&s,1,"new",1,"epoch-1");let p=request(&s,&fresh,"tail");assert_eq!(g.confirm_trusted(&p,&fresh,&Confirmation{binding:b.clone(),authority:fresh.authority.clone()}).unwrap_err(),ContractError::Unknown);assert_eq!(g.stage_candidate_trusted(&b,&fresh,b"unrelated retry bytes").unwrap_err(),ContractError::Unknown);
}
#[test] fn frozen_request_or_source_title_corruption_never_delivers_or_stages() {
 for which in ["request","source"] {let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let g=EditedCandidateJournal::initialize_trusted(&s).unwrap();let p=request(&s,&a,"corrupt");let b=confirmed(&g,&p,&a);let db=Db::open(f.path().to_str().unwrap(),false,false).unwrap();
 let column=if which=="request" {"request_json"}else{"source_json"};let rows=db.query(&format!("SELECT {column} FROM edit_candidate_intents WHERE intent_id='corrupt'"),&[]).unwrap();let raw=rows[0][0].as_ref().unwrap();let changed=if which=="request" {raw.replace("\"replacement\":\"5\"","\"replacement\":\"7\"")}else{raw.replace("\"title\":\"Synthetic\"","\"title\":\"forged\"")};assert_ne!(&changed,raw);db.exec(&format!("UPDATE edit_candidate_intents SET {column}=? WHERE intent_id='corrupt'"),&[&changed]).unwrap();assert_eq!(g.lookup_original(&b,&a).unwrap_err(),ContractError::StorageCorrupt);assert_eq!(g.stage_candidate_trusted(&b,&a,DIFFERENT).unwrap_err(),ContractError::StorageCorrupt);assert_eq!(g.candidate_bytes(&b,&a).unwrap_err(),ContractError::StorageCorrupt);assert_eq!(g.commit_edited(&b,&a).unwrap_err(),ContractError::UnsupportedOperation);}
}
#[test] fn staging_only_writes_journal_and_cannot_borrow_copy_route() {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let g=EditedCandidateJournal::initialize_trusted(&s).unwrap();let p=request(&s,&a,"edited");let b=confirmed(&g,&p,&a);let db=Db::open(f.path().to_str().unwrap(),true,false).unwrap();let disk=physical(&f);let before=counts(&db);assert_eq!(g.stage_candidate_trusted(&b,&a,DIFFERENT).unwrap().state,EditedCandidateState::CandidateUnvalidated);assert_eq!(physical(&f),disk);assert_eq!(counts(&db),before);let copy=DocumentEditGateway::initialize_trusted(&s).unwrap();assert_eq!(copy.prepare_copy(&a,"edited").unwrap_err(),ContractError::IntentConflict);assert!(copy.commit_copy(&b,&a).is_err());assert_eq!(g.commit_edited(&b,&a).unwrap_err(),ContractError::UnsupportedOperation);
}
