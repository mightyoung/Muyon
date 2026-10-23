//! Pure pre-dispatch host binding checks. No dispatch, credential access or ledger.
use super::{
    connectors::{CapabilityCatalog, ConnectionBinding},
    types::{Digest, IntentId, ScopeRef, ServiceError},
};
use crate::contract::Revision;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CallBinding {
    pub connection_id: String,
    pub external_identity: String,
    pub endpoint_digest: Digest,
    pub config_revision: Revision,
    pub authorization_generation: Revision,
    pub catalog_revision: Revision,
    pub plugin_binding_revision: Revision,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum RemoteRequest {
    CallTool {
        name: String,
        schema_digest: Digest,
        arguments: Value,
    },
    ReadResource {
        name: String,
        schema_digest: Digest,
        resource_ref: String,
    },
    GetPrompt {
        name: String,
        schema_digest: Digest,
        arguments: Value,
    },
}
pub fn validate_call(
    _expected: &CallBinding,
    _current: &CallBinding,
    _current_scope: &ScopeRef,
    _request: &RemoteRequest,
    _catalog: &CapabilityCatalog,
    _binding: &ConnectionBinding,
    _host_allowed: &[String],
) -> Result<(), ServiceError> {
    Err(super::connectors::error(
        super::types::ErrorCode::CapabilityUnavailable,
    ))
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RemoteEffect {
    NotDispatched,
    Confirmed,
    Unknown,
}
pub fn recovery_for(_effect: RemoteEffect, intent: &IntentId) -> Result<IntentId, ServiceError> {
    Err(super::commands::unphased_host_error(intent))
}
