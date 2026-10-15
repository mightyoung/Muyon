use muyon_core_agent_lab::{
    agent::{Agent, Hooks, Limits, State},
    model::{ModelEvent, ModelRequest, Provider},
    Result,
};
use muyon_plugin_contract_lab::{parse, Json};
use muyon_rust_agent_host_lab::*;
use std::{
    cell::RefCell,
    path::PathBuf,
    rc::Rc,
    sync::atomic::{AtomicUsize, Ordering},
};
fn json(s: &str) -> Json {
    parse(s.as_bytes()).unwrap()
}
struct Authority(RefCell<AuthoritySnapshot>);
impl AuthoritySource for Authority {
    fn snapshot(&self) -> Result<AuthoritySnapshot> {
        Ok(self.0.borrow().clone())
    }
}
struct Review;
impl PurposeReview for Review {
    fn review(&self, v: &Json, _facts: &Json, purpose: &str) -> Result<()> {
        if !matches!(purpose, "model_context" | "model_payload")
            || v.encode().contains("BORROWER_PRIVATE")
        {
            Err("actual_value_denied".into())
        } else {
            Ok(())
        }
    }
    fn mask_answer(&self, text: &str) -> Result<String> {
        Ok(text.replace("BORROWER_PRIVATE", "[redacted]"))
    }
}
static SERIAL: AtomicUsize = AtomicUsize::new(0);
fn directory() -> PathBuf {
    std::env::temp_dir().join(format!(
        "muyon-native-{}-{}",
        std::process::id(),
        SERIAL.fetch_add(1, Ordering::SeqCst)
    ))
}
fn authority() -> Rc<Authority> {
    Rc::new(Authority(RefCell::new(AuthoritySnapshot {
        read: json(
            r#"{"allowed":true,"available":true,"scope_allowed":true,"bindings":["host-equipment-read"],"revision":"a1","binding_revision":"b1","source_revision":"s1","rule_revision":"r1","scope":"selected-e1","refs":[{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"1","schema_version":1},{"module_id":"equipment_loan","type":"loan","key":"l1","revision":"1","schema_version":1}]}"#,
        ),
        model_allowed: true,
        profile: "offline-fixture".into(),
    })))
}
fn session(a: Rc<dyn AuthoritySource>) -> SharedSession {
    let plugin =
        PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").expect("actual child binary"));
    let s = NativeSession::create(
        &directory(),
        &plugin,
        a,
        Rc::new(Review),
        "inspect selected equipment",
    )
    .unwrap();
    let dir = s.borrow().store.dir.clone();
    let mut raw = projection();
    put(
        &mut raw,
        "borrower",
        Json::String("BORROWER_PRIVATE".into()),
    );
    muyon_core_agent_lab::store::atomic(&dir, "synthetic-data.db", &raw.encode()).unwrap();
    let handler = read_registry::PhysicalReadHandler::new(
        &dir,
        "synthetic-data.db",
        "equipment_key",
        "e1",
        vec!["equipment".into(), "label".into(), "loans".into()],
        Some(("include_loans".into(), "loans".into())),
    )
    .unwrap()
    .bind_record(equipment_scope()[0].clone(), None)
    .unwrap();
    s.borrow_mut()
        .register(Enrollment {
            bundle: json(include_str!(
                "../../../plugin-contract-lab/fixtures/equipment_loan.json"
            )),
            operation: "equipment_loan/inspect_equipment@1".into(),
            tool_id: "equipment_loan.inspect_equipment".into(),
            binding_id: "host-equipment-read".into(),
            scope_refs: equipment_scope(),
            handler: Box::new(handler),
        })
        .unwrap();
    s
}
fn projection() -> Json {
    json(
        r#"{"equipment":{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"1","schema_version":1},"label":"synthetic drill","loans":[{"module_id":"equipment_loan","type":"loan","key":"l1","revision":"1","schema_version":1}]}"#,
    )
}
fn session_handler(a: Rc<dyn AuthoritySource>, handler: Box<dyn ReadHandler>) -> SharedSession {
    let plugin = PathBuf::from(
        std::env::var("MUYON_PLUGIN_CONTRACT_BIN")
            .expect("CI must provide actual absolute plugin child"),
    );
    let s = NativeSession::create(
        &directory(),
        &plugin,
        a,
        Rc::new(Review),
        "inspect selected equipment",
    )
    .unwrap();
    s.borrow_mut()
        .register(Enrollment {
            bundle: json(include_str!(
                "../../../plugin-contract-lab/fixtures/equipment_loan.json"
            )),
            operation: "equipment_loan/inspect_equipment@1".into(),
            tool_id: "equipment_loan.inspect_equipment".into(),
            binding_id: "host-equipment-read".into(),
            scope_refs: equipment_scope(),
            handler,
        })
        .unwrap();
    s
}
struct CallProvider;
impl Provider for CallProvider {
    fn respond(&mut self, _r: &ModelRequest, position: usize) -> Result<ModelEvent> {
        if position == 0 {
            Ok(ModelEvent::HostTool {
                call_ref: "call1".into(),
                name: "equipment_loan.inspect_equipment".into(),
                arguments: json(r#"{"equipment_key":"e1","include_loans":true}"#),
            })
        } else {
            Ok(ModelEvent::Answer("synthetic completed".into()))
        }
    }
}
fn agent(s: &SharedSession) -> Agent {
    Agent {
        dir: s.borrow().store.dir.clone(),
        state: State::runtime(
            "inspect selected equipment".into(),
            "selected-e1".into(),
            Limits::default(),
        )
        .unwrap(),
    }
}
#[test]
fn native_host_executes_registered_read() {
    let s = session(authority());
    assert_eq!(s.borrow().handler_calls, 0, "registration is not execution");
    assert_eq!(
        field(&s.borrow_mut().discover().unwrap(), "operations")
            .unwrap()
            .array()
            .unwrap()
            .len(),
        1,
        "real child must admit the catalog"
    );
    let mut a = agent(&s);
    a.run_with_runtime_ports(
        &mut CallProvider,
        &mut RuntimePorts { session: s.clone() },
        &Hooks::default(),
    )
    .unwrap();
    assert_eq!(
        s.borrow().dispatch_attempts,
        1,
        "real common drive must reach native dispatch before interpreting RED"
    );
    assert_eq!(
        s.borrow().handler_calls,
        1,
        "NATIVE_READ_RED: native host must execute exactly one admitted registered read"
    );
    assert_eq!(a.state.status, "completed");
    assert_eq!(s.borrow().store.receipt_count(), 1);
}
fn run(s: &SharedSession) -> Agent {
    let mut a = agent(s);
    a.run_with_runtime_ports(
        &mut CallProvider,
        &mut RuntimePorts { session: s.clone() },
        &Hooks::default(),
    )
    .unwrap();
    a
}
fn put(j: &mut Json, k: &str, v: Json) {
    if let Json::Object(m) = j {
        m.insert(k.into(), v);
    }
}
#[test]
fn unauthorized_read_executes_zero() {
    let auth = authority();
    put(&mut auth.0.borrow_mut().read, "allowed", Json::Bool(false));
    let s = session(auth);
    assert!(field(&s.borrow_mut().discover().unwrap(), "operations")
        .unwrap()
        .array()
        .unwrap()
        .is_empty());
    let a = run(&s);
    assert_ne!(a.state.status, "completed");
    assert_eq!(s.borrow().handler_calls, 0);
    assert_eq!(s.borrow().store.receipt_count(), 0);
}
#[test]
fn wrong_projection_preserves_raw_receipt() {
    let s = session_handler(
        authority(),
        Box::new(|_: &Json| {
            Ok(RawRead {
                raw: json(r#"{"borrower":"BORROWER_PRIVATE"}"#),
                projection: json(r#"{"label":17}"#),
            })
        }),
    );
    let a = run(&s);
    assert_ne!(a.state.status, "completed");
    assert_eq!(s.borrow().handler_calls, 1);
    assert_eq!(s.borrow().store.receipt_count(), 1);
    assert!(s.borrow().store.receipts()[0]
        .encode()
        .contains("BORROWER_PRIVATE"));
    assert_eq!(s.borrow().model_history().array().unwrap().len(), 1);
}
#[test]
fn handler_failure_keeps_source_facts() {
    let s = session_handler(
        authority(),
        Box::new(|_: &Json| Err("BORROWER_PRIVATE".into())),
    );
    let a = run(&s);
    assert_ne!(a.state.status, "completed");
    assert_eq!(s.borrow().handler_calls, 1);
    assert_eq!(
        field(s.borrow().store.facts(), "unknown_source").unwrap(),
        &Json::Bool(true)
    );
    assert_eq!(s.borrow().store.receipt_count(), 1);
    assert!(!s
        .borrow()
        .model_history()
        .encode()
        .contains("BORROWER_PRIVATE"));
}
#[test]
fn receipt_time_revoke_exports_no_projection() {
    let auth = authority();
    let changed = auth.clone();
    let s = session_handler(
        auth,
        Box::new(move |_: &Json| {
            put(
                &mut changed.0.borrow_mut().read,
                "revision",
                Json::String("a2".into()),
            );
            Ok(RawRead {
                raw: json(r#"{"raw":"private"}"#),
                projection: projection(),
            })
        }),
    );
    let a = run(&s);
    assert_ne!(a.state.status, "completed");
    assert_eq!(s.borrow().handler_calls, 1);
    assert_eq!(s.borrow().store.receipt_count(), 1);
    assert_eq!(s.borrow().model_history().array().unwrap().len(), 1);
}
#[test]
fn actual_value_review_denies_sensitive_projection() {
    let mut p = projection();
    put(&mut p, "label", Json::String("BORROWER_PRIVATE".into()));
    let s = session_handler(
        authority(),
        Box::new(move |_: &Json| {
            Ok(RawRead {
                raw: p.clone(),
                projection: p.clone(),
            })
        }),
    );
    let a = run(&s);
    assert_ne!(a.state.status, "completed");
    assert_eq!(s.borrow().handler_calls, 1);
    assert_eq!(s.borrow().model_history().array().unwrap().len(), 1);
}
#[test]
fn cancel_closes_owned_child_and_executes_zero() {
    let s = session(authority());
    let pid = s.borrow().child_pid();
    s.borrow_mut().cancel();
    assert!(
        !PathBuf::from(format!("/proc/{pid}")).exists(),
        "owned child must be reaped"
    );
    let a = run(&s);
    assert_ne!(a.state.status, "completed");
    assert_eq!(s.borrow().handler_calls, 0);
    assert!(s.borrow_mut().discover().is_err());
}
#[test]
fn restart_retains_raw_evidence_without_live_export_authority() {
    let s = session(authority());
    let _ = run(&s);
    let dir = s.borrow().store.dir.clone();
    assert_eq!(s.borrow().store.receipt_count(), 1);
    drop(s);
    let store = store::NativeStore::open(&dir).unwrap();
    assert_eq!(store.receipt_count(), 1);
    assert_eq!(
        field(store.facts(), "unknown_source").unwrap(),
        &Json::Bool(true)
    );
    assert!(!dir.join("effects.db").exists()); /* No Session restore API: a receipt never restores a live projection/grant. */
}
use muyon_core_agent_lab::model::ProviderControl;
use muyon_rust_agent_host_lab::model_gateway::{ModelGateway, OfflineEndpoint};
struct Endpoint {
    responses: Vec<Vec<u8>>,
    sent: Rc<RefCell<Vec<Vec<u8>>>>,
}
impl OfflineEndpoint for Endpoint {
    fn exchange(&mut self, body: &[u8], control: &mut dyn ProviderControl) -> Result<Vec<u8>> {
        control.poll()?;
        self.sent.borrow_mut().push(body.to_vec());
        if self.responses.is_empty() {
            Err("offline_exhausted".into())
        } else {
            Ok(self.responses.remove(0))
        }
    }
}
fn call_sse() -> Vec<u8> {
    br#"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call1","type":"function","function":{"name":"registered_0","arguments":"{\"equipment_key\":\"e1\",\"include_loans\":true}"}}]},"finish_reason":"tool_calls"}]}

data: [DONE]

"#.to_vec()
}
fn answer_sse() -> Vec<u8> {
    b"data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"synthetic complete\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".to_vec()
}
fn gateway(s: &SharedSession) -> (ModelGateway, Rc<RefCell<Vec<Vec<u8>>>>) {
    let sent = Rc::new(RefCell::new(Vec::new()));
    (
        ModelGateway::new(
            s.clone(),
            Box::new(Endpoint {
                responses: vec![call_sse(), answer_sse()],
                sent: sent.clone(),
            }),
        ),
        sent,
    )
}
#[test]
fn two_turn_model_bytes_contain_only_validated_projection() {
    let s = session(authority());
    let (mut provider, sent) = gateway(&s);
    let mut a = agent(&s);
    a.run_with_runtime_ports(
        &mut provider,
        &mut RuntimePorts { session: s.clone() },
        &Hooks::default(),
    )
    .unwrap();
    assert_eq!(a.state.status, "completed");
    assert_eq!(sent.borrow().len(), 2);
    let body = String::from_utf8(sent.borrow()[1].clone()).unwrap();
    assert!(body.contains("synthetic drill"));
    assert!(!body.contains("BORROWER_PRIVATE"));
    assert_eq!(s.borrow().handler_calls, 1);
    assert_eq!(s.borrow().store.receipt_count(), 1);
}
#[test]
fn historical_projection_revoke_blocks_actual_second_send() {
    let auth = authority();
    let s = session(auth.clone());
    let a = run(&s);
    assert_eq!(a.state.status, "completed");
    put(
        &mut auth.0.borrow_mut().read,
        "source_revision",
        Json::String("s2".into()),
    );
    let (mut provider, sent) = gateway(&s);
    let mut fresh = agent(&s);
    fresh
        .run_with_runtime_ports(
            &mut provider,
            &mut RuntimePorts { session: s.clone() },
            &Hooks::default(),
        )
        .unwrap();
    assert!(sent.borrow().is_empty());
    assert_eq!(s.borrow().handler_calls, 1);
    assert_ne!(fresh.state.status, "completed");
}
#[test]
fn ledger_failure_sends_zero_bytes() {
    let s = session(authority());
    std::fs::create_dir(s.borrow().store.dir.join("outbound.db")).unwrap();
    let (mut provider, sent) = gateway(&s);
    let mut a = agent(&s);
    a.run_with_runtime_ports(
        &mut provider,
        &mut RuntimePorts { session: s.clone() },
        &Hooks::default(),
    )
    .unwrap();
    assert_ne!(a.state.status, "completed");
    assert!(sent.borrow().is_empty());
    assert_eq!(s.borrow().handler_calls, 0);
}
#[test]
fn malformed_oversize_eof_child_frames_invalidate_session() {
    for (mode, code) in [
        ("invalid", "plugin_invalid_json"),
        ("oversize", "plugin_frame_limit"),
        ("eof", "plugin_eof"),
    ] {
        let mut process = plugin_process::PluginProcess::spawn_with_args(
            std::path::Path::new(env!("CARGO_BIN_EXE_native-protocol-fixture")),
            &[mode],
            std::time::Duration::from_secs(1),
        )
        .unwrap();
        let pid = process.pid();
        assert_eq!(
            process
                .request(json(r#"{"protocol_version":1,"command":"inspect"}"#))
                .unwrap_err(),
            code
        );
        assert_eq!(process.request(Json::Null).unwrap_err(), "plugin_closed");
        assert!(!PathBuf::from(format!("/proc/{pid}")).exists());
    }
}
#[test]
fn silent_child_deadline_is_bounded_and_reaped() {
    let mut process = plugin_process::PluginProcess::spawn_with_args(
        std::path::Path::new(env!("CARGO_BIN_EXE_native-protocol-fixture")),
        &["silent"],
        std::time::Duration::from_millis(100),
    )
    .unwrap();
    let pid = process.pid();
    let started = std::time::Instant::now();
    assert_eq!(
        process
            .request(json(r#"{"protocol_version":1,"command":"inspect"}"#))
            .unwrap_err(),
        "plugin_deadline"
    );
    assert!(started.elapsed() < std::time::Duration::from_secs(3));
    assert!(!PathBuf::from(format!("/proc/{pid}")).exists());
}
struct RepeatProvider;
impl Provider for RepeatProvider {
    fn respond(&mut self, r: &ModelRequest, _p: usize) -> Result<ModelEvent> {
        CallProvider.respond(r, 0)
    }
}
#[test]
fn duplicate_model_call_never_reexecutes_handler() {
    let s = session(authority());
    let mut a = agent(&s);
    a.run_with_runtime_ports(
        &mut RepeatProvider,
        &mut RuntimePorts { session: s.clone() },
        &Hooks::default(),
    )
    .unwrap();
    assert_eq!(s.borrow().handler_calls, 1);
    assert_eq!(s.borrow().store.receipt_count(), 1);
    assert_ne!(a.state.status, "completed");
}
#[test]
fn wrong_reference_version_retains_only_original_receipt() {
    let mut p = projection();
    let mut r = field(&p, "equipment").unwrap().clone();
    put(&mut r, "schema_version", Json::Number("2".into()));
    put(&mut p, "equipment", r);
    let s = session_handler(
        authority(),
        Box::new(move |_: &Json| {
            Ok(RawRead {
                raw: p.clone(),
                projection: p.clone(),
            })
        }),
    );
    let a = run(&s);
    assert_ne!(a.state.status, "completed");
    assert_eq!(s.borrow().handler_calls, 1);
    assert_eq!(s.borrow().store.receipt_count(), 1);
    assert_eq!(s.borrow().model_history().array().unwrap().len(), 1);
}
struct RevokeReview {
    authority: Rc<Authority>,
}
impl PurposeReview for RevokeReview {
    fn review(&self, value: &Json, _facts: &Json, purpose: &str) -> Result<()> {
        if purpose == "model_payload" && value.encode().contains("synthetic drill") {
            self.authority.0.borrow_mut().model_allowed = false;
        }
        Review.review(value, _facts, purpose)
    }
    fn mask_answer(&self, text: &str) -> Result<String> {
        Review.mask_answer(text)
    }
}
#[test]
fn final_payload_policy_revoke_blocks_second_endpoint_admission() {
    let auth = authority();
    let plugin = PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").unwrap());
    let s = NativeSession::create(
        &directory(),
        &plugin,
        auth.clone(),
        Rc::new(RevokeReview { authority: auth }),
        "inspect selected equipment",
    )
    .unwrap();
    s.borrow_mut()
        .register(Enrollment {
            bundle: json(include_str!(
                "../../../plugin-contract-lab/fixtures/equipment_loan.json"
            )),
            operation: "equipment_loan/inspect_equipment@1".into(),
            tool_id: "equipment_loan.inspect_equipment".into(),
            binding_id: "host-equipment-read".into(),
            scope_refs: equipment_scope(),
            handler: Box::new(|_: &Json| {
                Ok(RawRead {
                    raw: projection(),
                    projection: projection(),
                })
            }),
        })
        .unwrap();
    let (mut provider, sent) = gateway(&s);
    let mut a = agent(&s);
    a.run_with_runtime_ports(
        &mut provider,
        &mut RuntimePorts { session: s.clone() },
        &Hooks::default(),
    )
    .unwrap();
    assert_eq!(s.borrow().handler_calls, 1);
    assert_eq!(s.borrow().store.receipt_count(), 1);
    assert_eq!(
        sent.borrow().len(),
        1,
        "post-policy revoke must block projection bytes"
    );
    assert_ne!(a.state.status, "completed");
}
struct RestoreAuthorityProvider {
    authority: Rc<Authority>,
}
impl Provider for RestoreAuthorityProvider {
    fn respond(&mut self, r: &ModelRequest, _position: usize) -> Result<ModelEvent> {
        assert!(
            r.tools.is_empty(),
            "negative precondition: no tool advertised this turn"
        );
        put(
            &mut self.authority.0.borrow_mut().read,
            "allowed",
            Json::Bool(true),
        );
        CallProvider.respond(r, 0)
    }
}
#[test]
fn catalog_known_but_unadvertised_call_executes_zero() {
    let auth = authority();
    put(&mut auth.0.borrow_mut().read, "allowed", Json::Bool(false));
    let s = session(auth.clone());
    let mut a = agent(&s);
    a.run_with_runtime_ports(
        &mut RestoreAuthorityProvider {
            authority: auth.clone(),
        },
        &mut RuntimePorts { session: s.clone() },
        &Hooks::default(),
    )
    .unwrap();
    assert_eq!(
        field(&auth.0.borrow().read, "allowed").unwrap(),
        &Json::Bool(true),
        "single cause: live authority is restored before dispatch"
    );
    assert_eq!(a.state.reason, "tool_not_advertised");
    assert_eq!(s.borrow().handler_calls, 0);
    assert_eq!(s.borrow().store.receipt_count(), 0);
}
fn structured_call_sse(args: &Json) -> Vec<u8> {
    let event = muyon_plugin_contract_lab::object([(
        "choices",
        Json::Array(vec![muyon_plugin_contract_lab::object([
            ("index", Json::Number("0".into())),
            (
                "delta",
                muyon_plugin_contract_lab::object([(
                    "tool_calls",
                    Json::Array(vec![muyon_plugin_contract_lab::object([
                        ("index", Json::Number("0".into())),
                        ("id", Json::String("call1".into())),
                        ("type", Json::String("function".into())),
                        (
                            "function",
                            muyon_plugin_contract_lab::object([
                                ("name", Json::String("registered_0".into())),
                                ("arguments", Json::String(args.encode())),
                            ]),
                        ),
                    ])]),
                )]),
            ),
            ("finish_reason", Json::String("tool_calls".into())),
        ])]),
    )]);
    format!("data: {}\n\ndata: [DONE]\n\n", event.encode()).into_bytes()
}
#[test]
fn all_native_mappings_use_physical_store_and_same_two_turn_runtime() {
    use muyon_plugin_contract_lab::mappings::{declaration, renamed_equipment, MappingKind};
    let variants = [
        (declaration(MappingKind::Research).unwrap(), "project", "p1"),
        (declaration(MappingKind::Inquiry).unwrap(), "supplier", "s1"),
        (
            declaration(MappingKind::Equipment).unwrap(),
            "equipment",
            "e1",
        ),
        (renamed_equipment(0x7631).unwrap(), "asset", "e1"),
    ];
    for (d, data_type, key) in variants {
        let module = field(&d.bundle, "module_id")
            .unwrap()
            .string()
            .unwrap()
            .to_string();
        let reference = json(&format!(
            r#"{{"module_id":"{module}","type":"{data_type}","key":"{key}","revision":"1","schema_version":1}}"#
        ));
        let native_key = if matches!(data_type, "project" | "supplier") {
            "id"
        } else {
            "equipment_key"
        };
        let args = if native_key == "id" {
            muyon_plugin_contract_lab::object([
                ("type", Json::String(data_type.into())),
                ("id", Json::String(key.into())),
            ])
        } else {
            json(r#"{"equipment_key":"e1","include_loans":false}"#)
        };
        let p = if native_key == "id" {
            muyon_plugin_contract_lab::object([(
                "objects",
                muyon_plugin_contract_lab::object([(
                    data_type,
                    Json::Array(vec![reference.clone()]),
                )]),
            )])
        } else {
            muyon_plugin_contract_lab::object([
                (data_type, reference.clone()),
                ("label", Json::String("synthetic mapped value".into())),
                ("loans", Json::Array(Vec::new())),
            ])
        };
        let auth = authority();
        put(
            &mut auth.0.borrow_mut().read,
            "bindings",
            Json::Array(vec![Json::String(d.binding_id.clone())]),
        );
        put(
            &mut auth.0.borrow_mut().read,
            "refs",
            Json::Array(vec![reference.clone()]),
        );
        let plugin = PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").unwrap());
        let s = NativeSession::create(
            &directory(),
            &plugin,
            auth,
            Rc::new(Review),
            "read selected record",
        )
        .unwrap();
        let dir = s.borrow().store.dir.clone();
        let mut raw = p.clone();
        put(
            &mut raw,
            "private_value",
            Json::String("BORROWER_PRIVATE".into()),
        );
        muyon_core_agent_lab::store::atomic(&dir, "mapped-data.db", &raw.encode()).unwrap();
        let fields = p.object().unwrap().keys().cloned().collect();
        let mut handler = read_registry::PhysicalReadHandler::new(
            &dir,
            "mapped-data.db",
            native_key,
            key,
            fields,
            None,
        )
        .unwrap();
        if native_key == "id" {
            handler = handler
                .require_argument("type", Json::String(data_type.into()))
                .unwrap();
        }
        handler = handler
            .bind_record(
                reference.clone(),
                if native_key == "id" {
                    Some("type".into())
                } else {
                    None
                },
            )
            .unwrap();
        s.borrow_mut()
            .register(Enrollment {
                bundle: d.bundle,
                operation: d.operation,
                tool_id: d.tool_id.clone(),
                binding_id: d.binding_id,
                scope_refs: vec![reference.clone()],
                handler: Box::new(handler),
            })
            .unwrap();
        assert_eq!(s.borrow().handler_calls, 0);
        let sent = Rc::new(RefCell::new(Vec::new()));
        let mut provider = ModelGateway::new(
            s.clone(),
            Box::new(Endpoint {
                responses: vec![structured_call_sse(&args), answer_sse()],
                sent: sent.clone(),
            }),
        );
        let mut a = agent(&s);
        a.run_with_runtime_ports(
            &mut provider,
            &mut RuntimePorts { session: s.clone() },
            &Hooks::default(),
        )
        .unwrap();
        assert_eq!(a.state.status, "completed", "{}", d.tool_id);
        assert_eq!(sent.borrow().len(), 2);
        assert_eq!(s.borrow().handler_calls, 1);
        assert_eq!(s.borrow().store.receipt_count(), 1);
        let final_body = String::from_utf8(sent.borrow()[1].clone()).unwrap();
        assert!(final_body.contains(&module));
        assert!(!final_body.contains("BORROWER_PRIVATE"));
        assert!(s.borrow().store.receipts()[0]
            .encode()
            .contains("BORROWER_PRIVATE"));
        eprintln!(
            "NATIVE_MAPPING_TWO_TURNS {} handler=1 receipt=1 sends=2",
            d.tool_id
        );
    }
}
#[test]
fn physical_handler_rejects_same_id_wrong_business_type() {
    let dir = directory();
    muyon_core_agent_lab::store::create_dir(&dir).unwrap();
    muyon_core_agent_lab::store::atomic(&dir, "object.db", r#"{"objects":{}}"#).unwrap();
    let mut handler = read_registry::PhysicalReadHandler::new(
        &dir,
        "object.db",
        "id",
        "s1",
        vec!["objects".into()],
        None,
    )
    .unwrap()
    .require_argument("type", Json::String("supplier".into()))
    .unwrap().bind_record(json(r#"{"module_id":"inquiry","type":"supplier","key":"s1","revision":"1","schema_version":1}"#),Some("type".into())).unwrap();
    let bound = json(
        r#"{"module_id":"inquiry","type":"supplier","key":"s1","revision":"1","schema_version":1}"#,
    );
    let valid_args = json(r#"{"id":"s1","type":"supplier"}"#);
    assert!(handler.admit_read(&valid_args, &[bound.clone()]).is_ok());
    let mut other = bound.clone();
    put(&mut other, "key", Json::String("s2".into()));
    assert_eq!(
        handler.admit_read(&valid_args, &[other]).unwrap_err(),
        "physical_reference_scope",
        "another allowed record cannot authorize this physical read"
    );
    assert_eq!(
        handler
            .admit_read(&json(r#"{"id":"s2","type":"supplier"}"#), &[bound.clone()])
            .unwrap_err(),
        "physical_record_scope"
    );
    let mut stale = bound;
    put(&mut stale, "revision", Json::String("2".into()));
    assert_eq!(
        handler.admit_read(&valid_args, &[stale]).unwrap_err(),
        "physical_reference_scope"
    );
    assert!(handler
        .read(&json(r#"{"id":"s1","type":"supplier"}"#))
        .is_ok());
    assert_eq!(
        handler
            .read(&json(r#"{"id":"s1","type":"product"}"#))
            .err()
            .unwrap(),
        "physical_argument_scope"
    );
}
#[test]
fn invalid_host_enrollment_publishes_nothing_and_active_catalog_is_sealed() {
    let plugin = PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").unwrap());
    let s =
        NativeSession::create(&directory(), &plugin, authority(), Rc::new(Review), "read").unwrap();
    let make = |tool: &str| Enrollment {
        bundle: json(include_str!(
            "../../../plugin-contract-lab/fixtures/equipment_loan.json"
        )),
        operation: "equipment_loan/inspect_equipment@1".into(),
        tool_id: tool.into(),
        binding_id: "host-equipment-read".into(),
        scope_refs: equipment_scope(),
        handler: Box::new(|_: &Json| {
            Ok(RawRead {
                raw: projection(),
                projection: projection(),
            })
        }),
    };
    assert!(s.borrow_mut().register(make("other.tool")).is_err());
    s.borrow_mut()
        .register(make("equipment_loan.inspect_equipment"))
        .unwrap();
    let a = run(&s);
    assert_eq!(a.state.status, "completed");
    let d = muyon_plugin_contract_lab::mappings::renamed_equipment(17).unwrap();
    let late = Enrollment {
        bundle: d.bundle,
        operation: d.operation,
        tool_id: d.tool_id,
        binding_id: d.binding_id,
        scope_refs: equipment_scope(),
        handler: Box::new(|_: &Json| {
            Ok(RawRead {
                raw: projection(),
                projection: projection(),
            })
        }),
    };
    assert_eq!(
        s.borrow_mut().register(late).err().unwrap(),
        "active_catalog_sealed"
    );
    assert_eq!(s.borrow().handler_calls, 1);
}
#[test]
fn missing_selected_refs_execute_zero_before_physical_read() {
    for permitted in [true, false] {
        let auth = authority();
        if !permitted {
            put(
                &mut auth.0.borrow_mut().read,
                "refs",
                Json::Array(Vec::new()),
            );
        }
        let s = session(auth);
        let a = run(&s);
        if permitted {
            assert_eq!(a.state.status, "completed");
            assert_eq!(s.borrow().handler_calls, 1);
        } else {
            assert_eq!(
                s.borrow().handler_calls,
                0,
                "empty current refs must deny before physical handler reads"
            );
            assert!(!s
                .borrow()
                .store
                .receipts()
                .iter()
                .any(|r| r.encode().contains("BORROWER_PRIVATE")));
            assert_ne!(a.state.status, "completed");
        }
    }
}
struct RevokeAfterReturnedSnapshot {
    authority: Rc<Authority>,
    calls: std::cell::Cell<usize>,
    revoke: bool,
}
impl AuthoritySource for RevokeAfterReturnedSnapshot {
    fn snapshot(&self) -> Result<AuthoritySnapshot> {
        let call = self.calls.get() + 1;
        self.calls.set(call);
        let value = self.authority.0.borrow().clone();
        if self.revoke && call == 3 {
            put(
                &mut self.authority.0.borrow_mut().read,
                "allowed",
                Json::Bool(false),
            );
            put(
                &mut self.authority.0.borrow_mut().read,
                "revision",
                Json::String("a2".into()),
            );
        }
        Ok(value)
    }
}
#[test]
fn revoke_after_preinvoke_snapshot_executes_zero() {
    for revoke in [false, true] {
        let a = authority();
        let source = Rc::new(RevokeAfterReturnedSnapshot {
            authority: a.clone(),
            calls: std::cell::Cell::new(0),
            revoke,
        });
        let s = session(source.clone());
        let result = run(&s);
        assert!(source.calls.get() >= 3);
        if revoke {
            assert_eq!(
                field(&a.0.borrow().read, "allowed").unwrap(),
                &Json::Bool(false)
            );
            assert_eq!(
                s.borrow().handler_calls,
                0,
                "revocation after the returned pre-invoke snapshot must prevent physical read"
            );
            assert_ne!(result.state.status, "completed");
            assert!(!s
                .borrow()
                .store
                .receipts()
                .iter()
                .any(|r| r.encode().contains("BORROWER_PRIVATE")));
        } else {
            assert_eq!(result.state.status, "completed");
            assert_eq!(s.borrow().handler_calls, 1);
        }
    }
}
#[test]
fn native_store_restore_rejects_forged_receipts_and_facts() {
    let s = session(authority());
    let _ = run(&s);
    let dir = s.borrow().store.dir.clone();
    drop(s);
    let valid = json(&std::fs::read_to_string(dir.join("native.db")).unwrap());
    let original_receipt = field(&valid, "receipts").unwrap().array().unwrap()[0].clone();
    let mut malformed = Vec::new();
    let mut v = valid.clone();
    put(&mut v, "facts", Json::Null);
    malformed.push(v);
    let mut v = valid.clone();
    put(&mut v, "receipts", Json::Array(vec![Json::Null]));
    malformed.push(v);
    let mut v = valid.clone();
    put(
        &mut v,
        "receipts",
        Json::Array(vec![original_receipt.clone(), original_receipt.clone()]),
    );
    malformed.push(v);
    let mut v = valid.clone();
    put(
        &mut v,
        "facts",
        json(r#"{"external_read":false,"unknown_source":false}"#),
    );
    malformed.push(v);
    let mut r = original_receipt.clone();
    put(&mut r, "status", Json::String("invented".into()));
    let mut v = valid.clone();
    put(&mut v, "receipts", Json::Array(vec![r]));
    malformed.push(v);
    let mut r = original_receipt.clone();
    put(&mut r, "status", Json::String("running".into()));
    let mut v = valid.clone();
    put(&mut v, "receipts", Json::Array(vec![r]));
    malformed.push(v);
    let mut r = original_receipt.clone();
    put(&mut r, "binding", Json::Null);
    let mut v = valid.clone();
    put(&mut v, "receipts", Json::Array(vec![r]));
    malformed.push(v);
    let mut r = original_receipt;
    let mut identity = field(&r, "identity").unwrap().clone();
    put(&mut identity, "owner", Json::String("foreign".into()));
    put(&mut r, "identity", identity);
    let mut v = valid.clone();
    put(&mut v, "receipts", Json::Array(vec![r]));
    malformed.push(v);
    assert_eq!(store::NativeStore::open(&dir).unwrap().receipt_count(), 1);
    for (i, v) in malformed.into_iter().enumerate() {
        let d = directory();
        muyon_core_agent_lab::store::create_dir(&d).unwrap();
        muyon_core_agent_lab::store::atomic(&d, "native.db", &v.encode()).unwrap();
        assert!(
            store::NativeStore::open(&d).is_err(),
            "forged store variant {i} must refuse"
        );
    }
}
#[test]
fn native_store_persist_budget_never_writes_unreadable_snapshot() {
    let s = session(authority());
    let _ = run(&s);
    let dir = s.borrow().store.dir.clone();
    drop(s);
    let mut store = store::NativeStore::open(&dir).unwrap();
    let first = store.receipts()[0].clone();
    let mut identity = field(&first, "identity").unwrap().clone();
    put(
        &mut identity,
        "invocation_id",
        Json::String("i-extra".into()),
    );
    put(
        &mut identity,
        "identity",
        Json::String("another-identity".into()),
    );
    let index = store
        .begin(identity, field(&first, "binding").unwrap().clone())
        .unwrap();
    let before = std::fs::read(dir.join("native.db")).unwrap();
    assert!(
        store
            .finish(index, Json::String("x".repeat(70000)), true)
            .is_err(),
        "a successful persist must stay inside restore parser budget"
    );
    assert_eq!(std::fs::read(dir.join("native.db")).unwrap(), before);
    assert_eq!(
        field(&store.receipts()[index], "status").unwrap(),
        &Json::String("running".into()),
        "failed candidate must not mutate accepted in-memory receipt"
    );
    assert_eq!(field(&store.receipts()[index], "raw").unwrap(), &Json::Null);
    assert!(
        store.ensure_healthy().is_err(),
        "uncertain persistence poisons further export/execution"
    );
    assert_eq!(
        field(store.facts(), "unknown_source").unwrap(),
        &Json::Bool(true)
    );
    drop(store);
    let restored = store::NativeStore::open(&dir).unwrap();
    assert_eq!(restored.receipt_count(), 2);
    assert_eq!(
        field(&restored.receipts()[1], "status").unwrap(),
        &Json::String("running".into())
    );
    let s = session_handler(
        authority(),
        Box::new(|_: &Json| {
            Ok(RawRead {
                raw: Json::String("x".repeat(70000)),
                projection: projection(),
            })
        }),
    );
    let (mut provider, sent) = gateway(&s);
    let mut agent = agent(&s);
    agent
        .run_with_runtime_ports(
            &mut provider,
            &mut RuntimePorts { session: s.clone() },
            &Hooks::default(),
        )
        .unwrap();
    assert_eq!(s.borrow().handler_calls, 1);
    assert_eq!(
        sent.borrow().len(),
        1,
        "no second model send after raw persistence failure"
    );
    assert_eq!(s.borrow().model_history().array().unwrap().len(), 1);
    assert!(s.borrow().store.ensure_healthy().is_err());
    assert_eq!(
        field(&s.borrow().store.receipts()[0], "status").unwrap(),
        &Json::String("running".into())
    );
    assert_eq!(
        field(s.borrow().store.facts(), "unknown_source").unwrap(),
        &Json::Bool(true)
    );
}

fn equipment_scope() -> Vec<Json> {
    let p = projection();
    vec![
        field(&p, "equipment").unwrap().clone(),
        field(&p, "loans").unwrap().array().unwrap()[0].clone(),
    ]
}
#[test]
fn cancel_during_handler_retains_raw_receipt_without_projection() {
    let path = Rc::new(RefCell::new(None::<PathBuf>));
    let signal = path.clone();
    let s = session_handler(
        authority(),
        Box::new(move |_: &Json| {
            muyon_core_agent_lab::store::atomic(
                signal.borrow().as_ref().unwrap(),
                "cancel.request",
                "CORE_CANCEL_V1\n",
            )?;
            Ok(RawRead {
                raw: projection(),
                projection: projection(),
            })
        }),
    );
    *path.borrow_mut() = Some(s.borrow().store.dir.clone());
    let a = run(&s);
    assert_eq!(s.borrow().handler_calls, 1);
    assert_eq!(s.borrow().store.receipt_count(), 1);
    assert_ne!(a.state.status, "completed");
    assert_eq!(
        s.borrow().model_history().array().unwrap().len(),
        1,
        "cancel after raw read must not admit a model projection"
    );
}
