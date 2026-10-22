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
    if case == "c2_worker_panic" {
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while !c.private_probe_worker_finished() {
            assert!(std::time::Instant::now() < deadline, "probe_worker_finish_timeout");
            std::thread::yield_now();
        }
        let before_join = kernel_lock(&root);
        println!("FAULT_LEASE worker_finished_before_join={}", before_join.trim());
        assert!(before_join == "busy\n", "SERVICE_PRIVATE_LEASE_RED: worker completion retains original root until Closed");
    }
    c.await_settled();
    if case == "c2_worker_panic" {
        assert_eq!(kernel_lock(&root), "busy\n");
        println!("FAULT_LEASE after_join_before_close=busy");
    }
    let AgentSnapshotOutcome::Snapshot {run: Some(snapshot), ..} = c.current(client).outcome else {panic!("probe_snapshot_missing")};
    let (terminal, receipt) = match snapshot {
        AgentRunSnapshot::Terminal {summary} => (summary.terminal, summary.receipt),
        AgentRunSnapshot::Unresolved {observation} => (AgentTerminal::OutcomeUnknown, observation.receipt),
        _ => panic!("probe_unsettled"),
    };
    let original = std::fs::read_to_string(evidence.join("original-opaque.txt")).unwrap();
    let dir = std::fs::read_to_string(evidence.join("run-dir.txt")).unwrap();
    assert_eq!(std::fs::read(PathBuf::from(dir).join("native.db")).unwrap(), std::fs::read(evidence.join("original-native.db")).unwrap(), "probe_native_bytes_changed");
    println!("FAULT_OBSERVED {case} terminal={terminal:?} receipt={:?} opaque_match={}", receipt.outcome, receipt.opaque_id.as_deref() == Some(original.as_str()));
    let expected = if case == "c3_cancel" {AgentTerminal::Cancelled} else {AgentTerminal::OutcomeUnknown};
    assert!(terminal == expected && receipt.outcome == AgentReceiptOutcome::RecordedSuccess && receipt.opaque_id.as_deref() == Some(original.as_str()), "SERVICE_PRIVATE_FAULT_RED: preserve actual receipt and normalized terminal");
    c.retire_service();
    assert!(matches!(c.await_settled().outcome, AgentSnapshotOutcome::Snapshot {service_state: AgentServiceState::Closed, ..}));
    if case == "c2_worker_panic" {
        assert_eq!(kernel_lock(&root), "available\n");
        println!("FAULT_LEASE after_closed=available");
    }
}

fn kernel_lock(root: &std::path::Path) -> String {
    let result = std::process::Command::new("python3")
        .arg(std::env::var("SERVICE_FAULT_LOCK_PROBE").unwrap())
        .arg(root.join("native-agent-service-v1/.lock")).output().unwrap();
    assert!(result.status.success(), "probe_kernel_lock_child_failed");
    assert!(result.stderr.is_empty());
    String::from_utf8(result.stdout).unwrap()
}
