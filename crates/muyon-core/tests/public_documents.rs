//! Public library reads plus a separately instrumented source-import spy boundary.
pub use muyon_core::{business, contract, documents, services};
#[path = "support/read_owner_spy.rs"]
pub mod read_owner_spy;
// The actual adapter source resolves this test-only import. Existing synthetic
// setup below keeps using muyon_core::evidence directly; only adapter work
// requests are intercepted, and every text read still calls the real owner.
pub mod evidence {
    pub use muyon_core::evidence::{EvidenceError, EvidenceRef, InputKind, ProcessingState};
    pub mod store {
        pub use crate::read_owner_spy::StoreEvidence;
        pub use muyon_core::evidence::store::{StoreEvidenceError, StoredProcessing};
    }
}
pub mod adapters {
    pub mod documents {
        include!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/src/services/documents.rs"
        ));
    }
    pub mod sources {
        include!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/src/services/sources.rs"
        ));
    }
}
// General contract tests exercise real library exports. The last test explicitly
// selects the instrumented source imports to retain its processing-request spy.
use muyon_core::services::{documents::*, sources::*};
use muyon_core::{
    blobs::BlobKind,
    business::BusinessStore,
    contract::*,
    documents::*,
    evidence::{store::*, *},
    services::types::*,
    sqlite::Db,
};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> (Self, BusinessStore) {
        let root = std::env::temp_dir().join(format!(
            "public-documents-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&root).unwrap();
        let f = Self(root);
        BusinessStore::initialize(&f.path(), "workspace").unwrap();
        let store = BusinessStore::open_existing(&f.path(), "workspace", "epoch").unwrap();
        for project in ["project", "other"] {
            let mut cmd = CommandEnvelope {
                protocol_version: 1,
                business_version: 1,
                intent_id: format!("create-{project}"),
                scope: Scope {
                    workspace_id: "workspace".into(),
                    project_id: Some(project.into()),
                },
                expected_revision: Revision::new(0),
                authority: AuthorityBinding {
                    grant_id: format!("grant-{project}"),
                    generation: Revision::new(1),
                    owner_epoch: "epoch".into(),
                },
                plan_id: format!("plan-{project}"),
                plan_digest: "0".repeat(64),
                command: Operation::ProjectCreate {
                    project_id: project.into(),
                    name: project.into(),
                },
            };
            cmd.plan_digest = cmd.expected_plan_digest().unwrap();
            store.issue_grant_trusted(&cmd, None).unwrap();
            assert_eq!(
                store.execute(&cmd).unwrap().status,
                ExecutionStatus::Committed
            );
        }
        store.initialize_documents_trusted().unwrap();
        (f, store)
    }
    fn path(&self) -> PathBuf {
        self.0.join("store.sqlite")
    }
    fn db(&self) -> Db {
        Db::open(self.path().to_str().unwrap(), false, false).unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn expires() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
        + 20_000
}
fn upload(store: &BusinessStore, project: &str, bytes: &[u8]) -> muyon_core::blobs::FinishedBlob {
    let h = store.begin_upload(project).unwrap();
    store.append_chunk(&h.upload_id, bytes).unwrap();
    store.finish_blob(&h.upload_id, BlobKind::Document).unwrap()
}
fn register(
    store: &BusinessStore,
    project: &str,
    bytes: &[u8],
    format: DocumentFormat,
    ops: &[DocumentOperation],
) -> DocumentAccess {
    let metadata = store
        .register_document_trusted(
            project,
            "document",
            "Synthetic",
            format,
            &upload(store, project, bytes),
        )
        .unwrap();
    let authority = AuthorityBinding {
        grant_id: format!("text-{project}"),
        generation: Revision::new(1),
        owner_epoch: "epoch".into(),
    };
    store
        .issue_document_grant_trusted(&metadata.document, &authority, ops, expires())
        .unwrap();
    DocumentAccess {
        document: metadata.document,
        authority,
    }
}
fn text(store: &BusinessStore) -> (DocumentAccess, StoredProcessing, Vec<EvidenceRef>) {
    let access = register(
        store,
        "project",
        "甲😀乙".as_bytes(),
        DocumentFormat::Text,
        &[DocumentOperation::Inspect, DocumentOperation::ReadText],
    );
    let owner = StoreEvidence::new(store);
    let processing = owner.process(&access, InputKind::Utf8Text).unwrap();
    let hits = owner.find_literal(&access, &processing, "😀", 1).unwrap();
    (access, processing, hits)
}
#[test]
fn exact_utf8_anchor_checks() {
    let (_f, store) = Fixture::new();
    let (access, p, hits) = text(&store);
    assert_eq!((hits[0].start_byte, hits[0].end_byte), (3, 7));
    assert_eq!(read_blocks(&store, &access, &p, &hits).unwrap(), vec!["😀"]);
    let locator = source_locator(&p, &hits[0]).unwrap();
    let opened = resolve_anchor(&store, &access, &p, &locator).unwrap();
    assert_eq!(opened.quote, "😀");
    assert_eq!(opened.document, access.document);
    for mutate in 0..6 {
        let mut bad = locator.clone();
        match mutate {
            0 => bad.text_result_ref = ResultId::parse("other-result").unwrap(),
            1 => bad.text_digest = Digest::parse(&"0".repeat(64)).unwrap(),
            2 => bad.normalization_version = "other".into(),
            3 => bad.evidence.start_byte = 4,
            4 => bad.evidence.evidence_id = "forged".into(),
            _ => bad.evidence.page_index_zero_based = Some(0),
        }
        assert!(
            resolve_anchor(&store, &access, &p, &bad).is_err(),
            "mutation {mutate}"
        );
    }
    let mut forged = hits[0].clone();
    forged.end_byte = 8;
    assert!(read_blocks(&store, &access, &p, &[forged]).is_err());
}
#[test]
fn processing_identity_is_result_metadata_not_business_receipt() {
    let (_f, store) = Fixture::new();
    let (access, p, hits) = text(&store);
    let result = describe_processing(&p).unwrap();
    assert_eq!(result.reference.result_id.as_str(), p.receipt().receipt_id);
    assert_eq!(result.reference.result_id.as_str().len(), 75);
    assert_eq!(result.reference.input_document_ref, access.document);
    assert!(result.reference.input_result_refs.is_empty());
    assert_eq!(result.reference.producer_version, p.receipt().processor);
    assert_eq!(
        result.reference.content_digest.as_str(),
        p.receipt().source.blob.digest
    );
    assert_eq!(result.normalization_version, "utf8-original-v1");
    let expected = stable_digest(&serde_json::json!({"input_kind":"utf8_text"})).unwrap();
    assert_eq!(result.reference.parameters_digest.as_str(), expected);
    assert_eq!(result.coverage.state, CoverageState::Complete);
    assert_eq!(
        (result.coverage.processed, result.coverage.total),
        (10, Some(10))
    );
    let wire = serde_json::to_value(&result).unwrap();
    assert!(wire.get("text").is_none());
    assert!(!wire.to_string().contains("甲"));
    assert_eq!(
        source_locator(&p, &hits[0]).unwrap().text_result_ref,
        result.reference.result_id
    );
    assert!(wire.get("intent_id").is_none());
}
#[test]
fn scope_revocation_and_old_version_checks() {
    let (f, store) = Fixture::new();
    let (access, p, hits) = text(&store);
    let other = register(
        &store,
        "other",
        "甲😀乙".as_bytes(),
        DocumentFormat::Text,
        &[DocumentOperation::Inspect, DocumentOperation::ReadText],
    );
    let other_p = StoreEvidence::new(&store)
        .process(&other, InputKind::Utf8Text)
        .unwrap();
    assert_eq!(
        p.receipt().source.blob.digest,
        other_p.receipt().source.blob.digest
    );
    assert_ne!(p.receipt().receipt_id, other_p.receipt().receipt_id);
    assert!(read_blocks(&store, &other, &p, &hits).is_err());
    let mut foreign = hits[0].clone();
    foreign.source = other_p.receipt().source.clone();
    assert!(source_locator(&p, &foreign).is_err());
    let locator = source_locator(&p, &hits[0]).unwrap();
    let next = store
        .publish_document_revision_trusted(
            &access.document,
            "new",
            DocumentFormat::Text,
            &upload(&store, "project", b"next"),
        )
        .unwrap();
    assert_ne!(next.document, access.document);
    assert_eq!(
        read_blocks(&store, &access, &p, &hits).unwrap_err().code,
        ErrorCode::StaleRevision
    );
    assert!(resolve_anchor(&store, &access, &p, &locator).is_err());
    assert_eq!(
        describe_processing(&p)
            .unwrap()
            .reference
            .input_document_ref,
        access.document
    );
    f.db()
        .exec("UPDATE projects SET deleted=1 WHERE id='other'", &[])
        .unwrap();
    assert!(get_metadata(&store, &other).is_err());
}
#[test]
fn getters_recheck_revocation_and_original_bytes_without_implicit_processing() {
    for mutation in [
        "UPDATE document_grants SET active=0",
        "UPDATE document_grants SET expires_at_ms='0'",
        "UPDATE projects SET deleted=1 WHERE id='project'",
        "UPDATE blobs SET state='deleting'",
    ] {
        let (f, store) = Fixture::new();
        let (access, p, hits) = text(&store);
        let before = serde_json::to_value(p.receipt()).unwrap();
        assert_eq!(
            get_metadata(&store, &access).unwrap().document,
            access.document
        );
        let locator = source_locator(&p, &hits[0]).unwrap();
        f.db().exec(mutation, &[]).unwrap();
        assert!(
            read_blocks(&store, &access, &p, &hits).is_err(),
            "{mutation}"
        );
        assert!(
            read_blocks(&store, &access, &p, &[]).is_err(),
            "empty read: {mutation}"
        );
        assert!(
            resolve_anchor(&store, &access, &p, &locator).is_err(),
            "{mutation}"
        );
        assert_eq!(serde_json::to_value(p.receipt()).unwrap(), before);
        assert_eq!(
            describe_processing(&p)
                .unwrap()
                .reference
                .input_document_ref,
            access.document
        );
    }
}
#[test]
fn unsupported_and_failed_results_never_claim_text_coverage() {
    for (bytes, format, kind) in [
        (&b"%PDF-synthetic"[..], DocumentFormat::Pdf, InputKind::Pdf),
        (&b"   "[..], DocumentFormat::Text, InputKind::Utf8Text),
    ] {
        let (_f, store) = Fixture::new();
        let access = register(
            &store,
            "project",
            bytes,
            format,
            &[DocumentOperation::ReadText],
        );
        let p = StoreEvidence::new(&store).process(&access, kind).unwrap();
        assert_eq!(
            describe_processing(&p).unwrap_err().code,
            ErrorCode::CapabilityUnavailable
        );
        assert_eq!(p.receipt().index, ProcessingState::NotRun);
        assert!(
            get_metadata(&store, &access).is_err(),
            "ReadText is not Inspect"
        );
    }
}

#[test]
fn processing_spy_is_active_and_never_runs_a_processor() {
    let (_fixture, store) = Fixture::new();
    let (access, _processing, _hits) = text(&store);
    read_owner_spy::reset();
    let owner = read_owner_spy::StoreEvidence::new(&store);
    for kind in [InputKind::Utf8Text, InputKind::Pdf, InputKind::Ocr] {
        assert_eq!(
            owner.process(&access, kind).unwrap_err(),
            StoreEvidenceError::Processing(EvidenceError::NotAvailable)
        );
    }
    assert_eq!(
        read_owner_spy::counts(),
        read_owner_spy::Counts {
            open: 0,
            processing: 3,
            parse_requests: 2,
            ocr_requests: 1
        }
    );
}

#[test]
fn adapter_getters_make_zero_processing_requests_on_success_and_denial() {
    use adapters::{documents::*, sources::*};
    let (_fixture, store) = Fixture::new();
    let (access, processing, hits) = text(&store);
    read_owner_spy::reset();
    assert_eq!(
        get_metadata(&store, &access).unwrap().document,
        access.document
    );
    assert_eq!(
        describe_processing(&processing)
            .unwrap()
            .reference
            .input_document_ref,
        access.document
    );
    let locator = source_locator(&processing, &hits[0]).unwrap();
    assert_eq!(
        read_blocks(&store, &access, &processing, &hits).unwrap(),
        vec!["😀"]
    );
    assert_eq!(
        resolve_anchor(&store, &access, &processing, &locator)
            .unwrap()
            .quote,
        "😀"
    );
    assert_eq!(
        read_owner_spy::counts(),
        read_owner_spy::Counts {
            open: 2,
            ..Default::default()
        }
    );
    store
        .revoke_document_grant_trusted(&access.authority)
        .unwrap();
    read_owner_spy::reset();
    assert!(get_metadata(&store, &access).is_err());
    assert!(read_blocks(&store, &access, &processing, &hits).is_err());
    assert!(resolve_anchor(&store, &access, &processing, &locator).is_err());
    assert_eq!(
        read_owner_spy::counts(),
        read_owner_spy::Counts {
            open: 2,
            ..Default::default()
        }
    );
}
