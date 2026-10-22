//! Synthetic envelopes only. No engine process or workbook parsing is invoked.
use muyon_core::{
    contract::{BlobRef, Revision, Scope},
    document_edit::engine_protocol::*,
    documents::{DocumentFormat, DocumentMetadata, DocumentRef},
};
use serde_json::{json, Value};
fn metadata() -> DocumentMetadata {
    DocumentMetadata {
        document: DocumentRef::new(
            Scope {
                workspace_id: "workspace".into(),
                project_id: Some("project".into()),
            },
            "file",
            Revision::new(9),
            DocumentFormat::Xlsx,
        )
        .unwrap(),
        title: "synthetic schema-only".into(),
        blob: BlobRef {
            digest: "a".repeat(64),
            byte_length: Revision::new(10),
        },
    }
}
fn op() -> NumericCellEdit {
    NumericCellEdit {
        sheet: "Original".into(),
        cell: "A1".into(),
        expected: "2".into(),
        replacement: "5.0".into(),
    }
}
fn prepared() -> PreparedEngineRequest {
    prepare_request_trusted(&metadata(), "operation", op()).unwrap()
}
fn response(p: &PreparedEngineRequest) -> Value {
    let request: Value = serde_json::from_str(p.request_json()).unwrap();
    json!({"schema_version":1,"status":"candidate_validated","identity":{"scope_id":request["scope_id"],"file_id":request["file_id"],"base_revision":request["base_revision"],"operation_id":request["operation_id"],"idempotency_key":request["idempotency_key"]},"source_sha256":request["source_sha256"],"engine_execution":"executed","real_roundtrip":"passed","fake_executor_used":false,"fidelity":"unknown","safety":"unknown","dimensions":{"render":"not_run","recalc":"not_run","visual":"not_run","annotation":"not_run"},"reasons":[]})
}
#[test]
fn real_metadata_maps_exact_identity_and_preserves_numeric_literals() {
    let p = prepared();
    let r: Value = serde_json::from_str(p.request_json()).unwrap();
    assert_eq!(r["file_id"], "file");
    assert_eq!(r["base_revision"], "9");
    assert_eq!(r["source_sha256"], "a".repeat(64));
    assert_eq!(r["operation"]["replacement"], "5.0");
    assert_eq!(p.binding().document, metadata().document);
    let mut different = op();
    different.replacement = "5".into();
    let other = prepare_request_trusted(&metadata(), "operation", different).unwrap();
    assert_ne!(p.binding().patch_digest, other.binding().patch_digest);
}
#[test]
fn six_response_fixtures_can_never_mint_an_engine_commit_permit() {
    let p = prepared();
    let base = response(&p);
    let mut simulation = base.clone();
    simulation["status"] = json!("simulated_validated");
    simulation["fake_executor_used"] = json!(true);
    let mut fake = base.clone();
    fake["fake_executor_used"] = json!(true);
    let mut hash = base.clone();
    hash["source_sha256"] = json!("b".repeat(64));
    let mut identity = base.clone();
    identity["identity"]["base_revision"] = json!("8");
    let mut held = base.clone();
    held["status"] = json!("held");
    for fixture in [base, simulation, fake, hash, identity, held] {
        assert!(check_response_held(&p, &serde_json::to_vec(&fixture).unwrap()).is_err());
    }
}
#[test]
fn unknown_keys_versions_duplicate_keys_and_oversize_receipts_fail_closed() {
    let p = prepared();
    let mut unknown = response(&p);
    unknown["host_path"] = json!("/tmp/output");
    assert_eq!(
        check_response_held(&p, &serde_json::to_vec(&unknown).unwrap()).unwrap_err(),
        ProtocolError::InvalidResponse
    );
    let mut version = response(&p);
    version["schema_version"] = json!(2);
    assert_eq!(
        check_response_held(&p, &serde_json::to_vec(&version).unwrap()).unwrap_err(),
        ProtocolError::InvalidResponse
    );
    let duplicate = serde_json::to_string(&response(&p)).unwrap().replacen(
        "\"schema_version\":1",
        "\"schema_version\":1,\"schema_version\":1",
        1,
    );
    assert_eq!(
        check_response_held(&p, duplicate.as_bytes()).unwrap_err(),
        ProtocolError::InvalidResponse
    );
    assert_eq!(
        check_response_held(&p, &vec![b' '; 128 * 1024]).unwrap_err(),
        ProtocolError::InvalidResponse
    );
}
#[test]
fn identity_and_hash_errors_are_distinct_from_environment_hold() {
    let p = prepared();
    let mut wrong = response(&p);
    wrong["identity"]["idempotency_key"] = json!("wrong");
    assert_eq!(
        check_response_held(&p, &serde_json::to_vec(&wrong).unwrap()).unwrap_err(),
        ProtocolError::BindingMismatch
    );
    let mut wrong = response(&p);
    wrong["source_sha256"] = json!("0".repeat(64));
    assert_eq!(
        check_response_held(&p, &serde_json::to_vec(&wrong).unwrap()).unwrap_err(),
        ProtocolError::BindingMismatch
    );
    assert_eq!(
        check_response_held(&p, &serde_json::to_vec(&response(&p)).unwrap()).unwrap_err(),
        ProtocolError::EnvironmentHold
    );
}
#[test]
fn numeric_cell_bounds_and_metadata_format_are_strict() {
    for value in ["NaN", "1e3", "01", "0.1234567890123456", "-", "1."] {
        let mut edit = op();
        edit.replacement = value.into();
        assert_eq!(
            prepare_request_trusted(&metadata(), "op", edit).unwrap_err(),
            ProtocolError::InvalidOperation
        );
    }
    for cell in ["A0", "XFE1", "A1048577", "a1", "/tmp"] {
        let mut edit = op();
        edit.cell = cell.into();
        assert!(prepare_request_trusted(&metadata(), "op", edit).is_err());
    }
    let mut m = metadata();
    m.document = DocumentRef::new(
        m.document.scope().clone(),
        "file",
        Revision::new(9),
        DocumentFormat::Unknown,
    )
    .unwrap();
    assert!(prepare_request_trusted(&m, "op", op()).is_err());
}

#[test]
fn apparently_real_status_requires_source_hash_and_simulated_diagnostics_are_hard_rejected() {
    let p = prepared();
    let mut missing = response(&p);
    missing.as_object_mut().unwrap().remove("source_sha256");
    assert_eq!(
        check_response_held(&p, &serde_json::to_vec(&missing).unwrap()).unwrap_err(),
        ProtocolError::InvalidResponse
    );
    for field in ["engine_execution", "real_roundtrip"] {
        let mut simulated = response(&p);
        simulated[field] = json!("simulated");
        assert_eq!(
            check_response_held(&p, &serde_json::to_vec(&simulated).unwrap()).unwrap_err(),
            ProtocolError::SimulationForbidden
        );
    }
    let mut nested = response(&p);
    nested["candidate_manifest"] = json!([{ "unknown_host_path":"/tmp/never-accepted" }]);
    assert_eq!(
        check_response_held(&p, &serde_json::to_vec(&nested).unwrap()).unwrap_err(),
        ProtocolError::InvalidResponse
    );
}
