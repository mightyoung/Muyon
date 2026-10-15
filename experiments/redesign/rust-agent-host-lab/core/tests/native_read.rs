use std::{cell::RefCell,path::PathBuf,rc::Rc,sync::atomic::{AtomicUsize,Ordering}};
use muyon_core_agent_lab::{Result,agent::{Agent,State,Limits,Hooks},model::{Provider,ModelEvent,ModelRequest}};
use muyon_plugin_contract_lab::{Json,parse};
use muyon_rust_agent_host_lab::*;
fn json(s:&str)->Json{parse(s.as_bytes()).unwrap()}
struct Authority(RefCell<AuthoritySnapshot>);
impl AuthoritySource for Authority{fn snapshot(&self)->Result<AuthoritySnapshot>{Ok(self.0.borrow().clone())}}
struct Review;
impl PurposeReview for Review{
 fn review(&self,v:&Json,_facts:&Json,purpose:&str)->Result<()>{if !matches!(purpose,"model_context"|"model_payload")||v.encode().contains("BORROWER_PRIVATE"){Err("actual_value_denied".into())}else{Ok(())}}
 fn mask_answer(&self,text:&str)->Result<String>{Ok(text.replace("BORROWER_PRIVATE","[redacted]"))}
}
static SERIAL:AtomicUsize=AtomicUsize::new(0);
fn directory()->PathBuf{std::env::temp_dir().join(format!("muyon-native-{}-{}",std::process::id(),SERIAL.fetch_add(1,Ordering::SeqCst)))}
fn authority()->Rc<Authority>{Rc::new(Authority(RefCell::new(AuthoritySnapshot{read:json(r#"{"allowed":true,"available":true,"scope_allowed":true,"bindings":["host-equipment-read"],"revision":"a1","binding_revision":"b1","source_revision":"s1","rule_revision":"r1","scope":"selected-e1","refs":[{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"1","schema_version":1},{"module_id":"equipment_loan","type":"loan","key":"l1","revision":"1","schema_version":1}]}"#),model_allowed:true,profile:"offline-fixture".into()})))}
fn session(a:Rc<Authority>)->SharedSession{
 let plugin=PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").expect("CI must provide actual absolute plugin child"));
 let s=NativeSession::create(&directory(),&plugin,a,Rc::new(Review),"inspect selected equipment").unwrap();
 s.borrow_mut().register(Enrollment{bundle:json(include_str!("../../../plugin-contract-lab/fixtures/equipment_loan.json")),operation:"equipment_loan/inspect_equipment@1".into(),tool_id:"equipment_loan.inspect_equipment".into(),binding_id:"host-equipment-read".into(),handler:Box::new(|_:&Json|Ok(RawRead{raw:json(r#"{"label":"synthetic drill","borrower":"BORROWER_PRIVATE"}"#),projection:json(r#"{"equipment":{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"1","schema_version":1},"label":"synthetic drill","loans":[{"module_id":"equipment_loan","type":"loan","key":"l1","revision":"1","schema_version":1}]}"#)}))}).unwrap();s
}
struct CallProvider;
impl Provider for CallProvider{fn respond(&mut self,_r:&ModelRequest,position:usize)->Result<ModelEvent>{if position==0{Ok(ModelEvent::HostTool{call_ref:"call1".into(),name:"equipment_loan.inspect_equipment".into(),arguments:json(r#"{"equipment_key":"e1","include_loans":true}"#)})}else{Ok(ModelEvent::Answer("synthetic completed".into()))}}}
fn agent(s:&SharedSession)->Agent{Agent{dir:s.borrow().store.dir.clone(),state:State::runtime("inspect selected equipment".into(),"selected-e1".into(),Limits::default()).unwrap()}}
#[test]
fn native_host_executes_registered_read(){
 let s=session(authority());assert_eq!(s.borrow().handler_calls,0,"registration is not execution");
 assert_eq!(field(&s.borrow_mut().discover().unwrap(),"operations").unwrap().array().unwrap().len(),1,"real child must admit the catalog");
 let mut a=agent(&s);a.run_with_runtime_ports(&mut CallProvider,&mut RuntimePorts{session:s.clone()},&Hooks::default()).unwrap();
 assert_eq!(s.borrow().dispatch_attempts,1,"real common drive must reach native dispatch before interpreting RED");
 assert_eq!(s.borrow().handler_calls,1,"NATIVE_READ_RED: native host must execute exactly one admitted registered read");
 assert_eq!(a.state.status,"completed");assert_eq!(s.borrow().store.receipt_count(),1);
}
