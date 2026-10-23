//! Pure preflight and original lookup. No requestRun, dispatch or second ledger.
use super::skills::{SkillBinding, SkillDescriptor};
use crate::{
    contract::Revision,
    documents::DocumentRef,
    services::{
        commands::{HostCommandPort, OriginalLookup},
        types::*,
    },
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RequirementView {
    pub required: Vec<String>,
    pub available: Vec<String>,
    pub missing: Vec<String>,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SkillInputs {
    pub schema_digest: Digest,
    pub values: Value,
    pub document_refs: Vec<DocumentRef>,
}
#[derive(Clone, Debug, PartialEq)]
pub enum StepDecision {
    Dispatch(Vec<String>),
    Reject(ServiceError),
}
pub fn input_schema_digest(descriptor: &SkillDescriptor) -> Digest {
    super::skills::digest_bytes(
        &serde_json::to_vec(&descriptor.input_schema).expect("JSON Value serializes"),
    )
}
/// Available means the declared requirements present in the host's current set.
pub fn inspect_requirements(descriptor: &SkillDescriptor, available: &[String]) -> RequirementView {
    let required: Vec<String> = descriptor
        .required_capabilities
        .iter()
        .cloned()
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect();
    let present = required
        .iter()
        .filter(|r| available.contains(r))
        .cloned()
        .collect();
    let missing = required
        .iter()
        .filter(|r| !available.contains(r))
        .cloned()
        .collect();
    RequirementView {
        required,
        available: present,
        missing,
    }
}
/// Only reviewed compiled list-argument schemas; not a general JSON Schema engine.
pub fn validate_inputs(
    descriptor: &SkillDescriptor,
    inputs: &SkillInputs,
) -> Result<(), ServiceError> {
    if descriptor.contract_major != 1 {
        return Err(super::skills::error(ErrorCode::UnsupportedVersion));
    }
    if descriptor.input_schema != super::skills::builtin_input_schema()
        || descriptor.output_schema != super::skills::builtin_output_schema()
        || input_schema_digest(descriptor) != inputs.schema_digest
    {
        return Err(super::skills::error(ErrorCode::CapabilityUnavailable));
    }
    let valid = inputs.values.as_object().is_some_and(|o| {
        o.len() == 2
            && o.get("limit")
                .and_then(Value::as_u64)
                .is_some_and(|n| (1..=50).contains(&n))
            && o.get("offset")
                .and_then(Value::as_u64)
                .is_some_and(|n| n <= 10000)
    });
    // Built-in list operations do not accept document/body context.
    if !valid || !inputs.document_refs.is_empty() {
        return Err(super::skills::error(ErrorCode::InvalidArgument));
    }
    Ok(())
}
/// Pure decision only. Inputs are trusted host-resolved current sets, never model authorization.
/// The executor must enforce these checks atomically again at use.
#[allow(clippy::too_many_arguments)] // Exact plan API keeps the four authority sets explicit.
pub fn decide_step(
    descriptor: &SkillDescriptor,
    binding: &SkillBinding,
    expected_binding_revision: &Revision,
    current_scope: &ScopeRef,
    host_allowed: &[String],
    plugin_allowed: &[String],
    connection_allowed: &[String],
    requested: &[String],
) -> StepDecision {
    let reject = |code| StepDecision::Reject(super::skills::error(code));
    if binding.scope != *current_scope {
        return reject(ErrorCode::ScopeChanged);
    }
    if binding.revision != *expected_binding_revision || binding.skill != descriptor.reference {
        return reject(ErrorCode::StaleRevision);
    }
    if !binding.enabled {
        return reject(ErrorCode::CapabilityUnavailable);
    }
    let candidate = super::skills::SkillRegistrySnapshot {
        catalog_revision: Revision::new(0),
        skills: vec![descriptor.clone()],
        bindings: vec![binding.clone()],
    };
    if let Err(e) = super::skills::validate_catalog(&candidate) {
        return StepDecision::Reject(e);
    }
    if requested.is_empty() {
        return reject(ErrorCode::InvalidArgument);
    }
    if requested.iter().any(|r| {
        !host_allowed.contains(r)
            || !plugin_allowed.contains(r)
            || !descriptor.required_capabilities.contains(r)
            || !connection_allowed.contains(r)
    }) {
        return reject(ErrorCode::PermissionDenied);
    }
    StepDecision::Dispatch(
        requested
            .iter()
            .cloned()
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect(),
    )
}
/// The trusted caller authorizes the original scope before invoking this adapter.
/// No retry, prepare, confirm, cancellation or new identity is created.
pub fn lookup_original_run(
    host: &dyn HostCommandPort,
    intent: &IntentId,
) -> Result<OriginalLookup, ServiceError> {
    let unknown = || crate::services::commands::unphased_host_error(intent);
    let result = host.lookup_original(intent).map_err(|_| unknown())?;
    match &result {
        OriginalLookup::NotSubmitted { intent_id } if intent_id != intent => return Err(unknown()),
        OriginalLookup::Execution(r) => {
            r.validate().map_err(|_| unknown())?;
            if r.receipt
                .as_ref()
                .is_some_and(|r| r.intent_id != intent.as_str())
            {
                return Err(unknown());
            }
        }
        _ => {}
    }
    Ok(result)
}

/// Pure adapter to C2 cancel_original; this is not a production host or stop proof.
/// The trusted caller must authorize the original current scope before use.
pub fn cancel_original_run(
    _: &dyn HostCommandPort,
    intent: &IntentId,
) -> Result<crate::contract::ExecutionResult, ServiceError> {
    Err(crate::services::commands::unphased_host_error(intent))
}
