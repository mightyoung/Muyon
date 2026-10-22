//! Actual synthetic BusinessStore/grants/temporary bytes through private native methods.
//! No renderer, Android PFD, model/search or user files. These tests are NOT_RUN until compiled.
use super::*;
use muyon_core::{blobs::BlobKind, documents::*};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicUsize, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};
static NEXT: AtomicUsize = AtomicUsize::new(0);
const TEXT: &[u8] = b"original literal evidence\nanother literal passage\n";
struct Fixture {
    core: Arc<ProductCore>,
    root: PathBuf,
    request: DocumentAccessRequest,
    access: DocumentAccess,
}
impl Fixture {
    fn new(bytes: &[u8], format: DocumentFormat, operations: &[DocumentOperation]) -> Self {
        let root = std::env::temp_dir().join(format!(
            "muyon-doc-ffi-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let core = ProductCore::open(
            root.to_str().unwrap().into(),
            "workspace".into(),
            "epoch".into(),
            true,
        )
        .unwrap();
        let access = {
            let state = core.state.lock().unwrap();
            let store = &state.store;
            let mut command = CommandEnvelope {
                protocol_version: 1,
                business_version: 1,
                intent_id: "synthetic-project".into(),
                scope: Scope {
                    workspace_id: "workspace".into(),
                    project_id: Some("project".into()),
                },
                expected_revision: Revision::new(0),
                authority: AuthorityBinding {
                    grant_id: "project-grant".into(),
                    generation: Revision::new(1),
                    owner_epoch: "epoch".into(),
                },
                plan_id: "synthetic-plan".into(),
                plan_digest: "0".repeat(64),
                command: Operation::ProjectCreate {
                    project_id: "project".into(),
                    name: "Synthetic".into(),
                },
            };
            command.plan_digest = command.expected_plan_digest().unwrap();
            store.issue_grant_trusted(&command, None).unwrap();
            assert_eq!(
                store.execute(&command).unwrap().status,
                ExecutionStatus::Committed
            );
            store.initialize_documents_trusted().unwrap();
            let upload = store.begin_upload("project").unwrap();
            for chunk in bytes.chunks(65536) {
                store.append_chunk(&upload.upload_id, chunk).unwrap();
            }
            let blob = store
                .finish_blob(&upload.upload_id, BlobKind::Document)
                .unwrap();
            let metadata = store
                .register_document_trusted(
                    "project",
                    "document",
                    "Synthetic original",
                    format,
                    &blob,
                )
                .unwrap();
            let authority = AuthorityBinding {
                grant_id: "document-grant".into(),
                generation: Revision::new(1),
                owner_epoch: "epoch".into(),
            };
            let expiry = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64
                + 25_000;
            store
                .issue_document_grant_trusted(&metadata.document, &authority, operations, expiry)
                .unwrap();
            DocumentAccess {
                document: metadata.document,
                authority,
            }
        };
        let request = DocumentAccessRequest {
            scope: DocumentReaderScope {
                service_session: "service-session".into(),
                generation: "generation-1".into(),
                project: Some("project".into()),
            },
            document_ref_json: serde_json::to_string(&access.document).unwrap(),
            grant_id: access.authority.grant_id.clone(),
            grant_generation: "1".into(),
        };
        Self {
            core,
            root,
            request,
            access,
        }
    }
    fn text() -> Self {
        Self::new(
            TEXT,
            DocumentFormat::Text,
            &[DocumentOperation::Inspect, DocumentOperation::ReadText],
        )
    }
    fn open(&self) -> DocumentReadUseRequest {
        let value: Value = serde_json::from_str(
            &self
                .core
                .document_read_open(self.request.clone(), DocumentReadOperation::ReadText)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(value["display_lease"], false);
        assert_eq!(value["safety_status"], "not_assessed");
        assert!(value["expires_at_ms"].is_null());
        DocumentReadUseRequest {
            scope: self.request.scope.clone(),
            read_session_id: value["read_session_id"].as_str().unwrap().into(),
        }
    }
    fn process(&self) -> DocumentEvidenceUseRequest {
        let value: Value = serde_json::from_str(
            &self
                .core
                .document_evidence_process(self.request.clone(), DocumentEvidenceKind::Utf8Text)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(value["projection"]["processing"]["extraction"], "available");
        assert_eq!(value["projection"]["processing"]["index"], "not_run");
        assert!(value.get("saved").is_none());
        DocumentEvidenceUseRequest {
            scope: self.request.scope.clone(),
            processing_id: value["processing_id"].as_str().unwrap().into(),
        }
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = self
            .core
            .document_read_release_owner(self.request.scope.service_session.clone());
        let _ = fs::remove_dir_all(&self.root);
    }
}
fn value(raw: String) -> Value {
    serde_json::from_str(&raw).unwrap()
}

#[test]
fn actual_metadata_and_bytes_mark_eof_closed_not_display_authority() {
    let f = Fixture::text();
    let metadata = value(f.core.document_metadata(f.request.clone()).unwrap());
    assert_eq!(
        metadata["document"]["document"],
        serde_json::to_value(&f.access.document).unwrap()
    );
    assert_eq!(metadata["annotation_editing"], false);
    let opened = f.open();
    let mut bytes = Vec::new();
    loop {
        let chunk = f.core.document_read_chunk(opened.clone(), 7).unwrap();
        assert_eq!(chunk.offset.parse::<usize>().unwrap(), bytes.len());
        bytes.extend_from_slice(&chunk.bytes);
        if chunk.eof {
            assert!(!chunk.session_active);
            break;
        }
        assert!(chunk.session_active);
    }
    assert_eq!(bytes, TEXT);
    let closed = value(f.core.document_read_check(opened.clone()).unwrap());
    assert_eq!(closed["status"], "invalidated");
    f.core.document_read_close(opened).unwrap();
}

#[test]
fn foreign_service_generation_and_project_never_borrow_a_live_reader() {
    let f = Fixture::text();
    let opened = f.open();
    let mut wrong = opened.clone();
    wrong.scope.service_session = "other".into();
    assert!(f.core.document_read_chunk(wrong.clone(), 7).is_err());
    assert!(f.core.document_read_close(wrong).is_err());
    let mut wrong = opened.clone();
    wrong.scope.generation = "old".into();
    assert!(f.core.document_read_check(wrong).is_err());
    let mut wrong = opened.clone();
    wrong.scope.project = Some("other".into());
    assert!(f.core.document_read_chunk(wrong, 7).is_err());
    assert_eq!(
        value(f.core.document_read_check(opened.clone()).unwrap())["status"],
        "current"
    );
    f.core.document_read_close(opened).unwrap();
}

#[test]
fn forged_or_inspect_only_grants_do_not_open_or_issue_read_permission() {
    let f = Fixture::new(TEXT, DocumentFormat::Text, &[DocumentOperation::Inspect]);
    assert!(f.core.document_metadata(f.request.clone()).is_ok());
    assert!(f
        .core
        .document_read_open(f.request.clone(), DocumentReadOperation::ReadText)
        .is_err());
    let mut forged = f.request.clone();
    forged.grant_id = "unissued".into();
    assert!(f.core.document_metadata(forged).is_err());
    let mut wrong = f.request.clone();
    wrong.scope.project = Some("other".into());
    assert!(f.core.document_metadata(wrong).is_err());
    let mut wrong = f.request.clone();
    let mut reference: Value = serde_json::from_str(&wrong.document_ref_json).unwrap();
    reference["scope"]["workspace_id"] = json!("other");
    wrong.document_ref_json = reference.to_string();
    assert!(f.core.document_metadata(wrong).is_err());
}

#[test]
fn revoked_current_grant_discards_bytes_and_publishes_invalidation() {
    let f = Fixture::text();
    let opened = f.open();
    f.core
        .state
        .lock()
        .unwrap()
        .store
        .revoke_document_grant_trusted(&f.access.authority)
        .unwrap();
    assert!(f.core.document_read_chunk(opened.clone(), 7).is_err());
    assert_eq!(
        value(f.core.document_read_check(opened).unwrap())["status"],
        "invalidated"
    );
}

#[test]
fn deleted_project_and_chunk_limit_errors_never_yield_successful_bytes() {
    let f = Fixture::text();
    let opened = f.open();
    assert!(f.core.document_read_chunk(opened.clone(), 65537).is_err());
    assert_eq!(
        value(f.core.document_read_check(opened).unwrap())["status"],
        "invalidated"
    );
    let opened = f.open();
    let db = muyon_core::sqlite::Db::open(
        f.root.join("business-v2.sqlite").to_str().unwrap(),
        false,
        false,
    )
    .unwrap();
    db.exec("UPDATE projects SET deleted=1 WHERE id='project'", &[])
        .unwrap();
    assert!(f.core.document_read_chunk(opened, 7).is_err());
}

#[test]
fn evidence_uses_real_text_explicit_citations_and_exact_query_snapshot() {
    let f = Fixture::new(TEXT, DocumentFormat::Text, &[DocumentOperation::ReadText]);
    let context = f.process();
    let query = value(
        f.core
            .document_evidence_query(context.clone(), "literal".into(), 8)
            .unwrap(),
    );
    assert_eq!(query["hits"].as_array().unwrap().len(), 2);
    let query_id = query["query_id"].as_str().unwrap().to_owned();
    let evidence_id = query["hits"][0]["evidence_id"].as_str().unwrap().to_owned();
    let quote = value(
        f.core
            .document_evidence_quote(context.clone(), query_id.clone(), evidence_id.clone())
            .unwrap(),
    );
    assert_eq!(quote["quote"], "literal");
    let uncited = value(
        f.core
            .document_evidence_answer(DocumentEvidenceAnswerRequest {
                context: context.clone(),
                query_id: query_id.clone(),
                body: "body [1] is not a citation".into(),
                cited_indices: vec![],
            })
            .unwrap(),
    );
    assert!(uncited["answer"]["citations"]
        .as_array()
        .unwrap()
        .is_empty());
    let cited = value(
        f.core
            .document_evidence_answer(DocumentEvidenceAnswerRequest {
                context: context.clone(),
                query_id: query_id.clone(),
                body: "explicit passage".into(),
                cited_indices: vec![0],
            })
            .unwrap(),
    );
    assert_eq!(cited["answer"]["citations"][0]["number"], 1);
    assert!(cited["answer"]["citations"][0]["evidence"]["page_index_zero_based"].is_null());
    assert!(cited["answer"]["independent_support_count"].is_null());
    f.core
        .document_evidence_query(context.clone(), "another".into(), 8)
        .unwrap();
    assert!(f
        .core
        .document_evidence_quote(context, query_id, evidence_id)
        .is_err());
}

#[test]
fn processing_cache_is_not_a_grant_and_other_sessions_cannot_read_it() {
    let f = Fixture::text();
    let context = f.process();
    let mut foreign = context.clone();
    foreign.scope.service_session = "other".into();
    assert!(f
        .core
        .document_evidence_query(foreign, "literal".into(), 8)
        .is_err());
    f.core
        .state
        .lock()
        .unwrap()
        .store
        .revoke_document_grant_trusted(&f.access.authority)
        .unwrap();
    assert!(f
        .core
        .document_evidence_query(context, "literal".into(), 8)
        .is_err());
}

#[test]
fn pdf_processing_remains_unsupported_and_never_claims_a_renderer() {
    let f = Fixture::new(
        b"%PDF-1.4\nsynthetic only\n%%EOF\n",
        DocumentFormat::Pdf,
        &[DocumentOperation::ReadText],
    );
    let result = value(
        f.core
            .document_evidence_process(f.request.clone(), DocumentEvidenceKind::Pdf)
            .unwrap(),
    );
    assert_eq!(
        result["projection"]["processing"]["extraction"],
        "unsupported"
    );
    assert_eq!(result["projection"]["processing"]["index"], "not_run");
    assert!(result.get("saved").is_none());
}

#[test]
fn owner_release_closes_only_its_sessions_and_evidence() {
    let f = Fixture::text();
    let first = f.open();
    let context = f.process();
    let mut other = f.request.clone();
    other.scope.service_session = "second-session".into();
    let result = value(
        f.core
            .document_read_open(other.clone(), DocumentReadOperation::ReadText)
            .unwrap(),
    );
    let other_use = DocumentReadUseRequest {
        scope: other.scope,
        read_session_id: result["read_session_id"].as_str().unwrap().into(),
    };
    f.core
        .document_read_release_owner(f.request.scope.service_session.clone())
        .unwrap();
    assert_eq!(
        value(f.core.document_read_check(first).unwrap())["status"],
        "invalidated"
    );
    assert!(f
        .core
        .document_evidence_query(context, "literal".into(), 8)
        .is_err());
    assert_eq!(
        value(f.core.document_read_check(other_use.clone()).unwrap())["status"],
        "current"
    );
    f.core.document_read_close(other_use).unwrap();
}

#[test]
fn eight_invalidated_native_ids_do_not_block_fresh_authorized_admission() {
    let f = Fixture::text();
    let old: Vec<_> = (0..8).map(|_| f.open()).collect();
    assert!(f
        .core
        .document_read_open(f.request.clone(), DocumentReadOperation::ReadText)
        .is_err());
    let mut authority = f.access.authority.clone();
    authority.generation = Revision::new(2);
    let expiry = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
        + 25_000;
    f.core
        .state
        .lock()
        .unwrap()
        .store
        .issue_document_grant_trusted(
            &f.access.document,
            &authority,
            &[DocumentOperation::Inspect, DocumentOperation::ReadText],
            expiry,
        )
        .unwrap();
    let mut request = f.request.clone();
    request.grant_generation = "2".into();
    let fresh = value(
        f.core
            .document_read_open(request.clone(), DocumentReadOperation::ReadText)
            .unwrap(),
    );
    let use_request = DocumentReadUseRequest {
        scope: request.scope,
        read_session_id: fresh["read_session_id"].as_str().unwrap().into(),
    };
    assert_eq!(
        f.core
            .document_read_chunk(use_request, 65536)
            .unwrap()
            .bytes,
        TEXT
    );
    for previous in old {
        assert_eq!(
            value(f.core.document_read_check(previous).unwrap())["status"],
            "invalidated"
        );
    }
}

#[test]
fn eight_actually_idle_expired_sessions_allow_fresh_open_without_manual_checks() {
    let f = Fixture::text();
    for _ in 0..8 {
        f.open();
    }
    // Actual monotonic core expiry: no private core hook, widened limit or fake clock.
    std::thread::sleep(std::time::Duration::from_secs(16));
    let mut fresh_authority = f.access.authority.clone();
    fresh_authority.grant_id = "fresh-after-idle".into();
    let expiry = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
        + 25_000;
    f.core
        .state
        .lock()
        .unwrap()
        .store
        .issue_document_grant_trusted(
            &f.access.document,
            &fresh_authority,
            &[DocumentOperation::ReadText],
            expiry,
        )
        .unwrap();
    let mut request = f.request.clone();
    request.grant_id = fresh_authority.grant_id;
    let fresh = value(
        f.core
            .document_read_open(request.clone(), DocumentReadOperation::ReadText)
            .unwrap(),
    );
    let use_request = DocumentReadUseRequest {
        scope: request.scope,
        read_session_id: fresh["read_session_id"].as_str().unwrap().into(),
    };
    assert_eq!(
        f.core
            .document_read_chunk(use_request, 65536)
            .unwrap()
            .bytes,
        TEXT
    );
}

#[test]
fn readonly_annotations_and_explicit_shutdown_do_not_claim_a_display_lease() {
    let f = Fixture::text();
    let read = f.open();
    let processing = f.process();
    let annotations = value(f.core.document_annotations(f.request.clone()).unwrap());
    assert!(annotations["annotations"].as_array().unwrap().is_empty());
    assert_eq!(annotations["annotation_editing"], false);
    f.core.document_read_shutdown().unwrap();
    assert!(f.core.document_read_chunk(read, 7).is_err());
    assert!(f.core.document_metadata(f.request.clone()).is_err());
    assert!(f
        .core
        .document_evidence_query(processing, "literal".into(), 8)
        .is_err());
    assert!(f
        .core
        .document_read_open(f.request.clone(), DocumentReadOperation::ReadText)
        .is_err());
}
