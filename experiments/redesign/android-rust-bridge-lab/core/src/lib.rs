//! Private stateless offline metadata bridge, not a business execution service.
use std::fmt;

#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum DiagnosticCapability {
    BundledDeclarationValidation,
}
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum DiagnosticVariant {
    Equipment,
    Research,
    Inquiry,
    SeededEquipment,
}
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct BridgeInfo {
    pub protocol: u32,
    pub build_identity: String,
    pub capability: DiagnosticCapability,
    pub model: bool,
    pub attachments: bool,
    pub business_read: bool,
    pub write: bool,
    pub execute: bool,
}
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct DiagnosticRequest {
    pub protocol: u32,
    pub request_id: String,
    pub variant: DiagnosticVariant,
}
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct DiagnosticReport {
    pub protocol: u32,
    pub request_id: String,
    pub build_identity: String,
    pub variant: DiagnosticVariant,
    pub namespace: String,
    pub catalog_generation: u64,
    pub data_count: u32,
    pub operation_count: u32,
    pub relation_count: u32,
    pub view_count: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Error)]
pub enum BridgeError {
    UnsupportedProtocol,
    InvalidRequestId,
    DeclarationRejected,
    InternalFailure,
}
impl fmt::Display for BridgeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::UnsupportedProtocol => "unsupported_protocol",
            Self::InvalidRequestId => "invalid_request_id",
            Self::DeclarationRejected => "declaration_rejected",
            Self::InternalFailure => "internal_failure",
        })
    }
}
impl std::error::Error for BridgeError {}
#[uniffi::export]
pub fn bridge_info() -> BridgeInfo {
    BridgeInfo {
        protocol: 1,
        build_identity: env!("MUYON_BRIDGE_BUILD_ID").into(),
        capability: DiagnosticCapability::BundledDeclarationValidation,
        model: false,
        attachments: false,
        business_read: false,
        write: false,
        execute: false,
    }
}
#[uniffi::export]
pub fn validate_bundled_contract(
    _request: DiagnosticRequest,
) -> Result<DiagnosticReport, BridgeError> {
    eprintln!("ANDROID_BRIDGE_STUB_REACHED code=internal_failure");
    Err(BridgeError::InternalFailure)
}
type CatalogCounts = (u64, u32, u32, u32, u32);
fn parse_inspection(
    _reply: &muyon_plugin_contract_lab::Json,
) -> Result<CatalogCounts, BridgeError> {
    Err(BridgeError::InternalFailure)
}
fn inspect_declaration(
    _declaration: muyon_plugin_contract_lab::mappings::ReadDeclaration,
) -> Result<(String, CatalogCounts), BridgeError> {
    Err(BridgeError::InternalFailure)
}
fn boundary(
    _action: impl FnOnce() -> Result<DiagnosticReport, BridgeError>,
) -> Result<DiagnosticReport, BridgeError> {
    Err(BridgeError::InternalFailure)
}
/// Linux evidence artifact only. Absent from default/Android bindings and library.
#[cfg(feature = "ffi-test-probes")]
#[uniffi::export]
pub fn ffi_test_panic_probe() -> Result<DiagnosticReport, BridgeError> {
    boundary(|| panic!("ANDROID_BRIDGE_TEST_PANIC"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use muyon_plugin_contract_lab::mappings::{declaration, MappingKind};
    use muyon_plugin_contract_lab::{parse, string, Json};
    fn valid_inspect() -> Json {
        parse(br#"{"ok":true,"generation":1,"data_count":2,"operation_count":1,"relation_count":1,"view_count":1}"#).unwrap()
    }
    fn put(value: &mut Json, key: &str, new: Json) {
        if let Json::Object(m) = value {
            m.insert(key.into(), new);
        }
    }
    #[test]
    fn inspection_rejects_missing_malformed_or_overflowed_counts() {
        assert_eq!(parse_inspection(&valid_inspect()), Ok((1, 2, 1, 1, 1)));
        for key in [
            "generation",
            "data_count",
            "operation_count",
            "relation_count",
            "view_count",
        ] {
            let mut missing = valid_inspect();
            if let Json::Object(m) = &mut missing {
                m.remove(key);
            }
            assert_eq!(
                parse_inspection(&missing),
                Err(BridgeError::InternalFailure)
            );
            for bad in [
                Json::Null,
                Json::Bool(true),
                string("1"),
                Json::Number("-1".into()),
                Json::Number("1.0".into()),
            ] {
                let mut reply = valid_inspect();
                put(&mut reply, key, bad);
                assert_eq!(parse_inspection(&reply), Err(BridgeError::InternalFailure));
            }
        }
        for key in [
            "data_count",
            "operation_count",
            "relation_count",
            "view_count",
        ] {
            let mut reply = valid_inspect();
            put(&mut reply, key, Json::Number("4294967296".into()));
            assert_eq!(parse_inspection(&reply), Err(BridgeError::InternalFailure));
        }
        let mut reply = valid_inspect();
        put(&mut reply, "ok", Json::Bool(false));
        assert_eq!(parse_inspection(&reply), Err(BridgeError::InternalFailure));
    }
    #[test]
    fn declaration_rejection_is_closed_and_has_valid_sibling() {
        assert!(inspect_declaration(declaration(MappingKind::Equipment).unwrap()).is_ok());
        let mut rejected = declaration(MappingKind::Equipment).unwrap();
        put(
            &mut rejected.bundle,
            "protocol_version",
            Json::Number("2".into()),
        );
        assert_eq!(
            inspect_declaration(rejected),
            Err(BridgeError::DeclarationRejected)
        );
    }
    #[test]
    fn panic_boundary_contains_failure_and_remains_usable() {
        assert_eq!(
            boundary(|| panic!("ANDROID_BRIDGE_TEST_PANIC")),
            Err(BridgeError::InternalFailure)
        );
        assert!(validate_bundled_contract(DiagnosticRequest {
            protocol: 1,
            request_id: "after_panic".into(),
            variant: DiagnosticVariant::Equipment
        })
        .is_ok());
    }
}
uniffi::setup_scaffolding!();
