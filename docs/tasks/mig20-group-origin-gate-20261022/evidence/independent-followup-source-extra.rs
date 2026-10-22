fn independent_prepared_group()->(Fixture,BusinessStore,agent::owner::AgentOwner,agent::workflow::RunLedger,agent::workflow::RunScope,agent::owner::AgentPlan,String) {
    let f=Fixture::new();let s=f.init();let o=owner(&f);let(mut l,scope,root)=actual_workflow(&f,&s);
    let child=l.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
    let g=GroupScope::current(&s,"project","group").unwrap();
    let p=s.group_prepare_chat(&g,&o,&l,&scope,group_runtime_store::gate::GroupChatPreparation{run_id:"run",workflow_run_id:&child,member_id:"a",text:"Synthetic group"},Some(&Proof)).unwrap();
    (f,s,o,l,scope,p,child)
}
fn independent_approve_actual_tool(s:&BusinessStore,o:&agent::owner::AgentOwner,p:&agent::owner::AgentPlan)->agent::tools::ToolsContext {
    let ctx=agent::tools::ToolsContext::current(s,"session","generation",Some("project")).unwrap();
    o.bind_tool_scope_trusted(&p.request_id,&ctx).unwrap();
    let cfg=o.configuration().unwrap();o.confirm_trusted(&p.request_id,&cfg.id).unwrap();
    let _unsent=o.claim_dispatch(&p.request_id,&cfg.id,&cfg.settings.credential_generation).unwrap();
    let body=json!({"id":"synthetic-tool","model":agent::owner::MODEL,"choices":[{"index":0,"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_a","type":"function","function":{"name":"product_supplier_list","arguments":"{\"limit\":5,\"offset\":0}"}}]}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string();
    assert_eq!(o.settle_response(&p.request_id,&body).unwrap().status,"tool_pending");
    let review=o.review_tool_read(s,&ctx,&p.request_id).unwrap();
    o.approve_tool_read_trusted(s,&ctx,&p.request_id,&review.digest).unwrap();ctx
}

#[test]
fn independent_followup_insert_cannot_mutate_parent_before_the_source_witness_is_captured() {
 let(f,s,o,_l,_scope,plan,_child)=independent_prepared_group();let ctx=independent_approve_actual_tool(&s,&o,&plan);
 let db=sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(),false,false).unwrap();let before=db.query("SELECT * FROM requests ORDER BY id",&[]).unwrap();
 db.exec(&format!("CREATE TRIGGER mutate_parent_during_new_request AFTER INSERT ON requests BEGIN UPDATE requests SET charged=charged+1 WHERE id='{}'; END",plan.request_id),&[]).unwrap();
 let next=o.prepare_tool_followup_trusted(&s,&ctx,&plan.request_id,Some(&Proof));println!("FOLLOWUP_INSERT_PARENT_SOURCE_RESULT={next:?} PARENT_STATUS={:?}",o.lookup(&plan.request_id));
 assert!(next.is_err(),"source parent must be frozen before the first new request INSERT, not captured after its trigger changed charged cost");assert_eq!(db.query("SELECT * FROM requests ORDER BY id",&[]).unwrap(),before);
}
