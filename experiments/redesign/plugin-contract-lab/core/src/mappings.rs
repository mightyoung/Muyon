//! Private source-backed native declaration subsets. No runtime, grant or
//! receipt is installed by these pure constructors. See fixtures/MAPPINGS.md.
use crate::{parse, Json, Result};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MappingKind { Research, Inquiry, Equipment }

#[derive(Clone, Debug)]
pub struct ReadDeclaration {
    pub bundle: Json,
    pub tool_id: String,
    pub operation: String,
    pub binding_id: String,
}

impl ReadDeclaration {
    fn from_bundle(bundle: Json) -> Result<Self> {
        let module=crate::schema::text(&bundle,"module_id")?;
        let operations=crate::schema::array(&bundle,"operations")?;
        if operations.len()!=1{return Err("mapping_operation_count".into())}
        let op=&operations[0];
        let name=crate::schema::text(op,"name")?;
        let version=crate::schema::version(crate::schema::get(op,"schema_version")?)?;
        let binding_id=crate::schema::text(op,"binding_id")?;
        Ok(Self{tool_id:format!("{module}.{name}"),operation:format!("{module}/{name}@{version}"),binding_id,bundle})
    }
}

pub fn declaration(kind: MappingKind) -> Result<ReadDeclaration> {
    let source=match kind {
        MappingKind::Research=>include_str!("../../fixtures/research_read.json"),
        MappingKind::Inquiry=>include_str!("../../fixtures/inquiry_read.json"),
        MappingKind::Equipment=>include_str!("../../fixtures/equipment_loan.json"),
    };
    ReadDeclaration::from_bundle(parse(source.as_bytes())?)
}

/// A synthetic metamorphic fixture. Only this fixture constructor knows the
/// old names; Agent/provider/authorization dispatch must not know them.
pub fn renamed_equipment(seed: u32) -> Result<ReadDeclaration> {
    let suffix=format!("{:x}",seed.wrapping_mul(1664525).wrapping_add(1013904223));
    let module=format!("module_{suffix}");let operation=format!("read_{suffix}");
    let binding=format!("binding_{suffix}");
    fn rewrite(value: Json,module:&str,operation:&str,binding:&str,suffix:&str)->Json {
        match value {
            Json::String(s)=>Json::String(match s.as_str(){
                "equipment_loan"=>module.into(),"inspect_equipment"=>operation.into(),
                "host-equipment-read"=>binding.into(),"equipment"=>"asset".into(),"loan"=>"lease".into(),
                "loan_equipment"=>format!("relation_{suffix}"),"equipment_details"=>format!("view_{suffix}"),
                "equipment_loan/equipment@1"=>format!("{module}/asset@1"),
                "equipment_loan/loan@1"=>format!("{module}/lease@1"),
                "equipment_loan/inspect_equipment@1"=>format!("{module}/{operation}@1"),_=>s,
            }),
            Json::Array(items)=>Json::Array(items.into_iter().map(|v|rewrite(v,module,operation,binding,suffix)).collect()),
            Json::Object(fields)=>Json::Object(fields.into_iter().map(|(k,v)|
                (if k=="equipment"{"asset".into()}else{k},rewrite(v,module,operation,binding,suffix))).collect()),
            value=>value,
        }
    }
    let original=declaration(MappingKind::Equipment)?.bundle;
    ReadDeclaration::from_bundle(rewrite(original,&module,&operation,&binding,&suffix))
}
