//! Hand-authored socket-free fixtures. Never open old Agent roots or real accounts.
use muyon_core_agent_lab::{
    agent::{Agent, Limits, State},
    model::{ModelEvent, ModelRequest, Provider, Role},
    policy::{HostFacts, Mode},
    store,
};
use muyon_rust_agent_host_lab::{service_provider::CredentialHandle, *};
use muyon_web_search_lab::{
    deepseek::DeepSeek,
    runtime::{install, SearchRuntime},
    *,
};
use std::{
    cell::RefCell,
    collections::BTreeMap,
    path::PathBuf,
    rc::Rc,
    sync::atomic::{AtomicUsize, Ordering},
};
static SERIAL: AtomicUsize = AtomicUsize::new(0);
fn dir() -> PathBuf {
    let p = std::env::temp_dir().join(format!(
        "muyon-search-fixture-{}-{}",
        std::process::id(),
        SERIAL.fetch_add(1, Ordering::SeqCst)
    ));
    std::fs::create_dir(&p).unwrap();
    p
}
fn config() -> SearchConfig {
    SearchConfig {
        enabled: true,
        id: "search-connection".into(),
        provider: "deepseek-search".into(),
        revision: "c1".into(),
        policy_revision: "p1".into(),
        endpoint: DeepSeek.endpoint().into(),
        endpoint_identity: "deepseek-search-official".into(),
        credential_ref: "fixture-handle-ref".into(),
        credential_generation: 1,
        price: DeepSeek.price("USD").unwrap(),
        max_response_bytes: 32768,
    }
}
fn call_json(call: &SearchCall) -> Json {
    let c = &call.config;
    let i = &call.invocation;
    object([
        (
            "config",
            object([
                ("enabled", Json::Bool(c.enabled)),
                ("id", string(&c.id)),
                ("provider", string(&c.provider)),
                ("revision", string(&c.revision)),
                ("policy_revision", string(&c.policy_revision)),
                ("endpoint", string(&c.endpoint)),
                ("endpoint_identity", string(&c.endpoint_identity)),
                ("credential_ref", string(&c.credential_ref)),
                (
                    "credential_generation",
                    Json::Number(c.credential_generation.to_string()),
                ),
                ("currency", string(&c.price.currency)),
                ("price_micros", Json::Number(c.price.micros.to_string())),
                (
                    "max_response_bytes",
                    Json::Number(c.max_response_bytes.to_string()),
                ),
            ]),
        ),
        (
            "invocation",
            object([
                ("task", string(&i.task)),
                ("attempt", string(&i.attempt)),
                ("scope", string(&i.scope)),
                ("turn", Json::Number(i.turn.to_string())),
                ("call_ref", string(&i.call_ref)),
            ]),
        ),
        ("connection", call.connection.clone()),
        (
            "payload",
            string(String::from_utf8(call.payload.clone()).unwrap()),
        ),
        (
            "max_cost",
            object([
                ("currency", string(&call.max_cost.currency)),
                ("micros", Json::Number(call.max_cost.micros.to_string())),
            ]),
        ),
    ])
}
#[derive(Clone)]
enum Behavior {
    Good,
    Empty,
    Unknown,
    Status(u16),
    Html,
    Wrong,
    Large,
    RejectOutput,
    WriteFail,
    TaskWriteFail,
    LateCancel,
    ChangeAfterReserve,
    RotateAfterReserve,
    NoSend,
    SettlementFail,
}
#[derive(Clone)]
struct Row {
    call: Json,
    status: String,
}
struct Owner {
    dir: PathBuf,
    config: RefCell<Option<SearchConfig>>,
    facts: RefCell<HostFacts>,
    behavior: Behavior,
    rows: RefCell<BTreeMap<String, Row>>,
    sends: RefCell<usize>,
    max_calls: usize,
    limit_micros: u64,
    session_dir: RefCell<Option<PathBuf>>,
    handle_generation: RefCell<u64>,
}
impl Owner {
    fn new(b: Behavior) -> Rc<Self> {
        Rc::new(Self {
            dir: dir(),
            config: RefCell::new(Some(config())),
            facts: RefCell::new(HostFacts {
                mode: Mode::FullAllow,
                high: true,
                tainted: true,
                new_destination: true,
                ..HostFacts::default()
            }),
            behavior: b,
            rows: RefCell::new(BTreeMap::new()),
            sends: RefCell::new(0),
            max_calls: 3,
            limit_micros: 2250,
            session_dir: RefCell::new(None),
            handle_generation: RefCell::new(1),
        })
    }
    fn restore(&self) -> Result<()> {
        let bytes = match std::fs::read(self.dir.join("search-ledger.json")) {
            Ok(v) => v,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound && self.rows.borrow().is_empty() => {
                return Ok(())
            }
            Err(_) => return Err("fixture-ledger-unavailable".into()),
        };
        let value = parse(&bytes)?;
        let m = value.object()?;
        if m["max_calls"].integer()? != self.max_calls as u64
            || m["limit_micros"].integer()? != self.limit_micros
            || m["currency"].string()?
                != self
                    .config
                    .borrow()
                    .as_ref()
                    .ok_or("fixture-config")?
                    .price
                    .currency
        {
            return Err("fixture-budget-config-mismatch".into());
        }
        let mut rows = BTreeMap::new();
        for row in m["rows"].array()? {
            let r = row.object()?;
            let status = r["status"].string()?;
            if !["held", "unknown", "nonempty", "empty", "failed", "released"].contains(&status) {
                return Err("fixture-status".into());
            }
            if rows
                .insert(
                    r["reservation"].string()?.into(),
                    Row {
                        call: r["binding"].clone(),
                        status: status.into(),
                    },
                )
                .is_some()
            {
                return Err("fixture-duplicate-row".into());
            }
        }
        *self.rows.borrow_mut() = rows;
        Ok(())
    }
    fn save(&self) {
        let rows = self.rows.borrow();
        let value = object([
            ("max_calls", Json::Number(self.max_calls.to_string())),
            ("limit_micros", Json::Number(self.limit_micros.to_string())),
            (
                "currency",
                string(&self.config.borrow().as_ref().unwrap().price.currency),
            ),
            (
                "rows",
                Json::Array(
                    rows.iter()
                        .map(|(k, r)| {
                            object([
                                ("reservation", string(k)),
                                ("binding", r.call.clone()),
                                ("status", string(&r.status)),
                            ])
                        })
                        .collect(),
                ),
            ),
        ]);
        store::atomic(&self.dir, "search-ledger.json", &value.encode()).unwrap();
    }
    fn bound_micros(&self) -> u64 {
        self.rows
            .borrow()
            .values()
            .filter(|r| ["held", "unknown", "nonempty"].contains(&r.status.as_str()))
            .map(|r| {
                r.call.object().unwrap()["max_cost"].object().unwrap()["micros"]
                    .integer()
                    .unwrap()
            })
            .sum()
    }
    fn statuses(&self) -> Vec<String> {
        self.rows
            .borrow()
            .values()
            .map(|r| r.status.clone())
            .collect()
    }
}
impl SearchHost for Owner {
    fn current(&self) -> Result<Option<SearchConfig>> {
        Ok(self.config.borrow().clone())
    }
    fn transport_ready(&self, _: &SearchConfig) -> bool {
        true
    }
    fn handle(&self, c: &SearchConfig) -> Result<CredentialHandle> {
        CredentialHandle::with_generation(
            &c.id,
            &c.credential_ref,
            "fixture-opaque-capability",
            *self.handle_generation.borrow(),
        )
    }
    fn review(&self, _: &SearchCall, value: &Json, purpose: &str) -> Result<HostFacts> {
        // Explicit synthetic scan case, not a production scanner claim.
        if (value.encode().contains("FIXTURE_CREDENTIAL")
            || value.encode().contains("OWNER_ONLY_SECRET"))
            || (purpose == "search_result" && matches!(self.behavior, Behavior::RejectOutput))
        {
            return Err("synthetic-credential-hit".into());
        }
        Ok(self.facts.borrow().clone())
    }
    fn reserve(&self, call: &SearchCall, _: &CredentialHandle) -> Result<String> {
        // Reload full new-root fixture ledger, including quota and tombstones.
        self.restore()?;
        let rows = self.rows.borrow();
        let binding = call_json(call);
        if rows.len() >= self.max_calls
            || self
                .bound_micros()
                .checked_add(call.max_cost.micros)
                .is_none_or(|n| n > self.limit_micros)
            || rows.values().any(|r| {
                let old = r.call.object().unwrap()["invocation"].object().unwrap();
                let new = binding.object().unwrap()["invocation"].object().unwrap();
                ["task", "attempt", "call_ref"]
                    .iter()
                    .all(|k| old[*k] == new[*k])
            })
        {
            return Err("fixture-budget-or-replay".into());
        }
        drop(rows);
        let id = format!("held-{}", self.rows.borrow().len());
        self.rows.borrow_mut().insert(
            id.clone(),
            Row {
                call: binding,
                status: "held".into(),
            },
        );
        self.save();
        if matches!(self.behavior, Behavior::ChangeAfterReserve) {
            self.config.borrow_mut().as_mut().unwrap().revision = "c2".into()
        }
        if matches!(self.behavior, Behavior::RotateAfterReserve) {
            *self.handle_generation.borrow_mut() = 2
        }
        Ok(id)
    }
    fn release_held(&self, id: &str) -> Result<()> {
        self.restore()?;
        let mut rows = self.rows.borrow_mut();
        if let Some(r) = rows.get_mut(id) {
            if r.status == "held" {
                r.status = "released".into();
            }
        }
        drop(rows);
        self.save();
        Ok(())
    }
    fn exchange_once(&self, id: &str, call: &SearchCall, h: &CredentialHandle) -> Exchange {
        if self.restore().is_err() {
            return Exchange::NotSent;
        }
        if self.current().unwrap().as_ref() != Some(&call.config)
            || self.handle(&call.config).unwrap() != *h
            || call.max_cost != call.config.price
        {
            return Exchange::NotSent;
        }
        if !self
            .rows
            .borrow()
            .get(id)
            .is_some_and(|r| r.status == "held" && r.call == call_json(call))
        {
            return Exchange::NotSent;
        }
        if matches!(self.behavior, Behavior::NoSend) {
            return Exchange::NotSent;
        }
        self.rows.borrow_mut().get_mut(id).unwrap().status = "unknown".into();
        self.save();
        *self.sends.borrow_mut() += 1;
        if matches!(self.behavior, Behavior::Unknown) {
            return Exchange::Unknown;
        }
        if matches!(self.behavior, Behavior::WriteFail) {
            let d = self.session_dir.borrow().clone().unwrap();
            std::fs::remove_file(d.join("native.db")).unwrap();
            std::fs::create_dir(d.join("native.db")).unwrap();
        }
        if matches!(self.behavior, Behavior::TaskWriteFail) {
            let d = self.session_dir.borrow().clone().unwrap();
            std::fs::remove_file(d.join("task.db")).unwrap();
            std::fs::create_dir(d.join("task.db")).unwrap();
        }
        // Cancellation is signalled by the normal Agent marker, no task reopen.
        if matches!(self.behavior, Behavior::LateCancel) {
            let d = self.session_dir.borrow().clone().unwrap();
            store::atomic(&d, "cancel.request", "CORE_CANCEL_V1\n").unwrap();
        }
        let (status, body) = match self.behavior {
            Behavior::Status(s) => (
                s,
                b"{\"error\":{\"message\":\"FIXTURE_CREDENTIAL\"}}".to_vec(),
            ),
            Behavior::Empty => (200, b"{\"results\":[]}".to_vec()),
            Behavior::Html => (200, b"<html>bad</html>".to_vec()),
            Behavior::Wrong => (200, b"{}".to_vec()),
            Behavior::Large => (200, vec![b' '; 32769]),
            _ => (200, include_bytes!("../../fixtures/nonempty.json").to_vec()),
        };
        Exchange::Http {
            status,
            content_type: if matches!(self.behavior, Behavior::Html) {
                "text/html"
            } else {
                "application/json"
            }
            .into(),
            body,
        }
    }
    fn settle(&self, id: &str, call: &SearchCall, outcome: Settlement) -> Result<()> {
        self.restore()?;
        if matches!(self.behavior, Behavior::SettlementFail) {
            return Err("fixture-settlement-failure".into());
        }
        let mut rows = self.rows.borrow_mut();
        let r = rows.get_mut(id).ok_or("fixture-row-missing")?;
        if r.call != call_json(call) || !["held", "unknown"].contains(&r.status.as_str()) {
            return Err("fixture-settlement-immutable".into());
        }
        r.status = match outcome {
            Settlement::Nonempty => "nonempty",
            Settlement::Empty => "empty",
            Settlement::Failed => "failed",
            Settlement::Unknown => "unknown",
        }
        .into();
        drop(rows);
        self.save();
        Ok(())
    }
}
struct Authority;
impl AuthoritySource for Authority {
    fn snapshot(&self) -> Result<AuthoritySnapshot> {
        Ok(AuthoritySnapshot{read:parse(br#"{"allowed":true,"available":true,"scope_allowed":true,"bindings":["host-web-search"],"revision":"a1","binding_revision":"b1","source_revision":"s1","rule_revision":"r1","scope":"search-scope","refs":[{"module_id":"web_search","type":"connection","key":"search-connection","revision":"c1","schema_version":1}]}"#)?,model_allowed:true,profile:"offline-fixture".into()})
    }
}
struct Review;
impl PurposeReview for Review {
    fn review(&self, v: &Json, _: &Json, _: &str) -> Result<()> {
        if v.encode().contains("FIXTURE_CREDENTIAL") {
            Err("fixture-denied".into())
        } else {
            Ok(())
        }
    }
    fn mask_answer(&self, s: &str) -> Result<String> {
        Ok(s.replace("FIXTURE_CREDENTIAL", "[masked]"))
    }
}
fn setup(
    owner: Rc<Owner>,
    provider: Rc<dyn SearchProvider>,
) -> (SharedSession, SearchRuntime, Agent) {
    let root = dir().join("run");
    let session = NativeSession::create(
        &root,
        &PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").expect("built catalog binary")),
        Rc::new(Authority),
        Rc::new(Review),
        "find synthetic source",
    )
    .unwrap();
    let runtime = install(session.clone(), owner.clone(), provider).unwrap();
    *owner.session_dir.borrow_mut() = Some(root.clone());
    let state = State::runtime(
        "find synthetic source".into(),
        "search-scope".into(),
        Limits::default(),
    )
    .unwrap();
    (session, runtime, Agent { dir: root, state })
}
struct Model {
    count: u64,
    query: String,
    duplicate: bool,
}
impl Default for Model {
    fn default() -> Self {
        Self {
            count: 10,
            query: "synthetic site:example.org".into(),
            duplicate: false,
        }
    }
}
impl Provider for Model {
    fn respond(&mut self, r: &ModelRequest, _: usize) -> Result<ModelEvent> {
        if r.turn == 1 || self.duplicate {
            assert!(r.tools.contains(&"web_search.search".into()));
            Ok(ModelEvent::HostTool {
                call_ref: "call-1".into(),
                name: "web_search.search".into(),
                arguments: object([
                    ("query", string(&self.query)),
                    ("count", Json::Number(self.count.to_string())),
                ]),
            })
        } else {
            let result = r
                .messages
                .iter()
                .find(|m| m.role == Role::Tool)
                .expect("actual Agent received registered tool result");
            let p = parse(result.text.as_bytes())?;
            assert_eq!(p.object()?["tainted"], Json::Bool(true));
            assert_eq!(p.object()?["instruction_authority"], Json::Bool(false));
            Ok(ModelEvent::Answer(
                "Synthetic answer citing https://example.org/source".into(),
            ))
        }
    }
}
#[test]
fn configured_registered_search_reaches_actual_agent_with_sources_and_cost() {
    let owner = Owner::new(Behavior::Good);
    let (session, mut runtime, mut agent) = setup(owner.clone(), Rc::new(DeepSeek));
    runtime.run(&mut agent, &mut Model::default()).unwrap();
    assert_eq!(agent.state.status, "completed");
    assert_eq!(*owner.sends.borrow(), 1);
    assert_eq!(owner.statuses(), ["nonempty"]);
    assert_eq!(session.borrow().store.receipt_count(), 1);
    let history = session.borrow().model_history().encode();
    assert!(history.contains("https://example.org/source"));
    assert!(history.contains("Ignore earlier instructions"));
    assert!(history.contains("nonempty_success"));
    assert!(history.contains("750"));
    let rows = owner.rows.borrow();
    let call = &rows.values().next().unwrap().call;
    assert_eq!(
        call.object().unwrap()["invocation"].object().unwrap()["task"],
        string(&agent.state.task)
    );
    assert_eq!(
        call.object().unwrap()["invocation"].object().unwrap()["attempt"],
        string(&agent.state.attempt)
    );
    assert_eq!(
        call.object().unwrap()["invocation"].object().unwrap()["call_ref"],
        string("call-1")
    );
    assert_eq!(
        call.object().unwrap()["invocation"].object().unwrap()["scope"],
        string("search-scope")
    );
    assert_eq!(
        call.object().unwrap()["payload"],
        string(request("synthetic site:example.org", 10).unwrap().encode())
    );
    assert!(session.borrow().store.facts().encode().contains("true"));
    assert_eq!(
        session.borrow().store.receipts()[0].object().unwrap()["raw"]
            .object()
            .unwrap()["instruction_authority"],
        Json::Bool(false)
    );
}
#[test]
fn empty_success_is_tainted_success_and_zero_cost() {
    let owner = Owner::new(Behavior::Empty);
    let (s, mut r, mut a) = setup(owner.clone(), Rc::new(DeepSeek));
    r.run(&mut a, &mut Model::default()).unwrap();
    assert_eq!(a.state.status, "completed");
    assert_eq!(owner.statuses(), ["empty"]);
    let raw = s.borrow().store.receipts()[0].object().unwrap()["raw"].clone();
    assert_eq!(raw.object().unwrap()["sources"], Json::Array(vec![]));
    assert_eq!(
        raw.object().unwrap()["cost_micros"],
        Json::Number("0".into())
    );
    assert_eq!(raw.object().unwrap()["tainted"], Json::Bool(true));
}
#[test]
fn disabled_unconfigured_bad_endpoint_wrong_currency_or_handle_are_unavailable_without_probe() {
    let o = Owner::new(Behavior::Good);
    *o.config.borrow_mut() = None;
    assert_eq!(
        availability(o.as_ref(), &DeepSeek).unwrap_err(),
        "search_unconfigured"
    );
    for change in 0..5 {
        let mut c = config();
        match change {
            0 => c.enabled = false,
            1 => c.endpoint = "https://other.example/search".into(),
            2 => c.price.currency = "EUR".into(),
            3 => c.price.micros = 1,
            _ => c.credential_generation = 2,
        };
        *o.config.borrow_mut() = Some(c);
        assert!(availability(o.as_ref(), &DeepSeek).is_err());
    }
    assert_eq!(*o.sends.borrow(), 0);
    assert!(o.rows.borrow().is_empty());
}
#[test]
fn auto_confirmation_and_hard_constraints_remain_distinct_from_full_allow_taint() {
    for case in 0..6 {
        let o = Owner::new(Behavior::Good);
        {
            let mut f = o.facts.borrow_mut();
            match case {
                0 => {
                    f.mode = Mode::Auto;
                    f.confirmed = false
                }
                1 => {
                    f.mode = Mode::Auto;
                    f.confirmed = true
                }
                2 => f.hard_ok = false,
                3 => f.revoked = true,
                4 => f.classification_ok = false,
                _ => f.scope_ok = false,
            }
        }
        let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
        r.run(&mut a, &mut Model::default()).unwrap();
        assert_eq!(*o.sends.borrow(), usize::from(case == 1));
        if case == 0 {
            assert_eq!(a.state.reason, "search_confirmation_required")
        } else if case != 1 {
            assert_eq!(a.state.reason, "search_authority_denied")
        }
    }
}
#[test]
fn credential_payload_refused_before_reservation() {
    let o = Owner::new(Behavior::Good);
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(
        &mut a,
        &mut Model {
            query: "FIXTURE_CREDENTIAL".into(),
            ..Model::default()
        },
    )
    .unwrap();
    assert_eq!(*o.sends.borrow(), 0);
    assert!(o.rows.borrow().is_empty());
    assert!(!a.state.encode().contains("synthetic-credential-hit"));
}
#[test]
fn changed_config_or_rotated_handle_releases_only_held_reservation_without_send() {
    for b in [Behavior::ChangeAfterReserve, Behavior::RotateAfterReserve] {
        let o = Owner::new(b);
        let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
        r.run(&mut a, &mut Model::default()).unwrap();
        assert_eq!(*o.sends.borrow(), 0);
        assert_eq!(o.statuses(), ["released"]);
        assert_ne!(a.state.status, "completed");
    }
}
#[test]
fn unknown_and_malformed_responses_never_resend_even_when_driven_again() {
    for b in [
        Behavior::Unknown,
        Behavior::Wrong,
        Behavior::Html,
        Behavior::Large,
        Behavior::RejectOutput,
        Behavior::SettlementFail,
    ] {
        let o = Owner::new(b);
        let (s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
        r.run(&mut a, &mut Model::default()).unwrap();
        assert_eq!(a.state.status, "outcome_unknown");
        assert!(a.state.answer.is_empty());
        r.run(&mut a, &mut Model::default()).unwrap();
        assert_eq!(*o.sends.borrow(), 1);
        assert_eq!(s.borrow().model_history().array().unwrap().len(), 1);
        let saved = std::fs::read_to_string(a.dir.join("task.db")).unwrap();
        assert!(saved.lines().any(|line| line == "status\toutcome_unknown"));
    }
}
#[test]
fn known_errors_and_redirects_have_controlled_messages_without_raw_provider_text() {
    for status in [
        400, 401, 402, 408, 413, 429, 500, 504, 302, 201, 202, 204, 418, 502,
    ] {
        let o = Owner::new(Behavior::Status(status));
        let (s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
        r.run(&mut a, &mut Model::default()).unwrap();
        assert_eq!(*o.sends.borrow(), 1);
        assert_ne!(a.state.status, "completed");
        assert!(!s.borrow().store.receipts()[0]
            .encode()
            .contains("FIXTURE_CREDENTIAL"));
        assert_eq!(
            a.state.status == "outcome_unknown",
            [302, 201, 202, 204, 418, 502].contains(&status)
        );
    }
}
#[test]
fn no_send_failure_and_duplicate_model_call_do_not_multiply_requests() {
    let o = Owner::new(Behavior::NoSend);
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(&mut a, &mut Model::default()).unwrap();
    assert_eq!(*o.sends.borrow(), 0);
    assert_eq!(a.state.reason, "search_not_sent");
    let o = Owner::new(Behavior::Good);
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(
        &mut a,
        &mut Model {
            duplicate: true,
            ..Model::default()
        },
    )
    .unwrap();
    assert_eq!(*o.sends.borrow(), 1);
    assert_ne!(a.state.status, "completed");
}
#[test]
fn post_exchange_cancellation_preserves_unknown_and_no_answer() {
    let o = Owner::new(Behavior::LateCancel);
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(&mut a, &mut Model::default()).unwrap();
    assert_eq!(*o.sends.borrow(), 1);
    assert_eq!(a.state.status, "outcome_unknown");
    assert!(a.state.answer.is_empty());
    r.run(&mut a, &mut Model::default()).unwrap();
    assert_eq!(*o.sends.borrow(), 1);
}
#[test]
fn post_exchange_receipt_write_failure_keeps_owner_evidence_and_unknown() {
    let o = Owner::new(Behavior::WriteFail);
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(&mut a, &mut Model::default()).unwrap();
    assert_eq!(a.state.status, "outcome_unknown");
    assert_eq!(o.statuses(), ["nonempty"]);
    assert!(a.state.answer.is_empty());
    r.run(&mut a, &mut Model::default()).unwrap();
    assert_eq!(*o.sends.borrow(), 1);
}
#[test]
fn post_exchange_task_persistence_failure_is_explicit_and_does_not_retry_transport() {
    let o = Owner::new(Behavior::TaskWriteFail);
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    assert_eq!(
        r.run(&mut a, &mut Model::default()).unwrap_err(),
        "search_state_persistence_failed"
    );
    assert_eq!(a.state.status, "outcome_unknown");
    assert!(a.state.answer.is_empty());
    assert!(r.run(&mut a, &mut Model::default()).is_err());
    assert_eq!(*o.sends.borrow(), 1);
    assert_eq!(o.statuses(), ["nonempty"]);
}
#[test]
fn durable_owner_replay_tombstone_rejects_same_identity_in_another_fresh_agent_session() {
    let o = Owner::new(Behavior::Unknown);
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(&mut a, &mut Model::default()).unwrap();
    let saved = std::fs::read_to_string(o.dir.join("search-ledger.json")).unwrap();
    assert!(saved.contains("unknown"));
    // New root/Agent; no old task.db read/open/recovery or HTTP execution.
    let mut o2 = Owner::new(Behavior::Good);
    Rc::get_mut(&mut o2).unwrap().dir = o.dir.clone();
    let (_s2, mut r2, mut a2) = setup(o2.clone(), Rc::new(DeepSeek));
    a2.state.task = a.state.task.clone();
    a2.state.attempt = a.state.attempt.clone();
    r2.run(&mut a2, &mut Model::default()).unwrap();
    assert_eq!(*o.sends.borrow(), 1);
    assert_ne!(a2.state.status, "completed");
    assert_eq!(o.statuses(), ["unknown"]);
    assert_eq!(*o2.sends.borrow(), 0);
    assert_eq!(o2.statuses(), ["unknown"]);
}
#[test]
fn budget_zero_does_not_send_or_use_any_chat_allowance() {
    let mut o = Owner::new(Behavior::Good);
    Rc::get_mut(&mut o).unwrap().max_calls = 0;
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(&mut a, &mut Model::default()).unwrap();
    assert_eq!(*o.sends.borrow(), 0);
    assert_eq!(a.state.reason, "search_budget_unavailable");
}
struct OtherProvider;
impl SearchProvider for OtherProvider {
    fn id(&self) -> &str {
        "other-search-fixture"
    }
    fn endpoint(&self) -> &str {
        "https://fixture.invalid/independent-search"
    }
    fn price(&self, currency: &str) -> Result<Money> {
        if currency != "USD" {
            return Err("fixture-price".into());
        }
        Ok(Money {
            currency: "USD".into(),
            micros: 2,
        })
    }
    fn encode(&self, q: &str, n: u64) -> Result<Json> {
        request(q, n)
    }
    fn decode(&self, b: &[u8], n: u64) -> Result<Vec<Json>> {
        DeepSeek.decode(b, n)
    }
}
#[test]
fn generic_registration_and_agent_entry_do_not_select_a_specific_provider() {
    let o = Owner::new(Behavior::Good);
    {
        let mut c = o.config.borrow_mut();
        let c = c.as_mut().unwrap();
        c.provider = OtherProvider.id().into();
        c.endpoint = OtherProvider.endpoint().into();
        c.price = OtherProvider.price("USD").unwrap();
    }
    let (s, mut r, mut a) = setup(o.clone(), Rc::new(OtherProvider));
    r.run(&mut a, &mut Model::default()).unwrap();
    assert_eq!(a.state.status, "completed");
    assert_eq!(*o.sends.borrow(), 1);
    assert!(s
        .borrow()
        .model_history()
        .encode()
        .contains("other-search-fixture"));
    assert_eq!(
        o.rows
            .borrow()
            .values()
            .next()
            .unwrap()
            .call
            .object()
            .unwrap()["max_cost"]
            .object()
            .unwrap()["micros"],
        Json::Number("2".into())
    );
}
struct RevokeOnAnswer {
    owner: Rc<Owner>,
    model: Model,
}
impl Provider for RevokeOnAnswer {
    fn respond(&mut self, r: &ModelRequest, p: usize) -> Result<ModelEvent> {
        let event = self.model.respond(r, p)?;
        if r.turn == 2 {
            self.owner.facts.borrow_mut().revoked = true;
        }
        Ok(event)
    }
}
#[test]
fn revocation_before_answer_disclosure_refuses_tainted_derived_output() {
    let o = Owner::new(Behavior::Good);
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(
        &mut a,
        &mut RevokeOnAnswer {
            owner: o.clone(),
            model: Model::default(),
        },
    )
    .unwrap();
    assert_ne!(a.state.status, "completed");
    assert!(a.state.answer.is_empty());
    assert_eq!(*o.sends.borrow(), 1);
}
struct UninstalledOwner;
impl SearchHost for UninstalledOwner {
    fn current(&self) -> Result<Option<SearchConfig>> {
        Ok(Some(config()))
    }
}
#[test]
fn mere_configuration_does_not_claim_an_installed_transport_or_probe_a_service() {
    assert_eq!(
        availability(&UninstalledOwner, &DeepSeek).unwrap_err(),
        "search_transport_unavailable"
    );
}
fn reconstructed(o: &Rc<Owner>, behavior: Behavior) -> Rc<Owner> {
    let mut next = Owner::new(behavior);
    let n = Rc::get_mut(&mut next).unwrap();
    n.dir = o.dir.clone();
    n.max_calls = o.max_calls;
    n.limit_micros = o.limit_micros;
    *n.config.borrow_mut() = o.config.borrow().clone();
    next
}
#[test]
fn unknown_then_reconstructed_owner_new_call_preserves_old_tombstone_and_total_quota() {
    let o = Owner::new(Behavior::Unknown);
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(&mut a, &mut Model::default()).unwrap();
    let o2 = reconstructed(&o, Behavior::Good);
    let (_s2, mut r2, mut a2) = setup(o2.clone(), Rc::new(DeepSeek));
    r2.run(&mut a2, &mut Model::default()).unwrap();
    assert_eq!(*o2.sends.borrow(), 1);
    assert_eq!(o2.bound_micros(), 1500);
    let o3 = reconstructed(&o2, Behavior::Good);
    let (_s3, mut r3, mut a3) = setup(o3.clone(), Rc::new(DeepSeek));
    a3.state.task = a.state.task.clone();
    a3.state.attempt = a.state.attempt.clone();
    r3.run(&mut a3, &mut Model::default()).unwrap();
    assert_eq!(*o3.sends.borrow(), 0);
    assert_eq!(o3.statuses(), ["unknown", "nonempty"]);
    let (_s4, mut r4, mut a4) = setup(o3.clone(), Rc::new(DeepSeek));
    r4.run(&mut a4, &mut Model::default()).unwrap();
    assert_eq!(*o3.sends.borrow(), 1);
    assert_eq!(o3.bound_micros(), 2250);
    let o4 = reconstructed(&o3, Behavior::Good);
    let (_s5, mut r5, mut a5) = setup(o4.clone(), Rc::new(DeepSeek));
    r5.run(&mut a5, &mut Model::default()).unwrap();
    assert_eq!(*o4.sends.borrow(), 0);
    assert_eq!(a5.state.reason, "search_budget_unavailable");
    assert_eq!(o4.rows.borrow().len(), 3);
}
#[test]
fn unknown_holds_spend_and_empty_releases_spend_but_completed_spend_cannot_be_refunded() {
    let mut o = Owner::new(Behavior::Unknown);
    Rc::get_mut(&mut o).unwrap().limit_micros = 750;
    let (_s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(&mut a, &mut Model::default()).unwrap();
    assert_eq!(o.bound_micros(), 750);
    let o2 = reconstructed(&o, Behavior::Good);
    let (_s2, mut r2, mut a2) = setup(o2.clone(), Rc::new(DeepSeek));
    r2.run(&mut a2, &mut Model::default()).unwrap();
    assert_eq!(*o2.sends.borrow(), 0);
    assert_eq!(o2.bound_micros(), 750);
    let mut empty = Owner::new(Behavior::Empty);
    Rc::get_mut(&mut empty).unwrap().limit_micros = 750;
    let (_s3, mut r3, mut a3) = setup(empty.clone(), Rc::new(DeepSeek));
    r3.run(&mut a3, &mut Model::default()).unwrap();
    assert_eq!(empty.bound_micros(), 0);
    let paid = reconstructed(&empty, Behavior::Good);
    let (_s4, mut r4, mut a4) = setup(paid.clone(), Rc::new(DeepSeek));
    r4.run(&mut a4, &mut Model::default()).unwrap();
    assert_eq!(*paid.sends.borrow(), 1);
    assert_eq!(paid.bound_micros(), 750);
    assert_eq!(paid.statuses(), ["empty", "nonempty"]);
    paid.release_held("held-1").unwrap();
    assert_eq!(paid.bound_micros(), 750);
    assert_eq!(paid.statuses(), ["empty", "nonempty"]);
    let last = reconstructed(&paid, Behavior::Good);
    let (_s5, mut r5, mut a5) = setup(last.clone(), Rc::new(DeepSeek));
    r5.run(&mut a5, &mut Model::default()).unwrap();
    assert_eq!(*last.sends.borrow(), 0);
    assert_eq!(last.bound_micros(), 750);
}
#[test]
fn owner_only_credential_refusal_precedes_native_argument_persistence() {
    let o = Owner::new(Behavior::Good);
    let (s, mut r, mut a) = setup(o.clone(), Rc::new(DeepSeek));
    r.run(
        &mut a,
        &mut Model {
            query: "OWNER_ONLY_SECRET".into(),
            ..Model::default()
        },
    )
    .unwrap();
    assert_eq!(*o.sends.borrow(), 0);
    assert!(o.rows.borrow().is_empty());
    assert!(
        !std::fs::read_to_string(a.dir.join("native.db"))
            .unwrap()
            .contains("OWNER_ONLY_SECRET"),
        "query must be reviewed by SearchHost before durable args"
    );
    assert_eq!(s.borrow().store.receipt_count(), 0);
    assert!(!s
        .borrow()
        .model_history()
        .encode()
        .contains("OWNER_ONLY_SECRET"));
    assert!(!std::fs::read_to_string(a.dir.join("task.db"))
        .unwrap()
        .contains("OWNER_ONLY_SECRET"));
}
