use muyon_core_agent_lab::store;
use muyon_rust_agent_host_lab::{service_controller::AgentServiceController, service_types::*};
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Mutex, MutexGuard,
    },
};
static SERIAL: Mutex<()> = Mutex::new(());
static NEXT: AtomicUsize = AtomicUsize::new(0);
struct Drain<'a>(&'a AgentServiceController);
impl Drop for Drain<'_> {
    fn drop(&mut self) {
        self.0.retire_service();
        self.0.await_settled();
    }
}
const SOURCE: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
fn root() -> PathBuf {
    let p = std::env::temp_dir().join(format!(
        "muyon-service-lifecycle-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    store::create_dir(&p).unwrap();
    p
}
fn config(root: &std::path::Path) -> AgentHostServiceConfig {
    AgentHostServiceConfig {
        protocol: 1,
        private_root: root.to_string_lossy().into(),
        build_identity: SOURCE.into(),
    }
}
struct Runtime {
    c: AgentServiceController,
    root: PathBuf,
    _serial: MutexGuard<'static, ()>,
}
impl Drop for Runtime {
    fn drop(&mut self) {
        self.c.retire_service();
        self.c.await_settled();
    }
}
impl Runtime {
    fn new() -> Self {
        let serial = SERIAL
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let root = root();
        let c = AgentServiceController::new(config(&root)).unwrap();
        let r = Self {
            c,
            root,
            _serial: serial,
        };
        assert!(
            matches!(
                r.c.await_settled().outcome,
                AgentSnapshotOutcome::Snapshot {
                    service_state: AgentServiceState::Ready,
                    run: None
                }
            ),
            "SERVICE_INIT_RED: only joined valid root inventory becomes Ready"
        );
        r
    }
    fn client(&self, key: char) -> AgentClientRef {
        connect(&self.c, key)
    }
}
fn connect(c: &AgentServiceController, key: char) -> AgentClientRef {
    let r = c.connect(AgentConnectRequest {
        protocol: 1,
        platform_client_key: key.to_string().repeat(32),
    });
    let AgentConnectOutcome::Connected { client_lease, .. } = r.outcome else {
        panic!("client connect must succeed")
    };
    AgentClientRef {
        protocol: 1,
        expected_service_epoch: r.meta.service_epoch,
        client_lease,
    }
}
fn visible(
    c: &AgentServiceController,
    client: &AgentClientRef,
    g: i64,
    v: bool,
) -> AgentControlReply {
    c.set_visibility(AgentVisibilityRequest {
        client: client.clone(),
        observation_generation: g,
        visible: v,
    })
}
fn start(
    c: &AgentServiceController,
    client: &AgentClientRef,
    id: &str,
    variant: AgentReadVariant,
) -> AgentStartReply {
    c.start_run(AgentStartRequest {
        client: client.clone(),
        request_id: id.into(),
        variant,
    })
}
fn summary(c: &AgentServiceController, client: &AgentClientRef) -> AgentRunSummary {
    let s = c.current(client.clone());
    let AgentSnapshotOutcome::Snapshot {
        run: Some(AgentRunSnapshot::Terminal { summary }),
        ..
    } = s.outcome
    else {
        panic!("joined runtime must expose its original terminal")
    };
    assert_eq!(summary.terminal, AgentTerminal::Completed);
    summary
}
#[test]
fn client_epochs_generations_and_visibility_are_fail_closed() {
    let r = Runtime::new();
    let one = r.client('b');
    let two = r.client('c');
    assert_eq!(
        r.c.connect(AgentConnectRequest {
            protocol: 1,
            platform_client_key: "d".repeat(32)
        })
        .outcome,
        AgentConnectOutcome::Busy
    );
    assert_eq!(
        r.c.connect(AgentConnectRequest {
            protocol: 1,
            platform_client_key: "b".repeat(32)
        })
        .outcome,
        AgentConnectOutcome::Connected {
            client_lease: one.client_lease.clone(),
            service_state: AgentServiceState::Ready
        }
    );
    let mut old = one.clone();
    old.expected_service_epoch = "e".repeat(32);
    assert_eq!(
        visible(&r.c, &old, 1, true).outcome,
        AgentControlOutcome::Rejected {
            error: AgentServiceError::EpochMismatch
        }
    );
    assert_eq!(
        visible(&r.c, &one, 2, true).outcome,
        AgentControlOutcome::Applied
    );
    let revision = r.c.current(one.clone()).meta.server_snapshot_revision;
    assert_eq!(
        visible(&r.c, &one, 2, true).outcome,
        AgentControlOutcome::Applied
    );
    assert_eq!(
        r.c.current(one.clone()).meta.server_snapshot_revision,
        revision
    );
    assert_eq!(
        visible(&r.c, &one, 1, false).outcome,
        AgentControlOutcome::Rejected {
            error: AgentServiceError::InvalidGeneration
        }
    );
    assert_eq!(
        visible(&r.c, &one, 2, false).outcome,
        AgentControlOutcome::Rejected {
            error: AgentServiceError::InvalidGeneration
        }
    );
    assert_eq!(
        visible(&r.c, &two, 1, true).outcome,
        AgentControlOutcome::Applied
    );
    assert_eq!(
        visible(&r.c, &one, 3, false).outcome,
        AgentControlOutcome::Applied
    );
    assert_eq!(
        visible(&r.c, &two, 2, false).outcome,
        AgentControlOutcome::Applied
    );
    assert_eq!(
        visible(&r.c, &one, 4, true).outcome,
        AgentControlOutcome::Rejected {
            error: AgentServiceError::Closed
        }
    );
    assert_eq!(
        start(&r.c, &one, "sealed", AgentReadVariant::Equipment).outcome,
        AgentStartOutcome::Rejected {
            error: AgentServiceError::Closed
        }
    );
    assert!(matches!(
        r.c.await_settled().outcome,
        AgentSnapshotOutcome::Snapshot {
            service_state: AgentServiceState::Closed,
            run: None
        }
    ));
}
#[test]
fn same_request_is_existing_without_a_second_worker() {
    let r = Runtime::new();
    let client = r.client('b');
    assert_eq!(
        visible(&r.c, &client, 1, true).outcome,
        AgentControlOutcome::Applied
    );
    assert!(matches!(
        start(&r.c, &client, "original", AgentReadVariant::Equipment).outcome,
        AgentStartOutcome::QueuedVolatile { .. }
    ));
    r.c.await_settled();
    let done = summary(&r.c, &client);
    let path = r
        .root
        .join("native-agent-service-v1")
        .join(&done.identity.run_id);
    let before = store::read(&path.join("native.db")).unwrap();
    let index = store::read(&r.root.join("native-agent-service-v1/index.db")).unwrap();
    let repeated = start(&r.c, &client, "original", AgentReadVariant::Equipment);
    assert_eq!(
        repeated.outcome,
        AgentStartOutcome::Existing {
            snapshot: AgentRunSnapshot::Terminal {
                summary: done.clone()
            }
        }
    );
    assert_eq!(
        start(&r.c, &client, "original", AgentReadVariant::Inquiry).outcome,
        AgentStartOutcome::Rejected {
            error: AgentServiceError::RequestConflict
        }
    );
    assert_eq!(store::read(&path.join("native.db")).unwrap(), before);
    assert_eq!(
        store::read(&r.root.join("native-agent-service-v1/index.db")).unwrap(),
        index
    );
    assert_eq!(
        r.c.lookup(AgentLookupRequest {
            client: client.clone(),
            key: AgentLookupKey::RequestId {
                request_id: "original".into()
            }
        })
        .outcome,
        AgentSnapshotOutcome::Snapshot {
            service_state: AgentServiceState::Ready,
            run: Some(AgentRunSnapshot::Terminal { summary: done })
        }
    );
    assert_eq!(
        r.c.cancel(AgentCancelRequest {
            client,
            run: AgentRunRef {
                request_id: "original".into(),
                variant: AgentReadVariant::Equipment,
                run_id: None
            }
        })
        .outcome,
        AgentControlOutcome::AlreadyTerminal
    );
}
#[test]
fn close_and_reconnect_preserve_original_durable_outcome() {
    let r = Runtime::new();
    let client = r.client('b');
    visible(&r.c, &client, 1, true);
    assert!(matches!(
        start(&r.c, &client, "original", AgentReadVariant::Inquiry).outcome,
        AgentStartOutcome::QueuedVolatile { .. }
    ));
    r.c.await_settled();
    let done = summary(&r.c, &client);
    let path = r
        .root
        .join("native-agent-service-v1")
        .join(&done.identity.run_id);
    let native = store::read(&path.join("native.db")).unwrap();
    let task = store::read(&path.join("task.db")).unwrap();
    assert_eq!(
        r.c.close(client.clone()).outcome,
        AgentCloseOutcome::Closing
    );
    assert!(
        matches!(
            AgentServiceController::new(config(&r.root)),
            Err(AgentServiceError::Busy)
        ),
        "close request cannot release the process slot before actual settlement"
    );
    assert!(matches!(
        r.c.await_settled().outcome,
        AgentSnapshotOutcome::Snapshot {
            service_state: AgentServiceState::Closed,
            ..
        }
    ));
    let readonly = connect(&r.c, 'c');
    assert_eq!(
        visible(&r.c, &readonly, 1, true).outcome,
        AgentControlOutcome::Rejected {
            error: AgentServiceError::Closed
        }
    );
    assert_eq!(summary(&r.c, &readonly), done);
    let replacement = AgentServiceController::new(config(&r.root)).unwrap();
    let _drain = Drain(&replacement);
    let settled = replacement.await_settled();
    assert!(matches!(
        settled.outcome,
        AgentSnapshotOutcome::Snapshot {
            service_state: AgentServiceState::Ready,
            ..
        }
    ));
    let replacement_client = connect(&replacement, 'd');
    assert_ne!(
        replacement_client.expected_service_epoch,
        client.expected_service_epoch
    );
    assert_eq!(summary(&replacement, &replacement_client), done);
    assert_eq!(store::read(&path.join("native.db")).unwrap(), native);
    assert_eq!(store::read(&path.join("task.db")).unwrap(), task);
    // Settling an old Closed object must not release its replacement's process gate.
    r.c.retire_service();
    r.c.await_settled();
    assert!(matches!(
        AgentServiceController::new(config(&root())),
        Err(AgentServiceError::Busy)
    ));
    replacement.retire_service();
    replacement.await_settled();
}

#[test]
fn incomplete_temp_evidence_blocks_ready_without_cleanup() {
    let r = Runtime::new();
    let client = r.client('b');
    assert_eq!(
        visible(&r.c, &client, 1, true).outcome,
        AgentControlOutcome::Applied
    );
    assert!(matches!(
        start(&r.c, &client, "original", AgentReadVariant::Equipment).outcome,
        AgentStartOutcome::QueuedVolatile { .. }
    ));
    r.c.await_settled();
    let done = summary(&r.c, &client);
    let path = r
        .root
        .join("native-agent-service-v1")
        .join(&done.identity.run_id);
    let native = store::read(&path.join("native.db")).unwrap();
    let task = store::read(&path.join("task.db")).unwrap();
    r.c.retire_service();
    r.c.await_settled();
    // Separate fresh controller/lease: valid committed evidence restores normally.
    let healthy = AgentServiceController::new(config(&r.root)).unwrap();
    let healthy_drain = Drain(&healthy);
    assert!(matches!(
        healthy.await_settled().outcome,
        AgentSnapshotOutcome::Snapshot {
            service_state: AgentServiceState::Ready,
            ..
        }
    ));
    let healthy_client = connect(&healthy, 'c');
    assert_eq!(summary(&healthy, &healthy_client), done);
    healthy.retire_service();
    healthy.await_settled();
    drop(healthy_drain);
    let remnant = ".task.db.9.1";
    store::atomic(&path, remnant, "unfinished task candidate").unwrap();
    let interrupted = AgentServiceController::new(config(&r.root)).unwrap();
    let _drain = Drain(&interrupted);
    let state = interrupted.await_settled();
    assert!(matches!(state.outcome,AgentSnapshotOutcome::Snapshot{service_state:AgentServiceState::RecoveryRequired,..}),
        "SERVICE_TEMP_RED: incomplete durable candidate forbids Ready even with a valid prior terminal");
    assert_eq!(
        store::read(&path.join(remnant)).unwrap(),
        "unfinished task candidate"
    );
    assert_eq!(store::read(&path.join("native.db")).unwrap(), native);
    assert_eq!(store::read(&path.join("task.db")).unwrap(), task);
}
