
#[test]
fn independent_canonical_tail_preserves_the_actual_source_plan_provenance() {
 let f=CanonicalFixture::new();
 f.store.database().exec("CREATE TRIGGER damage_source_plan AFTER INSERT ON group_request_bindings BEGIN DELETE FROM group_runtime_events WHERE intent_id='canonical-node'; END",&[]).unwrap();
 let receipt=f.bind();let scope=GroupScope::current(&f.store,"project","group").unwrap();let reread=f.store.group_request_binding(&scope,"run","node");
 println!("CANONICAL_SOURCE_PLAN_TAIL={receipt:?} REREAD={:?}",reread.as_ref().map(|v|serde_json::to_value(v).unwrap()));
 assert_ne!(receipt.status,LocalStatus::Committed,"same transaction must not commit a mapping whose checked source Plan provenance was erased by its write trigger");
}
