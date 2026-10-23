// Compile owner source without editing Contracts-owned registration files.
use muyon_core::{contract, services::types};
#[path = "../src/services/connectors.rs"]
pub mod connectors;
use connectors::*;
use contract::{Revision, Scope};
use serde_json::{json, Value};
use types::{decode_strict, Digest, ErrorCode, ScopeRef, UnixMs};

fn scope() -> ScopeRef {
    ScopeRef {
        scope: Scope {
            workspace_id: "workspace:synthetic".into(),
            project_id: Some("project:1".into()),
        },
        account_id: None,
        scope_generation: Revision::new(1),
    }
}
fn schema() -> Value {
    json!({"type":"object","properties":{"endpoint":{"type":"string"},"label":{"type":"string"}},"required":["endpoint"],"additionalProperties":false})
}
fn descriptor() -> ConnectorDescriptor {
    ConnectorDescriptor {
        reference: ConnectorRef {
            connector_id: "connector:local".into(),
            adapter_version: "1".into(),
            descriptor_digest: Digest::parse(&"a".repeat(64)).unwrap(),
        },
        protocol: ConnectorProtocol::Mcp,
        config_schema: schema(),
        auth_method: AuthMethod::HostManaged,
        declared_capabilities: vec!["tool:read".into()],
    }
}
fn catalog() -> CapabilityCatalog {
    CapabilityCatalog {
        connection_id: "connection:1".into(),
        protocol_version: "2025-11-25".into(),
        catalog_revision: Revision::new(9007199254740993),
        fetched_at_unix_ms: UnixMs::parse("0").unwrap(),
        fresh: true,
        entries: vec![CapabilityEntry {
            name: "read".into(),
            kind: CapabilityKind::Tool,
            schema_digest: Digest::parse(&"b".repeat(64)).unwrap(),
        }],
    }
}
fn snapshot(endpoint: &str) -> ConnectionSnapshot {
    ConnectionSnapshot {
        connection_id: "connection:1".into(),
        connector: descriptor().reference,
        scope: scope(),
        endpoint: endpoint.into(),
        external_identity: Some("synthetic:account".into()),
        config_revision: Revision::new(1),
        authorization_generation: Revision::new(1),
        auth: AuthState::Authorized,
        catalog: CatalogState::Failed,
        network: NetworkState::Connected,
        availability: Availability::Unknown,
    }
}

#[test]
fn auth_and_catalog_states_are_independent() {
    let snapshot = snapshot("https://example.invalid/mcp");
    let wire = serde_json::to_value(&snapshot).unwrap();
    assert_eq!(wire["auth"], "authorized");
    assert_eq!(wire["catalog"], "failed");
    assert_eq!(wire["availability"], "unknown");
    assert_eq!(
        get_capability_snapshot(&[], "connection:1")
            .unwrap_err()
            .code,
        ErrorCode::CapabilityUnavailable
    );
    let catalogs = [catalog()];
    assert!(std::ptr::eq(
        get_capability_snapshot(&catalogs, "connection:1").unwrap(),
        &catalogs[0]
    ));
    // No transport parameter/global transport exists. The returned value is the stored snapshot.
    assert_eq!(catalogs[0].catalog_revision.as_str(), "9007199254740993");
}

#[test]
fn no_secret_in_public_projection() {
    let marker = "SYNTHETIC_SECRET_SENTINEL";
    for endpoint in [
        format!("https://user:{marker}@example.invalid/mcp?token={marker}#{marker}"),
        format!("https://example.invalid/mcp?token={marker}#{marker}"),
    ] {
        let s = snapshot(&endpoint);
        let raw = serde_json::to_string(&s).unwrap();
        assert!(
            !raw.contains(marker),
            "serialized public endpoint leaked synthetic secret"
        );
        assert!(!format!("{s:?}").contains(marker));
        let v: Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(v["endpoint"], "https://example.invalid/mcp");
        let mut raw_input = v.clone();
        raw_input["endpoint"] = json!(endpoint);
        let restored: ConnectionSnapshot = decode_strict(&raw_input.to_string()).unwrap();
        assert_eq!(restored.endpoint, "https://example.invalid/mcp");
    }
    for field in [
        "password",
        "token",
        "client_secret",
        "secretRef",
        "api-key",
        "Authorization",
        "nested",
    ] {
        let mut cfg = json!({"endpoint":"https://example.invalid/mcp"});
        cfg[field] = if field == "nested" {
            json!({"password":marker})
        } else {
            json!(marker)
        };
        let error = validate_config(&descriptor(), &cfg).unwrap_err();
        assert_eq!(error.code, ErrorCode::InvalidArgument);
        assert!(!serde_json::to_string(&error).unwrap().contains(marker));
        assert!(!format!("{error:?}").contains(marker));
    }
    assert!(validate_config(
        &descriptor(),
        &json!({"endpoint":"https://example.invalid/mcp", "label":"local"})
    )
    .is_ok());
}

#[test]
fn only_trusted_builtin_schema_and_public_fields_are_accepted() {
    assert!(validate_config(
        &descriptor(),
        &json!({"endpoint":"https://example.invalid/mcp"})
    )
    .is_ok());
    for cfg in [
        json!({}),
        json!({"endpoint":7}),
        json!({"endpoint":"https://example.invalid/", "label":false}),
        json!({"endpoint":"https://user:secret@example.invalid/"}),
        json!({"endpoint":"https://example.invalid/?token=secret"}),
        json!({"endpoint":"https://example.invalid/", "connectionId":"other"}),
    ] {
        assert_eq!(
            validate_config(&descriptor(), &cfg).unwrap_err().code,
            ErrorCode::InvalidArgument
        );
    }
    let mut d = descriptor();
    d.config_schema = json!({"type":"object"});
    assert_eq!(
        validate_config(&d, &json!({"endpoint":"https://example.invalid/"}))
            .unwrap_err()
            .code,
        ErrorCode::CapabilityUnavailable
    );
}

#[test]
fn capability_kinds_are_separate() {
    let mut c = catalog();
    for kind in [CapabilityKind::Resource, CapabilityKind::Prompt] {
        c.entries.push(CapabilityEntry {
            kind,
            ..c.entries[0].clone()
        });
    }
    assert_eq!(
        get_capability_snapshot(&[c.clone()], "connection:1")
            .unwrap()
            .entries
            .len(),
        3
    );
    c.entries.push(c.entries[0].clone());
    assert_eq!(
        get_capability_snapshot(&[c], "connection:1")
            .unwrap_err()
            .code,
        ErrorCode::InvalidArgument
    );
}

#[test]
fn descriptor_identity_is_exact_and_ambiguous_snapshots_are_rejected() {
    let d = descriptor();
    let ds = [d.clone()];
    assert!(std::ptr::eq(
        get_descriptor(&ds, &d.reference).unwrap(),
        &ds[0]
    ));
    let mut changed = d.reference.clone();
    changed.adapter_version = "2".into();
    assert_eq!(
        get_descriptor(&ds, &changed).unwrap_err().code,
        ErrorCode::CapabilityUnavailable
    );
    changed = d.reference.clone();
    changed.descriptor_digest = Digest::parse(&"c".repeat(64)).unwrap();
    assert!(get_descriptor(&ds, &changed).is_err());
    assert!(get_descriptor(&[d.clone(), d.clone()], &d.reference).is_err());
    assert!(get_capability_snapshot(&[catalog(), catalog()], "connection:1").is_err());
}

#[test]
fn endpoint_projection_fails_closed_and_safety_fields_are_strict() {
    for endpoint in [
        "file:///secret",
        "https://",
        "https://example.invalid\\@secret/path",
        "https://exa mple.invalid/",
        "https://example.invalid/\nsecret",
    ] {
        let error = validate_config(&descriptor(), &json!({"endpoint":endpoint})).unwrap_err();
        assert_eq!(error.code, ErrorCode::InvalidArgument);
        assert!(!error.safe_message.contains(endpoint));
    }
    let mut v = serde_json::to_value(snapshot("https://example.invalid/")).unwrap();
    v["secret_ref"] = json!("secret:forged");
    assert!(decode_strict::<ConnectionSnapshot>(&v.to_string()).is_err());
    let c = catalog();
    let mut v = serde_json::to_value(c).unwrap();
    v["approved"] = json!(true);
    assert!(decode_strict::<CapabilityCatalog>(&v.to_string()).is_err());
}

#[test]
fn shared_connector_fixture_is_exercised() {
    let fixture: Value = serde_json::from_str(include_str!(
        "../../../docs/contracts/public-services-v02/fixtures/connectors.json"
    ))
    .unwrap();
    assert_eq!(fixture["contract_major"], 1);
    assert_eq!(fixture["schema_major"], 1);
    for case in fixture["cases"].as_array().unwrap() {
        let raw = case["json"].as_str().unwrap();
        let valid = match case["kind"].as_str().unwrap() {
            "catalog" => decode_strict::<CapabilityCatalog>(raw)
                .is_ok_and(|c| get_capability_snapshot(&[c], "connection:1").is_ok()),
            "snapshot" => decode_strict::<ConnectionSnapshot>(raw).is_ok_and(|s| {
                assert_eq!(s.endpoint, case["expected_endpoint"].as_str().unwrap());
                !serde_json::to_string(&s)
                    .unwrap()
                    .contains("SYNTHETIC_SECRET_SENTINEL")
            }),
            "config" => validate_config(&descriptor(), &serde_json::from_str(raw).unwrap()).is_ok(),
            _ => panic!("unknown fixture kind"),
        };
        assert_eq!(valid, case["valid"].as_bool().unwrap(), "{}", case["id"]);
    }
}
