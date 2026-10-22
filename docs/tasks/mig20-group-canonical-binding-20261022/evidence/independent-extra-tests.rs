
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
