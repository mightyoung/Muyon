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

use crate::{field, service_runtime::RunControl, supplier_scope_bridge::{HostSupplierScopeBridge, HostSupplierSource}, supplier_store::{SupplierReader, SupplierReadResult}};
use muyon_plugin_contract_lab::{object, string, Json};
use std::{path::Path, rc::Rc};
impl ServiceHostMode {
    pub(crate) fn label(self) -> &'static str { match self { Self::LocalRead => "host-local-read", Self::ConfiguredChat => "configured-chat" } }
    pub(crate) fn parse(value: &str) -> Result<Self> { match value { "host-local-read" => Ok(Self::LocalRead), "configured-chat" => Ok(Self::ConfiguredChat), _ => Err("host_mode_invalid".into()) } }
}
impl ServiceHostScope {
    fn binding(&self) -> Result<Json> {
        Ok(object([
            ("source_identity",string(&self.source_identity)), ("namespace",string(&self.namespace)),
            ("managed_root",string(self.managed_root.to_str().ok_or("host_path_invalid")?)),
            ("database",string(self.database.to_str().ok_or("host_path_invalid")?)),
            ("source_revision",string(&self.decision.source_revision)),
        ]))
    }
}
impl ServiceHostPorts {
    pub(crate) fn source_binding(&self) -> Result<Json> { self.owner.current_scope()?.binding() }
    fn reader(&self, dir: &Path, key: &str, revision: &str, expected: &Json) -> Result<SupplierReader> {
        let scope=self.owner.current_scope()?;
        if self.mode != ServiceHostMode::LocalRead || &scope.binding()? != expected
            || scope.decision.selected.len()!=1 || scope.decision.selected[0].key!=key || scope.decision.selected[0].revision!=revision {
            return Err("host_source_binding_changed".into());
        }
        let source=HostSupplierSource::new(&scope.source_identity,&scope.namespace,&scope.managed_root,&scope.database)?;
        let owner=self.owner.clone(); let expected=expected.clone(); let key=key.to_owned();let revision=revision.to_owned();
        let bridge=HostSupplierScopeBridge::new(source,Rc::new(move || {
            let current=owner.current_scope()?;
            if current.binding()?!=expected || current.decision.selected.len()!=1 || current.decision.selected[0].key!=key || current.decision.selected[0].revision!=revision {
                return Err("host_source_binding_changed".into());
            }
            Ok(current.decision)
        }))?;
        SupplierReader::install_host_scope_in_run(dir,&scope.decision.selected[0].key,Rc::new(bridge))
    }
    pub(crate) fn read_admitted(&self, dir: &Path, payload: &Json, binding: &Json, control: Arc<RunControl>, admitted: impl FnOnce(&muyon_core_agent_lab::agent::State)->Result<()>) -> Result<SupplierReadResult> {
        let key=field(payload,"key")?.string()?; let revision=field(payload,"revision")?.string()?;
        let reader=self.reader(dir,key,revision,binding)?;
        reader.read_in_run_admitted(dir,field(payload,"text")?.string()?,key,control,admitted)
    }
    pub(crate) fn validate(&self,dir:&Path,payload:&Json,binding:&Json,projection:Option<&Json>)->Result<()> {
        let reader=self.reader(dir,field(payload,"key")?.string()?,field(payload,"revision")?.string()?,binding)?;
        if let Some(projection)=projection { reader.validate_current_projection(projection)?; }
        Ok(())
    }
    pub(crate) fn configured_readiness(&self)->Result<()> {
        let bridge=self.owner.provider().map_err(|_|"configured_profile_unavailable".to_owned())?;
        bridge.readiness(&self.budget)?;
        // No INTERNET permission or authorized transport exists in this slice.
        Err("configured_transport_unavailable".into())
    }
}
