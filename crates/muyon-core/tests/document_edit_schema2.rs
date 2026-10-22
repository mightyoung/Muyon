use muyon_core::document_edit::fingerprint::{
    canonical_tree_bytes, local_fingerprint, ExpandedNode,
};
fn node(v: &serde_json::Value) -> ExpandedNode {
    ExpandedNode {
        tag: v[0].as_str().unwrap().into(),
        attributes: v[1]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| (p[0].as_str().unwrap().into(), p[1].as_str().unwrap().into()))
            .collect(),
        text: v[2].as_str().map(Into::into),
        tail: v[3].as_str().map(Into::into),
        children: v[4].as_array().unwrap().iter().map(node).collect(),
    }
}
#[test]
fn expanded_tree_matches_python_ascii_json_bytes_and_hashes() {
    let vectors: serde_json::Value =
        serde_json::from_str(include_str!("document_edit_tree_goldens.json")).unwrap();
    for row in vectors.as_array().unwrap() {
        let n = node(&row["form"]);
        assert_eq!(
            canonical_tree_bytes(&n).unwrap(),
            row["canonical"].as_str().unwrap().as_bytes(),
            "{}",
            row["name"]
        );
        assert_eq!(
            local_fingerprint(&n).unwrap(),
            row["sha256"].as_str().unwrap(),
            "{}",
            row["name"]
        );
    }
}
#[test]
fn duplicate_attributes_limits_and_tree_identity_fail_closed() {
    let mut n = ExpandedNode {
        tag: "{urn:t}r".into(),
        attributes: vec![("a".into(), "1".into()), ("a".into(), "2".into())],
        text: None,
        tail: None,
        children: vec![],
    };
    assert!(local_fingerprint(&n).is_err());
    n.attributes.clear();
    let a = local_fingerprint(&n).unwrap();
    n.text = Some(String::new());
    assert_ne!(a, local_fingerprint(&n).unwrap());
    n.text = Some("x".repeat(300_000));
    assert!(local_fingerprint(&n).is_err());
    n.text = None;
    for _ in 0..65 {
        n = ExpandedNode {
            tag: "r".into(),
            attributes: vec![],
            text: None,
            tail: None,
            children: vec![n],
        };
    }
    assert!(local_fingerprint(&n).is_err());
}

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
#[test]
fn schema2_maps_true_format_exact_locator_and_local_run_hash() {
    for format in [DocumentFormat::Docx, DocumentFormat::Pptx] {
        let p = prepare_text_request_trusted(&source(format), "intent", edit(format)).unwrap();
        let raw: serde_json::Value = serde_json::from_str(p.request_json()).unwrap();
        assert_eq!(raw["schema_version"], 2);
        assert_eq!(raw["source_sha256"], "a".repeat(64));
        assert_eq!(raw["base_revision"], "7");
        assert_eq!(
            raw["operation"]["target_sha256"],
            local_fingerprint(&run(format)).unwrap()
        );
        assert_eq!(
            raw["operation"]["part"],
            if format == DocumentFormat::Docx {
                "word/document.xml"
            } else {
                "ppt/slides/slide3.xml"
            }
        );
        assert_eq!(raw["operation"]["replacement"], "edited 文😀");
        assert!(p.request_json().contains("replace_"));
    }
}
#[test]
fn schema2_digest_binds_locator_tree_format_source_operation_and_intent() {
    let s = source(DocumentFormat::Docx);
    let baseline = prepare_text_request_trusted(&s, "intent", edit(DocumentFormat::Docx))
        .unwrap()
        .binding()
        .patch_digest;
    let mut op = edit(DocumentFormat::Docx);
    op.location = TextLocation::DocxRun {
        paragraph_index: 3,
        run_index: 1,
    };
    assert_ne!(
        baseline,
        prepare_text_request_trusted(&s, "intent", op)
            .unwrap()
            .binding()
            .patch_digest
    );
    let mut op = edit(DocumentFormat::Docx);
    op.observed_run.tail = Some("neighbor".into());
    assert_ne!(
        baseline,
        prepare_text_request_trusted(&s, "intent", op)
            .unwrap()
            .binding()
            .patch_digest
    );
    let mut op = edit(DocumentFormat::Docx);
    op.replacement = "other".into();
    assert_ne!(
        baseline,
        prepare_text_request_trusted(&s, "intent", op)
            .unwrap()
            .binding()
            .patch_digest
    );
    let mut other = source(DocumentFormat::Docx);
    other.blob.digest = "b".repeat(64);
    assert_ne!(
        baseline,
        prepare_text_request_trusted(&other, "intent", edit(DocumentFormat::Docx))
            .unwrap()
            .binding()
            .patch_digest
    );
    other = source(DocumentFormat::Docx);
    other.blob.byte_length = Revision::new(124);
    assert_ne!(
        baseline,
        prepare_text_request_trusted(&other, "intent", edit(DocumentFormat::Docx))
            .unwrap()
            .binding()
            .patch_digest
    );
    assert_ne!(
        baseline,
        prepare_text_request_trusted(&s, "other-intent", edit(DocumentFormat::Docx))
            .unwrap()
            .binding()
            .patch_digest
    );
    assert_ne!(
        baseline,
        prepare_text_request_trusted(
            &source(DocumentFormat::Pptx),
            "intent",
            edit(DocumentFormat::Pptx)
        )
        .unwrap()
        .binding()
        .patch_digest
    );
}
#[test]
fn schema2_refuses_wrong_format_locator_run_text_and_xml_space_change() {
    let s = source(DocumentFormat::Docx);
    assert!(prepare_text_request_trusted(
        &source(DocumentFormat::Pdf),
        "intent",
        edit(DocumentFormat::Docx)
    )
    .is_err());
    assert!(prepare_text_request_trusted(&s, "intent", edit(DocumentFormat::Pptx)).is_err());
    for replacement in ["target", "\nnew", " new", "new\t", "\u{ffff}"] {
        let mut op = edit(DocumentFormat::Docx);
        op.replacement = replacement.into();
        assert!(prepare_text_request_trusted(&s, "intent", op).is_err());
    }
    let mut op = edit(DocumentFormat::Docx);
    op.expected = "wrong".into();
    assert!(prepare_text_request_trusted(&s, "intent", op).is_err());
    let mut op = edit(DocumentFormat::Docx);
    op.location = TextLocation::DocxRun {
        paragraph_index: 10000,
        run_index: 0,
    };
    assert!(prepare_text_request_trusted(&s, "intent", op).is_err());
    for part in [
        "../slide1.xml",
        "ppt/slides/slide0.xml",
        "ppt/slides/slide01.xml",
        "ppt/slides/slide100000.xml",
    ] {
        let mut op = edit(DocumentFormat::Pptx);
        op.location = TextLocation::PptxShape {
            part: part.into(),
            slide_id: 256,
            shape_id: 2,
            paragraph_index: 0,
            run_index: 0,
        };
        assert!(prepare_text_request_trusted(&source(DocumentFormat::Pptx), "intent", op).is_err());
    }
    let mut op = edit(DocumentFormat::Docx);
    op.observed_run
        .children
        .push(op.observed_run.children[0].clone());
    assert!(prepare_text_request_trusted(&s, "intent", op).is_err());
}
#[test]
fn matching_schema2_response_is_held_and_simulation_or_version_never_admitted() {
    let p = prepare_text_request_trusted(
        &source(DocumentFormat::Docx),
        "intent",
        edit(DocumentFormat::Docx),
    )
    .unwrap();
    let req: serde_json::Value = serde_json::from_str(p.request_json()).unwrap();
    let mut identity = serde_json::Map::new();
    for key in [
        "scope_id",
        "file_id",
        "base_revision",
        "operation_id",
        "idempotency_key",
    ] {
        identity.insert(key.into(), req[key].clone());
    }
    let mut r = serde_json::json!({"schema_version":2,"status":"held","identity":identity,"engine_execution":"not_run","real_roundtrip":"not_run","fake_executor_used":false,"fidelity":"unknown","safety":"unknown","dimensions":{"render":"not_run","recalc":"not_run","visual":"not_run","annotation":"not_run"},"reasons":[]});
    assert_eq!(
        check_response_held(&p, &serde_json::to_vec(&r).unwrap()).unwrap_err(),
        ProtocolError::EnvironmentHold
    );
    r["fake_executor_used"] = true.into();
    assert_eq!(
        check_response_held(&p, &serde_json::to_vec(&r).unwrap()).unwrap_err(),
        ProtocolError::SimulationForbidden
    );
    r["schema_version"] = 1.into();
    assert_eq!(
        check_response_held(&p, &serde_json::to_vec(&r).unwrap()).unwrap_err(),
        ProtocolError::InvalidResponse
    );
}
