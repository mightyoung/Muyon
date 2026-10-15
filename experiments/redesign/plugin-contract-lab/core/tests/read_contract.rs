mod support;
use support::*;
use muyon_plugin_contract_lab::{Json,string};
#[test]
fn prepared_bindings_are_exact() {
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
 for (key,value) in [("label",json("17")),("extra",string("raw-secret")),("equipment",json(r#"{"module_id":"foreign","type":"equipment","key":"e1","revision":"1"}"#)),("equipment",json(r#"{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"old"}"#))] {
 let mut c=admitted();let t=ticket(&mut c);assert!(ok(&invoke(&mut c,t.clone(),authority())));let mut p=projection();put(&mut p,key,value);assert!(!ok(&accept(&mut c,t,authority(),receipt(),p))); }
}
#[test]
fn cancel_before_dispatch_executes_zero() {let mut c=admitted();let t=ticket(&mut c);assert!(ok(&call(&mut c,"cancel",vec![("ticket",t.clone())])));assert!(!ok(&invoke(&mut c,t,authority())));assert_eq!(field(&stats(&mut c),"execution_requests"),&json("0"));}
#[test]
fn cancel_after_dispatch_accepts_no_projection() {let mut c=admitted();let t=ticket(&mut c);assert!(ok(&invoke(&mut c,t.clone(),authority())));assert!(ok(&call(&mut c,"cancel",vec![("ticket",t.clone())])));assert!(!ok(&accept(&mut c,t,authority(),receipt(),projection())));assert_eq!(field(&stats(&mut c),"receipts_created"),&json("0"));}
#[test]
fn eof_and_concurrency_fail_closed() {let mut c=admitted();let t=ticket(&mut c);assert!(!ok(&prepare(&mut c)),"one pending read only");assert!(ok(&call(&mut c,"close",vec![])));assert!(!ok(&invoke(&mut c,t,authority())));let s=stats(&mut c);assert_eq!(field(&s,"pending"),&json("0"));assert_eq!(field(&s,"execution_requests"),&json("0"));}
