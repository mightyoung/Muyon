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
