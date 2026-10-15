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
 let plugin=PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").expect("actual child binary"));let s=NativeSession::create(&directory(),&plugin,a,Rc::new(Review),"inspect selected equipment").unwrap();
 let dir=s.borrow().store.dir.clone();let mut raw=projection();put(&mut raw,"borrower",Json::String("BORROWER_PRIVATE".into()));muyon_core_agent_lab::store::atomic(&dir,"synthetic-data.db",&raw.encode()).unwrap();
 let handler=read_registry::PhysicalReadHandler::new(&dir,"synthetic-data.db","equipment_key","e1",vec!["equipment".into(),"label".into(),"loans".into()],Some(("include_loans".into(),"loans".into()))).unwrap();
 s.borrow_mut().register(Enrollment{bundle:json(include_str!("../../../plugin-contract-lab/fixtures/equipment_loan.json")),operation:"equipment_loan/inspect_equipment@1".into(),tool_id:"equipment_loan.inspect_equipment".into(),binding_id:"host-equipment-read".into(),handler:Box::new(handler)}).unwrap();s
}
fn projection()->Json{json(r#"{"equipment":{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"1","schema_version":1},"label":"synthetic drill","loans":[{"module_id":"equipment_loan","type":"loan","key":"l1","revision":"1","schema_version":1}]}"#)}
fn session_handler(a:Rc<Authority>,handler:Box<dyn ReadHandler>)->SharedSession{
 let plugin=PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").expect("CI must provide actual absolute plugin child"));
 let s=NativeSession::create(&directory(),&plugin,a,Rc::new(Review),"inspect selected equipment").unwrap();
 s.borrow_mut().register(Enrollment{bundle:json(include_str!("../../../plugin-contract-lab/fixtures/equipment_loan.json")),operation:"equipment_loan/inspect_equipment@1".into(),tool_id:"equipment_loan.inspect_equipment".into(),binding_id:"host-equipment-read".into(),handler}).unwrap();s
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
fn run(s:&SharedSession)->Agent{let mut a=agent(s);a.run_with_runtime_ports(&mut CallProvider,&mut RuntimePorts{session:s.clone()},&Hooks::default()).unwrap();a}
fn put(j:&mut Json,k:&str,v:Json){if let Json::Object(m)=j{m.insert(k.into(),v);}}
#[test]
fn unauthorized_read_executes_zero(){let auth=authority();put(&mut auth.0.borrow_mut().read,"allowed",Json::Bool(false));let s=session(auth);assert!(field(&s.borrow_mut().discover().unwrap(),"operations").unwrap().array().unwrap().is_empty());let a=run(&s);assert_ne!(a.state.status,"completed");assert_eq!(s.borrow().handler_calls,0);assert_eq!(s.borrow().store.receipt_count(),0);}
#[test]
fn wrong_projection_preserves_raw_receipt(){let s=session_handler(authority(),Box::new(|_:&Json|Ok(RawRead{raw:json(r#"{"borrower":"BORROWER_PRIVATE"}"#),projection:json(r#"{"label":17}"#)})));let a=run(&s);assert_ne!(a.state.status,"completed");assert_eq!(s.borrow().handler_calls,1);assert_eq!(s.borrow().store.receipt_count(),1);assert!(s.borrow().store.receipts()[0].encode().contains("BORROWER_PRIVATE"));assert_eq!(s.borrow().model_history().array().unwrap().len(),1);}
#[test]
fn handler_failure_keeps_source_facts(){let s=session_handler(authority(),Box::new(|_:&Json|Err("BORROWER_PRIVATE".into())));let a=run(&s);assert_ne!(a.state.status,"completed");assert_eq!(s.borrow().handler_calls,1);assert_eq!(field(s.borrow().store.facts(),"unknown_source").unwrap(),&Json::Bool(true));assert_eq!(s.borrow().store.receipt_count(),1);assert!(!s.borrow().model_history().encode().contains("BORROWER_PRIVATE"));}
#[test]
fn receipt_time_revoke_exports_no_projection(){let auth=authority();let changed=auth.clone();let s=session_handler(auth,Box::new(move|_:&Json|{put(&mut changed.0.borrow_mut().read,"revision",Json::String("a2".into()));Ok(RawRead{raw:json(r#"{"raw":"private"}"#),projection:projection()})}));let a=run(&s);assert_ne!(a.state.status,"completed");assert_eq!(s.borrow().handler_calls,1);assert_eq!(s.borrow().store.receipt_count(),1);assert_eq!(s.borrow().model_history().array().unwrap().len(),1);}
#[test]
fn actual_value_review_denies_sensitive_projection(){let mut p=projection();put(&mut p,"label",Json::String("BORROWER_PRIVATE".into()));let s=session_handler(authority(),Box::new(move|_:&Json|Ok(RawRead{raw:p.clone(),projection:p.clone()})));let a=run(&s);assert_ne!(a.state.status,"completed");assert_eq!(s.borrow().handler_calls,1);assert_eq!(s.borrow().model_history().array().unwrap().len(),1);}
#[test]
fn cancel_closes_owned_child_and_executes_zero(){let s=session(authority());let pid=s.borrow().child_pid();s.borrow_mut().cancel();assert!(!PathBuf::from(format!("/proc/{pid}")).exists(),"owned child must be reaped");let a=run(&s);assert_ne!(a.state.status,"completed");assert_eq!(s.borrow().handler_calls,0);assert!(s.borrow_mut().discover().is_err());}
#[test]
fn restart_retains_raw_evidence_without_live_export_authority(){let s=session(authority());let _=run(&s);let dir=s.borrow().store.dir.clone();assert_eq!(s.borrow().store.receipt_count(),1);drop(s);let store=store::NativeStore::open(&dir).unwrap();assert_eq!(store.receipt_count(),1);assert_eq!(field(store.facts(),"unknown_source").unwrap(),&Json::Bool(true));assert!(!dir.join("effects.db").exists());/* No Session restore API: a receipt never restores a live projection/grant. */}
use muyon_rust_agent_host_lab::model_gateway::{ModelGateway,OfflineEndpoint};
use muyon_core_agent_lab::model::ProviderControl;
struct Endpoint{responses:Vec<Vec<u8>>,sent:Rc<RefCell<Vec<Vec<u8>>>>}
impl OfflineEndpoint for Endpoint{fn exchange(&mut self,body:&[u8],control:&mut dyn ProviderControl)->Result<Vec<u8>>{control.poll()?;self.sent.borrow_mut().push(body.to_vec());if self.responses.is_empty(){Err("offline_exhausted".into())}else{Ok(self.responses.remove(0))}}}
fn call_sse()->Vec<u8>{br#"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call1","type":"function","function":{"name":"registered_0","arguments":"{\"equipment_key\":\"e1\",\"include_loans\":true}"}}]},"finish_reason":"tool_calls"}]}

data: [DONE]

"#.to_vec()}
fn answer_sse()->Vec<u8>{b"data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"synthetic complete\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".to_vec()}
fn gateway(s:&SharedSession)->(ModelGateway,Rc<RefCell<Vec<Vec<u8>>>>){let sent=Rc::new(RefCell::new(Vec::new()));(ModelGateway::new(s.clone(),Box::new(Endpoint{responses:vec![call_sse(),answer_sse()],sent:sent.clone()})),sent)}
#[test]
fn two_turn_model_bytes_contain_only_validated_projection(){let s=session(authority());let(mut provider,sent)=gateway(&s);let mut a=agent(&s);a.run_with_runtime_ports(&mut provider,&mut RuntimePorts{session:s.clone()},&Hooks::default()).unwrap();assert_eq!(a.state.status,"completed");assert_eq!(sent.borrow().len(),2);let body=String::from_utf8(sent.borrow()[1].clone()).unwrap();assert!(body.contains("synthetic drill"));assert!(!body.contains("BORROWER_PRIVATE"));assert_eq!(s.borrow().handler_calls,1);assert_eq!(s.borrow().store.receipt_count(),1);}
#[test]
fn historical_projection_revoke_blocks_actual_second_send(){let auth=authority();let s=session(auth.clone());let a=run(&s);assert_eq!(a.state.status,"completed");put(&mut auth.0.borrow_mut().read,"source_revision",Json::String("s2".into()));let(mut provider,sent)=gateway(&s);let mut fresh=agent(&s);fresh.run_with_runtime_ports(&mut provider,&mut RuntimePorts{session:s.clone()},&Hooks::default()).unwrap();assert!(sent.borrow().is_empty());assert_eq!(s.borrow().handler_calls,1);assert_ne!(fresh.state.status,"completed");}
#[test]
fn ledger_failure_sends_zero_bytes(){let s=session(authority());std::fs::create_dir(s.borrow().store.dir.join("outbound.db")).unwrap();let(mut provider,sent)=gateway(&s);let mut a=agent(&s);a.run_with_runtime_ports(&mut provider,&mut RuntimePorts{session:s.clone()},&Hooks::default()).unwrap();assert_ne!(a.state.status,"completed");assert!(sent.borrow().is_empty());assert_eq!(s.borrow().handler_calls,0);}
#[test]
fn malformed_oversize_eof_child_frames_invalidate_session(){for (mode,code) in [("invalid","plugin_invalid_json"),("oversize","plugin_frame_limit"),("eof","plugin_eof")]{let mut process=plugin_process::PluginProcess::spawn_with_args(std::path::Path::new(env!("CARGO_BIN_EXE_native-protocol-fixture")),&[mode],std::time::Duration::from_secs(1)).unwrap();let pid=process.pid();assert_eq!(process.request(json(r#"{"protocol_version":1,"command":"inspect"}"#)).unwrap_err(),code);assert_eq!(process.request(Json::Null).unwrap_err(),"plugin_closed");assert!(!PathBuf::from(format!("/proc/{pid}")).exists());}}
#[test]
fn silent_child_deadline_is_bounded_and_reaped(){let mut process=plugin_process::PluginProcess::spawn_with_args(std::path::Path::new(env!("CARGO_BIN_EXE_native-protocol-fixture")),&["silent"],std::time::Duration::from_millis(100)).unwrap();let pid=process.pid();let started=std::time::Instant::now();assert_eq!(process.request(json(r#"{"protocol_version":1,"command":"inspect"}"#)).unwrap_err(),"plugin_deadline");assert!(started.elapsed()<std::time::Duration::from_secs(3));assert!(!PathBuf::from(format!("/proc/{pid}")).exists());}
struct RepeatProvider;
impl Provider for RepeatProvider{fn respond(&mut self,r:&ModelRequest,_p:usize)->Result<ModelEvent>{CallProvider.respond(r,0)}}
#[test]
fn duplicate_model_call_never_reexecutes_handler(){let s=session(authority());let mut a=agent(&s);a.run_with_runtime_ports(&mut RepeatProvider,&mut RuntimePorts{session:s.clone()},&Hooks::default()).unwrap();assert_eq!(s.borrow().handler_calls,1);assert_eq!(s.borrow().store.receipt_count(),1);assert_ne!(a.state.status,"completed");}
#[test]
fn wrong_reference_version_retains_only_original_receipt(){let mut p=projection();let mut r=field(&p,"equipment").unwrap().clone();put(&mut r,"schema_version",Json::Number("2".into()));put(&mut p,"equipment",r);let s=session_handler(authority(),Box::new(move|_:&Json|Ok(RawRead{raw:p.clone(),projection:p.clone()})));let a=run(&s);assert_ne!(a.state.status,"completed");assert_eq!(s.borrow().handler_calls,1);assert_eq!(s.borrow().store.receipt_count(),1);assert_eq!(s.borrow().model_history().array().unwrap().len(),1);}
struct RevokeReview{authority:Rc<Authority>}
impl PurposeReview for RevokeReview{
 fn review(&self,value:&Json,_facts:&Json,purpose:&str)->Result<()>{if purpose=="model_payload"&&value.encode().contains("synthetic drill"){self.authority.0.borrow_mut().model_allowed=false;}Review.review(value,_facts,purpose)}
 fn mask_answer(&self,text:&str)->Result<String>{Review.mask_answer(text)}
}
#[test]
fn final_payload_policy_revoke_blocks_second_endpoint_admission(){let auth=authority();let plugin=PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").unwrap());let s=NativeSession::create(&directory(),&plugin,auth.clone(),Rc::new(RevokeReview{authority:auth}),"inspect selected equipment").unwrap();s.borrow_mut().register(Enrollment{bundle:json(include_str!("../../../plugin-contract-lab/fixtures/equipment_loan.json")),operation:"equipment_loan/inspect_equipment@1".into(),tool_id:"equipment_loan.inspect_equipment".into(),binding_id:"host-equipment-read".into(),handler:Box::new(|_:&Json|Ok(RawRead{raw:projection(),projection:projection()}))}).unwrap();let(mut provider,sent)=gateway(&s);let mut a=agent(&s);a.run_with_runtime_ports(&mut provider,&mut RuntimePorts{session:s.clone()},&Hooks::default()).unwrap();assert_eq!(s.borrow().handler_calls,1);assert_eq!(s.borrow().store.receipt_count(),1);assert_eq!(sent.borrow().len(),1,"post-policy revoke must block projection bytes");assert_ne!(a.state.status,"completed");}
struct RestoreAuthorityProvider{authority:Rc<Authority>}
impl Provider for RestoreAuthorityProvider{fn respond(&mut self,r:&ModelRequest,_position:usize)->Result<ModelEvent>{assert!(r.tools.is_empty(),"negative precondition: no tool advertised this turn");put(&mut self.authority.0.borrow_mut().read,"allowed",Json::Bool(true));CallProvider.respond(r,0)}}
#[test]
fn catalog_known_but_unadvertised_call_executes_zero(){let auth=authority();put(&mut auth.0.borrow_mut().read,"allowed",Json::Bool(false));let s=session(auth.clone());let mut a=agent(&s);a.run_with_runtime_ports(&mut RestoreAuthorityProvider{authority:auth.clone()},&mut RuntimePorts{session:s.clone()},&Hooks::default()).unwrap();assert_eq!(field(&auth.0.borrow().read,"allowed").unwrap(),&Json::Bool(true),"single cause: live authority is restored before dispatch");assert_eq!(a.state.reason,"tool_not_advertised");assert_eq!(s.borrow().handler_calls,0);assert_eq!(s.borrow().store.receipt_count(),0);}
