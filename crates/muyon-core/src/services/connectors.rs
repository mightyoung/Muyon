//! Local Connector snapshots only. No transport, credentials or persistent commands.
use super::types::{Digest, ScopeRef, ServiceError, UnixMs};
use crate::contract::Revision;
use serde::{de, Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;
use std::{collections::BTreeSet, fmt};

macro_rules! wire_enum {
    ($name:ident { $($variant:ident),+ }) => {
        #[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
        #[serde(rename_all = "snake_case")]
        pub enum $name { $($variant),+ }
    };
}
wire_enum!(ConnectorProtocol { Mcp, Http });
wire_enum!(AuthMethod {
    None,
    OAuth,
    ApiKey,
    HostManaged
});
wire_enum!(CapabilityKind {
    Tool,
    Resource,
    Prompt
});
wire_enum!(AuthState {
    NotConfigured,
    ConsentRequired,
    Authorized,
    Expired,
    Revoked,
    Unknown
});
wire_enum!(CatalogState {
    NotReady,
    Ready,
    Partial,
    Failed,
    Unknown
});
wire_enum!(NetworkState {
    Disconnected,
    Connected,
    Unknown
});
wire_enum!(Availability {
    Available,
    Unavailable,
    Unknown
});

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
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConnectionSnapshot {
    pub connection_id: String,
    pub connector: ConnectorRef,
    pub scope: ScopeRef,
    #[serde(
        serialize_with = "serialize_endpoint",
        deserialize_with = "deserialize_endpoint"
    )]
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
/// Exact adapter identity lookup over host-filtered local snapshots. Never refreshes.
pub fn get_descriptor<'a>(
    descriptors: &'a [ConnectorDescriptor],
    reference: &ConnectorRef,
) -> Result<&'a ConnectorDescriptor, ServiceError> {
    let mut found = descriptors.iter().filter(|d| d.reference == *reference);
    let value = found.next().ok_or_else(unavailable)?;
    if found.next().is_some() {
        return Err(invalid());
    }
    Ok(value)
}
/// Returns the stored catalog, including its freshness flag, without networking.
pub fn get_capability_snapshot<'a>(
    catalogs: &'a [CapabilityCatalog],
    connection_id: &str,
) -> Result<&'a CapabilityCatalog, ServiceError> {
    let mut found = catalogs.iter().filter(|c| c.connection_id == connection_id);
    let value = found.next().ok_or_else(unavailable)?;
    if found.next().is_some() {
        return Err(invalid());
    }
    validate_catalog(value)?;
    Ok(value)
}
/// P1 supports this exact trusted built-in schema only, not arbitrary JSON schema.
pub fn public_config_schema() -> Value {
    serde_json::json!({"type":"object","properties":{"endpoint":{"type":"string"},"label":{"type":"string"}},"required":["endpoint"],"additionalProperties":false})
}
pub fn validate_config(
    descriptor: &ConnectorDescriptor,
    public_config: &Value,
) -> Result<(), ServiceError> {
    if descriptor.config_schema != public_config_schema() {
        return Err(unavailable());
    }
    let fields = public_config.as_object().ok_or_else(invalid)?;
    if fields
        .keys()
        .any(|key| !matches!(key.as_str(), "endpoint" | "label"))
    {
        return Err(invalid());
    }
    let endpoint = fields
        .get("endpoint")
        .and_then(Value::as_str)
        .ok_or_else(invalid)?;
    // Public config must already be safe. Secret-bearing URL parts belong only to
    // the later trusted host configuration owner, not this public value.
    if public_endpoint(endpoint).as_deref() != Some(endpoint) {
        return Err(invalid());
    }
    if fields.get("label").is_some_and(|v| {
        v.as_str()
            .is_none_or(|s| s.len() > 256 || s.chars().any(char::is_control))
    }) {
        return Err(invalid());
    }
    Ok(())
}
pub(crate) fn validate_catalog(catalog: &CapabilityCatalog) -> Result<(), ServiceError> {
    if !valid_identity(&catalog.connection_id)
        || !valid_identity(&catalog.protocol_version)
        || catalog.entries.len() > 4096
    {
        return Err(invalid());
    }
    let mut seen = BTreeSet::new();
    for entry in &catalog.entries {
        if !valid_identity(&entry.name) || !seen.insert(capability_key(&entry.kind, &entry.name)) {
            return Err(invalid());
        }
    }
    Ok(())
}
/// Kind-qualified keys prevent a prompt/resource with the same name becoming a tool grant.
pub fn capability_key(kind: &CapabilityKind, name: &str) -> String {
    let prefix = match kind {
        CapabilityKind::Tool => "tool",
        CapabilityKind::Resource => "resource",
        CapabilityKind::Prompt => "prompt",
    };
    format!("{prefix}:{name}")
}
pub(crate) fn valid_identity(value: &str) -> bool {
    !value.is_empty() && value.len() <= 128 && !value.chars().any(char::is_control)
}
pub(crate) fn invalid() -> ServiceError {
    error(super::types::ErrorCode::InvalidArgument)
}
fn unavailable() -> ServiceError {
    error(super::types::ErrorCode::CapabilityUnavailable)
}
pub(crate) fn error(code: super::types::ErrorCode) -> ServiceError {
    ServiceError {
        code,
        phase: "connector_preflight".into(),
        retryability: super::types::Retryability::Never,
        effect_knowledge: super::types::EffectKnowledge::NotStarted,
        original_intent_id: None,
        safe_message: "Connector snapshot or request unavailable.".into(),
        details_ref: None,
    }
}
// This is a deliberately restricted URL projection, not a request URL parser.
// Original endpoints are resolved separately by a trusted host, never reconstructed here.
fn public_endpoint(raw: &str) -> Option<String> {
    if raw.len() > 4096
        || raw.chars().any(|c| c.is_control() || c.is_whitespace())
        || raw.contains('\\')
    {
        return None;
    }
    let (scheme, rest) = raw.split_once("://")?;
    if !matches!(scheme, "https" | "http") {
        return None;
    }
    let rest = rest.split(['?', '#']).next()?;
    let (authority, path) = rest.split_once('/').map_or((rest, ""), |(a, p)| (a, p));
    let authority = authority.rsplit('@').next()?;
    if authority.is_empty() || !authority.is_ascii() || authority.contains('%') {
        return None;
    }
    let (host, port) = if authority.starts_with('[') {
        let end = authority.find(']')?;
        authority[1..end].parse::<std::net::Ipv6Addr>().ok()?;
        let after = &authority[end + 1..];
        (
            &authority[..=end],
            if after.is_empty() {
                None
            } else {
                Some(after.strip_prefix(':')?)
            },
        )
    } else {
        let (h, p) = authority
            .split_once(':')
            .map_or((authority, None), |(h, p)| (h, Some(p)));
        if h.is_empty()
            || !h
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'-'))
        {
            return None;
        }
        (h, p)
    };
    if let Some(port) = port {
        if port.is_empty()
            || !port.bytes().all(|b| b.is_ascii_digit())
            || port.parse::<u16>().is_err()
        {
            return None;
        }
    }
    if host.is_empty() {
        return None;
    }
    let slash = if rest.contains('/') { "/" } else { "" };
    Some(format!("{scheme}://{authority}{slash}{path}"))
}
fn serialize_endpoint<S: Serializer>(raw: &str, serializer: S) -> Result<S::Ok, S::Error> {
    serializer.serialize_str(&public_endpoint(raw).unwrap_or_else(|| "[unavailable]".into()))
}
fn deserialize_endpoint<'de, D: Deserializer<'de>>(deserializer: D) -> Result<String, D::Error> {
    let raw = String::deserialize(deserializer)?;
    public_endpoint(&raw).ok_or_else(|| de::Error::custom("invalid public endpoint"))
}
impl fmt::Debug for ConnectionSnapshot {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        // Serialize uses the exact same safety projection as the UI wire.
        match serde_json::to_value(self) {
            Ok(value) => formatter
                .debug_tuple("ConnectionSnapshot")
                .field(&value)
                .finish(),
            Err(_) => formatter.write_str("ConnectionSnapshot([unavailable])"),
        }
    }
}
