mod support;
use support::*;
use muyon_plugin_contract_lab::{Catalog, Json, string};
use muyon_plugin_contract_lab::mappings::{declaration, renamed_equipment, MappingKind};

#[test]
fn native_declarations_register_without_grants_or_reads() {
    let mut catalog=Catalog::new();
    for kind in [MappingKind::Research,MappingKind::Inquiry,MappingKind::Equipment] {
        let mapped=declaration(kind);
        // A compilation/setup failure cannot masquerade as this behavior RED.
        if let Err(code)=&mapped {assert_eq!(code,"native_mapping_unsupported");
            eprintln!("NATIVE_PLUGIN_MAPPING_STUB_REACHED code={code}");}
        assert!(mapped.is_ok(),"RUST_NATIVE_PLUGIN_MAPPING_RED: registered native declaration required");
        let mapped=mapped.unwrap();
        let published=call(&mut catalog,"register",vec![("bundle",mapped.bundle.clone()),("host_bindings",Json::Array(vec![string(&mapped.binding_id)]))]);
        assert!(ok(&published),"valid native mapping must register: {}",published.encode());
        let operations=field(&mapped.bundle,"operations").array().unwrap();assert_eq!(operations.len(),1);
        let operation=&operations[0];
        let module=field(&mapped.bundle,"module_id").string().unwrap();
        let name=field(operation,"name").string().unwrap();
        assert_eq!(mapped.tool_id,format!("{module}.{name}"));
        assert_eq!(mapped.operation,format!("{module}/{name}@1"));
        assert_eq!(field(operation,"binding_id"),&string(&mapped.binding_id));
        let input=field(operation,"input_schema");
        if kind==MappingKind::Equipment {
            assert_eq!(field(input,"required"),&json(r#"["equipment_key"]"#));
            assert!(field(input,"properties").object().unwrap().contains_key("include_loans"));
        } else {
            assert_eq!(field(input,"required"),&json(r#"["type","id"]"#));
            assert!(!field(input,"properties").object().unwrap().contains_key("equipment_key"));
            assert!(field(field(operation,"projection_schema"),"properties").object().unwrap().contains_key("objects"));
        }
        assert!(!field(&mapped.bundle,"relations").array().unwrap().is_empty());
        for view in field(&mapped.bundle,"views").array().unwrap(){
            assert!(!view.object().unwrap().contains_key("handler"));
        }
        let current=stats(&mut catalog);assert_eq!(field(&current,"execution_requests"),&json("0"));
        assert_eq!(field(&current,"grants"),&json("0"));assert_eq!(field(&current,"receipts_created"),&json("0"));
    }
    assert_eq!(field(&stats(&mut catalog),"generation"),&json("3"));
}

#[test]
fn seeded_rename_preserves_closed_schema_and_separate_binding() {
    let original=declaration(MappingKind::Equipment).expect("native declaration required");
    let renamed=renamed_equipment(0x1357).expect("seeded declaration required");
    assert_ne!(original.tool_id,renamed.tool_id);assert_ne!(original.operation,renamed.operation);
    assert_ne!(original.binding_id,renamed.binding_id);
    let encoded=renamed.bundle.encode();
    assert!(!encoded.contains("equipment_loan"));assert!(!encoded.contains("inspect_equipment"));
    assert!(!encoded.contains("host-equipment-read"));
    let mut catalog=Catalog::new();
    for mapped in [original,renamed] {
        assert!(ok(&call(&mut catalog,"register",vec![("bundle",mapped.bundle),("host_bindings",Json::Array(vec![string(mapped.binding_id)]))])));
    }
    let stats=stats(&mut catalog);assert_eq!(field(&stats,"data_count"),&json("4"));
    assert_eq!(field(&stats,"operation_count"),&json("2"));assert_eq!(field(&stats,"execution_requests"),&json("0"));
}

#[test]
fn source_subsets_have_exact_types_relations_and_classification() {
    for (kind,module,types) in [
        (MappingKind::Research,"research",vec!["project","document"]),
        (MappingKind::Inquiry,"inquiry",vec!["supplier","product"]),
    ] {
        let mapped=declaration(kind).expect("native declaration required");
        assert_eq!(field(&mapped.bundle,"module_id"),&string(module));
        let rows=field(&mapped.bundle,"data").array().unwrap();assert_eq!(rows.len(),2);
        assert_eq!(rows.iter().map(|r|field(r,"name").string().unwrap()).collect::<Vec<_>>(),types);
        let op=&field(&mapped.bundle,"operations").array().unwrap()[0];
        assert_eq!(field(field(field(op,"input_schema"),"properties"),"type"),
            &muyon_plugin_contract_lab::object([("type",string("string")),("enum",Json::Array(types.iter().map(|t|string(*t)).collect()))]));
        assert_eq!(field(op,"data_refs"),&Json::Array(types.iter().map(|t|string(format!("{module}/{t}@1"))).collect()));
        for row in rows {
            assert_eq!(field(row,"schema_version"),&json("1"));
            assert_eq!(field(field(row,"schema"),"additionalProperties"),&Json::Bool(false));
            let classifications=field(row,"classification").object().unwrap();
            assert_eq!(classifications.len(),field(field(row,"schema"),"properties").object().unwrap().len());
            for value in classifications.values() {assert_eq!(value,&string(if kind==MappingKind::Research{"none"}else{"unreviewed"}));}
        }
        let relations=field(&mapped.bundle,"relations").array().unwrap();
        if kind==MappingKind::Research {
            assert_eq!(relations.len(),1);let rel=&relations[0];
            assert_eq!(field(rel,"name"),&string("document_project"));
            assert_eq!(field(rel,"from"),&string("research/document@1"));
            assert_eq!(field(rel,"to"),&string("research/project@1"));
            assert_eq!(field(rel,"field"),&string("projectId"));
            let props=field(field(&rows[0],"schema"),"properties").object().unwrap();
            assert_eq!(props.keys().map(String::as_str).collect::<Vec<_>>(),vec!["nextStep","question","title"]);
            assert_eq!(field(field(field(field(&rows[1],"schema"),"properties"),"projectId"),"data_ref"),&string("research/project@1"));
        } else {
            assert_eq!(relations.len(),2);
            for (row,typ) in rows.iter().zip(types.iter()) {
                let props=field(field(row,"schema"),"properties").object().unwrap();
                assert!(!props.contains_key("attributes"));assert!(!props.contains_key("unit_conversions"));assert!(!props.contains_key("source_attachment_ids"));
                assert_eq!(field(&props["merged_into"],"data_ref"),&string(format!("inquiry/{typ}@1")));
                assert!(relations.iter().any(|rel|field(rel,"from")==&string(format!("inquiry/{typ}@1")) && field(rel,"to")==&string(format!("inquiry/{typ}@1")) && field(rel,"field")==&string("merged_into")));
            }
            assert_eq!(field(field(&rows[0],"schema"),"required"),&json(r#"["name"]"#));
            assert_eq!(field(field(&rows[1],"schema"),"required"),&json(r#"["name","unit"]"#));
        }
        // Exact resolved annotation is required, even when another DATA exists.
        let mut invalid=mapped.bundle.clone();put(row(&mut invalid,"relations",0),"to",string(format!("{module}/{}@2",types[0])));
        let mut c=Catalog::new();expect_code(&call(&mut c,"register",vec![("bundle",invalid),("host_bindings",Json::Array(vec![string(&mapped.binding_id)]))]),"unresolved_data");
        assert_eq!(field(&stats(&mut c),"generation"),&json("0"));
        assert!(ok(&call(&mut c,"register",vec![("bundle",mapped.bundle),("host_bindings",Json::Array(vec![string(mapped.binding_id)]))])));
    }
}

#[test]
fn mapped_reads_keep_native_arguments_and_typed_scope() {
    for mapped in [declaration(MappingKind::Research),declaration(MappingKind::Inquiry),declaration(MappingKind::Equipment),renamed_equipment(0x1357)] {
        let mapped=mapped.expect("native declaration required");
        let op=&field(&mapped.bundle,"operations").array().unwrap()[0];
        let input=field(op,"input_schema");let properties=field(input,"properties").object().unwrap();
        let args=if properties.contains_key("type") {
            muyon_plugin_contract_lab::object([("type",field(&properties["type"],"enum").array().unwrap()[0].clone()),("id",string("synthetic-key"))])
        } else {json(r#"{"equipment_key":"synthetic-key","include_loans":true}"#)};
        let mut refs=Vec::new();let projection=sample_projection(field(op,"projection_schema"),&mut refs);
        let mut a=authority();put(&mut a,"bindings",Json::Array(vec![string(&mapped.binding_id)]));put(&mut a,"refs",Json::Array(refs));
        for mode in ["bad_args","foreign_ref","schema_version","valid"] {
            let mut c=Catalog::new();assert!(ok(&call(&mut c,"register",vec![("bundle",mapped.bundle.clone()),("host_bindings",Json::Array(vec![string(&mapped.binding_id)]))])));
            let mut proposed=args.clone();if mode=="bad_args"{put(&mut proposed,"not_a_native_parameter",Json::Bool(true));}
            let prepared=call(&mut c,"prepare",vec![("operation",string(&mapped.operation)),("args",proposed),("authority",a.clone()),("invocation_id",string("mapping-i1")),("receipt_owner",string("ToolRegistry")),("receipt_identity",string("native-owner-identity"))]);
            if mode=="bad_args"{expect_code(&prepared,"extra_property");assert_eq!(field(&stats(&mut c),"execution_requests"),&json("0"));continue}
            assert!(ok(&prepared));let t=field(&prepared,"ticket").clone();let dispatch=invoke(&mut c,t.clone(),a.clone());assert!(ok(&dispatch));assert_eq!(field(field(&dispatch,"dispatch"),"args"),&args);
            let mut p=projection.clone();if mode!="valid"{alter_first_ref(&mut p,if mode=="foreign_ref"{"key"}else{"schema_version"},if mode=="foreign_ref"{string("outside-current-scope")}else{json("2")});}
            let r=muyon_plugin_contract_lab::object([("owner",string("ToolRegistry")),("invocation_id",string("mapping-i1")),("binding_id",string(&mapped.binding_id)),("identity",string("native-owner-identity"))]);
            let accepted=accept(&mut c,t,a.clone(),r.clone(),p.clone());
            if mode=="valid"{assert!(ok(&accepted));assert_eq!(field(&accepted,"receipt_ref"),&r);assert_eq!(field(&accepted,"projection"),&p);}else{expect_code(&accepted,if mode=="foreign_ref"{"result_reference"}else{"result_reference_type"});}
            assert_eq!(field(&stats(&mut c),"receipts_created"),&json("0"));
        }
    }
}

fn sample_projection(schema:&Json,refs:&mut Vec<Json>)->Json {
    if let Some(target)=schema.object().unwrap().get("data_ref") {
        let (name,version)=target.string().unwrap().split_once('@').unwrap();let (module,typ)=name.split_once('/').unwrap();
        let value=muyon_plugin_contract_lab::object([("module_id",string(module)),("type",string(typ)),("key",string("synthetic-key")),("revision",string("object-revision-7")),("schema_version",json(version))]);
        refs.push(value.clone());return value;
    }
    match field(schema,"type").string().unwrap() {
        "object"=>Json::Object(field(schema,"properties").object().unwrap().iter().map(|(k,v)|(k.clone(),sample_projection(v,refs))).collect()),
        "array"=>Json::Array(vec![sample_projection(field(schema,"items"),refs)]),
        "string"=>string("synthetic selected value"),_=>panic!("unexpected fixture projection shape"),
    }
}
fn alter_first_ref(value:&mut Json,key:&str,replacement:Json)->bool {
    if let Json::Object(map)=value {
        if map.contains_key("schema_version"){map.insert(key.into(),replacement);return true}
        for child in map.values_mut(){if alter_first_ref(child,key,replacement.clone()){return true}}
    } else if let Json::Array(items)=value {for child in items {if alter_first_ref(child,key,replacement.clone()){return true}}}
    false
}
