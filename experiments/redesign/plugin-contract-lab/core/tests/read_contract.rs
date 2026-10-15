mod support;
use support::*;
use muyon_plugin_contract_lab::{Json,string};
#[test]
fn prepared_bindings_are_exact() {
 let mut numeric=bundle();let mut input=field(&row(&mut numeric,"operations",0).clone(),"input_schema").clone();let mut props=field(&input,"properties").clone();put(&mut props,"count",json(r#"{"type":"integer"}"#));put(&mut input,"properties",props);put(row(&mut numeric,"operations",0),"input_schema",input);
 for (value,expected) in [("-9007199254740991","-9007199254740991"),("9007199254740991","9007199254740991"),("-0","0")] {
  let mut c=muyon_plugin_contract_lab::Catalog::new();assert!(ok(&register(&mut c,numeric.clone())));
  let p=prepare_args(&mut c,json(&format!(r#"{{"count":{value},"equipment_key":"e1"}}"#)),authority());assert!(ok(&p));
  let r=invoke(&mut c,field(&p,"ticket").clone(),authority());assert_eq!(field(field(&r,"dispatch"),"args").encode(),format!(r#"{{"count":{expected},"equipment_key":"e1"}}"#));
 }
 for value in ["9007199254740992","-9007199254740992","1.0","1e0"] {
  let mut c=muyon_plugin_contract_lab::Catalog::new();assert!(ok(&register(&mut c,numeric.clone())));
  expect_code(&prepare_args(&mut c,json(&format!(r#"{{"equipment_key":"e1","count":{value}}}"#)),authority()),"bounded_integer_required");assert_eq!(field(&stats(&mut c),"execution_requests"),&json("0"));
 }
 let mut typed=bundle();let ref_schema=field(field(field(row(&mut typed,"operations",0),"projection_schema"),"properties"),"equipment").clone();let mut input=field(row(&mut typed,"operations",0),"input_schema").clone();let mut props=field(&input,"properties").clone();put(&mut props,"selected",ref_schema);put(&mut input,"properties",props);put(row(&mut typed,"operations",0),"input_schema",input);
 for in_scope in [false,true] {let mut c=muyon_plugin_contract_lab::Catalog::new();assert!(ok(&register(&mut c,typed.clone())));let mut selected=field(&projection(),"equipment").clone();if !in_scope{put(&mut selected,"key",string("outside"));}let args=muyon_plugin_contract_lab::object([("equipment_key",string("e1")),("selected",selected)]);let result=prepare_args(&mut c,args,authority());if in_scope{assert!(ok(&result))}else{expect_code(&result,"result_reference");}}

 let mut c=admitted();let t=ticket(&mut c);let mut a=authority();let first=row(&mut a,"refs",0);put(first,"revision",string("2"));expect_code(&invoke(&mut c,t,a),"stale_authority");
 let mut c=admitted();let t=ticket(&mut c);let b=json(&bundle().encode().replace("equipment_loan","new_module").replace("host-equipment-read","new_binding"));assert!(ok(&call(&mut c,"register",vec![("bundle",b),("host_bindings",json(r#"["new_binding"]"#))])));expect_code(&invoke(&mut c,t,authority()),"stale_authority");
 let mut old=admitted();let old_ticket=ticket(&mut old);let mut fresh=admitted();let fresh_ticket=ticket(&mut fresh);expect_code(&invoke(&mut fresh,old_ticket,authority()),"unknown_ticket");assert!(ok(&invoke(&mut fresh,fresh_ticket,authority())));

 for key in ["revision","binding_revision","source_revision","rule_revision","scope"] {
 let mut c=admitted();let t=ticket(&mut c);let mut a=authority();put(&mut a,key,string("changed"));assert!(!ok(&invoke(&mut c,t,a)));assert_eq!(field(&stats(&mut c),"execution_requests"),&json("0")); }
 let mut c=admitted();let t=ticket(&mut c);let mut forged=t.clone();if matches!(forged,Json::Object(_)){put(&mut forged,"invocation_id",string("other"));}else{forged=string("forged");}assert!(!ok(&invoke(&mut c,forged,authority())));assert!(ok(&invoke(&mut c,t,authority())));
}
#[test]
fn revoke_before_invoke_executes_zero() {
 let mut c=admitted();let t=ticket(&mut c);let mut a=authority();put(&mut a,"allowed",Json::Bool(false));assert!(!ok(&invoke(&mut c,t,a.clone())));assert_eq!(field(&stats(&mut c),"execution_requests"),&json("0"));
 let mut c=admitted();let t=ticket(&mut c);assert!(ok(&invoke(&mut c,t.clone(),authority())));assert!(!ok(&accept(&mut c,t,a,receipt(),projection())));
}
#[test]
fn ticket_is_one_shot() {let mut c=admitted();let t=ticket(&mut c);assert!(ok(&invoke(&mut c,t.clone(),authority())));assert!(!ok(&invoke(&mut c,t.clone(),authority())));assert!(ok(&accept(&mut c,t.clone(),authority(),receipt(),projection())));assert!(!ok(&accept(&mut c,t,authority(),receipt(),projection())));assert_eq!(field(&stats(&mut c),"execution_requests"),&json("1"));}
#[test]
fn receipt_reference_has_original_owner() {
 for key in ["owner","invocation_id","binding_id","identity"] {let mut c=admitted();let t=ticket(&mut c);assert!(ok(&invoke(&mut c,t.clone(),authority())));let mut r=receipt();put(&mut r,key,string("foreign"));assert!(!ok(&accept(&mut c,t,authority(),r,projection())));}
 let mut c=admitted();let t=ticket(&mut c);assert!(ok(&invoke(&mut c,t.clone(),authority())));let r=accept(&mut c,t,authority(),receipt(),projection());assert!(ok(&r));assert_eq!(field(&r,"receipt_ref"),&receipt());assert_eq!(field(&stats(&mut c),"receipts_created"),&json("0"));
}
#[test]
fn invalid_projection_and_refs_reject() {
 let mut wrong_type=projection();let loan=field(&wrong_type,"loans").array().unwrap()[0].clone();put(&mut wrong_type,"equipment",loan);
 let mut c=admitted();let t=ticket(&mut c);assert!(ok(&invoke(&mut c,t.clone(),authority())));
 expect_code(&accept(&mut c,t,authority(),receipt(),wrong_type),"result_reference_type");
 // Version confusion remains a type error even when that exact ref is in scope.
 let mut p=projection();let mut wrong=field(&p,"equipment").clone();put(&mut wrong,"schema_version",json("2"));put(&mut p,"equipment",wrong.clone());
 let mut a=authority();put(&mut a,"refs",Json::Array(vec![wrong,field(&projection(),"loans").array().unwrap()[0].clone()]));
 let mut c=admitted();let prepared=prepare_args(&mut c,json(r#"{"equipment_key":"e1"}"#),a.clone());assert!(ok(&prepared));let t=field(&prepared,"ticket").clone();assert!(ok(&invoke(&mut c,t.clone(),a.clone())));expect_code(&accept(&mut c,t,a,receipt(),p),"result_reference_type");
 // A business object with a revision field is not implicitly an object ref.
 let mut b=bundle();let mut ps=field(row(&mut b,"operations",0),"projection_schema").clone();let mut props=field(&ps,"properties").clone();put(&mut props,"business",json(r#"{"type":"object","properties":{"revision":{"type":"string"}},"required":["revision"],"additionalProperties":false}"#));put(&mut ps,"properties",props);put(row(&mut b,"operations",0),"projection_schema",ps);
 let mut c=muyon_plugin_contract_lab::Catalog::new();assert!(ok(&register(&mut c,b)));let t=ticket(&mut c);assert!(ok(&invoke(&mut c,t.clone(),authority())));let mut p=projection();put(&mut p,"business",json(r#"{"revision":"business-value"}"#));assert!(ok(&accept(&mut c,t,authority(),receipt(),p)));

 for (key,value) in [("label",json("17")),("extra",string("raw-secret")),("equipment",json(r#"{"module_id":"foreign","type":"equipment","key":"e1","revision":"1","schema_version":1}"#)),("equipment",json(r#"{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"old","schema_version":1}"#))] {
 let mut c=admitted();let t=ticket(&mut c);assert!(ok(&invoke(&mut c,t.clone(),authority())));let mut p=projection();put(&mut p,key,value);assert!(!ok(&accept(&mut c,t,authority(),receipt(),p))); }
}
#[test]
fn cancel_before_dispatch_executes_zero() {let mut c=admitted();let t=ticket(&mut c);assert!(ok(&call(&mut c,"cancel",vec![("ticket",t.clone())])));assert!(!ok(&invoke(&mut c,t,authority())));assert_eq!(field(&stats(&mut c),"execution_requests"),&json("0"));}
#[test]
fn cancel_after_dispatch_accepts_no_projection() {let mut c=admitted();let t=ticket(&mut c);assert!(ok(&invoke(&mut c,t.clone(),authority())));assert!(ok(&call(&mut c,"cancel",vec![("ticket",t.clone())])));assert!(!ok(&accept(&mut c,t,authority(),receipt(),projection())));assert_eq!(field(&stats(&mut c),"receipts_created"),&json("0"));}
#[test]
fn eof_and_concurrency_fail_closed() {
 for bad in [r#"{"command":"inspect"}"#,r#"{"protocol_version":2,"command":"inspect"}"#,r#"{"protocol_version":1,"command":"inspect","grant":true}"#] {
  let replies=wire(&format!("{bad}\n"));assert_eq!(replies.len(),1);assert!(!ok(&replies[0]),"WIRE_PROTOCOL_FAULT_MUST_REFUSE: {bad}");
 }
 let register_request=muyon_plugin_contract_lab::object([("protocol_version",json("1")),("command",string("register")),("bundle",bundle()),("host_bindings",json(r#"["host-equipment-read"]"#))]);
 let prepare_request=muyon_plugin_contract_lab::object([("protocol_version",json("1")),("command",string("prepare")),("operation",string("equipment_loan/inspect_equipment@1")),("args",json(r#"{"equipment_key":"e1"}"#)),("authority",authority()),("invocation_id",string("i1")),("receipt_owner",string("ToolRegistry")),("receipt_identity",string("owner-digest"))]);
 for bad in [r#"{"protocol_version":1}"#,r#"{"protocol_version":1,"command":7}"#] {
  let lines=format!("{}\n{}\n{bad}\n{{\"protocol_version\":1,\"command\":\"inspect\"}}\n",register_request.encode(),prepare_request.encode());
  let replies=wire(&lines);assert_eq!(replies.len(),3,"INVALID_ENVELOPE_MUST_END_PREPARED_SESSION: {bad}");assert!(ok(&replies[0]));assert!(ok(&replies[1]));expect_code(&replies[2],"protocol_envelope");
 }
 // Actual stdin EOF while a prepared ticket exists: helper observes bounded
 // process exit. A new child cannot inherit that transient Catalog.
 let eof=wire(&format!("{}\n{}\n",register_request.encode(),prepare_request.encode()));assert_eq!(eof.len(),2);assert!(ok(&eof[0]));assert!(ok(&eof[1]));
 let old_ticket=field(&eof[1],"ticket").clone();let invoke_old=muyon_plugin_contract_lab::object([("protocol_version",json("1")),("command",string("invoke")),("ticket",old_ticket),("authority",authority())]);
 let fresh=wire(&format!("{}\n{}\n",register_request.encode(),invoke_old.encode()));assert_eq!(fresh.len(),2);assert!(ok(&fresh[0]));expect_code(&fresh[1],"unknown_ticket");
 let lines=format!("{}\n{}\n{{\"command\":\"inspect\",\"command\":\"inspect\"}}\n{{\"protocol_version\":1,\"command\":\"inspect\"}}\n",register_request.encode(),prepare_request.encode());
 let replies=wire(&lines);assert_eq!(replies.len(),3,"protocol fault must terminate the child session before another request");assert!(ok(&replies[0]));assert!(ok(&replies[1]));expect_code(&replies[2],"invalid_json");
 let oversized=wire(&format!("{}\n", "x".repeat(65537)));assert_eq!(oversized.len(),1);assert!(oversized[0].encode().len()<256);assert!(!ok(&oversized[0]));
let mut c=admitted();let t=ticket(&mut c);assert!(!ok(&prepare(&mut c)),"one pending read only");assert!(ok(&call(&mut c,"close",vec![])));assert!(!ok(&invoke(&mut c,t,authority())));let s=stats(&mut c);assert_eq!(field(&s,"pending"),&json("0"));assert_eq!(field(&s,"execution_requests"),&json("0"));}

fn wire(lines:&str)->Vec<muyon_plugin_contract_lab::Json> {
 use std::process::{Command,Stdio};use std::io::{Read,Write};use std::time::{Duration,Instant};use std::sync::mpsc;
 struct OwnedChild(std::process::Child);
 impl Drop for OwnedChild {fn drop(&mut self){
  if self.0.try_wait().ok().flatten().is_some(){return}
  // A panicking test kills only its owned child and polls to reap it.
  let _=self.0.kill();let until=Instant::now()+Duration::from_secs(1);
  while self.0.try_wait().ok().flatten().is_none() && Instant::now()<until {std::thread::sleep(Duration::from_millis(5));}
 }}
 let mut owned=OwnedChild(Command::new(env!("CARGO_BIN_EXE_muyon-plugin-contract-lab")).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().unwrap());
 let child=&mut owned.0;
 let mut input=child.stdin.take().unwrap();let output=child.stdout.take().unwrap();let owned=lines.as_bytes().to_vec();
 let (tx,rx)=mpsc::channel();
 std::thread::spawn(move||{let _=input.write_all(&owned);drop(input);});
 std::thread::spawn(move||{let mut bytes=Vec::new();let result=output.take(1048577).read_to_end(&mut bytes);let _=tx.send((result,bytes));});
 let deadline=Instant::now()+Duration::from_secs(5);
 let status=loop {
  if let Some(status)=child.try_wait().unwrap(){break status}
  if Instant::now()>=deadline {let _=child.kill();let cleanup=Instant::now()+Duration::from_secs(1);
   while child.try_wait().unwrap().is_none() && Instant::now()<cleanup{std::thread::sleep(Duration::from_millis(5));}
   panic!("owned wire child exceeded bounded deadline");
  }
  std::thread::sleep(Duration::from_millis(5));
 };
 let (result,bytes)=rx.recv_timeout(Duration::from_secs(1)).expect("bounded stdout collection");result.unwrap();assert!(bytes.len()<=1048576);assert!(status.success());
 String::from_utf8(bytes).unwrap().lines().map(json).collect()
}
