//! Private Linux-only native read composition. Uses the existing Agent drive;
//! the child admits contracts/tickets, while host-installed Rust handlers read.
pub mod plugin_process;
pub mod store;
pub mod model_gateway;
use std::{cell::RefCell,collections::BTreeMap,io::Read,path::Path,rc::Rc,time::Duration};
use muyon_core_agent_lab::{Result,agent::{Agent,State},agent_ports::AgentPorts,model::{Message,Role}};
use muyon_plugin_contract_lab::{Json,object,string};
use plugin_process::PluginProcess;
use store::NativeStore;
pub const STUB_REACHED:&str="NATIVE_HOST_STUB_REACHED";
pub fn field<'a>(j:&'a Json,key:&str)->Result<&'a Json>{j.object()?.get(key).ok_or_else(||format!("missing_{key}"))}
fn text(j:&Json,key:&str)->Result<String>{Ok(field(j,key)?.string()?.into())}
fn request(command:&str,fields:Vec<(&str,Json)>)->Json{let mut pairs=fields;pairs.push(("command",string(command)));pairs.push(("protocol_version",Json::Number("1".into())));object(pairs)}
fn success(reply:Json)->Result<Json>{if field(&reply,"ok")?==&Json::Bool(true){Ok(reply)}else{Err(format!("contract_{}",text(&reply,"code").unwrap_or_else(|_|"rejected".into())))}}
fn nonce()->Result<String>{let mut bytes=[0u8;16];std::fs::File::open("/dev/urandom").and_then(|mut f|f.read_exact(&mut bytes)).map_err(|_|"identity_entropy")?;Ok(bytes.iter().map(|b|format!("{b:02x}")).collect())}
#[derive(Clone,Debug,PartialEq,Eq)]
pub struct AuthoritySnapshot{pub read:Json,pub model_allowed:bool,pub profile:String}
pub trait AuthoritySource{fn snapshot(&self)->Result<AuthoritySnapshot>;}
pub trait PurposeReview{fn review(&self,value:&Json,facts:&Json,purpose:&str)->Result<()>;fn mask_answer(&self,text:&str)->Result<String>;}
pub struct RawRead{pub raw:Json,pub projection:Json}
pub trait ReadHandler{fn read(&mut self,canonical_args:&Json)->Result<RawRead>;}
impl<F:FnMut(&Json)->Result<RawRead>> ReadHandler for F{fn read(&mut self,args:&Json)->Result<RawRead>{self(args)}}
pub struct Enrollment{pub bundle:Json,pub operation:String,pub tool_id:String,pub binding_id:String,pub handler:Box<dyn ReadHandler>}
struct Installed{operation:String,tool_id:String,binding:String,parameters:Json,handler:Box<dyn ReadHandler>}
#[derive(Clone)]
struct Projection{value:Json,authority:AuthoritySnapshot,receipt:Json}
pub struct NativeSession{pub store:NativeStore,process:PluginProcess,authority:Rc<dyn AuthoritySource>,review:Rc<dyn PurposeReview>,installed:BTreeMap<String,Installed>,history:Vec<Json>,projections:Vec<Projection>,pub dispatch_attempts:usize,pub handler_calls:usize,pub model_sends:usize,cancelled:bool}
pub type SharedSession=Rc<RefCell<NativeSession>>;
impl NativeSession{
 pub fn create(dir:&Path,plugin:&Path,authority:Rc<dyn AuthoritySource>,review:Rc<dyn PurposeReview>,input:&str)->Result<SharedSession>{
  if input.len()>8192{return Err("input_limit".into())}let store=NativeStore::create(dir)?;let process=PluginProcess::spawn(plugin,Duration::from_secs(5))?;
  Ok(Rc::new(RefCell::new(Self{store,process,authority,review,installed:BTreeMap::new(),history:vec![object([("role",string("user")),("content",string(input))])],projections:Vec::new(),dispatch_attempts:0,handler_calls:0,model_sends:0,cancelled:false})))
 }
 pub fn register(&mut self,enrollment:Enrollment)->Result<()>{
  if self.cancelled||self.installed.values().any(|v|v.operation==enrollment.operation||v.tool_id==enrollment.tool_id||v.binding==enrollment.binding_id){return Err("duplicate_enrollment".into())}
  let operations=field(&enrollment.bundle,"operations")?.array()?;let declared=operations.iter().find(|d|text(d,"binding_id").ok().as_deref()==Some(&enrollment.binding_id)).ok_or("binding_declaration")?;let parameters=field(declared,"input_schema")?.clone();
  success(self.process.request(request("register",vec![("bundle",enrollment.bundle),("host_bindings",Json::Array(vec![string(&enrollment.binding_id)]))]))?)?;
  self.installed.insert(enrollment.operation.clone(),Installed{operation:enrollment.operation,tool_id:enrollment.tool_id,binding:enrollment.binding_id,parameters,handler:enrollment.handler});Ok(())
 }
 pub fn discover(&mut self)->Result<Json>{let a=self.authority.snapshot()?;success(self.process.request(request("discover",vec![("authority",a.read)]))?)}
 pub fn cancel(&mut self){self.cancelled=true;self.process.close();}
 pub fn child_pid(&self)->u32{self.process.pid()}
 pub fn definitions(&self)->Vec<muyon_core_agent_lab::model::ToolDefinition>{self.installed.values().enumerate().map(|(index,v)|muyon_core_agent_lab::model::ToolDefinition{name:v.tool_id.clone(),wire_name:format!("registered_{index}"),parameters:v.parameters.clone()}).collect()}
 pub fn model_history(&self)->Json{Json::Array(self.history.clone())}
 pub fn review_payload(&self,payload:&[u8])->Result<()>{
  if self.cancelled{return Err("native_cancelled".into())}let current=self.authority.snapshot()?;
  if !current.model_allowed||current.profile!="offline-fixture"{return Err("model_authority_denied".into())}
  for p in &self.projections{if current!=p.authority{return Err("projection_revoked".into())}self.review.review(&p.value,self.store.facts(),"model_context")?;if !self.store.receipts().iter().any(|r|field(r,"identity")==Ok(&p.receipt)){return Err("projection_receipt_missing".into())}}
  let json=muyon_plugin_contract_lab::parse(payload)?;self.review.review(&json,self.store.facts(),"model_payload")?;
  // This synchronous final revision equality is the send admission point.
  if self.authority.snapshot()?!=current{return Err("send_authority_changed".into())}Ok(())
 }
 fn dispatch(&mut self,_agent:&mut Agent,_call_ref:String,_name:String,_arguments:Json)->Result<()>{self.dispatch_attempts+=1;eprintln!("{STUB_REACHED} handlerCalls={}",self.handler_calls);Err(STUB_REACHED.into())}
}
pub struct RuntimePorts{pub session:SharedSession}
impl AgentPorts for RuntimePorts{
 fn advertised_tools(&self,_state:&State)->Result<Vec<String>>{let mut s=self.session.borrow_mut();let d=s.discover()?;let mut tools=Vec::new();for row in field(&d,"operations")?.array()?{let operation=text(row,"operation")?;let installed=s.installed.get(&operation).ok_or("unenrolled_operation")?;tools.push(installed.tool_id.clone());}Ok(tools)}
 fn persist(&self,agent:&Agent)->Result<()>{muyon_core_agent_lab::store::atomic(&self.session.borrow().store.dir,"task.db",&agent.state.encode())}
 fn check_control(&mut self)->Result<()>{if self.session.borrow().cancelled{Err("native_cancelled".into())}else{Ok(())}}
 fn dispatch(&mut self,agent:&mut Agent,call_ref:String,name:String,arguments:Json)->Result<()>{self.session.borrow_mut().dispatch(agent,call_ref,name,arguments)}
 fn admit_answer(&self,_state:&State,text:&str)->Result<()>{let s=self.session.borrow();if s.review.mask_answer(text)?!=text{return Err("unsafe_answer".into())}Ok(())}
 fn failure(&mut self,state:&mut State,_reason:&str){state.status="failed".into();state.reason="native_host_refused".into();}
}
