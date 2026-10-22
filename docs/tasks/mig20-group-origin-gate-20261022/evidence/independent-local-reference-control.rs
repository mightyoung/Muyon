
#[test]
fn independent_origin_gate_holds_canonical_local_reference_when_workflow_child_is_missing() {
 for pending in [false,true] {
 let f=CanonicalFixture::new();
 if pending {f.store.database().exec("CREATE TRIGGER damage_independent_map AFTER INSERT ON group_request_bindings BEGIN UPDATE group_request_bindings SET record='{}' WHERE request_id=NEW.request_id; END",&[]).unwrap();}
 assert_eq!(f.bind().status,if pending{LocalStatus::PendingOriginal}else{LocalStatus::Committed});
 let db=sqlite::Db::open(f.files.0.join("workflow.sqlite").to_str().unwrap(),false,false).unwrap();db.exec("DELETE FROM runs WHERE id=?",&[&f.child]).unwrap();
 let gate=f.store.group_request_gate(&f.plan.request_id,&f.owner,&f.ledger);println!("LOCAL_CANONICAL_REFERENCE_WITH_MISSING_CHILD pending={pending} {}",serde_json::to_value(&gate).unwrap());assert!(gate.group_hold(),"missing workflow child cannot discard committed/pending local association");
 }
}
