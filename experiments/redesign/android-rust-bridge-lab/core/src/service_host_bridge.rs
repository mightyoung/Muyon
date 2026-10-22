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
/// Exact owner snapshot for admission. Availability-only handle sentinels are excluded.
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerAdmissionBinding {
    pub profile: ServiceOwnerProfile,
    pub profile_revision: String, pub policy_revision: String, pub grant_revision: String,
    pub authorization_owner: String, pub model_allowed: bool, pub outbound_allowed: bool,
    pub budget: ServiceOwnerBudget,
}
#[derive(Clone, uniffi::Enum)]
pub enum ServiceOwnerMode { LocalRead, ConfiguredChat }
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerCallBudget {
    pub max_tokens: u64, pub max_micros: u64,
    pub requires_tools: bool, pub requires_streaming: bool,
}
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerChatAuthority {
    pub workspace:String, pub conversation:String, pub owner:String, pub mode:String,
    pub policy_revision:String, pub grant_revision:String, pub rule_revision:String,
    pub restriction_revision:String, pub sensitivity:String,
    pub active:bool, pub model_allowed:bool, pub outbound_allowed:bool,
    pub inherited_allowed:bool, pub synthetic:bool,
}
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerCredentialCapability {pub identity:String,pub generation:u64}
#[derive(Clone, uniffi::Record)]
pub struct ServiceOwnerChatResponse {pub answer:String,pub input_tokens:u64,pub output_tokens:u64,pub synthetic:bool}
/// Rust-created capability for the exact controller run. No UI constructor.
#[derive(uniffi::Object)]
pub struct ServiceOwnerRunControl { control:Arc<muyon_rust_agent_host_lab::service_runtime::RunControl> }
#[uniffi::export]
impl ServiceOwnerRunControl {
    pub fn allowed(&self)->bool { self.control.poll().is_ok() }
}
#[uniffi::export(with_foreign)]
pub trait ServiceHostOwnerCallback: Send + Sync {
    fn current_chat_authority(&self, conversation:String, text:String)->Option<ServiceOwnerChatAuthority>;
    fn credential_capability(&self, profile:String, reference:String)->Option<ServiceOwnerCredentialCapability>;
    fn bind_chat_context(&self,reservation:String,binding:ServiceOwnerAdmissionBinding,request_id:String,payload:Vec<u8>,context:Vec<u8>,capability:ServiceOwnerCredentialCapability)->bool;
    fn exchange_chat(&self, admission:String, binding:ServiceOwnerAdmissionBinding, context:Vec<u8>, payload:Vec<u8>, capability:ServiceOwnerCredentialCapability)->Option<ServiceOwnerChatResponse>;
    fn exchange_live_chat(&self, admission:String, binding:ServiceOwnerAdmissionBinding, context:Vec<u8>, payload:Vec<u8>, capability:ServiceOwnerCredentialCapability, control:Arc<ServiceOwnerRunControl>)->Option<ServiceOwnerChatResponse>;
    /// Pure local, durable acceptance. true is irrevocable success only after Rust's final poll.
    fn settle_chat(&self, admission:String, accepted:bool)->bool;
    fn chat_settlement(&self, admission:String)->Option<String>;
    fn current_scope(&self) -> Option<ServiceOwnerScope>;
    fn current_provider(&self) -> Option<ServiceOwnerProvider>;
    /// Trusted current-policy review of exactly these bytes. Absence must deny.
    fn review_payload(&self, binding: ServiceOwnerAdmissionBinding, payload: Vec<u8>) -> bool;
    /// Durable owner must bind the full budget/request/payload/current owner and
    /// conservatively bound total input+output tokens, one call/choice and spend.
    /// Exposed binding drift fails closed; owner owns stranded hold release/expiry.
    fn reserve_budget(&self, binding: ServiceOwnerAdmissionBinding, request_id: String,
        payload: Vec<u8>, budget: ServiceOwnerCallBudget) -> Option<String>;
    /// Atomically expire held state only; keep tombstone and never refund consumed quota.
    fn release_reservation(&self, reservation: String) -> bool;
    /// Owner must atomically consume its exact reservation, including the full
    /// CallBudget captured at reserve. No credential value or send capability.
    fn commit_admission(&self, reservation: String, binding: ServiceOwnerAdmissionBinding,
        request_id: String, payload: Vec<u8>, credential_profile_id: String,
        credential_ref: String) -> Option<String>;
}

struct CallbackOwner { callback: Arc<dyn ServiceHostOwnerCallback> }
impl ServiceHostOwner for CallbackOwner {
    fn chat_authority(&self,conversation:&str,text:&str)->Result<muyon_rust_agent_host_lab::ordinary_chat::ChatAuthority,String>{
        let a=self.callback.current_chat_authority(conversation.into(),text.into()).ok_or("chat_authority_unconfigured")?;
        Ok(muyon_rust_agent_host_lab::ordinary_chat::ChatAuthority{workspace:a.workspace,conversation:a.conversation,owner:a.owner,mode:a.mode,policy_revision:a.policy_revision,grant_revision:a.grant_revision,rule_revision:a.rule_revision,restriction_revision:a.restriction_revision,sensitivity:a.sensitivity,active:a.active,model_allowed:a.model_allowed,outbound_allowed:a.outbound_allowed,inherited_allowed:a.inherited_allowed,synthetic:a.synthetic})
    }
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
    fn bind_chat_context(&self,reservation:&str,binding:&ProviderBinding,request_id:&str,payload:&[u8],handle:&CredentialHandle,context:&muyon_plugin_contract_lab::Json)->Result<(),String>{
        let capability=ServiceOwnerCredentialCapability{identity:handle.identity().into(),generation:handle.generation().ok_or("chat_credential_unavailable")?};
        if self.callback.bind_chat_context(reservation.into(),admission_binding(binding),request_id.into(),payload.to_vec(),context.encode().into_bytes(),capability){Ok(())}else{Err("chat_context_binding_denied".into())}
    }
    fn exchange_chat(&self,admission:&ProviderAdmission,context:&muyon_plugin_contract_lab::Json)->Result<muyon_rust_agent_host_lab::ordinary_chat::ChatResponse,String>{
        let cap=ServiceOwnerCredentialCapability{identity:admission.credential_handle().identity().into(),generation:admission.credential_handle().generation().ok_or("chat_credential_unavailable")?};
        let r=self.callback.exchange_chat(admission.record_id().into(),admission_binding(admission.binding()),context.encode().into_bytes(),admission.payload().to_vec(),cap).ok_or("chat_exchange_unavailable")?;
        Ok(muyon_rust_agent_host_lab::ordinary_chat::ChatResponse{answer:r.answer,input_tokens:r.input_tokens,output_tokens:r.output_tokens,synthetic:r.synthetic})
    }
    fn exchange_live_chat(&self,admission:&ProviderAdmission,context:&muyon_plugin_contract_lab::Json,control:Arc<muyon_rust_agent_host_lab::service_runtime::RunControl>)->Result<muyon_rust_agent_host_lab::ordinary_chat::ChatResponse,String>{
        let cap=ServiceOwnerCredentialCapability{identity:admission.credential_handle().identity().into(),generation:admission.credential_handle().generation().ok_or("chat_credential_unavailable")?};
        let r=self.callback.exchange_live_chat(admission.record_id().into(),admission_binding(admission.binding()),context.encode().into_bytes(),admission.payload().to_vec(),cap,Arc::new(ServiceOwnerRunControl{control})).ok_or("chat_exchange_unavailable")?;
        Ok(muyon_rust_agent_host_lab::ordinary_chat::ChatResponse{answer:r.answer,input_tokens:r.input_tokens,output_tokens:r.output_tokens,synthetic:r.synthetic})
    }
    fn settle_chat(&self,admission:&str,accepted:bool)->Result<(),String>{if self.callback.settle_chat(admission.into(),accepted){Ok(())}else{Err("chat_settlement_unavailable".into())}}
    fn chat_settlement(&self,admission:&str)->Result<String,String>{self.callback.chat_settlement(admission.into()).ok_or_else(||"chat_settlement_unavailable".into())}
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
        if let Some(cap)=self.callback.credential_capability(requested.id.clone(),requested.credential_ref.clone()) {
            return CredentialHandle::with_generation(&requested.id,&requested.credential_ref,&cap.identity,cap.generation).map(Some)
        }
        // A stable existence-only sentinel. This is never a value-reading credential capability.
        CredentialHandle::new(&requested.id, &requested.credential_ref, "service-owner-existence-only-v1").map(Some)
    }
    fn review_payload(&self, binding: &ProviderBinding, payload: &[u8]) -> Result<(), String> {
        if self.callback.review_payload(admission_binding(binding), payload.to_vec()) { Ok(()) }
        else { Err("service_payload_review_unavailable".into()) }
    }
    fn reserve_budget(&self, binding: &ProviderBinding, request_id: &str, payload: &[u8], budget: &CallBudget) -> Result<String, String> {
        self.callback.reserve_budget(admission_binding(binding), request_id.into(), payload.to_vec(),
            ServiceOwnerCallBudget { max_tokens: budget.max_tokens, max_micros: budget.max_micros,
                requires_tools: budget.requires_tools, requires_streaming: budget.requires_streaming })
            .ok_or_else(|| "service_budget_ledger_unavailable".into())
    }
    fn release_reservation(&self, reservation: &str) -> Result<(), String> {
        if self.callback.release_reservation(reservation.into()) { Ok(()) }
        else { Err("service_reservation_release_unavailable".into()) }
    }
    fn commit_admission(&self, reservation: &str, binding: &ProviderBinding, request_id: &str, payload: &[u8], handle: &CredentialHandle) -> Result<String, String> {
        // Correlation metadata only. The existence sentinel is never exported;
        // it proves neither a usable secret capability nor real handle rotation.
        self.callback.commit_admission(reservation.into(), admission_binding(binding), request_id.into(),
            payload.to_vec(), binding.profile.id.clone(), handle.reference().into())
            .ok_or_else(|| "service_outbound_ledger_unavailable".into())
    }
}
fn admission_binding(b: &ProviderBinding) -> ServiceOwnerAdmissionBinding {
    let p = &b.profile;
    ServiceOwnerAdmissionBinding {
        profile: ServiceOwnerProfile {
            id: p.id.clone(), endpoint: p.endpoint.clone(), endpoint_identity: p.endpoint_identity.clone(),
            provider: p.provider.clone(), model: p.model.clone(), credential_ref: p.credential_ref.clone(),
            location: match p.location { ModelLocation::Remote => ServiceOwnerLocation::Remote, ModelLocation::OwnDevice => ServiceOwnerLocation::OwnDevice },
            purpose: match p.purpose { ModelPurpose::Chat => ServiceOwnerPurpose::Chat, ModelPurpose::Embedding => ServiceOwnerPurpose::Embedding },
            declared: ServiceOwnerCapabilities { tool_calls: p.declared.tool_calls, streaming: p.declared.streaming },
            tested: ServiceOwnerCapabilities { tool_calls: p.tested.tool_calls, streaming: p.tested.streaming },
        },
        profile_revision: b.profile_revision.clone(), policy_revision: b.policy_revision.clone(),
        grant_revision: b.grant_revision.clone(), authorization_owner: b.authorization_owner.clone(),
        model_allowed: b.model_allowed, outbound_allowed: b.outbound_allowed,
        budget: ServiceOwnerBudget { revision: b.budget.revision.clone(), quota_proof: b.budget.quota_proof.clone(),
            remaining_calls: b.budget.remaining_calls, remaining_tokens: b.budget.remaining_tokens,
            remaining_micros: b.budget.remaining_micros },
    }
}
