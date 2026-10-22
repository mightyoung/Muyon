//! Same-crate source harness exercises actual pub(crate) BusinessStore seams.
#![allow(dead_code)]
#[path = "/workspace/mig20/crates/muyon-core/src/agent/mod.rs"]
mod agent;
#[path = "/workspace/mig20/crates/muyon-core/src/archive.rs"]
mod archive;
#[path = "/workspace/mig20/crates/muyon-core/src/blobs.rs"]
mod blobs;
#[path = "/workspace/mig20/crates/muyon-core/src/business.rs"]
mod business;
#[path = "/workspace/mig20/crates/muyon-core/src/contract.rs"]
mod contract;
#[path = "/workspace/mig20/crates/muyon-core/src/group_runtime/store.rs"]
mod group_runtime_store;
#[path = "/workspace/mig20/crates/muyon-core/src/research.rs"]
mod research;
#[path = "/workspace/mig20/crates/muyon-core/src/review_lifecycle.rs"]
mod review_lifecycle;
#[path = "/workspace/mig20/crates/muyon-core/src/sqlite.rs"]
mod sqlite;
use business::BusinessStore;
use contract::*;
use group_runtime_store::*;
#[path = "/workspace/mig20/crates/muyon-core/src/group_runtime/bridge.rs"]
mod group_runtime_bridge;
use group_runtime_bridge::*;
use serde_json::json;
use std::{
    collections::{BTreeMap, BTreeSet},
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "mig20-store-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&p).unwrap();
        Self(p)
    }
    fn path(&self) -> PathBuf {
        self.0.join("business.sqlite")
    }
    fn store(&self) -> BusinessStore {
        BusinessStore::open_existing(&self.path(), "ws", "epoch").unwrap()
    }
    fn init(&self) -> BusinessStore {
        BusinessStore::initialize(&self.path(), "ws").unwrap();
        let s = self.store();
        let mut c:CommandEnvelope=serde_json::from_value(json!({"protocol_version":1,"business_version":1,"intent_id":"project-create","scope":{"workspace_id":"ws","project_id":"project"},"expected_revision":"0","authority":{"grant_id":"project-grant","generation":"1","owner_epoch":"epoch"},"plan_id":"project-plan","plan_digest":"0".repeat(64),"command":{"operation":"project_create","project_id":"project","name":"Synthetic"}})).unwrap();
        c.plan_digest = c.expected_plan_digest().unwrap();
        s.issue_grant_trusted(&c, None).unwrap();
        assert_eq!(s.execute(&c).unwrap().status, ExecutionStatus::Committed);
        s.initialize_group_runtime().unwrap();
        s
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn command(id: &str, revision: u64, operation: GroupOperation) -> GroupCommand {
    GroupCommand {
        intent_id: id.into(),
        workspace_id: "ws".into(),
        project_id: "project".into(),
        group_id: "group".into(),
        expected_revision: Revision::new(revision),
        expected_epoch: None,
        actor: GroupActor::Human("owner".into()),
        authority: AuthorityBinding {
            grant_id: format!("grant-{id}"),
            generation: Revision::new(1),
            owner_epoch: "epoch".into(),
        },
        operation,
    }
}
fn registration() -> GroupOperation {
    GroupOperation::Register {
        owner: "owner".into(),
        admins: BTreeSet::from(["admin".into()]),
        conversation_id: "conversation".into(),
        mode: "per_task".into(),
        fixed_leader: None,
        members: BTreeMap::from([
            (
                "a".into(),
                Capabilities {
                    scopes: BTreeSet::from(["project".into()]),
                    permissions: BTreeSet::from(["read".into()]),
                },
            ),
            (
                "b".into(),
                Capabilities {
                    scopes: BTreeSet::from(["project".into()]),
                    permissions: BTreeSet::from(["read".into()]),
                },
            ),
        ]),
    }
}
fn apply(s: &BusinessStore, c: &GroupCommand) -> LocalReceipt {
    s.issue_group_local_grant_trusted(c).unwrap();
    s.execute_group_local(c, None).unwrap()
}
fn start(s: &BusinessStore) {
    apply(s, &command("register", 0, registration()));
    apply(
        s,
        &command(
            "start",
            1,
            GroupOperation::Start {
                run_id: "run".into(),
                root_task_id: "root".into(),
                leader: Some("a".into()),
                max_rounds: 8,
                max_handoffs: 2,
                deadline_ms: u64::MAX,
            },
        ),
    );
}
fn mutation(id: &str, rev: u64, epoch: u64, op: GroupOperation) -> GroupCommand {
    let mut c = command(id, rev, op);
    c.expected_epoch = Some(epoch);
    c
}
fn config(mode: &str) -> GroupOperation {
    let r = registration();
    let GroupOperation::Register { members, .. } = r else {
        unreachable!()
    };
    GroupOperation::Configure {
        mode: mode.into(),
        fixed_leader: if mode == "fixed" {
            Some("b".into())
        } else {
            None
        },
        members,
    }
}
fn ui_scope(s: &BusinessStore) -> GroupUiScope {
    GroupUiScope::current(s, "project", "owner").unwrap()
}
fn read(s: &BusinessStore, request: serde_json::Value) -> serde_json::Value {
    s.group_ui_read(
        &ui_scope(s),
        &json!({"schema_version":1,"request":request}).to_string(),
        None,
        None,
    )
    .unwrap()
}
#[test]
fn configure_defaults_are_real_cas_writes_and_running_tasks_keep_mode_and_members() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let c = command("configure", 2, config("host_only"));
    assert_eq!(apply(&s, &c).status, LocalStatus::Committed);
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(s.group_registration(&scope).unwrap().mode, "host_only");
    assert_eq!(
        s.group_run(&scope, "run")
            .unwrap()
            .coordination_mode
            .as_deref(),
        Some("per_task")
    );
    drop(s);
    let s = f.store();
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(s.group_registration(&scope).unwrap().mode, "host_only");
    assert_eq!(
        s.group_run(&scope, "run").unwrap().leader.as_deref(),
        Some("a")
    );
    assert_eq!(s.group_run(&scope, "run").unwrap().members.len(), 2);
}
#[test]
fn configuring_legacy_records_freezes_the_previous_actual_mode_before_defaults_change() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let rows = s
        .database()
        .query(
            "SELECT record FROM group_runtime_runs WHERE run_id='run'",
            &[],
        )
        .unwrap();
    let mut old: serde_json::Value = serde_json::from_str(rows[0][0].as_ref().unwrap()).unwrap();
    old.as_object_mut().unwrap().remove("coordination_mode");
    s.database()
        .exec(
            "UPDATE group_runtime_runs SET record=? WHERE run_id='run'",
            &[&old.to_string()],
        )
        .unwrap();
    apply(&s, &command("configure", 2, config("host_only")));
    let raw = s
        .database()
        .query(
            "SELECT record FROM group_runtime_runs WHERE run_id='run'",
            &[],
        )
        .unwrap();
    let v: serde_json::Value = serde_json::from_str(raw[0][0].as_ref().unwrap()).unwrap();
    assert_eq!(v["coordination_mode"], "per_task");
}
#[test]
fn configure_rejects_unknown_modes_stale_cas_and_invalid_fixed_leader() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    for (index, op) in [
        config("automatic"),
        GroupOperation::Configure {
            mode: "fixed".into(),
            fixed_leader: Some("absent".into()),
            members: BTreeMap::new(),
        },
    ]
    .into_iter()
    .enumerate()
    {
        let c = command(&format!("bad-{index}"), 2, op);
        assert_eq!(apply(&s, &c).status, LocalStatus::Rejected);
    }
    apply(&s, &command("configure", 2, config("fixed")));
    assert_eq!(
        apply(&s, &command("stale", 2, config("host_only"))).status,
        LocalStatus::Rejected
    );
}
#[test]
fn mode_catalog_and_configuration_prepare_default_only_new_groups_to_host_only() {
    let f = Fixture::new();
    let s = f.init();
    let catalog = read(&s, json!({"operation":"catalog"}));
    assert_eq!(catalog["default_mode"], "host_only");
    assert_eq!(catalog["execution_authority"], false);
    let raw=json!({"schema_version":1,"change":{"operation":"register","intent_id":"ui-register","group_id":"group","expected_revision":"0","members":{"a":{"scopes":["project"],"permissions":["read"]}}}}).to_string();
    let auth = AuthorityBinding {
        grant_id: "ui-grant".into(),
        generation: Revision::new(1),
        owner_epoch: "epoch".into(),
    };
    let c = s
        .group_ui_prepare_configuration(&ui_scope(&s), &raw, auth, Some("conversation"))
        .unwrap();
    let GroupOperation::Register { mode, .. } = &c.operation else {
        panic!("wrong command")
    };
    assert_eq!(mode, "host_only");
    assert!(GroupScope::current(&s, "project", "group").is_err());
    assert!(s.execute_group_local(&c, None).is_err());
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::Committed
    );
    let bad=json!({"schema_version":1,"change":{"operation":"configure","intent_id":"ui-change","group_id":"group","expected_revision":"1","members":{"a":{"scopes":["project"],"permissions":["read"]}}}}).to_string();
    let auth = AuthorityBinding {
        grant_id: "other".into(),
        generation: Revision::new(1),
        owner_epoch: "epoch".into(),
    };
    assert!(s
        .group_ui_prepare_configuration(&ui_scope(&s), &bad, auth, None)
        .is_err());
}
#[test]
fn bridge_json_is_strict_and_cannot_nominate_host_scope_or_authority() {
    let f = Fixture::new();
    let s = f.init();
    for raw in [
        r#"{"schema_version":1,"schema_version":1,"request":{"operation":"catalog"}}"#,
        r#"{"schema_version":2,"request":{"operation":"catalog"}}"#,
        r#"{"schema_version":1,"workspace_id":"other","request":{"operation":"catalog"}}"#,
        r#"{"schema_version":1,"request":{"operation":"sql","statement":"delete"}}"#,
    ] {
        assert!(s.group_ui_read(&ui_scope(&s), raw, None, None).is_err());
    }
}
#[test]
fn group_lists_and_get_are_persisted_and_paginated_with_management_separate_from_coordination() {
    let f = Fixture::new();
    let s = f.init();
    apply(&s, &command("register", 0, registration()));
    let mut c = command("register-z", 0, registration());
    c.group_id = "z-group".into();
    apply(&s, &c);
    let first = read(&s, json!({"operation":"groups","limit":1}));
    assert_eq!(first["groups"].as_array().unwrap().len(), 1);
    assert_eq!(first["groups"][0]["group_id"], "group");
    assert_eq!(first["groups"][0]["management_role"], "owner");
    assert_eq!(first["groups"][0]["default_mode"], "per_task");
    let second = read(
        &s,
        json!({"operation":"groups","limit":1,"after_group_id":"group"}),
    );
    assert_eq!(second["groups"][0]["group_id"], "z-group");
    let scope = GroupUiScope::current(&s, "project", "a").unwrap();
    let v = s
        .group_ui_read(
            &scope,
            &json!({"schema_version":1,"request":{"operation":"group","group_id":"group"}})
                .to_string(),
            None,
            None,
        )
        .unwrap();
    assert_eq!(v["group"]["management_role"], "none");
    assert_eq!(v["group"]["members"].as_object().unwrap().len(), 2);
}
#[test]
fn live_owner_absence_is_explicit_and_local_intent_receipts_are_actual() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let view = read(
        &s,
        json!({"operation":"run","group_id":"group","run_id":"run"}),
    );
    assert_eq!(view["run"]["coordination_mode"], "per_task");
    assert_eq!(view["run"]["coordinator_epoch"], "1");
    assert_eq!(view["run"]["original_owner_status"], "not_bound");
    assert_eq!(view["run"]["execution_authority"], false);
    let receipt = read(
        &s,
        json!({"operation":"local_intent","group_id":"group","intent_id":"start"}),
    );
    assert_eq!(receipt["local_intent"]["status"], "committed");
    assert_eq!(receipt["local_intent"]["receipt"]["revision"], "2");
}
fn owner(f: &Fixture) -> agent::owner::AgentOwner {
    use agent::owner::*;
    let p = f.0.join("agent.sqlite");
    AgentOwner::initialize(&p, "ws").unwrap();
    let o = AgentOwner::open(&p, "ws", "epoch").unwrap();
    o.configure_trusted(Settings {
        credential_generation: "synthetic".into(),
        cap_micro_cny: Revision::new(100000),
        max_calls: Revision::new(10),
        chat: true,
        search: false,
        price_revision: PRICE_REVISION.into(),
    })
    .unwrap();
    o
}
struct Proof;
impl agent::owner::HostedCostVerifier for Proof {
    fn prove(&self, _: &[u8], _: &str) -> agent::owner::Result<agent::owner::HostedCostBound> {
        agent::owner::HostedCostBound::verified(1000, 128)
    }
}
fn actual_workflow(
    f: &Fixture,
    s: &BusinessStore,
) -> (
    agent::workflow::RunLedger,
    agent::workflow::RunScope,
    String,
) {
    let mut l =
        agent::workflow::RunLedger::open(&f.0.join("workflow.sqlite"), "ws", "epoch").unwrap();
    let scope =
        agent::workflow::RunScope::current(s, "session", "conversation", Some("project")).unwrap();
    let root = l
        .execute(
            &json!({"action":"create_root","title":"Synthetic group root","task":"Offline only"})
                .to_string(),
            s,
            &scope,
        )
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();
    apply(s, &command("register", 0, registration()));
    apply(
        s,
        &command(
            "start",
            1,
            GroupOperation::Start {
                run_id: "run".into(),
                root_task_id: root.clone(),
                leader: Some("a".into()),
                max_rounds: 8,
                max_handoffs: 2,
                deadline_ms: u64::MAX,
            },
        ),
    );
    (l, scope, root)
}
#[test]
fn actual_workflow_projection_follows_child_conversation_and_preserves_unknown_cost() {
    let f = Fixture::new();
    let s = f.init();
    let (mut ledger, scope, root) = actual_workflow(&f, &s);
    let child=ledger.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic remote fixture","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
    let context = ledger.remote_context(&scope, &child).unwrap();
    assert_ne!(context["conversation_id"], "conversation");
    let o = owner(&f);
    let p = o
        .prepare_chat(
            context["conversation_id"].as_str().unwrap(),
            "Synthetic request",
            Some(&Proof),
        )
        .unwrap();
    ledger.bind_remote_plan(&scope, &child, &p).unwrap();
    let cfg = o.configuration().unwrap();
    o.confirm_trusted(&p.request_id, &cfg.id).unwrap();
    let _offline_bytes = o
        .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
        .unwrap();
    ledger
        .observe_remote(&scope, &child, &o.lookup(&p.request_id).unwrap())
        .unwrap();
    let held = o.budget().unwrap().held_micro_cny;
    let req=json!({"schema_version":1,"request":{"operation":"workflow","group_id":"group","run_id":"run"}}).to_string();
    let v = s
        .group_ui_read(
            &ui_scope(&s),
            &req,
            Some(&o),
            Some((&mut ledger, "session")),
        )
        .unwrap();
    assert_eq!(v["workflow"]["source"], "actual_run_ledger_snapshot");
    assert_eq!(v["workflow"]["lifetime_child_count"], 1);
    assert_eq!(v["workflow"]["active_child_count"], 1);
    assert_eq!(
        v["workflow"]["children"][0]["original"]["status"],
        "unknown"
    );
    assert!(v["workflow"]["children"][0]["original"]["actual_micro_cny"].is_null());
    assert_eq!(
        v["workflow"]["children"][0]["original"]["original_request_id"],
        p.request_id
    );
    assert_eq!(v["workflow"]["host_dispatch_permission"], false);
    assert_eq!(o.budget().unwrap().held_micro_cny, held);
    assert_eq!(o.budget().unwrap().used_calls.value(), 1);
}
#[test]
fn actual_workflow_rows_remain_complete_when_display_events_are_truncated() {
    let f = Fixture::new();
    let s = f.init();
    let (mut ledger, scope, root) = actual_workflow(&f, &s);
    for _ in 0..7 {
        let child=ledger.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic local read","executor":"local_read","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
        ledger
            .execute(
                &json!({"action":"execute_local","run_id":child}).to_string(),
                &s,
                &scope,
            )
            .unwrap();
    }
    let child=ledger.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic unknown fixture","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
    let o = owner(&f);
    let context = ledger.remote_context(&scope, &child).unwrap();
    let p = o
        .prepare_chat(
            context["conversation_id"].as_str().unwrap(),
            "Synthetic fixture",
            Some(&Proof),
        )
        .unwrap();
    ledger.bind_remote_plan(&scope, &child, &p).unwrap();
    let cfg = o.configuration().unwrap();
    o.confirm_trusted(&p.request_id, &cfg.id).unwrap();
    let _offline = o
        .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
        .unwrap();
    ledger
        .observe_remote(&scope, &child, &o.lookup(&p.request_id).unwrap())
        .unwrap();
    for _ in 0..150 {
        ledger
            .execute(
                &json!({"action":"cancel","run_id":root}).to_string(),
                &s,
                &scope,
            )
            .unwrap();
    }
    let req=json!({"schema_version":1,"request":{"operation":"workflow","group_id":"group","run_id":"run"}}).to_string();
    let v = s
        .group_ui_read(&ui_scope(&s), &req, None, Some((&mut ledger, "session")))
        .unwrap();
    assert_eq!(v["workflow"]["children"].as_array().unwrap().len(), 8);
    assert_eq!(v["workflow"]["lifetime_child_count"], 8);
    assert_eq!(v["workflow"]["complete_lifetime_children"], true);
    assert_eq!(v["workflow"]["display_event_count"], 256);
    assert_eq!(v["workflow"]["events_are_display_only"], true);
}
#[test]
fn workflow_owner_absence_and_missing_real_root_do_not_fabricate_ready_state() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let req=json!({"schema_version":1,"request":{"operation":"workflow","group_id":"group","run_id":"run"}}).to_string();
    let v = s.group_ui_read(&ui_scope(&s), &req, None, None).unwrap();
    assert_eq!(v["workflow"]["availability"], "not_bound");
    assert_eq!(v["workflow"]["complete_lifetime_children"], false);
    let mut ledger =
        agent::workflow::RunLedger::open(&f.0.join("workflow.sqlite"), "ws", "epoch").unwrap();
    assert!(s
        .group_ui_read(&ui_scope(&s), &req, None, Some((&mut ledger, "session")))
        .is_err());
}
#[test]
fn stale_native_ui_scope_cannot_read_after_owner_epoch_rotation() {
    let f = Fixture::new();
    let s = f.init();
    let scope = ui_scope(&s);
    drop(s);
    let s = BusinessStore::open_existing(&f.path(), "ws", "new-epoch").unwrap();
    assert!(s
        .group_ui_read(
            &scope,
            &json!({"schema_version":1,"request":{"operation":"catalog"}}).to_string(),
            None,
            None
        )
        .is_err());
}
#[test]
fn configuration_preparation_validates_mode_member_scope_without_issuing_grants() {
    let f = Fixture::new();
    let s = f.init();
    let raw=json!({"schema_version":1,"change":{"operation":"register","intent_id":"bad-ui","group_id":"group","expected_revision":"0","mode":"fixed","fixed_leader":"missing","members":{"a":{"scopes":["project"],"permissions":["read"]}}}}).to_string();
    let auth = AuthorityBinding {
        grant_id: "ui-no-grant".into(),
        generation: Revision::new(1),
        owner_epoch: "epoch".into(),
    };
    assert!(s
        .group_ui_prepare_configuration(&ui_scope(&s), &raw, auth, Some("conversation"))
        .is_err());
    assert!(s
        .database()
        .query(
            "SELECT * FROM business_grants WHERE grant_id='ui-no-grant'",
            &[]
        )
        .unwrap()
        .is_empty());
}
#[test]
fn run_view_shows_deadline_without_turning_a_local_proposal_into_a_completion() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    let mut run = s.group_run(&scope, "run").unwrap();
    run.deadline_ms = 1;
    s.database()
        .exec(
            "UPDATE group_runtime_runs SET record=? WHERE run_id='run'",
            &[&serde_json::to_string(&run).unwrap()],
        )
        .unwrap();
    let v = read(
        &s,
        json!({"operation":"run","group_id":"group","run_id":"run"}),
    );
    assert_eq!(v["run"]["deadline_reached"], true);
    assert_eq!(v["run"]["stopped"], false);
    assert_eq!(v["run"]["execution_authority"], false);
}
#[test]
fn configure_tail_expiry_rolls_back_defaults_and_legacy_capture() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let rows = s
        .database()
        .query(
            "SELECT record FROM group_runtime_runs WHERE run_id='run'",
            &[],
        )
        .unwrap();
    let mut old: serde_json::Value = serde_json::from_str(rows[0][0].as_ref().unwrap()).unwrap();
    old.as_object_mut().unwrap().remove("coordination_mode");
    s.database()
        .exec(
            "UPDATE group_runtime_runs SET record=? WHERE run_id='run'",
            &[&old.to_string()],
        )
        .unwrap();
    let c = command("configure-expired", 2, config("host_only"));
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.database().exec("CREATE TRIGGER expire_config AFTER UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='configure-expired' AND NEW.status='committed' BEGIN UPDATE business_grants SET expires_at_ms='0' WHERE grant_id='grant-configure-expired'; END",&[]).unwrap();
    assert_ne!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::Committed
    );
    assert_eq!(
        s.database()
            .query(
                "SELECT record FROM group_runtime_runs WHERE run_id='run'",
                &[]
            )
            .unwrap()[0][0]
            .as_deref(),
        Some(old.to_string().as_str())
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(s.group_registration(&scope).unwrap().mode, "per_task");
}

#[test]
fn local_configuration_remains_readable_when_real_owner_has_no_configuration() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let path = f.0.join("unconfigured-owner.sqlite");
    agent::owner::AgentOwner::initialize(&path, "ws").unwrap();
    let o = agent::owner::AgentOwner::open(&path, "ws", "epoch").unwrap();
    let v=s.group_ui_read(&ui_scope(&s),&json!({"schema_version":1,"request":{"operation":"run","group_id":"group","run_id":"run"}}).to_string(),Some(&o),None).unwrap();
    assert_eq!(v["run"]["owner_budget_status"], "unavailable");
    assert!(v["run"]["owner_budget"].is_null());
    assert_eq!(v["run"]["coordinator_id"], "a");
}
#[test]
fn configuration_preparation_does_not_turn_coordinator_into_manager() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let scope = GroupUiScope::current(&s, "project", "a").unwrap();
    let raw=json!({"schema_version":1,"change":{"operation":"configure","intent_id":"member-config","group_id":"group","expected_revision":"2","mode":"host_only","members":{"a":{"scopes":["project"],"permissions":["read"]}}}}).to_string();
    let c = s
        .group_ui_prepare_configuration(
            &scope,
            &raw,
            AuthorityBinding {
                grant_id: "member-grant".into(),
                generation: Revision::new(1),
                owner_epoch: "epoch".into(),
            },
            None,
        )
        .unwrap();
    assert!(s.issue_group_local_grant_trusted(&c).is_err());
}

#[test]
fn regression_existing_run_keeps_removed_members_and_handoff_mode() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let cap = Capabilities {
        scopes: BTreeSet::from(["project".into()]),
        permissions: BTreeSet::from(["read".into()]),
    };
    assert_eq!(
        apply(
            &s,
            &command(
                "defaults",
                2,
                GroupOperation::Configure {
                    mode: "fixed".into(),
                    fixed_leader: Some("c".into()),
                    members: BTreeMap::from([("c".into(), cap)])
                }
            )
        )
        .status,
        LocalStatus::Committed
    );
    let o = owner(&f);
    let hand = mutation(
        "handoff-after-configure",
        3,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    s.issue_group_local_grant_trusted(&hand).unwrap();
    assert_eq!(
        s.execute_group_local(&hand, Some(&o)).unwrap().status,
        LocalStatus::Committed
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    let old = s.group_run(&scope, "run").unwrap();
    assert_eq!(old.leader.as_deref(), Some("b"));
    assert!(!old.members.contains_key("c"));
    assert_eq!(
        apply(
            &s,
            &command(
                "new-run",
                4,
                GroupOperation::Start {
                    run_id: "run-new".into(),
                    root_task_id: "root-new".into(),
                    leader: None,
                    max_rounds: 8,
                    max_handoffs: 2,
                    deadline_ms: u64::MAX
                }
            )
        )
        .status,
        LocalStatus::Committed
    );
    let new = s.group_run(&scope, "run-new").unwrap();
    assert_eq!(new.leader.as_deref(), Some("c"));
    assert_eq!(new.coordination_mode.as_deref(), Some("fixed"));
}
#[test]
fn regression_tool_pending_cost_projection() {
    let f = Fixture::new();
    let s = f.init();
    let (mut ledger, scope, root) = actual_workflow(&f, &s);
    let child=ledger.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
    let context = ledger.remote_context(&scope, &child).unwrap();
    let o = owner(&f);
    let p = o
        .prepare_chat(
            context["conversation_id"].as_str().unwrap(),
            "Synthetic",
            Some(&Proof),
        )
        .unwrap();
    ledger.bind_remote_plan(&scope, &child, &p).unwrap();
    let cfg = o.configuration().unwrap();
    o.confirm_trusted(&p.request_id, &cfg.id).unwrap();
    let _bytes = o
        .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
        .unwrap();
    let body = json!({"id":"synthetic","model":agent::owner::MODEL,"choices":[{"index":0,"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_a","type":"function","function":{"name":"product_supplier_list","arguments":"{\"limit\":5,\"offset\":0}"}}]}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}});
    let observed = o.settle_response(&p.request_id, &body.to_string()).unwrap();
    assert_eq!(observed.status, "tool_pending");
    assert!(observed.charged_micro_cny.value() > 0);
    ledger.observe_remote(&scope, &child, &observed).unwrap();
    let req=json!({"schema_version":1,"request":{"operation":"workflow","group_id":"group","run_id":"run"}}).to_string();
    let v = s
        .group_ui_read(
            &ui_scope(&s),
            &req,
            Some(&o),
            Some((&mut ledger, "session")),
        )
        .unwrap();
    println!(
        "OWNER_SETTLED_COST={} UI_ORIGINAL={}",
        observed.charged_micro_cny.as_str(),
        v["workflow"]["children"][0]["original"]
    );
    assert_eq!(
        v["workflow"]["children"][0]["original"]["actual_micro_cny"],
        json!(observed.charged_micro_cny)
    );
    assert_eq!(
        v["workflow"]["children"][0]["original"]["original_chain_resolved"],
        false
    );
    assert_eq!(
        v["workflow"]["children"][0]["original"]["chain"][0]["actual_micro_cny"],
        json!(observed.charged_micro_cny)
    );
}

#[test]
fn regression_legacy_capture_survives_configuration_tail() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let rows = s
        .database()
        .query(
            "SELECT record FROM group_runtime_runs WHERE run_id='run'",
            &[],
        )
        .unwrap();
    let mut legacy: serde_json::Value = serde_json::from_str(rows[0][0].as_ref().unwrap()).unwrap();
    legacy.as_object_mut().unwrap().remove("coordination_mode");
    s.database()
        .exec(
            "UPDATE group_runtime_runs SET record=? WHERE run_id='run'",
            &[&legacy.to_string()],
        )
        .unwrap();
    s.database().exec("CREATE TRIGGER undo_freeze AFTER UPDATE ON group_runtime_runs BEGIN UPDATE group_runtime_runs SET record=OLD.record WHERE run_id=NEW.run_id; END",&[]).unwrap();
    let receipt = apply(
        &s,
        &command("configure-tail-capture", 2, config("host_only")),
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    let run = s.group_run(&scope, "run").unwrap();
    println!(
        "CONFIGURE_RECEIPT={:?} EXISTING_RUN_MODE={:?}",
        receipt.status, run.coordination_mode
    );
    assert!(
        receipt.status != LocalStatus::Committed
            || run.coordination_mode.as_deref() == Some("per_task")
    );
}

#[test]
fn configuration_run_witness_checks_receipt_and_consumption_tail_mutations() {
    for (name, trigger) in [
        ("receipt", "AFTER UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='tail-config' AND NEW.status='committed'"),
        ("consume", "AFTER UPDATE ON business_grants WHEN NEW.grant_id='grant-tail-config' AND NEW.active=0"),
    ] {
        let f=Fixture::new(); let s=f.init(); start(&s);
        let before=s.database().query("SELECT run_id,group_id,record FROM group_runtime_runs ORDER BY run_id",&[]).unwrap();
        let c=command("tail-config",2,config("host_only"));
        s.issue_group_local_grant_trusted(&c).unwrap();
        s.database().exec(&format!("CREATE TRIGGER damage_run {trigger} BEGIN UPDATE group_runtime_runs SET record='{{}}' WHERE run_id='run'; END"),&[]).unwrap();
        let receipt=s.execute_group_local(&c,None).unwrap();
        assert_eq!(receipt.status,LocalStatus::PendingOriginal,"{name}");
        assert_eq!(s.database().query("SELECT run_id,group_id,record FROM group_runtime_runs ORDER BY run_id",&[]).unwrap(),before,"{name}");
        let scope=GroupScope::current(&s,"project","group").unwrap();
        assert_eq!(s.group_registration(&scope).unwrap().mode,"per_task","{name}");
        assert!(s.database().query("SELECT intent_id FROM group_runtime_events WHERE intent_id='tail-config'",&[]).unwrap().is_empty());
        assert_eq!(s.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='tail-config'",&[]).unwrap(),vec![vec![Some("pending".into()),None]]);
        assert_eq!(s.database().query("SELECT active FROM business_grants WHERE grant_id='grant-tail-config'",&[]).unwrap()[0][0].as_deref(),Some("1"));
    }
}

#[test]
fn parent_configure_group_trigger_cannot_replace_intended_mode_and_leader() {
    for target in ["host_only", "fixed"] {
        let f = Fixture::new();
        let s = f.init();
        start(&s);
        let before=s.database().query("SELECT workspace,project_id,revision,record FROM group_runtime_groups WHERE group_id='group'",&[]).unwrap();
        let runs = s
            .database()
            .query("SELECT run_id,group_id,record FROM group_runtime_runs", &[])
            .unwrap();
        s.database().exec("CREATE TRIGGER restore_old_defaults AFTER UPDATE OF record ON group_runtime_groups BEGIN UPDATE group_runtime_groups SET record=json_set(NEW.record,'$.mode',json_extract(OLD.record,'$.mode'),'$.fixed_leader',json_extract(OLD.record,'$.fixed_leader')) WHERE group_id=NEW.group_id; END",&[]).unwrap();
        let c = command("parent-mode", 2, config(target));
        let receipt = apply(&s, &c);
        let after=s.database().query("SELECT workspace,project_id,revision,record FROM group_runtime_groups WHERE group_id='group'",&[]).unwrap();
        println!(
            "TARGET={target} RECEIPT={:?} GROUP={after:?}",
            receipt.status
        );
        assert_eq!(receipt.status, LocalStatus::PendingOriginal);
        assert_eq!(after, before);
        assert_eq!(
            s.database()
                .query("SELECT run_id,group_id,record FROM group_runtime_runs", &[])
                .unwrap(),
            runs
        );
        assert!(s
            .database()
            .query(
                "SELECT * FROM group_runtime_events WHERE intent_id='parent-mode'",
                &[]
            )
            .unwrap()
            .is_empty());
        assert_eq!(s.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='parent-mode'",&[]).unwrap(),vec![vec![Some("pending".into()),None]]);
        assert_eq!(
            s.database()
                .query(
                    "SELECT active FROM business_grants WHERE grant_id='grant-parent-mode'",
                    &[]
                )
                .unwrap()[0][0]
                .as_deref(),
            Some("1")
        );
    }
}

#[test]
fn parent_exact_revision_trigger_preserves_new_revision_but_undoes_configuration() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let before=s.database().query("SELECT workspace,project_id,revision,record FROM group_runtime_groups WHERE group_id='group'",&[]).unwrap();
    s.database().exec(r#"CREATE TRIGGER undo_group_config AFTER UPDATE OF revision ON group_runtime_groups WHEN OLD.group_id='group' AND OLD.revision='2' AND NEW.revision='3' BEGIN UPDATE group_runtime_groups SET record=replace(OLD.record,'"revision":"2"','"revision":"3"') WHERE group_id=NEW.group_id; END"#,&[]).unwrap();
    let receipt = apply(&s, &command("parent-exact", 2, config("fixed")));
    let after=s.database().query("SELECT workspace,project_id,revision,record FROM group_runtime_groups WHERE group_id='group'",&[]).unwrap();
    println!(
        "EXACT_PARENT_TRIGGER RECEIPT={:?} GROUP={after:?}",
        receipt.status
    );
    assert_eq!(receipt.status, LocalStatus::PendingOriginal);
    assert_eq!(after, before);
}

#[test]
fn parent_pending_register_recovery_reads_original_after_failure_and_restart_without_group() {
    let f = Fixture::new();
    {
        let s = f.init();
        s.database().exec("CREATE TRIGGER fail_register BEFORE INSERT ON group_runtime_groups BEGIN SELECT RAISE(ABORT,'synthetic register effect failure'); END",&[]).unwrap();
        let receipt = apply(&s, &command("pending-registration", 0, registration()));
        assert_eq!(receipt.status, LocalStatus::PendingOriginal);
        assert!(s
            .database()
            .query("SELECT * FROM group_runtime_groups", &[])
            .unwrap()
            .is_empty());
        let query=json!({"schema_version":1,"request":{"operation":"local_intent","group_id":"group","intent_id":"pending-registration"}}).to_string();
        let result = s.group_ui_read(&ui_scope(&s), &query, None, None);
        println!("BEFORE_RESTART_ORIGINAL_LOOKUP={result:?}");
        assert!(
            result.is_ok(),
            "pending Register must be queryable without a group"
        );
    }
    let s = BusinessStore::open_existing(&f.path(), "ws", "restart-epoch").unwrap();
    let scope = GroupUiScope::current(&s, "project", "owner").unwrap();
    let raw=json!({"schema_version":1,"request":{"operation":"local_intent","group_id":"group","intent_id":"pending-registration"}}).to_string();
    let journal = s
        .database()
        .query("SELECT * FROM group_runtime_local_intents", &[])
        .unwrap();
    let grants = s
        .database()
        .query("SELECT * FROM business_grants ORDER BY grant_id", &[])
        .unwrap();
    for _ in 0..2 {
        let value = s.group_ui_read(&scope, &raw, None, None).unwrap();
        assert_eq!(value["local_intent"]["status"], "pending_original");
        assert!(value["local_intent"]["receipt"].is_null());
        assert_eq!(
            value["local_intent"]["recovery_action"],
            "query_original_local_intent"
        );
    }
    assert_eq!(
        s.database()
            .query("SELECT * FROM group_runtime_local_intents", &[])
            .unwrap(),
        journal
    );
    assert_eq!(
        s.database()
            .query("SELECT * FROM business_grants ORDER BY grant_id", &[])
            .unwrap(),
        grants
    );
    assert!(s
        .database()
        .query("SELECT * FROM group_runtime_groups", &[])
        .unwrap()
        .is_empty());
    assert!(s
        .database()
        .query("SELECT * FROM group_runtime_events", &[])
        .unwrap()
        .is_empty());
    let unauthorized = GroupUiScope::current(&s, "project", "different-human").unwrap();
    assert_eq!(
        s.group_ui_read(&unauthorized, &raw, None, None)
            .unwrap_err(),
        ContractError::InvalidAuthority
    );
    let wrong_group = raw.replace("\"group\"", "\"other-group\"");
    assert!(s.group_ui_read(&scope, &wrong_group, None, None).is_err());
}

#[test]
fn parent_v1_migration_preserves_journal_without_fabricating_missing_original_identity() {
    let f = Fixture::new();
    let s = f.init();
    s.database().exec("CREATE TRIGGER fail_old_registration BEFORE INSERT ON group_runtime_groups BEGIN SELECT RAISE(ABORT,'synthetic old failure'); END",&[]).unwrap();
    assert_eq!(
        apply(&s, &command("legacy-pending", 0, registration())).status,
        LocalStatus::PendingOriginal
    );
    let rows = s
        .database()
        .query("SELECT * FROM group_runtime_local_intents", &[])
        .unwrap();
    s.database()
        .exec("DROP TABLE IF EXISTS group_runtime_intent_bindings", &[])
        .unwrap();
    s.database()
        .exec("UPDATE group_runtime_schema SET version='1'", &[])
        .unwrap();
    s.initialize_group_runtime().unwrap();
    assert_eq!(
        s.database()
            .query("SELECT version FROM group_runtime_schema", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("2")
    );
    assert_eq!(
        s.database()
            .query("SELECT * FROM group_runtime_local_intents", &[])
            .unwrap(),
        rows
    );
    assert!(s
        .database()
        .query("SELECT * FROM group_runtime_intent_bindings", &[])
        .unwrap()
        .is_empty());
    let raw=json!({"schema_version":1,"request":{"operation":"local_intent","group_id":"group","intent_id":"legacy-pending"}}).to_string();
    assert_eq!(
        s.group_ui_read(&ui_scope(&s), &raw, None, None)
            .unwrap_err(),
        ContractError::Unknown
    );
}

#[test]
fn parent_normal_explicit_modes_and_fixed_leader_persist_and_start_real_local_runs() {
    for mode in ["host_only", "fixed", "per_task"] {
        let f = Fixture::new();
        {
            let s = f.init();
            start(&s);
            assert_eq!(
                apply(&s, &command("normal-config", 2, config(mode))).status,
                LocalStatus::Committed
            );
            let scope = GroupScope::current(&s, "project", "group").unwrap();
            let group = s.group_registration(&scope).unwrap();
            assert_eq!(group.mode, mode);
            assert_eq!(group.owner, "owner");
            assert!(group.admins.contains("admin"));
            assert_eq!(
                group.fixed_leader.as_deref(),
                if mode == "fixed" { Some("b") } else { None }
            );
            let c = command(
                "new-mode-run",
                3,
                GroupOperation::Start {
                    run_id: "new-mode-run".into(),
                    root_task_id: "new-root".into(),
                    leader: if mode == "per_task" {
                        Some("a".into())
                    } else {
                        None
                    },
                    max_rounds: 3,
                    max_handoffs: 2,
                    deadline_ms: u64::MAX,
                },
            );
            assert_eq!(apply(&s, &c).status, LocalStatus::Committed);
        }
        let s = f.store();
        let scope = GroupScope::current(&s, "project", "group").unwrap();
        assert_eq!(s.group_registration(&scope).unwrap().mode, mode);
        let run = s.group_run(&scope, "new-mode-run").unwrap();
        assert_eq!(run.coordination_mode.as_deref(), Some(mode));
        assert_eq!(
            run.leader.as_deref(),
            match mode {
                "fixed" => Some("b"),
                "per_task" => Some("a"),
                _ => None,
            }
        );
        assert_eq!(
            s.group_run(&scope, "run")
                .unwrap()
                .coordination_mode
                .as_deref(),
            Some("per_task")
        );
    }
}

#[test]
fn parent_pending_register_binding_tamper_and_missing_metadata_do_not_claim_identity() {
    let f = Fixture::new();
    let s = f.init();
    s.database().exec("CREATE TRIGGER fail_registration BEFORE INSERT ON group_runtime_groups BEGIN SELECT RAISE(ABORT,'synthetic'); END",&[]).unwrap();
    let c = command("pending-identity", 0, registration());
    assert_eq!(apply(&s, &c).status, LocalStatus::PendingOriginal);
    let raw=json!({"schema_version":1,"request":{"operation":"local_intent","group_id":"group","intent_id":"pending-identity"}}).to_string();
    let mut forged = serde_json::to_value(&c).unwrap();
    forged["actor"] = json!({"Human":"different-human"});
    forged["operation"]["Register"]["owner"] = json!("different-human");
    s.database()
        .exec(
            "UPDATE group_runtime_intent_bindings SET command=? WHERE intent_id='pending-identity'",
            &[&forged.to_string()],
        )
        .unwrap();
    assert_eq!(
        s.group_ui_read(&ui_scope(&s), &raw, None, None)
            .unwrap_err(),
        ContractError::BindingMismatch
    );
    let different = GroupUiScope::current(&s, "project", "different-human").unwrap();
    assert_eq!(
        s.group_ui_read(&different, &raw, None, None).unwrap_err(),
        ContractError::BindingMismatch
    );
    s.database()
        .exec(
            "DELETE FROM group_runtime_intent_bindings WHERE intent_id='pending-identity'",
            &[],
        )
        .unwrap();
    assert_eq!(
        s.group_ui_read(&ui_scope(&s), &raw, None, None)
            .unwrap_err(),
        ContractError::Unknown
    );
    assert!(s
        .database()
        .query("SELECT * FROM group_runtime_groups", &[])
        .unwrap()
        .is_empty());
    assert!(s
        .database()
        .query("SELECT * FROM group_runtime_events", &[])
        .unwrap()
        .is_empty());
}

#[test]
fn parent_original_binding_suppression_and_tampering_roll_back_pending_transaction() {
    for action in ["BEFORE INSERT ON group_runtime_intent_bindings BEGIN SELECT RAISE(IGNORE); END","AFTER INSERT ON group_runtime_intent_bindings BEGIN UPDATE group_runtime_intent_bindings SET command='{}' WHERE intent_id=NEW.intent_id; END"] {
        let f=Fixture::new();let s=f.init();
        let c=command("pending-atomic",0,registration());s.issue_group_local_grant_trusted(&c).unwrap();
        s.database().exec(&format!("CREATE TRIGGER damage_original {action}"),&[]).unwrap();
        assert_eq!(s.execute_group_local(&c,None).unwrap_err(),ContractError::Storage);
        assert!(s.database().query("SELECT * FROM group_runtime_local_intents",&[]).unwrap().is_empty());
        assert!(s.database().query("SELECT * FROM group_runtime_intent_bindings",&[]).unwrap().is_empty());
        assert!(s.database().query("SELECT * FROM group_runtime_groups",&[]).unwrap().is_empty());
    }
}

#[test]
fn parent_original_binding_receipt_and_consume_tail_damage_returns_pending_and_rolls_back() {
    for trigger in ["AFTER UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='binding-tail' AND NEW.status='committed'","AFTER UPDATE ON business_grants WHEN NEW.grant_id='grant-binding-tail' AND NEW.active=0"] {
        let f=Fixture::new();let s=f.init();start(&s);
        let before=s.database().query("SELECT * FROM group_runtime_groups",&[]).unwrap();
        let c=command("binding-tail",2,config("fixed"));s.issue_group_local_grant_trusted(&c).unwrap();
        s.database().exec(&format!("CREATE TRIGGER damage_binding {trigger} BEGIN DELETE FROM group_runtime_intent_bindings WHERE intent_id='binding-tail'; END"),&[]).unwrap();
        assert_eq!(s.execute_group_local(&c,None).unwrap().status,LocalStatus::PendingOriginal);
        assert_eq!(s.database().query("SELECT * FROM group_runtime_groups",&[]).unwrap(),before);
        assert_eq!(s.database().query("SELECT command FROM group_runtime_intent_bindings WHERE intent_id='binding-tail'",&[]).unwrap(),vec![vec![Some(serde_json::to_string(&c).unwrap())]]);
        assert_eq!(s.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='binding-tail'",&[]).unwrap(),vec![vec![Some("pending".into()),None]]);
        assert!(s.database().query("SELECT * FROM group_runtime_events WHERE intent_id='binding-tail'",&[]).unwrap().is_empty());
    }
}

#[test]
fn parent_v1_identity_migration_storage_failure_rolls_back_schema_without_identity_backfill() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let journal = s
        .database()
        .query(
            "SELECT * FROM group_runtime_local_intents ORDER BY intent_id",
            &[],
        )
        .unwrap();
    s.database()
        .exec("DROP TABLE group_runtime_intent_bindings", &[])
        .unwrap();
    s.database()
        .exec("UPDATE group_runtime_schema SET version='1'", &[])
        .unwrap();
    s.database().exec("CREATE TRIGGER fail_identity_migration BEFORE UPDATE ON group_runtime_schema BEGIN SELECT RAISE(ABORT,'synthetic migration failure'); END",&[]).unwrap();
    assert_eq!(
        s.initialize_group_runtime().unwrap_err(),
        ContractError::Storage
    );
    assert!(s.database().query("SELECT name FROM sqlite_master WHERE type='table' AND name='group_runtime_intent_bindings'",&[]).unwrap().is_empty());
    assert_eq!(
        s.database()
            .query("SELECT version FROM group_runtime_schema", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
    assert_eq!(
        s.database()
            .query(
                "SELECT * FROM group_runtime_local_intents ORDER BY intent_id",
                &[]
            )
            .unwrap(),
        journal
    );
    s.database()
        .exec("DROP TRIGGER fail_identity_migration", &[])
        .unwrap();
    s.initialize_group_runtime().unwrap();
    assert!(s
        .database()
        .query("SELECT * FROM group_runtime_intent_bindings", &[])
        .unwrap()
        .is_empty());
    let raw=json!({"schema_version":1,"request":{"operation":"local_intent","group_id":"group","intent_id":"start"}}).to_string();
    assert_eq!(
        s.group_ui_read(&ui_scope(&s), &raw, None, None).unwrap()["local_intent"]
            ["identity_source"],
        "current_group_management"
    );
    let member = GroupUiScope::current(&s, "project", "a").unwrap();
    assert_eq!(
        s.group_ui_read(&member, &raw, None, None).unwrap_err(),
        ContractError::InvalidAuthority
    );
}

#[test]
fn parent_original_binding_insert_cannot_commit_a_corrupted_pending_journal() {
    let f = Fixture::new();
    let s = f.init();
    let c = command("corrupt-pending", 0, registration());
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.database().exec("CREATE TRIGGER damage_pending AFTER INSERT ON group_runtime_intent_bindings BEGIN UPDATE group_runtime_local_intents SET binding_digest='wrong' WHERE intent_id=NEW.intent_id; END",&[]).unwrap();
    s.database().exec("CREATE TRIGGER fail_new_group BEFORE INSERT ON group_runtime_groups BEGIN SELECT RAISE(ABORT,'synthetic effect failure'); END",&[]).unwrap();
    let outcome = s.execute_group_local(&c, None);
    println!("PENDING_INSERT_TAIL_OUTCOME={outcome:?}");
    assert_eq!(outcome.unwrap_err(), ContractError::Storage);
    assert!(s
        .database()
        .query("SELECT * FROM group_runtime_local_intents", &[])
        .unwrap()
        .is_empty());
    assert!(s
        .database()
        .query("SELECT * FROM group_runtime_intent_bindings", &[])
        .unwrap()
        .is_empty());
    assert!(s
        .database()
        .query("SELECT * FROM group_runtime_groups", &[])
        .unwrap()
        .is_empty());
}

fn legacy_migration_fixture() -> (Fixture, BusinessStore) {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    assert_eq!(
        apply(&s, &command("legacy-rejected", 99, config("fixed"))).status,
        LocalStatus::Rejected
    );
    s.database().exec("CREATE TRIGGER fail_legacy_group BEFORE INSERT ON group_runtime_groups WHEN NEW.group_id='legacy-group' BEGIN SELECT RAISE(ABORT,'synthetic legacy registration failure'); END",&[]).unwrap();
    let mut c = command("legacy-pending", 0, registration());
    c.group_id = "legacy-group".into();
    assert_eq!(apply(&s, &c).status, LocalStatus::PendingOriginal);
    s.database()
        .exec("DROP TABLE group_runtime_intent_bindings", &[])
        .unwrap();
    s.database()
        .exec("UPDATE group_runtime_schema SET version='1'", &[])
        .unwrap();
    (f, s)
}
fn check_legacy_migration_fault(sql: &str) {
    let (_f, s) = legacy_migration_fixture();
    let before = s
        .database()
        .query(
            "SELECT * FROM group_runtime_local_intents ORDER BY intent_id",
            &[],
        )
        .unwrap();
    assert_eq!(before.len(), 4);
    s.database().exec(&format!("CREATE TRIGGER damage_migration AFTER UPDATE ON group_runtime_schema WHEN OLD.version='1' AND NEW.version='2' BEGIN {sql}; END"),&[]).unwrap();
    let result = s.initialize_group_runtime();
    let after = s
        .database()
        .query(
            "SELECT * FROM group_runtime_local_intents ORDER BY intent_id",
            &[],
        )
        .unwrap();
    println!("MIGRATION_FAULT={sql}\nRESULT={result:?}\nBEFORE={before:?}\nAFTER={after:?}");
    assert_eq!(result, Err(ContractError::Storage));
    assert_eq!(after, before);
    assert_eq!(
        s.database()
            .query("SELECT version FROM group_runtime_schema", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
    assert!(s.database().query("SELECT name FROM sqlite_master WHERE type='table' AND name='group_runtime_intent_bindings'",&[]).unwrap().is_empty());
}
#[test]
fn migration_preservation_rejects_legacy_pending_deletion() {
    check_legacy_migration_fault(
        "DELETE FROM group_runtime_local_intents WHERE intent_id='legacy-pending'",
    );
}
#[test]
fn migration_preservation_rejects_legacy_receipt_rewrite() {
    check_legacy_migration_fault("UPDATE group_runtime_local_intents SET receipt='{\"synthetic\":\"changed\"}' WHERE intent_id='register'");
}
#[test]
fn migration_preservation_rejects_journal_row_injection() {
    check_legacy_migration_fault("INSERT INTO group_runtime_local_intents SELECT 'injected-intent',workspace,project_id,group_id,binding_digest,'pending',NULL FROM group_runtime_local_intents WHERE intent_id='legacy-pending'");
}
#[test]
fn migration_preservation_rejects_original_binding_injection() {
    check_legacy_migration_fault("INSERT INTO group_runtime_intent_bindings SELECT intent_id,'{}' FROM group_runtime_local_intents WHERE intent_id='legacy-pending'");
}
#[test]
fn migration_preservation_normal_reads_and_later_v2_bindings_remain_usable_without_replay() {
    let (_f, s) = legacy_migration_fixture();
    let before = s
        .database()
        .query(
            "SELECT * FROM group_runtime_local_intents ORDER BY intent_id",
            &[],
        )
        .unwrap();
    s.initialize_group_runtime().unwrap();
    assert_eq!(
        s.database()
            .query(
                "SELECT * FROM group_runtime_local_intents ORDER BY intent_id",
                &[]
            )
            .unwrap(),
        before
    );
    assert!(s
        .database()
        .query("SELECT * FROM group_runtime_intent_bindings", &[])
        .unwrap()
        .is_empty());
    for (intent, status) in [("register", "committed"), ("legacy-rejected", "rejected")] {
        let raw=json!({"schema_version":1,"request":{"operation":"local_intent","group_id":"group","intent_id":intent}}).to_string();
        let value = s.group_ui_read(&ui_scope(&s), &raw, None, None).unwrap();
        assert_eq!(value["local_intent"]["status"], status);
        assert_eq!(
            value["local_intent"]["identity_source"],
            "current_group_management"
        );
    }
    let raw=json!({"schema_version":1,"request":{"operation":"local_intent","group_id":"legacy-group","intent_id":"legacy-pending"}}).to_string();
    assert_eq!(
        s.group_ui_read(&ui_scope(&s), &raw, None, None)
            .unwrap_err(),
        ContractError::Unknown
    );
    assert_eq!(
        s.database()
            .query(
                "SELECT * FROM group_runtime_local_intents ORDER BY intent_id",
                &[]
            )
            .unwrap(),
        before
    );
    assert!(s
        .database()
        .query(
            "SELECT * FROM group_runtime_groups WHERE group_id='legacy-group'",
            &[]
        )
        .unwrap()
        .is_empty());
    assert_eq!(
        apply(&s, &command("post-migration-config", 2, config("fixed"))).status,
        LocalStatus::Committed
    );
    let bindings = s
        .database()
        .query(
            "SELECT * FROM group_runtime_intent_bindings ORDER BY intent_id",
            &[],
        )
        .unwrap();
    assert_eq!(bindings.len(), 1);
    s.initialize_group_runtime().unwrap();
    assert_eq!(
        s.database()
            .query(
                "SELECT * FROM group_runtime_intent_bindings ORDER BY intent_id",
                &[]
            )
            .unwrap(),
        bindings
    );
}

#[test]
fn independent_migration_preserves_null_distinction() {
 check_legacy_migration_fault("UPDATE group_runtime_local_intents SET receipt='null' WHERE intent_id='legacy-pending'");
}
#[test]
fn independent_migration_preserves_receipt_raw_bytes() {
 check_legacy_migration_fault("UPDATE group_runtime_local_intents SET receipt=receipt || ' ' WHERE intent_id='register'");
}
#[test]
fn independent_migration_preserves_identity_with_unchanged_row_count() {
 check_legacy_migration_fault("UPDATE group_runtime_local_intents SET intent_id='renamed-pending' WHERE intent_id='legacy-pending'");
}

#[test]
fn independent_migration_legacy_pending_existing_group_is_read_only() {
 let f=Fixture::new();let s=f.init();start(&s);
 s.database().exec("CREATE TRIGGER fail_historical_config BEFORE UPDATE ON group_runtime_groups BEGIN SELECT RAISE(ABORT,'synthetic'); END",&[]).unwrap();
 assert_eq!(apply(&s,&command("legacy-existing-pending",2,config("fixed"))).status,LocalStatus::PendingOriginal);
 s.database().exec("DROP TRIGGER fail_historical_config",&[]).unwrap();
 s.database().exec("DROP TABLE group_runtime_intent_bindings",&[]).unwrap();s.database().exec("UPDATE group_runtime_schema SET version='1'",&[]).unwrap();
 let queries=["SELECT * FROM group_runtime_local_intents ORDER BY intent_id","SELECT * FROM business_grants ORDER BY grant_id","SELECT * FROM group_runtime_groups ORDER BY group_id","SELECT * FROM group_runtime_runs ORDER BY run_id","SELECT * FROM group_runtime_nodes ORDER BY node_id","SELECT * FROM group_runtime_events ORDER BY intent_id"];
 let before:Vec<_>=queries.iter().map(|q|s.database().query(q,&[]).unwrap()).collect();
 s.initialize_group_runtime().unwrap();
 let raw=json!({"schema_version":1,"request":{"operation":"local_intent","group_id":"group","intent_id":"legacy-existing-pending"}}).to_string();
 for actor in ["owner","admin"] {
 let scope=GroupUiScope::current(&s,"project",actor).unwrap();
 for _ in 0..2 {let v=s.group_ui_read(&scope,&raw,None,None).unwrap();assert_eq!(v["local_intent"]["status"],"pending_original");assert_eq!(v["local_intent"]["identity_source"],"current_group_management");assert!(v["local_intent"]["receipt"].is_null());}
 }
 let member=GroupUiScope::current(&s,"project","a").unwrap();assert_eq!(s.group_ui_read(&member,&raw,None,None).unwrap_err(),ContractError::InvalidAuthority);
 s.initialize_group_runtime().unwrap();
 for (q,expected) in queries.iter().zip(before) {assert_eq!(s.database().query(q,&[]).unwrap(),expected,"{q}");}
 assert!(s.database().query("SELECT * FROM group_runtime_intent_bindings",&[]).unwrap().is_empty());
}
