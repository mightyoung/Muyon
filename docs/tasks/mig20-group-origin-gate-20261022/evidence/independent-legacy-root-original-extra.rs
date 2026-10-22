
#[test]
fn independent_origin_gate_holds_actual_legacy_bind_original_without_a_workflow_child() {
 let f=Fixture::new();let s=f.init();let(l,_scope,_root)=actual_workflow(&f,&s);let o=owner(&f);
 let plan=o.prepare_chat("conversation","Synthetic root original",Some(&Proof)).unwrap();
 let cap=Capabilities{scopes:BTreeSet::from(["project".into()]),permissions:BTreeSet::from(["read".into()])};
 assert_eq!(apply(&s,&mutation("legacy-root-node",2,1,GroupOperation::Plan{run_id:"run".into(),node_id:"root-node".into(),member_id:"a".into(),dependencies:BTreeSet::new(),capabilities:cap,payload_digest:plan.payload_digest.clone()})).status,LocalStatus::Committed);
 let bind=mutation("legacy-root-bind",3,1,GroupOperation::BindOriginal{run_id:"run".into(),node_id:"root-node".into(),request_id:plan.request_id.clone()});s.issue_group_local_grant_trusted(&bind).unwrap();assert_eq!(s.execute_group_local(&bind,Some(&o)).unwrap().status,LocalStatus::Committed);
 let gate=s.group_request_gate(&plan.request_id,&o,&l);println!("ACTUAL_LEGACY_BIND_ORIGINAL_GATE={}",serde_json::to_value(&gate).unwrap());assert!(gate.group_hold(),"actual committed Group BindOriginal is group evidence even when no remote workflow child or canonical mapping exists");
}
