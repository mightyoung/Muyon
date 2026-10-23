//! Pure candidate metadata; registration, binding and enablement grant no authority.
use crate::{contract::Revision, services::types::*};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest as _, Sha256};

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
/// Exact compiled resource bytes, never a disk/package scan.
pub fn builtin_descriptors() -> Vec<SkillDescriptor> {
    [
        (
            "supplier-overview",
            "inquiry",
            "supplier_list",
            include_str!("../agent/skills/supplier-overview/SKILL.md"),
        ),
        (
            "paper-overview",
            "research",
            "paper_list",
            include_str!("../agent/skills/paper-overview/SKILL.md"),
        ),
    ]
    .into_iter()
    .map(|(id, owner, capability, body)| SkillDescriptor {
        reference: SkillRef {
            skill_id: id.into(),
            version: "builtin-v1".into(),
            content_digest: digest_bytes(body.as_bytes()),
        },
        owner_plugin_id: owner.into(),
        contract_major: 1,
        input_schema: builtin_input_schema(),
        output_schema: builtin_output_schema(),
        required_capabilities: vec![capability.into()],
        resource_manifest: vec!["SKILL.md".into()],
    })
    .collect()
}
pub(crate) fn digest_bytes(bytes: &[u8]) -> Digest {
    let hex: String = Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    Digest::parse(&hex).expect("SHA256 is canonical hexadecimal")
}
pub(crate) fn builtin_input_schema() -> Value {
    json!({"type":"object","properties":{"limit":{"type":"integer","minimum":1,"maximum":50},"offset":{"type":"integer","minimum":0,"maximum":10000}},"required":["limit","offset"],"additionalProperties":false})
}
pub(crate) fn builtin_output_schema() -> Value {
    json!({"type":"object","required":["records"],"properties":{"records":{"type":"array"}}})
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
