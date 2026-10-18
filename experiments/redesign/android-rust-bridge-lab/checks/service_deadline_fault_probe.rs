// Compiled only in an immutable private source copy, never shipping code.
use muyon_rust_agent_host_lab::{service_controller::AgentServiceController, service_types::*};
use std::path::PathBuf;
#[test]
fn service_private_fault_contract() {
    let case = std::env::var("SERVICE_FAULT_CASE").unwrap();
    let evidence = PathBuf::from(std::env::var("SERVICE_FAULT_EVIDENCE").unwrap());
    let root = evidence.join("private-root");
    muyon_core_agent_lab::store::create_dir(&root).unwrap();
    let c = AgentServiceController::new(AgentHostServiceConfig {
        protocol: 1, private_root: root.to_string_lossy().into(), build_identity: "a".repeat(40),
    }).unwrap();
    assert!(matches!(c.await_settled().outcome, AgentSnapshotOutcome::Snapshot {service_state: AgentServiceState::Ready, run: None}));
    let connected = c.connect(AgentConnectRequest {protocol: 1, platform_client_key: "b".repeat(32)});
    let AgentConnectOutcome::Connected {client_lease, ..} = connected.outcome else {panic!("probe_connect_failed")};
    let client = AgentClientRef {protocol: 1, expected_service_epoch: connected.meta.service_epoch, client_lease};
    assert_eq!(c.set_visibility(AgentVisibilityRequest {client: client.clone(), observation_generation: 1, visible: true}).outcome, AgentControlOutcome::Applied);
    assert!(matches!(c.start_run(AgentStartRequest {client: client.clone(), request_id: "fault_probe".into(), variant: AgentReadVariant::Equipment}).outcome, AgentStartOutcome::QueuedVolatile {..}));
    c.await_settled();
    let AgentSnapshotOutcome::Snapshot {run: Some(snapshot), ..} = c.current(client).outcome else {panic!("probe_snapshot_missing")};
    let (terminal, reason, receipt) = match snapshot {
        AgentRunSnapshot::Terminal {summary} => (summary.terminal, summary.reason, summary.receipt),
        AgentRunSnapshot::Unresolved {observation} => (AgentTerminal::OutcomeUnknown, AgentReason::Interrupted, observation.receipt),
        _ => panic!("probe_unsettled"),
    };
    let original = std::fs::read_to_string(evidence.join("original-opaque.txt")).unwrap();
    let dir = std::fs::read_to_string(evidence.join("run-dir.txt")).unwrap();
    assert_eq!(std::fs::read(PathBuf::from(dir).join("native.db")).unwrap(), std::fs::read(evidence.join("original-native.db")).unwrap(), "probe_native_bytes_changed");
    println!("FAULT_OBSERVED {case} terminal={terminal:?} reason={reason:?} receipt={:?} opaque_match={}", receipt.outcome, receipt.opaque_id.as_deref() == Some(original.as_str()));
    let expected = AgentTerminal::BudgetExhausted;
    assert!(terminal == expected && reason == AgentReason::DeadlineExceeded && receipt.outcome == AgentReceiptOutcome::RecordedSuccess && receipt.opaque_id.as_deref() == Some(original.as_str()), "SERVICE_DEADLINE_LATE_CANCEL_RED: deadline cause survives later cancel");
    c.retire_service(); c.await_settled();
}
