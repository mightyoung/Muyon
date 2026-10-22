
#[test]
fn independent_binding_write_faults_are_atomic_and_terminal_tamper_is_pending() {
 for (name,trigger,initial_failure) in [
 ("ignore", "BEFORE INSERT ON group_runtime_intent_bindings BEGIN SELECT RAISE(IGNORE); END",true),
 ("abort", "BEFORE INSERT ON group_runtime_intent_bindings BEGIN SELECT RAISE(ABORT,'offline'); END",true),
 ("terminal", "AFTER UPDATE ON group_runtime_local_intents WHEN NEW.status='committed' BEGIN UPDATE group_runtime_intent_bindings SET command='{}' WHERE intent_id=NEW.intent_id; END",false),
 ("consume", "AFTER UPDATE ON business_grants WHEN NEW.active=0 BEGIN UPDATE group_runtime_intent_bindings SET command='{}' WHERE intent_id='binding-fault'; END",false),
 ] {
 let f=Fixture::new();let s=f.init();let c=command("binding-fault",0,registration());s.issue_group_local_grant_trusted(&c).unwrap();
 s.database().exec(&format!("CREATE TRIGGER binding_fault {trigger}"),&[]).unwrap();
 let result=s.execute_group_local(&c,None);
 let journal=s.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id='binding-fault'",&[]).unwrap();
 if initial_failure {assert!(result.is_err(),"{name}: {result:?}");assert!(journal.is_empty(),"{name}");assert!(s.database().query("SELECT * FROM group_runtime_intent_bindings",&[]).unwrap().is_empty());}
 else {assert_eq!(result.unwrap().status,LocalStatus::PendingOriginal,"{name}");assert_eq!(journal,vec![vec![Some("pending".into()),None]]);assert_eq!(s.group_original_command("binding-fault","project","group").unwrap().intent_id,"binding-fault");}
 assert!(s.database().query("SELECT * FROM group_runtime_groups",&[]).unwrap().is_empty(),"{name}");assert!(s.database().query("SELECT * FROM group_runtime_events",&[]).unwrap().is_empty(),"{name}");
 assert_eq!(s.database().query("SELECT active FROM business_grants WHERE grant_id='grant-binding-fault'",&[]).unwrap()[0][0].as_deref(),Some("1"),"{name}");
 }
}
#[test]
fn independent_v1_migration_failure_is_atomic() {
 let f=Fixture::new();let s=f.init();s.database().exec("DROP TABLE group_runtime_intent_bindings",&[]).unwrap();s.database().exec("UPDATE group_runtime_schema SET version='1'",&[]).unwrap();
 s.database().exec("CREATE TRIGGER stop_migration BEFORE UPDATE ON group_runtime_schema BEGIN SELECT RAISE(IGNORE); END",&[]).unwrap();
 assert!(s.initialize_group_runtime().is_err());
 assert_eq!(s.database().query("SELECT version FROM group_runtime_schema",&[]).unwrap()[0][0].as_deref(),Some("1"));
 assert!(s.database().query("SELECT name FROM sqlite_master WHERE name='group_runtime_intent_bindings'",&[]).unwrap().is_empty());
}
