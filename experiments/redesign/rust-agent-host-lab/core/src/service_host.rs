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
    fn chat_authority(&self, _conversation: &str, _text: &str) -> Result<crate::ordinary_chat::ChatAuthority> { Err("chat_authority_unconfigured".into()) }
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
use std::{fs::{Metadata, OpenOptions}, os::unix::fs::{MetadataExt, OpenOptionsExt}, path::Path, rc::Rc};
impl ServiceHostMode {
    pub(crate) fn label(self) -> &'static str { match self { Self::LocalRead => "host-local-read", Self::ConfiguredChat => "configured-chat" } }
    pub(crate) fn parse(value: &str) -> Result<Self> { match value { "host-local-read" => Ok(Self::LocalRead), "configured-chat" => Ok(Self::ConfiguredChat), _ => Err("host_mode_invalid".into()) } }
}
// Capture metadata only. No SQLite value or credential bytes are read here.
// The supported Service targets are Linux/Android; 0x20000 is O_NOFOLLOW on
// both, matching supplier_lab_source's existing readonly-open pattern.
fn physical_identity(path: &Path, metadata: &Metadata) -> Result<Json> {
    Ok(object([
        ("path", string(path.to_str().ok_or("host_path_invalid")?)),
        ("dev", Json::Number(metadata.dev().to_string())),
        ("ino", Json::Number(metadata.ino().to_string())),
        ("uid", Json::Number(metadata.uid().to_string())),
        ("mode", Json::Number(metadata.mode().to_string())),
    ]))
}
fn source_lineage(database: &Path) -> Result<Json> {
    let mut path=PathBuf::new();
    let mut sampled=Vec::new();
    let components: Vec<_>=database.components().collect();
    if components.is_empty() || components.len()>128 { return Err("host_source_lineage_invalid".into()); }
    for (index, component) in components.iter().enumerate() {
        path.push(component.as_os_str());
        let metadata=std::fs::symlink_metadata(&path).map_err(|_|"host_source_unavailable")?;
        let directory=index+1!=components.len();
        if metadata.file_type().is_symlink() || (directory && !metadata.is_dir()) || (!directory && !metadata.is_file()) {
            return Err("host_source_lineage_invalid".into());
        }
        sampled.push((path.clone(),physical_identity(&path,&metadata)?));
    }
    // Tie the database sample to an actual readonly open with no final symlink
    // following, then resample every ancestor to reject replacements during capture.
    let file=OpenOptions::new().read(true).custom_flags(0x20000).open(database).map_err(|_|"host_source_unavailable")?;
    let opened=file.metadata().map_err(|_|"host_source_unavailable")?;
    if !opened.is_file() || physical_identity(database,&opened)?!=sampled.last().ok_or("host_source_lineage_invalid")?.1 {
        return Err("host_source_lineage_changed".into());
    }
    for (path, expected) in &sampled {
        let current=std::fs::symlink_metadata(path).map_err(|_|"host_source_unavailable")?;
        if &physical_identity(path,&current)?!=expected { return Err("host_source_lineage_changed".into()); }
    }
    Ok(Json::Array(sampled.into_iter().map(|(_,identity)|identity).collect()))
}
impl ServiceHostScope {
    fn binding(&self) -> Result<Json> {
        HostSupplierSource::new(&self.source_identity,&self.namespace,&self.managed_root,&self.database)?;
        Ok(object([
            ("source_identity",string(&self.source_identity)), ("namespace",string(&self.namespace)),
            ("managed_root",string(self.managed_root.to_str().ok_or("host_path_invalid")?)),
            ("database",string(self.database.to_str().ok_or("host_path_invalid")?)),
            ("source_revision",string(&self.decision.source_revision)),
            ("lineage",source_lineage(&self.database)?),
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

/// Fixed metadata-only operations available to trusted Service bootstrap. These
/// never take caller payloads, budgets, authority fields or send capabilities.
#[derive(Clone, Copy)]
pub enum ServiceAdmissionProbeOperation {
    PrimaryCommit, PrimaryCancel, SecondaryCommit, SecondaryCancel, TertiaryCommit,
}
pub struct ServiceAdmissionProbeReply {
    pub admitted: bool,
    pub record_id: String,
    pub code: String,
}
impl ServiceAdmissionProbeReply {
    pub(crate) fn rejected(code: &str) -> Self {
        Self { admitted: false, record_id: String::new(), code: code.into() }
    }
}
impl ServiceHostPorts {
    pub(crate) fn admission_probe(&self, operation: ServiceAdmissionProbeOperation) -> ServiceAdmissionProbeReply {
        use ServiceAdmissionProbeOperation::*;
        let (request, cancel) = match operation {
            PrimaryCommit => ("service-lifecycle-primary-v1", false),
            PrimaryCancel => ("service-lifecycle-primary-v1", true),
            SecondaryCommit => ("service-lifecycle-secondary-v1", false),
            SecondaryCancel => ("service-lifecycle-secondary-v1", true),
            TertiaryCommit => ("service-lifecycle-tertiary-v1", false),
        };
        const PAYLOAD: &[u8] = br#"{"model":"service-lifecycle-fixture-model","messages":[{"role":"user","content":"synthetic admission metadata probe"}],"max_tokens":8,"n":1}"#;
        let budget = CallBudget { max_tokens: 32, max_micros: 4,
            requires_tools: false, requires_streaming: false };
        let bridge = match self.owner.provider() {
            Ok(bridge) => bridge,
            Err(_) => return ServiceAdmissionProbeReply::rejected("service_probe_provider_unavailable"),
        };
        let prepared = match bridge.prepare(request, PAYLOAD, budget) {
            Ok(prepared) => prepared,
            Err(code) => return ServiceAdmissionProbeReply::rejected(&code),
        };
        if cancel {
            drop(prepared);
            return ServiceAdmissionProbeReply::rejected("release_requested");
        }
        match bridge.final_admit(prepared) {
            Ok(admission) => ServiceAdmissionProbeReply { admitted: true,
                record_id: admission.record_id().into(), code: "admitted_metadata_only".into() },
            Err(code) => ServiceAdmissionProbeReply::rejected(&code),
        }
    }
}
