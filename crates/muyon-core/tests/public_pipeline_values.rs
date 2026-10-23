//! Shared value vectors, not a resolver, authorization check, or JVM execution.
pub use muyon_core::{contract, documents, services};
pub mod adapter {
    include!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/services/pipeline.rs"
    ));
}
use adapter::{validate_vector_compatibility, VectorDescriptor};
use muyon_core::{
    contract::{Revision, Scope},
    documents::{DocumentFormat, DocumentRef},
    services::types::ResultId,
};
use serde_json::Value;
fn fixture() -> Value {
    serde_json::from_str(include_str!("fixtures/public_pipeline.json")).unwrap()
}
fn descriptor(v: &Value) -> VectorDescriptor {
    assert_eq!(v.as_object().unwrap().len(), 4);
    VectorDescriptor {
        model_version: v["model_version"].as_str().unwrap().into(),
        tokenizer_version: v["tokenizer_version"].as_str().unwrap().into(),
        dimensions: u32::try_from(v["dimensions"].as_u64().unwrap()).unwrap(),
        chunk_version: v["chunk_version"].as_str().unwrap().into(),
    }
}
fn jvm_dimensions(d: &VectorDescriptor) -> bool {
    (1..=i32::MAX as u32).contains(&d.dimensions)
}
fn document_id_valid(v: &Value) -> bool {
    v.as_str().is_some_and(|id| {
        DocumentRef::new(
            Scope {
                workspace_id: "synthetic-w".into(),
                project_id: Some("synthetic-p".into()),
            },
            id,
            Revision::new(1),
            DocumentFormat::Text,
        )
        .is_ok()
    })
}
#[test]
fn descriptor_value_vectors_match_rust_reference() {
    let fixture = fixture();
    for case in fixture["compatibility_cases"].as_array().unwrap() {
        let index = descriptor(&case["index"]);
        let query = descriptor(&case["query"]);
        assert_eq!(
            validate_vector_compatibility(&index, &query).is_ok(),
            case["expected_rust_compatible"].as_bool().unwrap(),
            "{}",
            case["id"]
        );
    }
}
#[test]
fn reference_candidates_are_only_existing_value_parser_conjunctions() {
    let fixture = fixture();
    for case in fixture["reference_candidate_cases"].as_array().unwrap() {
        let doc = document_id_valid(&case["document_id"]);
        let result = case["result_id"]
            .as_str()
            .is_some_and(|s| ResultId::parse(s).is_ok());
        let model = if case["model"].is_null() {
            None
        } else {
            Some(descriptor(&case["model"]))
        };
        let valid_model = model
            .as_ref()
            .is_some_and(|d| validate_vector_compatibility(d, d).is_ok());
        let domain = model.as_ref().is_some_and(jvm_dimensions);
        for (field, observed) in [
            ("expected_document_id_valid", doc),
            ("expected_result_id_valid", result),
            ("expected_descriptor_valid_rust", valid_model),
            ("jvm_dimensions_supported", domain),
            (
                "expected_rust_shape_candidate",
                doc && result && valid_model,
            ),
            (
                "expected_jvm_shape_candidate",
                doc && result && valid_model && domain,
            ),
        ] {
            assert_eq!(
                observed,
                case[field].as_bool().unwrap(),
                "{} {field}",
                case["id"]
            );
        }
    }
    assert_eq!(fixture["trusted_resolution_implemented"], false);
}
#[test]
fn jvm_dimension_domain_does_not_truncate_valid_rust_u32() {
    let fixture = fixture();
    let cases = fixture["compatibility_cases"].as_array().unwrap();
    for case in cases {
        let index = descriptor(&case["index"]);
        let query = descriptor(&case["query"]);
        assert_eq!(
            jvm_dimensions(&index) && jvm_dimensions(&query),
            case["jvm_dimensions_supported"].as_bool().unwrap(),
            "{}",
            case["id"]
        );
    }
    for value in [i32::MAX as u32 + 1, u32::MAX] {
        let case = cases
            .iter()
            .find(|c| c["index"]["dimensions"] == value)
            .unwrap();
        assert!(case["expected_rust_compatible"].as_bool().unwrap());
        assert!(!case["jvm_dimensions_supported"].as_bool().unwrap());
    }
}
#[test]
fn fixture_covers_the_pinned_rust_whitespace_set_without_normalizing_versions() {
    let fixture = fixture();
    assert_eq!(fixture["contract_major"], 1);
    assert_eq!(fixture["schema_major"], 1);
    assert_eq!(fixture["fixture_revision"], 2);
    assert_eq!(fixture["synthetic"], true);
    assert_eq!(
        fixture["candidate_semantics"],
        "shape_only_not_trusted_resolution"
    );
    assert_eq!(fixture["kotlin_api_frozen"], false);
    let actual: Vec<u32> = (0..=0x10ffff)
        .filter(|cp| char::from_u32(*cp).is_some_and(char::is_whitespace))
        .collect();
    let declared: Vec<u32> = fixture["rust_whitespace_code_points"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| u32::try_from(v.as_u64().unwrap()).unwrap())
        .collect();
    assert_eq!(actual, declared);
    for cp in actual {
        let name = format!("same-model-U+{cp:04X}");
        let case = fixture["compatibility_cases"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["id"] == name)
            .unwrap();
        assert!(!case["expected_rust_compatible"].as_bool().unwrap());
    }
}

fn hex_string(v: &Value) -> String {
    v.as_str()
        .unwrap()
        .as_bytes()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
fn nullable_hex(v: &Value) -> String {
    if v.is_null() {
        "-".into()
    } else {
        hex_string(v)
    }
}
fn descriptor_columns(v: &Value) -> Vec<String> {
    let d = descriptor(v);
    vec![
        hex_string(&v["model_version"]),
        hex_string(&v["tokenizer_version"]),
        d.dimensions.to_string(),
        hex_string(&v["chunk_version"]),
    ]
}
#[test]
fn jvm_projection_is_lossless_and_complete_derivative_of_shared_json() {
    let f = fixture();
    let d = f["compatibility_cases"].as_array().unwrap();
    let c = f["reference_candidate_cases"].as_array().unwrap();
    let w = f["rust_whitespace_code_points"].as_array().unwrap();
    let mut rows = vec![vec![
        "H".into(),
        "muyon.public-pipeline-values".into(),
        "1".into(),
        "1".into(),
        "2".into(),
        "true".into(),
        "false".into(),
        "false".into(),
        "shape_only_not_trusted_resolution".into(),
        d.len().to_string(),
        c.len().to_string(),
        w.len().to_string(),
    ]];
    let mut base = vec!["B".into()];
    base.extend(descriptor_columns(&f["descriptor"]));
    rows.push(base);
    for cp in w {
        rows.push(vec![
            "W".into(),
            u32::try_from(cp.as_u64().unwrap()).unwrap().to_string(),
        ]);
    }
    for case in d {
        let mut row = vec!["D".into(), case["id"].as_str().unwrap().into()];
        row.extend(descriptor_columns(&case["index"]));
        row.extend(descriptor_columns(&case["query"]));
        for key in ["expected_rust_compatible", "jvm_dimensions_supported"] {
            row.push(case[key].as_bool().unwrap().to_string());
        }
        rows.push(row);
    }
    for case in c {
        let mut row = vec![
            "C".into(),
            case["id"].as_str().unwrap().into(),
            nullable_hex(&case["document_id"]),
            nullable_hex(&case["result_id"]),
        ];
        row.extend(if case["model"].is_null() {
            vec!["-".into(); 4]
        } else {
            descriptor_columns(&case["model"])
        });
        for key in [
            "expected_document_id_valid",
            "expected_result_id_valid",
            "expected_descriptor_valid_rust",
            "jvm_dimensions_supported",
            "expected_rust_shape_candidate",
            "expected_jvm_shape_candidate",
        ] {
            row.push(case[key].as_bool().unwrap().to_string());
        }
        rows.push(row);
    }
    let expected = rows
        .into_iter()
        .map(|row| row.join("\t") + "\n")
        .collect::<String>();
    assert_eq!(
        include_str!("fixtures/public_pipeline.values.tsv"),
        expected
    );
}
