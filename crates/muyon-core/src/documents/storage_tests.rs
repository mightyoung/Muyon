//! Same-owner transaction hook regressions using original synthetic blob bytes.
use super::*;
use crate::{blobs::BlobKind, business::BusinessStore, contract::*, sqlite::Db};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!(
            "muyon-document-grant-tail-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&root).unwrap();
        Self(root)
    }
    fn path(&self) -> PathBuf {
        self.0.join("store.sqlite")
    }
    fn setup(&self) -> (BusinessStore, DocumentAccess) {
        BusinessStore::initialize(&self.path(), "workspace").unwrap();
        let store = BusinessStore::open_existing(&self.path(), "workspace", "epoch").unwrap();
        store
            .database()
            .exec(
                "INSERT INTO projects VALUES('project','workspace','Synthetic','1',0)",
                &[],
            )
            .unwrap();
        store.initialize_documents_trusted().unwrap();
        let finished = upload(&store);
        let metadata = store
            .register_document_trusted(
                "project",
                "document",
                "Synthetic",
                DocumentFormat::Pdf,
                &finished,
            )
            .unwrap();
        let authority = AuthorityBinding {
            grant_id: "grant".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch".into(),
        };
        let expiry = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64
            + 20_000;
        store
            .issue_document_grant_trusted(
                &metadata.document,
                &authority,
                &[
                    DocumentOperation::Inspect,
                    DocumentOperation::StructuredEdit,
                ],
                expiry,
            )
            .unwrap();
        (
            store,
            DocumentAccess {
                document: metadata.document,
                authority,
            },
        )
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn upload(store: &BusinessStore) -> crate::blobs::FinishedBlob {
    let upload = store.begin_upload("project").unwrap();
    store
        .append_chunk(
            &upload.upload_id,
            b"%PDF-1.4\noriginal synthetic hook fixture\n%%EOF\n",
        )
        .unwrap();
    store.finish_blob(&upload.upload_id, BlobKind::Pdf).unwrap()
}
#[test]
fn tail_grant_survives_own_cas_without_authorizing_old_revision_reads() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    let finished = upload(&store);
    let tx = store.database().transaction().unwrap();
    assert!(store
        .document_access_in_transaction(&tx, &access, &[DocumentOperation::StructuredEdit])
        .is_ok());
    let published = store
        .document_publish_in_transaction(
            &tx,
            &access.document,
            "Copy",
            DocumentFormat::Pdf,
            &finished,
        )
        .unwrap();
    assert_eq!(published.document.revision(), &Revision::new(2));
    assert_eq!(
        store.document_grant_in_transaction(&tx, &access, &[DocumentOperation::StructuredEdit]),
        Ok(())
    );
    assert_eq!(
        store.document_access_in_transaction(&tx, &access, &[DocumentOperation::Inspect]),
        Err(ContractError::RevisionConflict)
    );
    drop(tx);
    assert_eq!(
        store.read_document(&access).unwrap().document.revision(),
        &Revision::new(1)
    );
}
#[test]
fn tail_grant_rechecks_revocation_expiry_generation_epoch_and_project() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    for mutation in [
        "UPDATE document_grants SET active=0",
        "UPDATE document_grants SET expires_at_ms='0'",
        "UPDATE document_grants SET generation='2'",
        "UPDATE document_grants SET owner_epoch='old'",
        "UPDATE projects SET deleted=1 WHERE id='project'",
    ] {
        let tx = store.database().transaction().unwrap();
        store.database().exec(mutation, &[]).unwrap();
        assert!(
            store
                .document_grant_in_transaction(&tx, &access, &[DocumentOperation::StructuredEdit])
                .is_err(),
            "{mutation}"
        );
        drop(tx);
    }
    let tx = store.database().transaction().unwrap();
    assert!(store
        .document_grant_in_transaction(&tx, &access, &[DocumentOperation::Export])
        .is_err());
    drop(tx);
}
#[test]
fn tail_grant_rejects_foreign_transaction_and_mismatched_document_binding() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    let foreign = Db::open(":memory:", false, true).unwrap();
    let foreign_tx = foreign.transaction().unwrap();
    assert_eq!(
        store.document_grant_in_transaction(&foreign_tx, &access, &[DocumentOperation::Inspect]),
        Err(ContractError::InvalidAuthority)
    );
    let wrong = DocumentAccess {
        document: DocumentRef::new(
            access.document.scope().clone(),
            "other",
            Revision::new(1),
            DocumentFormat::Pdf,
        )
        .unwrap(),
        authority: access.authority.clone(),
    };
    let tx = store.database().transaction().unwrap();
    assert_eq!(
        store.document_grant_in_transaction(&tx, &wrong, &[DocumentOperation::Inspect]),
        Err(ContractError::InvalidAuthority)
    );
    drop(tx);
}

#[test]
fn copy_clone_commits_same_bytes_and_revision_without_upload_or_staging() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    let original = store.read_document(&access).unwrap();
    let before_uploads = store.database().query("SELECT * FROM blob_uploads", &[]).unwrap();
    let before_pins = store.database().query("SELECT * FROM blob_pins", &[]).unwrap();
    let tx = store.database().transaction().unwrap();
    store.document_access_in_transaction(&tx, &access, &[DocumentOperation::StructuredEdit]).unwrap();
    let copy = store.document_clone_in_transaction(&tx, &access.document, "COPY only", &original.blob).unwrap();
    assert_eq!(copy.blob, original.blob);
    assert_eq!(copy.document.format(), original.document.format());
    assert_eq!(copy.document.revision(), &Revision::new(2));
    store.document_grant_in_transaction(&tx, &access, &[DocumentOperation::StructuredEdit]).unwrap();
    tx.commit().unwrap();
    assert_eq!(store.database().query("SELECT * FROM blob_uploads", &[]).unwrap(), before_uploads);
    assert_eq!(store.database().query("SELECT * FROM blob_pins", &[]).unwrap(), before_pins);
    assert_eq!(fs::read_dir(store.root_dir().join("staging")).unwrap().count(), 0);
    assert_eq!(store.database().query("SELECT * FROM document_revisions", &[]).unwrap().len(), 2);
    assert_eq!(store.database().query("SELECT * FROM blob_references", &[]).unwrap().len(), 2);
    let mut reader = store.open_blob_reader("project", &original.blob).unwrap();
    assert_eq!(store.read_blob_chunk(&mut reader, 4096).unwrap(), b"%PDF-1.4\noriginal synthetic hook fixture\n%%EOF\n");
}

#[test]
fn clone_and_late_receipt_failure_roll_back_together() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    let original = store.read_document(&access).unwrap();
    // Synthetic receipt constraint, not the gateway owner's production journal.
    store.database().exec("CREATE TABLE synthetic_copy_receipts(id TEXT PRIMARY KEY)", &[]).unwrap();
    store.database().exec("INSERT INTO synthetic_copy_receipts VALUES('existing')", &[]).unwrap();
    let tx = store.database().transaction().unwrap();
    store.document_clone_in_transaction(&tx, &access.document, "COPY only", &original.blob).unwrap();
    assert!(store.database().exec("INSERT INTO synthetic_copy_receipts VALUES('existing')", &[]).is_err());
    drop(tx);
    assert_eq!(store.read_document(&access).unwrap(), original);
    assert_eq!(store.database().query("SELECT * FROM document_revisions", &[]).unwrap().len(), 1);
    assert_eq!(store.database().query("SELECT * FROM blob_references", &[]).unwrap().len(), 1);
    assert_eq!(store.database().query("SELECT * FROM blob_uploads", &[]).unwrap().len(), 1);
    assert!(store.database().query("SELECT * FROM blob_pins", &[]).unwrap().is_empty());
}

#[test]
fn clone_rejects_changed_source_stale_base_and_foreign_transaction() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    let original = store.read_document(&access).unwrap();
    let tx = store.database().transaction().unwrap();
    for wrong in [BlobRef { digest: "b".repeat(64), ..original.blob.clone() }, BlobRef { byte_length: original.blob.byte_length.next().unwrap(), ..original.blob.clone() }] {
        assert_eq!(store.document_clone_in_transaction(&tx, &access.document, "COPY", &wrong), Err(ContractError::BindingMismatch));
    }
    let stale = DocumentRef::new(access.document.scope().clone(), "document", Revision::new(0), DocumentFormat::Pdf).unwrap();
    assert_eq!(store.document_clone_in_transaction(&tx, &stale, "COPY", &original.blob), Err(ContractError::RevisionConflict));
    drop(tx);
    let foreign = Db::open(":memory:", false, true).unwrap();
    let foreign_tx = foreign.transaction().unwrap();
    assert_eq!(store.document_clone_in_transaction(&foreign_tx, &access.document, "COPY", &original.blob), Err(ContractError::InvalidAuthority));
    assert_eq!(store.clone_blob_reference_in_transaction(&foreign_tx, "project", "document", &original.blob, "new-ref"), Err(ContractError::InvalidAuthority));
}

#[test]
fn clone_reference_requires_same_project_ready_source_and_unique_reference() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    let original = store.read_document(&access).unwrap();
    store.database().exec("INSERT INTO projects VALUES('other','workspace','Other','1',0)", &[]).unwrap();
    let tx = store.database().transaction().unwrap();
    assert!(store.clone_blob_reference_in_transaction(&tx, "other", "document", &original.blob, "new-ref").is_err());
    store.clone_blob_reference_in_transaction(&tx, "project", "document", &original.blob, "new-ref").unwrap();
    assert!(store.clone_blob_reference_in_transaction(&tx, "project", "document", &original.blob, "new-ref").is_err());
    drop(tx);
    for mutation in ["UPDATE blobs SET state='deleting'", "UPDATE projects SET deleted=1 WHERE id='project'", "DELETE FROM blob_references"] {
        let tx = store.database().transaction().unwrap();
        store.database().exec(mutation, &[]).unwrap();
        assert!(store.clone_blob_reference_in_transaction(&tx, "project", "document", &original.blob, "new-ref").is_err());
        drop(tx);
    }
    assert_eq!(store.database().query("SELECT * FROM blob_references", &[]).unwrap().len(), 1);
}

#[test]
fn clone_verifies_real_source_file_hash_and_missing_file() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    let original = store.read_document(&access).unwrap();
    let object = store.root_dir().join("objects").join(&original.blob.digest);
    let bytes = fs::read(&object).unwrap();
    let mut corrupted = bytes.clone();
    corrupted[0] ^= 1;
    fs::write(&object, &corrupted).unwrap();
    let tx = store.database().transaction().unwrap();
    assert_eq!(store.document_clone_in_transaction(&tx, &access.document, "COPY", &original.blob), Err(ContractError::BindingMismatch));
    drop(tx);
    fs::write(&object, &bytes).unwrap();
    fs::remove_file(&object).unwrap();
    let tx = store.database().transaction().unwrap();
    assert!(store.document_clone_in_transaction(&tx, &access.document, "COPY", &original.blob).is_err());
    drop(tx);
    assert_eq!(store.database().query("SELECT * FROM document_revisions", &[]).unwrap().len(), 1);
}

#[test]
fn clone_late_metadata_failure_and_revision_overflow_leave_original_intact() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    let original = store.read_document(&access).unwrap();
    store.database().exec("CREATE TRIGGER fail_clone_metadata BEFORE INSERT ON document_revisions BEGIN SELECT RAISE(ABORT,'synthetic failure'); END", &[]).unwrap();
    let tx = store.database().transaction().unwrap();
    assert!(store.document_clone_in_transaction(&tx, &access.document, "COPY", &original.blob).is_err());
    drop(tx);
    assert_eq!(store.read_document(&access).unwrap(), original);
    assert_eq!(store.database().query("SELECT * FROM blob_references", &[]).unwrap().len(), 1);
    store.database().exec("DROP TRIGGER fail_clone_metadata", &[]).unwrap();
    let max_document = DocumentRef::new(access.document.scope().clone(), "document", Revision::new(u64::MAX), DocumentFormat::Pdf).unwrap();
    let max_metadata = DocumentMetadata { document: max_document.clone(), ..original };
    store.database().exec("UPDATE document_heads SET revision=?", &[max_document.revision().as_str()]).unwrap();
    store.database().exec("UPDATE document_revisions SET revision=?,payload=?", &[max_document.revision().as_str(), &serde_json::to_string(&max_metadata).unwrap()]).unwrap();
    let tx = store.database().transaction().unwrap();
    assert_eq!(store.document_clone_in_transaction(&tx, &max_document, "COPY", &max_metadata.blob), Err(ContractError::InvalidRevision));
    drop(tx);
    assert_eq!(store.database().query("SELECT * FROM blob_references", &[]).unwrap().len(), 1);
}
