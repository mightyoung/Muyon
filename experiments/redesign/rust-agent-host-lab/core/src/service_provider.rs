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
    pub fn readiness(&self, _budget: &CallBudget) -> Result<ConfiguredProfile> {
        Err("service_provider_unavailable".into())
    }
    pub fn prepare(&self, _request_id: &str, _payload: &[u8], _budget: CallBudget) -> Result<PreparedProviderCall> {
        Err("service_provider_unavailable".into())
    }
    pub fn final_admit(&self, _prepared: PreparedProviderCall) -> Result<ProviderAdmission> {
        Err("service_provider_unavailable".into())
    }
}
