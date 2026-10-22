//! Original synthetic bytes only; no Office engine, model, network or user files.
use muyon_core::{
    blobs::BlobKind,
    business::BusinessStore,
    contract::*,
    document_edit::{gateway::*, Binding, Confirmation},
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
            "muyon-edit-gateway-{}-{}",
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
        self.store_with_format(DocumentFormat::Unknown)
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
        DocumentFormat::Unknown,
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
fn ready(g: &DocumentEditGateway<'_>, a: &DocumentAccess, intent: &str) -> Binding {
    let b = g.prepare_copy(a, intent).unwrap().binding;
    g.confirm_trusted(
        &b,
        a,
        &Confirmation {
            binding: b.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    assert_eq!(
        g.copy_candidate(&b, a).unwrap().state,
        DurableState::Candidate
    );
    assert_eq!(
        g.validate_copy(&b, a).unwrap().state,
        DurableState::Validated
    );
    b
}
#[test]
fn prepare_is_durable_without_confirmation_or_engine_success() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "grant", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = g.prepare_copy(&a, "intent").unwrap().binding;
    assert_eq!(
        g.copy_candidate(&b, &a).unwrap_err(),
        ContractError::InvalidAuthority
    );
    assert_eq!(
        g.apply_engine_patch(&b, &a).unwrap_err(),
        ContractError::UnsupportedOperation
    );
    drop(g);
    drop(s);
    let s = f.reopen("epoch-2");
    let a = access(&s, 1, "read-after-restart", 1, "epoch-2");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    assert_eq!(
        g.lookup_original(&b, &a).unwrap().state,
        DurableState::Prepared
    );
}
#[test]
fn candidate_and_original_receipt_survive_restart_without_replay() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "grant", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = ready(&g, &a, "intent");
    assert_eq!(g.candidate_bytes(&b, &a).unwrap(), SYNTHETIC);
    let committed = g.commit_copy(&b, &a).unwrap();
    assert_eq!(committed.state, DurableState::Committed);
    let receipt = committed.receipt.unwrap();
    assert_eq!(receipt.operation, CopyOperation::ByteIdenticalCopy);
    assert_eq!(receipt.result.document.revision(), &Revision::new(2));
    drop(g);
    drop(s);
    let s = f.reopen("epoch-2");
    let a = access(&s, 2, "query", 1, "epoch-2");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    assert_eq!(
        g.lookup_original(&b, &a).unwrap().receipt,
        Some(receipt.clone())
    );
    assert_eq!(g.commit_copy(&b, &a).unwrap().receipt, Some(receipt));
    assert_eq!(g.candidate_bytes(&b, &a).unwrap(), SYNTHETIC);
}
#[test]
fn two_original_intents_cannot_publish_the_same_source_revision() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "grant-a", 1, "epoch-1");
    let other = access(&s, 1, "grant-b", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = ready(&g, &a, "first");
    let second = ready(&g, &other, "second");
    g.commit_copy(&b, &a).unwrap();
    assert_eq!(
        g.commit_copy(&second, &other).unwrap_err(),
        ContractError::RevisionConflict
    );
    let fresh = access(&s, 2, "query", 1, "epoch-1");
    let view = g.lookup_original(&second, &fresh).unwrap();
    assert_eq!(view.state, DurableState::Conflict);
    assert!(view.candidate.is_some());
    assert!(view.receipt.is_none());
}
#[test]
fn confirmation_is_exact_and_revocation_stops_publication() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "grant", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = g.prepare_copy(&a, "intent").unwrap().binding;
    let mut old = b.clone();
    old.intent_id = "other".into();
    assert_eq!(
        g.confirm_trusted(
            &b,
            &a,
            &Confirmation {
                binding: old,
                authority: a.authority.clone()
            }
        )
        .unwrap_err(),
        ContractError::BindingMismatch
    );
    g.confirm_trusted(
        &b,
        &a,
        &Confirmation {
            binding: b.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    g.copy_candidate(&b, &a).unwrap();
    g.validate_copy(&b, &a).unwrap();
    s.revoke_document_grant_trusted(&a.authority).unwrap();
    assert_eq!(
        g.commit_copy(&b, &a).unwrap_err(),
        ContractError::InvalidAuthority
    );
}
#[test]
fn cancellation_is_not_rollback_and_cannot_erase_a_committed_receipt() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "grant", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = ready(&g, &a, "cancel");
    g.cancel_trusted(&b).unwrap();
    assert_eq!(g.commit_copy(&b, &a).unwrap_err(), ContractError::Cancelled);
    let b = ready(&g, &a, "publish");
    let receipt = g.commit_copy(&b, &a).unwrap().receipt;
    g.cancel_trusted(&b).unwrap();
    let query = access(&s, 2, "query", 1, "epoch-1");
    let v = g.lookup_original(&b, &query).unwrap();
    assert!(v.cancel_requested);
    assert_eq!(v.state, DurableState::Committed);
    assert_eq!(v.receipt, receipt);
}
#[test]
fn duplicate_intent_binds_original_and_never_creates_second_upload() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "grant", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = ready(&g, &a, "intent");
    assert_eq!(
        g.copy_candidate(&b, &a).unwrap().state,
        DurableState::Validated
    );
    let mut wrong = b.clone();
    wrong.patch_digest = [33; 32];
    assert_eq!(
        g.lookup_original(&wrong, &a).unwrap_err(),
        ContractError::IntentConflict
    );
}

#[test]
fn candidate_reopens_but_new_effect_requires_an_explicit_fresh_confirmation() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = g.prepare_copy(&a, "restart-candidate").unwrap().binding;
    g.confirm_trusted(
        &b,
        &a,
        &Confirmation {
            binding: b.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    g.copy_candidate(&b, &a).unwrap();
    drop(g);
    drop(s);
    let s = f.reopen("epoch-2");
    let a = access(&s, 1, "fresh", 1, "epoch-2");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    assert_eq!(
        g.lookup_original(&b, &a).unwrap().state,
        DurableState::Candidate
    );
    assert_eq!(g.candidate_bytes(&b, &a).unwrap(), SYNTHETIC);
    assert_eq!(
        g.validate_copy(&b, &a).unwrap_err(),
        ContractError::InvalidAuthority
    );
    g.confirm_trusted(
        &b,
        &a,
        &Confirmation {
            binding: b.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    g.validate_copy(&b, &a).unwrap();
    assert_eq!(
        g.commit_copy(&b, &a).unwrap().state,
        DurableState::Committed
    );
}
#[test]
fn late_copy_duplicate_is_only_an_authorized_original_result_query() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = ready(&g, &a, "intent");
    let receipt = g.commit_copy(&b, &a).unwrap().receipt;
    let query = access(&s, 2, "query", 1, "epoch-1");
    assert_eq!(g.copy_candidate(&b, &query).unwrap().receipt, receipt);
}
#[test]
fn receipt_tail_failure_rolls_back_cas_and_restart_unknown_never_replays() {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = ready(&g, &a, "original-intent");
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    db.exec("CREATE TRIGGER fail_edit_receipt BEFORE UPDATE OF receipt_json ON edit_journal_intents WHEN NEW.receipt_json IS NOT NULL BEGIN SELECT RAISE(ABORT,'synthetic receipt failure'); END",&[]).unwrap();
    assert_eq!(g.commit_copy(&b, &a).unwrap_err(), ContractError::Unknown);
    assert_eq!(
        s.read_document(&a).unwrap().document.revision(),
        &Revision::new(1)
    );
    let before = db.query("SELECT COUNT(*) FROM blob_uploads", &[]).unwrap();
    assert_eq!(
        g.lookup_original(&b, &a).unwrap().state,
        DurableState::Unknown
    );
    assert_eq!(g.commit_copy(&b, &a).unwrap_err(), ContractError::Unknown);
    assert_eq!(
        db.query("SELECT COUNT(*) FROM blob_uploads", &[]).unwrap(),
        before
    );
    drop(db);
    drop(g);
    drop(s);
    let s = f.reopen("epoch-2");
    let a = access(&s, 1, "query", 1, "epoch-2");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    assert_eq!(
        g.lookup_original(&b, &a).unwrap().state,
        DurableState::Unknown
    );
    assert!(g.lookup_original(&b, &a).unwrap().receipt.is_none());
    assert_eq!(g.commit_copy(&b, &a).unwrap_err(), ContractError::Unknown);
    assert_eq!(
        g.copy_candidate(&b, &a).unwrap_err(),
        ContractError::Unknown
    );
}
#[test]
fn corrupt_candidate_never_validates_or_publishes() {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = g.prepare_copy(&a, "tamper").unwrap().binding;
    g.confirm_trusted(
        &b,
        &a,
        &Confirmation {
            binding: b.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    g.copy_candidate(&b, &a).unwrap();
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    db.exec("UPDATE edit_journal_intents SET candidate_hex=lower(hex('forged')) WHERE intent_id='tamper'",&[]).unwrap();
    assert_eq!(
        g.candidate_bytes(&b, &a).unwrap_err(),
        ContractError::BindingMismatch
    );
    assert_eq!(
        g.validate_copy(&b, &a).unwrap_err(),
        ContractError::BindingMismatch
    );
    assert!(g.commit_copy(&b, &a).is_err());
    assert_eq!(
        s.read_document(&a).unwrap().document.revision(),
        &Revision::new(1)
    );
    g.cancel_trusted(&b).unwrap();
}

#[test]
fn grant_revoked_or_expired_by_last_receipt_write_rolls_back_the_entire_publish() {
    use muyon_core::sqlite::Db;
    for change in ["active=0", "expires_at_ms='0'", "generation='2'"] {
        let f = Fixture::new();
        let s = f.store();
        let a = access(&s, 1, "original", 1, "epoch-1");
        let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
        let b = ready(&g, &a, "tail");
        let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
        db.exec(&format!("CREATE TRIGGER revoke_at_receipt AFTER UPDATE OF receipt_json ON edit_journal_intents WHEN NEW.receipt_json IS NOT NULL BEGIN UPDATE document_grants SET {change} WHERE grant_id='original'; END"),&[]).unwrap();
        assert_eq!(
            g.commit_copy(&b, &a).unwrap_err(),
            ContractError::InvalidAuthority
        );
        assert_eq!(
            s.read_document(&a).unwrap().document.revision(),
            &Revision::new(1)
        );
        assert_eq!(
            db.query("SELECT COUNT(*) FROM document_revisions", &[])
                .unwrap()[0][0]
                .as_deref(),
            Some("1")
        );
        let v = g.lookup_original(&b, &a).unwrap();
        assert!(v.receipt.is_none());
        assert_ne!(v.state, DurableState::Committed);
    }
}
#[test]
fn a_copy_claim_that_cannot_store_its_candidate_is_query_only_after_restart() {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = g.prepare_copy(&a, "pending-copy").unwrap().binding;
    g.confirm_trusted(
        &b,
        &a,
        &Confirmation {
            binding: b.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    db.exec("CREATE TRIGGER deny_candidate BEFORE UPDATE OF candidate_hex ON edit_journal_intents WHEN NEW.candidate_hex IS NOT NULL BEGIN SELECT RAISE(ABORT,'synthetic candidate failure'); END",&[]).unwrap();
    assert_eq!(
        g.copy_candidate(&b, &a).unwrap_err(),
        ContractError::Unknown
    );
    assert_eq!(
        g.lookup_original(&b, &a).unwrap().state,
        DurableState::Unknown
    );
    drop(db);
    drop(g);
    drop(s);
    let s = f.reopen("epoch-2");
    let a = access(&s, 1, "query", 1, "epoch-2");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let v = g.lookup_original(&b, &a).unwrap();
    assert_eq!(v.state, DurableState::Unknown);
    assert!(v.candidate.is_none());
    assert_eq!(
        g.copy_candidate(&b, &a).unwrap_err(),
        ContractError::Unknown
    );
    assert_eq!(
        g.confirm_trusted(
            &b,
            &a,
            &Confirmation {
                binding: b.clone(),
                authority: a.authority.clone()
            }
        )
        .unwrap_err(),
        ContractError::Unknown
    );
}

#[test]
fn corrupt_oversize_persisted_metadata_is_rejected_before_payload_decode() {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = g.prepare_copy(&a, "oversize").unwrap().binding;
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    let rows = db
        .query(
            "SELECT source_json FROM edit_journal_intents WHERE intent_id='oversize'",
            &[],
        )
        .unwrap();
    let mut json: serde_json::Value = serde_json::from_str(rows[0][0].as_deref().unwrap()).unwrap();
    json["title"] = serde_json::json!("x".repeat(9000));
    db.exec(
        "UPDATE edit_journal_intents SET source_json=? WHERE intent_id='oversize'",
        &[&json.to_string()],
    )
    .unwrap();
    assert_eq!(
        g.lookup_original(&b, &a).unwrap_err(),
        ContractError::StorageCorrupt
    );
}

#[test]
fn live_engine_envelope_cannot_be_confused_with_a_validated_copy_intent() {
    use muyon_core::document_edit::engine_protocol::*;
    let f = Fixture::new();
    let s = f.store_with_format(DocumentFormat::Xlsx);
    let a = DocumentAccess {
        document: DocumentRef::new(
            reference(1).scope().clone(),
            "document",
            Revision::new(1),
            DocumentFormat::Xlsx,
        )
        .unwrap(),
        authority: AuthorityBinding {
            grant_id: "numeric".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch-1".into(),
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
        ],
        now + 20_000,
    )
    .unwrap();
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    g.prepare_copy(&a, "same-intent").unwrap();
    let request = g
        .prepare_numeric_cell_request(
            &a,
            "same-intent",
            NumericCellEdit {
                sheet: "Original".into(),
                cell: "A1".into(),
                expected: "2".into(),
                replacement: "5.0".into(),
            },
        )
        .unwrap();
    let envelope: serde_json::Value = serde_json::from_str(request.request_json()).unwrap();
    assert_eq!(
        envelope["source_sha256"],
        s.read_document(&a).unwrap().blob.digest
    );
    assert_eq!(envelope["base_revision"], "1");
    assert_eq!(envelope["file_id"], "document");
    assert_eq!(
        g.commit_copy(request.binding(), &a).unwrap_err(),
        ContractError::IntentConflict
    );
    assert_eq!(
        g.validate_copy(request.binding(), &a).unwrap_err(),
        ContractError::IntentConflict
    );
    assert_eq!(
        g.apply_engine_patch(request.binding(), &a).unwrap_err(),
        ContractError::UnsupportedOperation
    );
    s.revoke_document_grant_trusted(&a.authority).unwrap();
    assert_eq!(
        g.prepare_numeric_cell_request(
            &a,
            "other",
            NumericCellEdit {
                sheet: "Original".into(),
                cell: "A1".into(),
                expected: "2".into(),
                replacement: "5".into()
            }
        )
        .unwrap_err(),
        ContractError::InvalidAuthority
    );
}

#[test]
fn frozen_source_title_cannot_change_without_changing_the_reviewed_copy_plan() {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = g.prepare_copy(&a, "frozen-plan").unwrap().binding;
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    let rows = db
        .query(
            "SELECT source_json FROM edit_journal_intents WHERE intent_id='frozen-plan'",
            &[],
        )
        .unwrap();
    let mut json: serde_json::Value = serde_json::from_str(rows[0][0].as_deref().unwrap()).unwrap();
    json["title"] = serde_json::json!("unreviewed title");
    db.exec(
        "UPDATE edit_journal_intents SET source_json=? WHERE intent_id='frozen-plan'",
        &[&json.to_string()],
    )
    .unwrap();
    assert_eq!(
        g.confirm_trusted(
            &b,
            &a,
            &Confirmation {
                binding: b.clone(),
                authority: a.authority.clone()
            }
        )
        .unwrap_err(),
        ContractError::StorageCorrupt
    );
}

#[test]
fn a_different_hash_candidate_cannot_borrow_the_copy_only_publication_route() {
    use muyon_core::sqlite::Db;
    use sha2::{Digest, Sha256};
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = ready(&g, &a, "not-an-edit-route");
    let mut changed = SYNTHETIC.to_vec();
    changed[0] = b'X';
    let bytes_hex: String = changed.iter().map(|b| format!("{b:02x}")).collect();
    let digest: String = Sha256::digest(&changed)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    db.exec("UPDATE edit_journal_intents SET candidate_hex=?,candidate_digest=? WHERE intent_id='not-an-edit-route'",&[&bytes_hex,&digest]).unwrap();
    assert_eq!(
        g.commit_copy(&b, &a).unwrap_err(),
        ContractError::BindingMismatch
    );
    assert_eq!(
        s.read_document(&a).unwrap().document.revision(),
        &Revision::new(1)
    );
    assert_eq!(
        g.apply_engine_patch(&b, &a).unwrap_err(),
        ContractError::UnsupportedOperation
    );
}

#[test]
fn copy_publication_uses_new_metadata_reference_without_new_upload_or_staging_files() {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = ready(&g, &a, "clone-only");
    let db = Db::open(f.path().to_str().unwrap(), true, false).unwrap();
    let uploads = db.query("SELECT COUNT(*) FROM blob_uploads", &[]).unwrap();
    let references = db
        .query("SELECT COUNT(*) FROM blob_references", &[])
        .unwrap()[0][0]
        .as_ref()
        .unwrap()
        .parse::<usize>()
        .unwrap();
    let root = PathBuf::from(format!("{}.blobs", f.path().display()));
    let entries = |name: &str| {
        let mut names: Vec<_> = fs::read_dir(root.join(name))
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        names.sort();
        names
    };
    let objects = entries("objects");
    let staging = entries("staging");
    let receipt = g.commit_copy(&b, &a).unwrap().receipt.unwrap();
    assert_eq!(receipt.operation, CopyOperation::ByteIdenticalCopy);
    assert_eq!(
        receipt.result.blob,
        s.read_document(&access(&s, 2, "after", 1, "epoch-1"))
            .unwrap()
            .blob
    );
    assert_eq!(
        db.query("SELECT COUNT(*) FROM blob_uploads", &[]).unwrap(),
        uploads
    );
    assert_eq!(entries("objects"), objects);
    assert_eq!(entries("staging"), staging);
    assert_eq!(
        db.query("SELECT COUNT(*) FROM blob_references", &[])
            .unwrap()[0][0]
            .as_ref()
            .unwrap()
            .parse::<usize>()
            .unwrap(),
        references + 1
    );
}

#[test]
fn reading_a_newer_different_blob_does_not_authorize_old_candidate_bytes() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = ready(&g, &a, "old-candidate");
    g.commit_copy(&b, &a).unwrap();
    let upload = s.begin_upload("project").unwrap();
    s.append_chunk(
        &upload.upload_id,
        b"newer synthetic content; not an engine output",
    )
    .unwrap();
    let finished = s
        .finish_blob(&upload.upload_id, BlobKind::Document)
        .unwrap();
    s.publish_document_revision_trusted(
        &reference(2),
        "New revision",
        DocumentFormat::Unknown,
        &finished,
    )
    .unwrap();
    let current = access(&s, 3, "only-current", 1, "epoch-1");
    assert_eq!(
        g.candidate_bytes(&b, &current).unwrap_err(),
        ContractError::InvalidAuthority
    );
    // Original intent metadata remains queryable, but it is not byte delivery authority.
    assert_eq!(
        g.lookup_original(&b, &current).unwrap().state,
        DurableState::Committed
    );
}

#[test]
fn persisted_receipt_title_must_match_frozen_reviewed_source() {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = ready(&g, &a, "receipt-title");
    let receipt = g.commit_copy(&b, &a).unwrap().receipt.unwrap();
    assert_eq!(receipt.result.title, "Synthetic");
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    let row = db
        .query(
            "SELECT receipt_json FROM edit_journal_intents WHERE intent_id='receipt-title'",
            &[],
        )
        .unwrap();
    let mut corrupted: serde_json::Value =
        serde_json::from_str(row[0][0].as_ref().unwrap()).unwrap();
    corrupted["title"] = serde_json::json!("unreviewed-forged-title");
    db.exec(
        "UPDATE edit_journal_intents SET receipt_json=? WHERE intent_id='receipt-title'",
        &[&corrupted.to_string()],
    )
    .unwrap();
    let current = access(&s, 2, "inspect-current", 1, "epoch-1");
    assert_eq!(
        g.lookup_original(&b, &current).unwrap_err(),
        ContractError::StorageCorrupt
    );
    assert_eq!(s.read_document(&current).unwrap().title, "Synthetic");
}
