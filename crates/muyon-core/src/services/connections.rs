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
/// Host supplies both current snapshots and this plugin's grants in the same
/// pre-dispatch critical section. Decoded/model-provided bindings are not authority.
/// This checks the local intersection only; disclosure/budget/consent and concrete
/// Operation mapping must still pass the trusted host gate. No dispatch is enabled.
pub fn validate_call(
    expected: &CallBinding,
    current: &CallBinding,
    current_scope: &ScopeRef,
    request: &RemoteRequest,
    catalog: &CapabilityCatalog,
    binding: &ConnectionBinding,
    host_allowed: &[String],
) -> Result<(), ServiceError> {
    use super::{
        connectors::{
            capability_key, error, invalid, valid_identity, validate_catalog, CapabilityKind,
        },
        types::ErrorCode,
    };
    if expected != current {
        return Err(error(ErrorCode::StaleRevision));
    }
    if binding.scope != *current_scope {
        return Err(error(ErrorCode::ScopeChanged));
    }
    if !valid_identity(&current.connection_id)
        || !valid_identity(&current.external_identity)
        || !valid_identity(&binding.binding_id)
        || !valid_identity(&binding.owner_plugin_id)
    {
        return Err(invalid());
    }
    if binding.connection_id != current.connection_id
        || catalog.connection_id != current.connection_id
        || binding.revision != current.plugin_binding_revision
        || catalog.catalog_revision != current.catalog_revision
    {
        return Err(error(ErrorCode::StaleRevision));
    }
    validate_catalog(catalog)?;
    if !catalog.fresh {
        return Err(error(ErrorCode::CapabilityUnavailable));
    }
    if serde_json::to_vec(request).map_err(|_| invalid())?.len()
        > crate::contract::MAX_COMMAND_BYTES
    {
        return Err(invalid());
    }
    let (name, kind, schema) = match request {
        RemoteRequest::CallTool {
            name,
            schema_digest,
            ..
        } => (name, CapabilityKind::Tool, schema_digest),
        RemoteRequest::ReadResource {
            name,
            schema_digest,
            resource_ref,
        } => {
            if resource_ref.is_empty()
                || resource_ref.len() > 4096
                || resource_ref.chars().any(char::is_control)
            {
                return Err(invalid());
            }
            (name, CapabilityKind::Resource, schema_digest)
        }
        RemoteRequest::GetPrompt {
            name,
            schema_digest,
            ..
        } => (name, CapabilityKind::Prompt, schema_digest),
    };
    if !valid_identity(name) {
        return Err(invalid());
    }
    let entry = catalog
        .entries
        .iter()
        .find(|e| e.name == *name && e.kind == kind)
        .ok_or_else(|| error(ErrorCode::CapabilityUnavailable))?;
    if entry.schema_digest != *schema {
        return Err(error(ErrorCode::StaleRevision));
    }
    let key = capability_key(&kind, name);
    if !binding.allowed_capabilities.contains(&key) || !host_allowed.contains(&key) {
        return Err(error(ErrorCode::PermissionDenied));
    }
    Ok(())
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RemoteEffect {
    NotDispatched,
    Confirmed,
    Unknown,
}
/// Chooses original lookup identity only. Ok does not authorize replay or attest a
/// business outcome; Unknown retains C2's original identity/error-effect envelope.
pub fn recovery_for(effect: RemoteEffect, intent: &IntentId) -> Result<IntentId, ServiceError> {
    match effect {
        RemoteEffect::Unknown => Err(super::commands::unphased_host_error(intent)),
        RemoteEffect::NotDispatched | RemoteEffect::Confirmed => Ok(intent.clone()),
    }
}
