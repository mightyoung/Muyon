use muyon_core::contract::*;
use serde_json::{json, Value};

fn operation(fixture: &Value, case: &Value) -> Value {
    let mut payload = fixture["base_payload"].clone();
    if let Some(patch) = case["patch"].as_object() {
        for (key, value) in patch {
            payload[key] = value.clone();
        }
    }
    if let Some(repeat) = case["repeat"].as_object() {
        let field = repeat["field"].as_str().unwrap();
        let unit = repeat["unit"].as_str().unwrap();
        let count = repeat["count"].as_u64().unwrap() as usize;
        payload[field] = if repeat["array"].as_bool().unwrap() {
            Value::Array(vec![Value::String(unit.into()); count])
        } else {
            Value::String(unit.repeat(count) + repeat["suffix"].as_str().unwrap())
        };
    }
    json!({"operation":case["operation"].as_str().unwrap_or("supplier_create"), "supplier_id":format!("vector-{}", case["id"].as_str().unwrap()), "payload":payload})
}

fn validate(operation: &Value, revision: &str) -> Result<CommandEnvelope, ContractError> {
    // Match the actual preparation boundary: strict Operation decode, text Revision, envelope validation.
    let command: Operation = serde_json::from_value(decode_json(&operation.to_string())?)
        .map_err(|_| ContractError::InvalidPayload)?;
    let mut envelope = CommandEnvelope {
        protocol_version: PROTOCOL_VERSION,
        business_version: BUSINESS_VERSION,
        intent_id: "vector-intent".into(),
        scope: Scope {
            workspace_id: "vector-workspace".into(),
            project_id: None,
        },
        expected_revision: Revision::parse(revision)?,
        authority: AuthorityBinding {
            grant_id: "vector-grant".into(),
            generation: Revision::new(1),
            owner_epoch: "vector-epoch".into(),
        },
        plan_id: "vector-plan".into(),
        plan_digest: "0".repeat(64),
        command,
    };
    envelope.plan_digest = envelope.expected_plan_digest()?;
    envelope.validate()?;
    Ok(envelope)
}

#[test]
fn ct01_ct04_shared_codec_vectors_use_real_contract_and_lossless_wire_text() {
    let fixture: Value = serde_json::from_str(include_str!(
        "../../../docs/contracts/muyon-android/fixtures/codec-vectors.json"
    ))
    .unwrap();
    let cases = fixture["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 32);
    assert_eq!(
        cases.iter().filter(|case| case["confirm"] == true).count(),
        1
    );
    for case in cases {
        let id = case["id"].as_str().unwrap();
        let revision = case["revision"].as_str().unwrap();
        if case["revision_parse_valid"] == true {
            assert_eq!(
                Revision::parse(revision).unwrap().as_str(),
                revision,
                "{id}"
            );
        }
        let result = validate(&operation(&fixture, case), revision);
        if let Some(expected_error) = case["error"].as_str() {
            assert_eq!(result.unwrap_err().to_string(), expected_error, "{id}");
        } else {
            let envelope = result.unwrap_or_else(|error| panic!("{id}: {error}"));
            assert_eq!(envelope.expected_revision.as_str(), revision, "{id}");
            let serialized = serde_json::to_string(&envelope).unwrap();
            let roundtrip = CommandEnvelope::decode(&serialized).unwrap();
            assert_eq!(roundtrip.expected_revision.as_str(), revision, "{id}");
            let payload = match &roundtrip.command {
                Operation::SupplierCreate { payload, .. }
                | Operation::SupplierUpdate { payload, .. } => payload,
                _ => panic!("supplier vector expected"),
            };
            let normalized = serde_json::to_value(payload.normalize().unwrap()).unwrap();
            assert_eq!(normalized.as_object().unwrap().len(), 8, "{id}");
            if !case["expected"].is_null() {
                assert_eq!(normalized, case["expected"], "{id}");
            }
        }
    }
}
