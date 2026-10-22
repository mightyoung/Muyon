use muyon_android_contract_bridge::service_host_bridge::{
    service_owner_adapter, ServiceHostOwnerCallback, ServiceOwnerProvider, ServiceOwnerScope,
};
use std::sync::{Arc, atomic::{AtomicUsize, Ordering}};
use muyon_android_contract_bridge::service_host_bridge::*;

struct UnconfiguredOwner { scope_reads: AtomicUsize, provider_reads: AtomicUsize }
impl ServiceHostOwnerCallback for UnconfiguredOwner {
    fn exchange_live_chat(&self,_:String,_:ServiceOwnerAdmissionBinding,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability,_:Arc<ServiceOwnerRunControl>)->Option<ServiceOwnerChatResponse>{None}
    fn settle_chat(&self,_:String,_:bool)->bool{false}
    fn chat_settlement(&self,_:String)->Option<String>{None}
    fn current_chat_authority(&self,_:String,_:String)->Option<ServiceOwnerChatAuthority>{None}
    fn credential_capability(&self,_:String,_:String)->Option<ServiceOwnerCredentialCapability>{None}
    fn bind_chat_context(&self,_:String,_:ServiceOwnerAdmissionBinding,_:String,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability)->bool{false}
    fn exchange_chat(&self,_:String,_:ServiceOwnerAdmissionBinding,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability)->Option<ServiceOwnerChatResponse>{None}

    fn release_reservation(&self, _: String) -> bool { false }
    fn review_payload(&self, _: ServiceOwnerAdmissionBinding, _: Vec<u8>) -> bool { false }
    fn reserve_budget(&self, _: ServiceOwnerAdmissionBinding, _: String, _: Vec<u8>, _: ServiceOwnerCallBudget) -> Option<String> { None }
    fn commit_admission(&self, _: String, _: ServiceOwnerAdmissionBinding, _: String, _: Vec<u8>, _: String, _: String) -> Option<String> { None }

    fn current_scope(&self) -> Option<ServiceOwnerScope> {
        self.scope_reads.fetch_add(1, Ordering::SeqCst);
        None
    }
    fn current_provider(&self) -> Option<ServiceOwnerProvider> {
        self.provider_reads.fetch_add(1, Ordering::SeqCst);
        None
    }
}

fn profile() -> ServiceOwnerProfile {
    ServiceOwnerProfile {
        id: "approved-fixture".into(), endpoint: "https://provider.example/v1".into(),
        endpoint_identity: "fixture-endpoint".into(), provider: "fixture".into(), model: "fixture-chat".into(),
        location: ServiceOwnerLocation::Remote, purpose: ServiceOwnerPurpose::Chat,
        credential_ref: "existing-handle-ref".into(),
        declared: ServiceOwnerCapabilities { tool_calls: true, streaming: false },
        tested: ServiceOwnerCapabilities { tool_calls: true, streaming: false },
    }
}
struct ConfiguredOwner { available: std::sync::atomic::AtomicBool }
impl ServiceHostOwnerCallback for ConfiguredOwner {
    fn exchange_live_chat(&self,_:String,_:ServiceOwnerAdmissionBinding,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability,_:Arc<ServiceOwnerRunControl>)->Option<ServiceOwnerChatResponse>{None}
    fn settle_chat(&self,_:String,_:bool)->bool{false}
    fn chat_settlement(&self,_:String)->Option<String>{None}
    fn current_chat_authority(&self,_:String,_:String)->Option<ServiceOwnerChatAuthority>{None}
    fn credential_capability(&self,_:String,_:String)->Option<ServiceOwnerCredentialCapability>{None}
    fn bind_chat_context(&self,_:String,_:ServiceOwnerAdmissionBinding,_:String,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability)->bool{false}
    fn exchange_chat(&self,_:String,_:ServiceOwnerAdmissionBinding,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability)->Option<ServiceOwnerChatResponse>{None}

    fn release_reservation(&self, _: String) -> bool { false }
    fn review_payload(&self, _: ServiceOwnerAdmissionBinding, _: Vec<u8>) -> bool { false }
    fn reserve_budget(&self, _: ServiceOwnerAdmissionBinding, _: String, _: Vec<u8>, _: ServiceOwnerCallBudget) -> Option<String> { None }
    fn commit_admission(&self, _: String, _: ServiceOwnerAdmissionBinding, _: String, _: Vec<u8>, _: String, _: String) -> Option<String> { None }

    fn current_scope(&self) -> Option<ServiceOwnerScope> {
        Some(ServiceOwnerScope {
            source_identity: "trusted-source".into(), namespace: "trusted-namespace".into(),
            managed_root: "/owner/private".into(), database: "/owner/private/user.db".into(),
            decision: ServiceOwnerDecision {
                source_identity: "trusted-source".into(), namespace: "trusted-namespace".into(),
                allowed: self.available.load(Ordering::SeqCst), available: true, scope_allowed: true,
                bindings: vec!["host-supplier-name-read".into()], revision: "a".into(),
                binding_revision: "b".into(), source_revision: "c".into(), rule_revision: "d".into(),
                scope: "selected".into(), selected: vec![ServiceOwnerSelection { key: "supplier".into(), revision: "7".into() }],
            },
        })
    }
    fn current_provider(&self) -> Option<ServiceOwnerProvider> {
        Some(ServiceOwnerProvider {
            profile: profile(), profile_revision: "profile1".into(), policy_revision: "policy1".into(),
            grant_revision: "grant1".into(), authorization_owner: "trusted-owner".into(),
            model_allowed: true, outbound_allowed: true,
            budget: ServiceOwnerBudget { revision: "budget1".into(), quota_proof: "quota1".into(),
                remaining_calls: 1, remaining_tokens: 10, remaining_micros: 10 },
            credential_handle_available: self.available.load(Ordering::SeqCst),
        })
    }
}

#[test]
fn service_callback_maps_current_scope_and_handle_existence_without_transport() {
    let callback = Arc::new(ConfiguredOwner { available: std::sync::atomic::AtomicBool::new(true) });
    let owner = service_owner_adapter(callback.clone());
    let scope = owner.current_scope().expect("trusted owner scope");
    assert_eq!(scope.source_identity, "trusted-source");
    assert_eq!(scope.namespace, "trusted-namespace");
    assert_eq!(scope.database, std::path::PathBuf::from("/owner/private/user.db"));
    assert!(scope.decision.allowed);
    assert_eq!(scope.decision.selected[0].revision, "7");
    let provider = owner.provider().expect("thread-local provider adapter");
    let budget = muyon_rust_agent_host_lab::service_provider::CallBudget {
        max_tokens: 1, max_micros: 1, requires_tools: true, requires_streaming: false,
    };
    assert_eq!(provider.readiness(&budget).expect("metadata readiness only").id, "approved-fixture");
    assert_eq!(provider.prepare("request", br#"{"model":"fixture-chat","max_tokens":1}"#, budget.clone()).err().as_deref(), Some("provider_payload_denied"));
    callback.available.store(false, Ordering::SeqCst);
    assert!(!owner.current_scope().expect("current revoked decision").decision.allowed);
    assert!(provider.readiness(&budget).is_err());
}

#[test]
fn unconfigured_service_owner_fails_closed_and_is_queried_fresh() {
    let callback = Arc::new(UnconfiguredOwner {
        scope_reads: AtomicUsize::new(0), provider_reads: AtomicUsize::new(0),
    });
    let owner = service_owner_adapter(callback.clone());
    assert_eq!(owner.current_scope().err().as_deref(), Some("service_scope_unconfigured"));
    assert_eq!(owner.current_scope().err().as_deref(), Some("service_scope_unconfigured"));
    assert_eq!(callback.scope_reads.load(Ordering::SeqCst), 2);
    let provider = owner.provider().expect("adapter creation has no side effects");
    let budget = muyon_rust_agent_host_lab::service_provider::CallBudget {
        max_tokens: 1, max_micros: 1, requires_tools: false, requires_streaming: false,
    };
    assert!(provider.readiness(&budget).is_err());
    assert_eq!(callback.provider_reads.load(Ordering::SeqCst), 1);
}

// Deliberately synthetic owner: this exercises the adapter, not durable production storage.
struct AdmissionOwner {
    mode: AtomicUsize,
    revision: AtomicUsize,
    reviews: AtomicUsize,
    reserves: AtomicUsize,
    commits: AtomicUsize,
    consumed: std::sync::atomic::AtomicBool,
    reserved_budget: std::sync::Mutex<Option<muyon_rust_agent_host_lab::service_provider::CallBudget>>,
}
impl AdmissionOwner {
    fn new(mode: usize) -> Self {
        Self { mode: AtomicUsize::new(mode), revision: AtomicUsize::new(0),
            reviews: AtomicUsize::new(0), reserves: AtomicUsize::new(0),
            commits: AtomicUsize::new(0), consumed: std::sync::atomic::AtomicBool::new(false),
            reserved_budget: std::sync::Mutex::new(None) }
    }
    fn check_binding(&self, b: &ServiceOwnerAdmissionBinding) {
        assert_eq!(b.profile.id, "approved-fixture");
        assert_eq!(b.profile.endpoint, "https://provider.example/v1");
        assert_eq!(b.profile.endpoint_identity, "fixture-endpoint");
        assert_eq!(b.profile.provider, "fixture");
        assert_eq!(b.profile.model, "fixture-chat");
        assert_eq!(matches!(b.profile.location, ServiceOwnerLocation::OwnDevice), self.mode.load(Ordering::SeqCst) == 10);
        assert!(matches!(b.profile.purpose, ServiceOwnerPurpose::Chat));
        assert_eq!(b.profile.credential_ref, "existing-handle-ref");
        let alternate = self.mode.load(Ordering::SeqCst) == 10;
        assert_eq!(b.profile.declared.tool_calls, !alternate);
        assert!(b.profile.tested.tool_calls);
        assert_eq!(b.profile.declared.streaming, alternate);
        assert_eq!(b.profile.tested.streaming, alternate);
        assert_eq!(b.profile_revision, "profile1");
        assert_eq!(b.policy_revision, "policy1");
        assert_eq!(b.grant_revision, "grant1");
        assert_eq!(b.authorization_owner, "trusted-owner");
        assert!(b.model_allowed && b.outbound_allowed);
        assert_eq!(b.budget.revision, "budget1");
        assert_eq!(b.budget.quota_proof, "quota1");
        assert_eq!((b.budget.remaining_calls,b.budget.remaining_tokens,b.budget.remaining_micros), (1,10,10));
    }
}
const PAYLOAD: &[u8] = b"{ \"model\":\"fixture-chat\",\"max_tokens\":3,\"messages\":[] }";
fn admission_budget() -> muyon_rust_agent_host_lab::service_provider::CallBudget {
    muyon_rust_agent_host_lab::service_provider::CallBudget {
        max_tokens: 3, max_micros: 7, requires_tools: true, requires_streaming: false,
    }
}
impl ServiceHostOwnerCallback for AdmissionOwner {
    fn exchange_live_chat(&self,_:String,_:ServiceOwnerAdmissionBinding,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability,_:Arc<ServiceOwnerRunControl>)->Option<ServiceOwnerChatResponse>{None}
    fn settle_chat(&self,_:String,_:bool)->bool{false}
    fn chat_settlement(&self,_:String)->Option<String>{None}
    fn current_chat_authority(&self,_:String,_:String)->Option<ServiceOwnerChatAuthority>{None}
    fn credential_capability(&self,_:String,_:String)->Option<ServiceOwnerCredentialCapability>{None}
    fn bind_chat_context(&self,_:String,_:ServiceOwnerAdmissionBinding,_:String,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability)->bool{false}
    fn exchange_chat(&self,_:String,_:ServiceOwnerAdmissionBinding,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability)->Option<ServiceOwnerChatResponse>{None}

    fn release_reservation(&self, _: String) -> bool { false }
    fn current_scope(&self) -> Option<ServiceOwnerScope> { None }
    fn current_provider(&self) -> Option<ServiceOwnerProvider> {
        let mut p = ConfiguredOwner { available: std::sync::atomic::AtomicBool::new(true) }.current_provider()?;
        if self.mode.load(Ordering::SeqCst) == 10 {
            p.profile.location = ServiceOwnerLocation::OwnDevice;
            p.profile.declared.tool_calls = false;
            p.profile.declared.streaming = true;
            p.profile.tested.streaming = true;
        }
        if self.revision.load(Ordering::SeqCst) != 0 { p.policy_revision = "revoked".into(); }
        Some(p)
    }
    fn review_payload(&self, binding: ServiceOwnerAdmissionBinding, payload: Vec<u8>) -> bool {
        self.check_binding(&binding);
        assert_eq!(payload, PAYLOAD);
        self.reviews.fetch_add(1, Ordering::SeqCst);
        if self.mode.load(Ordering::SeqCst) == 4 { self.revision.store(1, Ordering::SeqCst); }
        self.mode.load(Ordering::SeqCst) != 1
    }
    fn reserve_budget(&self, binding: ServiceOwnerAdmissionBinding, request_id: String,
        payload: Vec<u8>, budget: ServiceOwnerCallBudget) -> Option<String> {
        self.check_binding(&binding);
        assert_eq!(request_id, "exact-request");
        assert_eq!(payload, PAYLOAD);
        let alternate = self.mode.load(Ordering::SeqCst) == 10;
        assert_eq!((budget.max_tokens,budget.max_micros,budget.requires_tools,budget.requires_streaming), (3,7,!alternate,alternate));
        *self.reserved_budget.lock().unwrap() = Some(muyon_rust_agent_host_lab::service_provider::CallBudget {
            max_tokens: budget.max_tokens, max_micros: budget.max_micros,
            requires_tools: budget.requires_tools, requires_streaming: budget.requires_streaming,
        });
        self.reserves.fetch_add(1, Ordering::SeqCst);
        match self.mode.load(Ordering::SeqCst) {
            2 => None,
            5 => { self.revision.store(1, Ordering::SeqCst); Some("owner-reservation".into()) },
            7 => Some(" bad-id ".into()),
            _ => Some("owner-reservation".into()),
        }
    }
    fn commit_admission(&self, reservation: String, binding: ServiceOwnerAdmissionBinding,
        request_id: String, payload: Vec<u8>, credential_profile_id: String, credential_ref: String) -> Option<String> {
        self.check_binding(&binding);
        assert_eq!(reservation, "owner-reservation");
        assert_eq!(request_id, "exact-request");
        assert_eq!(payload, PAYLOAD);
        assert_eq!(credential_profile_id, "approved-fixture");
        assert_eq!(credential_ref, "existing-handle-ref");
        // Mirrors the required owner lookup, not a reconstructed commit budget.
        let mut expected = admission_budget();
        if self.mode.load(Ordering::SeqCst) == 10 { expected.requires_tools = false; expected.requires_streaming = true; }
        assert_eq!(*self.reserved_budget.lock().unwrap(), Some(expected));
        self.commits.fetch_add(1, Ordering::SeqCst);
        match self.mode.load(Ordering::SeqCst) {
            3 | 6 => None,
            8 => Some("".into()),
            _ if self.consumed.swap(true, Ordering::SeqCst) => None,
            _ => Some("synthetic-admission-row".into()),
        }
    }
}
fn admission_provider(owner: Arc<AdmissionOwner>) -> muyon_rust_agent_host_lab::service_provider::ServiceProviderBridge {
    service_owner_adapter(owner).provider().unwrap()
}
#[test]
fn trusted_admission_callbacks_preserve_exact_binding_payload_and_budget() {
    let owner = Arc::new(AdmissionOwner::new(0));
    let provider = admission_provider(owner.clone());
    let prepared = provider.prepare("exact-request", PAYLOAD, admission_budget()).unwrap();
    let admitted = provider.final_admit(prepared).unwrap();
    assert_eq!(admitted.payload(), PAYLOAD);
    assert_eq!(admitted.record_id(), "synthetic-admission-row");
    assert_eq!(admitted.credential_handle().reference(), "existing-handle-ref");
    assert_eq!((owner.reviews.load(Ordering::SeqCst),owner.reserves.load(Ordering::SeqCst),owner.commits.load(Ordering::SeqCst)), (2,1,1));
}
#[test]
fn owner_denial_and_invalid_ids_stop_at_the_correct_boundary() {
    for (mode, expected, reserves, commits) in [(1,"provider_payload_denied",0,0),
        (2,"provider_budget_reservation_failed",1,0),(3,"provider_admission_failed",1,1),
        (7,"provider_budget_reservation_failed",1,0),(8,"provider_admission_failed",1,1)] {
        let owner = Arc::new(AdmissionOwner::new(mode));
        let provider = admission_provider(owner.clone());
        let result = provider.prepare("exact-request", PAYLOAD, admission_budget()).and_then(|p| provider.final_admit(p));
        assert_eq!(result.err().as_deref(), Some(expected), "mode {mode}");
        assert_eq!(owner.reserves.load(Ordering::SeqCst), reserves);
        assert_eq!(owner.commits.load(Ordering::SeqCst), commits);
    }
}
#[test]
fn binding_drift_during_review_or_reserve_prevents_commit() {
    for mode in [4,5] {
        let owner = Arc::new(AdmissionOwner::new(mode));
        let provider = admission_provider(owner.clone());
        assert_eq!(provider.prepare("exact-request", PAYLOAD, admission_budget()).err().as_deref(), Some("provider_binding_changed"));
        assert_eq!(owner.commits.load(Ordering::SeqCst), 0);
        assert_eq!(owner.reserves.load(Ordering::SeqCst), usize::from(mode == 5));
    }
}
#[test]
fn changed_current_binding_before_final_admission_never_calls_owner_commit() {
    let owner = Arc::new(AdmissionOwner::new(0));
    let provider = admission_provider(owner.clone());
    let prepared = provider.prepare("exact-request", PAYLOAD, admission_budget()).unwrap();
    owner.revision.store(1, Ordering::SeqCst);
    assert_eq!(provider.final_admit(prepared).err().as_deref(), Some("provider_binding_changed"));
    assert_eq!(owner.commits.load(Ordering::SeqCst), 0);
}
#[test]
fn synthetic_owner_rejects_reused_reservation_without_claiming_durability() {
    let owner = Arc::new(AdmissionOwner::new(0));
    let provider = admission_provider(owner.clone());
    let first = provider.prepare("exact-request", PAYLOAD, admission_budget()).unwrap();
    let second = provider.prepare("exact-request", PAYLOAD, admission_budget()).unwrap();
    assert!(provider.final_admit(first).is_ok());
    assert_eq!(provider.final_admit(second).err().as_deref(), Some("provider_admission_failed"));
    assert_eq!(owner.commits.load(Ordering::SeqCst), 2);
}

#[test]
fn synthetic_owner_can_expire_reservation_before_commit() {
    let owner = Arc::new(AdmissionOwner::new(0));
    let provider = admission_provider(owner.clone());
    let prepared = provider.prepare("exact-request", PAYLOAD, admission_budget()).unwrap();
    owner.mode.store(6, Ordering::SeqCst);
    assert_eq!(provider.final_admit(prepared).err().as_deref(), Some("provider_admission_failed"));
    assert_eq!(owner.commits.load(Ordering::SeqCst), 1);
}

#[test]
fn own_device_and_asymmetric_capabilities_survive_admission_mapping() {
    let owner = Arc::new(AdmissionOwner::new(10));
    let provider = admission_provider(owner);
    let mut budget = admission_budget();
    budget.requires_tools = false;
    budget.requires_streaming = true;
    let prepared = provider.prepare("exact-request", PAYLOAD, budget).unwrap();
    let admitted = provider.final_admit(prepared).unwrap();
    assert!(matches!(admitted.profile().location, muyon_rust_agent_host_lab::service_provider::ModelLocation::OwnDevice));
    assert!(!admitted.profile().declared.tool_calls);
    assert!(admitted.profile().tested.tool_calls && admitted.profile().tested.streaming);
}
