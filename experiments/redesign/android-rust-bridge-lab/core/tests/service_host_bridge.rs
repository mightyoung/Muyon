use muyon_android_contract_bridge::service_host_bridge::{
    service_owner_adapter, ServiceHostOwnerCallback, ServiceOwnerProvider, ServiceOwnerScope,
};
use std::sync::{Arc, atomic::{AtomicUsize, Ordering}};

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
