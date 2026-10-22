//! Offline contract tests, not engine or host integration acceptance.
use muyon_core::{contract::*, documents::*};
use std::cell::{Cell, RefCell};

fn document(project: &str, revision: u64, format: DocumentFormat) -> DocumentRef {
    DocumentRef::new(
        Scope { workspace_id: "workspace".into(), project_id: Some(project.into()) },
        "document", Revision::new(revision), format,
    ).unwrap()
}
fn authority() -> AuthorityBinding {
    AuthorityBinding { grant_id: "grant".into(), generation: Revision::new(1), owner_epoch: "epoch".into() }
}
fn request() -> ReadRequest {
    ReadRequest { document: document("project", 1, DocumentFormat::Pdf), authority: authority(), operation: DocumentOperation::ReadText, anchor: None }
}
struct Host { current: RefCell<CurrentDocument>, calls: Cell<usize> }
impl DocumentHost for Host {
    fn resolve_current(&self, _: &ReadRequest) -> Result<CurrentDocument, ReadInvalidation> {
        self.calls.set(self.calls.get() + 1);
        Ok(self.current.borrow().clone())
    }
}
fn host() -> Host {
    Host { current: RefCell::new(CurrentDocument {
        document: request().document, authority: authority(), access: AccessState::Active,
        source: FileSource { snapshot_id: "snapshot".into(), blob: BlobRef { digest: "a".repeat(64), byte_length: Revision::new(10) }, lease: ReadLease { lease_id: "lease".into(), owner_epoch: "epoch".into(), generation: Revision::new(1) } },
        permissions: vec![DocumentOperation::ReadText],
    }), calls: Cell::new(0) }
}
fn capabilities() -> CapabilityMatrix {
    let mut matrix = CapabilityMatrix::default();
    matrix.set(DocumentFormat::Pdf, DocumentOperation::ReadText, CapabilityStatus::Supported);
    matrix
}

#[test]
fn declared_format_never_enables_a_reader() {
    for format in [DocumentFormat::Docx, DocumentFormat::Pptx, DocumentFormat::Xlsx, DocumentFormat::Pdf, DocumentFormat::Doc, DocumentFormat::Ppt, DocumentFormat::Xls, DocumentFormat::Unknown] {
        assert_eq!(CapabilityMatrix::default().status(format, DocumentOperation::ReadText), CapabilityStatus::Unknown);
    }
    assert_eq!(validate_read(&host(), &request(), &CapabilityMatrix::default()), Err(ReadInvalidation::CapabilityUnavailable));
}
#[test]
fn current_host_and_operation_capability_must_both_allow_read() {
    let h = host();
    assert_eq!(validate_read(&h, &request(), &capabilities()), Ok(()));
    h.current.borrow_mut().permissions.clear();
    assert_eq!(validate_read(&h, &request(), &capabilities()), Err(ReadInvalidation::PermissionDenied));
}
#[test]
fn capability_for_other_operation_or_format_grants_nothing() {
    let mut c = CapabilityMatrix::default();
    c.set(DocumentFormat::Docx, DocumentOperation::ReadText, CapabilityStatus::Supported);
    c.set(DocumentFormat::Pdf, DocumentOperation::Render, CapabilityStatus::Supported);
    assert_eq!(validate_read(&host(), &request(), &c), Err(ReadInvalidation::CapabilityUnavailable));
}
#[test]
fn unsupported_and_gated_capabilities_deny() {
    for status in [CapabilityStatus::Unknown, CapabilityStatus::Unsupported, CapabilityStatus::NeedsLicense, CapabilityStatus::NeedsNetwork] {
        let mut c = capabilities();
        c.set(DocumentFormat::Pdf, DocumentOperation::ReadText, status);
        assert_eq!(validate_read(&host(), &request(), &c), Err(ReadInvalidation::CapabilityUnavailable));
    }
}
#[test]
fn workspace_and_project_are_exact_not_wildcards() {
    for scope in [Scope { workspace_id: "other".into(), project_id: Some("project".into()) }, Scope { workspace_id: "workspace".into(), project_id: None }, Scope { workspace_id: "workspace".into(), project_id: Some("other".into()) }] {
        let mut r = request();
        r.document = DocumentRef::new(scope, "document", Revision::new(1), DocumentFormat::Pdf).unwrap();
        assert_eq!(validate_read(&host(), &r, &capabilities()), Err(ReadInvalidation::ScopeMismatch));
    }
}
#[test]
fn old_revision_or_other_document_is_rejected() {
    let h = host();
    h.current.borrow_mut().document = document("project", 2, DocumentFormat::Pdf);
    assert_eq!(validate_read(&h, &request(), &capabilities()), Err(ReadInvalidation::StaleRevision));
    let mut r = request();
    r.document = DocumentRef::new(r.document.scope().clone(), "other", Revision::new(2), DocumentFormat::Pdf).unwrap();
    assert_eq!(validate_read(&h, &r, &capabilities()), Err(ReadInvalidation::DocumentMismatch));
}
#[test]
fn cached_metadata_never_bypasses_revocation_or_unknown_authority() {
    let h = host();
    assert_eq!(validate_read(&h, &request(), &capabilities()), Ok(()));
    for state in [AccessState::Revoked, AccessState::Unknown] {
        h.current.borrow_mut().access = state;
        assert_eq!(validate_read(&h, &request(), &capabilities()), Err(ReadInvalidation::AuthorityUnavailable));
    }
    assert_eq!(h.calls.get(), 3);
}
#[test]
fn stale_grant_epoch_generation_and_id_are_rejected() {
    for binding in [AuthorityBinding { owner_epoch: "old".into(), ..authority() }, AuthorityBinding { generation: Revision::new(2), ..authority() }, AuthorityBinding { grant_id: "other".into(), ..authority() }, AuthorityBinding { generation: Revision::new(0), ..authority() }] {
        let mut r = request(); r.authority = binding;
        assert_eq!(validate_read(&host(), &r, &capabilities()), Err(ReadInvalidation::AuthorityUnavailable));
    }
}
#[test]
fn host_errors_and_invalid_or_stale_lease_fail_closed() {
    struct Missing;
    impl DocumentHost for Missing {
        fn resolve_current(&self, _: &ReadRequest) -> Result<CurrentDocument, ReadInvalidation> { Err(ReadInvalidation::HostUnavailable) }
    }
    assert_eq!(validate_read(&Missing, &request(), &capabilities()), Err(ReadInvalidation::HostUnavailable));
    for generation in [0, 1] {
        let h = host();
        h.current.borrow_mut().source.lease.generation = Revision::new(generation);
        h.current.borrow_mut().source.lease.owner_epoch = "old".into();
        assert_eq!(validate_read(&h, &request(), &capabilities()), Err(ReadInvalidation::AuthorityUnavailable));
    }
}
#[test]
fn read_contract_cannot_admit_edit_even_when_both_lists_allow_it() {
    let h = host(); let mut r = request(); let mut c = capabilities();
    r.operation = DocumentOperation::StructuredEdit;
    h.current.borrow_mut().permissions.push(r.operation);
    c.set(DocumentFormat::Pdf, r.operation, CapabilityStatus::Supported);
    assert_eq!(validate_read(&h, &r, &c), Err(ReadInvalidation::NotAReadOperation));
}
fn pdf() -> PdfAnchor {
    PdfAnchor { page_index_zero_based: Some(0), coordinates: CoordinateSystem::PdfUserSpace, rotation: Some(PageRotation::Degrees90), crop: Some(Rect { x: -10.0, y: -20.0, width: 600.0, height: 800.0 }), region: Rect { x: 1.0, y: 2.0, width: 3.0, height: 4.0 } }
}
#[test]
fn pdf_geometry_keeps_unknowns_without_guessing() {
    let mut p = pdf(); p.coordinates = CoordinateSystem::Unknown; p.rotation = None; p.crop = None; p.page_index_zero_based = None;
    let a = DocumentAnchor { document: request().document, location: AnchorLocation::Pdf(p) };
    assert_eq!(a.validate_for(&request().document), Ok(AnchorStatus::UnresolvedGeometry));
    let mut r = request(); r.anchor = Some(a);
    assert_eq!(validate_read(&host(), &r, &capabilities()), Err(ReadInvalidation::AnchorUnresolved));
}
#[test]
fn nonfinite_empty_overflowing_and_invalid_normalized_rectangles_fail() {
    for region in [Rect { x: f64::NAN, ..pdf().region }, Rect { width: 0.0, ..pdf().region }, Rect { height: -1.0, ..pdf().region }, Rect { x: f64::MAX, width: f64::MAX, ..pdf().region }, Rect { x: f64::INFINITY, ..pdf().region }] {
        let a = DocumentAnchor { document: request().document, location: AnchorLocation::Pdf(PdfAnchor { region, ..pdf() }) };
        assert_eq!(a.validate_for(&request().document), Err(ReadInvalidation::InvalidAnchor));
    }
    let a = DocumentAnchor { document: request().document, location: AnchorLocation::Pdf(PdfAnchor { coordinates: CoordinateSystem::CropNormalizedTopLeft, ..pdf() }) };
    assert_eq!(a.validate_for(&request().document), Err(ReadInvalidation::InvalidAnchor));
}
#[test]
fn anchors_are_bound_to_identity_revision_and_format() {
    let a = DocumentAnchor { document: request().document, location: AnchorLocation::Pdf(pdf()) };
    assert_eq!(a.validate_for(&request().document), Ok(AnchorStatus::StructurallyValid));
    assert_eq!(a.validate_for(&document("project", 2, DocumentFormat::Pdf)), Err(ReadInvalidation::StaleRevision));
    assert_eq!(a.validate_for(&document("other", 1, DocumentFormat::Pdf)), Err(ReadInvalidation::ScopeMismatch));
    let wrong = DocumentAnchor { document: document("project", 1, DocumentFormat::Docx), location: a.location };
    assert_eq!(wrong.validate_for(&wrong.document), Err(ReadInvalidation::FormatMismatch));
}
#[test]
fn structured_anchors_validate_ids_ranges_and_package_parts() {
    let cases = [
        (DocumentFormat::Docx, AnchorLocation::Docx { part: "word/document.xml".into(), paragraph_id: "p1".into() }),
        (DocumentFormat::Pptx, AnchorLocation::Pptx { slide_id: "s1".into(), shape_id: "shape1".into() }),
        (DocumentFormat::Xlsx, AnchorLocation::Xlsx { sheet_id: "sheet1".into(), first_row: 1, first_column: 1, last_row: 1_048_576, last_column: 16_384 }),
    ];
    for (format, location) in cases {
        let a = DocumentAnchor { document: document("project", 1, format), location };
        assert_eq!(a.validate_for(&a.document), Ok(AnchorStatus::StructurallyValid));
    }
    for location in [AnchorLocation::Docx { part: "../word/document.xml".into(), paragraph_id: "p".into() }, AnchorLocation::Docx { part: "/word/document.xml".into(), paragraph_id: "p".into() }] {
        let a = DocumentAnchor { document: document("project", 1, DocumentFormat::Docx), location };
        assert_eq!(a.validate_for(&a.document), Err(ReadInvalidation::InvalidAnchor));
    }
    let a = DocumentAnchor { document: document("project", 1, DocumentFormat::Xlsx), location: AnchorLocation::Xlsx { sheet_id: "sheet".into(), first_row: 2, first_column: 1, last_row: 1, last_column: 1 } };
    assert_eq!(a.validate_for(&a.document), Err(ReadInvalidation::InvalidAnchor));
}
#[test]
fn invalid_document_metadata_is_rejected_and_revision_is_preserved() {
    assert!(DocumentRef::new(Scope { workspace_id: "".into(), project_id: None }, "document", Revision::new(1), DocumentFormat::Pdf).is_err());
    assert!(DocumentRef::new(request().document.scope().clone(), "/tmp/user.pdf", Revision::new(1), DocumentFormat::Pdf).is_err());
    assert_eq!(request().document.revision(), &Revision::new(1));
    assert_eq!(request().document.document_id(), "document");
}
