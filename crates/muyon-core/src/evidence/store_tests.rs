use super::*;
use crate::{blobs::BlobKind, contract::*, documents::*, sqlite::Db};
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
        let path = std::env::temp_dir().join(format!(
            "muyon-evidence-owner-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn path(&self) -> PathBuf {
        self.0.join("store.sqlite")
    }
    fn setup(
        &self,
        bytes: &[u8],
        operations: &[DocumentOperation],
    ) -> (BusinessStore, DocumentAccess) {
        self.setup_format(bytes, DocumentFormat::Text, operations)
    }
    fn setup_format(
        &self,
        bytes: &[u8],
        format: DocumentFormat,
        operations: &[DocumentOperation],
    ) -> (BusinessStore, DocumentAccess) {
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
        let finished = upload(&store, bytes);
        let metadata = store
            .register_document_trusted(
                "project",
                "document",
                "Synthetic original",
                format,
                &finished,
            )
            .unwrap();
        let authority = AuthorityBinding {
            grant_id: "grant".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch".into(),
        };
        store
            .issue_document_grant_trusted(
                &metadata.document,
                &authority,
                operations,
                now() + 25_000,
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
fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
}
fn upload(store: &BusinessStore, bytes: &[u8]) -> crate::blobs::FinishedBlob {
    let upload = store.begin_upload("project").unwrap();
    for chunk in bytes.chunks(crate::blobs::MAX_CHUNK) {
        store.append_chunk(&upload.upload_id, chunk).unwrap();
    }
    store
        .finish_blob(&upload.upload_id, BlobKind::Document)
        .unwrap()
}
fn reader_pins(store: &BusinessStore) -> String {
    store
        .database()
        .query("SELECT COUNT(*) FROM blob_pins WHERE kind='reader'", &[])
        .unwrap()[0][0]
        .clone()
        .unwrap()
}
#[test]
fn real_saved_text_readtext_grant_produces_processing_receipt_and_exact_quote() {
    let f = Fixture::new();
    let (store, access) = f.setup(
        "原创 α evidence alpha".as_bytes(),
        &[DocumentOperation::ReadText],
    );
    let gateway = StoreEvidence::new(&store);
    let result = gateway.process(&access, InputKind::Utf8Text).unwrap();
    assert_eq!(result.source_metadata().document, access.document);
    assert_eq!(result.receipt().extraction, ProcessingState::Available);
    assert_eq!(result.receipt().index, ProcessingState::NotRun);
    let projection = serde_json::to_value(result.projection()).unwrap();
    assert_eq!(projection["schema"], "muyon.stored-processing.v1");
    assert_eq!(projection["processing"]["extraction"], "available");
    assert_eq!(projection["processing"]["index"], "not_run");
    assert_eq!(
        projection["registered_source_snapshot"]["document"]["format"],
        "text"
    );
    assert!(projection.get("saved").is_none());
    let hits = gateway
        .find_literal(&access, &result, "α evidence", 10)
        .unwrap();
    assert_eq!(
        gateway.open(&access, &result, &hits[0]).unwrap(),
        "α evidence"
    );
    let answer = gateway
        .answer(&access, &result, "Unverified claim", &hits, &[0])
        .unwrap();
    assert_eq!(answer.citations.len(), 1);
    assert_eq!(answer.citations[0].support, ClaimSupport::Unassessed);
    assert_eq!(answer.independent_support_count, None);
    assert_eq!(reader_pins(&store), "0");
}
#[test]
fn inspect_is_not_readtext_and_failure_opens_no_reader() {
    let f = Fixture::new();
    let (store, access) = f.setup(b"synthetic", &[DocumentOperation::Inspect]);
    assert!(store.read_document(&access).is_ok());
    assert_eq!(
        StoreEvidence::new(&store)
            .process(&access, InputKind::Utf8Text)
            .unwrap_err(),
        StoreEvidenceError::Core(ContractError::InvalidAuthority)
    );
    assert_eq!(reader_pins(&store), "0");
}
#[test]
fn persisted_revocation_expiry_generation_epoch_and_project_deletion_deny_cached_results() {
    for mutation in [
        "UPDATE document_grants SET active=0",
        "UPDATE document_grants SET expires_at_ms='0'",
        "UPDATE document_grants SET generation='2'",
        "UPDATE document_grants SET owner_epoch='other'",
        "UPDATE projects SET deleted=1",
    ] {
        let f = Fixture::new();
        let (store, access) = f.setup(b"synthetic", &[DocumentOperation::ReadText]);
        let gateway = StoreEvidence::new(&store);
        let result = gateway.process(&access, InputKind::Utf8Text).unwrap();
        let hits = gateway
            .find_literal(&access, &result, "synthetic", 10)
            .unwrap();
        store.database().exec(mutation, &[]).unwrap();
        assert!(
            gateway.open(&access, &result, &hits[0]).is_err(),
            "{mutation}"
        );
        assert!(
            gateway
                .find_literal(&access, &result, "synthetic", 10)
                .is_err(),
            "{mutation}"
        );
        assert!(
            gateway
                .answer(&access, &result, "body", &hits, &[0])
                .is_err(),
            "{mutation}"
        );
        assert_eq!(reader_pins(&store), "0");
    }
}
#[test]
fn reader_lease_and_grant_mutation_in_same_transaction_block_delivery() {
    for mutation in [
        "DELETE FROM blob_pins WHERE kind='reader'",
        "UPDATE document_grants SET active=0",
    ] {
        let f = Fixture::new();
        let (store, access) = f.setup(b"synthetic", &[DocumentOperation::ReadText]);
        let gateway = StoreEvidence::new(&store);
        let result = gateway.with_source(&access, |host, request, bytes, _| {
            store.database().exec(mutation, &[]).unwrap();
            process_local(host, request, InputKind::Utf8Text, bytes).map(|_| ())
        });
        assert!(result.is_err(), "{mutation}");
        assert_eq!(reader_pins(&store), "0");
    }
}
#[test]
fn owner_delivery_transaction_excludes_other_sqlite_writer() {
    let f = Fixture::new();
    let (store, access) = f.setup(b"synthetic", &[DocumentOperation::ReadText]);
    let other = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    other.query("PRAGMA busy_timeout=0", &[]).unwrap();
    StoreEvidence::new(&store)
        .with_source(&access, |host, request, bytes, _| {
            let error = other
                .exec("UPDATE document_grants SET active=0", &[])
                .unwrap_err();
            assert!(error.starts_with("SQLite 5:"), "{error}");
            process_local(host, request, InputKind::Utf8Text, bytes).map(|_| ())
        })
        .unwrap();
    assert_eq!(
        other
            .exec("UPDATE document_grants SET active=0", &[])
            .unwrap(),
        1
    );
    assert!(StoreEvidence::new(&store)
        .process(&access, InputKind::Utf8Text)
        .is_err());
    assert_eq!(reader_pins(&store), "0");
}
#[test]
fn changed_current_revision_never_rebinds_old_evidence() {
    let f = Fixture::new();
    let (store, access) = f.setup(b"old synthetic", &[DocumentOperation::ReadText]);
    let gateway = StoreEvidence::new(&store);
    let result = gateway.process(&access, InputKind::Utf8Text).unwrap();
    let hits = gateway.find_literal(&access, &result, "old", 10).unwrap();
    let finished = upload(&store, b"new synthetic");
    let next = store
        .publish_document_revision_trusted(
            &access.document,
            "new",
            access.document.format(),
            &finished,
        )
        .unwrap();
    assert_eq!(
        gateway.open(&access, &result, &hits[0]).unwrap_err(),
        StoreEvidenceError::Core(ContractError::RevisionConflict)
    );
    let authority = AuthorityBinding {
        generation: Revision::new(2),
        ..access.authority.clone()
    };
    store
        .issue_document_grant_trusted(
            &next.document,
            &authority,
            &[DocumentOperation::ReadText],
            now() + 20_000,
        )
        .unwrap();
    let next_access = DocumentAccess {
        document: next.document,
        authority,
    };
    assert!(gateway.open(&next_access, &result, &hits[0]).is_err());
    assert_eq!(reader_pins(&store), "0");
}
#[test]
fn malformed_saved_text_is_failed_processing_not_saved_or_index_success() {
    let f = Fixture::new();
    let (store, access) = f.setup(b"bad\xfftext", &[DocumentOperation::ReadText]);
    let result = StoreEvidence::new(&store)
        .process(&access, InputKind::Utf8Text)
        .unwrap();
    assert_eq!(result.receipt().extraction, ProcessingState::Failed);
    assert_eq!(result.receipt().index, ProcessingState::NotRun);
    assert_eq!(reader_pins(&store), "0");
}
#[test]
fn original_unknown_intents_are_not_looked_up_retried_or_changed() {
    let f = Fixture::new();
    let (store, access) = f.setup(b"synthetic", &[DocumentOperation::ReadText]);
    store.database().exec("INSERT INTO intents VALUES('synthetic-existing-unknown','binding','{}','unknown',NULL,NULL,'epoch')",&[]).unwrap();
    let before = store
        .database()
        .query("SELECT * FROM intents", &[])
        .unwrap();
    StoreEvidence::new(&store)
        .process(&access, InputKind::Utf8Text)
        .unwrap();
    assert_eq!(
        store
            .database()
            .query("SELECT * FROM intents", &[])
            .unwrap(),
        before
    );
}
#[test]
fn corrupt_controlled_blob_never_uses_previous_cache_as_success() {
    let f = Fixture::new();
    let (store, access) = f.setup(b"synthetic", &[DocumentOperation::ReadText]);
    let gateway = StoreEvidence::new(&store);
    let result = gateway.process(&access, InputKind::Utf8Text).unwrap();
    fs::write(
        store
            .root_dir()
            .join("objects")
            .join(&result.source_metadata().blob.digest),
        b"corrupted",
    )
    .unwrap();
    assert!(gateway
        .find_literal(&access, &result, "synthetic", 10)
        .is_err());
    assert_eq!(reader_pins(&store), "0");
}
#[test]
fn unknown_pdf_and_relabelled_pdf_never_gain_utf8_processing() {
    for (format, bytes) in [
        (DocumentFormat::Unknown, &b"synthetic"[..]),
        (DocumentFormat::Pdf, &b"synthetic"[..]),
        (DocumentFormat::Text, &b"%PDF-1.4\nsynthetic\n%%EOF"[..]),
    ] {
        let f = Fixture::new();
        let (store, access) = f.setup_format(bytes, format, &[DocumentOperation::ReadText]);
        assert_eq!(
            StoreEvidence::new(&store)
                .process(&access, InputKind::Utf8Text)
                .unwrap_err(),
            StoreEvidenceError::Processing(EvidenceError::InvalidRequest)
        );
        assert_eq!(reader_pins(&store), "0");
    }
}
#[test]
fn actual_registered_pdf_and_ocr_have_unsupported_receipt_not_fake_content() {
    for kind in [InputKind::Pdf, InputKind::Ocr] {
        let f = Fixture::new();
        let (store, access) = f.setup_format(
            b"%PDF-1.4\nsynthetic\n%%EOF",
            DocumentFormat::Pdf,
            &[DocumentOperation::ReadText],
        );
        let gateway = StoreEvidence::new(&store);
        let result = gateway.process(&access, kind).unwrap();
        assert_eq!(result.receipt().extraction, ProcessingState::Unsupported);
        assert_eq!(result.receipt().index, ProcessingState::NotRun);
        assert_eq!(
            gateway
                .find_literal(&access, &result, "synthetic", 10)
                .unwrap_err(),
            StoreEvidenceError::Processing(EvidenceError::NotAvailable)
        );
        assert_eq!(reader_pins(&store), "0");
    }
}
#[test]
fn processing_errors_release_actual_reader_pins_without_new_intents() {
    let f = Fixture::new();
    let (store, access) = f.setup(b"synthetic", &[DocumentOperation::ReadText]);
    let gateway = StoreEvidence::new(&store);
    let result = gateway.process(&access, InputKind::Utf8Text).unwrap();
    let hits = gateway
        .find_literal(&access, &result, "synthetic", 10)
        .unwrap();
    let before = store
        .database()
        .query("SELECT * FROM intents", &[])
        .unwrap();
    assert!(gateway.find_literal(&access, &result, "", 10).is_err());
    assert_eq!(reader_pins(&store), "0");
    assert!(gateway
        .answer(&access, &result, "body", &hits, &[0, 0])
        .is_err());
    assert_eq!(reader_pins(&store), "0");
    assert_eq!(
        store
            .database()
            .query("SELECT * FROM intents", &[])
            .unwrap(),
        before
    );
}
