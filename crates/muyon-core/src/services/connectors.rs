//! Local Connector snapshots only. No transport, credentials or persistent commands.
use super::types::{Digest, ScopeRef, ServiceError, UnixMs};
use crate::contract::Revision;
use serde::{Deserialize, Serialize};
use serde_json::Value;

macro_rules! wire_enum {
    ($name:ident { $($variant:ident),+ }) => {
        #[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
        #[serde(rename_all = "snake_case")]
        pub enum $name { $($variant),+ }
    };
}
wire_enum!(ConnectorProtocol { Mcp, Http });
wire_enum!(AuthMethod { None, OAuth, ApiKey, HostManaged });
wire_enum!(CapabilityKind { Tool, Resource, Prompt });
wire_enum!(AuthState { NotConfigured, ConsentRequired, Authorized, Expired, Revoked, Unknown });
wire_enum!(CatalogState { NotReady, Ready, Partial, Failed, Unknown });
wire_enum!(NetworkState { Disconnected, Connected, Unknown });
wire_enum!(Availability { Available, Unavailable, Unknown });

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConnectorRef {
    pub connector_id: String,
    pub adapter_version: String,
    pub descriptor_digest: Digest,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConnectorDescriptor {
    pub reference: ConnectorRef,
    pub protocol: ConnectorProtocol,
    pub config_schema: Value,
    pub auth_method: AuthMethod,
    pub declared_capabilities: Vec<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CapabilityEntry {
    pub name: String,
    pub kind: CapabilityKind,
    pub schema_digest: Digest,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CapabilityCatalog {
    pub connection_id: String,
    pub protocol_version: String,
    pub catalog_revision: Revision,
    pub fetched_at_unix_ms: UnixMs,
    pub fresh: bool,
    pub entries: Vec<CapabilityEntry>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConnectionSnapshot {
    pub connection_id: String,
    pub connector: ConnectorRef,
    pub scope: ScopeRef,
    pub endpoint: String,
    pub external_identity: Option<String>,
    pub config_revision: Revision,
    pub authorization_generation: Revision,
    pub auth: AuthState,
    pub catalog: CatalogState,
    pub network: NetworkState,
    pub availability: Availability,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConnectionBinding {
    pub binding_id: String,
    pub connection_id: String,
    pub owner_plugin_id: String,
    pub scope: ScopeRef,
    pub revision: Revision,
    pub allowed_capabilities: Vec<String>,
}
pub fn get_descriptor<'a>(
    _descriptors: &'a [ConnectorDescriptor],
    _reference: &ConnectorRef,
) -> Result<&'a ConnectorDescriptor, ServiceError> {
    Err(unavailable())
}
pub fn get_capability_snapshot<'a>(
    _catalogs: &'a [CapabilityCatalog],
    _connection_id: &str,
) -> Result<&'a CapabilityCatalog, ServiceError> {
    Err(unavailable())
}
pub fn validate_config(_descriptor: &ConnectorDescriptor, _public_config: &Value) -> Result<(), ServiceError> {
    Err(unavailable())
}

fn unavailable() -> ServiceError {
    ServiceError { code:super::types::ErrorCode::CapabilityUnavailable, phase:"connector_preflight".into(), retryability:super::types::Retryability::Never, effect_knowledge:super::types::EffectKnowledge::NotStarted, original_intent_id:None, safe_message:"Connector capability unavailable.".into(), details_ref:None }
}
