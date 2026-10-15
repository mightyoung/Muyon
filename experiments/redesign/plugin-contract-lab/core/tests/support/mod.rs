#![allow(dead_code)]
use muyon_plugin_contract_lab::{Catalog, Json, parse, object, string};
pub fn json(s: &str) -> Json { parse(s.as_bytes()).unwrap() }
pub fn bundle() -> Json { json(include_str!("../../../fixtures/equipment_loan.json")) }
pub fn field<'a>(j: &'a Json, k: &str) -> &'a Json { &j.object().unwrap()[k] }
pub fn put(j: &mut Json, k: &str, value: Json) { if let Json::Object(m) = j { m.insert(k.into(), value); } else { panic!("fixture object") } }
pub fn row<'a>(j: &'a mut Json, key: &str, index: usize) -> &'a mut Json {
    if let Json::Object(m) = j { if let Json::Array(a) = m.get_mut(key).unwrap() { return &mut a[index]; } }
    panic!("fixture array")
}
pub fn call(c: &mut Catalog, command: &str, fields: Vec<(&str, Json)>) -> Json {
    let mut request = object(fields); put(&mut request, "command", string(command)); c.handle(request)
}
pub fn ok(j: &Json) -> bool { j.object().unwrap().get("ok") == Some(&Json::Bool(true)) }
pub fn authority() -> Json { json(r#"{"allowed":true,"revision":"a1","binding_revision":"b1","source_revision":"s1","rule_revision":"r1","scope":"selected-e1","refs":[{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"1"},{"module_id":"equipment_loan","type":"loan","key":"l1","revision":"1"}]}"#) }
pub fn register(c: &mut Catalog, b: Json) -> Json { call(c,"register",vec![("bundle",b),("host_bindings",json(r#"["host-equipment-read"]"#))]) }
pub fn admitted() -> Catalog { let mut c=Catalog::new(); assert!(ok(&register(&mut c,bundle())),"valid fixture must register"); c }
pub fn prepare(c: &mut Catalog) -> Json {
    call(c,"prepare",vec![("operation",string("equipment_loan/inspect_equipment@1")),("args",json(r#"{"equipment_key":"e1","include_loans":true}"#)),("authority",authority()),("invocation_id",string("i1")),("receipt_owner",string("ToolRegistry"))])
}
pub fn ticket(c: &mut Catalog) -> Json { let p=prepare(c); assert!(ok(&p),"valid read must prepare"); field(&p,"ticket").clone() }
pub fn invoke(c: &mut Catalog, t: Json, a: Json) -> Json { call(c,"invoke",vec![("ticket",t),("authority",a)]) }
pub fn projection() -> Json { json(r#"{"equipment":{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"1"},"label":"synthetic drill","loans":[{"module_id":"equipment_loan","type":"loan","key":"l1","revision":"1"}]}"#) }
pub fn receipt() -> Json { json(r#"{"owner":"ToolRegistry","invocation_id":"i1","binding_id":"host-equipment-read","identity":"host-sha256-identity"}"#) }
pub fn accept(c:&mut Catalog,t:Json,a:Json,r:Json,p:Json)->Json { call(c,"accept_result",vec![("ticket",t),("authority",a),("receipt_ref",r),("projection",p)]) }
pub fn stats(c:&mut Catalog)->Json { call(c,"inspect",vec![]) }
