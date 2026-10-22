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
#[test]
fn bridge_creates_real_private_new_bytes_pin_without_document_success() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let b = ready(&s, &a, "newbytes");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let db = db(&f);
    let refs = count(&db, "blob_references");
    let revisions = count(&db, "document_revisions");
    let uploads = count(&db, "blob_uploads");
    let before = g.lookup_original(&b, &a).unwrap().candidate.unwrap();
    let repeated = g
        .stage_candidate_trusted(&b, &a, b"new caller bytes must not replace original")
        .unwrap()
        .candidate
        .unwrap();
    assert_eq!(repeated, before);
    assert_eq!(g.candidate_bytes(&b, &a).unwrap(), DIFFERENT);
    let core = g.prepare_core_candidate_trusted(&b, &a).unwrap();
    assert_eq!(core.state, CandidateState::SealedUnvalidated);
    assert_eq!(core.original_binding, b);
    assert_ne!(
        core.expected_blob.digest,
        s.read_document(&a).unwrap().blob.digest
    );
    let objects = PathBuf::from(format!("{}.blobs", f.path().display())).join("objects");
    assert_eq!(
        fs::read(objects.join(&core.expected_blob.digest)).unwrap(),
        DIFFERENT
    );
    assert_eq!(
        fs::read(objects.join(&s.read_document(&a).unwrap().blob.digest)).unwrap(),
        SYNTHETIC
    );
    assert_eq!(count(&db, "blob_references"), refs);
    assert_eq!(count(&db, "document_revisions"), revisions);
    assert_eq!(count(&db, "blob_uploads"), uploads + 1);
    assert_eq!(count(&db, "blob_pins"), 1);
    assert_eq!(
        g.commit_edited(&b, &a).unwrap_err(),
        ContractError::UnsupportedOperation
    );
    let duplicate = g.prepare_core_candidate_trusted(&b, &a).unwrap();
    assert_eq!(duplicate, core);
    assert_eq!(count(&db, "blob_uploads"), uploads + 1);
}
#[test]
fn restart_and_fresh_grant_query_original_without_confirmation_or_repreparation() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let b = ready(&s, &a, "restart");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let original = g.prepare_core_candidate_trusted(&b, &a).unwrap();
    drop(s);
    let s = f.reopen("epoch-2");
    assert_eq!(
        s.reconcile_blobs_after_restart().unwrap().aborted_uploads,
        0
    );
    let a = access(&s, 1, "new-read-edit", 1, "epoch-2");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    assert_eq!(g.lookup_core_candidate(&b, &a).unwrap(), original);
    assert_eq!(g.prepare_core_candidate_trusted(&b, &a).unwrap(), original);
    assert_eq!(count(&db(&f), "blob_uploads"), 2);
    assert_eq!(
        g.candidate_bytes(&b, &a).unwrap_err(),
        ContractError::InvalidAuthority
    );
}
#[test]
fn gateway_claim_with_no_core_reservation_stays_unknown_without_retry() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let b = ready(&s, &a, "absent");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let db = db(&f);
    db.exec("CREATE TRIGGER fail_core_reserve BEFORE INSERT ON document_candidates_v1 BEGIN SELECT RAISE(ABORT,'synthetic core reserve failure'); END",&[]).unwrap();
    assert_eq!(
        g.prepare_core_candidate_trusted(&b, &a).unwrap_err(),
        ContractError::Unknown
    );
    assert_eq!(count(&db, "blob_uploads"), 1);
    db.exec("DROP TRIGGER fail_core_reserve", &[]).unwrap();
    let status = g.lookup_core_candidate(&b, &a).unwrap();
    assert_eq!(status.state, CandidateState::PreparationUnknown);
    assert_eq!(g.prepare_core_candidate_trusted(&b, &a).unwrap(), status);
    assert_eq!(count(&db, "blob_uploads"), 1);
}
#[test]
fn core_late_seal_failure_retains_pin_and_unknown_is_never_replayed() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let b = ready(&s, &a, "late");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let db = db(&f);
    db.exec("CREATE TRIGGER fail_core_seal BEFORE UPDATE OF state ON document_candidates_v1 WHEN NEW.state='sealed_unvalidated' BEGIN SELECT RAISE(ABORT,'synthetic seal fault'); END",&[]).unwrap();
    assert_eq!(
        g.prepare_core_candidate_trusted(&b, &a).unwrap_err(),
        ContractError::Unknown
    );
    assert_eq!(count(&db, "blob_pins"), 1);
    db.exec("DROP TRIGGER fail_core_seal", &[]).unwrap();
    let status = g.lookup_core_candidate(&b, &a).unwrap();
    assert_eq!(status.state, CandidateState::PreparationUnknown);
    assert_eq!(g.prepare_core_candidate_trusted(&b, &a).unwrap(), status);
    assert_eq!(count(&db, "blob_uploads"), 2);
    assert_eq!(count(&db, "document_revisions"), 1);
}
#[test]
fn cancellation_and_claim_tail_revocation_block_before_any_core_file_work() {
    for cancel in [false, true] {
        let f = Fixture::new();
        let s = f.store();
        let a = access(&s, 1, "original", 1, "epoch-1");
        let b = ready(&s, &a, "blocked");
        let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
        let db = db(&f);
        if cancel {
            g.cancel_trusted(&b).unwrap();
            assert_eq!(
                g.prepare_core_candidate_trusted(&b, &a).unwrap_err(),
                ContractError::Cancelled
            );
        } else {
            db.exec("CREATE TRIGGER revoke_bridge AFTER INSERT ON edit_candidate_core_claims BEGIN UPDATE document_grants SET active=0 WHERE grant_id='original'; END",&[]).unwrap();
            assert_eq!(
                g.prepare_core_candidate_trusted(&b, &a).unwrap_err(),
                ContractError::InvalidAuthority
            );
        }
        assert_eq!(count(&db, "blob_uploads"), 1);
        assert_eq!(count(&db, "document_candidates_v1"), 0);
        assert_eq!(count(&db, "edit_candidate_core_claims"), 0);
    }
}
#[test]
fn bridge_checks_core_operation_identity_and_claim_corruption() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let b = ready(&s, &a, "identity");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let core = g.prepare_core_candidate_trusted(&b, &a).unwrap();
    let db = db(&f);
    let text = db
        .query(
            "SELECT payload FROM document_candidates_v1 WHERE candidate_id=?",
            &[&core.candidate_id],
        )
        .unwrap();
    let mut payload: serde_json::Value =
        serde_json::from_str(text[0][0].as_ref().unwrap()).unwrap();
    payload["operation_id"] = "wrong-operation".into();
    db.exec(
        "UPDATE document_candidates_v1 SET payload=? WHERE candidate_id=?",
        &[&payload.to_string(), &core.candidate_id],
    )
    .unwrap();
    assert_eq!(
        g.lookup_core_candidate(&b, &a).unwrap_err(),
        ContractError::BindingMismatch
    );
    payload["operation_id"] = core.operation_id.into();
    db.exec(
        "UPDATE document_candidates_v1 SET payload=? WHERE candidate_id=?",
        &[&payload.to_string(), &core.candidate_id],
    )
    .unwrap();
    db.exec("UPDATE edit_candidate_core_claims SET candidate_id='wrong-candidate' WHERE intent_id='identity'",&[]).unwrap();
    assert_eq!(
        g.lookup_core_candidate(&b, &a).unwrap_err(),
        ContractError::StorageCorrupt
    );
}

#[test]
fn actual_core_pin_then_expiry_is_unknown_and_fresh_grant_cannot_resume() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let b = ready(&s, &a, "expiry");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let db = db(&f);
    db.exec("CREATE TRIGGER expire_after_core_pin AFTER UPDATE ON blob_uploads WHEN NEW.state='pinned' BEGIN UPDATE document_grants SET expires_at_ms='0' WHERE grant_id='original'; END",&[]).unwrap();
    assert_eq!(
        g.prepare_core_candidate_trusted(&b, &a).unwrap_err(),
        ContractError::Unknown
    );
    assert_eq!(count(&db, "blob_pins"), 1);
    assert_eq!(count(&db, "document_revisions"), 1);
    let fresh = access(&s, 1, "fresh-query", 1, "epoch-1");
    let observed = g.lookup_core_candidate(&b, &fresh).unwrap();
    assert_eq!(observed.state, CandidateState::PreparationUnknown);
    assert_eq!(
        g.prepare_core_candidate_trusted(&b, &fresh).unwrap(),
        observed
    );
    assert_eq!(count(&db, "blob_uploads"), 2);
}

#[test]
fn first_core_preparation_requires_fresh_confirmation_and_a_stored_candidate() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let p = request(&s, &a, "not-staged");
    let b = confirmed(&g, &p, &a);
    assert_eq!(
        g.prepare_core_candidate_trusted(&b, &a).unwrap_err(),
        ContractError::InvalidAuthority
    );
    assert_eq!(count(&db(&f), "blob_uploads"), 1);
    g.stage_candidate_trusted(&b, &a, DIFFERENT).unwrap();
    let fresh = access(&s, 1, "fresh", 1, "epoch-1");
    let p = request(&s, &fresh, "not-staged");
    g.prepare(&p, &fresh).unwrap();
    assert_eq!(
        g.prepare_core_candidate_trusted(&b, &fresh).unwrap_err(),
        ContractError::InvalidAuthority
    );
    assert_eq!(count(&db(&f), "document_candidates_v1"), 0);
    confirmed(&g, &p, &fresh);
    assert_eq!(
        g.prepare_core_candidate_trusted(&b, &fresh).unwrap().state,
        CandidateState::SealedUnvalidated
    );
}
