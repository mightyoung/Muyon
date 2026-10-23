//! Pure candidate metadata; registration, binding and enablement grant no authority.
use crate::{contract::Revision, services::types::*};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SkillRef {
    pub skill_id: String,
    pub version: String,
    pub content_digest: Digest,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SkillDescriptor {
    pub reference: SkillRef,
    pub owner_plugin_id: String,
    pub contract_major: u32,
    pub input_schema: Value,
    pub output_schema: Value,
    pub required_capabilities: Vec<String>,
    pub resource_manifest: Vec<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SkillBinding {
    pub binding_id: String,
    pub scope: ScopeRef,
    pub bot_id: Option<String>,
    pub revision: Revision,
    pub skill: SkillRef,
    pub enabled: bool,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SkillRegistrySnapshot {
    pub catalog_revision: Revision,
    pub skills: Vec<SkillDescriptor>,
    pub bindings: Vec<SkillBinding>,
}
pub(crate) fn error(code: ErrorCode) -> ServiceError {
    ServiceError {
        code,
        phase: "skill_validation".into(),
        retryability: Retryability::Never,
        effect_knowledge: EffectKnowledge::NotStarted,
        original_intent_id: None,
        safe_message: "技能候选不可用。".into(),
        details_ref: None,
    }
}
pub fn builtin_descriptors() -> Vec<SkillDescriptor> {
    vec![]
}
pub fn validate_catalog(_: &SkillRegistrySnapshot) -> Result<(), ServiceError> {
    Err(error(ErrorCode::CapabilityUnavailable))
}
pub fn list_skills(_: &SkillRegistrySnapshot) -> Vec<SkillRef> {
    vec![]
}
pub fn get_descriptor<'a>(
    _: &'a SkillRegistrySnapshot,
    _: &SkillRef,
) -> Result<&'a SkillDescriptor, ServiceError> {
    Err(error(ErrorCode::CapabilityUnavailable))
}
pub fn get_binding<'a>(
    _: &'a SkillRegistrySnapshot,
    _: &str,
) -> Result<&'a SkillBinding, ServiceError> {
    Err(error(ErrorCode::CapabilityUnavailable))
}
pub fn validate_binding_update(
    _: &SkillBinding,
    _: &Revision,
    _: &SkillBinding,
) -> Result<(), ServiceError> {
    Err(error(ErrorCode::CapabilityUnavailable))
}
