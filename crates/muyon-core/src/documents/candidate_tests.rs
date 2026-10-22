//! Original synthetic candidate bytes only; never a production validator.
use super::{storage_tests::Fixture, *};
use crate::{business::BusinessStore, contract::*, sqlite::Db};
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
