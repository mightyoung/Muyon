
#[test]
fn independent_migration_legacy_pending_existing_group_is_read_only() {
 let f=Fixture::new();let s=f.init();start(&s);
 s.database().exec("CREATE TRIGGER fail_historical_config BEFORE UPDATE ON group_runtime_groups BEGIN SELECT RAISE(ABORT,'synthetic'); END",&[]).unwrap();
 assert_eq!(apply(&s,&command("legacy-existing-pending",2,config("fixed"))).status,LocalStatus::PendingOriginal);
 s.database().exec("DROP TRIGGER fail_historical_config",&[]).unwrap();
 s.database().exec("DROP TABLE group_runtime_intent_bindings",&[]).unwrap();s.database().exec("UPDATE group_runtime_schema SET version='1'",&[]).unwrap();
 let queries=["SELECT * FROM group_runtime_local_intents ORDER BY intent_id","SELECT * FROM business_grants ORDER BY grant_id","SELECT * FROM group_runtime_groups ORDER BY group_id","SELECT * FROM group_runtime_runs ORDER BY run_id","SELECT * FROM group_runtime_nodes ORDER BY node_id","SELECT * FROM group_runtime_events ORDER BY intent_id"];
 let before:Vec<_>=queries.iter().map(|q|s.database().query(q,&[]).unwrap()).collect();
 s.initialize_group_runtime().unwrap();
 let raw=json!({"schema_version":1,"request":{"operation":"local_intent","group_id":"group","intent_id":"legacy-existing-pending"}}).to_string();
 for actor in ["owner","admin"] {
 let scope=GroupUiScope::current(&s,"project",actor).unwrap();
 for _ in 0..2 {let v=s.group_ui_read(&scope,&raw,None,None).unwrap();assert_eq!(v["local_intent"]["status"],"pending_original");assert_eq!(v["local_intent"]["identity_source"],"current_group_management");assert!(v["local_intent"]["receipt"].is_null());}
 }
 let member=GroupUiScope::current(&s,"project","a").unwrap();assert_eq!(s.group_ui_read(&member,&raw,None,None).unwrap_err(),ContractError::InvalidAuthority);
 s.initialize_group_runtime().unwrap();
 for (q,expected) in queries.iter().zip(before) {assert_eq!(s.database().query(q,&[]).unwrap(),expected,"{q}");}
 assert!(s.database().query("SELECT * FROM group_runtime_intent_bindings",&[]).unwrap().is_empty());
}
