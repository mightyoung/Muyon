
#[test]
fn independent_pending_canonical_unknown_still_blocks_handoff_checkpoint() {
 let f=CanonicalFixture::new();let cfg=f.owner.configuration().unwrap();f.owner.confirm_trusted(&f.plan.request_id,&cfg.id).unwrap();let _unsent=f.owner.claim_dispatch(&f.plan.request_id,&cfg.id,&cfg.settings.credential_generation).unwrap();
 f.store.database().exec("CREATE TRIGGER break_local_mapping AFTER INSERT ON group_request_bindings BEGIN UPDATE group_request_bindings SET record='{}' WHERE request_id=NEW.request_id; END",&[]).unwrap();
 assert_eq!(f.bind().status,LocalStatus::PendingOriginal);
 let g=GroupScope::current(&f.store,"project","group").unwrap();assert!(matches!(f.store.group_next_pending(&g,"run",&f.owner).unwrap(),PendingAdvice::LookupOriginal{..}));
 let h=mutation("handoff-with-pending-canonical",3,1,GroupOperation::Handoff{run_id:"run".into(),to:"b".into()});f.store.issue_group_local_grant_trusted(&h).unwrap();
 let receipt=f.store.execute_group_local(&h,Some(&f.owner)).unwrap();let run=f.store.group_run(&g,"run").unwrap();println!("PENDING_CANONICAL_UNKNOWN_HANDOFF={receipt:?} EPOCH={}",run.epoch);
 assert_ne!(receipt.status,LocalStatus::Committed,"unresolved actual child original must not cross a handoff checkpoint merely because its local mapping rolled back");assert_eq!(run.epoch,1);
}
