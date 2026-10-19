//! Thin typed Service boundary. Existing stateless diagnostic API is separate.
use muyon_rust_agent_host_lab::service_types as host;
use std::sync::Arc;
trait ToHost {
    type Host;
    fn to_host(self) -> Self::Host;
}
trait ToBridge {
    type Bridge;
    fn to_bridge(self) -> Self::Bridge;
}
macro_rules! identity_conversion { ($($ty:ty),*) => { $(
 impl ToHost for $ty { type Host=Self; fn to_host(self)->Self {self} }
 impl ToBridge for $ty { type Bridge=Self; fn to_bridge(self)->Self {self} }
)* }; }
identity_conversion!(String, u32, i64, bool);
impl<T: ToHost> ToHost for Option<T> {
    type Host = Option<T::Host>;
    fn to_host(self) -> Self::Host {
        self.map(ToHost::to_host)
    }
}
impl<T: ToBridge> ToBridge for Option<T> {
    type Bridge = Option<T::Bridge>;
    fn to_bridge(self) -> Self::Bridge {
        self.map(ToBridge::to_bridge)
    }
}
macro_rules! service_record {
 ($name:ident {$($field:ident:$ty:ty),*}) => {
  #[derive(Clone,Debug,PartialEq,Eq,uniffi::Record)]
  pub struct $name {$(pub $field:$ty),*}
  impl ToHost for $name {type Host=host::$name;fn to_host(self)->Self::Host{host::$name{$($field:self.$field.to_host()),*}}}
  impl ToBridge for host::$name {type Bridge=$name;fn to_bridge(self)->Self::Bridge{$name{$($field:self.$field.to_bridge()),*}}}
 };
}
macro_rules! service_enum {
 ($name:ident {$($variant:ident $({$($field:ident:$ty:ty),*})?),*}) => {
  #[derive(Clone,Debug,PartialEq,Eq,uniffi::Enum)]
  pub enum $name {$($variant $({$($field:$ty),*})?),*}
  impl ToHost for $name {type Host=host::$name;fn to_host(self)->Self::Host{match self {$(Self::$variant $({$($field),*})?=>host::$name::$variant $({$($field:$field.to_host()),*})?),*}}}
  impl ToBridge for host::$name {type Bridge=$name;fn to_bridge(self)->Self::Bridge{match self {$(Self::$variant $({$($field),*})?=>$name::$variant $({$($field:$field.to_bridge()),*})?),*}}}
 };
}
muyon_rust_agent_host_lab::define_agent_service_types!(service_record, service_enum);
// Service bootstrap alone supplies this config; source identity is compile-bound.
#[derive(Clone, Debug, uniffi::Record)]
pub struct AgentServiceConfig {
    pub protocol: u32,
    pub private_root: String,
}
#[derive(Clone, Debug, uniffi::Error)]
pub enum AgentServiceSetupError {
    UnsupportedProtocol,
    InvalidRoot,
    Busy,
    RecoveryRequired,
    InternalFailure,
}
impl std::fmt::Display for AgentServiceSetupError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("agent_service_setup_failure")
    }
}
impl std::error::Error for AgentServiceSetupError {}
/// Trusted Service bootstrap only. No Binder command selects this operation.
#[derive(Clone, Debug, uniffi::Enum)]
pub enum ServiceAdmissionProbeOperation {
    PrimaryCommit, PrimaryCancel, SecondaryCommit, SecondaryCancel, TertiaryCommit,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct ServiceAdmissionProbeReply {
    pub admitted: bool, pub record_id: String, pub code: String,
}
#[derive(uniffi::Object)]
pub struct AgentServiceController {
    inner: muyon_rust_agent_host_lab::service_controller::AgentServiceController,
}
#[uniffi::export]
impl AgentServiceController {
    /// Private Service bootstrap injection. Never populated from UI or Binder request fields.
    #[uniffi::constructor]
    pub fn with_host(
        config: AgentServiceConfig,
        owner: Arc<dyn crate::service_host_bridge::ServiceHostOwnerCallback>,
        mode: crate::service_host_bridge::ServiceOwnerMode,
        budget: crate::service_host_bridge::ServiceOwnerCallBudget,
    ) -> Result<Arc<Self>, AgentServiceSetupError> {
        use crate::service_host_bridge::{service_owner_adapter, ServiceOwnerMode};
        use muyon_rust_agent_host_lab::{service_host::{ServiceHostMode, ServiceHostPorts}, service_provider::CallBudget};
        let ports = ServiceHostPorts::new(service_owner_adapter(owner), match mode {
            ServiceOwnerMode::LocalRead => ServiceHostMode::LocalRead,
            ServiceOwnerMode::ConfiguredChat => ServiceHostMode::ConfiguredChat,
        }, CallBudget { max_tokens: budget.max_tokens, max_micros: budget.max_micros,
            requires_tools: budget.requires_tools, requires_streaming: budget.requires_streaming });
        let inner = muyon_rust_agent_host_lab::service_controller::AgentServiceController::new_with_host(
            host::AgentHostServiceConfig { protocol: config.protocol, private_root: config.private_root,
                build_identity: env!("MUYON_BRIDGE_BUILD_ID").into() }, Arc::new(ports),
        ).map_err(setup_error)?;
        Ok(Arc::new(Self { inner }))
    }
    /// Additive Service-bootstrap tool route; UI/Binder cannot select installation.
    #[uniffi::constructor]
    pub fn with_registered_tools(config:AgentServiceConfig,owner:Arc<dyn crate::service_host_bridge::ServiceHostOwnerCallback>,mode:crate::service_host_bridge::ServiceOwnerMode,budget:crate::service_host_bridge::ServiceOwnerCallBudget,settings:Arc<dyn crate::registered_tools::RegisteredToolSettings>,synthetic_tools:bool)->Result<Arc<Self>,AgentServiceSetupError> {
        use crate::service_host_bridge::{service_owner_adapter,ServiceOwnerMode};
        use muyon_rust_agent_host_lab::{service_host::{ServiceHostMode,ServiceHostPorts},service_provider::CallBudget};
        let ports=ServiceHostPorts::new(service_owner_adapter(owner),match mode{ServiceOwnerMode::LocalRead=>ServiceHostMode::LocalRead,ServiceOwnerMode::ConfiguredChat=>ServiceHostMode::ConfiguredChat},CallBudget{max_tokens:budget.max_tokens,max_micros:budget.max_micros,requires_tools:budget.requires_tools,requires_streaming:budget.requires_streaming}).with_tools(crate::registered_tools::route(settings,synthetic_tools));
        let inner=muyon_rust_agent_host_lab::service_controller::AgentServiceController::new_with_host(host::AgentHostServiceConfig{protocol:config.protocol,private_root:config.private_root,build_identity:env!("MUYON_BRIDGE_BUILD_ID").into()},Arc::new(ports)).map_err(setup_error)?;
        Ok(Arc::new(Self{inner}))
    }
    #[uniffi::constructor]
    pub fn new(config: AgentServiceConfig) -> Result<Arc<Self>, AgentServiceSetupError> {
        let inner = muyon_rust_agent_host_lab::service_controller::AgentServiceController::new(
            host::AgentHostServiceConfig {
                protocol: config.protocol,
                private_root: config.private_root,
                build_identity: env!("MUYON_BRIDGE_BUILD_ID").into(),
            },
        )
        .map_err(|e| match e {
            host::AgentServiceError::UnsupportedProtocol => {
                AgentServiceSetupError::UnsupportedProtocol
            }
            host::AgentServiceError::InvalidRoot => AgentServiceSetupError::InvalidRoot,
            host::AgentServiceError::Busy => AgentServiceSetupError::Busy,
            host::AgentServiceError::RecoveryRequired => AgentServiceSetupError::RecoveryRequired,
            _ => AgentServiceSetupError::InternalFailure,
        })?;
        Ok(Arc::new(Self { inner }))
    }
    pub fn service_admission_probe(&self, operation: ServiceAdmissionProbeOperation) -> ServiceAdmissionProbeReply {
        use muyon_rust_agent_host_lab::service_host::ServiceAdmissionProbeOperation as HostOperation;
        let operation = match operation {
            ServiceAdmissionProbeOperation::PrimaryCommit => HostOperation::PrimaryCommit,
            ServiceAdmissionProbeOperation::PrimaryCancel => HostOperation::PrimaryCancel,
            ServiceAdmissionProbeOperation::SecondaryCommit => HostOperation::SecondaryCommit,
            ServiceAdmissionProbeOperation::SecondaryCancel => HostOperation::SecondaryCancel,
            ServiceAdmissionProbeOperation::TertiaryCommit => HostOperation::TertiaryCommit,
        };
        let reply = self.inner.service_admission_probe(operation);
        ServiceAdmissionProbeReply { admitted: reply.admitted, record_id: reply.record_id, code: reply.code }
    }
    pub fn connect(&self, req: AgentConnectRequest) -> AgentConnectReply {
        self.inner.connect(req.to_host()).to_bridge()
    }
    pub fn start_run(&self, req: AgentStartRequest) -> AgentStartReply {
        self.inner.start_run(req.to_host()).to_bridge()
    }
    pub fn submit_ordinary_chat(&self,client:AgentClientRef,request_id:String,conversation:String,text:String)->String {
        self.inner.submit_ordinary_chat(client.to_host(),request_id,conversation,text)
    }
    pub fn submit_supplier_read(
        &self,
        client: AgentClientRef,
        request_id: String,
        text: String,
        key: String,
        revision: String,
    ) -> String {
        self.inner
            .submit_supplier_read(client.to_host(), request_id, text, key, revision)
    }
    pub fn supplier_read_events(
        &self,
        client: AgentClientRef,
        request_id: String,
        after: i64,
    ) -> String {
        self.inner
            .supplier_read_events(client.to_host(), request_id, after)
    }
    pub fn status(&self, req: AgentStatusRequest) -> AgentSnapshotReply {
        self.inner.status(req.to_host()).to_bridge()
    }
    pub fn current(&self, req: AgentClientRef) -> AgentSnapshotReply {
        self.inner.current(req.to_host()).to_bridge()
    }
    pub fn lookup(&self, req: AgentLookupRequest) -> AgentSnapshotReply {
        self.inner.lookup(req.to_host()).to_bridge()
    }
    pub fn set_visibility(&self, req: AgentVisibilityRequest) -> AgentControlReply {
        self.inner.set_visibility(req.to_host()).to_bridge()
    }
    pub fn release_client(&self, req: AgentReleaseRequest) -> AgentControlReply {
        self.inner.release_client(req.to_host()).to_bridge()
    }
    pub fn cancel(&self, req: AgentCancelRequest) -> AgentControlReply {
        self.inner.cancel(req.to_host()).to_bridge()
    }
    pub fn close(&self, req: AgentClientRef) -> AgentCloseReply {
        self.inner.close(req.to_host()).to_bridge()
    }
    pub fn client_gone(&self, platform_client_key: String) -> AgentControlReply {
        self.inner.client_gone(platform_client_key).to_bridge()
    }
    pub fn retire_service(&self) -> AgentCloseReply {
        self.inner.retire_service().to_bridge()
    }
    pub fn await_settled(&self) -> AgentSnapshotReply {
        self.inner.await_settled().to_bridge()
    }
}

fn setup_error(e: host::AgentServiceError) -> AgentServiceSetupError {
    match e {
        host::AgentServiceError::UnsupportedProtocol => AgentServiceSetupError::UnsupportedProtocol,
        host::AgentServiceError::InvalidRoot => AgentServiceSetupError::InvalidRoot,
        host::AgentServiceError::Busy => AgentServiceSetupError::Busy,
        host::AgentServiceError::RecoveryRequired => AgentServiceSetupError::RecoveryRequired,
        _ => AgentServiceSetupError::InternalFailure,
    }
}
