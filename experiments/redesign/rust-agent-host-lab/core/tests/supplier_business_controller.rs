use muyon_plugin_contract_lab::{parse, Json};
use muyon_rust_agent_host_lab::{service_controller::AgentServiceController, service_types::*};
use std::{
    path::PathBuf,
    sync::atomic::{AtomicUsize, Ordering},
};
static NEXT: AtomicUsize = AtomicUsize::new(0);
fn value(s: &str, k: &str) -> Json {
    parse(s.as_bytes()).unwrap().object().unwrap()[k].clone()
}
fn make(root: &PathBuf) -> AgentServiceController {
    AgentServiceController::new(AgentHostServiceConfig {
        protocol: 1,
        private_root: root.to_str().unwrap().into(),
        build_identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
    })
    .unwrap()
}
fn connect(c: &AgentServiceController, key: &str) -> AgentClientRef {
    c.await_settled();
    let r = c.connect(AgentConnectRequest {
        protocol: 1,
        platform_client_key: key.into(),
    });
    let AgentConnectOutcome::Connected { client_lease, .. } = r.outcome else {
        panic!("connect")
    };
    let client = AgentClientRef {
        protocol: 1,
        expected_service_epoch: r.meta.service_epoch,
        client_lease,
    };
    c.set_visibility(AgentVisibilityRequest {
        client: client.clone(),
        observation_generation: 1,
        visible: true,
    });
    client
}
#[test]
fn business_read_is_real_durable_and_reconnect_never_executes_again() {
    let root = std::env::temp_dir().join(format!(
        "muyon-business-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    muyon_core_agent_lab::store::create_dir(&root).unwrap();
    let c = make(&root);
    let client = connect(&c, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    let invalid = c.submit_supplier_read(
        client.clone(),
        "bad".into(),
        "  ".into(),
        "11111111-1111-4111-8111-111111111111".into(),
        "7".into(),
    );
    assert_eq!(value(&invalid, "status"), Json::String("rejected".into()));
    let submitted = c.submit_supplier_read(
        client.clone(),
        "business1".into(),
        "读取选中的供应商".into(),
        "11111111-1111-4111-8111-111111111111".into(),
        "7".into(),
    );
    assert_eq!(value(&submitted, "status"), Json::String("accepted".into()));
    c.await_settled();
    let events = c.supplier_read_events(client.clone(), "business1".into(), 0);
    assert_eq!(value(&events, "terminal"), Json::Bool(true), "{events}");
    let es = value(&events, "events");
    let es = es.array().unwrap();
    assert_eq!(es.len(), 4, "{events}");
    assert_eq!(
        es[3].object().unwrap()["payload"].object().unwrap()["state"],
        Json::String("completed".into()),
        "{events}"
    );
    let receipt = es[2].object().unwrap()["payload"].clone();
    let run = value(&events, "run_id").string().unwrap().to_owned();
    let dir = root.join("native-agent-service-v1").join(&run);
    let original = std::fs::read(dir.join("native.db")).unwrap();
    assert!(String::from_utf8_lossy(&original).contains(&receipt.encode()));
    let conflict = c.submit_supplier_read(
        client.clone(),
        "business1".into(),
        "different".into(),
        "11111111-1111-4111-8111-111111111111".into(),
        "7".into(),
    );
    assert_eq!(
        value(&conflict, "reason"),
        Json::String("RequestConflict".into())
    );
    let duplicate = c.submit_supplier_read(
        client.clone(),
        "business1".into(),
        "读取选中的供应商".into(),
        "11111111-1111-4111-8111-111111111111".into(),
        "7".into(),
    );
    assert_eq!(value(&duplicate, "status"), Json::String("existing".into()));
    assert_eq!(std::fs::read(dir.join("native.db")).unwrap(), original);
    let mut stale = client.clone();
    stale.expected_service_epoch = "cccccccccccccccccccccccccccccccc".into();
    assert_eq!(
        value(
            &c.supplier_read_events(stale, "business1".into(), 0),
            "status"
        ),
        Json::String("rejected".into())
    );
    c.retire_service();
    c.await_settled();
    drop(c);
    let c = make(&root);
    let client = connect(&c, "dddddddddddddddddddddddddddddddd");
    let replay = c.supplier_read_events(client.clone(), "business1".into(), 0);
    assert_eq!(
        value(&replay, "events"),
        Json::Array(es.to_vec()),
        "{replay}"
    );
    assert_eq!(value(&replay, "run_id"), Json::String(run));
    assert_eq!(std::fs::read(dir.join("native.db")).unwrap(), original);
    let tail = c.supplier_read_events(client.clone(), "business1".into(), 3);
    assert_eq!(value(&tail, "events").array().unwrap().len(), 1);
    let gone = c.supplier_read_events(client.clone(), "missing".into(), 0);
    assert_eq!(value(&gone, "status"), Json::String("unknown".into()));
    let bad_cursor = c.supplier_read_events(client.clone(), "business1".into(), 5);
    assert_eq!(
        value(&bad_cursor, "status"),
        Json::String("rejected".into())
    );
    // A forged or corrupted receipt cannot be replayed from the cached projection.
    std::fs::write(dir.join("native.db"), b"corrupted receipt").unwrap();
    let corrupt = c.supplier_read_events(client.clone(), "business1".into(), 0);
    assert_eq!(
        value(&corrupt, "reason"),
        Json::String("DISCLOSURE_UNAVAILABLE".into())
    );
    assert!(value(&corrupt, "events").array().unwrap().is_empty());
    std::fs::write(dir.join("native.db"), &original).unwrap();
    // Replacing the synthetic source revokes display and does not destroy historical receipts.
    std::fs::write(dir.join("lab-supplier.siq"), b"replaced").unwrap();
    let revoked = c.supplier_read_events(client, "business1".into(), 0);
    assert_eq!(
        value(&revoked, "reason"),
        Json::String("DISCLOSURE_UNAVAILABLE".into())
    );
    assert!(value(&revoked, "events").array().unwrap().is_empty());
    assert_eq!(std::fs::read(dir.join("native.db")).unwrap(), original);
    c.retire_service();
    c.await_settled();
    drop(c);
    std::fs::remove_dir_all(root).unwrap();
    let root = std::env::temp_dir().join(format!(
        "muyon-business-cancel-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    muyon_core_agent_lab::store::create_dir(&root).unwrap();
    let c = make(&root);
    let client = connect(&c, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
    c.submit_supplier_read(
        client.clone(),
        "cancel1".into(),
        "read supplier".into(),
        "11111111-1111-4111-8111-111111111111".into(),
        "7".into(),
    );
    let cancel = c.cancel(AgentCancelRequest {
        client: client.clone(),
        run: AgentRunRef {
            request_id: "cancel1".into(),
            variant: AgentReadVariant::Inquiry,
            run_id: None,
        },
    });
    assert!(matches!(
        cancel.outcome,
        AgentControlOutcome::Requested | AgentControlOutcome::AlreadyTerminal
    ));
    c.await_settled();
    let cancelled = c.supplier_read_events(client, "cancel1".into(), 0);
    assert_eq!(
        value(&cancelled, "terminal"),
        Json::Bool(true),
        "{cancelled}"
    );
    c.retire_service();
    c.await_settled();
    drop(c);
    std::fs::remove_dir_all(root).unwrap();
}
