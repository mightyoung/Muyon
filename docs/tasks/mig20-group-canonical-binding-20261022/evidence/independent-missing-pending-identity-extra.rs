
#[test]
fn independent_pending_canonical_missing_identity_does_not_restore_admission_or_handoff() {
 let f=CanonicalFixture::new();let cfg=f.owner.configuration().unwrap();f.owner.confirm_trusted(&f.plan.request_id,&cfg.id).unwrap();let _unsent=f.owner.claim_dispatch(&f.plan.request_id,&cfg.id,&cfg.settings.credential_generation).unwrap();
 f.store.database().exec("CREATE TRIGGER break_missing_mapping AFTER INSERT ON group_request_bindings BEGIN UPDATE group_request_bindings SET record='{}' WHERE request_id=NEW.request_id; END",&[]).unwrap();assert_eq!(f.bind().status,LocalStatus::PendingOriginal);
 f.store.database().exec("DELETE FROM group_runtime_intent_bindings WHERE intent_id='canonical-bind'",&[]).unwrap();
 let g=GroupScope::current(&f.store,"project","group").unwrap();let advice=f.store.group_next_pending(&g,"run",&f.owner);println!("MISSING_PENDING_IDENTITY_ADVICE={advice:?}");
 let h=mutation("handoff-missing-pending-source",3,1,GroupOperation::Handoff{run_id:"run".into(),to:"b".into()});f.store.issue_group_local_grant_trusted(&h).unwrap();let receipt=f.store.execute_group_local(&h,Some(&f.owner)).unwrap();println!("MISSING_PENDING_IDENTITY_HANDOFF={receipt:?}");
 assert!(!matches!(advice,Ok(PendingAdvice::PendingHostAdmission{..})),"loss of original pending identity proof must remain inconclusive, never new host-admission advice");assert_ne!(receipt.status,LocalStatus::Committed);
}
