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
fn identity(raw: &str) -> bool {
    !raw.is_empty()
        && raw.len() <= 128
        && raw
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
}
fn valid_ref(reference: &SkillRef) -> bool {
    identity(&reference.skill_id) && identity(&reference.version)
}
/// Validates candidate metadata only; callers still require trusted current scope.
pub fn validate_catalog(snapshot: &SkillRegistrySnapshot) -> Result<(), ServiceError> {
    for (i, d) in snapshot.skills.iter().enumerate() {
        if !valid_ref(&d.reference)
            || !identity(&d.owner_plugin_id)
            || d.required_capabilities.iter().any(|c| !identity(c))
            || snapshot.skills[..i].iter().any(|p| {
                p.reference.skill_id == d.reference.skill_id
                    && p.reference.version == d.reference.version
            })
        {
            return Err(error(ErrorCode::InvalidArgument));
        }
        if d.contract_major != 1 {
            return Err(error(ErrorCode::UnsupportedVersion));
        }
        if d.input_schema != builtin_input_schema() || d.output_schema != builtin_output_schema() {
            return Err(error(ErrorCode::CapabilityUnavailable));
        }
    }
    for (i, binding) in snapshot.bindings.iter().enumerate() {
        if !identity(&binding.binding_id)
            || !valid_ref(&binding.skill)
            || binding.bot_id.as_deref().is_some_and(|id| !identity(id))
            || snapshot.bindings[..i]
                .iter()
                .any(|b| b.binding_id == binding.binding_id)
            || !snapshot.skills.iter().any(|d| d.reference == binding.skill)
        {
            return Err(error(ErrorCode::InvalidArgument));
        }
    }
    Ok(())
}
/// Checked candidate read: malformed metadata is never reported as an empty catalog.
/// This validates shape only, not the caller's authority or any runnable service.
pub fn list_skills(snapshot: &SkillRegistrySnapshot) -> Result<Vec<SkillRef>, ServiceError> {
    validate_catalog(snapshot)?;
    Ok(snapshot
        .skills
        .iter()
        .map(|d| d.reference.clone())
        .collect())
}
pub fn get_descriptor<'a>(
    snapshot: &'a SkillRegistrySnapshot,
    reference: &SkillRef,
) -> Result<&'a SkillDescriptor, ServiceError> {
    validate_catalog(snapshot)?;
    let d = snapshot
        .skills
        .iter()
        .find(|d| {
            d.reference.skill_id == reference.skill_id && d.reference.version == reference.version
        })
        .ok_or_else(|| error(ErrorCode::CapabilityUnavailable))?;
    if d.reference != *reference {
        return Err(error(ErrorCode::StaleRevision));
    }
    Ok(d)
}
pub fn get_binding<'a>(
    snapshot: &'a SkillRegistrySnapshot,
    binding_id: &str,
) -> Result<&'a SkillBinding, ServiceError> {
    validate_catalog(snapshot)?;
    snapshot
        .bindings
        .iter()
        .find(|b| b.binding_id == binding_id)
        .ok_or_else(|| error(ErrorCode::CapabilityUnavailable))
}
/// CAS candidate check, not a storage command or execution permit.
/// Resolve replacement.skill against the reviewed catalog before persisting.
pub fn validate_binding_update(
    current: &SkillBinding,
    expected: &Revision,
    replacement: &SkillBinding,
) -> Result<(), ServiceError> {
    if expected != &current.revision
        || current.revision.next().ok().as_ref() != Some(&replacement.revision)
    {
        return Err(error(ErrorCode::StaleRevision));
    }
    if current.scope != replacement.scope {
        return Err(error(ErrorCode::ScopeChanged));
    }
    if current.binding_id != replacement.binding_id
        || current.bot_id != replacement.bot_id
        || !identity(&replacement.binding_id)
        || !valid_ref(&replacement.skill)
        || replacement
            .bot_id
            .as_deref()
            .is_some_and(|id| !identity(id))
    {
        return Err(error(ErrorCode::InvalidArgument));
    }
    Ok(())
}
