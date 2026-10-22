//! Same-crate source harness exercises actual pub(crate) BusinessStore seams.
#![allow(dead_code)]
#[path = "../src/agent/mod.rs"]
mod agent;
#[path = "../src/archive.rs"]
mod archive;
#[path = "../src/blobs.rs"]
mod blobs;
#[path = "../src/business.rs"]
mod business;
#[path = "../src/contract.rs"]
mod contract;
#[path = "../src/group_runtime/store.rs"]
mod group_runtime_store;
#[path = "../src/research.rs"]
mod research;
#[path = "../src/review_lifecycle.rs"]
mod review_lifecycle;
#[path = "../src/sqlite.rs"]
mod sqlite;
use business::BusinessStore;
use contract::*;
use group_runtime_store::*;
#[path = "../src/group_runtime/bridge.rs"]
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
