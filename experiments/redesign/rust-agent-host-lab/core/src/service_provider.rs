//! Service-owned configured-provider admission. No transport or secret-value API.
use std::rc::Rc;
use muyon_core_agent_lab::Result;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelLocation { Remote, OwnDevice }
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelPurpose { Chat, Embedding }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Capabilities { pub tool_calls: bool, pub streaming: bool }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConfiguredProfile {
    pub id: String, pub endpoint: String, pub endpoint_identity: String,
    pub provider: String, pub model: String, pub location: ModelLocation,
    pub purpose: ModelPurpose, pub credential_ref: String,
    pub declared: Capabilities, pub tested: Capabilities,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProviderBudget {
    pub revision: String, pub quota_proof: String,
    pub remaining_calls: u64, pub remaining_tokens: u64, pub remaining_micros: u64,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProviderBinding {
    pub profile: ConfiguredProfile,
    pub profile_revision: String, pub policy_revision: String, pub grant_revision: String,
    pub authorization_owner: String, pub model_allowed: bool, pub outbound_allowed: bool,
    pub budget: ProviderBudget,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallBudget {
    pub max_tokens: u64, pub max_micros: u64,
    pub requires_tools: bool, pub requires_streaming: bool,
}
/// Opaque platform handle, never credential bytes. It deliberately has no Debug.
#[derive(PartialEq, Eq)]
pub struct CredentialHandle { profile: String, reference: String, opaque: String }
impl CredentialHandle {
    pub fn new(profile: &str, reference: &str, opaque: &str) -> Result<Self> {
        if profile.is_empty() || reference.is_empty() || opaque.is_empty() {
            return Err("credential_handle_unavailable".into());
        }
        Ok(Self { profile: profile.into(), reference: reference.into(), opaque: opaque.into() })
    }
    pub fn reference(&self) -> &str { &self.reference }
}
/// Implemented only by the trusted Service owner. No UI deserialization path.
/// Reserve and commit must use the owner's durable quota/outbound ledger.
/// Commit must atomically recheck the exact binding, handle and reservation;
/// a returned row is admission only, never evidence that a request was sent.
pub trait ServiceProviderHost {
    fn current_binding(&self) -> Result<Option<ProviderBinding>>;
    fn credential_handle(&self, profile: &ConfiguredProfile) -> Result<Option<CredentialHandle>>;
    fn review_payload(&self, binding: &ProviderBinding, payload: &[u8]) -> Result<()>;
    fn reserve_budget(&self, binding: &ProviderBinding, request_id: &str, payload: &[u8], budget: &CallBudget) -> Result<String>;
    fn commit_admission(&self, reservation: &str, binding: &ProviderBinding, request_id: &str, payload: &[u8], handle: &CredentialHandle) -> Result<String>;
}
pub struct PreparedProviderCall {
    owner: Rc<dyn ServiceProviderHost>, binding: ProviderBinding, handle: CredentialHandle,
    request_id: String, payload: Vec<u8>, budget: CallBudget, reservation: String,
}
pub struct ProviderAdmission {
    profile: ConfiguredProfile, handle: CredentialHandle, payload: Vec<u8>, record_id: String,
}
impl ProviderAdmission {
    pub fn profile(&self) -> &ConfiguredProfile { &self.profile }
    pub fn credential_handle(&self) -> &CredentialHandle { &self.handle }
    pub fn payload(&self) -> &[u8] { &self.payload }
    pub fn record_id(&self) -> &str { &self.record_id }
}
pub struct ServiceProviderBridge { host: Rc<dyn ServiceProviderHost> }
impl ServiceProviderBridge {
    pub fn new(host: Rc<dyn ServiceProviderHost>) -> Self { Self { host } }
    /// Configuration and handle availability only: no payload, reservation or send.
    pub fn readiness(&self, budget: &CallBudget) -> Result<ConfiguredProfile> {
        let binding = self.binding(budget)?;
        self.handle(&binding.profile)?;
        self.ensure_current(&binding, budget)?;
        Ok(binding.profile)
    }
    pub fn prepare(&self, request_id: &str, payload: &[u8], budget: CallBudget) -> Result<PreparedProviderCall> {
        if !identity(request_id) || payload.is_empty() || payload.len() > 65536 {
            return Err("provider_request_invalid".into());
        }
        let binding = self.binding(&budget)?;
        let json = muyon_plugin_contract_lab::parse(payload).map_err(|_| "provider_payload_invalid")?;
        let fields = json.object().map_err(|_| "provider_payload_invalid")?;
        if fields.get("model").and_then(|v| v.string().ok()) != Some(binding.profile.model.as_str()) {
            return Err("provider_payload_model_mismatch".into());
        }
        // Capabilities must describe the actual wire request, not only caller hints.
        if fields.get("stream") == Some(&crate::Json::Bool(true)) && !budget.requires_streaming {
            return Err("provider_payload_capability_mismatch".into());
        }
        if fields.get("tools").is_some_and(|v| !matches!(v, crate::Json::Array(a) if a.is_empty())) && !budget.requires_tools {
            return Err("provider_payload_capability_mismatch".into());
        }
        let handle = self.handle(&binding.profile)?;
        self.host.review_payload(&binding, payload).map_err(|_| "provider_payload_denied")?;
        self.ensure_current(&binding, &budget)?;
        let reservation = self.host.reserve_budget(&binding, request_id, payload, &budget)
            .map_err(|_| "provider_budget_reservation_failed")?;
        if !identity(&reservation) { return Err("provider_budget_reservation_failed".into()); }
        self.ensure_current(&binding, &budget)?;
        Ok(PreparedProviderCall { owner: self.host.clone(), binding, handle,
            request_id: request_id.into(), payload: payload.to_vec(), budget, reservation })
    }
    /// Consume one prepared call. The trusted host must atomically commit its
    /// exact-current policy, quota reservation and outbound row. This does not
    /// transmit bytes or authorize a transport fallback/retry.
    pub fn final_admit(&self, prepared: PreparedProviderCall) -> Result<ProviderAdmission> {
        if !Rc::ptr_eq(&self.host, &prepared.owner) { return Err("provider_owner_mismatch".into()); }
        self.ensure_current(&prepared.binding, &prepared.budget)?;
        let handle = self.handle(&prepared.binding.profile)?;
        if handle != prepared.handle { return Err("provider_credential_changed".into()); }
        self.host.review_payload(&prepared.binding, &prepared.payload).map_err(|_| "provider_payload_denied")?;
        self.ensure_current(&prepared.binding, &prepared.budget)?;
        let record_id = self.host.commit_admission(&prepared.reservation, &prepared.binding,
            &prepared.request_id, &prepared.payload, &handle).map_err(|_| "provider_admission_failed")?;
        if !identity(&record_id) { return Err("provider_admission_failed".into()); }
        Ok(ProviderAdmission { profile: prepared.binding.profile, handle, payload: prepared.payload, record_id })
    }
    fn binding(&self, budget: &CallBudget) -> Result<ProviderBinding> {
        let binding = self.host.current_binding().map_err(|_| "provider_config_unavailable")?
            .ok_or("provider_config_unavailable")?;
        validate_binding(&binding, budget)?;
        Ok(binding)
    }
    fn ensure_current(&self, binding: &ProviderBinding, budget: &CallBudget) -> Result<()> {
        if self.binding(budget)? != *binding { return Err("provider_binding_changed".into()); }
        Ok(())
    }
    fn handle(&self, profile: &ConfiguredProfile) -> Result<CredentialHandle> {
        let handle = self.host.credential_handle(profile).map_err(|_| "provider_credential_unavailable")?
            .ok_or("provider_credential_unavailable")?;
        if handle.profile != profile.id || handle.reference != profile.credential_ref || !identity(&handle.opaque) {
            return Err("provider_credential_unavailable".into());
        }
        Ok(handle)
    }
}
fn identity(value: &str) -> bool {
    !value.is_empty() && value.len() <= 512 && value.trim() == value && !value.chars().any(char::is_control)
}
fn validate_binding(binding: &ProviderBinding, budget: &CallBudget) -> Result<()> {
    let profile = &binding.profile;
    for value in [&profile.id, &profile.endpoint_identity, &profile.provider, &profile.model,
        &profile.credential_ref, &binding.profile_revision, &binding.policy_revision,
        &binding.grant_revision, &binding.authorization_owner] {
        if !identity(value) { return Err("provider_binding_invalid".into()); }
    }
    if !https_endpoint(&profile.endpoint) || profile.purpose != ModelPurpose::Chat
        || !binding.model_allowed || !binding.outbound_allowed
        || (budget.requires_tools && (!profile.declared.tool_calls || !profile.tested.tool_calls))
        || (budget.requires_streaming && (!profile.declared.streaming || !profile.tested.streaming)) {
        return Err("provider_binding_invalid".into());
    }
    let remaining = &binding.budget;
    if !identity(&remaining.revision) || !identity(&remaining.quota_proof)
        || budget.max_tokens == 0 || budget.max_micros == 0 || remaining.remaining_calls == 0
        || remaining.remaining_tokens < budget.max_tokens || remaining.remaining_micros < budget.max_micros {
        return Err("provider_budget_unavailable".into());
    }
    Ok(())
}
/// Conservative canonical DNS/IPv4 HTTPS subset. Unsupported URI forms fail
/// closed; no normalization, endpoint completion, DNS lookup or loopback adapter.
fn https_endpoint(endpoint: &str) -> bool {
    if endpoint.len() > 2048 || !endpoint.is_ascii() || endpoint.bytes().any(|b| b <= 32 || b >= 127)
        || endpoint.contains(['@', '?', '#', '\\']) { return false; }
    let Some(rest) = endpoint.strip_prefix("https://") else { return false; };
    let (authority, path) = rest.split_once('/').unwrap_or((rest, ""));
    if path.contains("//") { return false; }
    let (host, port) = authority.split_once(':').map_or((authority, None), |(h,p)| (h,Some(p)));
    if let Some(port) = port {
        if port.parse::<u16>().ok().filter(|n| *n != 0).is_none() || !port.bytes().all(|b| b.is_ascii_digit()) { return false; }
    }
    if host.is_empty() || host.len() > 253 || host.eq_ignore_ascii_case("localhost") || host.to_ascii_lowercase().ends_with(".localhost")
        || host == "0.0.0.0" || host.starts_with("127.") { return false; }
    if !host.contains('.') { return false; }
    if host.bytes().all(|b| b.is_ascii_digit() || b == b'.') {
        let Ok(ip) = host.parse::<std::net::Ipv4Addr>() else { return false; };
        if ip.is_loopback() || ip.is_unspecified() || ip.to_string() != host { return false; }
    }
    host.split('.').all(|label| !label.is_empty() && label.len() <= 63
        && label.as_bytes()[0].is_ascii_alphanumeric()
        && label.as_bytes()[label.len()-1].is_ascii_alphanumeric()
        && label.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-'))
}
