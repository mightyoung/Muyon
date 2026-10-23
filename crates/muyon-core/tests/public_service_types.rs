use muyon_core::{contract::Revision, services::types::*};
use serde_json::{json, Value};

#[test]
fn revision_and_time_are_exact() {
    let revision: Revision = decode_strict("\"9007199254740993\"").unwrap();
    assert_eq!(revision.as_str(), "9007199254740993");
    assert_eq!(
        serde_json::to_string(&revision).unwrap(),
        "\"9007199254740993\""
    );
    for raw in ["01", "-0", "18446744073709551616"] {
        assert!(decode_strict::<Revision>(&format!("\"{raw}\"")).is_err());
    }
    for raw in ["0", "-1", "9223372036854775807", "-9223372036854775808"] {
        let time = UnixMs::parse(raw).unwrap();
        assert_eq!(time.as_str(), raw);
        assert_eq!(serde_json::to_value(time).unwrap(), json!(raw));
    }
    for raw in [
        "",
        "01",
        "-0",
        "+1",
        " 1",
        "9223372036854775808",
        "-9223372036854775809",
    ] {
        assert!(UnixMs::parse(raw).is_err(), "{raw:?}");
        assert!(decode_strict::<UnixMs>(&json!(raw).to_string()).is_err());
    }
    assert!(decode_strict::<UnixMs>("1").is_err());
}

#[test]
fn opaque_identifiers_and_digests_are_validated_on_wire() {
    for raw in ["", "a\0b", &"x".repeat(129), &"甲".repeat(43)] {
        assert!(ResultId::parse(raw).is_err());
        assert!(JobId::parse(raw).is_err());
        assert!(IntentId::parse(raw).is_err());
        assert!(decode_strict::<ResultId>(&json!(raw).to_string()).is_err());
    }
    assert_eq!(
        ResultId::parse(&"x".repeat(128)).unwrap().as_str().len(),
        128
    );
    assert_eq!(JobId::parse("job:1").unwrap().as_str(), "job:1");
    assert_eq!(
        IntentId::parse("original:1").unwrap().as_str(),
        "original:1"
    );
    assert!(Digest::parse(&"a".repeat(64)).is_ok());
    for raw in ["", &"a".repeat(63), &"A".repeat(64), &"g".repeat(64)] {
        assert!(Digest::parse(raw).is_err());
        assert!(decode_strict::<Digest>(&json!(raw).to_string()).is_err());
    }
}

#[test]
fn unknown_safety_field_is_rejected() {
    let raw = r#"{"scope":{"workspace_id":"w","project_id":null},"account_id":null,"scope_generation":"1","approved":true}"#;
    assert!(decode_strict::<ScopeRef>(raw).is_err());
    assert!(decode_strict::<ScopeRef>(r#"{"scope":{"workspace_id":"w","project_id":null},"account_id":null,"scope_generation":"1","scope_generation":"2"}"#).is_err());
    assert!(decode_strict::<ScopeRef>(r#"{"scope":{"workspace_id":"w","workspace_id":"other","project_id":null},"account_id":null,"scope_generation":"1"}"#).is_err());
    let oversized_valid_json = format!("\"{}\"", "x".repeat(1_048_576));
    assert!(serde_json::from_str::<Value>(&oversized_valid_json).is_ok());
    assert!(decode_strict::<Value>(&oversized_valid_json).is_err());
    assert!(negotiate(1, 1).is_ok());
    for (contract, schema) in [(0, 1), (2, 1), (1, 0), (1, 2)] {
        assert_eq!(
            negotiate(contract, schema).unwrap_err().code,
            ErrorCode::UnsupportedVersion
        );
    }
}

#[test]
fn coverage_unknown_is_not_zero() {
    let coverage: Coverage =
        decode_strict(r#"{"state":"unknown","processed":"0","total":null,"failed_units":[]}"#)
            .unwrap();
    assert_eq!(coverage.state, CoverageState::Unknown);
    assert_eq!(coverage.total, None);
    assert_eq!(
        serde_json::to_value(coverage).unwrap()["total"],
        Value::Null
    );
    let large: Coverage = decode_strict(r#"{"state":"partial","processed":"9007199254740993","total":"18446744073709551615","failed_units":[0]}"#).unwrap();
    assert_eq!(
        serde_json::to_value(large).unwrap()["processed"],
        "9007199254740993"
    );
    for raw in [
        r#"{"state":"complete","processed":"0","total":null,"failed_units":[]}"#,
        r#"{"state":"complete","processed":"1","total":"2","failed_units":[]}"#,
        r#"{"state":"complete","processed":"2","total":"2","failed_units":[0]}"#,
        r#"{"state":"partial","processed":"3","total":"2","failed_units":[]}"#,
        r#"{"state":"unknown","processed":0,"total":null,"failed_units":[]}"#,
        r#"{"state":"unknown","processed":"01","total":null,"failed_units":[]}"#,
    ] {
        assert!(decode_strict::<Coverage>(raw).is_err(), "{raw}");
    }
}

#[test]
fn shared_fixtures_roundtrip_with_expected_semantics() {
    let fixture: Value = serde_json::from_str(include_str!(
        "../../../docs/contracts/public-services-v02/fixtures/types.json"
    ))
    .unwrap();
    assert_eq!(fixture["contract_major"], 1);
    assert_eq!(fixture["schema_major"], 1);
    for case in fixture["cases"].as_array().unwrap() {
        let raw = case["json"].as_str().unwrap();
        let result: Result<Value, ServiceError> = match case["kind"].as_str().unwrap() {
            "scope" => decode_strict::<ScopeRef>(raw)
                .and_then(|v| serde_json::to_value(v).map_err(|_| unreachable!())),
            "result" => decode_strict::<ResultRef>(raw)
                .and_then(|v| serde_json::to_value(v).map_err(|_| unreachable!())),
            "error" => decode_strict::<ServiceError>(raw)
                .and_then(|v| serde_json::to_value(v).map_err(|_| unreachable!())),
            "coverage" => decode_strict::<Coverage>(raw)
                .and_then(|v| serde_json::to_value(v).map_err(|_| unreachable!())),
            other => panic!("unrecognized fixture kind {other}"),
        };
        assert_eq!(
            result.is_ok(),
            case["valid"].as_bool().unwrap(),
            "{}",
            case["id"]
        );
        if case["valid"] == true {
            assert_eq!(result.unwrap(), case["expected"], "{}", case["id"]);
        }
    }
}

#[test]
fn legacy_identity_vectors_still_require_original_command_validation() {
    use muyon_core::contract::CommandEnvelope;
    let fixture: Value = serde_json::from_str(include_str!(
        "../../../docs/contracts/public-services-v02/fixtures/types.json"
    ))
    .unwrap();
    for vector in fixture["legacy_identity_vectors"].as_array().unwrap() {
        let raw = vector["value"].as_str().unwrap();
        let mut command:CommandEnvelope=serde_json::from_value(json!({
            "protocol_version":1,"business_version":1,"intent_id":"intent:original",
            "scope":{"workspace_id":"w","project_id":null},"expected_revision":"0",
            "authority":{"grant_id":"grant:original","generation":"1","owner_epoch":"epoch:original"},
            "plan_id":"plan:original","plan_digest":"0".repeat(64),
            "command":{"operation":"project_create","project_id":"project:1","name":"Test"}
        })).unwrap();
        if vector["field"] == "intent_id" {
            command.intent_id = raw.into();
        } else {
            command.plan_id = raw.into();
        }
        command.plan_digest = command.expected_plan_digest().unwrap();
        assert_eq!(
            command.validate().is_ok(),
            vector["valid_native"].as_bool().unwrap(),
            "{}",
            vector["id"]
        );
        if vector["field"] == "intent_id" {
            assert_eq!(
                IntentId::parse(raw).is_ok(),
                vector["valid_public"].as_bool().unwrap()
            );
        }
        if let Some(length) = vector["byte_length"].as_u64() {
            assert_eq!(raw.len(), length as usize);
        }
    }
}
