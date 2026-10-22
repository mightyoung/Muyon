//! Original synthetic sources only. No native renderer or text parser is implied.
use super::{reader::*, storage_tests::Fixture, *};
use crate::{business::BusinessStore, contract::*};
use std::{fs, time::{SystemTime, UNIX_EPOCH}};

fn setup() -> (Fixture, DocumentReaderHost, DocumentAccess) {
    let fixture = Fixture::new();
    let (store, mut access) = fixture.setup();
    access.authority.generation = access.authority.generation.next().unwrap();
    let expiry = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64 + 20_000;
    store.issue_document_grant_trusted(&access.document, &access.authority,
        &[DocumentOperation::Inspect, DocumentOperation::ReadText, DocumentOperation::Render, DocumentOperation::StructuredEdit], expiry).unwrap();
    (fixture, DocumentReaderHost::new(store), access)
}
fn pins(store: &BusinessStore) -> usize {
    store.database().query("SELECT pin_id FROM blob_pins WHERE kind='reader'", &[]).unwrap().len()
}

#[test]
fn exact_metadata_and_sequential_bytes_close_at_eof() {
    let (_f, mut host, access) = setup();
    let metadata = host.inspect(&access).unwrap();
    let opened = host.open(&access, DocumentReadPurpose::ReadText).unwrap();
    assert_eq!(opened.metadata, metadata);
    assert_eq!(pins(host.store()), 1);
    let mut bytes = Vec::new();
    loop {
        let chunk = host.read_chunk(&opened.session_id, 7).unwrap();
        assert_eq!(chunk.offset.value(), bytes.len() as u64);
        bytes.extend(chunk.bytes);
        if chunk.eof { break; }
    }
    assert_eq!(bytes, fs::read(host.store().root_dir().join("objects").join(metadata.blob.digest)).unwrap());
    assert_eq!(pins(host.store()), 0);
    assert!(!host.is_current(&opened.session_id).unwrap());
    host.close(&opened.session_id).unwrap();
}

#[test]
fn open_failure_after_pin_creation_rolls_back_without_exposing_a_session() {
    let (_f, mut host, access) = setup();
    host.store().database().exec("CREATE TRIGGER expire_on_reader_pin AFTER INSERT ON blob_pins WHEN NEW.kind='reader' BEGIN UPDATE document_grants SET expires_at_ms='0'; END", &[]).unwrap();
    assert!(host.open(&access, DocumentReadPurpose::ReadText).is_err());
    assert_eq!(pins(host.store()), 0);
    host.store().database().exec("DROP TRIGGER expire_on_reader_pin", &[]).unwrap();
    // The initial pin and fault mutation shared the rolled-back transaction.
    let opened = host.open(&access, DocumentReadPurpose::ReadText).unwrap();
    host.close(&opened.session_id).unwrap();
    assert_eq!(pins(host.store()), 0);
}

#[test]
fn open_commit_rejection_maps_to_unknown_and_cleans_original_pin() {
    let (_f, mut host, access) = setup();
    // Genuine SQLite deferred constraint failure at COMMIT, not a claim to
    // reproduce a crash where COMMIT may already have reached durable storage.
    host.store().database().exec("CREATE TABLE reader_commit_fault(project_id TEXT REFERENCES projects(id) DEFERRABLE INITIALLY DEFERRED)", &[]).unwrap();
    host.store().database().exec("CREATE TRIGGER reject_reader_commit AFTER INSERT ON blob_pins WHEN NEW.kind='reader' BEGIN INSERT INTO reader_commit_fault VALUES('nonexistent-project'); END", &[]).unwrap();
    assert!(matches!(host.open(&access, DocumentReadPurpose::ReadText), Err(DocumentReadError::Core(ContractError::Unknown))));
    assert_eq!(pins(host.store()), 0);
    assert!(host.store().database().query("SELECT * FROM reader_commit_fault", &[]).unwrap().is_empty());
    host.store().database().exec("DROP TRIGGER reject_reader_commit", &[]).unwrap();
    host.close_all().unwrap();
}

#[test]
fn inspect_grant_cannot_open_bytes_and_forged_scope_never_substitutes_source() {
    let f = Fixture::new(); let (store, access) = f.setup();
    let mut host = DocumentReaderHost::new(store);
    assert!(host.inspect(&access).is_ok());
    assert!(host.open(&access, DocumentReadPurpose::ReadText).is_err());
    assert!(host.open(&access, DocumentReadPurpose::Render).is_err());
    let foreign = DocumentAccess { document: DocumentRef::new(Scope { workspace_id: "other".into(), project_id: Some("project".into()) }, "document", Revision::new(1), DocumentFormat::Pdf).unwrap(), authority: access.authority };
    assert!(host.open(&foreign, DocumentReadPurpose::ReadText).is_err());
    assert_eq!(pins(host.store()), 0);
}

#[test]
fn revoked_or_advanced_session_never_delivers_cached_bytes() {
    let (_f, mut host, access) = setup();
    let opened = host.open(&access, DocumentReadPurpose::ReadText).unwrap();
    host.store().revoke_document_grant_trusted(&access.authority).unwrap();
    assert!(host.read_chunk(&opened.session_id, 7).is_err());
    assert_eq!(pins(host.store()), 0);
    let (_f2, mut host, access) = setup();
    let metadata = host.inspect(&access).unwrap();
    let opened = host.open(&access, DocumentReadPurpose::Render).unwrap();
    let tx = host.store().database().transaction().unwrap();
    host.store().document_clone_in_transaction(&tx, &access.document, "Advanced", &metadata.blob).unwrap();
    tx.commit().unwrap();
    assert!(!host.is_current(&opened.session_id).unwrap());
    assert!(host.read_chunk(&opened.session_id, 7).is_err());
    assert_eq!(pins(host.store()), 0);
}

#[test]
fn generation_epoch_expiry_and_project_deletion_revoke_existing_sessions() {
    for mutation in [
        "UPDATE document_grants SET generation='99'",
        "UPDATE document_grants SET owner_epoch='foreign-epoch'",
        "UPDATE document_grants SET expires_at_ms='0'",
        "UPDATE projects SET deleted=1",
    ] {
        let (_f, mut host, access) = setup();
        let opened = host.open(&access, DocumentReadPurpose::ReadText).unwrap();
        host.store().database().exec(mutation, &[]).unwrap();
        assert!(host.read_chunk(&opened.session_id, 7).is_err(), "{mutation}");
        assert_eq!(pins(host.store()), 0);
    }
}

#[test]
fn one_shot_callback_failure_and_cleanup_failure_return_no_success_or_pin() {
    let (_f, host, access) = setup();
    let result: std::result::Result<(), _> = host.store().with_document_source(&access, DocumentReadPurpose::ReadText, 1024, |_| Err(ContractError::UnsupportedOperation));
    assert_eq!(result, Err(DocumentReadError::Core(ContractError::UnsupportedOperation)));
    assert_eq!(pins(host.store()), 0);
    host.store().database().exec("CREATE TRIGGER fail_reader_cleanup BEFORE DELETE ON blob_pins WHEN OLD.kind='reader' BEGIN SELECT RAISE(ABORT,'original synthetic cleanup failure'); END", &[]).unwrap();
    assert!(host.store().with_document_source(&access, DocumentReadPurpose::ReadText, 1024, |_| Ok(())).is_err());
    // The pin was created in this same rolled-back transaction, not committed.
    assert_eq!(pins(host.store()), 0);
}

#[test]
fn bounded_sessions_idle_absolute_lifetime_and_invalid_chunk_release_pins() {
    let (_f, mut host, access) = setup();
    let mut ids = Vec::new();
    for _ in 0..MAX_READ_SESSIONS { ids.push(host.open(&access, DocumentReadPurpose::ReadText).unwrap().session_id); }
    assert!(host.open(&access, DocumentReadPurpose::ReadText).is_err());
    assert_eq!(pins(host.store()), MAX_READ_SESSIONS);
    host.expire_for_test(&ids[0], true);
    assert!(!host.is_current(&ids[0]).unwrap());
    host.expire_for_test(&ids[1], false);
    assert!(host.read_chunk(&ids[1], 1).is_err());
    assert!(host.read_chunk(&ids[2], 0).is_err());
    assert!(host.read_chunk(&ids[3], crate::blobs::MAX_CHUNK + 1).is_err());
    host.close_all().unwrap();
    assert_eq!(pins(host.store()), 0);
}

#[test]
fn deleted_pin_or_same_length_corruption_invalidates_session() {
    let (_f, mut host, access) = setup();
    let opened = host.open(&access, DocumentReadPurpose::ReadText).unwrap();
    let path = host.store().root_dir().join("objects").join(&opened.metadata.blob.digest);
    let mut bytes = fs::read(&path).unwrap(); bytes[0] ^= 1; fs::write(&path, bytes).unwrap();
    assert!(host.read_chunk(&opened.session_id, 1).is_err());
    assert_eq!(pins(host.store()), 0);
    let (_f2, mut host, access) = setup();
    let opened = host.open(&access, DocumentReadPurpose::ReadText).unwrap();
    host.store().database().exec("DELETE FROM blob_pins WHERE kind='reader'", &[]).unwrap();
    assert!(!host.is_current(&opened.session_id).unwrap());
    assert_eq!(pins(host.store()), 0);
}

#[test]
fn corrupt_oversize_blob_length_is_rejected_without_creating_reader_pin() {
    let (_f, mut host, access) = setup();
    host.store().database().exec("UPDATE blobs SET byte_length=hex(zeroblob(100000))", &[]).unwrap();
    assert!(host.open(&access, DocumentReadPurpose::ReadText).is_err());
    assert_eq!(pins(host.store()), 0);
}

#[test]
fn one_shot_view_is_live_bounded_and_tail_rechecks_expiry_before_delivery() {
    let (_f, host, access) = setup();
    let output = host.store().with_document_source(&access, DocumentReadPurpose::ReadText, 1024, |view| {
        assert_eq!(view.metadata().document, access.document);
        assert_eq!(view.resolve_current(&view.request()).unwrap().source.blob, view.metadata().blob);
        Ok(view.bytes().to_vec())
    }).unwrap();
    assert!(!output.is_empty()); assert_eq!(pins(host.store()), 0);
    assert!(host.store().with_document_source(&access, DocumentReadPurpose::ReadText, 1, |_| Ok(())).is_err());
    let result = host.store().with_document_source(&access, DocumentReadPurpose::ReadText, 1024, |_| {
        // Same-owner fault in the active transaction: no nested public call.
        host.store().database().exec("UPDATE document_grants SET expires_at_ms='0'", &[]).unwrap();
        Ok(b"must never be delivered".to_vec())
    });
    assert!(result.is_err()); assert_eq!(pins(host.store()), 0);
}

#[test]
fn cleanup_failure_withholds_bytes_and_poisoned_host_refuses_new_sessions() {
    let (_f, mut host, access) = setup();
    let opened = host.open(&access, DocumentReadPurpose::ReadText).unwrap();
    host.store().database().exec("CREATE TRIGGER fail_reader_cleanup BEFORE DELETE ON blob_pins WHEN OLD.kind='reader' BEGIN SELECT RAISE(ABORT,'original synthetic cleanup failure'); END", &[]).unwrap();
    assert!(host.read_chunk(&opened.session_id, crate::blobs::MAX_CHUNK).is_err());
    assert!(host.open(&access, DocumentReadPurpose::ReadText).is_err());
    assert_eq!(pins(host.store()), 1);
    host.store().database().exec("DROP TRIGGER fail_reader_cleanup", &[]).unwrap();
    host.close_all().unwrap();
    assert_eq!(pins(host.store()), 0);
}

#[test]
fn dropping_host_releases_sessions_before_reopening_same_store() {
    let (f, mut host, access) = setup();
    host.open(&access, DocumentReadPurpose::ReadText).unwrap();
    drop(host);
    let store = BusinessStore::open_existing(&f.path(), "workspace", "new-epoch").unwrap();
    assert_eq!(pins(&store), 0);
}
