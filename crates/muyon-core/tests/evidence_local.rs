use contract::*;
use documents::*;
use evidence::*;
use muyon_core::{contract, documents};
// Compile the real pure processor without requiring the core-owned export patch.
// The store adapter is tested separately in the same-crate owner harness.
#[path = "../src/evidence/local.rs"]
mod evidence;
use sha2::{Digest, Sha256};
use std::cell::RefCell;

struct Host(RefCell<CurrentDocument>);
impl DocumentHost for Host {
    fn resolve_current(&self, _: &ReadRequest) -> Result<CurrentDocument, ReadInvalidation> {
        Ok(self.0.borrow().clone())
    }
}
fn setup(bytes: &[u8]) -> (Host, ReadRequest) {
    let document = DocumentRef::new(
        Scope {
            workspace_id: "w".into(),
            project_id: Some("p".into()),
        },
        "doc",
        Revision::new(1),
        DocumentFormat::Text,
    )
    .unwrap();
    let authority = AuthorityBinding {
        grant_id: "g".into(),
        generation: Revision::new(1),
        owner_epoch: "epoch".into(),
    };
    let blob = BlobRef {
        digest: Sha256::digest(bytes)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect(),
        byte_length: Revision::new(bytes.len() as u64),
    };
    let host = Host(RefCell::new(CurrentDocument {
        document: document.clone(),
        authority: authority.clone(),
        access: AccessState::Active,
        source: FileSource {
            snapshot_id: "s".into(),
            blob,
            lease: ReadLease {
                lease_id: "l".into(),
                owner_epoch: "epoch".into(),
                generation: Revision::new(1),
            },
        },
        permissions: vec![DocumentOperation::ReadText],
    }));
    (
        host,
        ReadRequest {
            document,
            authority,
            operation: DocumentOperation::ReadText,
            anchor: None,
        },
    )
}
#[test]
fn synthetic_text_has_real_receipt_and_bound_utf8_anchor() {
    let bytes = "原创 α evidence\nsecond evidence".as_bytes();
    let (host, request) = setup(bytes);
    let outcome = process_local(&host, &request, InputKind::Utf8Text, bytes).unwrap();
    assert_eq!(outcome.receipt().extraction, ProcessingState::Available);
    assert_eq!(outcome.receipt().index, ProcessingState::NotRun);
    let hits = outcome
        .find_literal(&host, &request, "α evidence", 10)
        .unwrap();
    assert_eq!(hits.len(), 1);
    assert_eq!(
        outcome.open(&host, &request, &hits[0]).unwrap(),
        "α evidence"
    );
    assert_eq!(hits[0].page_index_zero_based, None);
    assert_eq!(
        outcome.receipt().events,
        vec![LocalEvent::ExtractionStarted, LocalEvent::Extracted]
    );
    assert!(serde_json::to_string(outcome.receipt())
        .unwrap()
        .contains("not_run"));
}
#[test]
fn pdf_and_ocr_never_manufacture_content() {
    for kind in [InputKind::Pdf, InputKind::Ocr] {
        let bytes = b"%PDF synthetic";
        let (host, mut request) = setup(bytes);
        let pdf = DocumentRef::new(
            request.document.scope().clone(),
            "doc",
            Revision::new(1),
            DocumentFormat::Pdf,
        )
        .unwrap();
        request.document = pdf.clone();
        host.0.borrow_mut().document = pdf;
        let outcome = process_local(&host, &request, kind, bytes).unwrap();
        assert_eq!(outcome.receipt().extraction, ProcessingState::Unsupported);
        assert_eq!(
            outcome
                .find_literal(&host, &request, "PDF", 10)
                .unwrap_err(),
            EvidenceError::NotAvailable
        );
    }
}
#[test]
fn failed_decoding_empty_and_changed_bytes_are_distinct_from_success() {
    for bytes in [&b"\xff"[..], &b"   "[..], &b"nul\0text"[..]] {
        let (host, request) = setup(bytes);
        let result = process_local(&host, &request, InputKind::Utf8Text, bytes).unwrap();
        assert_eq!(result.receipt().extraction, ProcessingState::Failed);
        assert!(result.receipt().failure.is_some());
    }
    let (host, request) = setup(b"first");
    assert_eq!(
        process_local(&host, &request, InputKind::Utf8Text, b"other").unwrap_err(),
        EvidenceError::SourceMismatch
    );
}
#[test]
fn cache_access_rechecks_revision_scope_and_revocation() {
    let (host, request) = setup(b"evidence");
    let outcome = process_local(&host, &request, InputKind::Utf8Text, b"evidence").unwrap();
    let hit = outcome
        .find_literal(&host, &request, "evidence", 10)
        .unwrap()
        .remove(0);
    host.0.borrow_mut().access = AccessState::Unknown;
    assert!(outcome.open(&host, &request, &hit).is_err());
    host.0.borrow_mut().access = AccessState::Active;
    for (project, revision) in [("other", 1), ("p", 2)] {
        host.0.borrow_mut().document = DocumentRef::new(
            Scope {
                workspace_id: "w".into(),
                project_id: Some(project.into()),
            },
            "doc",
            Revision::new(revision),
            DocumentFormat::Text,
        )
        .unwrap();
        assert!(outcome.open(&host, &request, &hit).is_err());
    }
}
#[test]
fn forged_ranges_source_and_page_do_not_resolve() {
    let (host, request) = setup("α evidence".as_bytes());
    let outcome = process_local(
        &host,
        &request,
        InputKind::Utf8Text,
        "α evidence".as_bytes(),
    )
    .unwrap();
    let hit = outcome
        .find_literal(&host, &request, "α", 10)
        .unwrap()
        .remove(0);
    let mut forged = hit.clone();
    forged.start_byte = 1;
    assert!(outcome.open(&host, &request, &forged).is_err());
    let mut forged = hit.clone();
    forged.source_id = "forged".into();
    assert!(outcome.open(&host, &request, &forged).is_err());
    let mut forged = hit;
    forged.page_index_zero_based = Some(0);
    assert!(outcome.open(&host, &request, &forged).is_err());
}
#[test]
fn body_citations_and_candidates_are_separate_and_citation_numbers_are_stable() {
    let (host, request) = setup(b"alpha beta alpha");
    let outcome = process_local(&host, &request, InputKind::Utf8Text, b"alpha beta alpha").unwrap();
    let hits = outcome.find_literal(&host, &request, "alpha", 10).unwrap();
    let answer = outcome
        .answer(&host, &request, "A claim remains unverified.", &hits, &[1])
        .unwrap();
    assert_eq!(answer.body, "A claim remains unverified.");
    assert_eq!(answer.citations.len(), 1);
    assert_eq!(answer.candidates.len(), 1);
    assert_eq!(answer.citations[0].number, 1);
    assert_eq!(answer.citations[0].support, ClaimSupport::Unassessed);
    assert_eq!(answer.distinct_cited_source_count, 1);
    assert_eq!(answer.independent_support_count, None);
    assert!(outcome
        .answer(&host, &request, "body", &hits, &[0, 0])
        .is_err());
    assert!(outcome
        .answer(&host, &request, "body", &hits, &[2])
        .is_err());
}
#[test]
fn no_read_permission_never_gains_whole_text() {
    let (host, request) = setup(b"evidence");
    host.0.borrow_mut().permissions.clear();
    assert!(process_local(&host, &request, InputKind::Utf8Text, b"evidence").is_err());
}
#[test]
fn debug_never_discloses_cached_text_after_revocation() {
    let bytes = b"PRIVATE synthetic passage";
    let (host, request) = setup(bytes);
    let outcome = process_local(&host, &request, InputKind::Utf8Text, bytes).unwrap();
    host.0.borrow_mut().access = AccessState::Revoked;
    assert!(!format!("{outcome:?}").contains("PRIVATE"));
}
#[test]
fn anchored_request_and_inspect_do_not_expand_to_whole_text() {
    let (host, mut request) = setup(b"synthetic passage");
    request.anchor = Some(DocumentAnchor {
        document: request.document.clone(),
        location: AnchorLocation::Docx {
            part: "word/document.xml".into(),
            paragraph_id: "p1".into(),
        },
    });
    assert_eq!(
        process_local(&host, &request, InputKind::Utf8Text, b"synthetic passage").unwrap_err(),
        EvidenceError::InvalidRequest
    );
    request.anchor = None;
    request.operation = DocumentOperation::Inspect;
    assert_eq!(
        process_local(&host, &request, InputKind::Utf8Text, b"synthetic passage").unwrap_err(),
        EvidenceError::InvalidRequest
    );
}
#[test]
fn changed_blob_and_authority_invalidate_existing_derivation() {
    let (host, request) = setup(b"synthetic passage");
    let outcome =
        process_local(&host, &request, InputKind::Utf8Text, b"synthetic passage").unwrap();
    let hit = outcome
        .find_literal(&host, &request, "synthetic", 10)
        .unwrap()
        .remove(0);
    host.0.borrow_mut().source.blob.digest = "a".repeat(64);
    assert_eq!(
        outcome.open(&host, &request, &hit).unwrap_err(),
        EvidenceError::SourceMismatch
    );
    for change in 0..2 {
        let (host, request) = setup(b"synthetic passage");
        let outcome =
            process_local(&host, &request, InputKind::Utf8Text, b"synthetic passage").unwrap();
        if change == 0 {
            host.0.borrow_mut().authority.generation = Revision::new(2);
        } else {
            host.0.borrow_mut().authority.owner_epoch = "epoch2".into();
        }
        assert!(outcome
            .find_literal(&host, &request, "synthetic", 10)
            .is_err());
    }
}
#[test]
fn citation_order_is_explicit_and_repeated_processing_has_same_identity() {
    let (host, request) = setup(b"alpha alpha");
    let first = process_local(&host, &request, InputKind::Utf8Text, b"alpha alpha").unwrap();
    let second = process_local(&host, &request, InputKind::Utf8Text, b"alpha alpha").unwrap();
    assert_eq!(first.receipt().receipt_id, second.receipt().receipt_id);
    let hits = first.find_literal(&host, &request, "alpha", 10).unwrap();
    let answer = first
        .answer(&host, &request, "body", &hits, &[1, 0])
        .unwrap();
    assert_eq!(answer.citations[0].evidence, hits[1]);
    assert_eq!(answer.citations[1].evidence, hits[0]);
    assert_eq!(answer.citations[1].number, 2);
    assert_eq!(answer.distinct_cited_source_count, 1);
    assert!(answer.candidates.is_empty());
}
struct RevokeDuringUse {
    current: CurrentDocument,
    calls: std::cell::Cell<usize>,
}
impl DocumentHost for RevokeDuringUse {
    fn resolve_current(&self, _: &ReadRequest) -> Result<CurrentDocument, ReadInvalidation> {
        let call = self.calls.get();
        self.calls.set(call + 1);
        let mut value = self.current.clone();
        if call > 0 {
            value.access = AccessState::Revoked;
        }
        Ok(value)
    }
}
#[test]
fn revocation_between_checks_never_delivers_extraction() {
    let (host, request) = setup(b"synthetic");
    let revoker = RevokeDuringUse {
        current: host.0.into_inner(),
        calls: std::cell::Cell::new(0),
    };
    assert_eq!(
        process_local(&revoker, &request, InputKind::Utf8Text, b"synthetic").unwrap_err(),
        EvidenceError::Denied
    );
}
#[test]
fn every_derived_delivery_rechecks_permission_after_computation() {
    let (host, request) = setup(b"synthetic");
    let outcome = process_local(&host, &request, InputKind::Utf8Text, b"synthetic").unwrap();
    let hits = outcome
        .find_literal(&host, &request, "synthetic", 10)
        .unwrap();
    for operation in 0..3 {
        let revoker = RevokeDuringUse {
            current: host.0.borrow().clone(),
            calls: std::cell::Cell::new(0),
        };
        let error = match operation {
            0 => outcome.open(&revoker, &request, &hits[0]).unwrap_err(),
            1 => outcome
                .find_literal(&revoker, &request, "synthetic", 10)
                .unwrap_err(),
            _ => outcome
                .answer(&revoker, &request, "claim", &hits, &[0])
                .unwrap_err(),
        };
        assert_eq!(error, EvidenceError::Denied);
    }
}
#[test]
fn source_identity_separates_same_bytes_across_scope_document_and_revision() {
    let (host, request) = setup(b"synthetic");
    let first = process_local(&host, &request, InputKind::Utf8Text, b"synthetic").unwrap();
    for (project, document_id, revision) in
        [("other", "doc", 1), ("p", "other", 1), ("p", "doc", 2)]
    {
        let document = DocumentRef::new(
            Scope {
                workspace_id: "w".into(),
                project_id: Some(project.into()),
            },
            document_id,
            Revision::new(revision),
            DocumentFormat::Text,
        )
        .unwrap();
        host.0.borrow_mut().document = document.clone();
        let changed = ReadRequest {
            document,
            authority: request.authority.clone(),
            operation: DocumentOperation::ReadText,
            anchor: None,
        };
        let next = process_local(&host, &changed, InputKind::Utf8Text, b"synthetic").unwrap();
        assert_ne!(first.receipt().source_id, next.receipt().source_id);
    }
}
#[test]
fn limits_reject_overlarge_queries_invalid_limits_and_oversized_sources() {
    let (host, request) = setup(b"synthetic");
    let outcome = process_local(&host, &request, InputKind::Utf8Text, b"synthetic").unwrap();
    for query in ["", " ", "x\0y"] {
        assert_eq!(
            outcome
                .find_literal(&host, &request, query, 10)
                .unwrap_err(),
            EvidenceError::InvalidRequest
        );
    }
    for limit in [0, 101] {
        assert!(outcome
            .find_literal(&host, &request, "synthetic", limit)
            .is_err());
    }
    assert!(outcome
        .find_literal(&host, &request, &"x".repeat(4097), 10)
        .is_err());
    let bytes = vec![b'x'; 2_000_001];
    let (host, request) = setup(&bytes);
    assert_eq!(
        process_local(&host, &request, InputKind::Utf8Text, &bytes).unwrap_err(),
        EvidenceError::LimitExceeded
    );
}
#[test]
fn unknown_format_never_becomes_utf8_by_caller_assertion() {
    let (host, mut request) = setup(b"synthetic");
    let unknown = DocumentRef::new(
        request.document.scope().clone(),
        "doc",
        Revision::new(1),
        DocumentFormat::Unknown,
    )
    .unwrap();
    host.0.borrow_mut().document = unknown.clone();
    request.document = unknown;
    assert_eq!(
        process_local(&host, &request, InputKind::Utf8Text, b"synthetic").unwrap_err(),
        EvidenceError::InvalidRequest
    );
}
