//! Trusted Service-owner callbacks. These are bootstrap ports, never Binder requests.
use muyon_rust_agent_host_lab::{service_host::{ServiceHostOwner, ServiceHostScope}, service_provider::*, supplier_scope_bridge::{SupplierScopeDecision, SupplierSelection}};
use std::{sync::Arc, rc::Rc};

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

struct CallbackOwner { callback: Arc<dyn ServiceHostOwnerCallback> }
impl ServiceHostOwner for CallbackOwner {
    fn current_scope(&self) -> Result<ServiceHostScope, String> {
        let s = self.callback.current_scope().ok_or("service_scope_unconfigured")?;
        let d = s.decision;
        Ok(ServiceHostScope {
            source_identity: s.source_identity, namespace: s.namespace,
            managed_root: s.managed_root.into(), database: s.database.into(),
            decision: SupplierScopeDecision {
                source_identity: d.source_identity, namespace: d.namespace,
                allowed: d.allowed, available: d.available, scope_allowed: d.scope_allowed,
                bindings: d.bindings, revision: d.revision, binding_revision: d.binding_revision,
                source_revision: d.source_revision, rule_revision: d.rule_revision, scope: d.scope,
                selected: d.selected.into_iter().map(|s| SupplierSelection { key: s.key, revision: s.revision }).collect(),
            },
        })
    }
    fn provider(&self) -> Result<ServiceProviderBridge, String> {
        Ok(ServiceProviderBridge::new(Rc::new(CallbackProvider { callback: self.callback.clone() })))
    }
}
pub fn service_owner_adapter(callback: Arc<dyn ServiceHostOwnerCallback>) -> Arc<dyn ServiceHostOwner> {
    Arc::new(CallbackOwner { callback })
}
fn profile(p: ServiceOwnerProfile) -> ConfiguredProfile {
    ConfiguredProfile {
        id: p.id, endpoint: p.endpoint, endpoint_identity: p.endpoint_identity,
        provider: p.provider, model: p.model, credential_ref: p.credential_ref,
        location: match p.location { ServiceOwnerLocation::Remote => ModelLocation::Remote, ServiceOwnerLocation::OwnDevice => ModelLocation::OwnDevice },
        purpose: match p.purpose { ServiceOwnerPurpose::Chat => ModelPurpose::Chat, ServiceOwnerPurpose::Embedding => ModelPurpose::Embedding },
        declared: Capabilities { tool_calls: p.declared.tool_calls, streaming: p.declared.streaming },
        tested: Capabilities { tool_calls: p.tested.tool_calls, streaming: p.tested.streaming },
    }
}
struct CallbackProvider { callback: Arc<dyn ServiceHostOwnerCallback> }
impl ServiceProviderHost for CallbackProvider {
    fn current_binding(&self) -> Result<Option<ProviderBinding>, String> {
        Ok(self.callback.current_provider().map(|p| ProviderBinding {
            profile: profile(p.profile), profile_revision: p.profile_revision,
            policy_revision: p.policy_revision, grant_revision: p.grant_revision,
            authorization_owner: p.authorization_owner, model_allowed: p.model_allowed,
            outbound_allowed: p.outbound_allowed,
            budget: ProviderBudget { revision: p.budget.revision, quota_proof: p.budget.quota_proof,
                remaining_calls: p.budget.remaining_calls, remaining_tokens: p.budget.remaining_tokens,
                remaining_micros: p.budget.remaining_micros },
        }))
    }
    fn credential_handle(&self, requested: &ConfiguredProfile) -> Result<Option<CredentialHandle>, String> {
        let Some(current) = self.callback.current_provider() else { return Ok(None) };
        if !current.credential_handle_available || profile(current.profile) != *requested { return Ok(None) }
        // A stable existence-only sentinel. This is never a value-reading credential capability.
        CredentialHandle::new(&requested.id, &requested.credential_ref, "service-owner-existence-only-v1").map(Some)
    }
    fn review_payload(&self, _binding: &ProviderBinding, _payload: &[u8]) -> Result<(), String> {
        Err("service_payload_review_unavailable".into())
    }
    fn reserve_budget(&self, _binding: &ProviderBinding, _request_id: &str, _payload: &[u8], _budget: &CallBudget) -> Result<String, String> {
        Err("service_budget_ledger_unavailable".into())
    }
    fn commit_admission(&self, _reservation: &str, _binding: &ProviderBinding, _request_id: &str, _payload: &[u8], _handle: &CredentialHandle) -> Result<String, String> {
        Err("service_outbound_ledger_unavailable".into())
    }
}
