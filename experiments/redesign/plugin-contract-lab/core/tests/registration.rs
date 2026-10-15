mod support;
use support::*;
use muyon_plugin_contract_lab::{Catalog,Json,string};
#[test]
fn atomic_registration_publishes_only_valid_bundle() {
 let mut c=Catalog::new(); let result=register(&mut c,bundle());
 assert!(ok(&result),"PLUGIN_SLICE_RED_RUST_ATOMIC_PUBLICATION: valid atomic bundle must publish");
 assert_eq!(field(&result,"generation"),&json("1"));
 let before=stats(&mut c); let mut invalid=bundle(); put(&mut invalid,"module_id",string("another")); put(row(&mut invalid,"views",0),"operation_refs",json(r#"["missing/read@1"]"#));
 assert!(!ok(&register(&mut c,invalid))); assert_eq!(stats(&mut c),before);
 assert_eq!(field(&before,"data_count"),&json("2")); assert_eq!(field(&before,"operation_count"),&json("1"));
}
#[test]
fn registration_neither_grants_nor_reads() {
 let mut c=admitted(); let s=stats(&mut c); assert_eq!(field(&s,"execution_requests"),&json("0")); assert_eq!(field(&s,"grants"),&json("0"));
 let mut denied=authority(); put(&mut denied,"allowed",Json::Bool(false)); let d=call(&mut c,"discover",vec![("authority",denied)]); assert_eq!(field(&d,"operations"),&json("[]"));
}
#[test]
fn namespace_duplicates_and_versions_reject() {
 let mut c=admitted(); let before=stats(&mut c); assert!(!ok(&register(&mut c,bundle())));
 for (key,value) in [("module_id",string("bad/name")),("protocol_version",json("2"))] {let mut b=bundle();put(&mut b,key,value);assert!(!ok(&register(&mut c,b)));}
 let mut b=bundle(); put(row(&mut b,"data",0),"schema_version",json("0")); assert!(!ok(&register(&mut c,b))); assert_eq!(stats(&mut c),before);
}
#[test]
fn schema_subset_and_limits_fail_closed() {
 for schema in [r#"{"type":"object","additionalProperties":true}"#,r#"{"type":"object","properties":{},"required":["ghost"],"additionalProperties":false}"#,r#"{"type":"string","pattern":".*"}"#] {
  let mut c=Catalog::new();let mut b=bundle();put(row(&mut b,"data",0),"schema",json(schema));assert!(!ok(&register(&mut c,b)));
 }
 assert!(muyon_plugin_contract_lab::parse(br#"{"x":1,"x":2}"#).is_err());
 let mut c=admitted(); for bad in [json(r#"{"equipment_key":9}"#),json(r#"{"equipment_key":"e1","extra":true}"#),json(r#"{"equipment_key":"e1","include_loans":1e0}"#)] {
 let p=call(&mut c,"prepare",vec![("operation",string("equipment_loan/inspect_equipment@1")),("args",bad),("authority",authority())]);assert!(!ok(&p)); }
 let huge=string("x".repeat(65537));assert!(!ok(&call(&mut c,"register",vec![("bundle",huge)])));
}
#[test]
fn relation_and_view_refs_must_resolve() {
 for (array,key) in [("relations","to"),("relations","from"),("views","data_refs")] {
  let mut c=Catalog::new();let mut b=bundle(); let value=if key=="data_refs" {json(r#"["foreign/data@99"]"#)} else {string("foreign/data@99")}; put(row(&mut b,array,0),key,value);assert!(!ok(&register(&mut c,b)));
 }
 let mut c=admitted(); let s=stats(&mut c); assert_eq!(field(&s,"view_count"),&json("1"));assert_eq!(field(&s,"execution_requests"),&json("0"));
}
#[test]
fn discovery_filters_current_authority() {
 let mut c=admitted(); let visible=call(&mut c,"discover",vec![("authority",authority())]); assert_eq!(field(&visible,"operations").array().unwrap().len(),1);assert!(!visible.object().unwrap().contains_key("ticket"));
 for key in ["allowed","available","scope_allowed"] {let mut a=authority();put(&mut a,key,Json::Bool(false));assert_eq!(field(&call(&mut c,"discover",vec![("authority",a)]),"operations"),&json("[]"));}
}
#[test]
fn declaration_labels_cannot_authorize() {
 for key in ["grant","trusted","clean"] {let mut c=Catalog::new();let mut b=bundle();put(&mut b,key,Json::Bool(true));assert!(!ok(&register(&mut c,b)));}
 let mut c=admitted();let mut a=authority();put(&mut a,"allowed",Json::Bool(false));assert_eq!(field(&call(&mut c,"discover",vec![("authority",a)]),"operations"),&json("[]"));
}
#[test]
fn renamed_bundle_is_semantically_equivalent() {
 let seed=0x1357_u32.wrapping_mul(1664525).wrapping_add(1013904223);let name=format!("module_{seed:x}");
 let renamed=bundle().encode().replace("equipment_loan",&name).replace("inspect_equipment","inspect_random").replace("host-equipment-read","opaque-random");
 let mut c=Catalog::new();let r=call(&mut c,"register",vec![("bundle",json(&renamed)),("host_bindings",json(r#"["opaque-random"]"#))]);assert!(ok(&r));
 let a=json(&authority().encode().replace("equipment_loan",&name));let d=call(&mut c,"discover",vec![("authority",a)]);assert_eq!(field(&d,"operations").array().unwrap().len(),1);
}
