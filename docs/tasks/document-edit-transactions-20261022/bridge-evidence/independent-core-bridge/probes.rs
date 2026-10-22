//! Original synthetic bytes only; no Office engine, model, network or user files.
use muyon_core::{
    blobs::BlobKind,
    business::BusinessStore,
    contract::*,
    document_edit::{
        edited_candidates::*,
        engine_protocol::{prepare_request_trusted, NumericCellEdit, PreparedEngineRequest},
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
            "muyon-core-bridge-{}-{}",
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

use muyon_core::documents::CandidateState;
use muyon_core::sqlite::Db;
fn ready(s: &BusinessStore, a: &DocumentAccess, intent: &str) -> Binding {
    let g = EditedCandidateJournal::initialize_trusted(s).unwrap();
    let p = request(s, a, intent);
    let b = confirmed(&g, &p, a);
    g.stage_candidate_trusted(&b, a, DIFFERENT).unwrap();
    b
}
fn db(f: &Fixture) -> Db {
    Db::open(f.path().to_str().unwrap(), false, false).unwrap()
}
fn count(db: &Db, table: &str) -> usize {
    db.query(&format!("SELECT COUNT(*) FROM {table}"), &[])
        .unwrap()[0][0]
        .as_deref()
        .unwrap()
        .parse()
        .unwrap()
}

#[test] fn fresh_reconfirmation_cannot_replay_claim_whose_core_row_is_absent() {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let b=ready(&s,&a,"orphan");let g=EditedCandidateJournal::initialize_trusted(&s).unwrap();let db=db(&f);db.exec("CREATE TRIGGER deny_core BEFORE INSERT ON document_candidates_v1 BEGIN SELECT RAISE(ABORT,'independent reserve fault'); END",&[]).unwrap();assert_eq!(g.prepare_core_candidate_trusted(&b,&a).unwrap_err(),ContractError::Unknown);db.exec("DROP TRIGGER deny_core",&[]).unwrap();let uploads=count(&db,"blob_uploads");let fresh=access(&s,1,"fresh",1,"epoch-1");let p=request(&s,&fresh,"orphan");g.confirm_trusted(&p,&fresh,&Confirmation{binding:b.clone(),authority:fresh.authority.clone()}).unwrap();assert_eq!(g.prepare_core_candidate_trusted(&b,&fresh).unwrap().state,CandidateState::PreparationUnknown);assert_eq!(count(&db,"blob_uploads"),uploads);assert_eq!(count(&db,"document_candidates_v1"),0);
}
#[test] fn missing_real_pin_is_unknown_and_duplicate_cannot_repin() {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let b=ready(&s,&a,"missingpin");let g=EditedCandidateJournal::initialize_trusted(&s).unwrap();let core=g.prepare_core_candidate_trusted(&b,&a).unwrap();assert_eq!(core.state,CandidateState::SealedUnvalidated);let db=db(&f);let uploads=count(&db,"blob_uploads");db.exec("DELETE FROM blob_pins WHERE kind='upload'",&[]).unwrap();assert_eq!(g.lookup_core_candidate(&b,&a).unwrap().state,CandidateState::PreparationUnknown);assert_eq!(g.prepare_core_candidate_trusted(&b,&a).unwrap().state,CandidateState::PreparationUnknown);assert_eq!(count(&db,"blob_uploads"),uploads);assert_eq!(count(&db,"blob_pins"),0);
}
#[test] fn full_claim_and_real_core_expected_hash_are_bound() {
 for column in ["operation_id","expected_digest","expected_length","candidate_id"] {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let b=ready(&s,&a,"tamper");let g=EditedCandidateJournal::initialize_trusted(&s).unwrap();g.prepare_core_candidate_trusted(&b,&a).unwrap();let db=db(&f);let uploads=count(&db,"blob_uploads");let value=if column=="expected_digest" {"b".repeat(64)}else{"wrong".into()};db.exec(&format!("UPDATE edit_candidate_core_claims SET {column}=? WHERE intent_id='tamper'"),&[&value]).unwrap();assert_eq!(g.lookup_core_candidate(&b,&a).unwrap_err(),ContractError::StorageCorrupt);assert_eq!(count(&db,"blob_uploads"),uploads);
 }
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let b=ready(&s,&a,"corehash");let g=EditedCandidateJournal::initialize_trusted(&s).unwrap();let core=g.prepare_core_candidate_trusted(&b,&a).unwrap();let db=db(&f);let rows=db.query("SELECT payload FROM document_candidates_v1 WHERE candidate_id=?",&[&core.candidate_id]).unwrap();let mut p:serde_json::Value=serde_json::from_str(rows[0][0].as_ref().unwrap()).unwrap();p["expected_blob"]["digest"]="b".repeat(64).into();db.exec("UPDATE document_candidates_v1 SET payload=? WHERE candidate_id=?",&[&p.to_string(),&core.candidate_id]).unwrap();assert_eq!(g.lookup_core_candidate(&b,&a).unwrap_err(),ContractError::BindingMismatch);
}
#[test] fn cancellation_observed_after_real_seal_preserves_private_fact_without_publication() {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let b=ready(&s,&a,"cancel-late");let g=EditedCandidateJournal::initialize_trusted(&s).unwrap();let db=db(&f);let refs=count(&db,"blob_references");db.exec("CREATE TRIGGER cancel_after_seal AFTER UPDATE OF state ON document_candidates_v1 WHEN NEW.state='sealed_unvalidated' BEGIN UPDATE edit_candidate_intents SET cancel_requested=1,state='cancelled' WHERE intent_id='cancel-late'; END",&[]).unwrap();assert_eq!(g.prepare_core_candidate_trusted(&b,&a).unwrap_err(),ContractError::Unknown);assert_eq!(count(&db,"blob_pins"),1);let actual=g.lookup_core_candidate(&b,&a).unwrap();assert_eq!(actual.state,CandidateState::SealedUnvalidated);let uploads=count(&db,"blob_uploads");assert_eq!(g.prepare_core_candidate_trusted(&b,&a).unwrap(),actual);assert_eq!(count(&db,"blob_uploads"),uploads);assert_eq!(g.candidate_bytes(&b,&a).unwrap_err(),ContractError::Cancelled);assert_eq!(g.commit_edited(&b,&a).unwrap_err(),ContractError::UnsupportedOperation);assert_eq!(count(&db,"blob_references"),refs);assert_eq!(count(&db,"document_revisions"),1);assert_eq!(s.read_document(&a).unwrap().document.revision(),&Revision::new(1));
}
