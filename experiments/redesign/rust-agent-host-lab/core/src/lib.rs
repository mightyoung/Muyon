//! Private Linux-only native read composition. Uses the existing Agent drive;
//! the child admits contracts/tickets, while host-installed Rust handlers read.
pub mod model_gateway;
pub mod ordinary_chat;
mod chat_history;
pub mod plugin_process;
pub mod read_registry;
pub mod supplier_store;
pub mod supplier_scope_bridge;
pub mod service_provider;
pub mod service_host;
pub mod supplier_lab_source;
mod supplier_business;
pub mod store;
use contract_transport::{ContractTransport, InProcessCatalog};
use muyon_core_agent_lab::{
    agent::{Agent, State},
    agent_ports::AgentPorts,
    model::{Message, Role},
    Result,
};
use muyon_plugin_contract_lab::{object, string, Json};
use plugin_process::PluginProcess;
use service_runtime::RunControl;
use std::sync::Arc;
use std::{cell::RefCell, collections::BTreeMap, io::Read, path::Path, rc::Rc, time::Duration};
use store::NativeStore;
pub const STUB_REACHED: &str = "NATIVE_HOST_STUB_REACHED";
pub fn field<'a>(j: &'a Json, key: &str) -> Result<&'a Json> {
    j.object()?.get(key).ok_or_else(|| format!("missing_{key}"))
}
fn text(j: &Json, key: &str) -> Result<String> {
    Ok(field(j, key)?.string()?.into())
}
fn request(command: &str, fields: Vec<(&str, Json)>) -> Json {
    let mut pairs = fields;
    pairs.push(("command", string(command)));
    pairs.push(("protocol_version", Json::Number("1".into())));
    object(pairs)
}
fn success(reply: Json) -> Result<Json> {
    if field(&reply, "ok")? == &Json::Bool(true) {
        Ok(reply)
    } else {
        Err(format!(
            "contract_{}",
            text(&reply, "code").unwrap_or_else(|_| "rejected".into())
        ))
    }
}
fn nonce() -> Result<String> {
    let mut bytes = [0u8; 16];
    std::fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut bytes))
        .map_err(|_| "identity_entropy")?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AuthoritySnapshot {
    pub read: Json,
    pub model_allowed: bool,
    pub profile: String,
}
pub trait AuthoritySource {
    fn snapshot(&self) -> Result<AuthoritySnapshot>;
}
pub trait PurposeReview {
    fn review(&self, value: &Json, facts: &Json, purpose: &str) -> Result<()>;
    fn mask_answer(&self, text: &str) -> Result<String>;
}
pub struct RawRead {
    pub raw: Json,
    pub projection: Json,
}
pub trait ReadHandler {
    /// Pure trusted-host argument/scope admission, before physical execution.
    /// Native closures are trusted code; filesystem handlers bind exact records.
    fn admit_read(&self, _canonical_args: &Json, _scope_refs: &[Json]) -> Result<()> {
        Ok(())
    }
    fn read(&mut self, canonical_args: &Json) -> Result<RawRead>;
}
impl<F: FnMut(&Json) -> Result<RawRead>> ReadHandler for F {
    fn read(&mut self, args: &Json) -> Result<RawRead> {
        self(args)
    }
}
pub struct Enrollment {
    pub bundle: Json,
    pub operation: String,
    pub tool_id: String,
    pub binding_id: String,
    /// Trusted installation binds every physical record this handler may read.
    pub scope_refs: Vec<Json>,
    pub handler: Box<dyn ReadHandler>,
}
struct Installed {
    operation: String,
    tool_id: String,
    binding: String,
    parameters: Json,
    handler: Box<dyn ReadHandler>,
    scope_refs: Vec<Json>,
}
#[derive(Clone)]
struct Projection {
    value: Json,
    authority: AuthoritySnapshot,
    receipt: Json,
}
pub struct NativeSession {
    pub store: NativeStore,
    process: Box<dyn ContractTransport>,
    service_control: Option<Arc<RunControl>>,
    authority: Rc<dyn AuthoritySource>,
    review: Rc<dyn PurposeReview>,
    installed: BTreeMap<String, Installed>,
    history: Vec<Json>,
    projections: Vec<Projection>,
    pub dispatch_attempts: usize,
    pub handler_calls: usize,
    pub model_sends: usize,
    cancelled: bool,
    advertised: Vec<String>,
    call_ids: std::collections::BTreeSet<String>,
    catalog_sealed: bool,
}
pub type SharedSession = Rc<RefCell<NativeSession>>;
impl NativeSession {
    pub fn create(
        dir: &Path,
        plugin: &Path,
        authority: Rc<dyn AuthoritySource>,
        review: Rc<dyn PurposeReview>,
        input: &str,
    ) -> Result<SharedSession> {
        if input.len() > 8192 {
            return Err("input_limit".into());
        }
        let store = NativeStore::create(dir)?;
        let process = PluginProcess::spawn(plugin, Duration::from_secs(5))?;
        Ok(Self::from_parts(
            store,
            Box::new(process),
            authority,
            review,
            input,
        ))
    }
    fn from_parts(
        store: NativeStore,
        process: Box<dyn ContractTransport>,
        authority: Rc<dyn AuthoritySource>,
        review: Rc<dyn PurposeReview>,
        input: &str,
    ) -> SharedSession {
        Rc::new(RefCell::new(Self {
            store,
            process,
            service_control: None,
            authority,
            review,
            installed: BTreeMap::new(),
            history: vec![object([
                ("role", string("user")),
                ("content", string(input)),
            ])],
            projections: Vec::new(),
            dispatch_attempts: 0,
            handler_calls: 0,
            model_sends: 0,
            cancelled: false,
            advertised: Vec::new(),
            call_ids: std::collections::BTreeSet::new(),
            catalog_sealed: false,
        }))
    }
    pub(crate) fn service_in_process(
        dir: &Path,
        authority: Rc<dyn AuthoritySource>,
        review: Rc<dyn PurposeReview>,
        input: &str,
        control: Arc<RunControl>,
    ) -> Result<SharedSession> {
        if input.len() > 8192 {
            return Err("input_limit".into());
        }
        control.poll()?;
        let store = NativeStore::initialize_private(dir)?;
        let session = Self::from_parts(
            store,
            Box::new(InProcessCatalog::new()),
            authority,
            review,
            input,
        );
        session.borrow_mut().service_control = Some(control);
        Ok(session)
    }
    pub(crate) fn poll_service_control(&self) -> Result<()> {
        if let Some(control) = &self.service_control {
            control.poll()?;
        }
        Ok(())
    }
    pub fn register(&mut self, enrollment: Enrollment) -> Result<()> {
        if self.catalog_sealed {
            return Err("active_catalog_sealed".into());
        }
        if self.cancelled
            || self.installed.values().any(|v| {
                v.operation == enrollment.operation
                    || v.tool_id == enrollment.tool_id
                    || v.binding == enrollment.binding_id
            })
        {
            return Err("duplicate_enrollment".into());
        }
        let operations = field(&enrollment.bundle, "operations")?.array()?;
        if operations.len() != 1 {
            return Err("enrollment_operation_count".into());
        }
        let declared = operations
            .iter()
            .find(|d| text(d, "binding_id").ok().as_deref() == Some(&enrollment.binding_id))
            .ok_or("binding_declaration")?;
        let parameters = field(declared, "input_schema")?.clone();
        let data_refs = field(declared, "data_refs")?.array()?;
        if enrollment.scope_refs.is_empty() || enrollment.scope_refs.len() > 128 {
            return Err("unbound_read_scope".into());
        }
        let mut seen = std::collections::BTreeSet::new();
        for reference in &enrollment.scope_refs {
            validate_reference(reference)?;
            let target = format!(
                "{}/{}@{}",
                text(reference, "module_id")?,
                text(reference, "type")?,
                field(reference, "schema_version")?.integer()?
            );
            if !data_refs.contains(&string(target)) || !seen.insert(reference.encode()) {
                return Err("scope_reference_target".into());
            }
        }
        let module = text(&enrollment.bundle, "module_id")?;
        let operation_name = text(declared, "name")?;
        let version = field(declared, "schema_version")?.integer()?;
        if enrollment.tool_id != format!("{module}.{operation_name}")
            || enrollment.operation != format!("{module}/{operation_name}@{version}")
        {
            return Err("enrollment_identity".into());
        }
        success(self.process.request(request(
            "register",
            vec![
                ("bundle", enrollment.bundle),
                (
                    "host_bindings",
                    Json::Array(vec![string(&enrollment.binding_id)]),
                ),
            ],
        ))?)?;
        self.installed.insert(
            enrollment.operation.clone(),
            Installed {
                operation: enrollment.operation,
                tool_id: enrollment.tool_id,
                binding: enrollment.binding_id,
                parameters,
                handler: enrollment.handler,
                scope_refs: enrollment.scope_refs,
            },
        );
        Ok(())
    }
    pub fn discover(&mut self) -> Result<Json> {
        let a = self.authority.snapshot()?;
        success(
            self.process
                .request(request("discover", vec![("authority", a.read)]))?,
        )
    }
    pub fn cancel(&mut self) {
        self.cancelled = true;
        self.process.close();
    }
    pub fn child_pid(&self) -> u32 {
        self.process
            .child_pid()
            .expect("child_pid requires the legacy child-backed session")
    }
    pub fn definitions(&self) -> Vec<muyon_core_agent_lab::model::ToolDefinition> {
        self.installed
            .values()
            .enumerate()
            .map(|(index, v)| muyon_core_agent_lab::model::ToolDefinition {
                name: v.tool_id.clone(),
                wire_name: format!("registered_{index}"),
                parameters: v.parameters.clone(),
            })
            .collect()
    }
    pub fn model_history(&self) -> Json {
        Json::Array(self.history.clone())
    }
    pub fn review_payload(&self, payload: &[u8]) -> Result<()> {
        self.poll_service_control()?;
        if self.cancelled {
            return Err("native_cancelled".into());
        }
        self.store.ensure_healthy()?;
        let current = self.authority.snapshot()?;
        if !current.model_allowed || current.profile != "offline-fixture" {
            return Err("model_authority_denied".into());
        }
        for p in &self.projections {
            if current != p.authority {
                return Err("projection_revoked".into());
            }
            self.review
                .review(&p.value, self.store.facts(), "model_context")?;
            if !self
                .store
                .receipts()
                .iter()
                .any(|r| field(r, "identity") == Ok(&p.receipt))
            {
                return Err("projection_receipt_missing".into());
            }
        }
        let json = muyon_plugin_contract_lab::parse(payload)?;
        self.review
            .review(&json, self.store.facts(), "model_payload")?;
        // This synchronous final revision equality is the send admission point.
        if self.authority.snapshot()? != current {
            return Err("send_authority_changed".into());
        }
        Ok(())
    }
    fn check_agent_cancel(&self, agent: &mut Agent) -> Result<()> {
        if let Err(reason) = self.poll_service_control() {
            if reason == "native_cancelled" {
                agent.state.cancelled = true;
            }
            return Err(reason);
        }
        let path = agent.dir.join("cancel.request");
        match std::fs::symlink_metadata(&path) {
            Ok(_) => {
                if muyon_core_agent_lab::store::read(&path)? != "CORE_CANCEL_V1\n" {
                    return Err("invalid_cancel_signal".into());
                }
                agent.state.cancelled = true;
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => return Err("cancel_signal_unavailable".into()),
        }
        if self.cancelled || agent.state.cancelled {
            return Err("native_cancelled".into());
        }
        Ok(())
    }
    fn dispatch(
        &mut self,
        agent: &mut Agent,
        call_ref: String,
        name: String,
        arguments: Json,
    ) -> Result<()> {
        self.dispatch_attempts += 1;
        if self.cancelled {
            return Err("native_cancelled".into());
        }
        if !self.advertised.contains(&name) {
            return Err("tool_not_advertised".into());
        }
        self.poll_service_control()?;
        if self.service_control.is_some() && self.handler_calls >= 1 {
            return Err("service_read_budget".into());
        }
        if !muyon_core_agent_lab::identifier(&call_ref) || !self.call_ids.insert(call_ref.clone()) {
            return Err("duplicate_model_call".into());
        }
        let entry = self
            .installed
            .values()
            .find(|v| v.tool_id == name)
            .ok_or("unenrolled_operation")?;
        let operation = entry.operation.clone();
        let binding = entry.binding.clone();
        let scope_refs = entry.scope_refs.clone();
        let original = self.authority.snapshot()?;
        if text(&original.read, "scope")? != agent.state.scope {
            return Err("read_scope_mismatch".into());
        }
        entry.handler.admit_read(&arguments, &scope_refs)?;
        require_scope(&scope_refs, &original.read)?;
        self.review.review(
            &Json::Array(vec![string(&name), string(&call_ref), arguments.clone()]),
            self.store.facts(),
            "model_context",
        )?;
        let args = muyon_plugin_contract_lab::canonical_value(&arguments)?;
        let invocation = format!("i-{}", nonce()?);
        let identity = nonce()?;
        let prepared = success(self.process.request(request(
            "prepare",
            vec![
                ("operation", string(&operation)),
                ("args", args.clone()),
                ("authority", original.read.clone()),
                ("invocation_id", string(&invocation)),
                ("receipt_owner", string("ToolRegistry")),
                ("receipt_identity", string(&identity)),
            ],
        ))?)?;
        let ticket = field(&prepared, "ticket")?.clone();
        let current = self.authority.snapshot()?;
        if current != original {
            return Err("read_authority_changed".into());
        }
        self.store.mark_read()?;
        let invoked = success(self.process.request(request(
            "invoke",
            vec![
                ("ticket", ticket.clone()),
                ("authority", current.read.clone()),
            ],
        ))?)?;
        let dispatch = field(&invoked, "dispatch")?;
        let expected = object([
            ("binding_id", string(&binding)),
            ("args", args.clone()),
            ("invocation_id", string(&invocation)),
            ("receipt_identity", string(&identity)),
        ]);
        if dispatch != &expected {
            return Err("dispatch_identity_mismatch".into());
        }
        let receipt = object([
            ("owner", string("ToolRegistry")),
            ("invocation_id", string(&invocation)),
            ("binding_id", string(&binding)),
            ("identity", string(&identity)),
        ]);
        let durable_binding = object([
            ("task", string(&agent.state.task)),
            ("attempt", string(&agent.state.attempt)),
            ("turn", Json::Number(agent.state.counters.steps.to_string())),
            ("scope", string(&agent.state.scope)),
            ("operation", string(&operation)),
            ("args", args.clone()),
            ("authority", original.read.clone()),
            ("scope_refs", Json::Array(scope_refs.clone())),
        ]);
        let index = self.store.begin(receipt.clone(), durable_binding)?;
        // Final synchronous read admission: child IPC and durable receipt writes
        // may outlive the earlier snapshot. No IPC or persistence follows this
        // current-authority/ref check before the host handler is entered.
        self.installed
            .get(&operation)
            .ok_or("unenrolled_operation")?
            .handler
            .admit_read(&args, &scope_refs)?;
        self.check_agent_cancel(agent)?;
        let fresh = self.authority.snapshot()?;
        if fresh != original {
            return Err("read_authority_changed".into());
        }
        require_scope(&scope_refs, &fresh.read)?;
        self.poll_service_control()?;
        self.handler_calls += 1;
        let outcome = self
            .installed
            .get_mut(&operation)
            .ok_or("unenrolled_operation")?
            .handler
            .read(&args);
        let result = match outcome {
            Ok(result) => {
                self.store.finish(index, result.raw, true)?;
                result.projection
            }
            Err(error) => {
                self.store.finish(index, string(error), false)?;
                return Err("handler_failed".into());
            }
        };
        self.check_agent_cancel(agent)?;
        // No raw/provider/error fallback. Unknown-source facts remain durable even
        // when strict projection validation or later authority rejects the result.
        self.store.mark_read()?;
        let current = self.authority.snapshot()?;
        if current != original {
            return Err("read_authority_changed".into());
        }
        let accepted = success(self.process.request(request(
            "accept_result",
            vec![
                ("ticket", ticket),
                ("authority", current.read.clone()),
                ("receipt_ref", receipt.clone()),
                ("projection", result),
            ],
        ))?)?;
        if field(&accepted, "receipt_ref")? != &receipt {
            return Err("receipt_identity_mismatch".into());
        }
        let value = field(&accepted, "projection")?.clone();
        self.review
            .review(&value, self.store.facts(), "model_context")?;
        self.check_agent_cancel(agent)?;
        if self.authority.snapshot()? != original {
            return Err("read_authority_changed".into());
        }
        self.projections.push(Projection {
            value: value.clone(),
            authority: original,
            receipt: receipt.clone(),
        });
        let function = object([
            ("name", string(&name)),
            ("arguments", string(args.encode())),
        ]);
        self.history.push(object([
            ("role", string("assistant")),
            ("content", Json::Null),
            (
                "tool_calls",
                Json::Array(vec![object([
                    ("id", string(&call_ref)),
                    ("type", string("function")),
                    ("function", function),
                ])]),
            ),
        ]));
        self.history.push(object([
            ("role", string("tool")),
            ("tool_call_id", string(&call_ref)),
            (
                "content",
                string(object([("projection", value.clone()), ("receipt_ref", receipt)]).encode()),
            ),
        ]));
        agent.state.context.push(Message {
            role: Role::Tool,
            text: value.encode(),
        });
        agent.state.receipt = invocation;
        Ok(())
    }
}
pub struct RuntimePorts {
    pub session: SharedSession,
}
impl AgentPorts for RuntimePorts {
    fn advertised_tools(&self, state: &State) -> Result<Vec<String>> {
        let mut s = self.session.borrow_mut();
        s.poll_service_control()?;
        s.catalog_sealed = true;
        if s.service_control.is_some() && (s.handler_calls >= 1 || state.counters.steps > 1) {
            s.advertised.clear();
            return Ok(Vec::new());
        }
        let d = s.discover()?;
        let mut tools = Vec::new();
        for row in field(&d, "operations")?.array()? {
            let operation = text(row, "operation")?;
            let installed = s.installed.get(&operation).ok_or("unenrolled_operation")?;
            tools.push(installed.tool_id.clone());
        }
        s.advertised = tools.clone();
        Ok(tools)
    }
    fn persist(&self, agent: &Agent) -> Result<()> {
        let encoded = agent.state.encode();
        if self.session.borrow().service_control.is_some() && encoded.len() > 131072 {
            return Err("service_task_budget".into());
        }
        muyon_core_agent_lab::store::atomic(&self.session.borrow().store.dir, "task.db", &encoded)
    }
    fn check_control(&mut self) -> Result<()> {
        self.session.borrow().poll_service_control()?;
        if self.session.borrow().cancelled {
            Err("native_cancelled".into())
        } else {
            Ok(())
        }
    }
    fn dispatch(
        &mut self,
        agent: &mut Agent,
        call_ref: String,
        name: String,
        arguments: Json,
    ) -> Result<()> {
        self.session
            .borrow_mut()
            .dispatch(agent, call_ref, name, arguments)
    }
    fn admit_answer(&self, _state: &State, text: &str) -> Result<()> {
        let s = self.session.borrow();
        if s.review.mask_answer(text)? != text {
            return Err("unsafe_answer".into());
        }
        Ok(())
    }
    fn failure(&mut self, state: &mut State, _reason: &str) {
        if matches!(_reason, "model_ledger_failed" | "wire_journal") {
            state.status = "outcome_unknown".into();
            state.reason = _reason.into();
            return;
        }
        if _reason == "wire_total_limit" {
            state.status = "budget_exhausted".into();
            state.reason = _reason.into();
            return;
        }
        if self.session.borrow().service_control.is_some() {
            if _reason == "native_cancelled" {
                state.cancelled = true;
                state.status = "cancelled".into();
                state.reason = "native_cancelled".into();
                return;
            }
            if _reason == "native_deadline" {
                state.status = "budget_exhausted".into();
                state.reason = "native_deadline".into();
                return;
            }
        }
        state.status = "failed".into();
        state.reason = if _reason == "tool_not_advertised" {
            "tool_not_advertised".into()
        } else {
            "native_host_refused".into()
        };
    }
}

pub(crate) fn validate_reference(value: &Json) -> Result<()> {
    let m = value.object()?;
    if m.len() != 5
        || !["module_id", "type", "key", "revision"].iter().all(|key| {
            m.get(*key)
                .is_some_and(|v| v.string().is_ok_and(|s| !s.is_empty() && s.len() <= 128))
        })
        || !m
            .get("schema_version")
            .is_some_and(|v| v.integer().is_ok_and(|n| n > 0 && n <= 9007199254740991))
    {
        return Err("invalid_scope_reference".into());
    }
    Ok(())
}
fn require_scope(required: &[Json], authority: &Json) -> Result<()> {
    let available = field(authority, "refs")?.array()?;
    if required.is_empty()
        || required
            .iter()
            .any(|reference| !available.contains(reference))
    {
        return Err("selected_record_not_authorized".into());
    }
    Ok(())
}

// Private Android Service composition; legacy child-backed API is unchanged.
pub mod contract_transport;
pub mod service_controller;
pub mod service_runtime;
pub mod service_types;

pub mod service_root;

mod service_evidence;

#[cfg(test)]
mod http_recovery_tests;
