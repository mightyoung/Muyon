//! Rust-owned synthetic read composition. Never exported as a UI runtime entry.
use crate::{service_types::AgentReadVariant, Json, Result};
use muyon_core_agent_lab::agent::State;
use std::{
    path::Path,
    sync::{
        atomic::{AtomicBool, AtomicU8, Ordering},
        Arc,
    },
    time::{Duration, Instant},
};
pub struct RunControl {
    cancelled: AtomicBool,
    observed_stop: AtomicU8,
    deadline: Instant,
    live_deadline: std::sync::Mutex<Option<Instant>>,
}
impl RunControl {
    pub fn new() -> Self {
        Self {
            cancelled: AtomicBool::new(false),
            observed_stop: AtomicU8::new(0),
            deadline: Instant::now() + Duration::from_secs(5),
            live_deadline: std::sync::Mutex::new(None),
        }
    }
    pub(crate) fn cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }
    pub fn request_cancel(&self) {
        self.cancelled.store(true, Ordering::Release)
    }
    pub(crate) fn observed_deadline(&self) -> bool {
        self.observed_stop.load(Ordering::Acquire) == 2
    }
    /// Called once only after trusted non-synthetic chat authority validation.
    pub(crate) fn authorize_live_chat(&self) -> Result<()> {
        self.poll()?;
        let mut deadline = self.live_deadline.lock().map_err(|_| "native_deadline")?;
        if deadline.is_none() { *deadline = Some(Instant::now() + Duration::from_secs(60)); }
        Ok(())
    }
    pub fn poll(&self) -> Result<()> {
        let mut observed = self.observed_stop.load(Ordering::Acquire);
        if observed == 0 {
            let cause = if self.cancelled.load(Ordering::Acquire) {
                1
            } else if Instant::now() >= self.live_deadline.lock().map_err(|_| "native_deadline")?.unwrap_or(self.deadline) {
                2
            } else {
                return Ok(());
            };
            // A later control signal cannot rewrite an already observed stop.
            observed = match self.observed_stop.compare_exchange(
                0, cause, Ordering::AcqRel, Ordering::Acquire,
            ) {
                Ok(_) => cause,
                Err(first) => first,
            };
        }
        Err(if observed == 1 {
            "native_cancelled"
        } else {
            "native_deadline"
        }.into())
    }
}
impl Default for RunControl {
    fn default() -> Self {
        Self::new()
    }
}
pub struct BuiltinExecution {
    pub state: State,
    pub receipts: Vec<Json>,
    pub facts: Json,
    pub payloads: Vec<Vec<u8>>,
    pub handler_calls: usize,
}
struct BuiltinAuthority(crate::AuthoritySnapshot);
impl crate::AuthoritySource for BuiltinAuthority {
    fn snapshot(&self) -> Result<crate::AuthoritySnapshot> {
        Ok(self.0.clone())
    }
}
struct BuiltinReview;
impl crate::PurposeReview for BuiltinReview {
    fn review(&self, value: &Json, facts: &Json, purpose: &str) -> Result<()> {
        if !matches!(purpose, "model_context" | "model_payload")
            || value.encode().contains("BORROWER_PRIVATE")
        {
            return Err("service_value_denied".into());
        }
        // The trusted synthetic profile explicitly permits these purposes while source facts remain contaminated.
        for key in ["external_read", "unknown_source"] {
            if !matches!(crate::field(facts, key)?, Json::Bool(_)) {
                return Err("service_facts_invalid".into());
            }
        }
        Ok(())
    }
    fn mask_answer(&self, text: &str) -> Result<String> {
        if text.contains("BORROWER_PRIVATE") {
            Err("service_answer_denied".into())
        } else {
            Ok(text.into())
        }
    }
}
struct BuiltinEndpoint {
    args: Json,
    frames: std::rc::Rc<std::cell::RefCell<Vec<Vec<u8>>>>,
    control: Arc<RunControl>,
}
impl crate::model_gateway::OfflineEndpoint for BuiltinEndpoint {
    fn exchange(
        &mut self,
        payload: &[u8],
        control: &mut dyn muyon_core_agent_lab::model::ProviderControl,
    ) -> Result<Vec<u8>> {
        self.control.poll()?;
        control.poll()?;
        let position = self.frames.borrow().len();
        if position >= 2 {
            return Err("service_provider_budget".into());
        }
        self.frames.borrow_mut().push(payload.to_vec());
        use muyon_plugin_contract_lab::{object, string};
        let choice = if position == 0 {
            object([
                ("index", Json::Number("0".into())),
                (
                    "delta",
                    object([(
                        "tool_calls",
                        Json::Array(vec![object([
                            ("index", Json::Number("0".into())),
                            ("id", string("service_call1")),
                            ("type", string("function")),
                            (
                                "function",
                                object([
                                    ("name", string("registered_0")),
                                    ("arguments", string(self.args.encode())),
                                ]),
                            ),
                        ])]),
                    )]),
                ),
                ("finish_reason", string("tool_calls")),
            ])
        } else {
            object([
                ("index", Json::Number("0".into())),
                (
                    "delta",
                    object([("content", string("offline synthetic read completed"))]),
                ),
                ("finish_reason", string("stop")),
            ])
        };
        Ok(format!(
            "data: {}\n\ndata: [DONE]\n\n",
            object([("choices", Json::Array(vec![choice]))]).encode()
        )
        .into_bytes())
    }
}
pub fn run_builtin(
    dir: &Path,
    variant: AgentReadVariant,
    control: Arc<RunControl>,
) -> Result<BuiltinExecution> {
    run_builtin_admitted(dir, variant, control, |_| Ok(()))
}

// The controller persists the ORIGINAL State pair before the SAME Agent drive.
// This callback cannot supply a different provider, handler, authority or driver.
pub(crate) fn run_builtin_admitted(
    dir: &Path,
    variant: AgentReadVariant,
    control: Arc<RunControl>,
    mut admit_state: impl FnMut(&State) -> Result<()>,
) -> Result<BuiltinExecution> {
    use crate::{
        model_gateway::ModelGateway, read_registry::PhysicalReadHandler, AuthoritySnapshot,
        Enrollment, NativeSession, RuntimePorts,
    };
    use muyon_core_agent_lab::{
        agent::{Agent, Hooks, Limits, State},
        store,
    };
    use muyon_plugin_contract_lab::{
        mappings::{declaration, renamed_equipment, MappingKind},
        object, string,
    };
    use std::{cell::RefCell, rc::Rc};
    control.poll()?;
    let (decl, typ, key, native_key) = match variant {
        AgentReadVariant::Equipment => (
            declaration(MappingKind::Equipment)?,
            "equipment",
            "e1",
            "equipment_key",
        ),
        AgentReadVariant::Research => (declaration(MappingKind::Research)?, "project", "p1", "id"),
        AgentReadVariant::Inquiry => (declaration(MappingKind::Inquiry)?, "supplier", "s1", "id"),
        AgentReadVariant::SeededEquipment => {
            (renamed_equipment(0x7631)?, "asset", "e1", "equipment_key")
        }
    };
    let module = crate::field(&decl.bundle, "module_id")?
        .string()?
        .to_owned();
    let reference = object([
        ("module_id", string(&module)),
        ("type", string(typ)),
        ("key", string(key)),
        ("revision", string("1")),
        ("schema_version", Json::Number("1".into())),
    ]);
    let projection = if native_key == "id" {
        object([(
            "objects",
            object([(typ, Json::Array(vec![reference.clone()]))]),
        )])
    } else {
        object([
            (typ, reference.clone()),
            ("label", string("synthetic mapped value")),
            ("loans", Json::Array(Vec::new())),
        ])
    };
    let args = if native_key == "id" {
        object([("type", string(typ)), ("id", string(key))])
    } else {
        object([
            ("equipment_key", string(key)),
            ("include_loans", Json::Bool(false)),
        ])
    };
    let read = object([
        ("allowed", Json::Bool(true)),
        ("available", Json::Bool(true)),
        ("scope_allowed", Json::Bool(true)),
        ("bindings", Json::Array(vec![string(&decl.binding_id)])),
        ("revision", string("a1")),
        ("binding_revision", string("b1")),
        ("source_revision", string("s1")),
        ("rule_revision", string("r1")),
        ("scope", string("selected-record")),
        ("refs", Json::Array(vec![reference.clone()])),
    ]);
    let session = NativeSession::service_in_process(
        dir,
        Rc::new(BuiltinAuthority(AuthoritySnapshot {
            read,
            model_allowed: true,
            profile: "offline-fixture".into(),
        })),
        Rc::new(BuiltinReview),
        "read selected synthetic record",
        control.clone(),
    )?;
    let mut raw = projection.clone();
    if let Json::Object(map) = &mut raw {
        map.insert("private_value".into(), string("BORROWER_PRIVATE"));
    }
    let encoded = raw.encode();
    if encoded.len() > 8192 {
        return Err("service_raw_budget".into());
    }
    store::atomic(dir, "source.db", &encoded)?;
    let mut handler = PhysicalReadHandler::new(
        dir,
        "source.db",
        native_key,
        key,
        projection.object()?.keys().cloned().collect(),
        None,
    )?
    .service_bounded();
    if native_key == "id" {
        handler = handler.require_argument("type", string(typ))?;
    }
    handler = handler.bind_record(
        reference.clone(),
        if native_key == "id" {
            Some("type".into())
        } else {
            None
        },
    )?;
    session.borrow_mut().register(Enrollment {
        bundle: decl.bundle,
        operation: decl.operation,
        tool_id: decl.tool_id,
        binding_id: decl.binding_id,
        scope_refs: vec![reference],
        handler: Box::new(handler),
    })?;
    let frames = Rc::new(RefCell::new(Vec::new()));
    let mut provider = ModelGateway::new(
        session.clone(),
        Box::new(BuiltinEndpoint {
            args,
            frames: frames.clone(),
            control: control.clone(),
        }),
    );
    let state = State::runtime(
        "read selected synthetic record".into(),
        "selected-record".into(),
        Limits {
            steps: 2,
            calls: 2,
            context: 32768,
            output: 16384,
            total: 65536,
        },
    )?;
    let initial = state.encode();
    if initial.len() > 128 * 1024 {
        return Err("service_task_budget".into());
    }
    store::atomic(dir, "task.db", &initial)?;
    admit_state(&state)?;
    control.poll()?;
    let mut agent = Agent {
        dir: dir.into(),
        state,
    };
    agent.run_with_runtime_ports(
        &mut provider,
        &mut RuntimePorts {
            session: session.clone(),
        },
        &Hooks::default(),
    )?;
    let receipts = session.borrow().store.receipts().to_vec();
    let facts = session.borrow().store.facts().clone();
    let handler_calls = session.borrow().handler_calls;
    let payloads = frames.borrow().clone();
    drop(provider);
    drop(session);
    Ok(BuiltinExecution {
        state: agent.state,
        receipts,
        facts,
        payloads,
        handler_calls,
    })
}

#[cfg(test)]
mod stop_cause_tests {
    use super::*;

    #[test]
    fn trusted_live_deadline_extends_only_unstopped_control_and_never_revives_stop() {
        let mut live = RunControl::new();
        live.authorize_live_chat().unwrap();
        live.deadline = Instant::now();
        assert!(live.poll().is_ok());
        live.request_cancel();
        assert_eq!(live.poll().unwrap_err(), "native_cancelled");
        assert!(live.authorize_live_chat().is_err());
        let mut legacy = RunControl::new();
        legacy.deadline = Instant::now();
        assert_eq!(legacy.poll().unwrap_err(), "native_deadline");
        assert!(legacy.authorize_live_chat().is_err());
    }

    #[test]
    fn observed_deadline_survives_late_cancel() {
        let mut control = RunControl::new();
        control.deadline = Instant::now();
        assert_eq!(control.poll().unwrap_err(), "native_deadline");
        control.request_cancel();
        assert_eq!(control.poll().unwrap_err(), "native_deadline");
        assert!(control.observed_deadline());
    }

    #[test]
    fn observed_cancel_survives_later_deadline() {
        let mut control = RunControl::new();
        control.request_cancel();
        assert_eq!(control.poll().unwrap_err(), "native_cancelled");
        control.deadline = Instant::now();
        assert_eq!(control.poll().unwrap_err(), "native_cancelled");
        assert!(!control.observed_deadline());
    }
}
