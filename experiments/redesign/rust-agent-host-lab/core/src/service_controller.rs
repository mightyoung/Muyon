//! Compiling refusing service seam. This checkpoint does not run an Agent.
use crate::{service_runtime::BuiltinExecution, service_types::*};
use std::sync::Arc;
/// Rust test diagnostics only. No C/UniFFI export or UI-controlled selector.
/// Observes immutable actual worker output; it cannot supply authority or a driver.
#[doc(hidden)]
pub trait ServiceEvidenceObserver: Send + Sync {
    fn observe(&self, run: &AgentDurableRun, execution: &BuiltinExecution);
}
pub const SERVICE_STUB_REACHED: &str = "AGENT_SERVICE_STUB_REACHED";
pub struct AgentServiceController {
    meta: AgentReplyMeta,
    _observer: Option<Arc<dyn ServiceEvidenceObserver>>,
}
impl AgentServiceController {
    pub fn new(config: AgentHostServiceConfig) -> Result<Self, AgentServiceError> {
        Self::construct(config, None)
    }
    /// Rust-only diagnostic constructor; shares the shipping controller implementation.
    #[doc(hidden)]
    pub fn new_with_observer(
        config: AgentHostServiceConfig,
        observer: Arc<dyn ServiceEvidenceObserver>,
    ) -> Result<Self, AgentServiceError> {
        Self::construct(config, Some(observer))
    }
    fn construct(
        config: AgentHostServiceConfig,
        observer: Option<Arc<dyn ServiceEvidenceObserver>>,
    ) -> Result<Self, AgentServiceError> {
        if config.protocol != 1 {
            return Err(AgentServiceError::UnsupportedProtocol);
        }
        if config.build_identity.len() != 40
            || !config
                .build_identity
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        {
            return Err(AgentServiceError::InvalidIdentity);
        }
        let epoch = crate::nonce().map_err(|_| AgentServiceError::InternalFailure)?;
        Ok(Self {
            _observer: observer,
            meta: AgentReplyMeta {
                protocol: 1,
                build_identity: config.build_identity,
                service_epoch: epoch,
                server_snapshot_revision: 0,
            },
        })
    }
    fn meta(&self) -> AgentReplyMeta {
        self.meta.clone()
    }
    pub fn connect(&self, _req: AgentConnectRequest) -> AgentConnectReply {
        AgentConnectReply {
            meta: self.meta(),
            outcome: AgentConnectOutcome::Connected {
                client_lease: self.meta.service_epoch.clone(),
                service_state: AgentServiceState::Initializing,
            },
        }
    }
    pub fn start_run(&self, _req: AgentStartRequest) -> AgentStartReply {
        eprintln!("AGENT_SERVICE_STUB_REACHED code=internal_failure");
        AgentStartReply {
            meta: self.meta(),
            outcome: AgentStartOutcome::Rejected {
                error: AgentServiceError::InternalFailure,
            },
        }
    }
    fn refused_snapshot(&self) -> AgentSnapshotReply {
        AgentSnapshotReply {
            meta: self.meta(),
            outcome: AgentSnapshotOutcome::Snapshot {
                service_state: AgentServiceState::Initializing,
                run: None,
            },
        }
    }
    pub fn status(&self, _req: AgentStatusRequest) -> AgentSnapshotReply {
        self.refused_snapshot()
    }
    pub fn current(&self, _req: AgentClientRef) -> AgentSnapshotReply {
        self.refused_snapshot()
    }
    pub fn lookup(&self, _req: AgentLookupRequest) -> AgentSnapshotReply {
        self.refused_snapshot()
    }
    pub fn set_visibility(&self, _req: AgentVisibilityRequest) -> AgentControlReply {
        AgentControlReply {
            meta: self.meta(),
            outcome: AgentControlOutcome::Applied,
        }
    }
    fn refused_control(&self) -> AgentControlReply {
        AgentControlReply {
            meta: self.meta(),
            outcome: AgentControlOutcome::Rejected {
                error: AgentServiceError::InternalFailure,
            },
        }
    }
    pub fn release_client(&self, _req: AgentReleaseRequest) -> AgentControlReply {
        self.refused_control()
    }
    pub fn cancel(&self, _req: AgentCancelRequest) -> AgentControlReply {
        self.refused_control()
    }
    pub fn client_gone(&self, _platform_client_key: String) -> AgentControlReply {
        self.refused_control()
    }
    pub fn close(&self, _req: AgentClientRef) -> AgentCloseReply {
        AgentCloseReply {
            meta: self.meta(),
            outcome: AgentCloseOutcome::Closing,
        }
    }
    pub fn retire_service(&self) -> AgentCloseReply {
        AgentCloseReply {
            meta: self.meta(),
            outcome: AgentCloseOutcome::Closing,
        }
    }
    pub fn await_settled(&self) -> AgentSnapshotReply {
        self.refused_snapshot()
    }
}
