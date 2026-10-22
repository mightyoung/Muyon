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
#[path = "../src/documents/mod.rs"]
mod documents;
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
#[test]
fn registration_is_real_durable_scoped_fact_and_not_an_account_or_execution_grant() {
    let f = Fixture::new();
    let s = f.init();
    let c = command("register", 0, registration());
    assert_eq!(apply(&s, &c).status, LocalStatus::Committed);
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(s.group_registration(&scope).unwrap().owner, "owner");
    assert!(GroupScope::current(&s, "other", "group").is_err());
    drop(s);
    let s = f.store();
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(
        s.group_registration(&scope).unwrap().revision,
        Revision::new(1)
    );
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::Committed
    );
    assert!(s
        .database()
        .query("SELECT name FROM sqlite_master WHERE name='accounts'", &[])
        .unwrap()
        .is_empty());
}
#[test]
fn wire_claim_without_persisted_grant_and_member_management_are_denied() {
    let f = Fixture::new();
    let s = f.init();
    let mut c = command("register", 0, registration());
    assert!(s.execute_group_local(&c, None).is_err());
    c.actor = GroupActor::Member("owner".into());
    assert!(s.issue_group_local_grant_trusted(&c).is_err());
    assert!(GroupScope::current(&s, "project", "group").is_err());
}
#[test]
fn stale_revision_and_failed_sql_leave_no_partial_group_effect() {
    let f = Fixture::new();
    let s = f.init();
    apply(&s, &command("register", 0, registration()));
    let mut start = command(
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
    );
    start.expected_epoch = None;
    s.issue_group_local_grant_trusted(&start).unwrap();
    s.database().exec("CREATE TRIGGER fail_group_run BEFORE INSERT ON group_runtime_runs BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",&[]).unwrap();
    assert_eq!(
        s.execute_group_local(&start, None).unwrap().status,
        LocalStatus::PendingOriginal
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(
        s.group_registration(&scope).unwrap().revision,
        Revision::new(1)
    );
    assert!(s.group_run(&scope, "run").is_err());
    s.database()
        .exec("DROP TRIGGER fail_group_run", &[])
        .unwrap();
    assert_eq!(
        s.execute_group_local(&start, None).unwrap().status,
        LocalStatus::PendingOriginal
    );
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
fn plan(id: &str, rev: u64, epoch: u64, node: &str) -> GroupCommand {
    mutation(
        id,
        rev,
        epoch,
        GroupOperation::Plan {
            run_id: "run".into(),
            node_id: node.into(),
            member_id: "a".into(),
            dependencies: BTreeSet::new(),
            capabilities: Capabilities {
                scopes: BTreeSet::from(["project".into()]),
                permissions: BTreeSet::from(["read".into()]),
            },
            payload_digest: "a".repeat(64),
        },
    )
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
fn original(o: &agent::owner::AgentOwner, conversation: &str) -> String {
    let p = o
        .prepare_chat(conversation, "synthetic event fixture", Some(&Proof))
        .unwrap();
    let conf = o.configuration().unwrap();
    o.confirm_trusted(&p.request_id, &conf.id).unwrap();
    let _offline_bytes = o
        .claim_dispatch(
            &p.request_id,
            &conf.id,
            &conf.settings.credential_generation,
        )
        .unwrap();
    p.request_id
}
#[test]
fn handoff_and_stop_cas_survive_reopen_and_do_not_replay() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    let c = mutation(
        "handoff",
        2,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    let o = owner(&f);
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, Some(&o)).unwrap().status,
        LocalStatus::Committed
    );
    let r = s.group_run(&scope, "run").unwrap();
    assert_eq!(
        (r.epoch, r.handoffs, r.leader.as_deref()),
        (2, 1, Some("b"))
    );
    let stale = mutation(
        "stale",
        2,
        1,
        GroupOperation::Stop {
            run_id: "run".into(),
        },
    );
    s.issue_group_local_grant_trusted(&stale).unwrap();
    assert_eq!(
        s.execute_group_local(&stale, None).unwrap().status,
        LocalStatus::Rejected
    );
    apply(
        &s,
        &mutation(
            "stop",
            3,
            2,
            GroupOperation::Stop {
                run_id: "run".into(),
            },
        ),
    );
    drop(s);
    let s = f.store();
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert!(s.group_run(&scope, "run").unwrap().stopped);
    assert_eq!(s.group_run(&scope, "run").unwrap().epoch, 2);
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::Committed
    );
}
#[test]
fn schedule_is_only_durable_pending_advice_and_grants_are_consumed() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let o = owner(&f);
    let c = plan("plan", 2, 1, "node");
    apply(&s, &c);
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(
        s.group_next_pending(&scope, "run", &o).unwrap(),
        PendingAdvice::PendingHostAdmission {
            node_id: "node".into(),
            payload_digest: "a".repeat(64),
            epoch: 1
        }
    );
    assert_eq!(
        s.database()
            .query(
                "SELECT active FROM business_grants WHERE grant_id='grant-plan'",
                &[]
            )
            .unwrap()[0][0]
            .as_deref(),
        Some("0")
    );
    drop(s);
    let s = f.store();
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(
        s.group_next_pending(&scope, "run", &o).unwrap(),
        PendingAdvice::PendingHostAdmission {
            node_id: "node".into(),
            payload_digest: "a".repeat(64),
            epoch: 1
        }
    );
    assert_eq!(o.budget().unwrap().used_calls.value(), 0);
}
#[test]
fn real_original_unknown_is_scoped_query_only_and_holds_are_unchanged() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    apply(&s, &plan("plan", 2, 1, "node"));
    let o = owner(&f);
    let req = original(&o, "conversation");
    let bind = mutation(
        "bind",
        3,
        1,
        GroupOperation::BindOriginal {
            run_id: "run".into(),
            node_id: "node".into(),
            request_id: req.clone(),
        },
    );
    s.issue_group_local_grant_trusted(&bind).unwrap();
    assert_eq!(
        s.execute_group_local(&bind, Some(&o)).unwrap().status,
        LocalStatus::Committed
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    let held = o.budget().unwrap().held_micro_cny;
    assert_eq!(
        s.group_lookup_original(&scope, "run", "node", &o)
            .unwrap()
            .status,
        "unknown"
    );
    assert_eq!(
        s.group_next_pending(&scope, "run", &o).unwrap(),
        PendingAdvice::LookupOriginal {
            request_id: req.clone()
        }
    );
    assert_eq!(o.budget().unwrap().held_micro_cny, held);
    let transfer = mutation(
        "transfer",
        4,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    s.issue_group_local_grant_trusted(&transfer).unwrap();
    assert_eq!(
        s.execute_group_local(&transfer, Some(&o)).unwrap().status,
        LocalStatus::Rejected
    );
    drop(s);
    let s = f.store();
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(
        s.group_lookup_original(&scope, "run", "node", &o)
            .unwrap()
            .request_id,
        req
    );
    assert_eq!(o.budget().unwrap().held_micro_cny, held);
}
#[test]
fn wrong_conversation_cannot_be_linked_and_memory_capabilities_cannot_expand_grants() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let mut c = plan("bad-plan", 2, 1, "bad");
    if let GroupOperation::Plan { capabilities, .. } = &mut c.operation {
        capabilities.scopes.insert("secret".into());
    }
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::Rejected
    );
    apply(&s, &plan("plan", 2, 1, "node"));
    let o = owner(&f);
    let req = original(&o, "other-conversation");
    let bind = mutation(
        "bind",
        3,
        1,
        GroupOperation::BindOriginal {
            run_id: "run".into(),
            node_id: "node".into(),
            request_id: req,
        },
    );
    s.issue_group_local_grant_trusted(&bind).unwrap();
    assert_eq!(
        s.execute_group_local(&bind, Some(&o)).unwrap().status,
        LocalStatus::Rejected
    );
}
#[test]
fn stop_does_not_cancel_original_request_or_free_hold() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    apply(&s, &plan("plan", 2, 1, "node"));
    let o = owner(&f);
    let req = original(&o, "conversation");
    let bind = mutation(
        "bind",
        3,
        1,
        GroupOperation::BindOriginal {
            run_id: "run".into(),
            node_id: "node".into(),
            request_id: req.clone(),
        },
    );
    s.issue_group_local_grant_trusted(&bind).unwrap();
    s.execute_group_local(&bind, Some(&o)).unwrap();
    let held = o.budget().unwrap().held_micro_cny;
    apply(
        &s,
        &mutation(
            "stop",
            4,
            1,
            GroupOperation::Stop {
                run_id: "run".into(),
            },
        ),
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(
        s.group_next_pending(&scope, "run", &o).unwrap(),
        PendingAdvice::Stopped
    );
    assert_eq!(
        s.group_lookup_original(&scope, "run", "node", &o)
            .unwrap()
            .status,
        "unknown"
    );
    assert_eq!(o.budget().unwrap().held_micro_cny, held);
}
#[test]
fn grant_revocation_and_changed_payload_do_not_create_business_facts() {
    let f = Fixture::new();
    let s = f.init();
    let c = command("register", 0, registration());
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.revoke_grant_trusted(&c.authority.grant_id, &Revision::new(1))
        .unwrap();
    assert!(s.execute_group_local(&c, None).is_err());
    assert!(GroupScope::current(&s, "project", "group").is_err());
    let mut c = command("second", 0, registration());
    s.issue_group_local_grant_trusted(&c).unwrap();
    c.group_id = "changed".into();
    assert!(s.execute_group_local(&c, None).is_err());
}

#[test]
fn handoff_requires_original_owner_even_before_any_node_is_bound() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let c = mutation(
        "handoff-no-owner",
        2,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::Rejected
    );
}
#[test]
fn two_unsubmitted_nodes_can_be_invalidated_atomically_on_handoff() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    apply(&s, &plan("plan-a", 2, 1, "a"));
    apply(&s, &plan("plan-b", 3, 1, "b"));
    let o = owner(&f);
    let c = mutation(
        "handoff",
        4,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, Some(&o)).unwrap().status,
        LocalStatus::Committed
    );
    let rows = s
        .database()
        .query(
            "SELECT request_id,record FROM group_runtime_nodes ORDER BY node_id",
            &[],
        )
        .unwrap();
    assert!(rows.iter().all(|r| r[0].is_none()));
    assert!(rows
        .iter()
        .all(|r| r[1].as_ref().unwrap().contains("obsolete_epoch")));
}
#[test]
fn receipt_tail_failure_rolls_back_epoch_count_revision_grant_and_event() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let o = owner(&f);
    let c = mutation(
        "handoff-fault",
        2,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.database().exec("CREATE TRIGGER deny_group_receipt BEFORE UPDATE ON group_runtime_local_intents WHEN NEW.status='committed' BEGIN SELECT RAISE(ABORT,'synthetic tail failure'); END",&[]).unwrap();
    assert_eq!(
        s.execute_group_local(&c, Some(&o)).unwrap().status,
        LocalStatus::PendingOriginal
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    let r = s.group_run(&scope, "run").unwrap();
    assert_eq!((r.epoch, r.handoffs), (1, 0));
    assert_eq!(
        s.group_registration(&scope).unwrap().revision,
        Revision::new(2)
    );
    assert_eq!(
        s.database()
            .query(
                "SELECT active FROM business_grants WHERE grant_id='grant-handoff-fault'",
                &[]
            )
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
    assert!(s
        .database()
        .query(
            "SELECT * FROM group_runtime_events WHERE intent_id='handoff-fault'",
            &[]
        )
        .unwrap()
        .is_empty());
    drop(s);
    let s = f.store();
    assert_eq!(
        s.execute_group_local(&c, Some(&o)).unwrap().status,
        LocalStatus::PendingOriginal
    );
}
fn paper(s: &BusinessStore) {
    let h = s.begin_upload("project").unwrap();
    s.append_chunk(&h.upload_id, b"%PDF-1.7\nsynthetic-only\n%%EOF\n")
        .unwrap();
    let b = s.finish_blob(&h.upload_id, blobs::BlobKind::Pdf).unwrap();
    let mut c = CommandEnvelope {
        protocol_version: 1,
        business_version: 1,
        intent_id: "paper-create".into(),
        scope: Scope {
            workspace_id: "ws".into(),
            project_id: Some("project".into()),
        },
        expected_revision: Revision::new(0),
        authority: AuthorityBinding {
            grant_id: "paper-grant".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch".into(),
        },
        plan_id: "paper-plan".into(),
        plan_digest: "0".repeat(64),
        command: Operation::PaperCreate {
            paper_id: "paper".into(),
            payload: PaperPayload {
                title: "Synthetic evidence".into(),
                authors: vec![],
                year: None,
                doi: None,
                url: None,
                notes: None,
                attachment: b.blob,
                attachment_upload_id: Some(b.upload_id),
            },
        },
    };
    c.plan_digest = c.expected_plan_digest().unwrap();
    s.issue_grant_trusted(&c, None).unwrap();
    assert_eq!(s.execute(&c).unwrap().status, ExecutionStatus::Committed);
}
#[test]
fn observed_dissent_and_original_artifact_survive_unknown_resolution_and_restart() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    paper(&s);
    apply(&s, &plan("plan", 2, 1, "node"));
    let o = owner(&f);
    let req = original(&o, "conversation");
    let b = mutation(
        "bind",
        3,
        1,
        GroupOperation::BindOriginal {
            run_id: "run".into(),
            node_id: "node".into(),
            request_id: req.clone(),
        },
    );
    s.issue_group_local_grant_trusted(&b).unwrap();
    s.execute_group_local(&b, Some(&o)).unwrap();
    let e = StoredEvidence {
        claim_id: "claim".into(),
        source_id: "paper".into(),
        source_revision: Revision::new(1),
        stance: "contradicts".into(),
    };
    let c = mutation(
        "unknown-evidence",
        4,
        1,
        GroupOperation::Observe {
            run_id: "run".into(),
            node_id: "node".into(),
            evidence: vec![e.clone()],
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, Some(&o)).unwrap().status,
        LocalStatus::Committed
    );
    // Synthetic response goes directly to the existing original receipt owner;
    // this test never creates a network connection or claims provider execution.
    let response=json!({"id":"offline-fixture","model":agent::owner::MODEL,"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"Synthetic fixture output"}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string();
    o.settle_response(&req, &response).unwrap();
    let mut e = e;
    e.stance = "supports".into();
    let c = mutation(
        "resolved-evidence",
        5,
        1,
        GroupOperation::Observe {
            run_id: "run".into(),
            node_id: "node".into(),
            evidence: vec![e],
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, Some(&o)).unwrap().status,
        LocalStatus::Committed
    );
    drop(s);
    let s = f.store();
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    let r = s.group_run(&scope, "run").unwrap();
    assert_eq!(r.summary["claims"]["claim"]["disputed"], true);
    assert_eq!(r.summary["nodes"][0]["state"], "completed");
    assert_eq!(r.summary["nodes"][0]["request_id"], req);
    assert!(s
        .group_lookup_original(&scope, "run", "node", &o)
        .unwrap()
        .answer
        .is_some());
}
#[test]
fn stale_source_version_cannot_enter_persisted_summary() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    paper(&s);
    apply(&s, &plan("plan", 2, 1, "node"));
    let o = owner(&f);
    let req = original(&o, "conversation");
    let b = mutation(
        "bind",
        3,
        1,
        GroupOperation::BindOriginal {
            run_id: "run".into(),
            node_id: "node".into(),
            request_id: req,
        },
    );
    s.issue_group_local_grant_trusted(&b).unwrap();
    s.execute_group_local(&b, Some(&o)).unwrap();
    let c = mutation(
        "bad-source",
        4,
        1,
        GroupOperation::Observe {
            run_id: "run".into(),
            node_id: "node".into(),
            evidence: vec![StoredEvidence {
                claim_id: "claim".into(),
                source_id: "paper".into(),
                source_revision: Revision::new(2),
                stance: "supports".into(),
            }],
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, Some(&o)).unwrap().status,
        LocalStatus::Rejected
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(
        s.group_run(&scope, "run").unwrap().summary["claims"],
        json!({})
    );
}

#[test]
fn existing_original_can_be_registered_for_reconciliation_after_stop() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    apply(&s, &plan("plan", 2, 1, "node"));
    let o = owner(&f);
    let req = original(&o, "conversation");
    let held = o.budget().unwrap().held_micro_cny;
    apply(
        &s,
        &mutation(
            "stop",
            3,
            1,
            GroupOperation::Stop {
                run_id: "run".into(),
            },
        ),
    );
    let c = mutation(
        "late-binding",
        4,
        1,
        GroupOperation::BindOriginal {
            run_id: "run".into(),
            node_id: "node".into(),
            request_id: req.clone(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, Some(&o)).unwrap().status,
        LocalStatus::Committed
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert!(s.group_run(&scope, "run").unwrap().stopped);
    assert_eq!(
        s.group_lookup_original(&scope, "run", "node", &o)
            .unwrap()
            .request_id,
        req
    );
    assert_eq!(o.budget().unwrap().held_micro_cny, held);
    assert_eq!(
        s.group_next_pending(&scope, "run", &o).unwrap(),
        PendingAdvice::Stopped
    );
}

#[test]
fn handoff_narrowing_is_task_local_and_does_not_silently_change_group_defaults() {
    let f = Fixture::new();
    let s = f.init();
    let mut reg = registration();
    if let GroupOperation::Register { members, .. } = &mut reg {
        members
            .get_mut("b")
            .unwrap()
            .permissions
            .insert("write".into());
    }
    apply(&s, &command("register", 0, reg));
    apply(
        &s,
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
    let o = owner(&f);
    let c = mutation(
        "handoff",
        2,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.execute_group_local(&c, Some(&o)).unwrap();
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert!(s.group_registration(&scope).unwrap().members["b"]
        .permissions
        .contains("write"));
    let mut c = plan("narrowed-plan", 3, 2, "node");
    if let GroupOperation::Plan {
        member_id,
        capabilities,
        ..
    } = &mut c.operation
    {
        *member_id = "b".into();
        capabilities.permissions.insert("write".into());
    }
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::Rejected
    );
}

#[test]
fn a_new_run_id_cannot_reset_the_same_registered_root_lifetime() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let c = command(
        "same-root",
        2,
        GroupOperation::Start {
            run_id: "replacement-run".into(),
            root_task_id: "root".into(),
            leader: Some("a".into()),
            max_rounds: 8,
            max_handoffs: 2,
            deadline_ms: u64::MAX,
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::Rejected
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert!(s.group_run(&scope, "replacement-run").is_err());
}

// Parent review: SQL writes after the last authorization read are observable
// mutation boundaries, including the grant-consumption write itself.
fn authority_tail_fault(boundary: &str, mutation_sql: &str) {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let c = mutation(
        "tail-target",
        2,
        1,
        GroupOperation::Stop {
            run_id: "run".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    let db = s.database();
    let group_before = db
        .query("SELECT * FROM group_runtime_groups ORDER BY group_id", &[])
        .unwrap();
    let runs_before = db
        .query("SELECT * FROM group_runtime_runs ORDER BY run_id", &[])
        .unwrap();
    let nodes_before = db
        .query("SELECT * FROM group_runtime_nodes ORDER BY node_id", &[])
        .unwrap();
    let grants_before = db
        .query("SELECT * FROM business_grants ORDER BY grant_id", &[])
        .unwrap();
    let project_before = db.query("SELECT * FROM projects ORDER BY id", &[]).unwrap();
    let trigger=match boundary{
 "events"=>format!("CREATE TRIGGER inject_authority_tail AFTER INSERT ON group_runtime_events WHEN NEW.intent_id='tail-target' BEGIN {mutation_sql}; END"),
 "receipt"=>format!("CREATE TRIGGER inject_authority_tail AFTER UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='tail-target' AND NEW.status='committed' BEGIN {mutation_sql}; END"),
 "consume"=>format!("CREATE TRIGGER inject_authority_tail AFTER UPDATE OF active ON business_grants WHEN NEW.grant_id='grant-tail-target' AND OLD.active=1 AND NEW.active=0 BEGIN {mutation_sql}; END"),_=>panic!("unknown boundary")};
    db.exec(&trigger, &[]).unwrap();
    let r = s.execute_group_local(&c, None).unwrap();
    assert_ne!(
        r.status,
        LocalStatus::Committed,
        "{boundary} committed after: {mutation_sql}"
    );
    assert_eq!(
        db.query("SELECT * FROM group_runtime_groups ORDER BY group_id", &[])
            .unwrap(),
        group_before
    );
    assert_eq!(
        db.query("SELECT * FROM group_runtime_runs ORDER BY run_id", &[])
            .unwrap(),
        runs_before
    );
    assert_eq!(
        db.query("SELECT * FROM group_runtime_nodes ORDER BY node_id", &[])
            .unwrap(),
        nodes_before
    );
    assert_eq!(
        db.query("SELECT * FROM business_grants ORDER BY grant_id", &[])
            .unwrap(),
        grants_before
    );
    assert_eq!(
        db.query("SELECT * FROM projects ORDER BY id", &[]).unwrap(),
        project_before
    );
    assert!(db
        .query(
            "SELECT * FROM group_runtime_events WHERE intent_id='tail-target'",
            &[]
        )
        .unwrap()
        .is_empty());
    let row = db
        .query(
            "SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='tail-target'",
            &[],
        )
        .unwrap();
    assert_ne!(row[0][0].as_deref(), Some("committed"));
    if let Some(raw) = &row[0][1] {
        let receipt: LocalReceipt = serde_json::from_str(raw).unwrap();
        assert_eq!(receipt.status, LocalStatus::Rejected);
    }
    assert_ne!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::Committed
    );
}
macro_rules! tail_case {
    ($name:ident,$boundary:literal,$sql:literal) => {
        #[test]
        fn $name() {
            authority_tail_fault($boundary, $sql);
        }
    };
}
tail_case!(
    receipt_tail_expiry_revokes_local_commit,
    "receipt",
    "UPDATE business_grants SET expires_at_ms='0' WHERE grant_id='grant-tail-target'"
);
tail_case!(
    events_tail_expiry_revokes_local_commit,
    "events",
    "UPDATE business_grants SET expires_at_ms='0' WHERE grant_id='grant-tail-target'"
);
tail_case!(
    receipt_tail_revoke_is_not_mistaken_for_this_transaction_consumption,
    "receipt",
    "UPDATE business_grants SET active=0 WHERE grant_id='grant-tail-target'"
);
tail_case!(
    events_tail_revoke_is_not_mistaken_for_this_transaction_consumption,
    "events",
    "UPDATE business_grants SET active=0 WHERE grant_id='grant-tail-target'"
);
tail_case!(
    receipt_tail_epoch_change_revokes_local_commit,
    "receipt",
    "UPDATE business_grants SET owner_epoch='other-epoch' WHERE grant_id='grant-tail-target'"
);
tail_case!(
    events_tail_epoch_change_revokes_local_commit,
    "events",
    "UPDATE business_grants SET owner_epoch='other-epoch' WHERE grant_id='grant-tail-target'"
);
tail_case!(
    receipt_tail_generation_change_revokes_local_commit,
    "receipt",
    "UPDATE business_grants SET generation='2' WHERE grant_id='grant-tail-target'"
);
tail_case!(
    events_tail_generation_change_revokes_local_commit,
    "events",
    "UPDATE business_grants SET generation='2' WHERE grant_id='grant-tail-target'"
);
tail_case!(
    receipt_tail_project_delete_revokes_local_commit,
    "receipt",
    "UPDATE projects SET deleted=1 WHERE id='project'"
);
tail_case!(
    events_tail_project_delete_revokes_local_commit,
    "events",
    "UPDATE projects SET deleted=1 WHERE id='project'"
);
tail_case!(
    receipt_tail_group_scope_change_revokes_local_commit,
    "receipt",
    "UPDATE group_runtime_groups SET workspace='other-workspace' WHERE group_id='group'"
);
tail_case!(
    events_tail_group_scope_change_revokes_local_commit,
    "events",
    "UPDATE group_runtime_groups SET workspace='other-workspace' WHERE group_id='group'"
);
tail_case!(
    consume_tail_expiry_is_checked_after_this_transaction_consumption,
    "consume",
    "UPDATE business_grants SET expires_at_ms='0' WHERE grant_id='grant-tail-target'"
);
tail_case!(
    consume_tail_epoch_is_checked_after_this_transaction_consumption,
    "consume",
    "UPDATE business_grants SET owner_epoch='other-epoch' WHERE grant_id='grant-tail-target'"
);
tail_case!(
    consume_tail_generation_is_checked_after_this_transaction_consumption,
    "consume",
    "UPDATE business_grants SET generation='2' WHERE grant_id='grant-tail-target'"
);
tail_case!(
    consume_tail_project_is_checked_after_this_transaction_consumption,
    "consume",
    "UPDATE projects SET deleted=1 WHERE id='project'"
);
tail_case!(
    consume_tail_group_scope_is_checked_after_this_transaction_consumption,
    "consume",
    "UPDATE group_runtime_groups SET workspace='other-workspace' WHERE group_id='group'"
);
tail_case!(
    consume_tail_grant_readmission_is_checked,
    "consume",
    "UPDATE business_grants SET active=1 WHERE grant_id='grant-tail-target'"
);
tail_case!(consume_tail_admission_id_is_checked,"consume","UPDATE business_grants SET admission_id='foreign-admission' WHERE grant_id='grant-tail-target'");
tail_case!(receipt_tail_binding_change_is_checked,"receipt","UPDATE business_grants SET binding_digest='changed-binding' WHERE grant_id='grant-tail-target'");
#[test]
fn rejected_update_ignored_returns_original_pending_instead_of_fabricated_rejection() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let c = mutation(
        "reject-ignored",
        99,
        1,
        GroupOperation::Stop {
            run_id: "run".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.database().exec("CREATE TRIGGER ignore_rejection BEFORE UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='reject-ignored' AND NEW.status='rejected' BEGIN SELECT RAISE(IGNORE); END",&[]).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::PendingOriginal
    );
    let rows=s.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='reject-ignored'",&[]).unwrap();
    assert_eq!(rows[0], vec![Some("pending".into()), None]);
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::PendingOriginal
    );
}
#[test]
fn changed_pending_does_not_return_rejected_without_a_persisted_terminal_receipt() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let c = mutation(
        "reject-changed",
        99,
        1,
        GroupOperation::Stop {
            run_id: "run".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.database().exec("CREATE TRIGGER change_pending AFTER INSERT ON group_runtime_local_intents WHEN NEW.intent_id='reject-changed' BEGIN UPDATE group_runtime_local_intents SET status='committed' WHERE intent_id=NEW.intent_id; END",&[]).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::PendingOriginal
    );
    assert_eq!(
        s.database()
            .query(
                "SELECT receipt FROM group_runtime_local_intents WHERE intent_id='reject-changed'",
                &[]
            )
            .unwrap()[0][0],
        None
    );
}
#[test]
fn rejected_receipt_tail_tampering_returns_original_pending_instead_of_fabricated_rejection() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let c = mutation(
        "reject-tampered",
        99,
        1,
        GroupOperation::Stop {
            run_id: "run".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.database().exec("CREATE TRIGGER tamper_rejection AFTER UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='reject-tampered' AND NEW.status='rejected' BEGIN UPDATE group_runtime_local_intents SET receipt=NULL,status='pending' WHERE intent_id=NEW.intent_id; END",&[]).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::PendingOriginal
    );
}

#[test]
fn failed_request_chain_read_keeps_original_unknown_and_local_observation_pending() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    apply(&s, &plan("plan", 2, 1, "node"));
    let o = owner(&f);
    let req = original(&o, "conversation");
    let c = mutation(
        "bind",
        3,
        1,
        GroupOperation::BindOriginal {
            run_id: "run".into(),
            node_id: "node".into(),
            request_id: req.clone(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.execute_group_local(&c, Some(&o)).unwrap();
    let before = serde_json::to_value(o.lookup(&req).unwrap()).unwrap();
    let held = o.budget().unwrap().held_micro_cny;
    let raw = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    raw.exec(
        "ALTER TABLE tool_steps RENAME TO synthetic_unavailable_tool_steps",
        &[],
    )
    .unwrap();
    let c = mutation(
        "observe-read-fault",
        4,
        1,
        GroupOperation::Observe {
            run_id: "run".into(),
            node_id: "node".into(),
            evidence: vec![],
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, Some(&o)).unwrap().status,
        LocalStatus::PendingOriginal
    );
    assert_eq!(
        serde_json::to_value(o.lookup(&req).unwrap()).unwrap(),
        before
    );
    assert_eq!(o.budget().unwrap().held_micro_cny, held);
    assert_eq!(s.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='observe-read-fault'",&[]).unwrap()[0],vec![Some("pending".into()),None]);
}
#[test]
fn failed_request_chain_read_during_handoff_is_inconclusive_not_rejected() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    apply(&s, &plan("plan", 2, 1, "node"));
    let o = owner(&f);
    let req = original(&o, "conversation");
    let c = mutation(
        "bind",
        3,
        1,
        GroupOperation::BindOriginal {
            run_id: "run".into(),
            node_id: "node".into(),
            request_id: req.clone(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.execute_group_local(&c, Some(&o)).unwrap();
    let response=json!({"id":"offline-only","model":agent::owner::MODEL,"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"Synthetic output"}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string();
    o.settle_response(&req, &response).unwrap();
    let raw = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    raw.exec(
        "ALTER TABLE tool_steps RENAME TO synthetic_unavailable_tool_steps",
        &[],
    )
    .unwrap();
    let c = mutation(
        "handoff-read-fault",
        4,
        1,
        GroupOperation::Handoff {
            run_id: "run".into(),
            to: "b".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    assert_eq!(
        s.execute_group_local(&c, Some(&o)).unwrap().status,
        LocalStatus::PendingOriginal
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert_eq!(s.group_run(&scope, "run").unwrap().epoch, 1);
}
#[test]
fn register_tail_checks_the_newly_persisted_group_scope() {
    for boundary in ["receipt", "events"] {
        let f = Fixture::new();
        let s = f.init();
        let c = command("register-tail", 0, registration());
        s.issue_group_local_grant_trusted(&c).unwrap();
        let trigger = if boundary == "receipt" {
            "CREATE TRIGGER corrupt_registered_scope AFTER UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='register-tail' AND NEW.status='committed' BEGIN UPDATE group_runtime_groups SET workspace='other-workspace' WHERE group_id='group'; END"
        } else {
            "CREATE TRIGGER corrupt_registered_scope AFTER INSERT ON group_runtime_events WHEN NEW.intent_id='register-tail' BEGIN UPDATE group_runtime_groups SET workspace='other-workspace' WHERE group_id='group'; END"
        };
        s.database().exec(trigger, &[]).unwrap();
        assert_ne!(
            s.execute_group_local(&c, None).unwrap().status,
            LocalStatus::Committed
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
        assert_eq!(
            s.database()
                .query(
                    "SELECT active FROM business_grants WHERE grant_id='grant-register-tail'",
                    &[]
                )
                .unwrap()[0][0]
                .as_deref(),
            Some("1")
        );
    }
}
#[test]
fn rejected_write_sql_failure_is_pending_without_a_terminal_receipt() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let c = mutation(
        "reject-storage",
        99,
        1,
        GroupOperation::Stop {
            run_id: "run".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.database().exec("CREATE TRIGGER fail_rejection BEFORE UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='reject-storage' AND NEW.status='rejected' BEGIN SELECT RAISE(ABORT,'synthetic write failure'); END",&[]).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::PendingOriginal
    );
    assert_eq!(s.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='reject-storage'",&[]).unwrap()[0],vec![Some("pending".into()),None]);
}

#[test]
fn original_identity_storage_failure_is_pending_not_definitive_not_found() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    apply(&s, &plan("plan", 2, 1, "node"));
    let o = owner(&f);
    let req = original(&o, "conversation");
    let c = mutation(
        "bind",
        3,
        1,
        GroupOperation::BindOriginal {
            run_id: "run".into(),
            node_id: "node".into(),
            request_id: req.clone(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.execute_group_local(&c, Some(&o)).unwrap();
    let before = serde_json::to_value(o.lookup(&req).unwrap()).unwrap();
    let held = o.budget().unwrap().held_micro_cny;
    let raw = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    raw.exec(
        "ALTER TABLE requests RENAME TO synthetic_unavailable_requests",
        &[],
    )
    .unwrap();
    let c = mutation(
        "identity-read-fault",
        4,
        1,
        GroupOperation::Observe {
            run_id: "run".into(),
            node_id: "node".into(),
            evidence: vec![],
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    let result = s.execute_group_local(&c, Some(&o)).unwrap();
    raw.exec(
        "ALTER TABLE synthetic_unavailable_requests RENAME TO requests",
        &[],
    )
    .unwrap();
    assert_eq!(result.status, LocalStatus::PendingOriginal);
    assert_eq!(
        serde_json::to_value(o.lookup(&req).unwrap()).unwrap(),
        before
    );
    assert_eq!(o.budget().unwrap().held_micro_cny, held);
    assert_eq!(s.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='identity-read-fault'",&[]).unwrap()[0],vec![Some("pending".into()),None]);
}
#[test]
fn rejected_commit_failure_is_pending_without_committing_rejected_receipt() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let c = mutation(
        "reject-commit-fault",
        99,
        1,
        GroupOperation::Stop {
            run_id: "run".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.database().exec("CREATE TABLE synthetic_commit_fault(project TEXT REFERENCES projects(id) DEFERRABLE INITIALLY DEFERRED)",&[]).unwrap();
    s.database().exec("CREATE TRIGGER fail_rejection_commit AFTER UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='reject-commit-fault' AND NEW.status='rejected' BEGIN INSERT INTO synthetic_commit_fault VALUES('missing-project'); END",&[]).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::PendingOriginal
    );
    assert_eq!(s.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='reject-commit-fault'",&[]).unwrap()[0],vec![Some("pending".into()),None]);
    assert!(s
        .database()
        .query("SELECT * FROM synthetic_commit_fault", &[])
        .unwrap()
        .is_empty());
}
#[test]
fn business_commit_failure_rolls_back_receipt_event_stop_and_grant() {
    let f = Fixture::new();
    let s = f.init();
    start(&s);
    let c = mutation(
        "commit-fault",
        2,
        1,
        GroupOperation::Stop {
            run_id: "run".into(),
        },
    );
    s.issue_group_local_grant_trusted(&c).unwrap();
    s.database().exec("CREATE TABLE synthetic_commit_fault(project TEXT REFERENCES projects(id) DEFERRABLE INITIALLY DEFERRED)",&[]).unwrap();
    s.database().exec("CREATE TRIGGER fail_business_commit AFTER UPDATE ON group_runtime_local_intents WHEN NEW.intent_id='commit-fault' AND NEW.status='committed' BEGIN INSERT INTO synthetic_commit_fault VALUES('missing-project'); END",&[]).unwrap();
    assert_eq!(
        s.execute_group_local(&c, None).unwrap().status,
        LocalStatus::PendingOriginal
    );
    let scope = GroupScope::current(&s, "project", "group").unwrap();
    assert!(!s.group_run(&scope, "run").unwrap().stopped);
    assert_eq!(
        s.group_registration(&scope).unwrap().revision,
        Revision::new(2)
    );
    assert_eq!(s.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='commit-fault'",&[]).unwrap()[0],vec![Some("pending".into()),None]);
    assert_eq!(
        s.database()
            .query(
                "SELECT active FROM business_grants WHERE grant_id='grant-commit-fault'",
                &[]
            )
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
    assert!(s
        .database()
        .query(
            "SELECT * FROM group_runtime_events WHERE intent_id='commit-fault'",
            &[]
        )
        .unwrap()
        .is_empty());
}
