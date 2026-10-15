use muyon_rust_agent_host_lab::{service_controller::AgentServiceController, service_types::*};
use std::{
    path::PathBuf,
    sync::atomic::{AtomicUsize, Ordering},
};
static NEXT: AtomicUsize = AtomicUsize::new(0);
// Explicit semantic-test identity, not an artifact/source provenance claim.
const TEST_ID: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
fn root() -> PathBuf {
    std::env::temp_dir().join(format!(
        "muyon-service-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ))
}
fn controller() -> AgentServiceController {
    AgentServiceController::new(AgentHostServiceConfig {
        protocol: 1,
        private_root: root().to_string_lossy().into(),
        build_identity: TEST_ID.into(),
    })
    .unwrap()
}
fn connected(c: &AgentServiceController) -> AgentClientRef {
    let reply = c.connect(AgentConnectRequest {
        protocol: 1,
        platform_client_key: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".into(),
    });
    assert_eq!(reply.meta.protocol, 1);
    assert_eq!(reply.meta.build_identity, TEST_ID);
    assert_eq!(reply.meta.service_epoch.len(), 32);
    let AgentConnectOutcome::Connected { client_lease, .. } = reply.outcome else {
        panic!("real controller connect must return a correlated client lease")
    };
    AgentClientRef {
        protocol: 1,
        expected_service_epoch: reply.meta.service_epoch,
        client_lease,
    }
}
#[test]
fn service_controller_executes_registered_read() {
    let c = controller();
    let client = connected(&c);
    let visible = c.set_visibility(AgentVisibilityRequest {
        client: client.clone(),
        observation_generation: 1,
        visible: true,
    });
    assert_eq!(visible.outcome, AgentControlOutcome::Applied);
    let start = c.start_run(AgentStartRequest {
        client: client.clone(),
        request_id: "read_1".into(),
        variant: AgentReadVariant::Equipment,
    });
    // This first seam guard proves native controller entry/refusal, NOT Agent dispatch.
    assert!(
        matches!(
            start.outcome,
            AgentStartOutcome::QueuedVolatile { .. }
                | AgentStartOutcome::Rejected {
                    error: AgentServiceError::InternalFailure
                }
        ),
        "initial result must reach the known controller seam"
    );
    let _ = c.await_settled();
    let observed = c.current(client.clone());
    let completed = matches!(&observed.outcome,AgentSnapshotOutcome::Snapshot{run:Some(AgentRunSnapshot::Terminal{summary}),..} if summary.terminal==AgentTerminal::Completed);
    assert!(
        completed,
        "AGENT_SERVICE_RED: admitted run must complete the registered physical read"
    );
    let AgentSnapshotOutcome::Snapshot {
        run: Some(AgentRunSnapshot::Terminal { summary }),
        ..
    } = observed.outcome
    else {
        unreachable!()
    };
    assert_eq!(summary.request_id, "read_1");
    assert_eq!(summary.variant, AgentReadVariant::Equipment);
    assert_eq!(summary.source_build_identity, TEST_ID);
    assert!(
        summary.identity.actual_task.is_some(),
        "Completed requires real paired State identity"
    );
    assert_eq!(
        summary.receipt.outcome,
        AgentReceiptOutcome::RecordedSuccess
    );
    assert!(summary.receipt.opaque_id.is_some());
    assert_eq!(summary.reason, AgentReason::None);
    let run_id = summary.identity.run_id.clone();
    let looked = c.lookup(AgentLookupRequest {
        client,
        key: AgentLookupKey::RunId { run_id },
    });
    assert_eq!(
        looked.outcome,
        AgentSnapshotOutcome::Snapshot {
            service_state: AgentServiceState::Ready,
            run: Some(AgentRunSnapshot::Terminal { summary })
        },
        "lookup must copy original settled identity without another run"
    );
}
#[test]
fn controller_is_send_sync_without_moving_native_session() {
    fn require<T: Send + Sync>() {}
    require::<AgentServiceController>();
}
#[test]
fn build_identity_is_explicit_without_host_build_environment() {
    let c = controller();
    assert_eq!(
        c.connect(AgentConnectRequest {
            protocol: 1,
            platform_client_key: "cccccccccccccccccccccccccccccccc".into()
        })
        .meta
        .build_identity,
        TEST_ID
    );
    let bad = AgentServiceController::new(AgentHostServiceConfig {
        protocol: 1,
        private_root: root().to_string_lossy().into(),
        build_identity: "not-a-source-sha".into(),
    });
    assert!(matches!(bad, Err(AgentServiceError::InvalidIdentity)));
}
#[test]
fn zero_client_initialization_retirement_requires_real_settlement() {
    let c = controller();
    assert_eq!(
        c.retire_service().outcome,
        AgentCloseOutcome::Closing,
        "retire is pending, not fabricated Closed"
    );
    let settled = c.await_settled();
    assert!(
        matches!(
            settled.outcome,
            AgentSnapshotOutcome::Snapshot {
                service_state: AgentServiceState::Closed,
                run: None
            }
        ),
        "RETIRE_SERVICE_RED: zero-client late constructor must close only after actual settlement"
    );
    assert_eq!(
        c.retire_service().outcome,
        AgentCloseOutcome::Closed,
        "retirement is permanent and idempotent after join"
    );
}
