use muyon_core::document_edit::fingerprint::{ExpandedNode,local_fingerprint};
use muyon_core::{
    contract::{BlobRef, Revision, Scope},
    document_edit::{
        engine_protocol::{check_response_held, ProtocolError},
        text_protocol::{prepare_text_request_trusted, TextEdit, TextLocation},
    },
    documents::{DocumentFormat, DocumentMetadata, DocumentRef},
};
fn source(format: DocumentFormat) -> DocumentMetadata {
    DocumentMetadata {
        document: DocumentRef::new(
            Scope {
                workspace_id: "workspace".into(),
                project_id: Some("project".into()),
            },
            "document",
            Revision::new(7),
            format,
        )
        .unwrap(),
        title: "Synthetic only".into(),
        blob: BlobRef {
            digest: "a".repeat(64),
            byte_length: Revision::new(123),
        },
    }
}
fn run(format: DocumentFormat) -> ExpandedNode {
    let ns = if format == DocumentFormat::Docx {
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    } else {
        "http://schemas.openxmlformats.org/drawingml/2006/main"
    };
    ExpandedNode {
        tag: format!("{{{ns}}}r"),
        attributes: vec![],
        text: None,
        tail: None,
        children: vec![ExpandedNode {
            tag: format!("{{{ns}}}t"),
            attributes: vec![],
            text: Some("target".into()),
            tail: None,
            children: vec![],
        }],
    }
}
fn edit(format: DocumentFormat) -> TextEdit {
    TextEdit {
        location: if format == DocumentFormat::Docx {
            TextLocation::DocxRun {
                paragraph_index: 2,
                run_index: 1,
            }
        } else {
            TextLocation::PptxShape {
                part: "ppt/slides/slide3.xml".into(),
                slide_id: 256,
                shape_id: 2,
                paragraph_index: 0,
                run_index: 0,
            }
        },
        observed_run: run(format),
        expected: "target".into(),
        replacement: "edited 文😀".into(),
    }
}

#[test] fn schema2_bound_identity_response_and_faked_claims_never_produce_success() {
 for format in [DocumentFormat::Docx,DocumentFormat::Pptx] {
 let p=prepare_text_request_trusted(&source(format),"held",edit(format)).unwrap();let req:serde_json::Value=serde_json::from_str(p.request_json()).unwrap();let mut identity=serde_json::Map::new();for key in ["scope_id","file_id","base_revision","operation_id","idempotency_key"] {identity.insert(key.into(),req[key].clone());}
 let base=serde_json::json!({"schema_version":2,"status":"candidate_validated","identity":identity,"source_sha256":req["source_sha256"],"engine_execution":"executed","real_roundtrip":"passed","fake_executor_used":false,"fidelity":"unknown","safety":"unknown","dimensions":{"render":"not_run","recalc":"not_run","visual":"not_run","annotation":"not_run"},"reasons":[]});
 assert_eq!(check_response_held(&p,&serde_json::to_vec(&base).unwrap()).unwrap_err(),ProtocolError::EnvironmentHold);
 for field in ["scope_id","file_id","base_revision","operation_id","idempotency_key"] {let mut bad=base.clone();bad["identity"][field]="mismatch".into();assert_eq!(check_response_held(&p,&serde_json::to_vec(&bad).unwrap()).unwrap_err(),ProtocolError::BindingMismatch);}
 let mut bad=base.clone();bad["source_sha256"]="b".repeat(64).into();assert_eq!(check_response_held(&p,&serde_json::to_vec(&bad).unwrap()).unwrap_err(),ProtocolError::BindingMismatch);
 let mut bad=base.clone();bad["fake_executor_used"]=true.into();assert_eq!(check_response_held(&p,&serde_json::to_vec(&bad).unwrap()).unwrap_err(),ProtocolError::SimulationForbidden);
 for version in [1,3] {let mut bad=base.clone();bad["schema_version"]=version.into();assert_eq!(check_response_held(&p,&serde_json::to_vec(&bad).unwrap()).unwrap_err(),ProtocolError::InvalidResponse);}
 }
}
