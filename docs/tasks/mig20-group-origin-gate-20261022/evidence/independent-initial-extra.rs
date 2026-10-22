
#[test]
fn independent_origin_gate_cannot_drop_a_bound_child_after_conversation_damage() {
 let f=CanonicalFixture::new();
 assert!(f.store.group_request_gate(&f.plan.request_id,&f.owner,&f.ledger).group_hold());
 let db=sqlite::Db::open(f.files.0.join("workflow.sqlite").to_str().unwrap(),false,false).unwrap();
 db.exec("UPDATE runs SET record=json_set(record,'$.conversation_id','damaged-child-conversation') WHERE id=?",&[&f.child]).unwrap();
 let gate=f.store.group_request_gate(&f.plan.request_id,&f.owner,&f.ledger);println!("DAMAGED_CONVERSATION_GATE={}",serde_json::to_value(&gate).unwrap());
 assert!(gate.group_hold(),"actual persisted request reference still belongs to the group child; conversation damage must not erase reverse attribution and create Direct");
}
#[test]
fn independent_origin_gate_cannot_downgrade_when_actual_group_run_row_is_missing() {
 let f=Fixture::new();let s=f.init();let (mut l,scope,root)=actual_workflow(&f,&s);let o=owner(&f);
 let child=l.execute(&json!({"action":"create_child","root_id":root,"skill_id":"supplier-overview","task":"Synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&s,&scope).unwrap()["id"].as_str().unwrap().to_string();
 let context=l.remote_context(&scope,&child).unwrap();let p=o.prepare_chat(context["conversation_id"].as_str().unwrap(),"Synthetic existing group",Some(&Proof)).unwrap();l.bind_remote_plan(&scope,&child,&p).unwrap();
 assert!(s.group_request_gate(&p.request_id,&o,&l).group_hold());s.database().exec("DELETE FROM group_runtime_runs WHERE run_id='run'",&[]).unwrap();
 let gate=s.group_request_gate(&p.request_id,&o,&l);println!("MISSING_ACTUAL_GROUP_RUN_GATE={}",serde_json::to_value(&gate).unwrap());
 assert!(gate.group_hold(),"actual group registration and committed Start provenance remain; missing group run cannot prove nongroup");
}
