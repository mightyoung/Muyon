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

/// Borrowed host inputs only: not a serialized grant, persisted state or command.
pub struct ConnectionAdmission<'a> {
    pub current: &'a CallBinding,
    pub scope: &'a ScopeRef,
    pub connection: &'a super::connectors::ConnectionSnapshot,
    pub enabled: bool,
    pub catalog: &'a CapabilityCatalog,
    pub plugin_binding: &'a ConnectionBinding,
    pub host_allowed: &'a [String],
}

/// Additional local readiness gate; successful validation does not dispatch work.
pub fn validate_admission(
    expected: &CallBinding,
    request: &RemoteRequest,
    host: &ConnectionAdmission<'_>,
) -> Result<(), ServiceError> {
    use super::{
        connectors::{error, AuthState, Availability, CatalogState, NetworkState},
        types::ErrorCode,
    };
    if !host.enabled {
        return Err(error(ErrorCode::PermissionDenied));
    }
    let connection = host.connection;
    if connection.scope != *host.scope {
        return Err(error(ErrorCode::ScopeChanged));
    }
    if connection.connection_id != host.current.connection_id
        || connection.external_identity.as_deref() != Some(host.current.external_identity.as_str())
        || connection.config_revision != host.current.config_revision
        || connection.authorization_generation != host.current.authorization_generation
    {
        return Err(error(ErrorCode::StaleRevision));
    }
    validate_call(
        expected,
        host.current,
        host.scope,
        request,
        host.catalog,
        host.plugin_binding,
        host.host_allowed,
    )?;
    if connection.auth != AuthState::Authorized
        || connection.catalog != CatalogState::Ready
        || connection.network != NetworkState::Connected
        || connection.availability != Availability::Available
    {
        return Err(error(ErrorCode::CapabilityUnavailable));
    }
    // endpoint_digest is compared in validate_call using trusted original endpoint
    // bindings. Never reconstruct it from the lossy public endpoint projection.
    Ok(())
}

/// Conservative snapshot changes only, not remote protocol/command operations.
#[derive(Clone, Debug)]
pub enum ConnectionChange {
    LocalDisconnect,
    Disable,
    RevokeUnknown,
}

/// Validates a proposed host snapshot. Does not apply, persist or send anything.
pub fn validate_lifecycle_change(
    before: &super::connectors::ConnectionSnapshot,
    after: &super::connectors::ConnectionSnapshot,
    enabled_before: bool,
    enabled_after: bool,
    change: ConnectionChange,
    original: Option<&IntentId>,
) -> Result<(), ServiceError> {
    use super::{
        connectors::{AuthState, Availability, NetworkState},
        types::ErrorCode,
    };
    // Rejection of a snapshot candidate is never proof that an already-issued
    // remote command did not happen. Retain uncertainty and its original owner.
    let rejected = || lifecycle_error(ErrorCode::StaleRevision, original);
    if before.scope != after.scope {
        return Err(lifecycle_error(ErrorCode::ScopeChanged, original));
    }
    let mut expected = before.clone();
    expected.authorization_generation = before
        .authorization_generation
        .next()
        .map_err(|_| rejected())?;
    match change {
        ConnectionChange::LocalDisconnect => {
            if enabled_before != enabled_after {
                return Err(rejected());
            }
            expected.network = NetworkState::Disconnected;
            expected.availability = Availability::Unavailable;
            // Authentication knowledge is preserved; local disconnect is not revoke.
        }
        ConnectionChange::Disable => {
            if !enabled_before || enabled_after {
                return Err(rejected());
            }
            expected.availability = Availability::Unavailable;
        }
        ConnectionChange::RevokeUnknown => {
            if enabled_before != enabled_after {
                return Err(rejected());
            }
            expected.auth = AuthState::Unknown;
            expected.availability = Availability::Unknown;
        }
    }
    if expected != *after {
        return Err(rejected());
    }
    Ok(())
}
fn lifecycle_error(code: super::types::ErrorCode, original: Option<&IntentId>) -> ServiceError {
    let mut error = super::connectors::error(code);
    error.effect_knowledge = super::types::EffectKnowledge::Unknown;
    error.retryability = super::types::Retryability::AfterLookup;
    error.original_intent_id = original.cloned();
    error
}
