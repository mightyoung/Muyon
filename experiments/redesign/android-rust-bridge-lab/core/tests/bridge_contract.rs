use muyon_android_contract_bridge::*;
fn request(variant: DiagnosticVariant) -> DiagnosticRequest {
    DiagnosticRequest {
        protocol: 1,
        request_id: "request_1-safe".into(),
        variant,
    }
}
fn variants() -> Vec<(DiagnosticVariant, &'static str, u32)> {
    vec![
        (DiagnosticVariant::Equipment, "equipment_loan", 1),
        (DiagnosticVariant::Research, "research", 1),
        (DiagnosticVariant::Inquiry, "inquiry", 2),
        (DiagnosticVariant::SeededEquipment, "module_f65579dc", 1),
    ]
}
#[test]
fn bundled_contract_reaches_rust_catalog() {
    let info = bridge_info();
    assert_eq!(info.protocol, 1);
    assert_eq!(info.build_identity, env!("MUYON_BRIDGE_BUILD_ID"));
    let result = validate_bundled_contract(request(DiagnosticVariant::Equipment));
    assert!(
        result.is_ok() || result == Err(BridgeError::InternalFailure),
        "valid call must reach the known refusing Rust boundary"
    );
    assert!(
        result.is_ok(),
        "ANDROID_BRIDGE_RED: bundled declaration must be registered and inspected in Rust"
    );
    let report = result.unwrap();
    assert_eq!(report.namespace, "equipment_loan");
    assert_eq!(
        (
            report.data_count,
            report.operation_count,
            report.relation_count,
            report.view_count
        ),
        (2, 1, 1, 1)
    );
    assert_eq!(report.catalog_generation, 1);
}
#[test]
fn all_variants_preserve_fixture_counts_identity_and_fresh_generation() {
    for (variant, namespace, relations) in variants() {
        for round in 0..2 {
            let mut req = request(variant.clone());
            req.request_id = format!("repeat_{round}");
            let report = validate_bundled_contract(req.clone()).unwrap();
            assert_eq!(report.protocol, req.protocol);
            assert_eq!(report.request_id, req.request_id);
            assert_eq!(report.variant, variant);
            assert_eq!(report.namespace, namespace);
            assert_eq!(report.build_identity, env!("MUYON_BRIDGE_BUILD_ID"));
            assert_eq!(report.catalog_generation, 1);
            assert_eq!(
                (
                    report.data_count,
                    report.operation_count,
                    report.relation_count,
                    report.view_count
                ),
                (2, 1, relations, 1)
            );
        }
    }
}
#[test]
fn protocol_rejection_has_valid_sibling() {
    assert!(validate_bundled_contract(request(DiagnosticVariant::Equipment)).is_ok());
    for protocol in [0, 2, u32::MAX] {
        let mut req = request(DiagnosticVariant::Equipment);
        req.protocol = protocol;
        assert_eq!(
            validate_bundled_contract(req),
            Err(BridgeError::UnsupportedProtocol)
        );
    }
}
#[test]
fn request_id_accepts_only_frozen_safe_ascii_bound() {
    for id in [
        "A".into(),
        "_".into(),
        "-".into(),
        "Z9_safe-ID".into(),
        "a".repeat(64),
    ] {
        let mut req = request(DiagnosticVariant::Research);
        req.request_id = id.clone();
        assert_eq!(validate_bundled_contract(req).unwrap().request_id, id);
    }
    for id in [
        "".into(),
        "a".repeat(65),
        "has.dot".into(),
        "space id".into(),
        "line\nbreak".into(),
        "tab\tid".into(),
        "null\0id".into(),
        "中文".into(),
        "é".into(),
        "🚀".into(),
    ] {
        let mut req = request(DiagnosticVariant::Research);
        req.request_id = id;
        assert_eq!(
            validate_bundled_contract(req),
            Err(BridgeError::InvalidRequestId)
        );
    }
}
#[test]
fn handshake_declares_only_metadata_surface() {
    let info = bridge_info();
    assert_eq!(info.protocol, 1);
    assert_eq!(
        info.capability,
        DiagnosticCapability::BundledDeclarationValidation
    );
    assert!(
        !info.model && !info.attachments && !info.business_read && !info.write && !info.execute
    );
    assert_eq!(info.build_identity, env!("MUYON_BRIDGE_BUILD_ID"));
}
#[test]
fn errors_are_closed_safe_unit_variants() {
    for (error, tag) in [
        (BridgeError::UnsupportedProtocol, "unsupported_protocol"),
        (BridgeError::InvalidRequestId, "invalid_request_id"),
        (BridgeError::DeclarationRejected, "declaration_rejected"),
        (BridgeError::InternalFailure, "internal_failure"),
    ] {
        assert_eq!(error.to_string(), tag);
    }
}
