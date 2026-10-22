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
