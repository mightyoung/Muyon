//! Trusted Service injection. No UI or FFI deserialization of owner ports.
use crate::{service_provider::{CallBudget, ServiceProviderBridge}, supplier_scope_bridge::SupplierScopeDecision};
use muyon_core_agent_lab::Result;
use std::{path::PathBuf, sync::Arc};
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ServiceHostMode { LocalRead, ConfiguredChat }
pub struct ServiceHostScope {
    pub source_identity: String,
    pub namespace: String,
    pub managed_root: PathBuf,
    pub database: PathBuf,
    pub decision: SupplierScopeDecision,
}
/// Construct thread-local Rc adapters from a trusted cross-thread owner.
pub trait ServiceHostOwner: Send + Sync {
    fn current_scope(&self) -> Result<ServiceHostScope>;
    fn provider(&self) -> Result<ServiceProviderBridge>;
}
pub struct ServiceHostPorts {
    pub(crate) owner: Arc<dyn ServiceHostOwner>,
    pub(crate) mode: ServiceHostMode,
    pub(crate) budget: CallBudget,
}
impl ServiceHostPorts {
    pub fn new(owner: Arc<dyn ServiceHostOwner>, mode: ServiceHostMode, budget: CallBudget) -> Self {
        Self { owner, mode, budget }
    }
}
