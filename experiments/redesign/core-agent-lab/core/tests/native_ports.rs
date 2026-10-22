use muyon_core_agent_lab::{agent::{Agent,State,Limits,Hooks},agent_ports::AgentPorts,model::{Provider,ModelRequest,ModelEvent,Role},wire_json::{Json,object,string},Result};
struct Ports{dispatches:usize,persists:std::cell::Cell<usize>}
impl AgentPorts for Ports {
 fn advertised_tools(&self,_s:&State)->Result<Vec<String>>{Ok(vec!["weather.peek".into()])}
 fn persist(&self,_a:&Agent)->Result<()>{self.persists.set(self.persists.get()+1);Ok(())}
 fn check_control(&mut self)->Result<()>{Ok(())}
 fn dispatch(&mut self,a:&mut Agent,c:String,n:String,args:Json)->Result<()>{assert_eq!(c,"call-1");assert_eq!(n,"weather.peek");assert_eq!(args,object([("station_key",string("s1"))]));self.dispatches+=1;a.state.context.push(muyon_core_agent_lab::model::Message{role:Role::Tool,text:"safe-projection".into()});Ok(())}
 fn admit_answer(&self,_s:&State,_t:&str)->Result<()>{Ok(())}
 fn failure(&mut self,s:&mut State,r:&str){s.status="failed".into();s.reason=r.into();}
}

// The host owns this persistence port; provider controls must never bypass it
// by writing a fixture task journal in Agent::dir.
#[derive(Default)]
struct MeterPorts {
 snapshots:std::cell::RefCell<Vec<(u64,u64,u64,bool)>>,
 reject_persist:bool,
 reject_once_at:Option<usize>,
 attempts:std::cell::Cell<usize>,
}
impl AgentPorts for MeterPorts {
 fn advertised_tools(&self,_:&State)->Result<Vec<String>>{Ok(Vec::new())}
 fn persist(&self,a:&Agent)->Result<()>{let n=self.attempts.get()+1;self.attempts.set(n);if self.reject_persist||self.reject_once_at==Some(n){return Err("meter_store_failed".into());}self.snapshots.borrow_mut().push((a.state.counters.total,a.state.wire_counters.sent,a.state.wire_counters.received,a.state.wire_counters.inflight));Ok(())}
 fn check_control(&mut self)->Result<()>{Ok(())}
 fn dispatch(&mut self,_:&mut Agent,_:String,_:String,_:Json)->Result<()>{panic!("unexpected tool dispatch")}
 fn admit_answer(&self,_:&State,_:&str)->Result<()>{Ok(())}
 fn failure(&mut self,s:&mut State,r:&str){s.status="failed".into();s.reason=r.into();}
}
struct MeterModel {entries:usize,exhaust:bool}
impl Provider for MeterModel {
 fn respond(&mut self,_:&ModelRequest,_:usize)->Result<ModelEvent>{panic!("controlled provider required")}
 fn respond_controlled(&mut self,_:&ModelRequest,_:usize,_:&[muyon_core_agent_lab::model::NativeMessage],c:&mut dyn muyon_core_agent_lab::model::ProviderControl)->Result<ModelEvent>{
  self.entries+=1;
  if self.exhaust {assert_eq!(c.remaining(),9,"HOST_METER_RED: shared total admission");}
  c.charge(true,4)?;
  assert_eq!(c.remaining(),5,"host send uses the existing total budget");
  c.charge(false,3)?;
  c.checkpoint("meter")?;
  assert_eq!(c.remaining(),2);
  if self.exhaust {c.charge(false,3)?;panic!("over-budget charge admitted");}
  Ok(ModelEvent::Answer("ok".into()))
 }
}
fn meter_agent()->Agent{
 let mut limits=Limits::default();limits.total=10;
 Agent{dir:std::env::temp_dir().join(format!("host-meter-{}-{}",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos())),state:State::runtime("q".into(),"scope".into(),limits).unwrap()}
}
#[test]
fn host_wire_charges_share_budget_and_host_journal(){
 let mut a=meter_agent();let mut p=MeterPorts::default();let mut m=MeterModel{entries:0,exhaust:false};
 a.run_with_runtime_ports(&mut m,&mut p,&Hooks::default()).unwrap();
 assert_eq!(a.state.status,"completed","HOST_CHARGE_RED: {}",a.state.reason);
 assert_eq!(a.state.counters.total,10);assert_eq!(a.state.wire_counters.sent,4);assert_eq!(a.state.wire_counters.received,3);
 let snapshots=p.snapshots.borrow();assert!(snapshots.contains(&(5,4,0,true)));assert!(snapshots.contains(&(8,4,3,true)));
 assert!(!a.dir.exists(),"host accounting must use host persistence only");
}
#[test]
fn host_wire_budget_rejects_without_charging_excess(){
 let mut a=meter_agent();let mut p=MeterPorts::default();let mut m=MeterModel{entries:0,exhaust:true};
 a.run_with_runtime_ports(&mut m,&mut p,&Hooks::default()).unwrap();
 assert_eq!(a.state.reason,"wire_total_limit");assert_eq!(a.state.counters.total,8);assert_eq!(a.state.wire_counters.total(),7);assert_eq!(m.entries,1);
 a.run_with_runtime_ports(&mut m,&mut p,&Hooks::default()).unwrap();assert_eq!(m.entries,1,"failed exchange cannot automatically re-enter provider");
}
#[test]
fn host_persist_failure_and_inflight_prevent_provider_entry(){
 let mut a=meter_agent();let mut p=MeterPorts{reject_persist:true,..Default::default()};let mut m=MeterModel{entries:0,exhaust:false};
 assert_eq!(a.run_with_runtime_ports(&mut m,&mut p,&Hooks::default()).unwrap_err(),"meter_store_failed");assert_eq!(m.entries,0);
 p.reject_persist=false;a.state.status="ready".into();a.state.wire_counters.inflight=true;
 a.run_with_runtime_ports(&mut m,&mut p,&Hooks::default()).unwrap();assert_eq!(a.state.reason,"wire_interrupted");assert_eq!(m.entries,0);
}
#[test]
fn host_charge_persistence_failure_stops_exchange_and_keeps_charged_bytes(){
 let mut a=meter_agent();let mut p=MeterPorts{reject_once_at:Some(2),..Default::default()};let mut m=MeterModel{entries:0,exhaust:false};
 a.run_with_runtime_ports(&mut m,&mut p,&Hooks::default()).unwrap();
 assert_eq!(a.state.reason,"wire_journal");assert_eq!(a.state.counters.total,5);assert_eq!(a.state.wire_counters.sent,4);assert_eq!(a.state.wire_counters.received,0);
 assert_eq!(p.snapshots.borrow().first(),Some(&(1,0,0,true)),"inflight must be durable before provider entry");
 a.run_with_runtime_ports(&mut m,&mut p,&Hooks::default()).unwrap();assert_eq!(m.entries,1);
}
struct ResponseModel{entries:usize}
impl Provider for ResponseModel{
 fn respond(&mut self,_:&ModelRequest,_:usize)->Result<ModelEvent>{panic!("controlled provider required")}
 fn respond_controlled(&mut self,_:&ModelRequest,_:usize,_:&[muyon_core_agent_lab::model::NativeMessage],c:&mut dyn muyon_core_agent_lab::model::ProviderControl)->Result<ModelEvent>{self.entries+=1;c.charge(true,7)?;Ok(ModelEvent::Answer("big".into()))}
}
#[test]
fn host_transport_total_also_bounds_response_and_next_admission(){
 let mut a=meter_agent();let mut p=MeterPorts::default();let mut m=ResponseModel{entries:0};
 a.run_with_runtime_ports(&mut m,&mut p,&Hooks::default()).unwrap();
 assert_eq!(a.state.status,"budget_exhausted");assert_eq!(a.state.reason,"host_budget");assert!(a.state.answer.is_empty());assert_eq!(m.entries,1);
 // A ready task whose previous transport used the total budget cannot start
 // another exchange, even if its model-call count remains below the limit.
 let mut a=meter_agent();a.state.counters.total=10;
 a.run_with_runtime_ports(&mut m,&mut p,&Hooks::default()).unwrap();assert_eq!(m.entries,1);assert_eq!(a.state.reason,"host_budget");
}
struct Model{turns:usize}
impl Provider for Model {fn respond(&mut self,r:&ModelRequest,_p:usize)->Result<ModelEvent>{self.turns+=1;assert_eq!(r.tools,vec!["weather.peek"]);if self.turns==1{Ok(ModelEvent::HostTool{call_ref:"call-1".into(),name:"weather.peek".into(),arguments:object([("station_key",string("s1"))])})}else{assert_eq!(r.messages.last().unwrap().text,"safe-projection");Ok(ModelEvent::Answer("done".into()))}}}
#[test]
fn generic_ports_share_driver_without_inquiry_names(){
 let dir=std::env::temp_dir().join(format!("native-core-{}-{}",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
 std::fs::create_dir_all(&dir).unwrap();
 let state=State::runtime("weather?".into(),"scope".into(),Limits::default()).unwrap();
 assert!(state.script.is_empty());assert!(!dir.join("effects.db").exists());
 let mut a=Agent{dir,state};let mut p=Ports{dispatches:0,persists:std::cell::Cell::new(0)};let mut m=Model{turns:0};
 a.run_with_runtime_ports(&mut m,&mut p,&Hooks::default()).unwrap();
 if a.state.reason=="native_ports_unsupported"{assert_eq!(a.state.status,"failed");assert_eq!(m.turns,0);assert_eq!(p.persists.get(),1);assert_eq!(p.dispatches,0);eprintln!("NATIVE_PORT_STUB_REACHED persists={} dispatches={}",p.persists.get(),p.dispatches);}
 assert_eq!(p.dispatches,1,"NATIVE_PORT_RED: registered generic read reaches the shared driver");assert_eq!(m.turns,2);assert_eq!(a.state.status,"completed");assert_eq!(a.state.answer,"done");assert!(p.persists.get()>=3);std::fs::remove_dir(&a.dir).unwrap();
}
