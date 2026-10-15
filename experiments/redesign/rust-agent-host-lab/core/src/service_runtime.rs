//! Rust-owned synthetic read composition. Never exported as a UI runtime entry.
use crate::{service_types::AgentReadVariant, Json, Result};
use muyon_core_agent_lab::agent::State;
use std::{
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    time::{Duration, Instant},
};
pub struct RunControl {
    cancelled: AtomicBool,
    deadline: Instant,
}
impl RunControl {
    pub fn new() -> Self {
        Self {
            cancelled: AtomicBool::new(false),
            deadline: Instant::now() + Duration::from_secs(5),
        }
    }
    pub fn request_cancel(&self) {
        self.cancelled.store(true, Ordering::Release)
    }
    pub fn poll(&self) -> Result<()> {
        if self.cancelled.load(Ordering::Acquire) {
            Err("native_cancelled".into())
        } else if Instant::now() >= self.deadline {
            Err("native_deadline".into())
        } else {
            Ok(())
        }
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
pub fn run_builtin(
    _dir: &Path,
    _variant: AgentReadVariant,
    _control: Arc<RunControl>,
) -> Result<BuiltinExecution> {
    eprintln!("SERVICE_RUNTIME_STUB_REACHED");
    Err("service_runtime_stub".into())
}
