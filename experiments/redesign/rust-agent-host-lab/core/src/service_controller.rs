//! Service-owned async controller. Rc sessions exist only inside the one worker.
use crate::{
    service_evidence,
    service_root::ServiceRoot,
    service_runtime::{run_builtin_admitted, BuiltinExecution, RunControl},
    service_types::*,
    supplier_business::{self, BusinessRead},
};
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex, MutexGuard,
    },
    thread::{self, JoinHandle},
};
/// Rust test diagnostics only. No C/UniFFI export or UI-controlled selector.
/// Observes immutable actual worker output; it cannot supply authority or a driver.
#[doc(hidden)]
pub trait ServiceEvidenceObserver: Send + Sync {
    fn observe(&self, run: &AgentDurableRun, execution: &BuiltinExecution);
}
pub const SERVICE_STUB_REACHED: &str = "AGENT_SERVICE_STUB_REACHED";
static PROCESS_OCCUPIED: AtomicBool = AtomicBool::new(false);
struct Client {
    key: String,
    lease: String,
    active: bool,
    visible: bool,
    observation: Option<(i64, Observation)>,
}
#[derive(PartialEq, Eq)]
enum Observation {
    Visible(bool),
    Released,
}
struct Inner {
    meta: AgentReplyMeta,
    phase: AgentServiceState,
    sealed: bool,
    poison_observed: bool,
    clients: Vec<Client>,
    client_leases: Vec<String>,
    runs: Vec<AgentRunSnapshot>,
    business: std::collections::BTreeMap<String, BusinessRead>,
    root: Option<ServiceRoot>,
    worker: Option<JoinHandle<Completion>>,
    joining: bool,
    control: Option<Arc<RunControl>>,
    owner: Option<String>,
    owns_process_slot: bool,
}
struct Shared {
    inner: Mutex<Inner>,
}
struct ExecutionSettlement {
    snapshot: AgentRunSnapshot,
    recovery: bool,
}
enum Completion {
    Initialized(
        Result<
            (
                ServiceRoot,
                Vec<AgentRunSnapshot>,
                bool,
                std::collections::BTreeMap<String, BusinessRead>,
            ),
            String,
        >,
    ),
    Executed {
        root: ServiceRoot,
        snapshot: AgentRunSnapshot,
        recovery: bool,
    },
}
impl Inner {
    fn bump(&mut self) -> bool {
        if let Some(next) = self.meta.server_snapshot_revision.checked_add(1) {
            self.meta.server_snapshot_revision = next;
            true
        } else {
            self.sealed = true;
            if self.phase != AgentServiceState::Closed {
                self.phase = AgentServiceState::Closing
            }
            if let Some(c) = &self.control {
                c.request_cancel()
            }
            false
        }
    }
    fn seal(&mut self) {
        let changed = !self.sealed
            || !matches!(
                self.phase,
                AgentServiceState::Closing | AgentServiceState::Closed
            );
        self.sealed = true;
        if self.phase != AgentServiceState::Closed {
            self.phase = AgentServiceState::Closing
        }
        if let Some(c) = &self.control {
            c.request_cancel()
        }
        if changed {
            self.bump();
        }
    }
    fn validate(&self, r: &AgentClientRef, inactive: bool) -> Result<usize, AgentServiceError> {
        if r.protocol != 1 {
            return Err(AgentServiceError::UnsupportedProtocol);
        }
        if !hex_id(&r.expected_service_epoch, 32) || !hex_id(&r.client_lease, 32) {
            return Err(AgentServiceError::InvalidIdentity);
        }
        if r.expected_service_epoch != self.meta.service_epoch {
            return Err(AgentServiceError::EpochMismatch);
        }
        self.clients
            .iter()
            .position(|c| c.lease == r.client_lease && (inactive || c.active))
            .ok_or(AgentServiceError::ClientUnavailable)
    }
    fn snapshot(&self, run: Option<AgentRunSnapshot>) -> AgentSnapshotReply {
        AgentSnapshotReply {
            meta: self.meta.clone(),
            outcome: AgentSnapshotOutcome::Snapshot {
                service_state: self.phase.clone(),
                run,
            },
        }
    }
    fn current(&self) -> AgentSnapshotReply {
        self.snapshot(self.runs.last().cloned())
    }
    fn reject_snapshot(&self, error: AgentServiceError) -> AgentSnapshotReply {
        AgentSnapshotReply {
            meta: self.meta.clone(),
            outcome: AgentSnapshotOutcome::Rejected { error },
        }
    }
    fn publish(&mut self, snapshot: AgentRunSnapshot) {
        let request = intent_of(&snapshot).request_id;
        if let Some(existing) = self
            .runs
            .iter_mut()
            .find(|s| intent_of(s).request_id == request)
        {
            *existing = snapshot;
            self.bump();
        }
    }
    fn find(&self, r: &AgentRunRef) -> Result<Option<AgentRunSnapshot>, AgentServiceError> {
        if !request_id(&r.request_id) {
            return Err(AgentServiceError::InvalidRequestId);
        }
        if r.run_id.as_ref().map(|id| !hex_id(id, 32)).unwrap_or(false) {
            return Err(AgentServiceError::InvalidIdentity);
        }
        let Some(s) = self
            .runs
            .iter()
            .find(|s| intent_of(s).request_id == r.request_id)
        else {
            return Ok(None);
        };
        if intent_of(s).variant != r.variant {
            return Err(AgentServiceError::RequestConflict);
        }
        if let Some(expected) = &r.run_id {
            if identity_of(s).as_ref().map(|i| &i.run_id) != Some(expected) {
                return Err(AgentServiceError::RequestConflict);
            }
        }
        Ok(Some(s.clone()))
    }
}
impl Shared {
    fn lock(&self) -> MutexGuard<'_, Inner> {
        match self.inner.lock() {
            Ok(g) => g,
            Err(e) => {
                let mut g = e.into_inner();
                if !g.poison_observed {
                    g.poison_observed = true;
                    g.sealed = true;
                    g.phase = AgentServiceState::RecoveryRequired;
                    if let Some(c) = &g.control {
                        c.request_cancel()
                    }
                    g.bump();
                }
                g
            }
        }
    }
}
fn hex_id(s: &str, n: usize) -> bool {
    s.len() == n
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn self_request_id_valid(s: &str) -> bool {
    request_id(s)
}
fn request_id(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 64
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}
fn intent_of(s: &AgentRunSnapshot) -> AgentIntentBinding {
    match s {
        AgentRunSnapshot::QueuedVolatile { intent } => intent.clone(),
        AgentRunSnapshot::DurablyAdmitted { run } | AgentRunSnapshot::Running { run } => {
            run.intent.clone()
        }
        AgentRunSnapshot::Terminal { summary } => AgentIntentBinding {
            request_id: summary.request_id.clone(),
            variant: summary.variant.clone(),
            source_build_identity: summary.source_build_identity.clone(),
        },
        AgentRunSnapshot::SettledNoAdmission { settlement } => settlement.intent.clone(),
        AgentRunSnapshot::Unresolved { observation } => observation.intent.clone(),
    }
}
fn identity_of(s: &AgentRunSnapshot) -> Option<AgentRunIdentity> {
    match s {
        AgentRunSnapshot::DurablyAdmitted { run } | AgentRunSnapshot::Running { run } => {
            Some(run.identity.clone())
        }
        AgentRunSnapshot::Terminal { summary } => Some(summary.identity.clone()),
        AgentRunSnapshot::Unresolved { observation } => observation.identity.clone(),
        _ => None,
    }
}
fn unknown(intent: AgentIntentBinding, identity: Option<AgentRunIdentity>) -> AgentRunSnapshot {
    AgentRunSnapshot::Unresolved {
        observation: AgentUnresolvedObservation {
            intent,
            identity,
            receipt: AgentReceiptSummary {
                opaque_id: None,
                outcome: AgentReceiptOutcome::Unknown,
            },
        },
    }
}
fn settled(s: &AgentRunSnapshot) -> bool {
    matches!(
        s,
        AgentRunSnapshot::Terminal { .. }
            | AgentRunSnapshot::SettledNoAdmission { .. }
            | AgentRunSnapshot::Unresolved { .. }
    )
}
pub struct AgentServiceController {
    shared: Arc<Shared>,
    observer: Option<Arc<dyn ServiceEvidenceObserver>>,
    host: Option<Arc<crate::service_host::ServiceHostPorts>>,
}
impl AgentServiceController {
    /// Service-bootstrap-only metadata probe. Serialize with retirement so no
    /// owner callback can begin once native settlement/cleanup is published.
    pub fn service_admission_probe(&self, operation: crate::service_host::ServiceAdmissionProbeOperation)
        -> crate::service_host::ServiceAdmissionProbeReply {
        use crate::service_host::ServiceAdmissionProbeReply;
        let g = self.shared.lock();
        if g.sealed || g.phase != AgentServiceState::Ready || g.worker.is_some() || g.joining {
            return ServiceAdmissionProbeReply::rejected("service_probe_not_ready");
        }
        match &self.host {
            Some(host) => host.admission_probe(operation),
            None => ServiceAdmissionProbeReply::rejected("service_probe_owner_unavailable"),
        }
    }
    /// Host-only injection; never exposed by the UI/FFI request DTOs.
    pub fn new_with_host(
        config: AgentHostServiceConfig,
        host: Arc<crate::service_host::ServiceHostPorts>,
    ) -> Result<Self, AgentServiceError> {
        Self::construct(config, None, Some(host))
    }
    pub fn new(config: AgentHostServiceConfig) -> Result<Self, AgentServiceError> {
        Self::construct(config, None, None)
    }
    /// Rust-only diagnostics; same admission, worker, controls and driver as shipping new.
    #[doc(hidden)]
    pub fn new_with_observer(
        config: AgentHostServiceConfig,
        observer: Arc<dyn ServiceEvidenceObserver>,
    ) -> Result<Self, AgentServiceError> {
        Self::construct(config, Some(observer), None)
    }
    fn construct(
        config: AgentHostServiceConfig,
        observer: Option<Arc<dyn ServiceEvidenceObserver>>,
        host: Option<Arc<crate::service_host::ServiceHostPorts>>,
    ) -> Result<Self, AgentServiceError> {
        if config.protocol != 1 {
            return Err(AgentServiceError::UnsupportedProtocol);
        }
        if !hex_id(&config.build_identity, 40) {
            return Err(AgentServiceError::InvalidIdentity);
        }
        let path = PathBuf::from(&config.private_root);
        if !path.is_absolute()
            || muyon_core_agent_lab::store::validate_dir(&path).is_err()
            || std::fs::canonicalize(&path)
                .map(|p| p.as_os_str() != path.as_os_str())
                .unwrap_or(true)
        {
            return Err(AgentServiceError::InvalidRoot);
        }
        let epoch = crate::nonce().map_err(|_| AgentServiceError::InternalFailure)?;
        // Service bootstrap runs off Binder/main. Generate the entire lifetime lease
        // budget here so prompt connect/control never performs entropy I/O under lock.
        let client_leases = vec![
            crate::nonce().map_err(|_| AgentServiceError::InternalFailure)?,
            crate::nonce().map_err(|_| AgentServiceError::InternalFailure)?,
        ];
        if PROCESS_OCCUPIED
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            return Err(AgentServiceError::Busy);
        }
        let shared = Arc::new(Shared {
            inner: Mutex::new(Inner {
                meta: AgentReplyMeta {
                    protocol: 1,
                    build_identity: config.build_identity,
                    service_epoch: epoch,
                    server_snapshot_revision: 0,
                },
                phase: AgentServiceState::Initializing,
                sealed: false,
                poison_observed: false,
                clients: Vec::new(),
                client_leases,
                runs: Vec::new(),
                business: Default::default(),
                root: None,
                worker: None,
                joining: false,
                control: None,
                owner: None,
                owns_process_slot: true,
            }),
        });
        let inventory_host = host.clone();
        match thread::Builder::new()
            .name("muyon-agent-inventory".into())
            .spawn(move || {
                Completion::Initialized((|| {
                    let root = ServiceRoot::open(&path)?;
                    let (mut runs, _) = service_evidence::restore(&root);
                    let business = supplier_business::restore_all(&root, inventory_host);
                    // Static disk evidence alone never upgrades a live canary to success.
                    for run in root.runs() {
                        if let Some(b)=business.get(&run.intent.request_id).filter(|b|crate::ordinary_chat::live(b)) {
                            if let Ok(dir)=root.run_dir(&run.identity.run_id) {
                                if let Ok(snapshot)=crate::ordinary_chat::restore(&dir,run,b) {
                                    if let Some(old)=runs.iter_mut().find(|s|intent_of(s).request_id==run.intent.request_id){*old=snapshot;}
                                }
                            }
                        }
                    }
                    let recovery=root.is_poisoned() || runs.iter().any(|s|matches!(s,AgentRunSnapshot::Unresolved{..}) || matches!(s,AgentRunSnapshot::Terminal{summary} if summary.terminal==AgentTerminal::OutcomeUnknown));
                    Ok((root, runs, recovery, business))
                })())
            }) {
            Ok(handle) => shared.lock().worker = Some(handle),
            Err(_) => {
                PROCESS_OCCUPIED.store(false, Ordering::Release);
                return Err(AgentServiceError::InternalFailure);
            }
        }
        Ok(Self { shared, observer, host })
    }
    pub fn connect(&self, req: AgentConnectRequest) -> AgentConnectReply {
        let mut g = self.shared.lock();
        let reject = |g: &Inner, error| AgentConnectReply {
            meta: g.meta.clone(),
            outcome: AgentConnectOutcome::Rejected { error },
        };
        if req.protocol != 1 {
            return reject(&g, AgentServiceError::UnsupportedProtocol);
        }
        if !hex_id(&req.platform_client_key, 32) {
            return reject(&g, AgentServiceError::InvalidIdentity);
        }
        if let Some(c) = g.clients.iter().find(|c| c.key == req.platform_client_key) {
            return if c.active {
                AgentConnectReply {
                    meta: g.meta.clone(),
                    outcome: AgentConnectOutcome::Connected {
                        client_lease: c.lease.clone(),
                        service_state: g.phase.clone(),
                    },
                }
            } else {
                reject(&g, AgentServiceError::ClientUnavailable)
            };
        }
        // Tombstones are bounded by the same two slots; never resurrect a retired key.
        if g.clients.len() >= 2 {
            return AgentConnectReply {
                meta: g.meta.clone(),
                outcome: AgentConnectOutcome::Busy,
            };
        }
        let Some(lease) = g.client_leases.pop() else {
            return reject(&g, AgentServiceError::InternalFailure);
        };
        if !g.bump() {
            return reject(&g, AgentServiceError::BudgetExceeded);
        }
        g.clients.push(Client {
            key: req.platform_client_key,
            lease: lease.clone(),
            active: true,
            visible: false,
            observation: None,
        });
        AgentConnectReply {
            meta: g.meta.clone(),
            outcome: AgentConnectOutcome::Connected {
                client_lease: lease,
                service_state: g.phase.clone(),
            },
        }
    }
    pub fn start_run(&self, req: AgentStartRequest) -> AgentStartReply {
        if self.host.is_some() {
            let g = self.shared.lock();
            return AgentStartReply { meta: g.meta.clone(), outcome: AgentStartOutcome::Rejected { error: AgentServiceError::TargetUnavailable } };
        }
        self.start_internal(req, None)
    }
    fn start_internal(
        &self,
        req: AgentStartRequest,
        business: Option<BusinessRead>,
    ) -> AgentStartReply {
        let mut g = self.shared.lock();
        let rejected = |g: &Inner, error| AgentStartReply {
            meta: g.meta.clone(),
            outcome: AgentStartOutcome::Rejected { error },
        };
        let client = match g.validate(&req.client, false) {
            Ok(i) => i,
            Err(e) => return rejected(&g, e),
        };
        if !request_id(&req.request_id) {
            return rejected(&g, AgentServiceError::InvalidRequestId);
        }
        if g.sealed
            || matches!(
                g.phase,
                AgentServiceState::Closing | AgentServiceState::Closed
            )
        {
            return rejected(&g, AgentServiceError::Closed);
        }
        if let Some(old) = g.business.get(&req.request_id) {
            if business.as_ref().map(|b| &b.payload) != Some(&old.payload) {
                return rejected(&g, AgentServiceError::RequestConflict);
            }
        } else if business.is_some()
            && g.runs
                .iter()
                .any(|s| intent_of(s).request_id == req.request_id)
        {
            return rejected(&g, AgentServiceError::RequestConflict);
        }
        if g.phase == AgentServiceState::RecoveryRequired {
            return rejected(&g, AgentServiceError::RecoveryRequired);
        }
        if let Some(old) = g
            .runs
            .iter()
            .find(|s| intent_of(s).request_id == req.request_id)
        {
            let binding = intent_of(old);
            if binding.variant != req.variant
                || binding.source_build_identity != g.meta.build_identity
            {
                return rejected(&g, AgentServiceError::RequestConflict);
            }
            return AgentStartReply {
                meta: g.meta.clone(),
                outcome: AgentStartOutcome::Existing {
                    snapshot: old.clone(),
                },
            };
        }
        if !g.clients[client].visible {
            return rejected(&g, AgentServiceError::ClientNotVisible);
        }
        if g.phase != AgentServiceState::Ready || g.worker.is_some() || g.joining {
            return AgentStartReply {
                meta: g.meta.clone(),
                outcome: AgentStartOutcome::Busy,
            };
        }
        if g.runs.len() >= 8 {
            return rejected(&g, AgentServiceError::BudgetExceeded);
        }
        let Some(root) = g.root.take() else {
            return rejected(&g, AgentServiceError::RecoveryRequired);
        };
        let intent = AgentIntentBinding {
            request_id: req.request_id,
            variant: req.variant,
            source_build_identity: g.meta.build_identity.clone(),
        };
        let queued = AgentRunSnapshot::QueuedVolatile {
            intent: intent.clone(),
        };
        if !g.bump() {
            g.root = Some(root);
            return rejected(&g, AgentServiceError::BudgetExceeded);
        }
        if let Some(b) = &business {
            g.business.insert(intent.request_id.clone(), b.clone());
        }
        g.runs.push(queued.clone());
        let control = Arc::new(RunControl::new());
        g.control = Some(control.clone());
        g.owner = Some(req.client.client_lease);
        let shared = self.shared.clone();
        let epoch = g.meta.service_epoch.clone();
        let observer = self.observer.clone();
        let failure_intent = intent.clone();
        // Retain the lease if spawn rejects the closure before it can run.
        let root_transfer = Arc::new(Mutex::new(Some(root)));
        let worker_root = root_transfer.clone();
        match thread::Builder::new()
            .name("muyon-agent-run".into())
            .spawn(move || {
                let mut root = worker_root.lock().unwrap().take().unwrap();
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    execute(
                        &mut root,
                        intent,
                        epoch,
                        control,
                        shared.clone(),
                        observer,
                        business,
                    )
                }));
                match result {
                    Ok(settlement) => Completion::Executed {
                        root,
                        snapshot: settlement.snapshot,
                        recovery: settlement.recovery,
                    },
                    Err(panic) => {
                        // Preserve the original flock before continuing the original
                        // panic. The actual JoinHandle still settles with Err.
                        shared.lock().root = Some(root);
                        std::panic::resume_unwind(panic)
                    }
                }
            }) {
            Ok(handle) => g.worker = Some(handle),
            Err(_) => {
                g.root = root_transfer.lock().unwrap().take();
                g.publish(unknown(failure_intent, None));
                g.phase = AgentServiceState::RecoveryRequired;
                g.control = None;
                g.owner = None;
                g.bump();
                return rejected(&g, AgentServiceError::InternalFailure);
            }
        }
        AgentStartReply {
            meta: g.meta.clone(),
            outcome: AgentStartOutcome::QueuedVolatile { snapshot: queued },
        }
    }
    /// Private closed business protocol. Queued acceptance is volatile until run identity appears.
    pub fn submit_supplier_read(
        &self, client: AgentClientRef, request_id: String, text: String, key: String, revision: String,
    ) -> String {
        self.host_marker(self.submit_supplier_read_internal(client, request_id, text, key, revision))
    }
    /// Ordinary input intent: no supplier key, revision, read grant or caller authority.
    pub fn submit_ordinary_chat(&self,client:AgentClientRef,request_id:String,conversation:String,text:String)->String {
        // Duplicate identities retain their original frozen route, even after settings change.
        let old={self.shared.lock().business.get(&request_id).cloned()};
        if let Some(old)=old {if crate::field(&old.payload,"conversation").ok()!=Some(&crate::string(&conversation))||crate::field(&old.payload,"text").ok()!=Some(&crate::string(&text)){return self.host_marker(supplier_business::reply("rejected","RequestConflict",&request_id,None,None,0))}return self.submit_business(client,request_id,old)}
        if self.shared.lock().runs.iter().any(|r|intent_of(r).request_id==request_id){return self.host_marker(supplier_business::reply("unknown","original_evidence_unavailable",&request_id,None,None,0))}
        let frozen=self.host.as_ref().and_then(|h|h.tools.as_ref()).map(|r|r.prepare(&conversation,&text));
        let prepared=match frozen {Some(Ok(Some(route)))=>crate::service_tools::make(conversation,text,route),Some(Err(_))=>crate::service_tools::make(conversation,text,crate::object([("tool",crate::string("unavailable")),("status",crate::string("search_config_corrupt")),("synthetic",crate::Json::Bool(false))])),_=>BusinessRead::ordinary(conversation,text)};
        let business=match prepared{Ok(mut b)=>{b.attach_host(self.host.clone());b},Err(e)=>return supplier_business::reply("rejected",&e,&request_id,None,None,0)};
        self.submit_business(client,request_id,business)
    }
    fn host_marker(&self, reply: String) -> String {
        if self.host.is_none() { return reply; }
        let Ok(mut value) = muyon_plugin_contract_lab::parse(reply.as_bytes()) else { return reply; };
        if let Some(request)=crate::field(&value,"request_id").ok().and_then(|v|v.string().ok()) {
            let ordinary=self.shared.lock().business.get(request).filter(|b|crate::ordinary_chat::is_chat(b)).map(|b|b.chat_synthetic.unwrap_or(false));
            if let Some(synthetic)=ordinary {if let muyon_plugin_contract_lab::Json::Object(fields)=&mut value{fields.insert("synthetic".into(),muyon_plugin_contract_lab::Json::Bool(synthetic));}return value.encode();}
            if self.shared.lock().business.get(request).is_some_and(crate::service_tools::is_registered){return reply}
        }
        if let muyon_plugin_contract_lab::Json::Object(fields) = &mut value {
            fields.insert("synthetic".into(), muyon_plugin_contract_lab::Json::Bool(false));
        }
        value.encode()
    }
    fn submit_supplier_read_internal(
        &self,
        client: AgentClientRef,
        request_id: String,
        text: String,
        key: String,
        revision: String,
    ) -> String {
        let mut business = match BusinessRead::new(text, key, revision) {
            Ok(b) => b,
            Err(reason) => {
                return supplier_business::reply("rejected", &reason, &request_id, None, None, 0)
            }
        };
        business.attach_host(self.host.clone());
        self.submit_business(client,request_id,business)
    }
    fn submit_business(&self,client:AgentClientRef,request_id:String,business:BusinessRead)->String {
        let reply = self.start_internal(
            AgentStartRequest { client, request_id: request_id.clone(), variant: AgentReadVariant::Inquiry },Some(business));
        let (status, reason) = match reply.outcome {
            AgentStartOutcome::QueuedVolatile { .. } => ("accepted", "queued_volatile".into()),
            AgentStartOutcome::Existing { .. } => ("existing", "none".into()),
            AgentStartOutcome::Busy => ("rejected", "BUSY".into()),
            AgentStartOutcome::Rejected { error } => ("rejected", format!("{:?}", error)),
        };
        let g = self.shared.lock();
        let identity = g
            .runs
            .iter()
            .find(|s| intent_of(s).request_id == request_id)
            .and_then(identity_of);
        let ordinary=g.business.get(&request_id).filter(|b|crate::ordinary_chat::is_chat(b) || crate::service_tools::is_registered(b)).cloned().map(|mut b|{
            b.events.clear();
            // Acceptance exposes only frozen source metadata, never a result replay.
            if crate::service_tools::is_registered(&b){b.dir=None;}
            b
        });
        supplier_business::reply(status, &reason, &request_id, identity.as_ref(), ordinary.as_ref(), 0)
    }
    /// Cursor polling and reconnect lookup share this operation; it never executes a read.
    pub fn supplier_read_events(
        &self, client: AgentClientRef, request_id: String, after: i64,
    ) -> String {
        self.host_marker(self.supplier_read_events_internal(client, request_id, after))
    }
    fn supplier_read_events_internal(
        &self,
        client: AgentClientRef,
        request_id: String,
        after: i64,
    ) -> String {
        let g = self.shared.lock();
        if let Err(error) = g.validate(&client, false) {
            return supplier_business::reply(
                "rejected",
                &format!("{:?}", error),
                &request_id,
                None,
                None,
                0,
            );
        }
        if !self_request_id_valid(&request_id) || after < 0 || after > 4 {
            return supplier_business::reply(
                "rejected",
                "INVALID_CURSOR_OR_ID",
                &request_id,
                None,
                None,
                0,
            );
        }
        let identity = g
            .runs
            .iter()
            .find(|s| intent_of(s).request_id == request_id)
            .and_then(identity_of);
        let mut business = g.business.get(&request_id).cloned();
        let no_admission_cancelled = g.runs.iter().find(|s| intent_of(s).request_id == request_id).map(|s| matches!(s, AgentRunSnapshot::SettledNoAdmission { settlement } if settlement.reason == AgentNoAdmissionReason::CancelledBeforeAdmission)).unwrap_or(false);
        if no_admission_cancelled {
            if let Some(b) = &mut business {
                b.cancel_before_admission();
            }
        }
        let snapshot = g
            .runs
            .iter()
            .find(|s| intent_of(s).request_id == request_id)
            .cloned();
        drop(g);
        if let Some(
            snapshot @ (AgentRunSnapshot::Unresolved { .. } | AgentRunSnapshot::Terminal { .. }),
        ) = snapshot.as_ref()
        {
            return supplier_business::snapshot_reply(snapshot, business.as_ref(), after);
        }
        // A live worker may have saved candidate events before controller settlement.
        // Publish only stable source metadata until its final owner acceptance.
        if let Some(b)=business.as_mut().filter(|b|crate::ordinary_chat::is_chat(b) && b.chat_synthetic==Some(false)) {b.events.clear();}
        match business.as_ref() {
            Some(b) => supplier_business::reply(
                "events",
                "none",
                &request_id,
                identity.as_ref(),
                Some(b),
                after,
            ),
            None => supplier_business::reply(
                "unknown",
                "UNKNOWN",
                &request_id,
                identity.as_ref(),
                None,
                after,
            ),
        }
    }
    pub fn status(&self, req: AgentStatusRequest) -> AgentSnapshotReply {
        let g = self.shared.lock();
        if let Err(e) = g.validate(&req.client, false) {
            return g.reject_snapshot(e);
        }
        match g.find(&req.run) {
            Ok(Some(s)) => g.snapshot(Some(s)),
            Ok(None) => AgentSnapshotReply {
                meta: g.meta.clone(),
                outcome: AgentSnapshotOutcome::Unresolved,
            },
            Err(e) => g.reject_snapshot(e),
        }
    }
    pub fn current(&self, req: AgentClientRef) -> AgentSnapshotReply {
        let g = self.shared.lock();
        if let Err(e) = g.validate(&req, false) {
            return g.reject_snapshot(e);
        }
        g.current()
    }
    pub fn lookup(&self, req: AgentLookupRequest) -> AgentSnapshotReply {
        let g = self.shared.lock();
        if let Err(e) = g.validate(&req.client, false) {
            return g.reject_snapshot(e);
        }
        let found = match req.key {
            AgentLookupKey::RequestId { request_id: id } => {
                if !request_id(&id) {
                    return g.reject_snapshot(AgentServiceError::InvalidRequestId);
                }
                g.runs.iter().find(|s| intent_of(s).request_id == id)
            }
            AgentLookupKey::RunId { run_id: id } => {
                if !hex_id(&id, 32) {
                    return g.reject_snapshot(AgentServiceError::InvalidIdentity);
                }
                g.runs
                    .iter()
                    .find(|s| identity_of(s).map(|i| i.run_id == id).unwrap_or(false))
            }
        };
        match found {
            Some(s) => g.snapshot(Some(s.clone())),
            None => AgentSnapshotReply {
                meta: g.meta.clone(),
                outcome: AgentSnapshotOutcome::Unresolved,
            },
        }
    }
    pub fn set_visibility(&self, req: AgentVisibilityRequest) -> AgentControlReply {
        let mut g = self.shared.lock();
        let index = match g.validate(&req.client, false) {
            Ok(i) => i,
            Err(e) => return control_reply(&g, AgentControlOutcome::Rejected { error: e }),
        };
        if req.observation_generation < 0 {
            return control_reply(
                &g,
                AgentControlOutcome::Rejected {
                    error: AgentServiceError::InvalidGeneration,
                },
            );
        }
        if req.visible
            && (g.sealed
                || matches!(
                    g.phase,
                    AgentServiceState::Closing | AgentServiceState::Closed
                ))
        {
            return control_reply(
                &g,
                AgentControlOutcome::Rejected {
                    error: AgentServiceError::Closed,
                },
            );
        }
        if let Some((old, value)) = &g.clients[index].observation {
            if req.observation_generation < *old
                || req.observation_generation == *old && value != &Observation::Visible(req.visible)
            {
                return control_reply(
                    &g,
                    AgentControlOutcome::Rejected {
                        error: AgentServiceError::InvalidGeneration,
                    },
                );
            }
            if req.observation_generation == *old {
                return control_reply(&g, AgentControlOutcome::Applied);
            }
        }
        if !g.bump() {
            return control_reply(
                &g,
                AgentControlOutcome::Rejected {
                    error: AgentServiceError::BudgetExceeded,
                },
            );
        }
        g.clients[index].observation = Some((
            req.observation_generation,
            Observation::Visible(req.visible),
        ));
        g.clients[index].visible = req.visible;
        if !g.clients.iter().any(|c| c.active && c.visible) {
            g.seal()
        }
        control_reply(&g, AgentControlOutcome::Applied)
    }
    pub fn release_client(&self, req: AgentReleaseRequest) -> AgentControlReply {
        let mut g = self.shared.lock();
        let index = match g.validate(&req.client, true) {
            Ok(i) => i,
            Err(e) => return control_reply(&g, AgentControlOutcome::Rejected { error: e }),
        };
        if req.observation_generation < 0 {
            return control_reply(
                &g,
                AgentControlOutcome::Rejected {
                    error: AgentServiceError::InvalidGeneration,
                },
            );
        }
        if let Some((old, value)) = &g.clients[index].observation {
            if req.observation_generation < *old
                || req.observation_generation == *old && value != &Observation::Released
            {
                return control_reply(
                    &g,
                    AgentControlOutcome::Rejected {
                        error: AgentServiceError::InvalidGeneration,
                    },
                );
            }
            if req.observation_generation == *old {
                return control_reply(&g, AgentControlOutcome::Applied);
            }
        }
        if !g.clients[index].active {
            return control_reply(&g, AgentControlOutcome::NotActive);
        }
        g.clients[index].observation = Some((req.observation_generation, Observation::Released));
        g.clients[index].active = false;
        g.clients[index].visible = false;
        g.bump();
        if g.owner.as_ref() == Some(&req.client.client_lease) {
            if let Some(c) = &g.control {
                c.request_cancel()
            }
        }
        if !g.clients.iter().any(|c| c.active && c.visible) {
            g.seal()
        }
        control_reply(&g, AgentControlOutcome::Applied)
    }
    pub fn cancel(&self, req: AgentCancelRequest) -> AgentControlReply {
        let mut g = self.shared.lock();
        if let Err(e) = g.validate(&req.client, false) {
            return control_reply(&g, AgentControlOutcome::Rejected { error: e });
        }
        let snapshot = match g.find(&req.run) {
            Ok(Some(s)) => s,
            Ok(None) => return control_reply(&g, AgentControlOutcome::NotRunning),
            Err(e) => return control_reply(&g, AgentControlOutcome::Rejected { error: e }),
        };
        if settled(&snapshot) {
            return control_reply(&g, AgentControlOutcome::AlreadyTerminal);
        }
        if g.owner.as_ref() != Some(&req.client.client_lease) {
            return control_reply(
                &g,
                AgentControlOutcome::Rejected {
                    error: AgentServiceError::TargetUnavailable,
                },
            );
        }
        if let Some(c) = &g.control {
            let was_cancelled = c.cancelled();
            c.request_cancel();
            if !was_cancelled {
                g.bump();
            }
            control_reply(&g, AgentControlOutcome::Requested)
        } else {
            control_reply(&g, AgentControlOutcome::NotRunning)
        }
    }
    pub fn client_gone(&self, key: String) -> AgentControlReply {
        let mut g = self.shared.lock();
        if !hex_id(&key, 32) {
            return control_reply(
                &g,
                AgentControlOutcome::Rejected {
                    error: AgentServiceError::InvalidIdentity,
                },
            );
        }
        let Some(index) = g.clients.iter().position(|c| c.key == key) else {
            return control_reply(&g, AgentControlOutcome::NotActive);
        };
        if !g.clients[index].active {
            return control_reply(&g, AgentControlOutcome::NotActive);
        }
        let lease = g.clients[index].lease.clone();
        g.clients[index].active = false;
        g.clients[index].visible = false;
        g.bump();
        if g.owner.as_ref() == Some(&lease) {
            if let Some(c) = &g.control {
                c.request_cancel()
            }
        }
        if !g.clients.iter().any(|c| c.active && c.visible) {
            g.seal()
        }
        control_reply(&g, AgentControlOutcome::Applied)
    }
    pub fn close(&self, req: AgentClientRef) -> AgentCloseReply {
        let mut g = self.shared.lock();
        if let Err(error) = g.validate(&req, false) {
            return AgentCloseReply {
                meta: g.meta.clone(),
                outcome: AgentCloseOutcome::Rejected { error },
            };
        }
        g.seal();
        close_reply(&g)
    }
    pub fn retire_service(&self) -> AgentCloseReply {
        let mut g = self.shared.lock();
        g.seal();
        close_reply(&g)
    }
    pub fn await_settled(&self) -> AgentSnapshotReply {
        let handle = {
            let mut g = self.shared.lock();
            if g.joining {
                return g.current();
            }
            if g.worker.is_none() && g.phase != AgentServiceState::Closing {
                return g.current();
            }
            g.joining = true;
            g.worker.take()
        };
        // The only blocking join is on the Service backend waiter, never under the mutex.
        let completion = handle.map(JoinHandle::join);
        // The failed worker handed back the original lease before resuming its
        // panic. Read durable evidence on this backend waiter, outside the mutex.
        // Never restore a normal terminal after failed worker cleanup.
        let interrupted = if matches!(&completion, Some(Err(_))) {
            let pending = self
                .shared
                .lock()
                .runs
                .last()
                .filter(|s| !settled(s))
                .cloned();
            pending.map(|last| {
                let intent = intent_of(&last);
                let identity = identity_of(&last);
                let root = self.shared.lock().root.take();
                let recovered = root
                    .as_ref()
                    .and_then(|root| {
                        let run = root.runs().iter().find(|run| {
                            if run.intent != intent {
                                return false;
                            }
                            identity
                                .as_ref()
                                .map(|id| {
                                    id.run_id == run.identity.run_id
                                        && id.admitted_service_epoch
                                            == run.identity.admitted_service_epoch
                                        && id
                                            .actual_task
                                            .as_ref()
                                            .map(|task| {
                                                Some(task) == run.identity.actual_task.as_ref()
                                            })
                                            .unwrap_or(true)
                                })
                                .unwrap_or(true)
                        })?;
                        let dir = root.run_dir(&run.identity.run_id).ok()?;
                        let mut receipt = service_evidence::receipt(&dir, run).ok()?;
                        if receipt.outcome == AgentReceiptOutcome::NotStarted {
                            receipt.outcome = AgentReceiptOutcome::Unknown;
                        }
                        Some(service_evidence::unknown(run, receipt))
                    })
                    .unwrap_or_else(|| unknown(intent, identity));
                (root, recovered)
            })
        } else {
            None
        };
        {
            let mut g = self.shared.lock();
            match completion {
                Some(Ok(Completion::Initialized(result))) => match result {
                    Ok((root, runs, recovery, business)) => {
                        g.business = business;
                        g.runs = runs;
                        g.root = Some(root);
                        if !g.sealed {
                            g.phase = if recovery {
                                AgentServiceState::RecoveryRequired
                            } else {
                                AgentServiceState::Ready
                            }
                        }
                    }
                    Err(_) => {
                        if !g.sealed {
                            g.phase = AgentServiceState::RecoveryRequired
                        }
                    }
                },
                Some(Ok(Completion::Executed {
                    mut root,
                    mut snapshot,
                    mut recovery,
                })) => {
                    if let AgentRunSnapshot::Terminal{summary}=&mut snapshot {
                        let control=g.control.clone();
                        if let Some(b)=g.business.get_mut(&summary.request_id) {
                            crate::ordinary_chat::finalize(&mut root,b,summary,control.as_deref());
                            recovery|=summary.terminal==AgentTerminal::OutcomeUnknown || root.is_poisoned();
                        }
                    }
                    g.root = Some(root);
                    g.publish(snapshot);
                    if !g.sealed {
                        g.phase = if recovery {
                            AgentServiceState::RecoveryRequired
                        } else {
                            AgentServiceState::Ready
                        }
                    }
                    g.control = None;
                    g.owner = None;
                }
                Some(Err(_)) => {
                    if let Some((mut root, snapshot)) = interrupted {
                        // Panics cannot strand an owner admission in a sendable live state.
                        if let Some(root)=root.as_mut() {
                            let request=intent_of(&snapshot).request_id;
                            let indexed=root.runs().iter().find(|r|r.intent.request_id==request).cloned();
                            if let Some(run)=indexed {
                                if let Ok(dir)=root.run_dir(&run.identity.run_id) {
                                    if let Ok(mut business)=supplier_business::load(&dir) {
                                        business.attach_host(self.host.clone());
                                        if crate::ordinary_chat::live(&business) {
                                            let mut summary=AgentRunSummary{request_id:request.clone(),variant:run.intent.variant,source_build_identity:run.intent.source_build_identity,identity:run.identity,terminal:AgentTerminal::OutcomeUnknown,reason:AgentReason::Interrupted,receipt:AgentReceiptSummary{opaque_id:None,outcome:AgentReceiptOutcome::Unknown}};
                                            crate::ordinary_chat::finalize(root,&mut business,&mut summary,None);
                                            g.business.insert(request,business);
                                        }
                                    }
                                }
                            }
                        }
                        g.root = root;
                        g.publish(snapshot);
                    }
                    g.control = None;
                    g.owner = None;
                    if !g.sealed {
                        g.phase = AgentServiceState::RecoveryRequired
                    }
                }
                None => {}
            }
            g.bump();
        }
        let root_to_drop = {
            let mut g = self.shared.lock();
            if !g.sealed {
                g.joining = false;
                if !g.sealed {
                    return g.current();
                }
            }
            g.phase = AgentServiceState::Closing;
            g.root.take()
        };
        // Drop the actual root lease before Closed/global-slot release becomes observable.
        drop(root_to_drop);
        let mut g = self.shared.lock();
        if g.sealed {
            g.phase = AgentServiceState::Closed;
            g.joining = false;
            g.control = None;
            g.owner = None;
            g.bump();
            if g.owns_process_slot {
                g.owns_process_slot = false;
                PROCESS_OCCUPIED.store(false, Ordering::Release)
            }
        }
        g.current()
    }
}
impl Drop for AgentServiceController {
    fn drop(&mut self) {
        // Never join on a generated Cleaner thread or release a live process slot.
        // Service lifetime glue explicitly retains the controller through await_settled.
        // An abandoned controller conservatively leaves the process gate Busy until restart.
        self.shared.lock().seal();
    }
}
fn control_reply(g: &Inner, outcome: AgentControlOutcome) -> AgentControlReply {
    AgentControlReply {
        meta: g.meta.clone(),
        outcome,
    }
}
fn close_reply(g: &Inner) -> AgentCloseReply {
    AgentCloseReply {
        meta: g.meta.clone(),
        outcome: if g.phase == AgentServiceState::Closed {
            AgentCloseOutcome::Closed
        } else {
            AgentCloseOutcome::Closing
        },
    }
}
fn execute(
    root: &mut ServiceRoot,
    intent: AgentIntentBinding,
    epoch: String,
    control: Arc<RunControl>,
    shared: Arc<Shared>,
    observer: Option<Arc<dyn ServiceEvidenceObserver>>,
    business: Option<BusinessRead>,
) -> ExecutionSettlement {
    if let Err(reason) = control.poll() {
        let cancelled = reason == "native_cancelled";
        let snapshot = if cancelled {
            AgentRunSnapshot::SettledNoAdmission {
                settlement: AgentNoAdmissionSettlement {
                    intent,
                    reason: AgentNoAdmissionReason::CancelledBeforeAdmission,
                },
            }
        } else {
            unknown(intent, None)
        };
        return ExecutionSettlement {
            snapshot,
            recovery: !cancelled,
        };
    }
    let mut run = match root.admit(intent.clone(), &epoch) {
        Ok(run) => run,
        Err(error) => {
            let known_quota = error == "service_root_quota" && !root.is_poisoned();
            let snapshot = if known_quota {
                AgentRunSnapshot::SettledNoAdmission {
                    settlement: AgentNoAdmissionSettlement {
                        intent,
                        reason: AgentNoAdmissionReason::QuotaExceeded,
                    },
                }
            } else {
                unknown(intent, None)
            };
            return ExecutionSettlement {
                snapshot,
                recovery: !known_quota,
            };
        }
    };
    shared
        .lock()
        .publish(AgentRunSnapshot::DurablyAdmitted { run: run.clone() });
    let dir = match root.run_dir(&run.identity.run_id) {
        Ok(d) => d,
        Err(_) => {
            return ExecutionSettlement {
                snapshot: unknown(run.intent.clone(), Some(run.identity.clone())),
                recovery: true,
            }
        }
    };
    if let Some(mut business) = business {
        if crate::ordinary_chat::is_chat(&business) {
            let g=shared.lock();let mut sources=Vec::new();let mut complete=true;
            for indexed in root.runs().iter().filter(|r|r.intent.request_id!=run.intent.request_id) {
                match g.runs.iter().find(|s|intent_of(s).request_id==indexed.intent.request_id) {
                    Some(AgentRunSnapshot::Terminal{summary}) if summary.terminal==AgentTerminal::Completed=>{
                        if summary.identity!=indexed.identity || summary.source_build_identity!=indexed.intent.source_build_identity || summary.variant!=indexed.intent.variant {complete=false;break}
                        sources.push(indexed.clone());
                    },
                    Some(_)=>(),None=>{complete=false;break}
                }
            }
            business.chat_sources=if complete{Some(sources)}else{None};
        }
        let summary = supplier_business::execute(root, &mut run, &dir, &mut business, control);
        shared
            .lock()
            .business
            .insert(run.intent.request_id.clone(), business);
        let recovery = summary.terminal == AgentTerminal::OutcomeUnknown;
        return ExecutionSettlement {
            snapshot: AgentRunSnapshot::Terminal { summary },
            recovery,
        };
    }
    let result = run_builtin_admitted(&dir, run.intent.variant.clone(), control.clone(), |state| {
        let actual = AgentTaskIdentity {
            task_id: state.task.clone(),
            attempt_id: state.attempt.clone(),
        };
        root.attach_task(&run.identity.run_id, actual.clone())?;
        run.identity.actual_task = Some(actual);
        shared
            .lock()
            .publish(AgentRunSnapshot::Running { run: run.clone() });
        Ok(())
    });
    // Preserve original receipt success even when overall cancellation or storage failure occurs.
    let mut receipt = service_evidence::receipt(&dir, &run).unwrap_or(AgentReceiptSummary {
        opaque_id: None,
        outcome: AgentReceiptOutcome::Unknown,
    });
    let (mut terminal, mut reason) = match &result {
        Ok(done) => match done.state.status.as_str() {
            "completed" => (AgentTerminal::Completed, AgentReason::None),
            "cancelled" => (AgentTerminal::Cancelled, AgentReason::Cancelled),
            "budget_exhausted" => (
                AgentTerminal::BudgetExhausted,
                if control.observed_deadline() {
                    AgentReason::DeadlineExceeded
                } else {
                    AgentReason::BudgetExceeded
                },
            ),
            "denied" | "failed" => (AgentTerminal::Failed, AgentReason::InternalFailure),
            "outcome_unknown" if done.state.reason == "model_ledger_failed" => {
                (AgentTerminal::OutcomeUnknown, AgentReason::StorageFailure)
            }
            _ => (AgentTerminal::OutcomeUnknown, AgentReason::Interrupted),
        },
        Err(_) => (AgentTerminal::OutcomeUnknown, AgentReason::StorageFailure),
    };
    if result.is_err() && receipt.outcome == AgentReceiptOutcome::NotStarted {
        receipt.outcome = AgentReceiptOutcome::Unknown
    }
    if root.is_poisoned() || receipt.outcome == AgentReceiptOutcome::Unknown {
        terminal = AgentTerminal::OutcomeUnknown;
        reason = AgentReason::StorageFailure
    }
    let mut summary = AgentRunSummary {
        request_id: run.intent.request_id.clone(),
        variant: run.intent.variant.clone(),
        source_build_identity: run.intent.source_build_identity.clone(),
        identity: run.identity.clone(),
        terminal,
        reason,
        receipt,
    };
    if let Ok(done) = &result {
        if let Some(sink) = observer {
            // A diagnostic callback cannot manufacture runtime success or leak a panic across FFI.
            // Production always has None. The trusted test sink must itself be bounded/nonblocking.
            let _ =
                std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| sink.observe(&run, done)));
        }
    }
    if service_evidence::persist(root, &run, &summary).is_err() {
        summary.terminal = AgentTerminal::OutcomeUnknown;
        summary.reason = AgentReason::StorageFailure;
    }
    let recovery = summary.terminal == AgentTerminal::OutcomeUnknown || root.is_poisoned();
    ExecutionSettlement {
        snapshot: AgentRunSnapshot::Terminal { summary },
        recovery,
    }
}
