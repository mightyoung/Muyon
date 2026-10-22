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
fn owner_binding_reloads_actual_canonical_bytes_instead_of_caller_plan() {
    let f = Fixture::new();
    let o = owner(&f);
    let mut plan = o
        .prepare_chat("conversation", "Synthetic canonical fixture", Some(&Proof))
        .unwrap();
    let actual_digest = plan.payload_digest.clone();
    let id = plan.request_id.clone();
    plan.payload_digest = "0".repeat(64);
    let binding = o.request_binding(&id).unwrap();
    assert_eq!(binding.request_id(), id);
    assert_eq!(binding.payload_digest(), actual_digest);
    assert_eq!(binding.workspace_id(), "ws");
    assert_eq!(binding.conversation_id(), "conversation");
    assert_eq!(binding.request_epoch(), "epoch");
    assert_eq!(binding.configuration_id(), plan.configuration_id);
    assert_eq!(binding.purpose(), "chat");
    assert_ne!(binding.payload_digest(), plan.payload_digest);
}
#[test]
fn owner_binding_detects_persisted_payload_digest_mismatch() {
    let f = Fixture::new();
    let o = owner(&f);
    let p = o
        .prepare_chat("conversation", "Synthetic", Some(&Proof))
        .unwrap();
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    db.exec(
        "UPDATE requests SET payload=payload||' ' WHERE id=?",
        &[&p.request_id],
    )
    .unwrap();
    assert_eq!(
        o.request_binding(&p.request_id).unwrap_err(),
        "agent_request_binding_mismatch"
    );
}
#[test]
fn owner_binding_after_restart_preserves_original_epoch_unknown_and_hold_without_replay() {
    let f = Fixture::new();
    let id;
    {
        let o = owner(&f);
        let p = o
            .prepare_chat("conversation", "Synthetic", Some(&Proof))
            .unwrap();
        let cfg = o.configuration().unwrap();
        o.confirm_trusted(&p.request_id, &cfg.id).unwrap();
        let _unsent = o
            .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
            .unwrap();
        id = p.request_id;
    }
    let o = agent::owner::AgentOwner::open(&f.0.join("agent.sqlite"), "ws", "epoch-new").unwrap();
    let before = o.budget().unwrap();
    let binding = o.request_binding(&id).unwrap();
    assert_eq!(binding.request_epoch(), "epoch");
    assert_eq!(o.owner_epoch(), "epoch-new");
    assert_eq!(o.lookup(&id).unwrap().status, "unknown");
    assert!(before.held_micro_cny.value() > 0);
    assert_eq!(o.budget().unwrap().held_micro_cny, before.held_micro_cny);
}
#[test]
fn actual_ledger_admission_facts_include_live_original_and_private_context_without_permission() {
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
    let _unsent = o
        .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
        .unwrap();
    let facts = ledger.admission_facts(&scope, &root, &o).unwrap();
    assert_eq!(facts.root().id(), root);
    assert_eq!(facts.children().len(), 1);
    assert_eq!(facts.active_child_count(), 1);
    let row = &facts.children()[0];
    assert_eq!(row.id(), child);
    assert_eq!(row.owner_epoch(), "epoch");
    assert_eq!(row.host_session(), "session");
    assert_eq!(row.originals()[0].payload_digest(), p.payload_digest);
    assert_eq!(row.observations()[0].status, "unknown");
    assert!(row.native_context_current());
    assert!(row.skill_current());
    assert!(!facts.execution_authority());
}

#[test]
fn canonical_group_binding_is_real_durable_scoped_and_preserves_original_gate() {
    let f = Fixture::new();
    let s = f.init();
    s.initialize_group_request_bindings().unwrap();
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
    let allowed = Capabilities {
        scopes: BTreeSet::from(["project".into()]),
        permissions: BTreeSet::from(["read".into()]),
    };
    assert_eq!(
        apply(
            &s,
            &mutation(
                "canonical-node",
                2,
                1,
                GroupOperation::Plan {
                    run_id: "run".into(),
                    node_id: "node".into(),
                    member_id: "a".into(),
                    dependencies: BTreeSet::new(),
                    capabilities: allowed,
                    payload_digest: p.payload_digest.clone()
                }
            )
        )
        .status,
        LocalStatus::Committed
    );
    let c = mutation(
        "canonical-bind",
        3,
        1,
        GroupOperation::BindCanonical {
            run_id: "run".into(),
            node_id: "node".into(),
            workflow_run_id: child.clone(),
            request_id: p.request_id.clone(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_canonical_local(&c, &o, &ledger, &scope)
            .unwrap()
            .status,
        LocalStatus::Committed
    );
    let group_scope = GroupScope::current(&s, "project", "group").unwrap();
    let binding = s
        .group_request_binding(&group_scope, "run", "node")
        .unwrap();
    let v = serde_json::to_value(&binding).unwrap();
    assert_eq!(v["request_id"], p.request_id);
    assert_eq!(v["payload_digest"], p.payload_digest);
    assert_eq!(v["member_id"], "a");
    assert_eq!(v["workflow_run_id"], child);
    assert_eq!(v["root_task_id"], root);
    assert_eq!(v["registered_revision"], "4");
    let looked = s
        .group_lookup_original(&group_scope, "run", "node", &o)
        .unwrap();
    assert_eq!(looked.status, "prepared");
    let ui=s.group_ui_read(&ui_scope(&s),&json!({"schema_version":1,"request":{"operation":"run","group_id":"group","run_id":"run"}}).to_string(),Some(&o),None);
    println!("CANONICAL_CHILD_UI={ui:?}");
    assert!(ui.is_ok());
    assert!(matches!(
        s.group_next_pending(&group_scope, "run", &o).unwrap(),
        PendingAdvice::LookupOriginal { .. }
    ));
    let check = s
        .group_recheck_request_binding(&group_scope, "run", "node", &o, &ledger, &scope)
        .unwrap();
    let view = serde_json::to_value(check).unwrap();
    assert_eq!(view["canonical_verified_now"], true);
    assert_eq!(view["execution_authority"], false);
    let cfg = o.configuration().unwrap();
    o.confirm_trusted(&p.request_id, &cfg.id).unwrap();
    let _unsent = o
        .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
        .unwrap();
    let held = o.budget().unwrap().held_micro_cny;
    assert_eq!(
        apply(
            &s,
            &mutation(
                "stop-bound",
                4,
                1,
                GroupOperation::Stop {
                    run_id: "run".into()
                }
            )
        )
        .status,
        LocalStatus::Committed
    );
    let view = serde_json::to_value(
        s.group_recheck_request_binding(&group_scope, "run", "node", &o, &ledger, &scope)
            .unwrap(),
    )
    .unwrap();
    assert_eq!(view["observations"][0]["status"], "unknown");
    assert_eq!(view["execution_authority"], false);
    assert_eq!(o.budget().unwrap().held_micro_cny, held);
}

fn check_ledger_moved_physical_key(column: &str) {
    let f = Fixture::new();
    let s = f.init();
    let (mut ledger, scope, root) = actual_workflow(&f, &s);
    let o = owner(&f);
    let child=ledger.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
    let db = sqlite::Db::open(f.0.join("workflow.sqlite").to_str().unwrap(), false, false).unwrap();
    db.exec(
        &format!("UPDATE runs SET {column}='moved-away' WHERE id=?"),
        &[&child],
    )
    .unwrap();
    let facts = ledger.admission_facts(&scope, &root, &o);
    if let Ok(value) = &facts {
        println!(
            "MOVED_COLUMN={column} ACTUAL_CHILDREN={}",
            value.children().len()
        );
    }
    assert!(
        facts.is_err(),
        "a contradictory physical index must not produce complete lifetime facts"
    );
}
#[test]
fn ledger_complete_facts_do_not_omit_a_child_moved_to_another_physical_root() {
    check_ledger_moved_physical_key("root");
}
#[test]
fn ledger_complete_facts_do_not_omit_a_child_moved_to_another_physical_scope() {
    check_ledger_moved_physical_key("scope");
}
#[test]
fn ledger_facts_reject_duplicate_remote_conversations_and_original_chains() {
    let f = Fixture::new();
    let s = f.init();
    let (mut ledger, scope, root) = actual_workflow(&f, &s);
    let o = owner(&f);
    let mut children = Vec::new();
    let mut plans = Vec::new();
    for _ in 0..2 {
        let id=ledger.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
        let context = ledger.remote_context(&scope, &id).unwrap();
        let plan = o
            .prepare_chat(
                context["conversation_id"].as_str().unwrap(),
                "Synthetic",
                Some(&Proof),
            )
            .unwrap();
        ledger.bind_remote_plan(&scope, &id, &plan).unwrap();
        children.push(id);
        plans.push(plan);
    }
    let db = sqlite::Db::open(f.0.join("workflow.sqlite").to_str().unwrap(), false, false).unwrap();
    let row = db
        .query("SELECT record FROM runs WHERE id=?", &[&children[1]])
        .unwrap();
    let mut record: serde_json::Value =
        serde_json::from_str(row[0][0].as_deref().unwrap()).unwrap();
    record["conversation_id"] = json!(plans[0].conversation_id);
    record["remote_request_id"] = json!(plans[0].request_id);
    record["current_request_id"] = json!(plans[0].request_id);
    record["remote_request_ids"] = json!([plans[0].request_id]);
    db.exec(
        "UPDATE runs SET record=? WHERE id=?",
        &[&record.to_string(), &children[1]],
    )
    .unwrap();
    assert!(
        ledger.admission_facts(&scope, &root, &o).is_err(),
        "same original must not count as two independent children"
    );
}

struct CanonicalFixture {
    files: Fixture,
    store: BusinessStore,
    owner: agent::owner::AgentOwner,
    ledger: agent::workflow::RunLedger,
    scope: agent::workflow::RunScope,
    plan: agent::owner::AgentPlan,
    command: GroupCommand,
    child: String,
    root: String,
}
impl CanonicalFixture {
    fn new() -> Self {
        let f = Fixture::new();
        let s = f.init();
        s.initialize_group_request_bindings().unwrap();
        let (mut ledger, scope, root) = actual_workflow(&f, &s);
        let owner = owner(&f);
        let child=ledger.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
        let context = ledger.remote_context(&scope, &child).unwrap();
        let plan = owner
            .prepare_chat(
                context["conversation_id"].as_str().unwrap(),
                "Synthetic",
                Some(&Proof),
            )
            .unwrap();
        ledger.bind_remote_plan(&scope, &child, &plan).unwrap();
        let allowed = Capabilities {
            scopes: BTreeSet::from(["project".into()]),
            permissions: BTreeSet::from(["read".into()]),
        };
        assert_eq!(
            apply(
                &s,
                &mutation(
                    "canonical-node",
                    2,
                    1,
                    GroupOperation::Plan {
                        run_id: "run".into(),
                        node_id: "node".into(),
                        member_id: "a".into(),
                        dependencies: BTreeSet::new(),
                        capabilities: allowed,
                        payload_digest: plan.payload_digest.clone()
                    }
                )
            )
            .status,
            LocalStatus::Committed
        );
        let command = mutation(
            "canonical-bind",
            3,
            1,
            GroupOperation::BindCanonical {
                run_id: "run".into(),
                node_id: "node".into(),
                workflow_run_id: child.clone(),
                request_id: plan.request_id.clone(),
            },
        );
        s.issue_group_local_grant_trusted(&command).unwrap();
        Self {
            files: f,
            store: s,
            owner,
            ledger,
            scope,
            plan,
            command,
            child,
            root,
        }
    }
    fn bind(&self) -> LocalReceipt {
        self.store
            .execute_group_canonical_local(&self.command, &self.owner, &self.ledger, &self.scope)
            .unwrap()
    }
    fn check(&self) -> serde_json::Value {
        let scope = GroupScope::current(&self.store, "project", "group").unwrap();
        serde_json::to_value(
            self.store
                .group_recheck_request_binding(
                    &scope,
                    "run",
                    "node",
                    &self.owner,
                    &self.ledger,
                    &self.scope,
                )
                .unwrap(),
        )
        .unwrap()
    }
}
#[test]
fn canonical_context_recheck_detects_real_configuration_replacement() {
    let f = CanonicalFixture::new();
    assert_eq!(f.bind().status, LocalStatus::Committed);
    assert_eq!(f.check()["context_current"], true);
    let mut settings = f.owner.configuration().unwrap().settings;
    settings.credential_generation = "synthetic-next".into();
    f.owner.configure_trusted(settings).unwrap();
    let checked = f.check();
    println!("CONFIGURATION_REPLACED={checked}");
    assert_eq!(checked["canonical_verified_now"], true);
    assert_eq!(checked["context_current"], false);
    assert_eq!(checked["configuration_current"], false);
    assert_eq!(checked["execution_authority"], false);
}

#[test]
fn canonical_mapping_survives_restart_as_readonly_unknown_without_freeing_original_hold() {
    let f = CanonicalFixture::new();
    assert_eq!(f.bind().status, LocalStatus::Committed);
    let cfg = f.owner.configuration().unwrap();
    f.owner
        .confirm_trusted(&f.plan.request_id, &cfg.id)
        .unwrap();
    let _unsent = f
        .owner
        .claim_dispatch(
            &f.plan.request_id,
            &cfg.id,
            &cfg.settings.credential_generation,
        )
        .unwrap();
    let held = f.owner.budget().unwrap().held_micro_cny;
    let original = f.plan.request_id.clone();
    let CanonicalFixture {
        files,
        store,
        owner,
        ledger,
        ..
    } = f;
    drop(store);
    drop(owner);
    drop(ledger);
    let s = BusinessStore::open_existing(&files.path(), "ws", "epoch-new").unwrap();
    let o =
        agent::owner::AgentOwner::open(&files.0.join("agent.sqlite"), "ws", "epoch-new").unwrap();
    let l = agent::workflow::RunLedger::open(&files.0.join("workflow.sqlite"), "ws", "epoch-new")
        .unwrap();
    let scope =
        agent::workflow::RunScope::current(&s, "session-new", "conversation", Some("project"))
            .unwrap();
    let g = GroupScope::current(&s, "project", "group").unwrap();
    let view = serde_json::to_value(
        s.group_recheck_request_binding(&g, "run", "node", &o, &l, &scope)
            .unwrap(),
    )
    .unwrap();
    assert_eq!(view["binding"]["request_id"], original);
    assert_eq!(view["canonical_verified_now"], true);
    assert_eq!(view["workflow_verified_now"], true);
    assert_eq!(view["context_current"], false);
    assert_eq!(view["observations"][0]["status"], "unknown");
    assert_eq!(view["execution_authority"], false);
    assert_eq!(o.budget().unwrap().held_micro_cny, held);
    assert!(matches!(
        s.group_next_pending(&g, "run", &o).unwrap(),
        PendingAdvice::LookupOriginal { .. }
    ));
}
#[test]
fn canonical_binding_without_real_ledger_context_is_refused_then_real_native_path_works() {
    let mut f = CanonicalFixture::new();
    assert_eq!(
        f.store
            .execute_group_local(&f.command, Some(&f.owner))
            .unwrap()
            .status,
        LocalStatus::Rejected
    );
    assert!(f
        .store
        .database()
        .query("SELECT * FROM group_request_bindings", &[])
        .unwrap()
        .is_empty());
    f.command.intent_id = "canonical-real".into();
    f.command.authority.grant_id = "grant-canonical-real".into();
    f.store.issue_group_local_grant_trusted(&f.command).unwrap();
    assert_eq!(f.bind().status, LocalStatus::Committed);
}
#[test]
fn canonical_binding_does_not_substitute_another_actual_root_even_with_same_payload_digest() {
    let mut f = CanonicalFixture::new();
    let root = f
        .ledger
        .execute(
            &json!({"action":"create_root","title":"Other","task":"Synthetic"}).to_string(),
            &f.store,
            &f.scope,
        )
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();
    let child=f.ledger.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&f.store,&f.scope).unwrap()["id"].as_str().unwrap().to_string();
    let context = f.ledger.remote_context(&f.scope, &child).unwrap();
    let p = f
        .owner
        .prepare_chat(
            context["conversation_id"].as_str().unwrap(),
            "Synthetic",
            Some(&Proof),
        )
        .unwrap();
    f.ledger.bind_remote_plan(&f.scope, &child, &p).unwrap();
    assert_eq!(p.payload_digest, f.plan.payload_digest);
    f.command.intent_id = "wrong-root".into();
    f.command.authority.grant_id = "grant-wrong-root".into();
    f.command.operation = GroupOperation::BindCanonical {
        run_id: "run".into(),
        node_id: "node".into(),
        workflow_run_id: child,
        request_id: p.request_id,
    };
    f.store.issue_group_local_grant_trusted(&f.command).unwrap();
    assert_eq!(f.bind().status, LocalStatus::Rejected);
    assert!(f
        .store
        .database()
        .query("SELECT * FROM group_request_bindings", &[])
        .unwrap()
        .is_empty());
}
#[test]
fn canonical_binding_tail_fault_rolls_back_all_local_effects_and_gates_actual_unknown() {
    let f = CanonicalFixture::new();
    let cfg = f.owner.configuration().unwrap();
    f.owner
        .confirm_trusted(&f.plan.request_id, &cfg.id)
        .unwrap();
    let _unsent = f
        .owner
        .claim_dispatch(
            &f.plan.request_id,
            &cfg.id,
            &cfg.settings.credential_generation,
        )
        .unwrap();
    let held = f.owner.budget().unwrap().held_micro_cny;
    f.store.database().exec("CREATE TRIGGER damage_mapping AFTER INSERT ON group_request_bindings BEGIN UPDATE group_request_bindings SET record='{}' WHERE request_id=NEW.request_id; END",&[]).unwrap();
    assert_eq!(f.bind().status, LocalStatus::PendingOriginal);
    assert!(f
        .store
        .database()
        .query("SELECT * FROM group_request_bindings", &[])
        .unwrap()
        .is_empty());
    let g = GroupScope::current(&f.store, "project", "group").unwrap();
    assert_eq!(
        f.store.group_registration(&g).unwrap().revision,
        Revision::new(3)
    );
    let advice = f.store.group_next_pending(&g, "run", &f.owner).unwrap();
    println!("UNBOUND_ORIGINAL_ADVICE={advice:?}");
    assert!(
        matches!(advice,PendingAdvice::LookupOriginal{request_id} if request_id==f.plan.request_id)
    );
    assert_eq!(f.owner.budget().unwrap().held_micro_cny, held);
}

#[test]
fn canonical_registered_mapping_requires_its_actual_committed_original_local_receipt() {
    for fault in ["UPDATE group_runtime_local_intents SET status='pending',receipt=NULL WHERE intent_id='canonical-bind'","DELETE FROM group_runtime_events WHERE intent_id='canonical-bind'"] {
        let f=CanonicalFixture::new();assert_eq!(f.bind().status,LocalStatus::Committed);
        f.store.database().exec(fault,&[]).unwrap();
        let scope=GroupScope::current(&f.store,"project","group").unwrap();
        let actual=f.store.group_request_binding(&scope,"run","node");
        assert!(matches!(actual,Err(ContractError::Unknown)),"a mapping alone cannot certify its local origin receipt");
    }
}
#[test]
fn canonical_binding_cannot_grow_the_actual_members_task_capabilities() {
    let f = CanonicalFixture::new();
    let row = f
        .store
        .database()
        .query(
            "SELECT record FROM group_runtime_nodes WHERE node_id='node'",
            &[],
        )
        .unwrap();
    let mut node: serde_json::Value = serde_json::from_str(row[0][0].as_deref().unwrap()).unwrap();
    node["capabilities"]["permissions"] = json!(["read", "extra-permission"]);
    f.store
        .database()
        .exec(
            "UPDATE group_runtime_nodes SET record=? WHERE node_id='node'",
            &[&node.to_string()],
        )
        .unwrap();
    assert_eq!(f.bind().status, LocalStatus::Rejected);
    assert!(f
        .store
        .database()
        .query("SELECT * FROM group_request_bindings", &[])
        .unwrap()
        .is_empty());
}
#[test]
fn canonical_mapping_event_receipt_and_consume_faults_rollback_and_never_replay() {
    for (label,trigger,mutation) in [
        ("event","AFTER INSERT ON group_runtime_events WHEN NEW.intent_id='canonical-bind'","UPDATE group_request_bindings SET record='{}'"),
        ("receipt","AFTER UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='canonical-bind' AND NEW.status='committed'","UPDATE group_runtime_nodes SET record='{}' WHERE node_id='node'"),
        ("consume","AFTER UPDATE ON business_grants WHEN NEW.grant_id='grant-canonical-bind' AND NEW.active=0","UPDATE group_runtime_runs SET record='{}' WHERE run_id='run'"),
    ] {
        let f=CanonicalFixture::new();
        let group=f.store.database().query("SELECT * FROM group_runtime_groups",&[]).unwrap();let runs=f.store.database().query("SELECT * FROM group_runtime_runs",&[]).unwrap();let nodes=f.store.database().query("SELECT * FROM group_runtime_nodes",&[]).unwrap();
        f.store.database().exec(&format!("CREATE TRIGGER damage_binding_tail {trigger} BEGIN {mutation}; END"),&[]).unwrap();
        assert_eq!(f.bind().status,LocalStatus::PendingOriginal,"{label}");
        assert_eq!(f.store.database().query("SELECT * FROM group_runtime_groups",&[]).unwrap(),group,"{label}");assert_eq!(f.store.database().query("SELECT * FROM group_runtime_runs",&[]).unwrap(),runs,"{label}");assert_eq!(f.store.database().query("SELECT * FROM group_runtime_nodes",&[]).unwrap(),nodes,"{label}");
        assert!(f.store.database().query("SELECT * FROM group_request_bindings",&[]).unwrap().is_empty());
        assert!(f.store.database().query("SELECT * FROM group_runtime_events WHERE intent_id='canonical-bind'",&[]).unwrap().is_empty());
        assert_eq!(f.store.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='canonical-bind'",&[]).unwrap(),vec![vec![Some("pending".into()),None]]);
        assert_eq!(f.store.database().query("SELECT active FROM business_grants WHERE grant_id='grant-canonical-bind'",&[]).unwrap()[0][0].as_deref(),Some("1"));
        f.store.database().exec("DROP TRIGGER damage_binding_tail",&[]).unwrap();
        assert_eq!(f.bind().status,LocalStatus::PendingOriginal,"removing a fault is not authorization to replay {label}");
        assert!(f.store.database().query("SELECT * FROM group_request_bindings",&[]).unwrap().is_empty());
        assert_eq!(f.owner.lookup(&f.plan.request_id).unwrap().status,"prepared");
    }
}
#[test]
fn canonical_recheck_source_failure_keeps_registered_original_identity_without_ready_or_known_usage(
) {
    let f = CanonicalFixture::new();
    assert_eq!(f.bind().status, LocalStatus::Committed);
    let db = sqlite::Db::open(
        f.files.0.join("agent.sqlite").to_str().unwrap(),
        false,
        false,
    )
    .unwrap();
    db.exec("ALTER TABLE requests RENAME TO unavailable_requests", &[])
        .unwrap();
    let view = f.check();
    assert_eq!(view["binding"]["request_id"], f.plan.request_id);
    assert_eq!(view["canonical_verified_now"], false);
    assert_eq!(view["recovery_state"], "query_original");
    assert_eq!(view["execution_authority"], false);
    assert!(view["source_error"].is_string());
    db.exec("ALTER TABLE unavailable_requests RENAME TO requests", &[])
        .unwrap();
    assert_eq!(f.check()["canonical_verified_now"], true);
}

#[test]
fn pending_canonical_actual_unknown_blocks_the_real_handoff_checkpoint() {
    let f = CanonicalFixture::new();
    let cfg = f.owner.configuration().unwrap();
    f.owner
        .confirm_trusted(&f.plan.request_id, &cfg.id)
        .unwrap();
    let _unsent = f
        .owner
        .claim_dispatch(
            &f.plan.request_id,
            &cfg.id,
            &cfg.settings.credential_generation,
        )
        .unwrap();
    let held = f.owner.budget().unwrap().held_micro_cny;
    f.store.database().exec("CREATE TRIGGER damage_pending_map AFTER INSERT ON group_request_bindings BEGIN UPDATE group_request_bindings SET record='{}' WHERE request_id=NEW.request_id; END",&[]).unwrap();
    assert_eq!(f.bind().status, LocalStatus::PendingOriginal);
    let c = mutation(
        "pending-handoff",
        3,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    f.store.issue_group_local_grant_trusted(&c).unwrap();
    let r = f.store.execute_group_local(&c, Some(&f.owner)).unwrap();
    let g = GroupScope::current(&f.store, "project", "group").unwrap();
    let run = f.store.group_run(&g, "run").unwrap();
    println!("PENDING_CANONICAL_HANDOFF={r:?} EPOCH={}", run.epoch);
    assert_eq!(r.status, LocalStatus::Rejected);
    assert_eq!(run.epoch, 1);
    assert_eq!(f.owner.budget().unwrap().held_micro_cny, held);
    assert_eq!(
        f.owner.lookup(&f.plan.request_id).unwrap().status,
        "unknown"
    );
}

#[test]
fn pending_canonical_missing_identity_does_not_restore_admission_or_handoff() {
    let f = CanonicalFixture::new();
    let cfg = f.owner.configuration().unwrap();
    f.owner
        .confirm_trusted(&f.plan.request_id, &cfg.id)
        .unwrap();
    let _unsent = f
        .owner
        .claim_dispatch(
            &f.plan.request_id,
            &cfg.id,
            &cfg.settings.credential_generation,
        )
        .unwrap();
    f.store.database().exec("CREATE TRIGGER break_missing_mapping AFTER INSERT ON group_request_bindings BEGIN UPDATE group_request_bindings SET record='{}' WHERE request_id=NEW.request_id; END",&[]).unwrap();
    assert_eq!(f.bind().status, LocalStatus::PendingOriginal);
    f.store
        .database()
        .exec(
            "DELETE FROM group_runtime_intent_bindings WHERE intent_id='canonical-bind'",
            &[],
        )
        .unwrap();
    let g = GroupScope::current(&f.store, "project", "group").unwrap();
    let advice = f.store.group_next_pending(&g, "run", &f.owner);
    println!("MISSING_PENDING_IDENTITY_ADVICE={advice:?}");
    let h = mutation(
        "handoff-missing-pending-source",
        3,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    f.store.issue_group_local_grant_trusted(&h).unwrap();
    let receipt = f.store.execute_group_local(&h, Some(&f.owner)).unwrap();
    println!("MISSING_PENDING_IDENTITY_HANDOFF={receipt:?}");
    assert!(!matches!(advice,Ok(PendingAdvice::PendingHostAdmission{..})),"loss of original pending identity proof must remain inconclusive, never new host-admission advice");
    assert_eq!(receipt.status, LocalStatus::PendingOriginal);
    assert_eq!(f.store.group_run(&g, "run").unwrap().epoch, 1);
    assert_eq!(
        f.owner.lookup(&f.plan.request_id).unwrap().status,
        "unknown"
    );
}
#[test]
fn typed_admission_facts_cover_eight_lifetime_children_after_display_event_pruning() {
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
    let facts = ledger.admission_facts(&scope, &root, &o).unwrap();
    assert_eq!(facts.children().len(), 8);
    assert_eq!(facts.active_child_count(), 1);
    assert!(!facts.execution_authority());
    let value = serde_json::to_value(&facts).unwrap();
    assert_eq!(value["complete_lifetime_children"], true);
    assert_eq!(value["cross_owner_atomic"], false);
    assert_eq!(value["root_budget_available"], false);
    assert_eq!(o.lookup(&p.request_id).unwrap().status, "unknown");
    assert!(o.budget().unwrap().held_micro_cny.value() > 0);
}

#[test]
fn pending_canonical_chain_read_failure_remains_pending_and_keeps_epoch_and_hold() {
    let f = CanonicalFixture::new();
    let cfg = f.owner.configuration().unwrap();
    f.owner
        .confirm_trusted(&f.plan.request_id, &cfg.id)
        .unwrap();
    let _unsent = f
        .owner
        .claim_dispatch(
            &f.plan.request_id,
            &cfg.id,
            &cfg.settings.credential_generation,
        )
        .unwrap();
    let held = f.owner.budget().unwrap().held_micro_cny;
    f.store.database().exec("CREATE TRIGGER break_pending_chain_map AFTER INSERT ON group_request_bindings BEGIN UPDATE group_request_bindings SET record='{}' WHERE request_id=NEW.request_id; END",&[]).unwrap();
    assert_eq!(f.bind().status, LocalStatus::PendingOriginal);
    let db = sqlite::Db::open(
        f.files.0.join("agent.sqlite").to_str().unwrap(),
        false,
        false,
    )
    .unwrap();
    db.exec(
        "ALTER TABLE tool_steps RENAME TO unavailable_tool_steps",
        &[],
    )
    .unwrap();
    let c = mutation(
        "handoff-chain-unavailable",
        3,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    f.store.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        f.store
            .execute_group_local(&c, Some(&f.owner))
            .unwrap()
            .status,
        LocalStatus::PendingOriginal
    );
    let g = GroupScope::current(&f.store, "project", "group").unwrap();
    assert_eq!(f.store.group_run(&g, "run").unwrap().epoch, 1);
    assert_eq!(f.owner.budget().unwrap().held_micro_cny, held);
    db.exec(
        "ALTER TABLE unavailable_tool_steps RENAME TO tool_steps",
        &[],
    )
    .unwrap();
    assert_eq!(
        f.owner.lookup(&f.plan.request_id).unwrap().status,
        "unknown"
    );
    assert_eq!(
        f.store
            .execute_group_local(&c, Some(&f.owner))
            .unwrap()
            .status,
        LocalStatus::PendingOriginal
    );
}

#[test]
fn canonical_tail_preserves_exact_source_plan_provenance_or_rolls_back() {
    for (label, mutation) in [
        (
            "event_delete",
            "DELETE FROM group_runtime_events WHERE intent_id='canonical-node'",
        ),
        (
            "receipt_rewrite",
            "UPDATE group_runtime_local_intents SET receipt='{}' WHERE intent_id='canonical-node'",
        ),
        (
            "command_delete",
            "DELETE FROM group_runtime_intent_bindings WHERE intent_id='canonical-node'",
        ),
    ] {
        let f = CanonicalFixture::new();
        let before = f
            .store
            .database()
            .query("SELECT * FROM group_runtime_events", &[])
            .unwrap();
        f.store.database().exec(&format!("CREATE TRIGGER damage_source_plan AFTER INSERT ON group_request_bindings BEGIN {mutation}; END"),&[]).unwrap();
        assert_eq!(f.bind().status, LocalStatus::PendingOriginal, "{label}");
        assert_eq!(
            f.store
                .database()
                .query("SELECT * FROM group_runtime_events", &[])
                .unwrap(),
            before,
            "{label}"
        );
        assert!(f
            .store
            .database()
            .query("SELECT * FROM group_request_bindings", &[])
            .unwrap()
            .is_empty());
        assert_eq!(
            f.store
                .database()
                .query(
                    "SELECT active FROM business_grants WHERE grant_id='grant-canonical-bind'",
                    &[]
                )
                .unwrap()[0][0]
                .as_deref(),
            Some("1")
        );
        let g = GroupScope::current(&f.store, "project", "group").unwrap();
        assert_eq!(
            f.store.group_registration(&g).unwrap().revision,
            Revision::new(3)
        );
    }
}

#[path = "/workspace/mig20/crates/muyon-core/tests/support/group_origin_gate_cases.rs"]
mod group_origin_gate_cases;
fn independent_prepared_group() -> (
    Fixture,
    BusinessStore,
    agent::owner::AgentOwner,
    agent::workflow::RunLedger,
    agent::workflow::RunScope,
    agent::owner::AgentPlan,
    String,
) {
    let f = Fixture::new();
    let s = f.init();
    let o = owner(&f);
    let (mut l, scope, root) = actual_workflow(&f, &s);
    let child=l.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
    let g = GroupScope::current(&s, "project", "group").unwrap();
    let p = s
        .group_prepare_chat(
            &g,
            &o,
            &l,
            &scope,
            group_runtime_store::gate::GroupChatPreparation {
                run_id: "run",
                workflow_run_id: &child,
                member_id: "a",
                text: "Synthetic group",
            },
            Some(&Proof),
        )
        .unwrap();
    (f, s, o, l, scope, p, child)
}
fn independent_approve_actual_tool(
    s: &BusinessStore,
    o: &agent::owner::AgentOwner,
    p: &agent::owner::AgentPlan,
) -> agent::tools::ToolsContext {
    independent_approve_actual_tool_with_ref(s, o, p, &format!("call_{}", p.request_id))
}
fn independent_approve_actual_tool_with_ref(
    s: &BusinessStore,
    o: &agent::owner::AgentOwner,
    p: &agent::owner::AgentPlan,
    call_ref: &str,
) -> agent::tools::ToolsContext {
    let ctx =
        agent::tools::ToolsContext::current(s, "session", "generation", Some("project")).unwrap();
    o.bind_tool_scope_trusted(&p.request_id, &ctx).unwrap();
    let cfg = o.configuration().unwrap();
    o.confirm_trusted(&p.request_id, &cfg.id).unwrap();
    let _unsent = o
        .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
        .unwrap();
    let body=json!({"id":"synthetic-tool","model":agent::owner::MODEL,"choices":[{"index":0,"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"tool_calls":[{"id":call_ref,"type":"function","function":{"name":"product_supplier_list","arguments":"{\"limit\":5,\"offset\":0}"}}]}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string();
    assert_eq!(
        o.settle_response(&p.request_id, &body).unwrap().status,
        "tool_pending"
    );
    let review = o.review_tool_read(s, &ctx, &p.request_id).unwrap();
    o.approve_tool_read_trusted(s, &ctx, &p.request_id, &review.digest)
        .unwrap();
    ctx
}
fn independent_map_actual(
    s: &BusinessStore,
    o: &agent::owner::AgentOwner,
    l: &mut agent::workflow::RunLedger,
    scope: &agent::workflow::RunScope,
    p: &agent::owner::AgentPlan,
    child: &str,
) {
    s.initialize_group_request_bindings().unwrap();
    l.bind_remote_plan(scope, child, p).unwrap();
    let g = GroupScope::current(s, "project", "group").unwrap();
    let caps = s.group_run(&g, "run").unwrap().members["a"].clone();
    assert_eq!(
        apply(
            s,
            &mutation(
                "group-origin-node",
                2,
                1,
                GroupOperation::Plan {
                    run_id: "run".into(),
                    node_id: "node".into(),
                    member_id: "a".into(),
                    dependencies: BTreeSet::new(),
                    capabilities: caps,
                    payload_digest: p.payload_digest.clone()
                }
            )
        )
        .status,
        LocalStatus::Committed
    );
    let c = mutation(
        "group-origin-map",
        3,
        1,
        GroupOperation::BindCanonical {
            run_id: "run".into(),
            node_id: "node".into(),
            workflow_run_id: child.into(),
            request_id: p.request_id.clone(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_canonical_local(&c, o, l, scope)
            .unwrap()
            .status,
        LocalStatus::Committed
    );
}

fn independent_expected_followup_body(o:&agent::owner::AgentOwner,db:&sqlite::Db,parent:&agent::owner::AgentPlan)->serde_json::Value {
 let mut expected=parent.outbound_preview.clone();let answer=o.lookup(&parent.request_id).unwrap().answer.unwrap();let call:&serde_json::Value=&answer["call"];
 let wire=agent::tools::definitions().unwrap().into_iter().find(|d|d.name==call["name"].as_str().unwrap()).unwrap().wire_name;
 let review=db.query("SELECT review FROM tool_steps WHERE request_id=?",&[&parent.request_id]).unwrap()[0][0].clone().unwrap();
 expected["messages"].as_array_mut().unwrap().push(json!({"role":"assistant","content":null,"tool_calls":[{"id":call["call_ref"],"type":"function","function":{"name":wire,"arguments":call["arguments"].to_string()}}]}));
 expected["messages"].as_array_mut().unwrap().push(json!({"role":"tool","tool_call_id":call["call_ref"],"content":review}));expected
}
#[test]
fn independent_legal_second_followup_preserves_full_actual_payload_chain_and_hold() {
 let(f,s,o,mut l,scope,p,child)=independent_prepared_group();independent_map_actual(&s,&o,&mut l,&scope,&p,&child);
 let db=sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(),false,false).unwrap();
 let ctx=independent_approve_actual_tool_with_ref(&s,&o,&p,"independent-first-call");let expected_first=independent_expected_followup_body(&o,&db,&p);
 let next=o.prepare_tool_followup_trusted(&s,&ctx,&p.request_id,Some(&Proof)).unwrap();assert_eq!(next.outbound_preview,expected_first);
 let ctx=independent_approve_actual_tool_with_ref(&s,&o,&next,"independent-second-call");let expected_second=independent_expected_followup_body(&o,&db,&next);
 let last=o.prepare_tool_followup_trusted(&s,&ctx,&next.request_id,Some(&Proof));println!("ACTUAL_LEGAL_SECOND_PREPARE={:?}",last.as_ref().map(|v|&v.request_id));let last=last.unwrap();
 assert_eq!(last.outbound_preview,expected_second,"ALL envelope/messages/names/IDs/arguments/result contents preserved");assert_eq!(db.query("SELECT payload FROM requests WHERE id=?",&[&last.request_id]).unwrap()[0][0].as_deref(),Some(expected_second.to_string().as_str()));
 let chain=o.request_chain(&p.request_id).unwrap();assert_eq!(chain.iter().map(|v|v.request_id.as_str()).collect::<Vec<_>>(),vec![p.request_id.as_str(),next.request_id.as_str(),last.request_id.as_str()]);assert_eq!(chain.iter().map(|v|v.status.as_str()).collect::<Vec<_>>(),vec!["tool_consumed","tool_consumed","prepared"]);
 let first_origin=serde_json::to_value(o.request_origin(&p.request_id).unwrap()).unwrap();for (id,parent) in [(&next.request_id,&p.request_id),(&last.request_id,&next.request_id)] {let v=serde_json::to_value(o.request_origin(id).unwrap()).unwrap();assert_eq!(v["classification"],"group");assert_eq!(v["root_request_id"],p.request_id);assert_eq!(v["parent_request_id"],*parent);assert_eq!(v["group"],first_origin["group"]);}
 let gate=serde_json::to_value(s.group_request_gate(&last.request_id,&o,&l)).unwrap();assert_eq!(gate["group_hold"],true);assert_eq!(gate["execution_authority"],false);assert_eq!(gate["cross_owner_atomic"],false);assert_eq!(gate["canonical"]["request_id"],p.request_id);assert_eq!(gate["workflow"]["chain_contains_request"],true);
 assert_eq!(o.budget().unwrap().used_calls.value(),2);assert_eq!(o.budget().unwrap().charged_micro_cny.value(),132);assert_eq!(o.lookup(&last.request_id).unwrap().attempted,false);
}
#[test]
fn independent_kind_contradictions_never_erase_actual_group_references() {
 let f=CanonicalFixture::new();let db=sqlite::Db::open(f.files.0.join("workflow.sqlite").to_str().unwrap(),false,false).unwrap();let original=db.query("SELECT record FROM runs WHERE id=?",&[&f.child]).unwrap()[0][0].clone().unwrap();
 for kind in ["local_read","workflow","unknown_kind"] {let mut value:serde_json::Value=serde_json::from_str(&original).unwrap();value["kind"]=json!(kind);db.exec("UPDATE runs SET record=? WHERE id=?",&[&value.to_string(),&f.child]).unwrap();let attribution=f.ledger.request_attribution(&f.plan.request_id,&f.owner);let gate=f.store.group_request_gate(&f.plan.request_id,&f.owner,&f.ledger);println!("KIND={kind} ATTR_IS_ERR={} GROUP_HOLD={}",attribution.is_err(),gate.group_hold());assert!(attribution.is_err());assert!(gate.group_hold());db.exec("UPDATE runs SET record=? WHERE id=?",&[&original,&f.child]).unwrap();}
}
#[test]
fn independent_legal_local_read_and_direct_remain_nongroup() {
 let f=Fixture::new();let s=f.init();let o=owner(&f);let mut l=agent::workflow::RunLedger::open(&f.0.join("workflow.sqlite"),"ws","epoch").unwrap();let scope=agent::workflow::RunScope::current(&s,"session","independent-nongroup",Some("project")).unwrap();
 let root=l.execute(&json!({"action":"create_root","title":"Independent","task":"Offline"}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();let child=l.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Independent local","executor":"local_read","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();l.execute(&json!({"action":"execute_local","run_id":child}).to_string(),&s,&scope).unwrap();
 for conversation in ["independent-standalone","independent-nongroup"] {let p=o.prepare_chat(conversation,"Independent direct",Some(&Proof)).unwrap();assert!(l.request_attribution(&p.request_id,&o).unwrap().is_none());let gate=s.group_request_gate(&p.request_id,&o,&l);assert!(!gate.group_hold());assert_eq!(serde_json::to_value(gate).unwrap()["execution_authority"],false);}
}

fn independent_legacy_three_answers()->(Fixture,Vec<String>) {
 let f=Fixture::new();let o=owner(&f);let mut ids=Vec::new();for label in ["First","Second","Third"] {let p=o.prepare_chat("independent-migration-history",label,Some(&Proof)).unwrap();let cfg=o.configuration().unwrap();o.confirm_trusted(&p.request_id,&cfg.id).unwrap();let _unsent=o.claim_dispatch(&p.request_id,&cfg.id,&cfg.settings.credential_generation).unwrap();let reply=json!({"id":"synthetic","model":agent::owner::MODEL,"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":format!("Answer {label}")}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}});assert_eq!(o.settle_response(&p.request_id,&reply.to_string()).unwrap().status,"completed");ids.push(p.request_id);}
 drop(o);let db=sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(),false,false).unwrap();db.exec("DROP TABLE request_origins",&[]).unwrap();db.exec("UPDATE meta SET version='3'",&[]).unwrap();(f,ids)
}
#[test]
fn independent_migration_preserves_actual_rowid_order_and_rolls_back_replacement() {
 let(f,ids)=independent_legacy_three_answers();let db=sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(),false,false).unwrap();let before=db.query("SELECT rowid,* FROM requests ORDER BY id",&[]).unwrap();db.exec(&format!("CREATE TRIGGER reorder_original_history AFTER UPDATE OF version ON meta WHEN NEW.version='4' BEGIN INSERT OR REPLACE INTO requests SELECT * FROM requests WHERE id='{}'; END",ids[0]),&[]).unwrap();let migrated=agent::owner::AgentOwner::open(&f.0.join("agent.sqlite"),"ws","epoch");println!("ROWID_MIGRATION_REJECTED={} BEFORE={:?} AFTER={:?}",migrated.is_err(),before.iter().map(|r|&r[0]).collect::<Vec<_>>(),db.query("SELECT rowid,* FROM requests ORDER BY id",&[]).unwrap().iter().map(|r|&r[0]).collect::<Vec<_>>());assert!(migrated.is_err());assert_eq!(db.query("SELECT rowid,* FROM requests ORDER BY id",&[]).unwrap(),before);assert_eq!(db.query("SELECT version FROM meta",&[]).unwrap()[0][0].as_deref(),Some("3"));assert!(db.query("SELECT name FROM sqlite_master WHERE name='request_origins'",&[]).unwrap().is_empty());
}
#[test]
fn independent_normal_legacy_migration_preserves_next_actual_prompt_history() {
 let(f,_)=independent_legacy_three_answers();let db=sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(),false,false).unwrap();let before=db.query("SELECT rowid,* FROM requests ORDER BY id",&[]).unwrap();let o=agent::owner::AgentOwner::open(&f.0.join("agent.sqlite"),"ws","epoch").unwrap();assert_eq!(db.query("SELECT rowid,* FROM requests ORDER BY id",&[]).unwrap(),before);let p=o.prepare_chat("independent-migration-history","Fourth",Some(&Proof)).unwrap();let contents=p.outbound_preview["messages"].as_array().unwrap().iter().map(|m|m["content"].as_str().unwrap()).collect::<Vec<_>>();assert_eq!(contents,vec!["First","Answer First","Second","Answer Second","Third","Answer Third","Fourth"]);
}
#[test]
fn independent_second_followup_rejects_unknown_unselected_logical_and_unpaired_history() {
 use sha2::{Digest,Sha256};for fault in ["unknown_wire","unselected_wire","logical_in_wire","unpaired"] {
 let(f,s,o,mut l,scope,p,child)=independent_prepared_group();independent_map_actual(&s,&o,&mut l,&scope,&p,&child);let ctx=independent_approve_actual_tool_with_ref(&s,&o,&p,"independent-call-one");let next=o.prepare_tool_followup_trusted(&s,&ctx,&p.request_id,Some(&Proof)).unwrap();let ctx=independent_approve_actual_tool_with_ref(&s,&o,&next,"independent-call-two");
 let db=sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(),false,false).unwrap();let raw=db.query("SELECT payload FROM requests WHERE id=?",&[&next.request_id]).unwrap()[0][0].clone().unwrap();let mut body:serde_json::Value=serde_json::from_str(&raw).unwrap();
 match fault {"unknown_wire"=>body["messages"][1]["tool_calls"][0]["function"]["name"]=json!("product_not_registered"),"unselected_wire"=>body["messages"][1]["tool_calls"][0]["function"]["name"]=json!("product_paper_get"),"logical_in_wire"=>body["messages"][1]["tool_calls"][0]["function"]["name"]=json!("product.supplier_list"),_=>{body["messages"].as_array_mut().unwrap().remove(2);}}
 let payload=body.to_string();let digest=Sha256::digest(payload.as_bytes()).iter().map(|b|format!("{b:02x}")).collect::<String>();db.exec("UPDATE requests SET payload=?,digest=? WHERE id=?",&[&payload,&digest,&next.request_id]).unwrap();let mut origin:serde_json::Value=serde_json::from_str(db.query("SELECT record FROM request_origins WHERE request_id=?",&[&next.request_id]).unwrap()[0][0].as_ref().unwrap()).unwrap();origin["payload_digest"]=json!(digest);db.exec("UPDATE request_origins SET record=? WHERE request_id=?",&[&origin.to_string(),&next.request_id]).unwrap();assert!(o.request_origin(&next.request_id).unwrap().is_group());
 let queries=["SELECT * FROM requests ORDER BY id","SELECT * FROM request_origins ORDER BY request_id","SELECT * FROM tool_steps ORDER BY request_id"];let before=queries.iter().map(|q|db.query(q,&[]).unwrap()).collect::<Vec<_>>();let result=o.prepare_tool_followup_trusted(&s,&ctx,&next.request_id,Some(&Proof));println!("NEGATIVE_HISTORY={fault} RESULT={:?}",result.as_ref().map(|p|&p.request_id));assert!(matches!(result,Err("tool_history_invalid")),"{fault}");for(q,expected)in queries.iter().zip(before){assert_eq!(db.query(q,&[]).unwrap(),expected,"{fault}");}assert!(s.group_request_gate(&next.request_id,&o,&l).group_hold());
 }
}
#[test]
fn independent_duplicate_actual_call_ref_still_rejects_without_new_identity() {
 let(f,s,o,mut l,scope,p,child)=independent_prepared_group();independent_map_actual(&s,&o,&mut l,&scope,&p,&child);let ctx=independent_approve_actual_tool_with_ref(&s,&o,&p,"duplicate-call");let next=o.prepare_tool_followup_trusted(&s,&ctx,&p.request_id,Some(&Proof)).unwrap();let ctx=independent_approve_actual_tool_with_ref(&s,&o,&next,"duplicate-call");let db=sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(),false,false).unwrap();let before=db.query("SELECT * FROM requests ORDER BY id",&[]).unwrap();assert!(matches!(o.prepare_tool_followup_trusted(&s,&ctx,&next.request_id,Some(&Proof)),Err("tool_history_invalid")));assert_eq!(db.query("SELECT * FROM requests ORDER BY id",&[]).unwrap(),before);assert_eq!(o.request_chain(&p.request_id).unwrap().len(),2);assert!(s.group_request_gate(&next.request_id,&o,&l).group_hold());
}
