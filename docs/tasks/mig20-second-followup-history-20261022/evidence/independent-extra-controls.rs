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
