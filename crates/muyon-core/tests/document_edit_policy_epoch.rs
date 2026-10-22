//! The unchanged v1 wire shape cannot preserve pre-tightening preview identity.
use muyon_core::{
    contract::{BlobRef, Revision, Scope},
    document_edit::engine_protocol::{prepare_request_trusted, NumericCellEdit},
    documents::{DocumentFormat, DocumentMetadata, DocumentRef},
};
use serde::Serialize;
use sha2::{Digest, Sha256};
fn hash(v: &[u8]) -> String {
    Sha256::digest(v)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
#[derive(Serialize)]
struct LegacyIdentity {
    scope_id: String,
    file_id: String,
    base_revision: String,
    operation_id: String,
    idempotency_key: String,
}
#[test]
fn tightened_schema1_preview_cannot_reuse_legacy_binding() {
    let source = DocumentMetadata {
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
    };
    let identity = LegacyIdentity {
        scope_id: format!(
            "scope:{}",
            hash(&serde_json::to_vec(source.document.scope()).unwrap())
        ),
        file_id: "file".into(),
        base_revision: "9".into(),
        operation_id: "intent".into(),
        idempotency_key: String::new(),
    };
    let op = serde_json::json!({"kind":"set_numeric_cell","sheet":"Original","cell":"A1","expected":"2","replacement":"5"});
    let legacy: [u8; 32] =
        Sha256::digest(serde_json::to_vec(&(1, &identity, &source.blob.digest, &op)).unwrap())
            .into();
    let current = prepare_request_trusted(
        &source,
        "intent",
        NumericCellEdit {
            sheet: "Original".into(),
            cell: "A1".into(),
            expected: "2".into(),
            replacement: "5".into(),
        },
    )
    .unwrap();
    assert_ne!(
        legacy,
        current.binding().patch_digest,
        "tightened source eligibility must invalidate old preview/confirmation identity"
    );
    let wire: serde_json::Value = serde_json::from_str(current.request_json()).unwrap();
    assert_eq!(wire["schema_version"], 1);
    assert_eq!(wire["operation"], op);
}
