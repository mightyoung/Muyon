//! Experimental default-off product host boundary.
//!
//! This checkpoint intentionally supplies only the compilable protocol surface.
//! It performs no model, authorization or tool callback and has no agent loop.
use crate::{Result, wire_json::{self, Json, object, string}};
use std::{io::{Read, Write}, path::PathBuf};

pub const FRAME_LIMIT: usize = 65536;
pub const IPC_LIMIT: usize = 262144;

#[derive(Clone, Debug)]
pub struct HostSessionConfig {
    pub root: PathBuf,
    pub idle_ms: u64,
    pub total_ms: u64,
}
impl HostSessionConfig {
    pub fn validate(&self) -> Result<()> {
        if !self.root.is_absolute() || !self.root.is_dir()
            || !(1..=5000).contains(&self.idle_ms) || !(1..=30000).contains(&self.total_ms) {
            return Err("host_config_invalid".into());
        }
        Ok(())
    }
}

/// Metadata projection only. The original result and receipt stay in the host.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProjectedObjectRef {
    pub module_id: String,
    pub object_type: String,
    pub object_id: String,
    pub revision_ref: Option<String>,
    pub content_digest: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProjectedToolResult {
    pub invocation_id: String,
    pub prepared_ref: String,
    pub receipt_ref: String,
    pub object_ref: ProjectedObjectRef,
}

#[derive(Clone, Debug)]
pub struct HostStart {
    pub task_id: String,
    pub attempt_id: String,
    pub scope_ref: String,
    pub prompt: String,
    pub tool: Json,
}
impl HostStart {
    pub fn parse(value: &Json) -> Result<Self> {
        let fields = value.object().map_err(|_| "host_start_invalid")?;
        let keys = ["v", "kind", "task_id", "attempt_id", "scope_ref", "prompt", "tool"];
        if fields.len() != keys.len() || keys.iter().any(|key| !fields.contains_key(*key)) {
            return Err("host_start_invalid".into());
        }
        let get = |key: &str| fields.get(key).ok_or_else(|| "host_start_invalid".to_string());
        if get("v")?.integer()? != 1 || get("kind")?.string()? != "start" {
            return Err("host_start_invalid".into());
        }
        let task_id = get("task_id")?.string()?.to_string();
        let attempt_id = get("attempt_id")?.string()?.to_string();
        let safe_id = |s: &str| !s.is_empty() && s.len() <= 96 && s.bytes().all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b));
        if !safe_id(&task_id) || !safe_id(&attempt_id) { return Err("host_start_invalid".into()); }
        let scope_ref = get("scope_ref")?.string()?.to_string();
        let prompt = get("prompt")?.string()?.to_string();
        if scope_ref.is_empty() || scope_ref.len() > 128 || prompt.len() > 8192 {
            return Err("host_start_invalid".into());
        }
        let tool = get("tool")?.clone();
        tool.object().map_err(|_| "host_start_invalid")?;
        Ok(Self { task_id, attempt_id, scope_ref, prompt, tool })
    }
}

fn read_start(input: &mut dyn Read) -> Result<HostStart> {
    let mut header = [0u8; 4];
    input.read_exact(&mut header).map_err(|_| "host_frame_invalid")?;
    let length = u32::from_be_bytes(header) as usize;
    if !(1..=FRAME_LIMIT).contains(&length) { return Err("host_frame_invalid".into()); }
    let mut body = vec![0; length];
    input.read_exact(&mut body).map_err(|_| "host_frame_invalid")?;
    let value = wire_json::parse(&body).map_err(|_| "host_frame_invalid")?;
    HostStart::parse(&value).map_err(|_| "host_start_invalid".into())
}

/// Deliberately unavailable until the fixed compiling RED checkpoint is observed.
pub fn run_stdio(config: HostSessionConfig) -> Result<()> {
    config.validate()?;
    let start = read_start(&mut std::io::stdin().lock())?;
    let terminal = object([
        ("v", Json::Number("1".into())), ("kind", string("terminal")),
        ("task_id", string(start.task_id)), ("attempt_id", string(start.attempt_id)),
        ("status", string("failed")), ("reason", string("host_not_implemented")),
        ("answer", Json::Null), ("receipt_ref", Json::Null), ("projection", Json::Null),
        ("model_turns", Json::Number("0".into())), ("tool_invocations", Json::Number("0".into())),
    ]).encode().into_bytes();
    let mut output = std::io::stdout().lock();
    output.write_all(&(terminal.len() as u32).to_be_bytes()).map_err(|_| "host_output_failed")?;
    output.write_all(&terminal).map_err(|_| "host_output_failed")?;
    output.flush().map_err(|_| "host_output_failed".into())
}
