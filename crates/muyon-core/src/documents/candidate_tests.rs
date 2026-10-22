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
    let project = access.document.scope().project_id.as_deref().unwrap();
    let tx = store.database().transaction().unwrap();
    let upload = store.reserve_candidate_upload_in_transaction(&tx, project).unwrap();
    let payload = serde_json::json!({"candidate_id": id, "operation_id": "operation", "base": access.document,
        "source_blob": source.blob, "authority": access.authority, "expected_blob": expected, "upload_id": upload.upload_id});
    store.database().exec("INSERT INTO document_candidates_v1 VALUES(?,'workspace',?,?,?,?,'preparing')", &[id, project, &upload.upload_id, expected.byte_length.as_str(), &payload.to_string()]).unwrap();
    tx.commit().unwrap();
    upload
}

fn add_project_fixture(store: &BusinessStore, project: &str) -> DocumentAccess {
    store.database().exec("INSERT INTO projects VALUES(?,'workspace','Synthetic','1',0)", &[project]).unwrap();
    let upload = store.begin_upload(project).unwrap();
    store.append_chunk(&upload.upload_id, b"original synthetic multi-project source").unwrap();
    let finished = store.finish_blob(&upload.upload_id, crate::blobs::BlobKind::Document).unwrap();
    let metadata = store.register_document_trusted(project, &format!("document-{project}"), "Synthetic", DocumentFormat::Text, &finished).unwrap();
    let authority = AuthorityBinding { grant_id: format!("grant-{project}"), generation: Revision::new(1), owner_epoch: "epoch".into() };
    store.issue_document_grant_trusted(&metadata.document, &authority, &[DocumentOperation::Inspect, DocumentOperation::ReadText, DocumentOperation::StructuredEdit], expiry()).unwrap();
    DocumentAccess { document: metadata.document, authority }
}

#[test]
fn candidate_gc_crosses_page_boundary_preserving_exact_objects_and_project_quotas() {
    let (f, store, access) = setup();
    let mut projects = vec![access];
    for n in 1..5 { projects.push(add_project_fixture(&store, &format!("project-{n}"))); }
    let mut reserved = Vec::new();
    for (project_n, access) in projects.iter().enumerate() {
        // A real committed reservation is the crash point before CREATE_NEW.
        // Keep each project within its actual 32-entry admission policy.
        for n in 0..32 {
            let bytes = format!("original synthetic candidate {project_n}/{n}").into_bytes();
            let blob = expected(&bytes);
            let upload = reserve_fixture(&store, access, &format!("candidate-{project_n}-{n}"), &blob);
            reserved.push((upload.upload_id, blob, bytes));
        }
        assert_eq!(store.prepare_document_candidate_trusted(access, &format!("over-quota-{project_n}"), "operation", NEW_BYTES), Err(ContractError::TextLimit));
    }
    reserved.sort_by(|a, b| a.0.cmp(&b.0));
    assert_eq!(reserved.len(), 160);
    // Different expected digests before/on/after the 128-row boundary and at
    // the final row. Files model rename durability before the blob-ledger commit.
    let mut protected = Vec::new();
    for index in [0, 127, 128, 159] {
        let (_, blob, bytes) = &reserved[index];
        let path = store.root_dir().join("objects").join(&blob.digest);
        fs::write(&path, bytes).unwrap();
        protected.push((path, bytes.clone()));
    }
    // The final unresolved upload also has actual partial durable staging.
    let final_upload = &reserved[159].0;
    store.materialize_candidate_upload_trusted(final_upload).unwrap();
    store.append_chunk(final_upload, b"partial").unwrap();
    let partial = store.root_dir().join("staging").join(final_upload);
    let unrelated = b"unrelated synthetic object absent from every reservation";
    let orphan_path = store.root_dir().join("objects").join(expected(unrelated).digest);
    fs::write(&orphan_path, unrelated).unwrap();
    // Per-project quota must not become a global admission cap.
    let sixth = add_project_fixture(&store, "project-5");
    assert_eq!(store.prepare_document_candidate_trusted(&sixth, "sixth-candidate", "operation", NEW_BYTES).unwrap().state, CandidateState::SealedUnvalidated);
    assert!(store.lookup_document_candidate(&sixth, "candidate-0-0").is_err());
    let uploads = store.database().query("SELECT * FROM blob_uploads ORDER BY upload_id", &[]).unwrap();
    let journals = store.database().query("SELECT * FROM document_candidates_v1 ORDER BY candidate_id", &[]).unwrap();
    assert_eq!(journals.len(), 161);
    drop(store);
    let store = BusinessStore::open_existing(&f.path(), "workspace", "new-epoch").unwrap();
    assert_eq!(store.reconcile_blobs_after_restart().unwrap().aborted_uploads, 0);
    assert_eq!(fs::read(&partial).unwrap(), b"partial");
    assert_eq!(store.collect_blobs().unwrap(), 1);
    assert!(!orphan_path.exists());
    for (path, bytes) in &protected { assert_eq!(fs::read(path).unwrap(), *bytes); }
    assert_eq!(store.database().query("SELECT * FROM blob_uploads ORDER BY upload_id", &[]).unwrap(), uploads);
    assert_eq!(store.database().query("SELECT * FROM document_candidates_v1 ORDER BY candidate_id", &[]).unwrap(), journals);
    // A second sweep cannot repeat deletion or alter an uncertain reservation.
    assert_eq!(store.collect_blobs().unwrap(), 0);
    assert_eq!(fs::read(&partial).unwrap(), b"partial");
    assert_eq!(store.database().query("SELECT * FROM document_candidates_v1 ORDER BY candidate_id", &[]).unwrap(), journals);
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
    // Simulate the durable expected object existing before its ledger commit.
    let expected_object = store.root_dir().join("objects").join(&candidate.digest);
    fs::write(&expected_object, NEW_BYTES).unwrap();
    drop(store);
    let store = BusinessStore::open_existing(&f.path(), "workspace", "new-epoch").unwrap();
    assert_eq!(store.reconcile_blobs_after_restart().unwrap().aborted_uploads, 0);
    assert_eq!(fs::read(&staging).unwrap(), before);
    assert_eq!(store.collect_blobs().unwrap(), 1);
    assert!(!store.root_dir().join("objects").join(&orphan.blob.digest).exists());
    assert_eq!(fs::read(&expected_object).unwrap(), NEW_BYTES);
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
        assert_eq!(store.document_publish_candidate_in_transaction(&tx, &access, "candidate"), Err(ContractError::StorageCorrupt));
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
    let object = store.root_dir().join("objects").join(&status.expected_blob.digest);
    // Preserve length so this exercises the hash check, not just byte count.
    let mut corrupt = NEW_BYTES.to_vec();
    corrupt[0] ^= 1;
    fs::write(&object, &corrupt).unwrap();
    assert_eq!(store.lookup_document_candidate(&access, "candidate").unwrap().state, CandidateState::PreparationUnknown);
    fs::write(&object, NEW_BYTES).unwrap();
    assert_eq!(store.lookup_document_candidate(&access, "candidate").unwrap().state, CandidateState::SealedUnvalidated);
    fs::remove_file(&object).unwrap();
    assert_eq!(store.lookup_document_candidate(&access, "candidate").unwrap().state, CandidateState::PreparationUnknown);
    fs::write(&object, NEW_BYTES).unwrap();
    store.database().exec("DELETE FROM blob_pins WHERE kind='upload'", &[]).unwrap();
    assert_eq!(store.lookup_document_candidate(&access, "candidate").unwrap().state, CandidateState::PreparationUnknown);
    assert_eq!(store.database().query("SELECT * FROM document_revisions", &[]).unwrap().len(), 1);
}
#[test]
fn source_head_advance_rejects_old_candidate_without_latest_substitution() {
    let (_f, store, access) = setup();
    let original = store.read_document(&access).unwrap();
    store.prepare_document_candidate_trusted(&access, "candidate", "operation", NEW_BYTES).unwrap();
    let tx = store.database().transaction().unwrap();
    store.document_access_in_transaction(&tx, &access, &[DocumentOperation::StructuredEdit]).unwrap();
    store.document_clone_in_transaction(&tx, &access.document, "Source advanced", &original.blob).unwrap();
    tx.commit().unwrap();
    assert_eq!(store.lookup_document_candidate(&access, "candidate"), Err(ContractError::RevisionConflict));
    assert_eq!(store.database().query("SELECT state FROM document_candidates_v1", &[]).unwrap()[0][0].as_deref(), Some("sealed_unvalidated"));
    assert_eq!(store.database().query("SELECT * FROM document_revisions", &[]).unwrap().len(), 2);
}
