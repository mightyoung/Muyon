//! Pure in-memory metadata admission cleanup; no store, HTTP, model or reopen.
use muyon_rust_agent_host_lab::service_provider::*;
use std::{cell::Cell, rc::Rc};

struct Owner {
    revision: Cell<u8>, drift_on_reserve: Cell<bool>,
    malformed_reservation: Cell<bool>, fail_commit: Cell<bool>, malformed_record: Cell<bool>,
    held: Cell<bool>, consumed: Cell<bool>, releases: Cell<u32>,
}
impl Owner {
    fn new() -> Rc<Self> {
        Rc::new(Self { revision: Cell::new(0), drift_on_reserve: Cell::new(false),
            malformed_reservation: Cell::new(false), fail_commit: Cell::new(false),
            malformed_record: Cell::new(false), held: Cell::new(false),
            consumed: Cell::new(false), releases: Cell::new(0) })
    }
}
impl ServiceProviderHost for Owner {
    fn current_binding(&self) -> Result<Option<ProviderBinding>, String> {
        Ok(Some(ProviderBinding {
            profile: ConfiguredProfile { id: "synthetic".into(), endpoint: "https://fixture.invalid/v1".into(),
                endpoint_identity: "synthetic-endpoint".into(), provider: "synthetic".into(),
                model: "fixture".into(), location: ModelLocation::Remote, purpose: ModelPurpose::Chat,
                credential_ref: "existence-only".into(),
                declared: Capabilities { tool_calls: false, streaming: false },
                tested: Capabilities { tool_calls: false, streaming: false } },
            profile_revision: "v1".into(), policy_revision: format!("v{}", self.revision.get()),
            grant_revision: "v1".into(), authorization_owner: "synthetic-owner".into(),
            model_allowed: true, outbound_allowed: true,
            budget: ProviderBudget { revision: "v1".into(), quota_proof: "synthetic-proof".into(),
                remaining_calls: 1, remaining_tokens: 32, remaining_micros: 4 },
        }))
    }
    fn credential_handle(&self, p: &ConfiguredProfile) -> Result<Option<CredentialHandle>, String> {
        CredentialHandle::new(&p.id, &p.credential_ref, "existence-sentinel").map(Some)
    }
    fn review_payload(&self, _: &ProviderBinding, _: &[u8]) -> Result<(), String> { Ok(()) }
    fn reserve_budget(&self, _: &ProviderBinding, _: &str, _: &[u8], _: &CallBudget) -> Result<String, String> {
        self.held.set(true);
        if self.drift_on_reserve.get() { self.revision.set(1); }
        Ok(if self.malformed_reservation.get() { "" } else { "opaque-held-reservation" }.into())
    }
    fn release_reservation(&self, _: &str) -> Result<(), String> {
        self.releases.set(self.releases.get() + 1);
        if self.held.replace(false) { Ok(()) } else { Err("not_held".into()) }
    }
    fn commit_admission(&self, _: &str, _: &ProviderBinding, _: &str, _: &[u8], _: &CredentialHandle) -> Result<String, String> {
        if self.fail_commit.get() { return Err("synthetic_commit_rejected".into()); }
        assert!(self.held.replace(false));
        self.consumed.set(true);
        Ok(if self.malformed_record.get() { "" } else { "opaque-consumed-row" }.into())
    }
}
fn prepare(bridge: &ServiceProviderBridge) -> Result<PreparedProviderCall, String> {
    bridge.prepare("fixed-request", br#"{"model":"fixture","max_tokens":8}"#,
        CallBudget { max_tokens: 32, max_micros: 4, requires_tools: false, requires_streaming: false })
}
#[test]
fn dropping_prepared_call_releases_one_held_reservation() {
    let owner = Owner::new(); let bridge = ServiceProviderBridge::new(owner.clone());
    drop(prepare(&bridge).unwrap());
    assert!(!owner.held.get()); assert!(!owner.consumed.get()); assert_eq!(owner.releases.get(), 1);
}
#[test]
fn post_reserve_policy_drift_releases_hold() {
    let owner = Owner::new(); owner.drift_on_reserve.set(true);
    assert!(prepare(&ServiceProviderBridge::new(owner.clone())).is_err());
    assert!(!owner.held.get()); assert_eq!(owner.releases.get(), 1);
}
#[test]
fn malformed_reservation_still_runs_cleanup() {
    let owner = Owner::new(); owner.malformed_reservation.set(true);
    assert!(prepare(&ServiceProviderBridge::new(owner.clone())).is_err());
    assert!(!owner.held.get()); assert_eq!(owner.releases.get(), 1);
}
#[test]
fn final_policy_drift_and_commit_failure_release_held_only() {
    for drift in [true, false] {
        let owner = Owner::new(); let bridge = ServiceProviderBridge::new(owner.clone());
        let prepared = prepare(&bridge).unwrap();
        if drift { owner.revision.set(1) } else { owner.fail_commit.set(true) }
        assert!(bridge.final_admit(prepared).is_err());
        assert!(!owner.held.get()); assert!(!owner.consumed.get()); assert_eq!(owner.releases.get(), 1);
    }
}
#[test]
fn successful_commit_never_releases_even_when_returned_row_is_malformed() {
    for malformed in [true, false] {
        let owner = Owner::new(); owner.malformed_record.set(malformed);
        let bridge = ServiceProviderBridge::new(owner.clone());
        assert_eq!(bridge.final_admit(prepare(&bridge).unwrap()).is_err(), malformed);
        assert!(!owner.held.get()); assert!(owner.consumed.get()); assert_eq!(owner.releases.get(), 0);
    }
}
#[test]
fn wrong_bridge_rejection_releases_original_owners_hold() {
    let owner = Owner::new(); let bridge = ServiceProviderBridge::new(owner.clone());
    let other = ServiceProviderBridge::new(Owner::new());
    assert!(other.final_admit(prepare(&bridge).unwrap()).is_err());
    assert_eq!(owner.releases.get(), 1); assert!(!owner.held.get());
}
