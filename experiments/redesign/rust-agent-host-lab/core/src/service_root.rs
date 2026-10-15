//! Sole Service root lease and durable admission index. No handler or Agent loop.
use crate::{service_types::*, Result};
use std::path::{Path, PathBuf};
pub struct ServiceRoot;
impl ServiceRoot {
    pub fn open(_private_root: &Path) -> Result<Self> { eprintln!("SERVICE_ROOT_STUB_REACHED"); Err("service_root_stub".into()) }
    pub fn admit(&mut self, _intent: AgentIntentBinding, _epoch: &str) -> Result<AgentDurableRun> { Err("service_root_stub".into()) }
    pub fn attach_task(&mut self, _run: &str, _task: AgentTaskIdentity) -> Result<()> { Err("service_root_stub".into()) }
    pub fn run_dir(&self, _run: &str) -> Result<PathBuf> { Err("service_root_stub".into()) }
    pub fn runs(&self) -> &[AgentDurableRun] { &[] }
    pub fn recovery_required(&self) -> bool { true }
}
