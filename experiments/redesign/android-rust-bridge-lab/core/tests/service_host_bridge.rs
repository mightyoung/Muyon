use muyon_android_contract_bridge::service_host_bridge::{
    service_owner_adapter, ServiceHostOwnerCallback, ServiceOwnerProvider, ServiceOwnerScope,
};
use std::sync::{Arc, atomic::{AtomicUsize, Ordering}};
use muyon_android_contract_bridge::service_host_bridge::*;

struct UnconfiguredOwner { scope_reads: AtomicUsize, provider_reads: AtomicUsize }
impl ServiceHostOwnerCallback for UnconfiguredOwner {
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
    assert_eq!(provider.prepare("request", b"payload", budget.clone()).err().as_deref(), Some("provider_payload_denied"));
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
