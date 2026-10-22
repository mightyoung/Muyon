use super::*;
#[test]
fn ordinary_origin_is_persisted_at_prepare_and_missing_origin_never_means_direct() {
    let f = Fixture::new();
    let o = owner(&f);
    let p = o
        .prepare_chat("ordinary", "Synthetic direct", Some(&Proof))
        .unwrap();
    let v = serde_json::to_value(o.request_origin(&p.request_id).unwrap()).unwrap();
    assert_eq!(v["classification"], "direct");
    assert_eq!(v["root_request_id"], p.request_id);
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    db.exec(
        "DELETE FROM request_origins WHERE request_id=?",
        &[&p.request_id],
    )
    .unwrap();
    assert!(o.request_origin(&p.request_id).is_err());
}
#[test]
fn prepare_origin_tail_fault_rolls_back_request_and_origin() {
    let f = Fixture::new();
    let o = owner(&f);
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    db.exec("CREATE TRIGGER damage_origin AFTER INSERT ON request_origins BEGIN DELETE FROM requests WHERE id=NEW.request_id; END",&[]).unwrap();
    assert!(o
        .prepare_chat("ordinary", "Synthetic", Some(&Proof))
        .is_err());
    assert!(db.query("SELECT * FROM requests", &[]).unwrap().is_empty());
    assert!(db
        .query("SELECT * FROM request_origins", &[])
        .unwrap()
        .is_empty());
}
#[test]
fn group_prepare_records_real_group_root_child_before_canonical_mapping_exists() {
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
    let v = serde_json::to_value(o.request_origin(&p.request_id).unwrap()).unwrap();
    assert_eq!(v["classification"], "group");
    assert_eq!(v["group"]["root_task_id"], root);
    assert_eq!(v["group"]["workflow_run_id"], child);
    let gate = serde_json::to_value(s.group_request_gate(&p.request_id, &o, &l)).unwrap();
    assert_eq!(gate["group_hold"], true);
    assert_eq!(gate["execution_authority"], false);
    assert_eq!(gate["reason"], "canonical_mapping_unavailable");
    assert!(o
        .prepare_chat(
            &p.conversation_id,
            "Generic route cannot downgrade group",
            Some(&Proof)
        )
        .is_err());
}
#[test]
fn ordinary_prepare_in_actual_group_child_cannot_bypass_request_only_gate() {
    let f = CanonicalFixture::new(); // Actual older ordinary prepare, actual group root/child.
    let gate = serde_json::to_value(f.store.group_request_gate(
        &f.plan.request_id,
        &f.owner,
        &f.ledger,
    ))
    .unwrap();
    assert_eq!(gate["group_hold"], true);
    assert_eq!(gate["execution_authority"], false);
}
fn prepared_group() -> (
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
fn approve_actual_tool(
    s: &BusinessStore,
    o: &agent::owner::AgentOwner,
    p: &agent::owner::AgentPlan,
) -> agent::tools::ToolsContext {
    approve_actual_tool_with_ref(s, o, p, &format!("call_{}", p.request_id))
}
fn approve_actual_tool_with_ref(
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
fn map_actual(
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
#[test]
fn durable_followup_inherits_group_origin_and_request_only_gate_finds_first_original_mapping() {
    let (f, s, o, mut l, scope, p, child) = prepared_group();
    map_actual(&s, &o, &mut l, &scope, &p, &child);
    let ctx = approve_actual_tool(&s, &o, &p);
    let next = o
        .prepare_tool_followup_trusted(&s, &ctx, &p.request_id, Some(&Proof))
        .unwrap();
    let v = serde_json::to_value(o.request_origin(&next.request_id).unwrap()).unwrap();
    assert_eq!(v["classification"], "group");
    assert_eq!(v["root_request_id"], p.request_id);
    assert_eq!(v["parent_request_id"], p.request_id);
    let gate = serde_json::to_value(s.group_request_gate(&next.request_id, &o, &l)).unwrap();
    assert_eq!(gate["group_hold"], true);
    assert_eq!(gate["reason"], "cross_owner_consumption_unclosed");
    assert_eq!(gate["canonical"]["request_id"], p.request_id);
    let held = o.budget().unwrap().held_micro_cny;
    let next_id = next.request_id.clone();
    drop(o);
    let o = agent::owner::AgentOwner::open(&f.0.join("agent.sqlite"), "ws", "epoch-new").unwrap();
    assert!(o.request_origin(&next_id).unwrap().is_group());
    assert!(s.group_request_gate(&next_id, &o, &l).group_hold());
    assert_eq!(o.budget().unwrap().held_micro_cny, held);
}
#[test]
fn followup_tail_fault_rolls_back_new_identity_link_and_preserves_parent_origin() {
    for change in [
        "UPDATE request_origins SET record='{}' WHERE request_id=NEW.followup",
        "DELETE FROM request_origins WHERE request_id=NEW.request_id",
        "UPDATE tool_steps SET followup=NULL WHERE request_id=NEW.request_id",
    ] {
        let (f, s, o, _l, _scope, p, _child) = prepared_group();
        let ctx = approve_actual_tool(&s, &o, &p);
        let db =
            sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
        let requests = db.query("SELECT * FROM requests ORDER BY id", &[]).unwrap();
        let origins = db
            .query("SELECT * FROM request_origins ORDER BY request_id", &[])
            .unwrap();
        let steps = db.query("SELECT * FROM tool_steps", &[]).unwrap();
        let budget = o.budget().unwrap();
        db.exec(&format!("CREATE TRIGGER damage_followup AFTER UPDATE OF followup ON tool_steps WHEN NEW.followup IS NOT NULL BEGIN {change}; END"),&[]).unwrap();
        assert!(o
            .prepare_tool_followup_trusted(&s, &ctx, &p.request_id, Some(&Proof))
            .is_err());
        assert_eq!(
            db.query("SELECT * FROM requests ORDER BY id", &[]).unwrap(),
            requests
        );
        assert_eq!(
            db.query("SELECT * FROM request_origins ORDER BY request_id", &[])
                .unwrap(),
            origins
        );
        assert_eq!(db.query("SELECT * FROM tool_steps", &[]).unwrap(), steps);
        assert_eq!(o.budget().unwrap().held_micro_cny, budget.held_micro_cny);
        assert_eq!(o.lookup(&p.request_id).unwrap().status, "tool_pending");
    }
}
#[test]
fn direct_and_non_group_workflow_controls_remain_non_group_observations_without_permit() {
    let f = Fixture::new();
    let s = f.init();
    let o = owner(&f);
    let mut l =
        agent::workflow::RunLedger::open(&f.0.join("workflow.sqlite"), "ws", "epoch").unwrap();
    let p = o
        .prepare_chat("ordinary", "Synthetic direct", Some(&Proof))
        .unwrap();
    let gate = serde_json::to_value(s.group_request_gate(&p.request_id, &o, &l)).unwrap();
    assert_eq!(gate["group_hold"], false);
    assert_eq!(gate["execution_authority"], false);
    let scope = agent::workflow::RunScope::current(&s, "session", "nongroup-root", Some("project"))
        .unwrap();
    let root = l
        .execute(
            &json!({"action":"create_root","title":"Synthetic nongroup","task":"Offline"})
                .to_string(),
            &s,
            &scope,
        )
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();
    let child=l.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
    let context = l.remote_context(&scope, &child).unwrap();
    let p = o
        .prepare_chat(
            context["conversation_id"].as_str().unwrap(),
            "Synthetic nongroup child",
            Some(&Proof),
        )
        .unwrap();
    l.bind_remote_plan(&scope, &child, &p).unwrap();
    let gate = serde_json::to_value(s.group_request_gate(&p.request_id, &o, &l)).unwrap();
    assert_eq!(gate["group_hold"], false);
    assert_eq!(gate["workflow"]["child_id"], child);
    assert_eq!(gate["execution_authority"], false);
}
#[test]
fn legacy_v3_migration_preserves_original_bytes_and_unknown_hold_without_guessing_direct() {
    let f = Fixture::new();
    let o = owner(&f);
    let p = o.prepare_chat("legacy", "Synthetic", Some(&Proof)).unwrap();
    let cfg = o.configuration().unwrap();
    o.confirm_trusted(&p.request_id, &cfg.id).unwrap();
    let _unsent = o
        .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
        .unwrap();
    let hold = o.budget().unwrap().held_micro_cny;
    drop(o);
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    db.exec("DROP TABLE request_origins", &[]).unwrap();
    db.exec("UPDATE meta SET version='3'", &[]).unwrap();
    let original = db.query("SELECT * FROM requests", &[]).unwrap();
    let o = agent::owner::AgentOwner::open(&f.0.join("agent.sqlite"), "ws", "epoch-new").unwrap();
    let origin = serde_json::to_value(o.request_origin(&p.request_id).unwrap()).unwrap();
    assert_eq!(origin["classification"], "legacy_unknown");
    assert!(origin["root_request_id"].is_null());
    assert_eq!(db.query("SELECT * FROM requests", &[]).unwrap(), original);
    assert_eq!(o.lookup(&p.request_id).unwrap().status, "unknown");
    assert_eq!(o.budget().unwrap().held_micro_cny, hold);
}
#[test]
fn legacy_origin_migration_trigger_faults_rollback_whole_upgrade() {
    for change in [
        "DELETE FROM requests",
        "UPDATE requests SET digest='broken'",
        "INSERT INTO request_origins VALUES('injected','{}')",
        "DELETE FROM tool_steps",
        "DELETE FROM configuration",
    ] {
        let f = Fixture::new();
        let s = f.init();
        let o = owner(&f);
        let p = o.prepare_chat("legacy", "Synthetic", Some(&Proof)).unwrap();
        let _ctx = approve_actual_tool(&s, &o, &p);
        drop(o);
        let db =
            sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
        db.exec("DROP TABLE request_origins", &[]).unwrap();
        db.exec("UPDATE meta SET version='3'", &[]).unwrap();
        let requests = db.query("SELECT * FROM requests", &[]).unwrap();
        let tools = db.query("SELECT * FROM tool_steps", &[]).unwrap();
        let config = db.query("SELECT * FROM configuration", &[]).unwrap();
        db.exec(&format!("CREATE TRIGGER damage_origin_migration AFTER UPDATE OF version ON meta WHEN NEW.version='4' BEGIN {change}; END"),&[]).unwrap();
        assert!(
            agent::owner::AgentOwner::open(&f.0.join("agent.sqlite"), "ws", "epoch").is_err(),
            "{change}"
        );
        assert_eq!(db.query("SELECT * FROM requests", &[]).unwrap(), requests);
        assert_eq!(db.query("SELECT * FROM tool_steps", &[]).unwrap(), tools);
        assert_eq!(
            db.query("SELECT * FROM configuration", &[]).unwrap(),
            config
        );
        assert_eq!(
            db.query("SELECT version FROM meta", &[]).unwrap()[0][0].as_deref(),
            Some("3")
        );
        assert!(db
            .query(
                "SELECT name FROM sqlite_master WHERE name='request_origins'",
                &[]
            )
            .unwrap()
            .is_empty());
    }
}

#[test]
fn origin_gate_cannot_drop_a_bound_child_after_conversation_damage() {
    let f = CanonicalFixture::new();
    assert!(f
        .store
        .group_request_gate(&f.plan.request_id, &f.owner, &f.ledger)
        .group_hold());
    let db = sqlite::Db::open(
        f.files.0.join("workflow.sqlite").to_str().unwrap(),
        false,
        false,
    )
    .unwrap();
    db.exec("UPDATE runs SET record=json_set(record,'$.conversation_id','damaged-child-conversation') WHERE id=?",&[&f.child]).unwrap();
    let gate = f
        .store
        .group_request_gate(&f.plan.request_id, &f.owner, &f.ledger);
    println!(
        "DAMAGED_CONVERSATION_GATE={}",
        serde_json::to_value(&gate).unwrap()
    );
    assert!(gate.group_hold(),"actual persisted request reference still belongs to the group child; conversation damage must not erase reverse attribution and create Direct");
}
#[test]
fn origin_gate_cannot_downgrade_when_actual_group_run_row_is_missing() {
    let f = Fixture::new();
    let s = f.init();
    let (mut l, scope, root) = actual_workflow(&f, &s);
    let o = owner(&f);
    let child=l.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
    let context = l.remote_context(&scope, &child).unwrap();
    let p = o
        .prepare_chat(
            context["conversation_id"].as_str().unwrap(),
            "Synthetic existing group",
            Some(&Proof),
        )
        .unwrap();
    l.bind_remote_plan(&scope, &child, &p).unwrap();
    assert!(s.group_request_gate(&p.request_id, &o, &l).group_hold());
    s.database()
        .exec("DELETE FROM group_runtime_runs WHERE run_id='run'", &[])
        .unwrap();
    let gate = s.group_request_gate(&p.request_id, &o, &l);
    println!(
        "MISSING_ACTUAL_GROUP_RUN_GATE={}",
        serde_json::to_value(&gate).unwrap()
    );
    assert!(gate.group_hold(),"actual group registration and committed Start provenance remain; missing group run cannot prove nongroup");
}
#[test]
fn followup_first_insert_cannot_change_parent_charge_before_source_witness_capture() {
    let (f, s, o, _l, _scope, p, _child) = prepared_group();
    let ctx = approve_actual_tool(&s, &o, &p);
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    let before = db.query("SELECT * FROM requests ORDER BY id", &[]).unwrap();
    let budget = o.budget().unwrap();
    db.exec(&format!("CREATE TRIGGER corrupt_parent_before_origin AFTER INSERT ON requests BEGIN UPDATE requests SET charged=charged+1 WHERE id='{}'; END",p.request_id),&[]).unwrap();
    assert!(o
        .prepare_tool_followup_trusted(&s, &ctx, &p.request_id, Some(&Proof))
        .is_err());
    assert_eq!(
        db.query("SELECT * FROM requests ORDER BY id", &[]).unwrap(),
        before
    );
    assert_eq!(
        o.budget().unwrap().charged_micro_cny,
        budget.charged_micro_cny
    );
}
#[test]
fn canonical_mapping_evidence_survives_missing_workflow_child_for_direct_entry() {
    let f = CanonicalFixture::new();
    assert_eq!(f.bind().status, LocalStatus::Committed);
    let db = sqlite::Db::open(
        f.files.0.join("workflow.sqlite").to_str().unwrap(),
        false,
        false,
    )
    .unwrap();
    db.exec("DELETE FROM runs WHERE id=?", &[&f.child]).unwrap();
    assert!(f
        .store
        .group_request_gate(&f.plan.request_id, &f.owner, &f.ledger)
        .group_hold());
}
#[test]
fn pending_canonical_evidence_survives_missing_workflow_child_for_direct_entry() {
    let f = CanonicalFixture::new();
    f.store.database().exec("CREATE TRIGGER break_pending_for_gate AFTER INSERT ON group_request_bindings BEGIN UPDATE group_request_bindings SET record='{}'; END",&[]).unwrap();
    assert_eq!(f.bind().status, LocalStatus::PendingOriginal);
    let db = sqlite::Db::open(
        f.files.0.join("workflow.sqlite").to_str().unwrap(),
        false,
        false,
    )
    .unwrap();
    db.exec("DELETE FROM runs WHERE id=?", &[&f.child]).unwrap();
    assert!(f
        .store
        .group_request_gate(&f.plan.request_id, &f.owner, &f.ledger)
        .group_hold());
}

#[test]
fn origin_gate_holds_actual_legacy_bind_original_without_a_workflow_child() {
    let f = Fixture::new();
    let s = f.init();
    let (l, _scope, _root) = actual_workflow(&f, &s);
    let o = owner(&f);
    let plan = o
        .prepare_chat("conversation", "Synthetic root original", Some(&Proof))
        .unwrap();
    let cap = Capabilities {
        scopes: BTreeSet::from(["project".into()]),
        permissions: BTreeSet::from(["read".into()]),
    };
    assert_eq!(
        apply(
            &s,
            &mutation(
                "legacy-root-node",
                2,
                1,
                GroupOperation::Plan {
                    run_id: "run".into(),
                    node_id: "root-node".into(),
                    member_id: "a".into(),
                    dependencies: BTreeSet::new(),
                    capabilities: cap,
                    payload_digest: plan.payload_digest.clone()
                }
            )
        )
        .status,
        LocalStatus::Committed
    );
    let bind = mutation(
        "legacy-root-bind",
        3,
        1,
        GroupOperation::BindOriginal {
            run_id: "run".into(),
            node_id: "root-node".into(),
            request_id: plan.request_id.clone(),
        },
    );
    s.issue_group_local_grant_trusted(&bind).unwrap();
    assert_eq!(
        s.execute_group_local(&bind, Some(&o)).unwrap().status,
        LocalStatus::Committed
    );
    let gate = s.group_request_gate(&plan.request_id, &o, &l);
    println!(
        "ACTUAL_LEGACY_BIND_ORIGINAL_GATE={}",
        serde_json::to_value(&gate).unwrap()
    );
    assert!(gate.group_hold(),"actual committed Group BindOriginal is group evidence even when no remote workflow child or canonical mapping exists");
}
#[test]
fn second_followup_encoder_refusal_for_duplicate_call_ref_preserves_group_chain_and_hold() {
    let (f, s, o, mut l, scope, p, child) = prepared_group();
    map_actual(&s, &o, &mut l, &scope, &p, &child);
    let ctx = approve_actual_tool(&s, &o, &p);
    let next = o
        .prepare_tool_followup_trusted(&s, &ctx, &p.request_id, Some(&Proof))
        .unwrap();
    let ctx = approve_actual_tool_with_ref(&s, &o, &next, &format!("call_{}", p.request_id));
    let before = o
        .request_chain(&p.request_id)
        .unwrap()
        .iter()
        .map(|v| v.request_id.clone())
        .collect::<Vec<_>>();
    let result = o.prepare_tool_followup_trusted(&s, &ctx, &next.request_id, Some(&Proof));
    assert!(
        matches!(result, Err("tool_history_invalid")),
        "existing encoder refusal must not be bypassed"
    );
    assert_eq!(
        o.request_chain(&p.request_id)
            .unwrap()
            .iter()
            .map(|v| v.request_id.clone())
            .collect::<Vec<_>>(),
        before
    );
    let last = next;
    assert_eq!(
        o.request_origin(&last.request_id)
            .unwrap()
            .root_request_id(),
        Some(p.request_id.as_str())
    );
    let gate = serde_json::to_value(s.group_request_gate(&last.request_id, &o, &l)).unwrap();
    assert_eq!(gate["canonical"]["request_id"], p.request_id);
    assert_eq!(gate["group_hold"], true);
    assert_eq!(gate["execution_authority"], false);
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    db.exec(
        "DELETE FROM request_origins WHERE request_id=?",
        &[&p.request_id],
    )
    .unwrap();
    assert!(o.request_origin(&last.request_id).is_err());
    assert!(s.group_request_gate(&last.request_id, &o, &l).group_hold());
}
#[test]
fn ordinary_followup_stays_direct_non_group_and_keeps_existing_confirmation_semantics() {
    let f = Fixture::new();
    let s = f.init();
    let o = owner(&f);
    let l = agent::workflow::RunLedger::open(&f.0.join("workflow.sqlite"), "ws", "epoch").unwrap();
    let p = o
        .prepare_chat("ordinary", "Synthetic ordinary", Some(&Proof))
        .unwrap();
    let ctx = approve_actual_tool(&s, &o, &p);
    let next = o
        .prepare_tool_followup_trusted(&s, &ctx, &p.request_id, Some(&Proof))
        .unwrap();
    assert!(o.request_origin(&next.request_id).unwrap().is_direct());
    assert!(!s.group_request_gate(&next.request_id, &o, &l).group_hold());
    let cfg = o.configuration().unwrap();
    assert_eq!(
        o.confirm_trusted(&next.request_id, &cfg.id).unwrap().status,
        "reserved"
    );
}
#[test]
fn registered_group_sources_never_downgrade_under_missing_or_corrupt_mapping_and_source_tables() {
    for fault in [
        "DELETE FROM group_request_bindings",
        "UPDATE group_request_bindings SET record='{}'",
        "ALTER TABLE group_runtime_schema RENAME TO unavailable_group_schema",
        "ALTER TABLE request_origins RENAME TO unavailable_origins",
        "ALTER TABLE runs RENAME TO unavailable_runs",
    ] {
        let (f, s, o, mut l, scope, p, child) = prepared_group();
        map_actual(&s, &o, &mut l, &scope, &p, &child);
        let cfg = o.configuration().unwrap();
        o.confirm_trusted(&p.request_id, &cfg.id).unwrap();
        let _unsent = o
            .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
            .unwrap();
        let budget = o.budget().unwrap();
        if fault.contains("request_origins") {
            sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false)
                .unwrap()
                .exec(fault, &[])
                .unwrap();
        } else if fault.contains("TABLE runs") {
            sqlite::Db::open(f.0.join("workflow.sqlite").to_str().unwrap(), false, false)
                .unwrap()
                .exec(fault, &[])
                .unwrap();
        } else {
            s.database().exec(fault, &[]).unwrap();
        }
        let requests =
            sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
        let before = requests
            .query("SELECT * FROM requests ORDER BY id", &[])
            .unwrap();
        let gate = serde_json::to_value(s.group_request_gate(&p.request_id, &o, &l)).unwrap();
        assert_eq!(gate["group_hold"], true, "{fault}");
        assert_eq!(gate["execution_authority"], false);
        assert_eq!(gate["cross_owner_atomic"], false);
        assert_eq!(
            requests
                .query("SELECT * FROM requests ORDER BY id", &[])
                .unwrap(),
            before
        );
        assert_eq!(o.budget().unwrap().held_micro_cny, budget.held_micro_cny);
        assert_eq!(o.lookup(&p.request_id).unwrap().status, "unknown");
    }
}
#[test]
fn isolated_owned_namespace_remnants_are_inconclusive_not_never_initialized() {
    for keep in [
        "group_runtime_nodes",
        "group_runtime_events",
        "group_request_binding_schema",
    ] {
        let f = Fixture::new();
        let s = f.init();
        s.initialize_group_request_bindings().unwrap();
        let o = owner(&f);
        let l =
            agent::workflow::RunLedger::open(&f.0.join("workflow.sqlite"), "ws", "epoch").unwrap();
        let p = o
            .prepare_chat("ordinary", "Synthetic", Some(&Proof))
            .unwrap();
        for name in [
            "group_request_bindings",
            "group_runtime_intent_bindings",
            "group_runtime_nodes",
            "group_runtime_runs",
            "group_runtime_groups",
            "group_runtime_events",
            "group_runtime_local_intents",
            "group_runtime_schema",
            "group_request_binding_schema",
        ] {
            if name != keep {
                s.database()
                    .exec(&format!("DROP TABLE {name}"), &[])
                    .unwrap();
            }
        }
        assert!(
            s.group_request_gate(&p.request_id, &o, &l).group_hold(),
            "{keep}"
        );
    }
}

#[test]
fn second_legal_followup_preserves_group_origin_and_original_mapping() {
    let (f, s, o, mut l, scope, p, child) = prepared_group();
    map_actual(&s, &o, &mut l, &scope, &p, &child);
    let ctx = approve_actual_tool(&s, &o, &p);
    let next = o
        .prepare_tool_followup_trusted(&s, &ctx, &p.request_id, Some(&Proof))
        .unwrap();
    let ctx = approve_actual_tool(&s, &o, &next);
    let last = o
        .prepare_tool_followup_trusted(&s, &ctx, &next.request_id, Some(&Proof))
        .unwrap();
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    let previous: serde_json::Value = serde_json::from_str(
        db.query(
            "SELECT payload FROM requests WHERE id=?",
            &[&next.request_id],
        )
        .unwrap()[0][0]
            .as_deref()
            .unwrap(),
    )
    .unwrap();
    let final_payload: serde_json::Value = serde_json::from_str(
        db.query(
            "SELECT payload FROM requests WHERE id=?",
            &[&last.request_id],
        )
        .unwrap()[0][0]
            .as_deref()
            .unwrap(),
    )
    .unwrap();
    assert_eq!(previous["messages"].as_array().unwrap().len(), 3);
    assert_eq!(final_payload["messages"].as_array().unwrap().len(), 5);
    assert_eq!(
        &final_payload["messages"].as_array().unwrap()[..3],
        previous["messages"].as_array().unwrap().as_slice()
    );
    assert_eq!(final_payload["tools"], previous["tools"]);
    assert_eq!(
        final_payload["messages"][3]["tool_calls"][0]["function"]["name"],
        "product_supplier_list"
    );
    let original = serde_json::to_value(o.request_origin(&p.request_id).unwrap()).unwrap();
    let inherited = serde_json::to_value(o.request_origin(&last.request_id).unwrap()).unwrap();
    assert_eq!(inherited["parent_request_id"], next.request_id);
    assert_eq!(inherited["classification"], "group");
    assert_eq!(inherited["group"], original["group"]);
    assert_eq!(o.request_chain(&p.request_id).unwrap().len(), 3);
    assert_eq!(o.lookup(&last.request_id).unwrap().status, "prepared");
    assert_eq!(
        o.request_origin(&last.request_id)
            .unwrap()
            .root_request_id(),
        Some(p.request_id.as_str())
    );
    let gate = serde_json::to_value(s.group_request_gate(&last.request_id, &o, &l)).unwrap();
    assert_eq!(gate["canonical"]["request_id"], p.request_id);
    assert_eq!(gate["group_hold"], true);
    assert_eq!(gate["execution_authority"], false);
    assert_eq!(gate["execution_authority"], false);
    assert_eq!(gate["cross_owner_atomic"], false);
    let g = GroupScope::current(&s, "project", "group").unwrap();
    let check = serde_json::to_value(
        s.group_recheck_request_binding(&g, "run", "node", &o, &l, &scope)
            .unwrap(),
    )
    .unwrap();
    assert_eq!(check["observations"].as_array().unwrap().len(), 3);
    assert_eq!(check["recovery_state"], "query_original");
    assert_eq!(check["execution_authority"], false);
    assert_eq!(
        s.group_lookup_original(&g, "run", "node", &o)
            .unwrap()
            .request_id,
        last.request_id
    );
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    db.exec(
        "DELETE FROM request_origins WHERE request_id=?",
        &[&p.request_id],
    )
    .unwrap();
    assert!(o.request_origin(&last.request_id).is_err());
    assert!(s.group_request_gate(&last.request_id, &o, &l).group_hold());
}

#[test]
fn actual_second_followup_encoder_boundary_identifies_wire_logical_history_mismatch() {
    use muyon_core_agent_lab::{
        model::ModelRequest, wire_json, wire_provider::encode_registered_request,
    };
    let (f, s, o, mut l, scope, p, child) = prepared_group();
    map_actual(&s, &o, &mut l, &scope, &p, &child);
    let ctx = approve_actual_tool(&s, &o, &p);
    let next = o
        .prepare_tool_followup_trusted(&s, &ctx, &p.request_id, Some(&Proof))
        .unwrap();
    let _ctx = approve_actual_tool(&s, &o, &next);
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    let raw = db
        .query(
            "SELECT payload FROM requests WHERE id=?",
            &[&next.request_id],
        )
        .unwrap()[0][0]
        .clone()
        .unwrap();
    let mut body: serde_json::Value = serde_json::from_str(&raw).unwrap();
    let review = db
        .query(
            "SELECT review FROM tool_steps WHERE request_id=?",
            &[&next.request_id],
        )
        .unwrap()[0][0]
        .clone()
        .unwrap();
    let observed = o.lookup(&next.request_id).unwrap();
    let call: agent::tools::ToolCall =
        serde_json::from_value(observed.answer.unwrap()["call"].clone()).unwrap();
    println!(
        "ACTUAL_STORED_HISTORY_NAME={} NEW_ACTUAL_CALL_NAME={}",
        body["messages"][1]["tool_calls"][0]["function"]["name"], call.name
    );
    body["messages"].as_array_mut().unwrap().push(json!({"role":"assistant","content":null,"tool_calls":[{"id":call.call_ref,"type":"function","function":{"name":call.name,"arguments":call.arguments.to_string()}}]}));
    body["messages"]
        .as_array_mut()
        .unwrap()
        .push(json!({"role":"tool","tool_call_id":call.call_ref,"content":review}));
    let defs = agent::tools::definitions()
        .unwrap()
        .into_iter()
        .filter(|d| {
            body["tools"]
                .as_array()
                .unwrap()
                .iter()
                .any(|t| t["function"]["name"] == d.wire_name)
        })
        .collect::<Vec<_>>();
    let request = ModelRequest {
        task: "product".into(),
        attempt: next.request_id.clone(),
        turn: 1,
        messages: vec![],
        tools: defs.iter().map(|d| d.name.clone()).collect(),
    };
    let raw_history = wire_json::parse(body["messages"].to_string().as_bytes()).unwrap();
    assert_eq!(
        encode_registered_request(&request, &raw_history, &defs, agent::owner::MODEL).unwrap_err(),
        "wire_history_call"
    );
    let expected_wire_history = body["messages"].clone();
    // Probe only: invert exact registered wire names in memory, leaving ALL
    // ids/pairing/arguments/content untouched. The production encoder is unchanged.
    for row in body["messages"].as_array_mut().unwrap() {
        if let Some(calls) = row
            .get_mut("tool_calls")
            .and_then(serde_json::Value::as_array_mut)
        {
            for c in calls {
                if let Some(d) = defs.iter().find(|d| c["function"]["name"] == d.wire_name) {
                    c["function"]["name"] = json!(d.name);
                }
            }
        }
    }
    let history = wire_json::parse(body["messages"].to_string().as_bytes()).unwrap();
    let result = encode_registered_request(&request, &history, &defs, agent::owner::MODEL).unwrap();
    let encoded: serde_json::Value = serde_json::from_slice(&result).unwrap();
    let mut expected = expected_wire_history;
    expected.as_array_mut().unwrap()[3]["tool_calls"][0]["function"]["name"] =
        json!("product_supplier_list");
    assert_eq!(encoded["messages"], expected);
    println!("ONE_VARIABLE_INVERSE_MAPPING_PROBE=PASS; no request persisted or bytes sent");
}

#[test]
fn kind_damage_cannot_erase_actual_group_request_references() {
    let f = CanonicalFixture::new();
    let db = sqlite::Db::open(
        f.files.0.join("workflow.sqlite").to_str().unwrap(),
        false,
        false,
    )
    .unwrap();
    db.exec(
        "UPDATE runs SET record=json_set(record,'$.kind','local_read') WHERE id=?",
        &[&f.child],
    )
    .unwrap();
    let result = f.ledger.request_attribution(&f.plan.request_id, &f.owner);
    let gate = f
        .store
        .group_request_gate(&f.plan.request_id, &f.owner, &f.ledger);
    println!(
        "KIND_DAMAGED_ATTRIBUTION_IS_ERROR={} GATE={}",
        result.is_err(),
        serde_json::to_value(&gate).unwrap()
    );
    assert!(result.is_err());
    assert!(gate.group_hold());
}
#[test]
fn migration_must_preserve_request_rowid_history_order_not_only_named_columns() {
    let f = Fixture::new();
    let o = owner(&f);
    let mut ids = Vec::new();
    for label in ["First", "Second", "Third"] {
        let p = o
            .prepare_chat("migration-history", label, Some(&Proof))
            .unwrap();
        let cfg = o.configuration().unwrap();
        o.confirm_trusted(&p.request_id, &cfg.id).unwrap();
        let _unsent = o
            .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
            .unwrap();
        let response=json!({"id":"synthetic-answer","model":agent::owner::MODEL,"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":format!("Answer {label}")}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string();
        assert_eq!(
            o.settle_response(&p.request_id, &response).unwrap().status,
            "completed"
        );
        ids.push(p.request_id);
    }
    drop(o);
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    db.exec("DROP TABLE request_origins", &[]).unwrap();
    db.exec("UPDATE meta SET version='3'", &[]).unwrap();
    let before = db
        .query("SELECT rowid,* FROM requests ORDER BY id", &[])
        .unwrap();
    db.exec(&format!("CREATE TRIGGER reorder_legacy_history AFTER UPDATE OF version ON meta WHEN OLD.version='3' AND NEW.version='4' BEGIN INSERT OR REPLACE INTO requests SELECT * FROM requests WHERE id='{}'; END",ids[0]),&[]).unwrap();
    let result = agent::owner::AgentOwner::open(&f.0.join("agent.sqlite"), "ws", "epoch");
    println!(
        "ROWID_REORDER_MIGRATION_IS_ERROR={} BEFORE={:?} AFTER={:?}",
        result.is_err(),
        before.iter().map(|r| &r[0]).collect::<Vec<_>>(),
        db.query("SELECT rowid,* FROM requests ORDER BY id", &[])
            .unwrap()
            .iter()
            .map(|r| &r[0])
            .collect::<Vec<_>>()
    );
    assert!(
        result.is_err(),
        "same columns with changed rowid alters the real history LIMIT8 order"
    );
    assert_eq!(
        db.query("SELECT rowid,* FROM requests ORDER BY id", &[])
            .unwrap(),
        before
    );
    assert_eq!(
        db.query("SELECT version FROM meta", &[]).unwrap()[0][0].as_deref(),
        Some("3")
    );
}
#[test]
fn legitimate_local_read_and_workflow_roots_remain_non_group_but_remote_fields_are_invalid() {
    let f = Fixture::new();
    let s = f.init();
    let o = owner(&f);
    let mut l =
        agent::workflow::RunLedger::open(&f.0.join("workflow.sqlite"), "ws", "epoch").unwrap();
    let scope =
        agent::workflow::RunScope::current(&s, "session", "nongroup-local", Some("project"))
            .unwrap();
    let root = l
        .execute(
            &json!({"action":"create_root","title":"Synthetic local","task":"Offline"}).to_string(),
            &s,
            &scope,
        )
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();
    let child=l.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"local_read","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
    l.execute(
        &json!({"action":"execute_local","run_id":child}).to_string(),
        &s,
        &scope,
    )
    .unwrap();
    let p = o
        .prepare_chat("nongroup-local", "Synthetic ordinary", Some(&Proof))
        .unwrap();
    assert!(l.request_attribution(&p.request_id, &o).unwrap().is_none());
    assert!(!s.group_request_gate(&p.request_id, &o, &l).group_hold());
    let db = sqlite::Db::open(f.0.join("workflow.sqlite").to_str().unwrap(), false, false).unwrap();
    for id in [&root, &child] {
        let before = db
            .query("SELECT record FROM runs WHERE id=?", &[id])
            .unwrap()[0][0]
            .clone()
            .unwrap();
        for key in [
            "remote_request_id",
            "current_request_id",
            "remote_request_ids",
        ] {
            let mut value: serde_json::Value = serde_json::from_str(&before).unwrap();
            value[key] = if key == "remote_request_ids" {
                json!([p.request_id])
            } else {
                json!(p.request_id)
            };
            db.exec(
                "UPDATE runs SET record=? WHERE id=?",
                &[&value.to_string(), id],
            )
            .unwrap();
            assert!(l.request_attribution(&p.request_id, &o).is_err(), "{key}");
            assert!(s.group_request_gate(&p.request_id, &o, &l).group_hold());
            db.exec("UPDATE runs SET record=? WHERE id=?", &[&before, id])
                .unwrap();
        }
    }
    assert!(!s.group_request_gate(&p.request_id, &o, &l).group_hold());
}

#[test]
fn second_followup_unknown_unadvertised_and_unpaired_history_remain_rejected_without_writes() {
    for fault in [
        "unknown_wire",
        "unadvertised_wire",
        "logical_in_wire_history",
        "unpaired",
    ] {
        let (f, s, o, mut l, scope, p, child) = prepared_group();
        map_actual(&s, &o, &mut l, &scope, &p, &child);
        let ctx = approve_actual_tool(&s, &o, &p);
        let next = o
            .prepare_tool_followup_trusted(&s, &ctx, &p.request_id, Some(&Proof))
            .unwrap();
        let ctx = approve_actual_tool(&s, &o, &next);
        let db =
            sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
        let raw = db
            .query(
                "SELECT payload FROM requests WHERE id=?",
                &[&next.request_id],
            )
            .unwrap()[0][0]
            .clone()
            .unwrap();
        let mut body: serde_json::Value = serde_json::from_str(&raw).unwrap();
        match fault {
            "unknown_wire" => {
                body["messages"][1]["tool_calls"][0]["function"]["name"] =
                    json!("unregistered_tool")
            }
            "unadvertised_wire" => {
                body["messages"][1]["tool_calls"][0]["function"]["name"] =
                    json!("product_supplier_get")
            }
            "logical_in_wire_history" => {
                body["messages"][1]["tool_calls"][0]["function"]["name"] =
                    json!("product.supplier_list")
            }
            "unpaired" => {
                body["messages"].as_array_mut().unwrap().remove(2);
            }
            _ => unreachable!(),
        }
        db.exec(
            "UPDATE requests SET payload=? WHERE id=?",
            &[&body.to_string(), &next.request_id],
        )
        .unwrap();
        let requests = db
            .query("SELECT rowid,* FROM requests ORDER BY id", &[])
            .unwrap();
        let origins = db
            .query("SELECT * FROM request_origins ORDER BY request_id", &[])
            .unwrap();
        let steps = db
            .query("SELECT * FROM tool_steps ORDER BY request_id", &[])
            .unwrap();
        assert!(
            matches!(
                o.prepare_tool_followup_trusted(&s, &ctx, &next.request_id, Some(&Proof)),
                Err("tool_history_invalid")
            ),
            "{fault}"
        );
        assert_eq!(
            db.query("SELECT rowid,* FROM requests ORDER BY id", &[])
                .unwrap(),
            requests
        );
        assert_eq!(
            db.query("SELECT * FROM request_origins ORDER BY request_id", &[])
                .unwrap(),
            origins
        );
        assert_eq!(
            db.query("SELECT * FROM tool_steps ORDER BY request_id", &[])
                .unwrap(),
            steps
        );
        assert!(s.group_request_gate(&next.request_id, &o, &l).group_hold());
    }
}
#[test]
fn normal_legacy_migration_keeps_completed_history_order_and_new_direct_behavior() {
    let f = Fixture::new();
    let o = owner(&f);
    for label in ["First", "Second", "Third"] {
        let p = o
            .prepare_chat("migration-history", label, Some(&Proof))
            .unwrap();
        let cfg = o.configuration().unwrap();
        o.confirm_trusted(&p.request_id, &cfg.id).unwrap();
        let _unsent = o
            .claim_dispatch(&p.request_id, &cfg.id, &cfg.settings.credential_generation)
            .unwrap();
        let response=json!({"id":"synthetic-answer","model":agent::owner::MODEL,"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":format!("Answer {label}")}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string();
        o.settle_response(&p.request_id, &response).unwrap();
    }
    drop(o);
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    let before = db
        .query("SELECT rowid,* FROM requests ORDER BY id", &[])
        .unwrap();
    db.exec("DROP TABLE request_origins", &[]).unwrap();
    db.exec("UPDATE meta SET version='3'", &[]).unwrap();
    let o = agent::owner::AgentOwner::open(&f.0.join("agent.sqlite"), "ws", "epoch").unwrap();
    assert_eq!(
        db.query("SELECT rowid,* FROM requests ORDER BY id", &[])
            .unwrap(),
        before
    );
    let p = o
        .prepare_chat("migration-history", "Fourth", Some(&Proof))
        .unwrap();
    assert!(o.request_origin(&p.request_id).unwrap().is_direct());
    let payload: serde_json::Value = serde_json::from_str(
        db.query("SELECT payload FROM requests WHERE id=?", &[&p.request_id])
            .unwrap()[0][0]
            .as_deref()
            .unwrap(),
    )
    .unwrap();
    let users = payload["messages"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|v| v["role"] == "user")
        .map(|v| v["content"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(users, vec!["First", "Second", "Third", "Fourth"]);
}
#[test]
fn second_ordinary_followup_retains_direct_lineage_without_changing_confirmation_policy() {
    let f = Fixture::new();
    let s = f.init();
    let o = owner(&f);
    let l = agent::workflow::RunLedger::open(&f.0.join("workflow.sqlite"), "ws", "epoch").unwrap();
    let p = o
        .prepare_chat("ordinary-second", "Synthetic", Some(&Proof))
        .unwrap();
    let ctx = approve_actual_tool(&s, &o, &p);
    let next = o
        .prepare_tool_followup_trusted(&s, &ctx, &p.request_id, Some(&Proof))
        .unwrap();
    let ctx = approve_actual_tool(&s, &o, &next);
    let last = o
        .prepare_tool_followup_trusted(&s, &ctx, &next.request_id, Some(&Proof))
        .unwrap();
    assert!(o.request_origin(&last.request_id).unwrap().is_direct());
    assert_eq!(
        o.request_origin(&last.request_id)
            .unwrap()
            .root_request_id(),
        Some(p.request_id.as_str())
    );
    assert_eq!(o.request_chain(&p.request_id).unwrap().len(), 3);
    assert!(!s.group_request_gate(&last.request_id, &o, &l).group_hold());
    let cfg = o.configuration().unwrap();
    assert_eq!(
        o.confirm_trusted(&last.request_id, &cfg.id).unwrap().status,
        "reserved"
    );
}
