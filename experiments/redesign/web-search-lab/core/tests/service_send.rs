//! Exact new-root ordinary-Send route target. No sockets/Agent::open/legacy suites.
use muyon_rust_agent_host_lab::{
    service_controller::AgentServiceController, service_host::*, service_provider::*,
    service_types::*,
};
use muyon_web_search_lab::{chat_route::*, *};
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Condvar, Mutex,
    },
};
struct Settings(Mutex<Json>);
impl ToolSettingsSource for Settings {
    fn snapshot(&self) -> Result<Json> {
        Ok(self.0.lock().unwrap().clone())
    }
}
fn cfg(enabled: bool, connection: &str, revision: u64) -> Json {
    object([
        ("version", Json::Number("1".into())),
        ("enabled", Json::Bool(enabled)),
        ("provider", string("deepseek-search")),
        ("connection", string(connection)),
        ("revision", Json::Number(revision.to_string())),
    ])
}
struct NoChatOwner;
impl ServiceHostOwner for NoChatOwner {
    fn current_scope(&self) -> Result<ServiceHostScope> {
        Err("none".into())
    }
    fn provider(&self) -> Result<ServiceProviderBridge> {
        Err("none".into())
    }
}
static SERIAL: AtomicUsize = AtomicUsize::new(0);
fn open(s: Arc<dyn ToolSettingsSource>, synthetic: bool) -> (PathBuf, AgentServiceController, AgentClientRef) {
    let p = std::env::temp_dir().join(format!(
        "muyon-send-{}-{}",
        std::process::id(),
        SERIAL.fetch_add(1, Ordering::SeqCst)
    ));
    std::fs::create_dir(&p).unwrap();
    std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o700)).unwrap();
    let ports = ServiceHostPorts::new(
        Arc::new(NoChatOwner),
        ServiceHostMode::ConfiguredChat,
        CallBudget {
            max_tokens: 1,
            max_micros: 1,
            requires_tools: false,
            requires_streaming: false,
        },
    )
    .with_tools(Arc::new(ConfiguredToolRoute {
        settings: s,
        synthetic,
    }));
    let c = AgentServiceController::new_with_host(
        AgentHostServiceConfig {
            protocol: 1,
            private_root: p.to_str().unwrap().into(),
            build_identity: "a".repeat(40),
        },
        Arc::new(ports),
    )
    .unwrap();
    c.await_settled();
    let r = c.connect(AgentConnectRequest {
        protocol: 1,
        platform_client_key: "b".repeat(32),
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
    (p, c, client)
}
fn submit(c: &AgentServiceController, client: &AgentClientRef, id: &str, text: &str) -> Json {
    let first = c.submit_ordinary_chat(
        client.clone(),
        id.into(),
        "conversation1".into(),
        text.into(),
    );
    assert!(
        first.contains("accepted") || first.contains("existing") || first.contains("rejected"),
        "{first}"
    );
    c.await_settled();
    parse(
        c.supplier_read_events(client.clone(), id.into(), 0)
            .as_bytes(),
    )
    .unwrap()
}
fn clean(p: PathBuf, c: AgentServiceController) {
    c.retire_service();
    c.await_settled();
    drop(c);
    std::fs::remove_dir_all(p).unwrap();
}
// Hold the real route at its execution-time settings check, after durable admission.
// No Service, runtime or provider result is replaced by a test double.
struct PausedSettings {
    reads: AtomicUsize,
    gate: Mutex<(bool, bool)>,
    changed: Condvar,
}
impl ToolSettingsSource for PausedSettings {
    fn snapshot(&self) -> Result<Json> {
        if self.reads.fetch_add(1, Ordering::SeqCst) == 1 {
            let mut gate = self.gate.lock().unwrap();
            gate.0 = true;
            self.changed.notify_all();
            while !gate.1 {
                gate = self.changed.wait(gate).unwrap();
            }
        }
        Ok(cfg(true, "search-connection", 1))
    }
}
#[test]
fn admitted_registered_send_stays_pollable_until_real_result_is_available() {
    let settings = Arc::new(PausedSettings {
        reads: AtomicUsize::new(0),
        gate: Mutex::new((false, false)),
        changed: Condvar::new(),
    });
    let (p, c, client) = open(settings.clone(), true);
    let first = c.submit_ordinary_chat(client.clone(), "pending".into(), "conversation1".into(), "find fixture".into());
    let gate = settings.gate.lock().unwrap();
    let (gate, _) = settings.changed.wait_timeout_while(gate, std::time::Duration::from_secs(5), |state| !state.0).unwrap();
    let entered = gate.0;
    drop(gate);
    let early = c.supplier_read_events(client.clone(), "pending".into(), 0);
    {
        let mut gate = settings.gate.lock().unwrap();
        gate.1 = true;
        settings.changed.notify_all();
    }
    c.await_settled();
    let complete = c.supplier_read_events(client, "pending".into(), 0);
    clean(p, c);
    assert!(entered, "real route did not reach its execution-time settings check");
    assert!(first.contains("accepted"), "{first}");
    let early = parse(early.as_bytes()).unwrap();
    let fields = early.object().unwrap();
    assert_eq!(fields["status"], string("events"), "{}", early.encode());
    assert_eq!(fields["terminal"], Json::Bool(false), "{}", early.encode());
    assert_eq!(fields["events"], Json::Array(Vec::new()));
    assert_ne!(fields["run_id"], Json::Null);
    assert!(complete.contains("completed") && complete.contains("tool_receipt"), "{complete}");
}
#[test]
fn registered_source_label_is_frozen_from_trusted_route_not_host_mode() {
    for synthetic in [true, false] {
        let settings = Arc::new(Settings(Mutex::new(cfg(true, "search-connection", 1))));
        let (p, c, client) = open(settings, synthetic);
        let first = c.submit_ordinary_chat(client.clone(), "source-kind".into(), "conversation1".into(), "find fixture".into());
        c.await_settled();
        let complete = c.supplier_read_events(client, "source-kind".into(), 0);
        clean(p, c);
        for wire in [first, complete] {
            let value = parse(wire.as_bytes()).unwrap();
            assert_eq!(value.object().unwrap()["synthetic"], Json::Bool(synthetic), "{wire}");
        }
    }
}
#[test]
fn ordinary_send_reaches_registered_provider_and_returns_bound_sources_empty_and_error() {
    let s = Arc::new(Settings(Mutex::new(cfg(true, "search-connection", 1))));
    let (p, c, client) = open(s, true);
    for (id, q, expected) in [
        ("one", "find fixture", "completed"),
        ("two", "empty fixture", "completed"),
        ("three", "error fixture", "failed"),
    ] {
        let r = submit(&c, &client, id, q);
        let wire = r.encode();
        assert!(wire.contains(expected), "{wire}");
        let run = r.object().unwrap()["run_id"].string().unwrap();
        let d = p.join("native-agent-service-v1").join(run);
        assert!(d.join("registered-result.db").is_file());
        assert!(!d.join("ordinary-send-v1.db").exists());
        if id == "one" {
            assert!(wire.contains("tool_projection"));
            assert!(wire.contains("https://example.org/source"));
            assert!(wire.contains("instruction_authority"));
            assert!(wire.contains("tool_receipt"));
            assert!(wire.contains("750"));
        }
        if id == "two" {
            assert!(wire.contains("empty_success"));
            assert!(wire.contains("没有找到匹配结果"));
        }
        if id == "three" {
            assert!(wire.contains("search_authentication_failed"));
            assert!(!wire.contains("tool_projection"));
        }
    }
    clean(p, c);
}
#[test]
fn enabled_unconfigured_and_no_host_fail_explicitly_without_fallback_or_outbound() {
    for (connection, synthetic, reason) in [
        ("", true, "search_unconfigured"),
        ("search-connection", false, "search_transport_unavailable"),
    ] {
        let s = Arc::new(Settings(Mutex::new(cfg(true, connection, 1))));
        let (p, c, client) = open(s, synthetic);
        let r = submit(&c, &client, "nohost", "find fixture");
        assert!(r.encode().contains(reason), "{}", r.encode());
        assert!(r.encode().contains("failed"));
        let run = r.object().unwrap()["run_id"].string().unwrap();
        let d = p.join("native-agent-service-v1").join(run);
        assert!(!d.join("search-outbound.db").exists());
        assert!(!d.join("ordinary-send-v1.db").exists());
        clean(p, c);
    }
}
#[test]
fn explicit_disabled_uses_inherited_chat_but_corrupt_settings_never_fallback() {
    let s = Arc::new(Settings(Mutex::new(cfg(false, "", 1))));
    let (p, c, client) = open(s, false);
    let r = submit(&c, &client, "plain", "plain fixture");
    assert!(
        r.encode().contains("chat_authority_unconfigured"),
        "{}",
        r.encode()
    );
    clean(p, c);
    let s = Arc::new(Settings(Mutex::new(string("corrupt"))));
    let (p, c, client) = open(s, true);
    let r = submit(&c, &client, "corrupt", "plain fixture");
    assert!(
        r.encode().contains("search_config_corrupt"),
        "{}",
        r.encode()
    );
    assert!(!r.encode().contains("chat_authority_unconfigured"));
    clean(p, c);
}
#[test]
fn old_request_keeps_frozen_route_and_changed_config_hides_disclosure_without_resend() {
    let s = Arc::new(Settings(Mutex::new(cfg(true, "search-connection", 1))));
    let (p, c, client) = open(s.clone(), true);
    let first = submit(&c, &client, "stable", "find fixture");
    let run = first.object().unwrap()["run_id"].clone();
    let d = p
        .join("native-agent-service-v1")
        .join(run.string().unwrap());
    let outbound = std::fs::read(d.join("search-outbound.db")).unwrap();
    *s.0.lock().unwrap() = cfg(false, "", 2);
    let r = submit(&c, &client, "stable", "find fixture");
    assert_eq!(r.object().unwrap()["run_id"], run);
    assert!(r.encode().contains("DISCLOSURE_UNAVAILABLE"));
    assert!(!r.encode().contains("https://example.org/source"));
    assert_eq!(
        std::fs::read(d.join("search-outbound.db")).unwrap(),
        outbound
    );
    clean(p, c);
}
#[test]
fn unknown_is_not_redispatched_by_duplicate_submit_or_original_event_lookup() {
    let s = Arc::new(Settings(Mutex::new(cfg(true, "search-connection", 1))));
    let (p, c, client) = open(s, true);
    let r = submit(&c, &client, "unknown", "unknown fixture");
    assert!(r.encode().contains("unknown"));
    let run = r.object().unwrap()["run_id"].string().unwrap();
    let path = p
        .join("native-agent-service-v1")
        .join(run)
        .join("search-outbound.db");
    let bytes = std::fs::read(&path).unwrap();
    c.submit_ordinary_chat(
        client.clone(),
        "unknown".into(),
        "conversation1".into(),
        "unknown fixture".into(),
    );
    c.await_settled();
    c.supplier_read_events(client, "unknown".into(), 0);
    assert_eq!(std::fs::read(path).unwrap(), bytes);
    clean(p, c);
}
fn mutate(j: &mut Json, path: &[&str], value: Json) {
    if path.len() == 1 {
        if let Json::Object(m) = j {
            m.insert(path[0].into(), value);
        }
    } else if let Json::Object(m) = j {
        mutate(m.get_mut(path[0]).unwrap(), &path[1..], value)
    }
}
#[test]
fn missing_or_tampered_query_outbound_cost_call_and_config_hide_sources_without_resend() {
    for case in 0..6 {
        let s = Arc::new(Settings(Mutex::new(cfg(true, "search-connection", 1))));
        let (p, c, client) = open(s, true);
        let r = submit(&c, &client, "bound", "find fixture");
        let run = r.object().unwrap()["run_id"].string().unwrap();
        let d = p.join("native-agent-service-v1").join(run);
        let ledger = d.join("search-outbound.db");
        let before = std::fs::read(&ledger).unwrap();
        match case {
            0 => {
                let path = d.join("native.db");
                let mut j = parse(&std::fs::read(&path).unwrap()).unwrap();
                if let Json::Object(m) = &mut j {
                    if let Json::Array(rows) = m.get_mut("receipts").unwrap() {
                        mutate(
                            &mut rows[0],
                            &["binding", "args", "query"],
                            string("different query"),
                        );
                    }
                }
                std::fs::write(path, j.encode()).unwrap();
            }
            1 => std::fs::remove_file(&ledger).unwrap(),
            _ => {
                let mut j = parse(&before).unwrap();
                match case {
                    2 => mutate(&mut j, &["max_micros"], Json::Number("1".into())),
                    3 => mutate(&mut j, &["call"], string("other-call")),
                    4 => mutate(&mut j, &["config", "revision"], Json::Number("2".into())),
                    _ => mutate(&mut j, &["credential_generation"], Json::Number("2".into())),
                };
                std::fs::write(&ledger, j.encode()).unwrap();
            }
        }
        let after = c.supplier_read_events(client, "bound".into(), 0);
        assert!(
            after.contains("DISCLOSURE_UNAVAILABLE"),
            "case={case} {after}"
        );
        assert!(!after.contains("https://example.org/source"));
        assert!(!after.contains("tool_projection"));
        if case == 0 {
            assert_eq!(std::fs::read(&ledger).unwrap(), before)
        }
        clean(p, c);
    }
}
fn reopen(p: &PathBuf, s: Arc<Settings>) -> (AgentServiceController, AgentClientRef) {
    let ports = ServiceHostPorts::new(
        Arc::new(NoChatOwner),
        ServiceHostMode::ConfiguredChat,
        CallBudget {
            max_tokens: 1,
            max_micros: 1,
            requires_tools: false,
            requires_streaming: false,
        },
    )
    .with_tools(Arc::new(ConfiguredToolRoute {
        settings: s,
        synthetic: true,
    }));
    let c = AgentServiceController::new_with_host(
        AgentHostServiceConfig {
            protocol: 1,
            private_root: p.to_str().unwrap().into(),
            build_identity: "a".repeat(40),
        },
        Arc::new(ports),
    )
    .unwrap();
    c.await_settled();
    let r = c.connect(AgentConnectRequest {
        protocol: 1,
        platform_client_key: "c".repeat(32),
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
    (c, client)
}
#[test]
fn passive_service_restore_revalidates_original_result_without_executing_stored_agent() {
    let s = Arc::new(Settings(Mutex::new(cfg(true, "search-connection", 1))));
    let (p, c, client) = open(s.clone(), true);
    let first = submit(&c, &client, "restore", "find fixture");
    let run = first.object().unwrap()["run_id"].clone();
    let epoch = first.object().unwrap()["admitted_service_epoch"].clone();
    let d = p
        .join("native-agent-service-v1")
        .join(run.string().unwrap());
    let outbound = std::fs::read(d.join("search-outbound.db")).unwrap();
    c.retire_service();
    c.await_settled();
    drop(c);
    // ServiceRoot inventory/receipt parsing only; never Agent::open, HTTP or task execution.
    let (c, client) = reopen(&p, s.clone());
    assert_ne!(client.expected_service_epoch, epoch.string().unwrap());
    let restored = parse(
        c.supplier_read_events(client.clone(), "restore".into(), 0)
            .as_bytes(),
    )
    .unwrap();
    assert_eq!(restored.object().unwrap()["run_id"], run);
    assert_eq!(restored.object().unwrap()["admitted_service_epoch"], epoch);
    assert!(restored.encode().contains("completed"));
    assert!(restored.encode().contains("https://example.org/source"));
    assert_eq!(
        std::fs::read(d.join("search-outbound.db")).unwrap(),
        outbound
    );
    *s.0.lock().unwrap() = cfg(false, "", 2);
    let hidden = c.supplier_read_events(client, "restore".into(), 0);
    assert!(hidden.contains("DISCLOSURE_UNAVAILABLE"));
    assert!(!hidden.contains("https://example.org/source"));
    assert_eq!(
        std::fs::read(d.join("search-outbound.db")).unwrap(),
        outbound
    );
    clean(p, c);
}
