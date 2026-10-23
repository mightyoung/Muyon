//! Existing contract regression vectors only; no new values, authority or dispatch.
use muyon_core::{
    contract::{CommandEnvelope, Revision},
    services::types::*,
};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeSet;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Fixture {
    fixture_version: u32,
    contract_major: u32,
    schema_major: u32,
    synthetic: bool,
    scalar_cases: Vec<ScalarCase>,
    negotiation_cases: Vec<NegotiationCase>,
    strict_scope_cases: Vec<WireCase>,
    native_identity_cases: Vec<NativeCase>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ScalarCase {
    id: String,
    kind: String,
    json: String,
    valid: bool,
    expected: Option<Value>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct NegotiationCase {
    contract_major: u32,
    schema_major: u32,
    valid: bool,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct WireCase {
    id: String,
    json: String,
    valid: bool,
    expected: Option<Value>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct NativeCase {
    id: String,
    field: String,
    value: String,
    valid_native: bool,
    valid_public: Option<bool>,
}
fn fixture() -> Fixture {
    let fixture: Fixture = decode_strict(include_str!(
        "../../../docs/contracts/public-services-v02/fixtures/scalar-boundaries.json"
    ))
    .unwrap();
    assert_eq!(fixture.fixture_version, 1);
    assert_eq!((fixture.contract_major, fixture.schema_major), (1, 1));
    assert!(fixture.synthetic);
    for case in &fixture.scalar_cases {
        assert!(
            [
                "revision",
                "unix_ms",
                "result_id",
                "job_id",
                "intent_id",
                "digest"
            ]
            .contains(&case.kind.as_str()),
            "unknown fixture kind: {}",
            case.kind
        );
    }
    let mut ids = BTreeSet::new();
    for id in fixture
        .scalar_cases
        .iter()
        .map(|case| &case.id)
        .chain(fixture.strict_scope_cases.iter().map(|case| &case.id))
        .chain(fixture.native_identity_cases.iter().map(|case| &case.id))
    {
        assert!(!id.is_empty() && ids.insert(id), "duplicate/empty id: {id}");
    }
    fixture
}
fn check_wire<T: DeserializeOwned + Serialize>(
    id: &str,
    raw: &str,
    valid: bool,
    expected: &Option<Value>,
) {
    assert_eq!(expected.is_some(), valid, "fixture expectation: {id}");
    let result = decode_strict::<T>(raw);
    assert_eq!(result.is_ok(), valid, "wire acceptance: {id}");
    if valid {
        assert_eq!(
            serde_json::to_value(result.unwrap()).unwrap(),
            *expected.as_ref().unwrap(),
            "exact wire value: {id}"
        );
    }
}
// These vectors catch precision loss, permissive numeric decoding and divergent
// direct/wire validation. Expectations are literal fixture values, not recomputed
// through the production parser.
fn check_scalar_kind(kind: &str) {
    let fixture = fixture();
    let cases: Vec<_> = fixture
        .scalar_cases
        .iter()
        .filter(|case| case.kind == kind)
        .collect();
    assert!(!cases.is_empty(), "missing scalar family: {kind}");
    for case in cases {
        macro_rules! check {
            ($ty:ty) => {{
                check_wire::<$ty>(&case.id, &case.json, case.valid, &case.expected);
                if let Value::String(raw) = serde_json::from_str(&case.json).unwrap() {
                    assert_eq!(
                        <$ty>::parse(&raw).is_ok(),
                        case.valid,
                        "direct acceptance: {}",
                        case.id
                    );
                }
            }};
        }
        match kind {
            "revision" => check!(Revision),
            "unix_ms" => check!(UnixMs),
            "result_id" => check!(ResultId),
            "job_id" => check!(JobId),
            "intent_id" => check!(IntentId),
            "digest" => check!(Digest),
            other => panic!("unrecognized scalar family: {other}"),
        }
    }
}
#[test]
fn exact_integer_strings_reject_overflow_and_numeric_tokens() {
    for kind in ["revision", "unix_ms"] {
        check_scalar_kind(kind);
    }
}
#[test]
fn opaque_ids_use_utf8_byte_limits_and_reject_nul() {
    for kind in ["result_id", "job_id", "intent_id"] {
        check_scalar_kind(kind);
    }
}
#[test]
fn digests_reject_case_length_and_alphabet_drift() {
    check_scalar_kind("digest");
}
#[test]
fn incompatible_majors_remain_explicit_errors() {
    let fixture = fixture();
    assert!(!fixture.negotiation_cases.is_empty());
    for case in fixture.negotiation_cases {
        let result = negotiate(case.contract_major, case.schema_major);
        assert_eq!(result.is_ok(), case.valid);
        if !case.valid {
            assert_eq!(result.unwrap_err().code, ErrorCode::UnsupportedVersion);
        }
    }
}
#[test]
fn strict_scope_decoding_preserves_precision_and_rejects_ambiguous_authority() {
    let fixture = fixture();
    assert!(!fixture.strict_scope_cases.is_empty());
    for case in fixture.strict_scope_cases {
        check_wire::<ScopeRef>(&case.id, &case.json, case.valid, &case.expected);
    }
}
#[test]
fn original_envelope_validation_is_required_after_public_id_parsing() {
    let fixture = fixture();
    assert!(!fixture.native_identity_cases.is_empty());
    for case in fixture.native_identity_cases {
        let mut command: CommandEnvelope = serde_json::from_value(json!({
            "protocol_version":1,"business_version":1,"intent_id":"intent:original",
            "scope":{"workspace_id":"w","project_id":null},"expected_revision":"0",
            "authority":{"grant_id":"grant:original","generation":"1","owner_epoch":"epoch:original"},
            "plan_id":"plan:original","plan_digest":"0".repeat(64),
            "command":{"operation":"project_create","project_id":"project:1","name":"Synthetic"}
        }))
        .unwrap();
        match case.field.as_str() {
            "intent_id" => {
                command.intent_id = case.value.clone();
                assert_eq!(
                    IntentId::parse(&case.value).is_ok(),
                    case.valid_public
                        .expect("intent vector needs public expectation"),
                    "public parser: {}",
                    case.id
                );
            }
            "plan_id" => {
                assert!(case.valid_public.is_none());
                command.plan_id = case.value;
            }
            other => panic!("unrecognized identity field: {other}"),
        }
        command.plan_digest = command.expected_plan_digest().unwrap();
        assert_eq!(
            command.validate().is_ok(),
            case.valid_native,
            "native validation: {}",
            case.id
        );
    }
}
