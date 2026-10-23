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
pub fn inspect_requirements(_: &SkillDescriptor, _: &[String]) -> RequirementView {
    RequirementView {
        required: vec![],
        available: vec![],
        missing: vec![],
    }
}
pub fn validate_inputs(_: &SkillDescriptor, _: &SkillInputs) -> Result<(), ServiceError> {
    Err(super::skills::error(ErrorCode::CapabilityUnavailable))
}
// Exact approved pure function signature; authorization sets are host-resolved.
#[allow(clippy::too_many_arguments)]
pub fn decide_step(
    _: &SkillDescriptor,
    _: &SkillBinding,
    _: &Revision,
    _: &ScopeRef,
    _: &[String],
    _: &[String],
    _: &[String],
    _: &[String],
) -> StepDecision {
    StepDecision::Reject(super::skills::error(ErrorCode::CapabilityUnavailable))
}
pub fn lookup_original_run(
    _: &dyn HostCommandPort,
    intent: &IntentId,
) -> Result<OriginalLookup, ServiceError> {
    Err(crate::services::commands::unphased_host_error(intent))
}
