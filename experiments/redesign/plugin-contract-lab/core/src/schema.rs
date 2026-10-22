use crate::{Json, Result};
use std::collections::BTreeMap;

pub fn map(j: &Json) -> Result<&BTreeMap<String, Json>> { j.object().map_err(|_| "object_required".into()) }
pub fn get<'a>(j: &'a Json, key: &str) -> Result<&'a Json> { map(j)?.get(key).ok_or_else(|| format!("missing_{key}")) }
pub fn text(j: &Json, key: &str) -> Result<String> { Ok(get(j,key)?.string().map_err(|_| "string_required")?.to_owned()) }
pub fn array<'a>(j: &'a Json,key:&str)->Result<&'a [Json]> { get(j,key)?.array().map_err(|_| "array_required".into()) }
pub fn keys(j:&Json, allowed:&[&str], required:&[&str])->Result<()> {
 let m=map(j)?; if m.keys().any(|k| !allowed.contains(&k.as_str())) || required.iter().any(|k| !m.contains_key(*k)) { return Err("unexpected_or_missing_field".into()); } Ok(())
}
pub fn name(s:&str)->bool { !s.is_empty() && s.len()<=64 && s.as_bytes()[0].is_ascii_lowercase() && s.bytes().all(|b| b.is_ascii_lowercase()||b.is_ascii_digit()||b==b'_') }
pub fn version(j:&Json)->Result<u64> { let n=j.integer().map_err(|_| "schema_version")?; if n==0 {Err("schema_version".into())}else{Ok(n)} }
pub fn bounded(j:&Json)->Result<()> {
 fn walk(j:&Json,depth:usize,nodes:&mut usize)->Result<()> {
  *nodes+=1; if *nodes>4096 || depth>16 {return Err("structure_limit".into());}
  match j {
   Json::String(s) if s.len()>4096 => return Err("string_limit".into()),
   Json::Array(a) => {if a.len()>128{return Err("array_limit".into())}for v in a {walk(v,depth+1,nodes)?}},
   Json::Object(m)=>for(k,v)in m {if k.len()>4096{return Err("string_limit".into())}walk(v,depth+1,nodes)?},
   _=>{}
  } Ok(())
 }
 if j.encoded_len().map_err(|_|"frame_limit")?>65536{return Err("frame_limit".into())}walk(j,0,&mut 0)
}
pub fn integer(j:&Json)->Result<i64> {
 if let Json::Number(s)=j {if s.bytes().all(|b|b.is_ascii_digit()||b==b'-') {if let Ok(n)=s.parse::<i64>() {if (-9007199254740991..=9007199254740991).contains(&n){return Ok(n)}}}}
 Err("bounded_integer_required".into())
}
pub fn canonical(j:&Json)->Result<Json> {
 Ok(match j {
  Json::Number(_)=>Json::Number(integer(j)?.to_string()),
  Json::Array(a)=>Json::Array(a.iter().map(canonical).collect::<Result<_>>()?),
  Json::Object(m)=>Json::Object(m.iter().map(|(k,v)|Ok((k.clone(),canonical(v)?))).collect::<Result<_>>()?),
  _=>j.clone()
 })
}
pub fn check(s:&Json)->Result<()> {
 match text(s,"type")?.as_str() {
  "object"=>{keys(s,&["type","properties","required","additionalProperties","data_ref"],&["type","properties","required","additionalProperties"])?;
   if get(s,"additionalProperties")? != &Json::Bool(false){return Err("closed_schema_required".into())}
   let p=map(get(s,"properties")?)?;for schema in p.values(){check(schema)?}
   if let Some(target)=map(s)?.get("data_ref") {
    let target=target.string().map_err(|_|"reference_schema_required")?;
    let (qualified,version_text)=target.rsplit_once('@').ok_or("reference_schema_required")?;
    let (module,typ)=qualified.split_once('/').ok_or("reference_schema_required")?;
    if !name(module)||!name(typ)||version_text.parse::<u64>().ok().filter(|n|*n>0).is_none(){return Err("reference_schema_required".into())}
    let expected=["module_id","type","key","revision","schema_version"];
    if p.len()!=expected.len()||expected.iter().any(|k|!p.contains_key(*k))||array(s,"required")?.len()!=expected.len(){return Err("reference_schema_required".into())}
    for key in expected {if text(&p[key],"type")? != if key=="schema_version"{"integer"}else{"string"}{return Err("reference_schema_required".into())}}
   }
   let mut seen=std::collections::BTreeSet::new();for key in array(s,"required")? {let k=key.string().map_err(|_|"required_key")?;if !p.contains_key(k)||!seen.insert(k){return Err("required_key".into())}}
  },
  "string"=>{keys(s,&["type","enum"],&["type"])?;if let Some(e)=map(s)?.get("enum"){let a=e.array().map_err(|_|"enum")?;if a.is_empty()||a.iter().any(|x|x.string().is_err()){return Err("enum".into())}}},
  "integer"|"boolean"=>keys(s,&["type"],&["type"] )?,
  "array"=>{keys(s,&["type","items","maxItems"],&["type","items","maxItems"])?;if get(s,"maxItems")?.integer().map_err(|_|"max_items")?>128{return Err("max_items".into())}check(get(s,"items")?)?},
  _=>return Err("unsupported_schema".into())
 } Ok(())
}
pub fn validate(s:&Json,v:&Json)->Result<()> {
 match text(s,"type")?.as_str() {
  "object"=>{let m=map(v)?;let p=map(get(s,"properties")?)?;if m.keys().any(|k|!p.contains_key(k)){return Err("extra_property".into())}
   for key in array(s,"required")? {if !m.contains_key(key.string().map_err(|_|"required")?){return Err("missing_property".into())}}
   for(k,v)in m {validate(&p[k],v)?}
  },
  "string"=>{v.string().map_err(|_|"string_required")?;if let Some(e)=map(s)?.get("enum"){if !e.array().map_err(|_|"enum")?.contains(v){return Err("enum".into())}}},
  "integer"=>{integer(v)?;},"boolean"=>if !matches!(v,Json::Bool(_)){return Err("boolean_required".into())},
  "array"=>{let a=v.array().map_err(|_|"array_required")?;if a.len()>get(s,"maxItems")?.integer().map_err(|_|"max_items")? as usize{return Err("max_items".into())}for x in a{validate(get(s,"items")?,x)?}},
  _=>return Err("unsupported_schema".into())
 } Ok(())
}

/// The annotation is a closed schema target, not a grant or a revision.
pub fn references(s:&Json)->Result<Vec<String>> {
 let mut targets=Vec::new();
 if let Some(target)=map(s)?.get("data_ref"){targets.push(target.string().map_err(|_|"data_ref")?.to_owned());}
 match text(s,"type")?.as_str(){
  "object"=>for child in map(get(s,"properties")?)?.values(){targets.extend(references(child)?);},
  "array"=>targets.extend(references(get(s,"items")?)?),_=>{}
 }Ok(targets)
}
pub fn reference_value(v:&Json)->Result<String>{
 let fields=["module_id","type","key","revision","schema_version"];keys(v,&fields,&fields)?;
 let module=text(v,"module_id")?;let typ=text(v,"type")?;
 if !name(&module)||!name(&typ)||text(v,"key")?.is_empty()||text(v,"revision")?.is_empty(){return Err("result_reference".into())}
 Ok(format!("{module}/{typ}@{}",version(get(v,"schema_version")?)?))
}
pub fn validate_refs(s:&Json,v:&Json,a:&Json)->Result<()> {
 if let Some(target)=map(s)?.get("data_ref"){
  if reference_value(v)? != target.string().map_err(|_|"data_ref")? {return Err("result_reference_type".into())}
  if !array(a,"refs")?.contains(v){return Err("result_reference".into())}return Ok(())
 }
 match text(s,"type")?.as_str(){
  "object"=>for(k,value)in map(v)?{validate_refs(&map(get(s,"properties")?)?[k],value,a)?;},
  "array"=>for value in v.array().map_err(|_|"array_required")?{validate_refs(get(s,"items")?,value,a)?;},_=>{}
 }Ok(())
}
