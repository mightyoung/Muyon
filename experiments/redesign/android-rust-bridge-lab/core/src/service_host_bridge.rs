//! Trusted Service-owner callbacks. These are bootstrap ports, never Binder requests.
use muyon_rust_agent_host_lab::{service_host::{ServiceHostOwner, ServiceHostScope}, service_provider::ServiceProviderBridge};
use std::sync::Arc;

#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerSelection { pub key: String, pub revision: String }
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerDecision {
    pub source_identity: String, pub namespace: String,
    pub allowed: bool, pub available: bool, pub scope_allowed: bool,
    pub bindings: Vec<String>, pub revision: String, pub binding_revision: String,
    pub source_revision: String, pub rule_revision: String, pub scope: String,
    pub selected: Vec<ServiceOwnerSelection>,
}
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerScope {
    pub source_identity: String, pub namespace: String,
    pub managed_root: String, pub database: String, pub decision: ServiceOwnerDecision,
}
#[derive(Clone, uniffi::Enum)]
pub enum ServiceOwnerLocation { Remote, OwnDevice }
#[derive(Clone, uniffi::Enum)]
pub enum ServiceOwnerPurpose { Chat, Embedding }
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerCapabilities { pub tool_calls: bool, pub streaming: bool }
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerProfile {
    pub id: String, pub endpoint: String, pub endpoint_identity: String,
    pub provider: String, pub model: String, pub location: ServiceOwnerLocation,
    pub purpose: ServiceOwnerPurpose, pub credential_ref: String,
    pub declared: ServiceOwnerCapabilities, pub tested: ServiceOwnerCapabilities,
}
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerBudget {
    pub revision: String, pub quota_proof: String,
    pub remaining_calls: u64, pub remaining_tokens: u64, pub remaining_micros: u64,
}
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerProvider {
    pub profile: ServiceOwnerProfile,
    pub profile_revision: String, pub policy_revision: String, pub grant_revision: String,
    pub authorization_owner: String, pub model_allowed: bool, pub outbound_allowed: bool,
    pub budget: ServiceOwnerBudget,
    /// Existence of an owner-held opaque handle, never a credential value.
    pub credential_handle_available: bool,
}
#[derive(Clone, uniffi::Enum)]
pub enum ServiceOwnerMode { LocalRead, ConfiguredChat }
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerCallBudget {
    pub max_tokens: u64, pub max_micros: u64,
    pub requires_tools: bool, pub requires_streaming: bool,
}
#[uniffi::export(with_foreign)]
pub trait ServiceHostOwnerCallback: Send + Sync {
    fn current_scope(&self) -> Option<ServiceOwnerScope>;
    fn current_provider(&self) -> Option<ServiceOwnerProvider>;
}

struct CallbackOwner;
impl ServiceHostOwner for CallbackOwner {
    fn current_scope(&self) -> Result<ServiceHostScope, String> {
        Err("service_scope_unconfigured".into())
    }
    fn provider(&self) -> Result<ServiceProviderBridge, String> {
        Err("service_provider_unconfigured".into())
    }
}
pub fn service_owner_adapter(_callback: Arc<dyn ServiceHostOwnerCallback>) -> Arc<dyn ServiceHostOwner> {
    Arc::new(CallbackOwner)
}
