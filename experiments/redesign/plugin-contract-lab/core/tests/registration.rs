mod support;
use support::*;
use muyon_plugin_contract_lab::{Catalog,Json,string};
#[test]
fn atomic_registration_publishes_only_valid_bundle() {
 let mut c=Catalog::new(); let result=register(&mut c,bundle());
 assert!(ok(&result),"PLUGIN_SLICE_RED_RUST_ATOMIC_PUBLICATION: valid atomic bundle must publish");
 assert_eq!(field(&result,"generation"),&json("1"));
 let before=stats(&mut c);
 // Rename the entire namespace and binding, including all self references.
 // The only invalid field is the last view's operation reference.
 let valid_second=json(&bundle().encode().replace("equipment_loan","another").replace("host-equipment-read","host-another-read"));
 let second_bindings=json(r#"["host-another-read"]"#);
 let mut invalid=valid_second.clone();
 put(row(&mut invalid,"views",0),"operation_refs",json(r#"["another/missing@1"]"#));
 let rejected=call(&mut c,"register",vec![("bundle",invalid),("host_bindings",second_bindings.clone())]);
 assert!(!ok(&rejected)); assert_eq!(stats(&mut c),before);
 assert_eq!(field(&before,"data_count"),&json("2")); assert_eq!(field(&before,"operation_count"),&json("1"));
 // Repair only that tail: acceptance proves no other admission error caused
 // the negative result, and failed publication reserved no namespace/binding.
 let repaired=call(&mut c,"register",vec![("bundle",valid_second),("host_bindings",second_bindings)]);
 assert!(ok(&repaired),"the otherwise identical second bundle must publish after repairing only its last view");
 assert_eq!(field(&repaired,"generation"),&json("2"));
}
#[test]
fn registration_neither_grants_nor_reads() {
 let mut c=admitted(); let s=stats(&mut c); assert_eq!(field(&s,"execution_requests"),&json("0")); assert_eq!(field(&s,"grants"),&json("0"));
 let mut denied=authority(); put(&mut denied,"allowed",Json::Bool(false)); let d=call(&mut c,"discover",vec![("authority",denied)]); assert_eq!(field(&d,"operations"),&json("[]"));
}
#[test]
fn namespace_duplicates_and_versions_reject() {
 let mut c=admitted(); let before=stats(&mut c);expect_code(&register(&mut c,bundle()),"module_identity");assert_eq!(stats(&mut c),before);
 for (key,value,code) in [("module_id",string("bad/name"),"module_identity"),("protocol_version",json("2"),"protocol_version")] {
  let mut fresh=Catalog::new();let mut b=bundle();put(&mut b,key,value);expect_code(&register(&mut fresh,b),code);
 }
 let mut fresh=Catalog::new();let mut b=bundle();put(row(&mut b,"data",0),"schema_version",json("0"));expect_code(&register(&mut fresh,b),"schema_version");
}

#[test]
fn schema_subset_and_limits_fail_closed() {
 for schema in [r#"{"type":"object","additionalProperties":true}"#,r#"{"type":"object","properties":{},"required":["ghost"],"additionalProperties":false}"#,r#"{"type":"string","pattern":".*"}"#] {
  let mut c=Catalog::new();let mut b=bundle();put(row(&mut b,"data",0),"schema",json(schema));assert!(!ok(&register(&mut c,b)));
 }
 assert!(muyon_plugin_contract_lab::parse(br#"{"x":1,"x":2}"#).is_err());
 let mut c=admitted(); for (bad,code) in [(json(r#"{"equipment_key":9}"#),"string_required"),(json(r#"{"equipment_key":"e1","extra":true}"#),"extra_property"),(json(r#"{"equipment_key":"e1","include_loans":1e0}"#),"bounded_integer_required")] {
 let p=prepare_args(&mut c,bad,authority());expect_code(&p,code); }

 let huge=string("x".repeat(65537));assert!(!ok(&call(&mut c,"register",vec![("bundle",huge)])));
}
#[test]
fn relation_and_view_refs_must_resolve() {
 for (array,key) in [("relations","to"),("relations","from"),("views","data_refs")] {
  let mut c=Catalog::new();let mut b=bundle(); let value=if key=="data_refs" {json(r#"["foreign/data@99"]"#)} else {string("foreign/data@99")}; put(row(&mut b,array,0),key,value);assert!(!ok(&register(&mut c,b)));
 }
 let mut missing=bundle();
 if let Json::Object(data)=row(&mut missing,"data",1) {if let Json::Object(schema)=data.get_mut("schema").unwrap() {if let Json::Object(props)=schema.get_mut("properties").unwrap() {remove(props.get_mut("equipment").unwrap(),"data_ref");}}}
 let mut probe=Catalog::new();expect_code(&register(&mut probe,missing),"reference_schema_required");
 let mut c=admitted(); let s=stats(&mut c); assert_eq!(field(&s,"view_count"),&json("1"));assert_eq!(field(&s,"execution_requests"),&json("0"));
}
#[test]
fn discovery_filters_current_authority() {
 let mut c=admitted();
 for missing in ["available","scope_allowed","bindings","revision","binding_revision","source_revision","rule_revision","scope","refs"] {
  let mut a=authority();remove(&mut a,missing);
  let d=call(&mut c,"discover",vec![("authority",a.clone())]);
  assert_eq!(field(&d,"operations"),&json("[]"),"MISSING_AUTHORITY_MUST_DENY: {missing}");
  expect_code(&prepare_args(&mut c,json(r#"{"equipment_key":"e1"}"#),a),"denied");
  assert_eq!(field(&stats(&mut c),"execution_requests"),&json("0"));
 }
 for key in ["allowed","available","scope_allowed","bindings","revision","binding_revision","source_revision","rule_revision","scope","refs"] {
  for value in [Json::Null,json("7")] {let mut a=authority();put(&mut a,key,value);let d=call(&mut c,"discover",vec![("authority",a)]);assert_eq!(field(&d,"operations"),&json("[]"),"wrong type: {key}");}
 }
 let mut second=json(&bundle().encode().replace("equipment_loan","other_module").replace("host-equipment-read","other_binding"));
 put(&mut second,"views",json("[]"));assert!(ok(&call(&mut c,"register",vec![("bundle",second),("host_bindings",json(r#"["other_binding"]"#))])));
 let limited=call(&mut c,"discover",vec![("authority",authority())]);assert_eq!(field(&limited,"operations").array().unwrap().len(),1);
 assert_eq!(field(&limited,"schemas").object().unwrap().len(),2,"only the admitted operation's referenced DATA closure");
 assert!(field(&limited,"schemas").object().unwrap().keys().all(|k|k.starts_with("equipment_loan/")));
 let mut unknown=authority();put(&mut unknown,"plugin_grant",Json::Bool(true));
 assert_eq!(field(&call(&mut c,"discover",vec![("authority",unknown)]),"operations"),&json("[]"));
 let visible=call(&mut c,"discover",vec![("authority",authority())]); assert_eq!(field(&visible,"operations").array().unwrap().len(),1);assert!(!visible.object().unwrap().contains_key("ticket"));
 for key in ["allowed","available","scope_allowed"] {let mut a=authority();put(&mut a,key,Json::Bool(false));assert_eq!(field(&call(&mut c,"discover",vec![("authority",a)]),"operations"),&json("[]"));}
 let mut large=Catalog::new();let mut all_bindings=Vec::new();
 for index in 0..8 {
  let module=format!("module_{index}");let mut b=json(&bundle().encode().replace("equipment_loan",&module));let original=field(&b,"operations").array().unwrap()[0].clone();let mut ops=Vec::new();let mut ids=Vec::new();
  for n in 0..8 {let binding=format!("binding_{index}_{n}");let mut op=original.clone();put(&mut op,"name",string(format!("read_{n}")));put(&mut op,"binding_id",string(&binding));
   let mut input=field(&op,"input_schema").clone();let mut props=field(&input,"properties").clone();put(&mut props,"equipment_key",muyon_plugin_contract_lab::object([("type",string("string")),("enum",Json::Array(vec![string("x".repeat(3500))]))]));put(&mut input,"properties",props);put(&mut op,"input_schema",input);ops.push(op);ids.push(string(&binding));all_bindings.push(string(binding));
  }
  put(&mut b,"operations",Json::Array(ops));put(&mut b,"views",json("[]"));assert!(ok(&call(&mut large,"register",vec![("bundle",b),("host_bindings",Json::Array(ids))])));
 }
 let mut a=authority();put(&mut a,"bindings",Json::Array(all_bindings));let out=call(&mut large,"discover",vec![("authority",a)]);expect_code(&out,"response_limit");assert!(out.encode().len()<256);assert!(!out.object().unwrap().contains_key("operations"));
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
 let a=json(&authority().encode().replace("equipment_loan",&name).replace("host-equipment-read","opaque-random"));let d=call(&mut c,"discover",vec![("authority",a)]);assert_eq!(field(&d,"operations").array().unwrap().len(),1);
}

#[test]
fn foreign_data_admission_requires_the_referenced_schema_closure() {
 // The foreign loan schema references equipment. An explicit loan admission
 // must not implicitly admit equipment when discovery expands that closure.
 let mut consumer=bundle();
 put(&mut consumer,"module_id",string("consumer"));
 put(&mut consumer,"data",json("[]"));
 put(&mut consumer,"relations",json("[]"));
 put(&mut consumer,"views",json("[]"));
 let op=row(&mut consumer,"operations",0);
 put(op,"binding_id",string("consumer-read"));
 put(op,"data_refs",json(r#"["equipment_loan/loan@1"]"#));
 let mut projection=field(op,"projection_schema").clone();
 let mut properties=field(&projection,"properties").clone();
 remove(&mut properties,"equipment");remove(&mut properties,"label");
 put(&mut projection,"properties",properties);
 put(&mut projection,"required",json(r#"["loans"]"#));
 put(op,"projection_schema",projection);
 let mut catalog=admitted();let before=stats(&mut catalog);
 for admissions in [json("[]"),json(r#"["equipment_loan/loan@1"]"#),json(r#"["equipment_loan/loan@1","equipment_loan/equipment@2"]"#)] {
  let result=call(&mut catalog,"register",vec![("bundle",consumer.clone()),("host_bindings",json(r#"["consumer-read"]"#)),("host_data_admissions",admissions)]);
  expect_code(&result,"unresolved_data");
  assert_eq!(stats(&mut catalog),before,"rejection must not reserve module, binding or generation");
 }
 // Repair only the host admission list, retaining the exact same bundle.
 let result=call(&mut catalog,"register",vec![("bundle",consumer),("host_bindings",json(r#"["consumer-read"]"#)),("host_data_admissions",json(r#"["equipment_loan/loan@1","equipment_loan/equipment@1"]"#))]);
 assert!(ok(&result),"complete explicit foreign closure must register: {}",result.encode());
 let mut a=authority();put(&mut a,"bindings",json(r#"["consumer-read"]"#));
 let discovered=call(&mut catalog,"discover",vec![("authority",a)]);
 assert_eq!(field(&discovered,"operations").array().unwrap().len(),1);
 assert_eq!(field(&discovered,"schemas").object().unwrap().keys().map(String::as_str).collect::<Vec<_>>(),vec!["equipment_loan/equipment@1","equipment_loan/loan@1"]);
 let s=stats(&mut catalog);assert_eq!(field(&s,"generation"),&json("2"));
 for key in ["execution_requests","grants","receipts_created"] {assert_eq!(field(&s,key),&json("0"));}
}
