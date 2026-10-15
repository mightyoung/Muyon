//! Private Rust oracle: the public controller admission/worker must produce the evidence.
//! The shipping UniFFI ABI has no observer, payload or raw receipt export.
use muyon_core_agent_lab::store;
use muyon_plugin_contract_lab::{parse, Json};
use muyon_rust_agent_host_lab::{
    field,
    service_controller::{AgentServiceController, ServiceEvidenceObserver},
    service_runtime::BuiltinExecution,
    service_types::*,
};
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Mutex,
    },
};
static NEXT: AtomicUsize = AtomicUsize::new(0);
const SOURCE: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
struct Observed {
    run: AgentDurableRun,
    task: String,
    attempt: String,
    receipts: Vec<Json>,
    payloads: Vec<Vec<u8>>,
    handlers: usize,
    calls: u64,
    steps: u64,
}
#[derive(Default)]
struct Sink(Mutex<Option<Observed>>);
impl ServiceEvidenceObserver for Sink {
    fn observe(&self, run: &AgentDurableRun, execution: &BuiltinExecution) {
        let mut slot = self.0.lock().unwrap();
        assert!(slot.is_none(), "observer is bounded to one actual run");
        assert!(
            execution.payloads.len() <= 2 && execution.payloads.iter().all(|p| p.len() <= 65536)
        );
        assert!(execution.receipts.len() <= 1);
        *slot = Some(Observed {
            run: run.clone(),
            task: execution.state.task.clone(),
            attempt: execution.state.attempt.clone(),
            receipts: execution.receipts.clone(),
            payloads: execution.payloads.clone(),
            handlers: execution.handler_calls,
            calls: execution.state.counters.calls,
            steps: execution.state.counters.steps,
        });
    }
}
fn root() -> PathBuf {
    let p = std::env::temp_dir().join(format!(
        "muyon-service-oracle-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    store::create_dir(&p).unwrap();
    p
}
#[test]
fn service_controller_observer_correlates_all_builtin_payloads() {
    for (variant, module, typ, key) in [
        (
            AgentReadVariant::Equipment,
            "equipment_loan",
            "equipment",
            "e1",
        ),
        (AgentReadVariant::Research, "research", "project", "p1"),
        (AgentReadVariant::Inquiry, "inquiry", "supplier", "s1"),
        (
            AgentReadVariant::SeededEquipment,
            "module_f65579dc",
            "asset",
            "e1",
        ),
    ] {
        let root = root();
        let sink = Arc::new(Sink::default());
        let c = AgentServiceController::new_with_observer(
            AgentHostServiceConfig {
                protocol: 1,
                private_root: root.to_string_lossy().into(),
                build_identity: SOURCE.into(),
            },
            sink.clone(),
        )
        .unwrap();
        c.await_settled();
        let connection = c.connect(AgentConnectRequest {
            protocol: 1,
            platform_client_key: "b".repeat(32),
        });
        let AgentConnectOutcome::Connected { client_lease, .. } = connection.outcome else {
            panic!("real controller lease required")
        };
        let client = AgentClientRef {
            protocol: 1,
            expected_service_epoch: connection.meta.service_epoch.clone(),
            client_lease,
        };
        assert_eq!(
            c.set_visibility(AgentVisibilityRequest {
                client: client.clone(),
                observation_generation: 1,
                visible: true
            })
            .outcome,
            AgentControlOutcome::Applied
        );
        let start = c.start_run(AgentStartRequest {
            client: client.clone(),
            request_id: "observed_read".into(),
            variant: variant.clone(),
        });
        assert!(matches!(start.outcome,AgentStartOutcome::QueuedVolatile{..}),"SERVICE_CONTROLLER_ORACLE_RED: actual successful controller admission must precede private execution evidence");
        c.await_settled();
        let settled = c.current(client);
        let AgentSnapshotOutcome::Snapshot {
            run: Some(AgentRunSnapshot::Terminal { summary }),
            ..
        } = settled.outcome
        else {
            panic!("joined actual controller must publish terminal")
        };
        assert_eq!(summary.terminal, AgentTerminal::Completed);
        assert_eq!(summary.reason, AgentReason::None);
        assert_eq!(summary.request_id, "observed_read");
        assert_eq!(summary.variant, variant);
        assert_eq!(summary.source_build_identity, SOURCE);
        let observed = sink.0.lock().unwrap();
        let evidence = observed
            .as_ref()
            .expect("same worker must invoke the private immutable observer");
        assert_eq!(evidence.run.intent.request_id, summary.request_id);
        assert_eq!(evidence.run.intent.variant, summary.variant);
        assert_eq!(
            evidence.run.intent.source_build_identity,
            summary.source_build_identity
        );
        assert_eq!(evidence.run.identity, summary.identity);
        assert_eq!(
            summary.identity.admitted_service_epoch,
            connection.meta.service_epoch
        );
        assert_eq!(
            summary.identity.actual_task,
            Some(AgentTaskIdentity {
                task_id: evidence.task.clone(),
                attempt_id: evidence.attempt.clone()
            })
        );
        assert_eq!(
            (evidence.calls, evidence.steps, evidence.handlers),
            (2, 2, 1)
        );
        assert_eq!(evidence.payloads.len(), 2);
        assert_eq!(evidence.receipts.len(), 1);
        let receipt = &evidence.receipts[0];
        let receipt_id = field(field(receipt, "identity").unwrap(), "identity")
            .unwrap()
            .string()
            .unwrap();
        assert_eq!(
            summary.receipt,
            AgentReceiptSummary {
                opaque_id: Some(receipt_id.into()),
                outcome: AgentReceiptOutcome::RecordedSuccess
            }
        );
        let path = root
            .join("native-agent-service-v1")
            .join(&summary.identity.run_id);
        assert!(store::read(&path.join("source.db"))
            .unwrap()
            .contains("BORROWER_PRIVATE"));
        let native = parse(store::read(&path.join("native.db")).unwrap().as_bytes()).unwrap();
        assert_eq!(
            field(&native, "receipts").unwrap().array().unwrap(),
            &evidence.receipts
        );
        assert!(field(receipt, "raw")
            .unwrap()
            .encode()
            .contains("BORROWER_PRIVATE"));
        let task = store::read(&path.join("task.db")).unwrap();
        assert!(task.contains(&evidence.task) && task.contains(&evidence.attempt));
        let first = parse(&evidence.payloads[0]).unwrap();
        let second = parse(&evidence.payloads[1]).unwrap();
        assert_eq!(field(&first, "tools").unwrap().array().unwrap().len(), 1);
        assert_eq!(field(&second, "tools").unwrap().array().unwrap().len(), 0);
        let body = String::from_utf8(evidence.payloads[1].clone()).unwrap();
        assert!(body.contains(module) && body.contains(typ) && body.contains(key));
        assert!(body.contains("service_call1") && body.contains(receipt_id));
        assert!(!body.contains("BORROWER_PRIVATE"));
        assert!(evidence
            .payloads
            .iter()
            .all(|p| !String::from_utf8_lossy(p).contains("BORROWER_PRIVATE")));
        drop(observed);
        c.retire_service();
        c.await_settled();
    }
}
