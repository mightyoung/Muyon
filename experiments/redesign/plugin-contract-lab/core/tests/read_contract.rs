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
 for (key,value) in [("label",json("17")),("extra",string("raw-secret")),("equipment",json(r#"{"module_id":"foreign","type":"equipment","key":"e1","revision":"1"}"#)),("equipment",json(r#"{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"old"}"#))] {
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
 let lines=format!("{}\n{}\n{{\"command\":\"inspect\",\"command\":\"inspect\"}}\n{{\"protocol_version\":1,\"command\":\"inspect\"}}\n",register_request.encode(),prepare_request.encode());
 let replies=wire(&lines);assert_eq!(replies.len(),3,"protocol fault must terminate the child session before another request");assert!(ok(&replies[0]));assert!(ok(&replies[1]));expect_code(&replies[2],"invalid_json");
 let oversized=wire(&format!("{}\n", "x".repeat(65537)));assert_eq!(oversized.len(),1);assert!(oversized[0].encode().len()<256);assert!(!ok(&oversized[0]));
let mut c=admitted();let t=ticket(&mut c);assert!(!ok(&prepare(&mut c)),"one pending read only");assert!(ok(&call(&mut c,"close",vec![])));assert!(!ok(&invoke(&mut c,t,authority())));let s=stats(&mut c);assert_eq!(field(&s,"pending"),&json("0"));assert_eq!(field(&s,"execution_requests"),&json("0"));}

fn wire(lines:&str)->Vec<muyon_plugin_contract_lab::Json> {
 use std::process::{Command,Stdio};use std::io::Write;
 let mut child=Command::new(env!("CARGO_BIN_EXE_muyon-plugin-contract-lab")).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
 let mut input=child.stdin.take().unwrap();let _=input.write_all(lines.as_bytes());drop(input);
 let output=child.wait_with_output().unwrap();assert!(output.status.success());
 String::from_utf8(output.stdout).unwrap().lines().map(json).collect()
}
