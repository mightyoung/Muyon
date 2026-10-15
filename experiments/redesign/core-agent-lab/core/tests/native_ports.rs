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
