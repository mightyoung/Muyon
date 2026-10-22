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

#[test] fn former_protocol_gaps_are_explicitly_rejected() {
 let p=prepared();let mut r=response(&p);r.as_object_mut().unwrap().remove("source_sha256");assert_eq!(check_response_held(&p,&serde_json::to_vec(&r).unwrap()).unwrap_err(),ProtocolError::InvalidResponse);
 let mut r=response(&p);r["engine_execution"]=json!("SIMULATED");assert_eq!(check_response_held(&p,&serde_json::to_vec(&r).unwrap()).unwrap_err(),ProtocolError::SimulationForbidden);
 let mut r=response(&p);r["real_roundtrip"]=json!("fake");assert_eq!(check_response_held(&p,&serde_json::to_vec(&r).unwrap()).unwrap_err(),ProtocolError::SimulationForbidden);
 for field in ["candidate_manifest","source_manifest","validation"] {let mut r=response(&p);r[field]=json!({"unknown_host_path":"/tmp/no-file"});assert_eq!(check_response_held(&p,&serde_json::to_vec(&r).unwrap()).unwrap_err(),ProtocolError::InvalidResponse);}
 let mut r=response(&p);r["schema_version"]=json!(2);assert_eq!(check_response_held(&p,&serde_json::to_vec(&r).unwrap()).unwrap_err(),ProtocolError::InvalidResponse);
 assert_eq!(check_response_held(&p,&serde_json::to_vec(&response(&p)).unwrap()).unwrap_err(),ProtocolError::EnvironmentHold);
}
