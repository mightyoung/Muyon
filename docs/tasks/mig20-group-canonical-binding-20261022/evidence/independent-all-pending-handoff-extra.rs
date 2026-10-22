
#[test]
fn independent_handoff_checks_all_pending_canonical_chains_not_only_first() {
 let mut f=CanonicalFixture::new();
 let child=f.ledger.execute(&json!({"action":"create_child","root_id":f.root,"skill_id":"supplier-overview","task":"Second synthetic","executor":"remote_chat","arguments":{"limit":5,"offset":0}}).to_string(),&f.store,&f.scope).unwrap()["id"].as_str().unwrap().to_string();
 let ctx=f.ledger.remote_context(&f.scope,&child).unwrap();let plan=f.owner.prepare_chat(ctx["conversation_id"].as_str().unwrap(),"Second synthetic",Some(&Proof)).unwrap();f.ledger.bind_remote_plan(&f.scope,&child,&plan).unwrap();
 let cap=Capabilities{scopes:BTreeSet::from(["project".into()]),permissions:BTreeSet::from(["read".into()])};
 assert_eq!(apply(&f.store,&mutation("second-node",3,1,GroupOperation::Plan{run_id:"run".into(),node_id:"node-two".into(),member_id:"b".into(),dependencies:BTreeSet::new(),capabilities:cap,payload_digest:plan.payload_digest.clone()})).status,LocalStatus::Committed);
 let cfg=f.owner.configuration().unwrap();for id in [&f.plan.request_id,&plan.request_id] {f.owner.confirm_trusted(id,&cfg.id).unwrap();let _unsent=f.owner.claim_dispatch(id,&cfg.id,&cfg.settings.credential_generation).unwrap();}
 f.store.database().exec("CREATE TRIGGER break_two_mappings AFTER INSERT ON group_request_bindings BEGIN UPDATE group_request_bindings SET record='{}' WHERE request_id=NEW.request_id; END",&[]).unwrap();
 let first=mutation("a-pending-terminal",4,1,GroupOperation::BindCanonical{run_id:"run".into(),node_id:"node".into(),workflow_run_id:f.child.clone(),request_id:f.plan.request_id.clone()});
 let second=mutation("b-pending-unknown",4,1,GroupOperation::BindCanonical{run_id:"run".into(),node_id:"node-two".into(),workflow_run_id:child,request_id:plan.request_id.clone()});
 for c in [&first,&second] {f.store.issue_group_local_grant_trusted(c).unwrap();assert_eq!(f.store.execute_group_canonical_local(c,&f.owner,&f.ledger,&f.scope).unwrap().status,LocalStatus::PendingOriginal);}
 let body=json!({"id":"synthetic","model":agent::owner::MODEL,"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"Synthetic completed"}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}});
 assert_eq!(f.owner.settle_response(&f.plan.request_id,&body.to_string()).unwrap().status,"completed");assert_eq!(f.owner.lookup(&plan.request_id).unwrap().status,"unknown");
 let h=mutation("handoff-all-pending",4,1,GroupOperation::Handoff{run_id:"run".into(),to:"b".into()});f.store.issue_group_local_grant_trusted(&h).unwrap();let receipt=f.store.execute_group_local(&h,Some(&f.owner)).unwrap();
 let g=GroupScope::current(&f.store,"project","group").unwrap();let run=f.store.group_run(&g,"run").unwrap();println!("ALL_PENDING_CHAIN_HANDOFF={receipt:?} EPOCH={}",run.epoch);
 assert_ne!(receipt.status,LocalStatus::Committed,"the first pending original is terminal, but a second actual chain is still Unknown");assert_eq!(run.epoch,1);
}
