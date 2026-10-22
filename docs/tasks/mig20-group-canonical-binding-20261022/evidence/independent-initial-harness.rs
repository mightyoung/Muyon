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

fn independent_canonical_fixture() -> (Fixture,BusinessStore,agent::workflow::RunLedger,agent::workflow::RunScope,agent::owner::AgentOwner,String,String) {
 let f=Fixture::new();let s=f.init();s.initialize_group_request_bindings().unwrap();let (mut l,scope,root)=actual_workflow(&f,&s);
 let child=l.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
 let context=l.remote_context(&scope,&child).unwrap();let o=owner(&f);let plan=o.prepare_chat(context["conversation_id"].as_str().unwrap(),"Synthetic",Some(&Proof)).unwrap();l.bind_remote_plan(&scope,&child,&plan).unwrap();
 let caps=Capabilities{scopes:BTreeSet::from(["project".into()]),permissions:BTreeSet::from(["read".into()])};
 assert_eq!(apply(&s,&mutation("ind-node",2,1,GroupOperation::Plan{run_id:"run".into(),node_id:"node".into(),member_id:"a".into(),dependencies:BTreeSet::new(),capabilities:caps,payload_digest:plan.payload_digest})).status,LocalStatus::Committed);
 let c=mutation("ind-bind",3,1,GroupOperation::BindCanonical{run_id:"run".into(),node_id:"node".into(),workflow_run_id:child.clone(),request_id:plan.request_id});s.issue_group_local_grant_trusted(&c).unwrap();assert_eq!(s.execute_group_canonical_local(&c,&o,&l,&scope).unwrap().status,LocalStatus::Committed);
 (f,s,l,scope,o,root,child)
}
#[test]
fn independent_canonical_run_remains_readable_in_existing_ui() {
 let (_f,s,_l,_scope,o,_root,_child)=independent_canonical_fixture();
 let raw=json!({"schema_version":1,"request":{"operation":"run","group_id":"group","run_id":"run"}}).to_string();
 let v=s.group_ui_read(&ui_scope(&s),&raw,Some(&o),None);println!("CANONICAL_RUN_UI={v:?}");assert!(v.is_ok(),"actual canonical child mapping must remain readable");
}
#[test]
fn independent_actual_facts_must_not_hide_physically_misrooted_children() {
 let (f,s,mut l,scope,o,root,_child)=independent_canonical_fixture();
 let sibling=l.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic sibling","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
 let db=sqlite::Db::open(f.0.join("workflow.sqlite").to_str().unwrap(),false,false).unwrap();db.exec("UPDATE runs SET root='wrong-root' WHERE id=?",&[&sibling]).unwrap();
 let result=l.admission_facts(&scope,&root,&o);println!("HIDDEN_CHILD_FACTS={:?}",result.as_ref().map(|v|serde_json::to_value(v).unwrap()));assert!(result.is_err(),"inconsistent physical root must not silently disappear from complete lifetime facts");
}
#[test]
fn independent_actual_facts_reject_duplicate_original_identity_across_children() {
 let (f,s,mut l,scope,o,root,child)=independent_canonical_fixture();
 let sibling=l.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic sibling","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
 let db=sqlite::Db::open(f.0.join("workflow.sqlite").to_str().unwrap(),false,false).unwrap();let rows=db.query("SELECT record FROM runs WHERE id=?",&[&child]).unwrap();let original:serde_json::Value=serde_json::from_str(rows[0][0].as_ref().unwrap()).unwrap();
 let rows=db.query("SELECT record FROM runs WHERE id=?",&[&sibling]).unwrap();let mut second:serde_json::Value=serde_json::from_str(rows[0][0].as_ref().unwrap()).unwrap();
 for key in ["conversation_id","remote_request_id","current_request_id","remote_request_ids","status"] {second[key]=original[key].clone();}
 db.exec("UPDATE runs SET record=? WHERE id=?",&[&second.to_string(),&sibling]).unwrap();
 let result=l.admission_facts(&scope,&root,&o);println!("DUPLICATE_ORIGINAL_FACTS={:?}",result.as_ref().map(|v|serde_json::to_value(v).unwrap()));assert!(result.is_err(),"one owner request cannot be attributed to two workflow children");
}
