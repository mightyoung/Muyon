//! Generated controller metadata fixture only. Fresh private root, no HTTP/model.
use muyon_android_contract_bridge::{agent_service::*, service_host_bridge::*};
use std::{sync::{Arc, Mutex}, os::unix::fs::PermissionsExt};
struct Owner { calls: Mutex<Vec<String>> }
impl ServiceHostOwnerCallback for Owner {
    fn current_chat_authority(&self,_:String,_:String)->Option<ServiceOwnerChatAuthority>{None}
    fn credential_capability(&self,_:String,_:String)->Option<ServiceOwnerCredentialCapability>{None}
    fn bind_chat_context(&self,_:String,_:ServiceOwnerAdmissionBinding,_:String,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability)->bool{false}
    fn exchange_chat(&self,_:String,_:ServiceOwnerAdmissionBinding,_:Vec<u8>,_:Vec<u8>,_:ServiceOwnerCredentialCapability)->Option<ServiceOwnerChatResponse>{None}

    fn current_scope(&self) -> Option<ServiceOwnerScope> { None }
    fn current_provider(&self) -> Option<ServiceOwnerProvider> {
        Some(ServiceOwnerProvider {
            profile: ServiceOwnerProfile {
                id: "synthetic".into(), endpoint: "https://fixture.invalid/v1".into(),
                endpoint_identity: "synthetic-endpoint".into(), provider: "synthetic".into(),
                model: "service-lifecycle-fixture-model".into(), location: ServiceOwnerLocation::Remote,
                purpose: ServiceOwnerPurpose::Chat, credential_ref: "existence-only".into(),
                declared: ServiceOwnerCapabilities { tool_calls: false, streaming: false },
                tested: ServiceOwnerCapabilities { tool_calls: false, streaming: false },
            }, profile_revision: "v1".into(), policy_revision: "v1".into(), grant_revision: "v1".into(),
            authorization_owner: "synthetic-owner".into(), model_allowed: true, outbound_allowed: true,
            budget: ServiceOwnerBudget { revision: "v1".into(), quota_proof: "synthetic-proof".into(),
                remaining_calls: 1, remaining_tokens: 32, remaining_micros: 4 },
            credential_handle_available: true,
        })
    }
    fn review_payload(&self, _: ServiceOwnerAdmissionBinding, payload: Vec<u8>) -> bool {
        assert_eq!(payload, br#"{"model":"service-lifecycle-fixture-model","messages":[{"role":"user","content":"synthetic admission metadata probe"}],"max_tokens":8,"n":1}"#);
        true
    }
    fn reserve_budget(&self, _: ServiceOwnerAdmissionBinding, request: String, _: Vec<u8>, budget: ServiceOwnerCallBudget) -> Option<String> {
        assert_eq!((budget.max_tokens, budget.max_micros, budget.requires_tools, budget.requires_streaming), (32,4,false,false));
        self.calls.lock().unwrap().push(format!("reserve:{request}")); Some(format!("held:{request}"))
    }
    fn release_reservation(&self, reservation: String) -> bool {
        self.calls.lock().unwrap().push(format!("release:{reservation}")); true
    }
    fn commit_admission(&self, reservation: String, _: ServiceOwnerAdmissionBinding, request: String, _: Vec<u8>, profile: String, reference: String) -> Option<String> {
        assert_eq!((profile.as_str(), reference.as_str()), ("synthetic", "existence-only"));
        assert_eq!(reservation, format!("held:{request}"));
        self.calls.lock().unwrap().push(format!("commit:{request}")); Some("opaque-synthetic-admission-row".into())
    }
}
#[test]
fn generated_controller_fixed_probe_calls_installed_owner_and_rejects_after_retire() {
    let root = std::env::temp_dir().join(format!("muyon-lifecycle-probe-{}", std::process::id()));
    std::fs::create_dir(&root).unwrap();
    std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).unwrap();
    let owner = Arc::new(Owner { calls: Mutex::new(Vec::new()) });
    let controller = AgentServiceController::with_host(AgentServiceConfig { protocol: 1,
        private_root: root.to_str().unwrap().into() }, owner.clone(), ServiceOwnerMode::ConfiguredChat,
        ServiceOwnerCallBudget { max_tokens: 32, max_micros: 4, requires_tools: false, requires_streaming: false }).unwrap();
    controller.await_settled();
    let cancelled = controller.service_admission_probe(ServiceAdmissionProbeOperation::PrimaryCancel);
    assert!(!cancelled.admitted); assert_eq!(cancelled.code, "release_requested");
    let committed = controller.service_admission_probe(ServiceAdmissionProbeOperation::SecondaryCommit);
    assert!(committed.admitted); assert_eq!(committed.record_id, "opaque-synthetic-admission-row");
    assert_eq!(*owner.calls.lock().unwrap(), vec!["reserve:service-lifecycle-primary-v1", "release:held:service-lifecycle-primary-v1",
        "reserve:service-lifecycle-secondary-v1", "commit:service-lifecycle-secondary-v1"]);
    controller.retire_service(); controller.await_settled();
    let count = owner.calls.lock().unwrap().len();
    assert_eq!(controller.service_admission_probe(ServiceAdmissionProbeOperation::TertiaryCommit).code, "service_probe_not_ready");
    assert_eq!(owner.calls.lock().unwrap().len(), count);
    drop(controller);
    // This fixture creates a new root only; retain it as evidence rather than
    // ever reading/reopening or deleting an existing application task database.
}
