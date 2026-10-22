use muyon_core_agent_lab::store;
use muyon_rust_agent_host_lab::{service_root::ServiceRoot, service_types::*};
use std::{
    path::PathBuf,
    sync::atomic::{AtomicUsize, Ordering},
};
static NEXT: AtomicUsize = AtomicUsize::new(0);
fn root() -> PathBuf {
    let p = std::env::temp_dir().join(format!(
        "muyon-service-root-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    store::create_dir(&p).unwrap();
    p
}
fn intent() -> AgentIntentBinding {
    AgentIntentBinding {
        request_id: "read_1".into(),
        variant: AgentReadVariant::Equipment,
        source_build_identity: "a".repeat(40),
    }
}
#[test]
fn root_lease_serializes_durable_admission_and_preserves_identity() {
    let dir = root();
    let lease = ServiceRoot::open(&dir);
    assert!(
        lease.is_ok(),
        "SERVICE_ROOT_RED: real private namespace must acquire an exclusive root lease"
    );
    let mut lease = lease.unwrap();
    assert!(!lease.recovery_required());
    assert!(matches!(ServiceRoot::open(&dir),Err(ref e) if e=="directory_locked"));
    let run = lease.admit(intent(), &"b".repeat(32)).unwrap();
    assert_eq!(run.intent, intent());
    assert_eq!(run.identity.admitted_service_epoch, "b".repeat(32));
    assert_eq!(run.identity.run_id.len(), 32);
    assert_eq!(run.identity.actual_task, None);
    let run_dir = lease.run_dir(&run.identity.run_id).unwrap();
    store::validate_dir(&run_dir).unwrap();
    let state = muyon_core_agent_lab::agent::State::runtime(
        "synthetic identity only".into(),
        "selected-record".into(),
        Default::default(),
    )
    .unwrap();
    let task = AgentTaskIdentity {
        task_id: state.task,
        attempt_id: state.attempt,
    };
    assert!(lease
        .attach_task(
            &run.identity.run_id,
            AgentTaskIdentity {
                task_id: "../escape".into(),
                attempt_id: task.attempt_id.clone()
            }
        )
        .is_err());
    let attached = lease.attach_task(&run.identity.run_id, task.clone());
    assert!(
        attached.is_ok(),
        "SERVICE_TASK_ID_RED: preserve actual Core task and attempt identifiers without re-signing"
    );
    let before = store::read(&dir.join("native-agent-service-v1/index.db")).unwrap();
    assert!(before.contains(&run.identity.run_id));
    assert!(before.contains(&task.task_id));
    assert!(
        matches!(lease.admit(intent(),&"b".repeat(32)),Err(ref e) if e=="service_request_exists")
    );
    assert!(lease.run_dir("../escape").is_err());
    drop(lease);
    let reopened = ServiceRoot::open(&dir).unwrap();
    assert!(
        reopened.recovery_required(),
        "an admitted run without terminal evidence must not be replayed"
    );
    assert_eq!(reopened.runs().len(), 1);
    assert_eq!(reopened.runs()[0].identity.actual_task, Some(task));
    assert_eq!(
        store::read(&dir.join("native-agent-service-v1/index.db")).unwrap(),
        before
    );
}
#[test]
fn root_inventory_refuses_unowned_entries_and_peak_overflow() {
    let oversized = root();
    let ns = oversized.join("native-agent-service-v1");
    store::create_dir(&ns).unwrap();
    store::atomic(&ns, "index.db", &"x".repeat(65537)).unwrap();
    assert!(matches!(ServiceRoot::open(&oversized),Err(ref e) if e=="service_index_bound"));
    let linked = root();
    let ns = linked.join("native-agent-service-v1");
    store::create_dir(&ns).unwrap();
    store::atomic(&linked, "outside.db", "private unrelated file").unwrap();
    std::os::unix::fs::symlink(linked.join("outside.db"), ns.join("index.db")).unwrap();
    assert!(matches!(ServiceRoot::open(&linked),Err(ref e) if e=="service_index_file"));
    let bad = root();
    let namespace = bad.join("native-agent-service-v1");
    store::create_dir(&namespace).unwrap();
    store::atomic(&namespace, "unexpected.db", "unknown evidence").unwrap();
    assert!(
        matches!(ServiceRoot::open(&bad),Err(ref e) if e=="service_root_inventory"),
        "SERVICE_ROOT_INVENTORY_RED: never initialize over unknown evidence"
    );
    assert!(!namespace.join("index.db").exists());
    let dir = root();
    let mut lease = ServiceRoot::open(&dir).unwrap();
    let mut first = None;
    for n in 0..8 {
        let mut i = intent();
        i.request_id = format!("read_{n}");
        let run = lease.admit(i, &"b".repeat(32)).unwrap();
        if first.is_none() {
            first = Some(run.identity.run_id);
        }
    }
    let index = store::read(&dir.join("native-agent-service-v1/index.db")).unwrap();
    let mut i = intent();
    i.request_id = "ninth".into();
    assert!(matches!(lease.admit(i.clone(),&"b".repeat(32)),Err(ref e) if e=="service_root_quota"));
    assert_eq!(
        store::read(&dir.join("native-agent-service-v1/index.db")).unwrap(),
        index
    );
    drop(lease);
    let peak = root();
    let mut lease = ServiceRoot::open(&peak).unwrap();
    let r = lease.admit(intent(), &"b".repeat(32)).unwrap();
    let run_dir = lease.run_dir(&r.identity.run_id).unwrap();
    for n in 0..7 {
        store::atomic(&run_dir, &format!(".task.db.9.{n}"), &"x".repeat(1_000_000)).unwrap();
    }
    let mut i = intent();
    i.request_id = "overflow".into();
    assert!(matches!(lease.admit(i,&"b".repeat(32)),Err(ref e) if e=="service_root_quota"));
    assert_eq!(lease.runs().len(), 1);
}
