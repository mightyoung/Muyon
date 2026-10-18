use muyon_rust_agent_host_lab::service_provider::*;
use std::{cell::{Cell, RefCell}, rc::Rc};

type Result<T> = std::result::Result<T, String>;
fn binding() -> ProviderBinding {
    ProviderBinding {
        profile: ConfiguredProfile {
            id: "approved-profile".into(), endpoint: "https://provider.invalid/v1/chat/completions".into(),
            endpoint_identity: "endpoint-v3".into(), provider: "openai-compatible".into(),
            model: "approved-model".into(), location: ModelLocation::Remote,
            purpose: ModelPurpose::Chat, credential_ref: "keystore-ref".into(),
            declared: Capabilities { tool_calls: true, streaming: false },
            tested: Capabilities { tool_calls: true, streaming: false },
        },
        profile_revision: "profile-1".into(), policy_revision: "policy-1".into(),
        grant_revision: "grant-1".into(), authorization_owner: "host-owner".into(),
        model_allowed: true, outbound_allowed: true,
        budget: ProviderBudget { revision: "budget-1".into(), quota_proof: "quota-1".into(),
            remaining_calls: 1, remaining_tokens: 200, remaining_micros: 100 },
    }
}
struct Host {
    current: RefCell<Option<ProviderBinding>>, available: Cell<bool>,
    review_allowed: Cell<bool>, journal_allowed: Cell<bool>, change_on_reserve: Cell<bool>,
    commits: Cell<usize>, reservations: Cell<usize>,
}
impl Host { fn new() -> Rc<Self> { Rc::new(Self {
    current: RefCell::new(Some(binding())), available: Cell::new(true),
    review_allowed: Cell::new(true), journal_allowed: Cell::new(true), change_on_reserve: Cell::new(false),
    commits: Cell::new(0), reservations: Cell::new(0),
}) } }
impl ServiceProviderHost for Host {
    fn current_binding(&self) -> Result<Option<ProviderBinding>> { Ok(self.current.borrow().clone()) }
    fn credential_handle(&self, profile: &ConfiguredProfile) -> Result<Option<CredentialHandle>> {
        if !self.available.get() { return Ok(None); }
        Ok(Some(CredentialHandle::new(&profile.id, &profile.credential_ref, "opaque-handle")?))
    }
    fn review_payload(&self, _: &ProviderBinding, _: &[u8]) -> Result<()> {
        if self.review_allowed.get() { Ok(()) } else { Err("payload_blocked".into()) }
    }
    fn reserve_budget(&self, _: &ProviderBinding, _: &str, _: &[u8], _: &CallBudget) -> Result<String> {
        self.reservations.set(self.reservations.get() + 1);
        if self.change_on_reserve.get() { self.current.borrow_mut().as_mut().unwrap().policy_revision = "new".into(); }
        Ok("durable-reservation".into())
    }
    fn commit_admission(&self, _: &str, _: &ProviderBinding, _: &str, _: &[u8], _: &CredentialHandle) -> Result<String> {
        if !self.journal_allowed.get() { return Err("ledger_unavailable".into()); }
        self.commits.set(self.commits.get()+1); Ok("durable-outbound-row".into())
    }
}
fn cost() -> CallBudget { CallBudget { max_tokens: 100, max_micros: 50, requires_tools: true, requires_streaming: false } }
fn prepare(host: Rc<Host>) -> Result<PreparedProviderCall> {
    ServiceProviderBridge::new(host).prepare("request-1", br#"{"model":"approved-model","messages":[]}"#, cost())
}
#[test]
fn configured_handle_bridge_admits_exact_payload_without_secret_or_transport() {
    let host = Host::new(); let bridge = ServiceProviderBridge::new(host.clone());
    let pending = prepare(host.clone()).unwrap();
    assert_eq!(host.commits.get(), 0);
    let admitted = bridge.final_admit(pending).unwrap();
    assert_eq!(admitted.profile().model, "approved-model");
    assert_eq!(admitted.payload(), br#"{"model":"approved-model","messages":[]}"#);
    assert_eq!(admitted.credential_handle().reference(), "keystore-ref");
    assert_eq!(admitted.record_id(), "durable-outbound-row");
    assert_eq!(host.commits.get(), 1);
}
#[test]
fn missing_binding_and_handle_fail_closed() {
    let host=Host::new(); *host.current.borrow_mut()=None; assert!(prepare(host.clone()).is_err());
    *host.current.borrow_mut()=Some(binding()); host.available.set(false);
    assert!(prepare(host.clone()).is_err()); assert_eq!(host.reservations.get(),0);
}
#[test]
fn every_configuration_and_authorization_component_is_bound() {
    let mutations: Vec<Box<dyn Fn(&mut ProviderBinding)>> = vec![
        Box::new(|b| b.profile.id.clear()), Box::new(|b| b.profile.endpoint="http://provider.invalid/chat".into()),
        Box::new(|b| b.profile.endpoint="https://user:secret@provider.invalid/chat".into()),
        Box::new(|b| b.profile.endpoint_identity.clear()), Box::new(|b| b.profile.provider.clear()),
        Box::new(|b| b.profile.model.clear()), Box::new(|b| b.profile.purpose=ModelPurpose::Embedding),
        Box::new(|b| b.profile.credential_ref.clear()), Box::new(|b| b.profile.declared.tool_calls=false),
        Box::new(|b| b.profile.tested.tool_calls=false), Box::new(|b| b.profile_revision.clear()),
        Box::new(|b| b.policy_revision.clear()), Box::new(|b| b.grant_revision.clear()),
        Box::new(|b| b.authorization_owner.clear()), Box::new(|b| b.model_allowed=false),
        Box::new(|b| b.outbound_allowed=false), Box::new(|b| b.budget.quota_proof.clear()),
        Box::new(|b| b.budget.revision.clear()), Box::new(|b| b.budget.remaining_calls=0),
        Box::new(|b| b.budget.remaining_tokens=99), Box::new(|b| b.budget.remaining_micros=49),
    ];
    for mutate in mutations { let host=Host::new(); mutate(host.current.borrow_mut().as_mut().unwrap());
        assert!(prepare(host.clone()).is_err()); assert_eq!(host.reservations.get(),0); }
}
#[test]
fn current_policy_profile_and_budget_are_rechecked_at_final_admission() {
    let mutations: Vec<Box<dyn Fn(&mut ProviderBinding)>>=vec![
        Box::new(|b| b.policy_revision="new".into()), Box::new(|b| b.grant_revision="new".into()),
        Box::new(|b| b.profile.endpoint_identity="new".into()), Box::new(|b| b.budget.revision="new".into()),
        Box::new(|b| b.model_allowed=false), Box::new(|b| b.profile.model="other".into()),
    ];
    for mutate in mutations { let host=Host::new(); let bridge=ServiceProviderBridge::new(host.clone());
        let pending=prepare(host.clone()).unwrap(); mutate(host.current.borrow_mut().as_mut().unwrap());
        assert!(bridge.final_admit(pending).is_err()); assert_eq!(host.commits.get(),0); }
}
#[test]
fn revocation_review_or_ledger_failure_never_admits() {
    for failure in 0..3 { let host=Host::new(); let bridge=ServiceProviderBridge::new(host.clone());
        let pending=prepare(host.clone()).unwrap();
        match failure { 0=>host.available.set(false), 1=>host.review_allowed.set(false), _=>host.journal_allowed.set(false) }
        assert!(bridge.final_admit(pending).is_err()); assert_eq!(host.commits.get(),0);
    }
}
#[test]
fn reservation_race_and_cross_host_prepared_call_are_rejected() {
    let host=Host::new(); host.change_on_reserve.set(true); assert!(prepare(host.clone()).is_err());
    let first=Host::new(); let pending=prepare(first.clone()).unwrap(); let second=Host::new();
    assert!(ServiceProviderBridge::new(second.clone()).final_admit(pending).is_err());
    assert_eq!(first.commits.get(),0); assert_eq!(second.commits.get(),0);
}
#[test]
fn readiness_checks_binding_without_reservation_or_outbound_admission() {
    let host=Host::new(); let bridge=ServiceProviderBridge::new(host.clone());
    assert_eq!(bridge.readiness(&cost()).unwrap().id,"approved-profile");
    assert_eq!(host.reservations.get(),0); assert_eq!(host.commits.get(),0);
    host.available.set(false); assert!(bridge.readiness(&cost()).is_err());
}
#[test]
fn payload_model_must_match_configured_profile_and_payload_is_bounded() {
    let host=Host::new(); let bridge=ServiceProviderBridge::new(host.clone());
    for payload in [br#"{"model":"other","messages":[]}"#.as_slice(), b"not-json", b"{}"] {
        assert!(bridge.prepare("request-1",payload,cost()).is_err());
    }
    assert!(bridge.prepare("request-1",&vec![b'x';65537],cost()).is_err());
    assert_eq!(host.reservations.get(),0);
}
#[test]
fn readiness_never_accepts_ambiguous_or_local_endpoint_forms() {
    for endpoint in ["https://localhost/chat", "https://127.0.0.1/chat", "https://provider.invalid/chat?key=x",
        "https://provider.invalid/chat#part", "https://provider.invalid:0/chat", "https://provider.invalid:bad/chat",
        "https://provider.invalid/\\evil", "https://provider.invalid/white space"] {
        let host=Host::new(); host.current.borrow_mut().as_mut().unwrap().profile.endpoint=endpoint.into();
        assert!(ServiceProviderBridge::new(host.clone()).readiness(&cost()).is_err());
        assert_eq!(host.reservations.get(),0);
    }
}
#[test]
fn wire_capabilities_cannot_exceed_approved_call_requirements() {
    let host=Host::new(); let bridge=ServiceProviderBridge::new(host.clone());
    assert!(bridge.prepare("request-1",br#"{"model":"approved-model","stream":true,"messages":[]}"#,cost()).is_err());
    let mut no_tools=cost(); no_tools.requires_tools=false;
    assert!(bridge.prepare("request-1",br#"{"model":"approved-model","tools":[{}],"messages":[]}"#,no_tools).is_err());
    assert_eq!(host.reservations.get(),0);
}
#[test]
fn oversized_wire_token_caps_are_rejected_before_reservation() {
    for field in ["max_tokens", "max_completion_tokens"] {
        for value in ["101", "18446744073709551615", "18446744073709551616", "0", "-1", "1.5", "\"100\"", "null", "true"] {
            let host=Host::new(); let bridge=ServiceProviderBridge::new(host.clone());
            let payload=format!(r#"{{"model":"approved-model","messages":[],"{field}":{value}}}"#);
            assert!(bridge.prepare("request-1",payload.as_bytes(),cost()).is_err(),"{field}={value}");
            assert_eq!(host.reservations.get(),0,"{field}={value}");
        }
    }
}
#[test]
fn multiple_or_malformed_choices_are_rejected_before_reservation() {
    for value in ["2", "100", "0", "-1", "1.0", "\"1\"", "null", "true"] {
        let host=Host::new(); let bridge=ServiceProviderBridge::new(host.clone());
        let payload=format!(r#"{{"model":"approved-model","messages":[],"n":{value}}}"#);
        assert!(bridge.prepare("request-1",payload.as_bytes(),cost()).is_err(),"n={value}");
        assert_eq!(host.reservations.get(),0,"n={value}");
    }
}
#[test]
fn malformed_stream_or_tools_are_rejected_before_reservation() {
    for (field, values) in [("stream", vec!["\"false\"", "0", "null", "[]", "{}"]),
        ("tools", vec!["\"none\"", "0", "null", "false", "{}"]) ] {
        for value in values {
            let host=Host::new(); let bridge=ServiceProviderBridge::new(host.clone());
            let payload=format!(r#"{{"model":"approved-model","messages":[],"{field}":{value}}}"#);
            assert!(bridge.prepare("request-1",payload.as_bytes(),cost()).is_err(),"{field}={value}");
            assert_eq!(host.reservations.get(),0,"{field}={value}");
        }
    }
}
#[test]
fn unsupported_output_token_dialect_is_rejected_before_reservation() {
    let host=Host::new(); let bridge=ServiceProviderBridge::new(host.clone());
    assert!(bridge.prepare("request-1",br#"{"model":"approved-model","messages":[],"max_output_tokens":1}"#,cost()).is_err());
    assert_eq!(host.reservations.get(),0);
}
#[test]
fn single_choice_and_explicit_token_caps_within_budget_preserve_exact_bytes() {
    for field in ["max_tokens", "max_completion_tokens"] {
        for tokens in [1,100] {
            let host=Host::new(); let bridge=ServiceProviderBridge::new(host.clone());
            let payload=format!(r#"{{"model":"approved-model","messages":[],"n":1,"stream":false,"tools":[],"{field}":{tokens}}}"#);
            let pending=bridge.prepare("request-1",payload.as_bytes(),cost()).unwrap();
            assert_eq!(host.reservations.get(),1);
            assert_eq!(bridge.final_admit(pending).unwrap().payload(),payload.as_bytes());
        }
    }
}
