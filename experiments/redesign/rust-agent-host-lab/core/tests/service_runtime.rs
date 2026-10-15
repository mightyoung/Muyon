use muyon_core_agent_lab::store;
use muyon_plugin_contract_lab::{parse, string, Json};
use muyon_rust_agent_host_lab::{
    field,
    service_runtime::{run_builtin, RunControl},
    service_types::AgentReadVariant,
};
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
};
static NEXT: AtomicUsize = AtomicUsize::new(0);
fn directory() -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "muyon-service-runtime-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    store::create_dir(&dir).unwrap();
    dir
}
#[test]
fn all_builtins_read_physical_file_and_journal_two_actual_payloads() {
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
        let dir = directory();
        let result = run_builtin(&dir, variant, Arc::new(RunControl::new()));
        assert!(result.is_ok(),"SERVICE_RUNTIME_RED: same Agent drive must physically execute a registered built-in read");
        let done = result.unwrap();
        assert_eq!(done.state.status, "completed");
        assert_eq!(done.state.counters.calls, 2);
        assert_eq!(done.state.counters.steps, 2);
        assert_eq!(done.handler_calls, 1);
        assert_eq!(done.receipts.len(), 1);
        assert_eq!(done.payloads.len(), 2);
        let source = store::read(&dir.join("source.db")).unwrap();
        assert!(source.contains("BORROWER_PRIVATE"));
        let native = parse(store::read(&dir.join("native.db")).unwrap().as_bytes()).unwrap();
        let receipts = field(&native, "receipts").unwrap().array().unwrap();
        assert_eq!(receipts, &done.receipts);
        assert_eq!(field(&receipts[0], "status"), Ok(&string("succeeded")));
        assert!(field(&receipts[0], "raw")
            .unwrap()
            .encode()
            .contains("BORROWER_PRIVATE"));
        assert_eq!(field(&done.facts, "external_read"), Ok(&Json::Bool(true)));
        assert_eq!(field(&done.facts, "unknown_source"), Ok(&Json::Bool(true)));
        let second = String::from_utf8(done.payloads[1].clone()).unwrap();
        assert!(second.contains(module));
        assert!(second.contains(typ));
        assert!(second.contains(key));
        assert!(!second.contains("BORROWER_PRIVATE"));
        let body = parse(&done.payloads[1]).unwrap();
        assert_eq!(
            field(&body, "tools").unwrap().array().unwrap().len(),
            0,
            "second turn must publish no new calls"
        );
        assert!(store::read(&dir.join("task.db"))
            .unwrap()
            .contains(&done.state.task));
        assert!(store::read(&dir.join("task.db"))
            .unwrap()
            .contains(&done.state.attempt));
    }
}
#[test]
fn pre_cancelled_worker_never_bootstraps_or_reads() {
    let dir = directory();
    let control = Arc::new(RunControl::new());
    control.request_cancel();
    let result = run_builtin(&dir, AgentReadVariant::Equipment, control);
    assert!(
        matches!(result,Err(ref reason) if reason=="native_cancelled"),
        "SERVICE_PRE_CANCEL_RED: control must reach worker before any store/bootstrap"
    );
    assert!(!dir.join("native.db").exists());
    assert!(!dir.join("source.db").exists());
    assert!(!dir.join("task.db").exists());
}
