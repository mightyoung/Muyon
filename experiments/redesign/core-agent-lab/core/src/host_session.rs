//! Private product callbacks. Agent owns the only drive loop; the host owns authority.
use crate::{Result, agent::{Agent, State, Limits, Counters, Hooks}, model::{ModelRequest, ModelEvent, Provider, Message, Role}, policy::{HostFacts, Mode}, store, wire_provider::WireCounters, wire_json::{self, Json, object, string}};
use std::{cell::RefCell, collections::BTreeMap, fs, io, path::{Path, PathBuf}, rc::Rc, time::{Duration, Instant}};
use std::io::Read;
pub const FRAME_LIMIT: usize = 65536;
pub const IPC_LIMIT: usize = 262144;
fn number(n: u64) -> Json { Json::Number(n.to_string()) }
fn get<'a>(value: &'a Json, key: &str) -> Result<&'a Json> { value.object()?.get(key).ok_or_else(|| "host_protocol".into()) }
fn text<'a>(value: &'a Json, key: &str) -> Result<&'a str> { get(value, key)?.string() }
fn keys(value: &Json, expected: &[&str]) -> Result<()> {
    let fields = value.object()?;
    if fields.len() != expected.len() || expected.iter().any(|key| !fields.contains_key(*key)) { return Err("host_protocol".into()); }
    Ok(())
}
fn opaque(s: &str) -> bool { !s.is_empty() && s.len() <= 128 && s.bytes().all(|b| b.is_ascii_alphanumeric() || b"_.:-".contains(&b)) }
fn identity(s: &str) -> bool { !s.is_empty() && s.len() <= 96 && s.bytes().all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b)) }
fn metadata(s: &str) -> bool { !s.is_empty() && s.len() <= 128 && s.bytes().all(|b| b.is_ascii_alphanumeric() || b"._:/-".contains(&b)) }
fn object_type(s: &str) -> bool { !s.is_empty() && s.len() <= 32 && s.as_bytes()[0].is_ascii_lowercase() && s.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_') }
fn call_id(s: &str) -> bool { !s.is_empty() && s.len() <= 128 && !s.chars().any(char::is_control) }

#[derive(Clone, Debug)]
pub struct HostSessionConfig { pub root: PathBuf, pub idle_ms: u64, pub total_ms: u64 }
impl HostSessionConfig {
    pub fn validate(&self) -> Result<()> {
        if !self.root.is_absolute() || !self.root.is_dir() || !(1..=5000).contains(&self.idle_ms) || !(1..=30000).contains(&self.total_ms) { return Err("host_config_invalid".into()); }
        for path in self.root.ancestors() {
            if fs::symlink_metadata(path).map_err(|_| "host_config_invalid")?.file_type().is_symlink() { return Err("host_config_invalid".into()); }
        }
        if self.root.components().any(|p| matches!(p, std::path::Component::ParentDir)) { return Err("host_config_invalid".into()); }
        Ok(())
    }
}
#[derive(Clone, Debug)]
pub struct HostStart { pub task_id: String, pub attempt_id: String, pub scope_ref: String, pub prompt: String, pub tool: Json }
impl HostStart {
    pub fn parse(value: &Json) -> Result<Self> {
        keys(value, &["v", "kind", "task_id", "attempt_id", "scope_ref", "prompt", "tool"])?;
        if get(value, "v")?.integer()? != 1 || text(value, "kind")? != "start" { return Err("host_start_invalid".into()); }
        let task_id = text(value, "task_id")?.to_string(); let attempt_id = text(value, "attempt_id")?.to_string();
        let scope_ref = text(value, "scope_ref")?.to_string(); let prompt = text(value, "prompt")?.to_string();
        if !identity(&task_id) || !identity(&attempt_id) || !opaque(&scope_ref) || prompt.len() > 8192 { return Err("host_start_invalid".into()); }
        let tool = get(value, "tool")?.clone(); keys(&tool, &["name", "description", "parameters"])?;
        if text(&tool, "name")? != "inquiry.object" || text(&tool, "description")?.len() > 8192 { return Err("host_start_invalid".into()); }
        validate_schema(get(&tool, "parameters")?)?;
        Ok(Self { task_id, attempt_id, scope_ref, prompt, tool })
    }
    fn state(&self) -> State {
        State {
            task: self.task_id.clone(), attempt: self.attempt_id.clone(), status: "ready".into(), reason: String::new(), script: String::new(), scope: self.scope_ref.clone(),
            facts: HostFacts { mode: Mode::ReadOnly, ..HostFacts::default() },
            limits: Limits { steps: 2, calls: 2, context: 65536, output: 32768, total: 262144 }, counters: Counters::default(),
            context: vec![Message { role: Role::User, text: self.prompt.clone() }], position: 0,
            binding: None, unresolved: false, receipt: String::new(), answer: String::new(), cancelled: false,
            correlations: BTreeMap::new(), behavior: "host".into(), resume_status: String::new(), resume_reason: String::new(), result_pending: false,
            receipt_binding: None, evidence_hold: false, wire: None, wire_counters: WireCounters::default(), native: Vec::new(), pending_call_ref: String::new(),
        }
    }
}
fn validate_schema(schema: &Json) -> Result<()> {
    keys(schema, &["type", "properties", "required", "additionalProperties"])?;
    if text(schema, "type")? != "object" || get(schema, "additionalProperties")? != &Json::Bool(false) { return Err("host_schema_unsupported".into()); }
    let properties = get(schema, "properties")?; keys(properties, &["type", "id"])?;
    let types = get(properties, "type")?; keys(types, &["type", "enum"])?;
    if text(types, "type")? != "string" { return Err("host_schema_unsupported".into()); }
    let values = get(types, "enum")?.array()?;
    if values.is_empty() || values.len() > 32 { return Err("host_schema_unsupported".into()); }
    let mut seen = Vec::new();
    for value in values { let value = value.string()?; if !object_type(value) || seen.contains(&value) { return Err("host_schema_unsupported".into()); } seen.push(value); }
    keys(get(properties, "id")?, &["type"])?;
    if text(get(properties, "id")?, "type")? != "string" { return Err("host_schema_unsupported".into()); }
    let required = get(schema, "required")?.array()?;
    if required.len() != 2 || !required.contains(&string("type")) || !required.contains(&string("id")) { return Err("host_schema_unsupported".into()); }
    Ok(())
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HostInvocation { pub invocation_id: String, pub task_id: String, pub attempt_id: String, pub scope_ref: String, pub call_id: String, pub tool: String, pub arguments: Json, pub turn: u64 }
fn nonce_identity(entropy: &mut dyn Read) -> Result<String> {
    let mut nonce = [0u8; 32];
    entropy.read_exact(&mut nonce).map_err(|_| "host_identity_unavailable")?;
    Ok(format!("core:{}", nonce.iter().map(|byte| format!("{byte:02x}")).collect::<String>()))
}
impl HostInvocation {
    fn issue(state: &State, call_id: String, tool: String, arguments: Json) -> Result<Self> {
        let mut entropy = fs::File::open("/dev/urandom").map_err(|_| "host_identity_unavailable")?;
        let invocation_id = nonce_identity(&mut entropy)?;
        Ok(Self { invocation_id, task_id: state.task.clone(), attempt_id: state.attempt.clone(), scope_ref: state.scope.clone(), call_id, tool, arguments, turn: state.counters.steps })
    }
}
#[derive(Clone, Debug)]
pub struct PreparedInvocation { pub invocation: HostInvocation, pub prepared_ref: String }
pub enum PrepareDecision { Permit(PreparedInvocation), Denied, ConfirmationRequired }
pub trait HostAuthorizer { fn prepare(&mut self, call: &HostInvocation) -> Result<PrepareDecision>; }
pub trait HostToolPort { fn invoke(&mut self, prepared: &PreparedInvocation) -> Result<ProjectedToolResult>; }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProjectedObjectRef { pub module_id: String, pub object_type: String, pub object_id: String, pub revision_ref: Option<String>, pub content_digest: Option<String> }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProjectedToolResult { pub invocation_id: String, pub prepared_ref: String, pub receipt_ref: String, pub object_ref: ProjectedObjectRef }
impl ProjectedToolResult {
    pub fn projection(&self) -> Json {
        let optional = |v: &Option<String>| v.as_ref().map(string).unwrap_or(Json::Null);
        object([("found", Json::Bool(true)), ("objectRefs", Json::Array(vec![object([
            ("moduleId", string(&self.object_ref.module_id)), ("objectType", string(&self.object_ref.object_type)), ("objectId", string(&self.object_ref.object_id)),
            ("revisionRef", optional(&self.object_ref.revision_ref)), ("contentDigest", optional(&self.object_ref.content_digest)),
        ])]))])
    }
    fn parse(value: &Json, prepared: &PreparedInvocation) -> Result<Self> {
        if text(value, "invocation_id").map_err(|_| "host_protocol")? != prepared.invocation.invocation_id || text(value, "prepared_ref").map_err(|_| "host_protocol")? != prepared.prepared_ref { return Err("callback_mismatch".into()); }
        let receipt_ref = text(value, "receipt_ref").map_err(|_| "host_protocol")?;
        if !opaque(receipt_ref) { return Err("host_protocol".into()); }
        let projection = get(value, "projection")?;
        if projection.encoded_len()? > 8192 { return Err("projection_rejected".into()); }
        keys(projection, &["found", "objectRefs"]).map_err(|_| "projection_rejected")?;
        if get(projection, "found")? != &Json::Bool(true) { return Err("projection_rejected".into()); }
        let refs = get(projection, "objectRefs")?.array().map_err(|_| "projection_rejected")?;
        if refs.len() != 1 { return Err("projection_rejected".into()); }
        let reference = &refs[0]; keys(reference, &["moduleId", "objectType", "objectId", "revisionRef", "contentDigest"]).map_err(|_| "projection_rejected")?;
        let module_id = text(reference, "moduleId")?; let kind = text(reference, "objectType")?; let id = text(reference, "objectId")?;
        if module_id != "inquiry" || kind != text(&prepared.invocation.arguments, "type")? || id != text(&prepared.invocation.arguments, "id")? { return Err("projection_rejected".into()); }
        let optional = |key: &str| -> Result<Option<String>> { match get(reference, key)? { Json::Null => Ok(None), Json::String(value) if metadata(value) => Ok(Some(value.clone())), _ => Err("projection_rejected".into()) } };
        Ok(Self { invocation_id: prepared.invocation.invocation_id.clone(), prepared_ref: prepared.prepared_ref.clone(), receipt_ref: receipt_ref.into(), object_ref: ProjectedObjectRef {
            module_id: module_id.into(), object_type: kind.into(), object_id: id.into(), revision_ref: optional("revisionRef")?, content_digest: optional("contentDigest")?,
        } })
    }
}

#[derive(Clone, Copy, Debug)]
enum Shutdown { Cancel, Close }
impl Shutdown { fn error(self) -> &'static str { match self { Self::Cancel => "cancel_requested", Self::Close => "host_closed" } } }
#[repr(C)]
struct PollFd { fd: i32, events: i16, revents: i16 }
unsafe extern "C" { fn fcntl(fd: i32, cmd: i32, ...) -> i32; fn poll(fds: *mut PollFd, count: usize, timeout: i32) -> i32; fn read(fd: i32, buffer: *mut u8, count: usize) -> isize; fn write(fd: i32, buffer: *const u8, count: usize) -> isize; }
struct Transport {
    started: Instant, active: Instant, idle: Duration, total: Duration, bytes: usize,
    task: String, attempt: String, next: u64, shutdown: Option<Shutdown>, terminal_delivery: bool, invoke_admitted: bool, output_incomplete: bool, input_closed: bool, old_flags: [i32; 2],
}
impl Drop for Transport { fn drop(&mut self) { for fd in 0..2 { unsafe { fcntl(fd, 4, self.old_flags[fd as usize]); } } } }
impl Transport {
    fn new(config: &HostSessionConfig) -> Result<Self> {
        let started = Instant::now(); let mut old_flags = [0; 2];
        for fd in 0..2 { let flags = unsafe { fcntl(fd, 3) }; if flags < 0 || unsafe { fcntl(fd, 4, flags | 2048) } < 0 { return Err("host_pipe_setup".into()); } old_flags[fd as usize] = flags; }
        Ok(Self { started, active: started, idle: Duration::from_millis(config.idle_ms), total: Duration::from_millis(config.total_ms), bytes: 0, task: String::new(), attempt: String::new(), next: 1, shutdown: None, terminal_delivery: false, invoke_admitted: false, output_incomplete: false, input_closed: false, old_flags })
    }
    fn deadline(&self) -> Result<()> {
        let reserve = Duration::from_millis((self.total.as_millis() as u64 / 10).min(100));
        let total = if self.terminal_delivery { self.total } else { self.total.saturating_sub(reserve) };
        if self.started.elapsed() >= total || (!self.terminal_delivery && self.active.elapsed() >= self.idle) { Err("callback_timeout".into()) } else { Ok(()) }
    }
    fn admit_wait(&mut self) {
        // Rust-owned journal/entropy work is bounded by the absolute total;
        // peer idle time starts only when a fresh I/O/control wait is admitted.
        // Pending RPC, frame read/write and backpressure loops never call this.
        self.active = Instant::now();
    }
    fn remaining(&self) -> usize {
        let cap = if self.terminal_delivery { IPC_LIMIT } else { IPC_LIMIT - FRAME_LIMIT - 4 };
        cap.saturating_sub(self.bytes)
    }
    fn charge(&mut self, n: usize) -> Result<()> { if n > self.remaining() { return Err("host_budget".into()); } self.bytes += n; self.active = Instant::now(); Ok(()) }
    fn ready(&self, fd: i32, events: i16, wait: bool) -> Result<bool> {
        self.deadline()?;
        let mut item = PollFd { fd, events, revents: 0 }; let result = unsafe { poll(&mut item, 1, if wait { 20 } else { 0 }) };
        if result < 0 { if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted { return Ok(false); } return Err("host_io_failed".into()); }
        if item.revents & 32 != 0 { return Err("host_io_failed".into()); }
        Ok(result > 0 && item.revents & (events | 8 | 16) != 0)
    }
    fn read_exact(&mut self, buffer: &mut [u8], clean_eof: bool) -> Result<()> {
        let mut position = 0;
        while position < buffer.len() {
            let classify = |reason: String| if reason == "callback_timeout" && (!clean_eof || position > 0) { "host_protocol".into() } else { reason };
            self.deadline().map_err(&classify)?; if !self.ready(0, 1, true).map_err(&classify)? { continue; }
            let remaining = buffer.len() - position;
            if remaining > self.remaining() { return Err("host_budget".into()); }
            let n = unsafe { read(0, buffer[position..].as_mut_ptr(), remaining) };
            if n == 0 { self.input_closed = true; return Err(if clean_eof && position == 0 { "host_eof" } else { "host_protocol" }.into()); }
            if n < 0 { let kind = io::Error::last_os_error().kind(); if matches!(kind, io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock) { continue; } return Err("host_io_failed".into()); }
            self.charge(n as usize)?; position += n as usize;
        }
        Ok(())
    }
    fn receive(&mut self) -> Result<Json> {
        let mut header = [0; 4]; self.read_exact(&mut header, true)?; let length = u32::from_be_bytes(header) as usize;
        if length == 0 { return Err("host_protocol".into()); }
        if length > FRAME_LIMIT { return Err("host_budget".into()); }
        if length > self.remaining() { return Err("host_budget".into()); }
        let mut body = vec![0; length]; self.read_exact(&mut body, false)?;
        let value = wire_json::parse(&body).map_err(|_| "host_protocol")?;
        if get(&value, "v").and_then(Json::integer).map_err(|_| "host_protocol")? != 1 { return Err("host_protocol".into()); }
        Ok(value)
    }
    fn send(&mut self, value: &Json) -> Result<()> {
        let length = value.encoded_len()?;
        if length == 0 || length > FRAME_LIMIT || length.saturating_add(4) > self.remaining() { return Err("host_budget".into()); }
        let body = value.encode().into_bytes(); let mut bytes = Vec::with_capacity(length + 4); bytes.extend_from_slice(&(length as u32).to_be_bytes()); bytes.extend_from_slice(&body);
        let invoking = text(value, "kind").ok() == Some("invoke");
        let mut position = 0;
        while position < bytes.len() {
            // A full output pipe must never hide host Stop/close until idle timeout.
            if !self.input_closed && self.ready(0, 1, false)? {
                let incoming = self.receive()?;
                if !self.control(&incoming)? { return Err("callback_mismatch".into()); }
                return Err(self.shutdown.unwrap().error().into());
            }
            if !self.ready(1, 4, true)? { continue; }
            let n = unsafe { write(1, bytes[position..].as_ptr(), bytes.len() - position) };
            if n <= 0 { let kind = io::Error::last_os_error().kind(); if n < 0 && matches!(kind, io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock) { continue; } return Err("host_io_failed".into()); }
            position += n as usize;
            self.output_incomplete = position < bytes.len();
            if invoking { self.invoke_admitted = true; }
            self.charge(n as usize)?;
        }
        Ok(())
    }
    fn control(&mut self, value: &Json) -> Result<bool> {
        if !matches!(text(value, "kind")?, "cancel" | "close") { return Ok(false); }
        keys(value, &["v", "kind", "task_id", "attempt_id"])?;
        if text(value, "task_id")? != self.task || text(value, "attempt_id")? != self.attempt { return Err("callback_mismatch".into()); }
        if self.shutdown.is_none() { self.shutdown = Some(if text(value, "kind")? == "cancel" { Shutdown::Cancel } else { Shutdown::Close }); }
        Ok(true)
    }
    fn before_callback(&mut self) -> Result<()> {
        self.admit_wait();
        if let Some(stop) = self.shutdown { return Err(stop.error().into()); }
        if self.ready(0, 1, false)? { let value = self.receive()?; if !self.control(&value)? { return Err("callback_mismatch".into()); } }
        if let Some(stop) = self.shutdown { return Err(stop.error().into()); } Ok(())
    }
    fn exchange(&mut self, kind: &str, turn: u64, fields: Vec<(&str, Json)>, expected: &str, expected_fields: &[&str]) -> Result<Json> {
        self.before_callback()?;
        if self.next > 16 || !(1..=2).contains(&turn) { return Err("host_budget".into()); }
        let request_id = self.next; self.next += 1;
        let mut outgoing = vec![("v", number(1)), ("kind", string(kind)), ("request_id", number(request_id)), ("task_id", string(&self.task)), ("attempt_id", string(&self.attempt)), ("turn", number(turn))];
        outgoing.extend(fields);
        self.send(&object(outgoing))?;
        loop {
            let value = self.receive()?;
            if self.control(&value)? { if kind == "invoke" { continue; } return Err(self.shutdown.unwrap().error().into()); }
            // HOST_CORRELATION_GUARD: one outstanding callback, exact four-field echo.
            let echoed_request = get(&value, "request_id").and_then(Json::integer).map_err(|_| "host_protocol")?;
            let echoed_turn = get(&value, "turn").and_then(Json::integer).map_err(|_| "host_protocol")?;
            if echoed_request != request_id
                || text(&value, "task_id").map_err(|_| "host_protocol")? != self.task
                || text(&value, "attempt_id").map_err(|_| "host_protocol")? != self.attempt
                || echoed_turn != turn { return Err("callback_mismatch".into()); }
            let actual = text(&value, "kind")?;
            if actual == "callback_error" {
                keys(&value, &["v", "kind", "request_id", "task_id", "attempt_id", "turn", "code"])?;
                let code = text(&value, "code")?;
                if !matches!(code, "model_denied" | "model_confirmation_required" | "model_failed" | "tool_denied" | "tool_confirmation_required" | "tool_failed" | "projection_rejected") { return Err("host_protocol".into()); }
                return Err(code.into());
            }
            if actual != expected { return Err("callback_mismatch".into()); }
            let mut allowed = vec!["v", "kind", "request_id", "task_id", "attempt_id", "turn"]; allowed.extend_from_slice(expected_fields); keys(&value, &allowed)?;
            return Ok(value);
        }
    }
}
type SharedTransport = Rc<RefCell<Transport>>;
type SharedHistory = Rc<RefCell<Vec<Json>>>;
struct CallbackProvider { io: SharedTransport, history: SharedHistory, tool: Json }
impl Provider for CallbackProvider {
    fn respond(&mut self, request: &ModelRequest, _position: usize) -> Result<ModelEvent> {
        let history = self.history.borrow().clone(); if history.len() > 8 { return Err("host_budget".into()); }
        let tools = if request.turn == 1 { vec![self.tool.clone()] } else { Vec::new() };
        let response = self.io.borrow_mut().exchange("model_request", request.turn, vec![("messages", Json::Array(history)), ("tools", Json::Array(tools))], "model_reply", &["reply"])?;
        let reply = get(&response, "reply")?;
        match text(reply, "kind")? {
            "answer" => { keys(reply, &["kind", "text"])?; let answer = text(reply, "text")?; if answer.len() > 16384 { return Err("host_budget".into()); } Ok(ModelEvent::Answer(answer.into())) },
            "tool" => {
                keys(reply, &["kind", "call_id", "name", "arguments"])?;
                let call = text(reply, "call_id")?; let name = text(reply, "name")?; let arguments = get(reply, "arguments")?; keys(arguments, &["type", "id"])?;
                let kind = text(arguments, "type")?;
                let id = text(arguments, "id")?;
                if !call_id(call) || name != "inquiry.object" || !object_type(kind) || !metadata(id) || arguments.encoded_len()? > 8192 { return Err("model_failed".into()); }
                let values = get(get(get(&self.tool, "parameters")?, "properties")?, "type")?;
                if !get(values, "enum")?.array()?.contains(&string(kind)) { return Err("model_failed".into()); }
                Ok(ModelEvent::HostTool { call_ref: call.into(), name: name.into(), arguments: arguments.clone() })
            },
            _ => Err("host_protocol".into()),
        }
    }
}
#[derive(Clone)]
struct CallbackPorts { io: SharedTransport }
fn invocation_fields(call: &HostInvocation) -> Vec<(&'static str, Json)> { vec![("invocation_id", string(&call.invocation_id)), ("call_id", string(&call.call_id)), ("tool", string(&call.tool)), ("arguments", call.arguments.clone())] }
impl HostAuthorizer for CallbackPorts {
    fn prepare(&mut self, call: &HostInvocation) -> Result<PrepareDecision> {
        let response = self.io.borrow_mut().exchange("prepare", call.turn, invocation_fields(call), "decision", &["invocation_id", "decision", "prepared_ref"])?;
        if text(&response, "invocation_id")? != call.invocation_id { return Err("callback_mismatch".into()); }
        match text(&response, "decision")? {
            "permit" => { let reference = text(&response, "prepared_ref")?; if !opaque(reference) { return Err("host_protocol".into()); } Ok(PrepareDecision::Permit(PreparedInvocation { invocation: call.clone(), prepared_ref: reference.into() })) },
            "denied" | "confirmation_required" if get(&response, "prepared_ref")? == &Json::Null => Ok(if text(&response, "decision")? == "denied" { PrepareDecision::Denied } else { PrepareDecision::ConfirmationRequired }),
            _ => Err("host_protocol".into()),
        }
    }
}
impl HostToolPort for CallbackPorts {
    fn invoke(&mut self, prepared: &PreparedInvocation) -> Result<ProjectedToolResult> {
        let mut fields = invocation_fields(&prepared.invocation); fields.push(("prepared_ref", string(&prepared.prepared_ref)));
        let response = self.io.borrow_mut().exchange("invoke", prepared.invocation.turn, fields, "tool_result", &["invocation_id", "prepared_ref", "receipt_ref", "projection"])?;
        ProjectedToolResult::parse(&response, prepared).map_err(|reason| match reason.as_str() { "callback_mismatch" | "host_budget" | "host_protocol" => reason, _ => "projection_rejected".into() })
    }
}

/// Authorization and tool ports injected into Agent's common model/admission loop.
pub struct HostPorts {
    pub authorizer: Box<dyn HostAuthorizer>, pub tool: Box<dyn HostToolPort>,
    io: SharedTransport, history: SharedHistory, pub result: Option<ProjectedToolResult>, pub invocations: u64, invoke_pending: bool, current: Option<HostInvocation>,
}
impl HostPorts {
    pub fn persist(&self, agent: &Agent) -> Result<()> {
        let mut journal = self.terminal(&agent.state).object()?.clone();
        journal.insert("scope_ref".into(), string(&agent.state.scope));
        journal.insert("binding".into(), self.current.as_ref().map(|call| object([
            ("invocation_id", string(&call.invocation_id)), ("task_id", string(&call.task_id)), ("attempt_id", string(&call.attempt_id)),
            ("scope_ref", string(&call.scope_ref)), ("turn", number(call.turn)), ("call_id", string(&call.call_id)), ("tool", string(&call.tool)), ("arguments", call.arguments.clone()),
        ])).unwrap_or(Json::Null));
        store::atomic(&agent.dir, "host.db", &Json::Object(journal).encode()).map_err(|_| "host_journal_failed".into())
    }
    pub fn check_control(&mut self) -> Result<()> { self.io.borrow_mut().before_callback() }
    pub fn admit_answer(&self, state: &State, answer: &str) -> Result<()> {
        let mut terminal_state = state.clone();
        terminal_state.status = "completed".into(); terminal_state.reason.clear(); terminal_state.answer = answer.into();
        if self.terminal(&terminal_state).encoded_len()? > FRAME_LIMIT { return Err("host_budget".into()); }
        Ok(())
    }
    pub fn dispatch(&mut self, agent: &mut Agent, call_ref: String, name: String, arguments: Json) -> Result<()> {
        if agent.state.counters.steps != 1 || self.invocations != 0 { return Err("unsupported_tool_turn".into()); }
        let call = HostInvocation::issue(&agent.state, call_ref, name, arguments)?;
        self.current = Some(call.clone()); self.persist(agent)?;
        let prepared = match self.authorizer.prepare(&call)? { PrepareDecision::Denied => return Err("tool_denied".into()), PrepareDecision::ConfirmationRequired => return Err("core_confirmation_required".into()), PrepareDecision::Permit(value) => value };
        if prepared.invocation != call || !opaque(&prepared.prepared_ref) { return Err("host_protocol".into()); }
        self.check_control()?;
        if crate::model::context_bytes(&agent.state.context).saturating_add(call.arguments.encoded_len()? as u64).saturating_add(8192) > agent.state.limits.context { return Err("host_budget".into()); }
        self.invocations += 1; self.invoke_pending = true;
        agent.state.status = "interrupted".into(); agent.state.reason = "tool_outcome_unknown".into(); self.persist(agent)?;
        let result = match self.tool.invoke(&prepared) {
            Ok(result) => result,
            Err(reason) => {
                if !self.io.borrow().invoke_admitted { self.invocations = 0; self.invoke_pending = false; }
                return Err(reason);
            },
        };
        self.invoke_pending = false;
        let projection = result.projection().encode();
        let call_message = object([("role", string("assistant")), ("content", string("")), ("tool_calls", Json::Array(vec![object([
            ("id", string(&call.call_id)), ("type", string("function")), ("function", object([("name", string(&call.tool)), ("arguments", string(call.arguments.encode()))])),
        ])]))]);
        let tool_message = object([("role", string("tool")), ("content", string(&projection)), ("tool_call_id", string(&call.call_id))]);
        { let mut history = self.history.borrow_mut(); if history.len().saturating_add(2) > 8 { return Err("host_budget".into()); } history.push(call_message); history.push(tool_message); }
        agent.state.context.push(Message { role: Role::Assistant, text: call.arguments.encode() }); agent.state.context.push(Message { role: Role::Tool, text: projection });
        self.result = Some(result); agent.state.status = "ready".into(); agent.state.reason.clear(); self.persist(agent)?; self.check_control()
    }
    pub fn failure(&mut self, state: &mut State, reason: &str) {
        let (status, code) = match reason {
            "host_eof" | "callback_timeout" | "host_io_failed" | "host_protocol" | "callback_mismatch" | "host_budget" | "cancel_requested" | "host_closed" if self.invoke_pending => ("interrupted", "tool_outcome_unknown"),
            "host_budget" => ("budget_exhausted", "host_budget"), "cancel_requested" => ("cancelled", "cancel_requested"), "host_closed" => ("interrupted", "host_closed"),
            "model_denied" | "tool_denied" => ("denied", reason),
            "core_confirmation_required" | "model_confirmation_required" | "tool_confirmation_required" => ("denied", "core_confirmation_required"),
            "host_eof" => ("interrupted", "host_eof"),
            "callback_timeout" | "callback_mismatch" | "projection_rejected" | "unsupported_tool_turn" | "model_failed" | "tool_failed" | "host_journal_failed" | "host_identity_unavailable" | "host_protocol" => ("failed", reason),
            _ => ("failed", "host_protocol"),
        };
        state.status = status.into(); state.reason = code.into(); state.answer.clear();
    }
    fn delivery_failure(&mut self, state: &mut State, reason: &str) {
        if matches!(reason, "cancel_requested" | "host_closed") {
            // Only this send's actual control cause may change the decision;
            // an old shutdown latch is not evidence of a new delivery event.
            self.failure(state, reason);
        } else if !matches!(state.status.as_str(), "failed" | "denied" | "cancelled" | "interrupted" | "budget_exhausted") {
            // A completed answer is still unofficial if delivery fails. Once
            // failure is established, later EOF/I/O cannot replace its cause.
            self.failure(state, reason);
        }
    }
    fn terminal(&self, state: &State) -> Json {
        let (receipt, projection) = match &self.result { Some(result) => (string(&result.receipt_ref), result.projection()), None => (Json::Null, Json::Null) };
        object([
            ("v", number(1)), ("kind", string("terminal")), ("task_id", string(&state.task)), ("attempt_id", string(&state.attempt)),
            ("status", string(&state.status)), ("reason", string(if state.reason.is_empty() { "complete" } else { &state.reason })),
            ("answer", if state.status == "completed" { string(&state.answer) } else { Json::Null }),
            ("receipt_ref", receipt), ("projection", projection), ("model_turns", number(state.counters.calls)), ("tool_invocations", number(self.invocations)),
        ])
    }
}
fn session_dir(root: &Path, start: &HostStart) -> Result<PathBuf> {
    let task = root.join(&start.task_id);
    match fs::symlink_metadata(&task) { Ok(_) => store::validate_dir(&task).map_err(|_| "host_state_invalid")?, Err(e) if e.kind() == io::ErrorKind::NotFound => store::create_dir(&task).map_err(|_| "host_state_invalid")?, Err(_) => return Err("host_state_invalid".into()) }
    let attempt = task.join(&start.attempt_id); store::create_dir(&attempt).map_err(|_| "host_attempt_exists")?; Ok(attempt)
}
pub fn run_stdio(config: HostSessionConfig) -> Result<()> {
    if !cfg!(target_os = "linux") { return Err("host_platform_unsupported".into()); }
    let mut transport = Transport::new(&config)?; config.validate()?; transport.admit_wait();
    let start = HostStart::parse(&transport.receive()?).map_err(|_| "host_start_invalid")?;
    transport.task = start.task_id.clone(); transport.attempt = start.attempt_id.clone();
    let dir = session_dir(&config.root, &start)?; let _guard = store::lock(&dir).map_err(|_| "host_state_invalid")?;
    let mut agent = Agent { dir, state: start.state() };
    let history = Rc::new(RefCell::new(vec![object([("role", string("user")), ("content", string(&start.prompt))])]));
    let shared = Rc::new(RefCell::new(transport)); let callbacks = CallbackPorts { io: shared.clone() };
    let mut provider = CallbackProvider { io: shared.clone(), history: history.clone(), tool: start.tool };
    let mut ports = HostPorts { authorizer: Box::new(callbacks.clone()), tool: Box::new(callbacks), io: shared.clone(), history, result: None, invocations: 0, invoke_pending: false, current: None };
    ports.persist(&agent)?;
    if let Err(reason) = agent.run_with_ports(&mut provider, &mut ports, &Hooks::default()) { ports.failure(&mut agent.state, &reason); }
    ports.persist(&agent)?;
    // Appending another frame to an incomplete frame would fabricate a protocol.
    // The truthful journal and host's own control request remain authoritative.
    if shared.borrow().output_incomplete { return Err("host_partial_output".into()); }
    // Reserve bytes and time for this terminal inside the original total budget.
    shared.borrow_mut().terminal_delivery = true;
    let terminal = ports.terminal(&agent.state);
    let sent = shared.borrow_mut().send(&terminal);
    match sent {
        Ok(()) => Ok(()),
        Err(reason) => {
            // Final delivery is still part of the controlled session. A consumed
            // Stop/close must replace the pre-delivery completed projection,
            // retaining the genuine original tool result in the journal.
            ports.delivery_failure(&mut agent.state, &reason);
            ports.persist(&agent)?;
            if shared.borrow().output_incomplete { return Err("host_partial_output".into()); }
            // No byte of this terminal was emitted. One corrected terminal may
            // be sent inside the same original time/byte bounds; never retry a
            // partially emitted frame or start another callback.
            let corrected = ports.terminal(&agent.state);
            let retry = shared.borrow_mut().send(&corrected);
            if let Err(failure) = &retry {
                ports.delivery_failure(&mut agent.state, failure);
                ports.persist(&agent)?;
            }
            if shared.borrow().output_incomplete { return Err("host_partial_output".into()); }
            retry
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fresh_admission_excludes_host_work_from_idle_without_resetting_total() {
        let now = Instant::now();
        // Clock-only instance: no descriptor was opened or changed, so suppress
        // the fd-restoring Drop while testing deadline policy without I/O/sleeps.
        let mut timer = std::mem::ManuallyDrop::new(Transport {
            started: now, active: now - Duration::from_secs(2), idle: Duration::from_secs(1), total: Duration::from_secs(10),
            bytes: 0, task: String::new(), attempt: String::new(), next: 1, shutdown: None, terminal_delivery: false,
            invoke_admitted: false, output_incomplete: false, input_closed: false, old_flags: [0; 2],
        });
        assert_eq!(timer.deadline(), Err("callback_timeout".into()));
        timer.admit_wait();
        assert_eq!(timer.deadline(), Ok(()), "host-owned work must not count as a silent peer wait");
        assert_eq!(timer.started, now, "fresh admission never resets the attempt total");
        timer.active = now - Duration::from_secs(2);
        assert_eq!(timer.deadline(), Err("callback_timeout".into()), "a pending silent wait still exhausts idle");
        timer.started = now - Duration::from_secs(11);
        timer.admit_wait();
        assert_eq!(timer.deadline(), Err("callback_timeout".into()), "admission cannot revive an exhausted total");
    }
    #[test]
    fn invocation_identity_distinguishes_attempts_in_the_same_process() {
        let start = HostStart { task_id: "t-one".into(), attempt_id: "a-one".into(), scope_ref: "scope:one".into(), prompt: String::new(), tool: Json::Null };
        let mut first = start.state(); first.counters.steps = 1;
        let mut second = first.clone(); second.task = "t-two".into(); second.attempt = "a-two".into();
        let args = object([("type", string("supplier")), ("id", string("synthetic-id"))]);
        let a = HostInvocation::issue(&first, "same-model-id".into(), "inquiry.object".into(), args.clone()).unwrap();
        let b = HostInvocation::issue(&second, "same-model-id".into(), "inquiry.object".into(), args.clone()).unwrap();
        assert_ne!(a.invocation_id, b.invocation_id);
        assert_eq!((&a.task_id, &a.attempt_id, a.turn), (&first.task, &first.attempt, 1));
        assert_eq!((&b.task_id, &b.attempt_id, b.turn), (&second.task, &second.attempt, 1));
        assert_eq!(a.arguments, args); assert_eq!(b.arguments, args);
        assert_ne!(a.invocation_id, a.call_id);
    }
    #[test]
    fn incomplete_entropy_fails_closed_without_a_pid_or_time_fallback() {
        let mut unavailable = std::io::Cursor::new(vec![0u8; 31]);
        assert_eq!(nonce_identity(&mut unavailable), Err("host_identity_unavailable".into()));
    }
}
