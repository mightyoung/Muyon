//! Bounded, metadata-only registry and one-shot read admission. The trusted
//! host remains the sole handler executor, policy authority and receipt owner.
pub use muyon_core_agent_lab::wire_json::{object, parse, string, Json};
use std::collections::{BTreeMap,BTreeSet};
pub type Result<T> = std::result::Result<T,String>;
mod schema;
use schema::{get,text,array,map,keys};

#[derive(Clone)]
struct Operation { declaration:Json, module:String }
#[derive(Clone)]
struct Ticket { operation:Operation, args:Json, authority:Json, generation:u64, invocation:String, identity:String, dispatched:bool }
pub struct Catalog {
 generation:u64, modules:BTreeSet<String>, data:BTreeMap<String,Json>,
 operations:BTreeMap<String,Operation>, bindings:BTreeSet<String>,
 relation_count:usize, view_count:usize, serial:u64, tickets:BTreeMap<String,Ticket>,
 executions:u64, closed:bool, epoch:u128,
}
fn number(n:impl ToString)->Json {Json::Number(n.to_string())}
fn success(fields:Vec<(&str,Json)>)->Json {let mut j=object(fields);if let Json::Object(m)=&mut j{m.insert("ok".into(),Json::Bool(true));}j}
impl Catalog {
 pub fn new()->Self {
  static NEXT:std::sync::atomic::AtomicU64=std::sync::atomic::AtomicU64::new(1);
  let serial=NEXT.fetch_add(1,std::sync::atomic::Ordering::Relaxed) as u128;
  let epoch=std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_nanos() ^ ((std::process::id() as u128)<<64) ^ serial;
  Self{generation:0,modules:BTreeSet::new(),data:BTreeMap::new(),operations:BTreeMap::new(),bindings:BTreeSet::new(),relation_count:0,view_count:0,serial:0,tickets:BTreeMap::new(),executions:0,closed:false,epoch}
 }
 pub fn handle(&mut self, request:Json)->Json {
  match self.run(&request) {Ok(reply)=>reply,Err(code)=>object([("ok",Json::Bool(false)),("code",string(code))])}
 }
 fn run(&mut self,r:&Json)->Result<Json> {
  schema::bounded(r)?; let command=text(r,"command")?;
  if command=="inspect" {return Ok(success(vec![("generation",number(self.generation)),("data_count",number(self.data.len())),("operation_count",number(self.operations.len())),("relation_count",number(self.relation_count)),("view_count",number(self.view_count)),("execution_requests",number(self.executions)),("grants",number(0)),("receipts_created",number(0)),("pending",number(self.tickets.len()))]));}
  if command=="close" {self.closed=true;self.tickets.clear();return Ok(success(vec![]));}
  if self.closed{return Err("closed".into())}
  match command.as_str(){
   "register"=>self.register(r),"discover"=>self.discover(r),"prepare"=>self.prepare(r),"invoke"=>self.invoke(r),"accept_result"=>self.accept(r),
   "cancel"=>{keys(r,&["command","ticket"],&["command","ticket"])?;let t=text(r,"ticket")?;self.tickets.remove(&t).ok_or("unknown_ticket")?;Ok(success(vec![]))},
   _=>Err("unsupported_command".into())
  }
 }
 fn register(&mut self,r:&Json)->Result<Json> {
  keys(r,&["command","bundle","host_bindings","host_data_admissions"],&["command","bundle","host_bindings"])?;
  let b=get(r,"bundle")?;keys(b,&["module_id","protocol_version","data","relations","operations","views"],&["module_id","protocol_version","data","relations","operations","views"])?;
  let module=text(b,"module_id")?;if !schema::name(&module)||self.modules.contains(&module)||self.modules.len()>=8{return Err("module_identity".into())}
  if get(b,"protocol_version")? != &number(1){return Err("protocol_version".into())}
  let host_bindings:BTreeSet<String>=array(r,"host_bindings")?.iter().map(|v|v.string().map(str::to_owned).map_err(|_|"host_binding".into())).collect::<Result<_>>()?;
  let admitted:BTreeSet<String>=match map(r)?.get("host_data_admissions"){None=>BTreeSet::new(),Some(j)=>j.array().map_err(|_|"data_admissions")?.iter().map(|v|v.string().map(str::to_owned).map_err(|_|"data_admission".into())).collect::<Result<_>>()?};
  let ds=array(b,"data")?;let rs=array(b,"relations")?;let os=array(b,"operations")?;let vs=array(b,"views")?;
  if ds.len()>16||rs.len()>32||os.len()>16||vs.len()>16{return Err("bundle_limit".into())}
  let mut data=BTreeMap::new();let mut operations=BTreeMap::new();let mut bindings=BTreeSet::new();let mut relation_names=BTreeSet::new();let mut view_names=BTreeSet::new();
  let id=|j:&Json|->Result<String>{let name=text(j,"name")?;if !schema::name(&name){return Err("name".into())}let version=schema::version(get(j,"schema_version")?)?;Ok(format!("{module}/{name}@{version}"))};
  for d in ds {
   keys(d,&["name","schema_version","schema","classification"],&["name","schema_version","schema"])?;
   schema::check(get(d,"schema")?)?;if text(get(d,"schema")?,"type")?!="object"{return Err("data_object".into())}
   if let Some(labels)=map(d)?.get("classification"){for(field,label)in map(labels)? {if !map(get(get(d,"schema")?,"properties")?)?.contains_key(field)|| !["unreviewed","none","personal","commercial","credential"].contains(&label.string().map_err(|_|"classification")?) {return Err("classification".into())}}}
   if data.insert(id(d)?,d.clone()).is_some(){return Err("duplicate_data".into())}
  }
  let admitted_data=|reference:&str|->Result<&Json>{if let Some(d)=data.get(reference){return Ok(d)}if admitted.contains(reference){if let Some(d)=self.data.get(reference){return Ok(d)}}Err("unresolved_data".into())};
  for rel in rs {
   keys(rel,&["name","schema_version","from","field","to","many"],&["name","schema_version","from","field","to","many"])?;
   if !relation_names.insert(id(rel)?){return Err("duplicate_relation".into())}
   let from=text(rel,"from")?;let to=text(rel,"to")?;let d=admitted_data(&from)?;admitted_data(&to)?;
   let field=text(rel,"field")?;let fields=map(get(get(d,"schema")?,"properties")?)?;
   let shape=fields.get(&field).ok_or("relation_field")?;
   let many=get(rel,"many")?;let expected=if many==&Json::Bool(true){"array"}else if many==&Json::Bool(false){"object"}else{return Err("relation_many".into())};
   if text(shape,"type")?!=expected{return Err("relation_field_type".into())}
  }
  for op in os {
   keys(op,&["name","schema_version","effect","input_schema","projection_schema","data_refs","binding_id"],&["name","schema_version","effect","input_schema","projection_schema","data_refs","binding_id"])?;
   if text(op,"effect")?!="read"{return Err("read_only".into())}
   for key in ["input_schema","projection_schema"]{let s=get(op,key)?;schema::check(s)?;if text(s,"type")?!="object"{return Err("root_object".into())}}
   for reference in array(op,"data_refs")? {admitted_data(reference.string().map_err(|_|"data_ref")?)?;}
   let binding=text(op,"binding_id")?;if binding.is_empty()||!host_bindings.contains(&binding)||self.bindings.contains(&binding)||!bindings.insert(binding){return Err("host_binding".into())}
   if operations.insert(id(op)?,Operation{declaration:op.clone(),module:module.clone()}).is_some(){return Err("duplicate_operation".into())}
  }
  for view in vs {
   keys(view,&["name","data_refs","operation_refs"],&["name","data_refs","operation_refs"])?;
   let name=text(view,"name")?;if !schema::name(&name)||!view_names.insert(name){return Err("view_name".into())}
   for reference in array(view,"data_refs")? {admitted_data(reference.string().map_err(|_|"view_data")?)?;}
   for reference in array(view,"operation_refs")? {if !operations.contains_key(reference.string().map_err(|_|"view_operation")?){return Err("view_operation".into())}}
  }
  self.data.extend(data);self.operations.extend(operations);self.bindings.extend(bindings);self.modules.insert(module);self.relation_count+=rs.len();self.view_count+=vs.len();self.generation+=1;
  Ok(success(vec![("generation",number(self.generation))]))
 }
 fn allowed(a:&Json)->bool {
  let Ok(m)=map(a) else{return false};
  get(a,"allowed")==Ok(&Json::Bool(true)) && ["available","scope_allowed"].iter().all(|k|m.get(*k)!=Some(&Json::Bool(false))) &&
  ["revision","binding_revision","source_revision","rule_revision","scope"].iter().all(|k|text(a,k).is_ok_and(|s|!s.is_empty())) && array(a,"refs").is_ok()
 }
 fn operation_allowed(op:&Operation,a:&Json)->bool {
  if !Self::allowed(a){return false}
  if let Some(ids)=map(a).ok().and_then(|m|m.get("bindings")){if !ids.array().is_ok_and(|ids|ids.contains(get(&op.declaration,"binding_id").unwrap())){return false}}
  true
 }
 fn discover(&self,r:&Json)->Result<Json> {
  keys(r,&["command","authority"],&["command","authority"])?;
  let a=get(r,"authority")?;let visible=self.operations.iter().filter(|(_,op)|Self::operation_allowed(op,a)).map(|(id,op)|object([("operation",string(id)),("declaration",op.declaration.clone())])).collect();
  Ok(success(vec![("generation",number(self.generation)),("operations",Json::Array(visible))]))
 }
 fn prepare(&mut self,r:&Json)->Result<Json> {
  keys(r,&["command","operation","args","authority","invocation_id","receipt_owner","receipt_identity"],&["command","operation","args","authority","invocation_id","receipt_owner","receipt_identity"])?;
  if !self.tickets.is_empty(){return Err("busy".into())}
  let op=self.operations.get(&text(r,"operation")?).ok_or("unknown_operation")?.clone();let a=get(r,"authority")?;
  if !Self::operation_allowed(&op,a){return Err("denied".into())}
  let args=schema::canonical(get(r,"args")?)?;if args.encode().len()>8192{return Err("args_limit".into())}schema::validate(get(&op.declaration,"input_schema")?,&args)?;
  if text(r,"receipt_owner")?!="ToolRegistry"{return Err("receipt_owner".into())}
  let invocation=text(r,"invocation_id")?;let identity=text(r,"receipt_identity")?;if invocation.is_empty()||identity.is_empty(){return Err("receipt_identity".into())}
  self.serial+=1;let token=format!("read-{}-{}-{}",self.epoch,self.generation,self.serial);
  self.tickets.insert(token.clone(),Ticket{operation:op,args,authority:schema::canonical(a)?,generation:self.generation,invocation,identity,dispatched:false});
  Ok(success(vec![("ticket",string(token))]))
 }
 fn current(&self,t:&Ticket,a:&Json)->Result<()> {
  if t.generation!=self.generation||!Self::operation_allowed(&t.operation,a)||t.authority!=schema::canonical(a)?{return Err("stale_authority".into())}Ok(())
 }
 fn invoke(&mut self,r:&Json)->Result<Json> {
  keys(r,&["command","ticket","authority"],&["command","ticket","authority"])?;
  let token=text(r,"ticket")?;if self.tickets.get(&token).is_some_and(|t|t.dispatched){return Err("consumed".into())}
  let mut t=self.tickets.remove(&token).ok_or("unknown_ticket")?;self.current(&t,get(r,"authority")?)?;t.dispatched=true;self.executions+=1;
  let reply=success(vec![("dispatch",object([("binding_id",get(&t.operation.declaration,"binding_id")?.clone()),("args",t.args.clone()),("invocation_id",string(&t.invocation)),("receipt_identity",string(&t.identity))]))]);
  self.tickets.insert(token,t);Ok(reply)
 }
 fn accept(&mut self,r:&Json)->Result<Json> {
  keys(r,&["command","ticket","authority","receipt_ref","projection"],&["command","ticket","authority","receipt_ref","projection"])?;
  let token=text(r,"ticket")?;let t=self.tickets.remove(&token).ok_or("unknown_ticket")?;if !t.dispatched{return Err("not_dispatched".into())}self.current(&t,get(r,"authority")?)?;
  let receipt=get(r,"receipt_ref")?;keys(receipt,&["owner","invocation_id","binding_id","identity"],&["owner","invocation_id","binding_id","identity"])?;
  if text(receipt,"owner")?!="ToolRegistry"||text(receipt,"invocation_id")?!=t.invocation||get(receipt,"binding_id")?!=get(&t.operation.declaration,"binding_id")?||text(receipt,"identity")?!=t.identity{return Err("receipt_owner".into())}
  let p=get(r,"projection")?;schema::validate(get(&t.operation.declaration,"projection_schema")?,p)?;
  Self::validate_refs(p,&t.operation,&t.authority)?;
  Ok(success(vec![("receipt_ref",receipt.clone()),("projection",p.clone())]))
 }
 fn validate_refs(j:&Json,op:&Operation,a:&Json)->Result<()> {
  match j {
   Json::Object(m)=>{
    if m.contains_key("module_id")||m.contains_key("revision") {
     keys(j,&["module_id","type","key","revision"],&["module_id","type","key","revision"])?;
     let module=text(j,"module_id")?;let typ=text(j,"type")?;text(j,"key")?;text(j,"revision")?;
     let prefix=format!("{module}/{typ}@");if !array(&op.declaration,"data_refs")?.iter().any(|r|r.string().is_ok_and(|s|s.starts_with(&prefix)))||!array(a,"refs")?.contains(j){return Err("result_reference".into())}
     // Cross-module references are admitted only through the registration's
     // explicit host DATA admission; ordinary module reads stay scoped.
     let _ = &op.module;
    }else{for v in m.values(){Self::validate_refs(v,op,a)?}}
   },Json::Array(v)=>for x in v{Self::validate_refs(x,op,a)?},_=>{}
  }Ok(())
 }
}

impl Default for Catalog {fn default()->Self {Self::new()}}
