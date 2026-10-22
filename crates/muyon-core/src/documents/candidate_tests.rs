//! Original synthetic candidate bytes only; never a production validator.
use super::{storage_tests::Fixture, *};
use crate::{business::BusinessStore, contract::*, sqlite::Db};
use sha2::{Digest, Sha256};
use std::{fs, time::{SystemTime, UNIX_EPOCH}};
const NEW_BYTES: &[u8] = b"%PDF-1.4\nNEW ORIGINAL SYNTHETIC CANDIDATE; not engine-validated\n%%EOF\n";
fn expiry() -> u64 { SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64 + 20_000 }
fn setup() -> (Fixture, BusinessStore, DocumentAccess) {
    let f = Fixture::new(); let (store, mut access) = f.setup();
    access.authority.generation = access.authority.generation.next().unwrap();
    store.issue_document_grant_trusted(&access.document, &access.authority, &[DocumentOperation::Inspect, DocumentOperation::ReadText, DocumentOperation::StructuredEdit], expiry()).unwrap();
    store.initialize_document_candidates_trusted().unwrap();
    (f, store, access)
}
#[test]
fn new_bytes_are_private_sealed_unvalidated_and_never_publish() {
    let (_f, store, access) = setup(); let original = store.read_document(&access).unwrap();
    let status = store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).unwrap();
    assert_eq!(status.state, CandidateState::SealedUnvalidated);
    assert_ne!(status.expected_blob.digest, original.blob.digest);
    assert_eq!(fs::read(store.root_dir().join("objects").join(&status.expected_blob.digest)).unwrap(), NEW_BYTES);
    assert_eq!(store.read_document(&access).unwrap(), original);
    let tx = store.database().transaction().unwrap();
    assert_eq!(store.document_publish_candidate_in_transaction(&tx, &access, "candidate"), Err(ContractError::UnsupportedOperation));
    drop(tx);
    assert_eq!(store.database().query("SELECT * FROM document_revisions", &[]).unwrap().len(), 1);
    assert_eq!(store.database().query("SELECT * FROM blob_references", &[]).unwrap().len(), 1);
}
#[test]
fn duplicate_preparation_is_query_only_and_conflicting_binding_is_rejected() {
    let (_f, store, access) = setup();
    let one = store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).unwrap();
    let uploads = store.database().query("SELECT * FROM blob_uploads ORDER BY upload_id", &[]).unwrap();
    assert_eq!(store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).unwrap(), one);
    assert_eq!(store.database().query("SELECT * FROM blob_uploads ORDER BY upload_id", &[]).unwrap(), uploads);
    assert_eq!(store.prepare_document_candidate_trusted(&access, "candidate", "different", NEW_BYTES), Err(ContractError::IntentConflict));
    assert_eq!(store.prepare_document_candidate_trusted(&access, "candidate", "operation", b"different bytes"), Err(ContractError::IntentConflict));
    store.database().exec("UPDATE document_candidates_v1 SET state='preparation_unknown'", &[]).unwrap();
    assert_eq!(store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).unwrap().state, CandidateState::PreparationUnknown);
    assert_eq!(store.database().query("SELECT * FROM blob_uploads ORDER BY upload_id", &[]).unwrap(), uploads);
}
#[test]
fn reservation_failure_has_no_upload_or_output_effect() {
    let (_f, store, access) = setup();
    store.database().exec("CREATE TRIGGER fail_candidate_reservation BEFORE INSERT ON document_candidates_v1 BEGIN SELECT RAISE(ABORT,'synthetic reservation failure'); END", &[]).unwrap();
    assert!(store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).is_err());
    assert!(store.database().query("SELECT * FROM document_candidates_v1", &[]).unwrap().is_empty());
    assert_eq!(store.database().query("SELECT * FROM blob_uploads", &[]).unwrap().len(), 1);
    assert_eq!(fs::read_dir(store.root_dir().join("objects")).unwrap().count(), 1);
}
#[test]
fn late_seal_failure_leaves_unpublished_object_and_query_only_unknown() {
    let (_f, store, access) = setup();
    store.database().exec("CREATE TRIGGER fail_candidate_seal BEFORE UPDATE OF state ON document_candidates_v1 WHEN NEW.state='sealed_unvalidated' BEGIN SELECT RAISE(ABORT,'synthetic seal failure'); END", &[]).unwrap();
    assert_eq!(store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES), Err(ContractError::Unknown));
    let status = store.lookup_document_candidate(&access, "candidate").unwrap();
    assert_eq!(status.state, CandidateState::PreparationUnknown);
    assert_eq!(fs::read(store.root_dir().join("objects").join(&status.expected_blob.digest)).unwrap(), NEW_BYTES);
    assert_eq!(store.database().query("SELECT * FROM document_revisions", &[]).unwrap().len(), 1);
    assert_eq!(store.database().query("SELECT * FROM blob_pins WHERE kind='upload'", &[]).unwrap().len(), 1);
    assert_eq!(store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).unwrap().state, CandidateState::PreparationUnknown);
}
#[test]
fn restart_retains_prepared_pin_but_never_adopts_original_execution_authority() {
    let (f, store, access) = setup();
    store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).unwrap();
    drop(store);
    let store = BusinessStore::open_existing(&f.path(), "workspace", "new-epoch").unwrap();
    let recovery = store.reconcile_blobs_after_restart().unwrap();
    assert_eq!(recovery.aborted_uploads, 0);
    assert_eq!(store.database().query("SELECT * FROM blob_pins WHERE kind='upload'", &[]).unwrap().len(), 1);
    assert!(store.lookup_document_candidate(&access, "candidate").is_err());
    let fresh = DocumentAccess { document: access.document, authority: AuthorityBinding { generation: access.authority.generation.next().unwrap(), owner_epoch: "new-epoch".into(), ..access.authority } };
    store.issue_document_grant_trusted(&fresh.document, &fresh.authority, &[DocumentOperation::ReadText, DocumentOperation::StructuredEdit], expiry()).unwrap();
    assert_eq!(store.lookup_document_candidate(&fresh, "candidate").unwrap().state, CandidateState::SealedUnvalidated);
    assert_eq!(store.prepare_document_candidate_trusted(&fresh, "candidate", "operation", NEW_BYTES), Err(ContractError::IntentConflict));
}
#[test]
fn revocation_conflict_invalid_input_and_foreign_publication_fail_closed() {
    let (_f, store, access) = setup();
    assert!(store.prepare_document_candidate_trusted(&access, "/tmp/model-path", "operation", NEW_BYTES).is_err());
    assert!(store.prepare_document_candidate_trusted(&access, "empty", "operation", &[]).is_err());
    assert!(store.prepare_document_candidate_trusted(&access, "huge", "operation", &vec![1; 30 * 1024 * 1024 + 1]).is_err());
    store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).unwrap();
    let foreign = Db::open(":memory:", false, true).unwrap(); let tx = foreign.transaction().unwrap();
    assert_eq!(store.document_publish_candidate_in_transaction(&tx, &access, "candidate"), Err(ContractError::InvalidAuthority)); drop(tx);
    store.revoke_document_grant_trusted(&access.authority).unwrap();
    assert!(store.lookup_document_candidate(&access, "candidate").is_err());
    assert!(store.prepare_document_candidate_trusted(&access, "later", "operation", NEW_BYTES).is_err());
}

// Test-only construction of a genuinely reserved pre-file-write crash window.
// It never creates a production validation credential or a publication permit.
fn reserve_fixture(store: &BusinessStore, access: &DocumentAccess, id: &str, expected: &BlobRef) -> crate::blobs::UploadHandle {
    let source = store.read_document(access).unwrap();
    let tx = store.database().transaction().unwrap();
    let upload = store.reserve_candidate_upload_in_transaction(&tx, "project").unwrap();
    let payload = serde_json::json!({"candidate_id": id, "operation_id": "operation", "base": access.document,
        "source_blob": source.blob, "authority": access.authority, "expected_blob": expected, "upload_id": upload.upload_id});
    store.database().exec("INSERT INTO document_candidates_v1 VALUES(?,'workspace','project',?,?,?,'preparing')", &[id, &upload.upload_id, expected.byte_length.as_str(), &payload.to_string()]).unwrap();
    tx.commit().unwrap();
    upload
}
fn expected(bytes: &[u8]) -> BlobRef {
    BlobRef { digest: Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect(), byte_length: Revision::new(bytes.len() as u64) }
}
#[test]
fn partial_staging_restart_preserves_candidate_without_blocking_unrelated_gc() {
    use std::io::Write;
    let (f, store, access) = setup();
    let candidate = expected(NEW_BYTES);
    let upload = reserve_fixture(&store, &access, "partial", &candidate);
    store.materialize_candidate_upload_trusted(&upload.upload_id).unwrap();
    store.append_chunk(&upload.upload_id, &NEW_BYTES[..7]).unwrap();
    let staging = store.root_dir().join("staging").join(&upload.upload_id);
    // Real file write after the ledger's last commit: SQLite cannot undo it.
    let mut file = fs::OpenOptions::new().append(true).open(&staging).unwrap();
    file.write_all(b"unsql-committed-tail").unwrap(); file.sync_all().unwrap(); drop(file);
    let before = fs::read(&staging).unwrap();
    let orphan = store.begin_upload("project").unwrap();
    store.append_chunk(&orphan.upload_id, b"unrelated original synthetic orphan").unwrap();
    let orphan = store.finish_blob(&orphan.upload_id, crate::blobs::BlobKind::Document).unwrap();
    store.abort_upload(&orphan.upload_id).unwrap();
    drop(store);
    let store = BusinessStore::open_existing(&f.path(), "workspace", "new-epoch").unwrap();
    assert_eq!(store.reconcile_blobs_after_restart().unwrap().aborted_uploads, 0);
    assert_eq!(fs::read(&staging).unwrap(), before);
    assert_eq!(store.collect_blobs().unwrap(), 1);
    assert!(!store.root_dir().join("objects").join(&orphan.blob.digest).exists());
    assert_eq!(fs::read(&staging).unwrap(), before);
    assert_eq!(store.lookup_upload(&upload.upload_id).unwrap().state, "copying");
}
#[test]
fn oversize_nonpayload_fields_fail_before_status_decode() {
    let (_f, store, access) = setup();
    store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).unwrap();
    for mutation in ["UPDATE document_candidates_v1 SET workspace=hex(zeroblob(100000))", "UPDATE document_candidates_v1 SET expected_length=hex(zeroblob(100000))"] {
        let tx = store.database().transaction().unwrap(); store.database().exec(mutation, &[]).unwrap();
        // No nested lookup transaction: inspect the same mutation via direct
        // source publication gate, which must reject before producing authority.
        assert!(store.document_publish_candidate_in_transaction(&tx, &access, "candidate").is_err());
        drop(tx);
    }
}
#[test]
fn candidate_count_and_expected_byte_admission_limits_precede_file_writes() {
    let (_f, store, access) = setup();
    let one = expected(b"one");
    for n in 0..32 { reserve_fixture(&store, &access, &format!("reserved-{n}"), &one); }
    assert_eq!(store.prepare_document_candidate_trusted(&access, "blocked", "operation", NEW_BYTES), Err(ContractError::TextLimit));
    assert_eq!(store.database().query("SELECT * FROM blob_uploads", &[]).unwrap().len(), 33);
    let (_f2, store, access) = setup();
    let bytes = vec![1; 24 * 1024 * 1024]; let planned = expected(&bytes);
    for n in 0..5 { reserve_fixture(&store, &access, &format!("reserved-{n}"), &planned); }
    assert_eq!(store.prepare_document_candidate_trusted(&access, "blocked", "operation", &vec![2; 9 * 1024 * 1024]), Err(ContractError::TextLimit));
    assert_eq!(store.database().query("SELECT * FROM blob_uploads", &[]).unwrap().len(), 6);
}
#[test]
fn expiry_after_durable_pin_is_unknown_and_never_source_success() {
    let (_f, store, access) = setup();
    store.database().exec("CREATE TRIGGER expire_after_candidate_pin AFTER UPDATE ON blob_uploads WHEN NEW.state='pinned' BEGIN UPDATE document_grants SET expires_at_ms='0'; END", &[]).unwrap();
    assert_eq!(store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES), Err(ContractError::Unknown));
    assert_eq!(store.database().query("SELECT * FROM document_revisions", &[]).unwrap().len(), 1);
    assert_eq!(store.database().query("SELECT * FROM blob_pins WHERE kind='upload'", &[]).unwrap().len(), 1);
    assert!(store.lookup_document_candidate(&access, "candidate").is_err());
}
#[test]
fn missing_pin_or_corrupt_object_is_query_only_unknown() {
    let (_f, store, access) = setup();
    let status = store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).unwrap();
    store.database().exec("DELETE FROM blob_pins WHERE kind='upload'", &[]).unwrap();
    assert_eq!(store.lookup_document_candidate(&access, "candidate").unwrap().state, CandidateState::PreparationUnknown);
    let object = store.root_dir().join("objects").join(&status.expected_blob.digest);
    fs::write(&object, b"corrupt synthetic output").unwrap();
    assert_eq!(store.lookup_document_candidate(&access, "candidate").unwrap().state, CandidateState::PreparationUnknown);
    assert_eq!(store.database().query("SELECT * FROM document_revisions", &[]).unwrap().len(), 1);
}
