use super::*;
use std::{path::PathBuf, sync::atomic::{AtomicU64, Ordering}};
static NEXT: AtomicU64 = AtomicU64::new(1);
const CONVERSATION: &str = "11111111-1111-4111-8111-111111111111";
const INTENT: &str = "22222222-2222-4222-8222-222222222222";
const OTHER: &str = "33333333-3333-4333-8333-333333333333";
struct Fixture { path: PathBuf, store: Option<BusinessStore>, binding: DraftBinding }
impl Fixture {
 fn new() -> Self {
  let path=std::env::temp_dir().join(format!("muyon-definition-{}-{}.db",std::process::id(),NEXT.fetch_add(1,Ordering::SeqCst)));
  BusinessStore::initialize(&path,"synthetic").unwrap();
  let store=BusinessStore::open_existing(&path,"synthetic","epoch1").unwrap();
  let d=crate::bot_drafts::resolve(&store,CONVERSATION,None).unwrap();
  let mut binding=DraftBinding{namespace_id:d["namespace_id"].as_str().unwrap().into(),draft_id:d["draft_id"].as_str().unwrap().into(),expected_generation:"1".into(),expected_stored_revision:"0".into()};
  crate::bot_drafts::save(&store,CONVERSATION,None,&binding,OTHER,"3",&archive(1)).unwrap();
  binding.expected_stored_revision="1".into();
  Self{path,store:Some(store),binding}
 }
 fn store(&self)->&BusinessStore{self.store.as_ref().unwrap()}
 fn reopen(&mut self){self.store.take();self.store=Some(BusinessStore::open_existing(&self.path,"synthetic","epoch2").unwrap());}
}
impl Drop for Fixture {fn drop(&mut self){self.store.take();for suffix in ["","-wal","-shm",".owner.lock"]{let _=std::fs::remove_file(format!("{}{suffix}",self.path.display()));}}}
fn archive(revision:i64)->Vec<u8>{
 let mut b=b"MYBD\0\0\0\x01".to_vec();b.extend(revision.to_be_bytes());
 for s in ["论文助手","整理文献","研究员"]{b.extend([0,1]);b.extend((s.len() as i32).to_be_bytes());b.extend(s.as_bytes());}
 b.push(0);let h=Sha256::digest(&b);b.extend(h);b
}
fn prepare(f:&Fixture)->CreateReview{prepare_create(f.store(),CONVERSATION,None,&f.binding,INTENT).unwrap()}
#[test] fn creates_only_after_confirm_and_original_intent_is_idempotent(){
 let f=Fixture::new();let r=prepare(&f);
 assert!(list(f.store(),CONVERSATION,None).unwrap().is_empty());
 let a=confirm_create_trusted(f.store(),CONVERSATION,None,INTENT,&r.review_digest).unwrap();
 assert_eq!(a.status,CreateStatus::Committed);let bot=a.definition.as_ref().unwrap();
 assert_eq!(bot.name,"论文助手");assert!(!bot.runnable);assert_eq!(bot.unavailable_reason,"provider_not_configured");
 let b=confirm_create_trusted(f.store(),CONVERSATION,None,INTENT,&r.review_digest).unwrap();assert_eq!(a,b);
 assert_eq!(lookup_create(f.store(),CONVERSATION,None,INTENT).unwrap(),a);
 assert_eq!(list(f.store(),CONVERSATION,None).unwrap().len(),1);
 assert_eq!(get(f.store(),CONVERSATION,None,&bot.id).unwrap(),*bot);
 assert!(prepare_create(f.store(),CONVERSATION,None,&f.binding,OTHER).is_err());
 assert_eq!(f.store().database().query("SELECT COUNT(*) FROM business_grants",&[]).unwrap()[0][0].as_deref(),Some("0"));
}
#[test] fn cas_scope_and_changed_confirmation_reject_without_definition(){
 let f=Fixture::new();let r=prepare(&f);
 assert!(confirm_create_trusted(f.store(),CONVERSATION,None,INTENT,"wrong").is_err());
 assert!(lookup_create(f.store(),OTHER,None,INTENT).is_err());
 f.store().database().exec("UPDATE local_bot_drafts SET stored_revision='2'",&[]).unwrap();
 assert!(confirm_create_trusted(f.store(),CONVERSATION,None,INTENT,&r.review_digest).is_err());
 assert!(list(f.store(),CONVERSATION,None).unwrap().is_empty());
}
#[test] fn pending_unknown_never_reexecutes_and_archive_replay_cannot_clear_stop(){
 let mut f=Fixture::new();let r=prepare(&f);
 f.store().database().exec("CREATE TRIGGER fail_bot BEFORE INSERT ON local_bot_definitions BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",&[]).unwrap();
 assert!(confirm_create_trusted(f.store(),CONVERSATION,None,INTENT,&r.review_digest).is_err());
 f.reopen();recover_previous_owner(f.store()).unwrap();
 let unknown=lookup_create(f.store(),CONVERSATION,None,INTENT).unwrap();assert_eq!(unknown.status,CreateStatus::Unknown);
 f.store().database().exec("DROP TRIGGER fail_bot",&[]).unwrap();
 assert_eq!(confirm_create_trusted(f.store(),CONVERSATION,None,INTENT,&r.review_digest).unwrap(),unknown);
 assert!(prepare_create(f.store(),CONVERSATION,None,&f.binding,OTHER).is_err());
 assert!(list(f.store(),CONVERSATION,None).unwrap().is_empty());
}
#[test] fn committed_receipt_and_definition_survive_restart_without_replaying(){
 let mut f=Fixture::new();let r=prepare(&f);
 let receipt=confirm_create_trusted(f.store(),CONVERSATION,None,INTENT,&r.review_digest).unwrap();
 f.reopen();recover_previous_owner(f.store()).unwrap();
 assert_eq!(lookup_create(f.store(),CONVERSATION,None,INTENT).unwrap(),receipt);
 assert_eq!(list(f.store(),CONVERSATION,None).unwrap().len(),1);
}
#[test] fn old_prepared_review_is_sealed_and_explicit_cancel_allows_new_review(){
 let mut f=Fixture::new();prepare(&f);f.reopen();
 assert!(confirm_create_trusted(f.store(),CONVERSATION,None,INTENT,&prepare(&f).review_digest).is_err());
 recover_previous_owner(f.store()).unwrap();
 assert_eq!(lookup_create(f.store(),CONVERSATION,None,INTENT).unwrap().status,CreateStatus::Rejected);
 let r=prepare_create(f.store(),CONVERSATION,None,&f.binding,OTHER).unwrap();
 cancel_prepared(f.store(),CONVERSATION,None,OTHER).unwrap();
 assert!(confirm_create_trusted(f.store(),CONVERSATION,None,OTHER,&r.review_digest).is_err());
}
#[test] fn corrupted_archive_and_unknown_schema_fail_closed(){
 let f=Fixture::new();
 f.store().database().exec("UPDATE local_bot_drafts SET archive_hex='00'",&[]).unwrap();
 assert!(prepare_create(f.store(),CONVERSATION,None,&f.binding,INTENT).is_err());
 assert!(list(f.store(),CONVERSATION,None).unwrap().is_empty());
}
