//! Private native read seam; authority and durable receipts belong to the host.
use crate::{agent::{Agent,State}, wire_json::Json, Result};
pub trait AgentPorts {
    fn advertised_tools(&self, state:&State)->Result<Vec<String>>;
    fn persist(&self, agent:&Agent)->Result<()>;
    fn check_control(&mut self)->Result<()>;
    fn dispatch(&mut self, agent:&mut Agent, call_ref:String, name:String, arguments:Json)->Result<()>;
    fn admit_answer(&self, state:&State, answer:&str)->Result<()>;
    fn failure(&mut self, state:&mut State, reason:&str);
}

// The historical callback host remains a compatibility adapter.
impl AgentPorts for crate::host_session::HostPorts {
    fn advertised_tools(&self,state:&State)->Result<Vec<String>>{Ok(if state.counters.steps==1{vec!["inquiry.object".into()]}else{Vec::new()})}
    fn persist(&self,agent:&Agent)->Result<()>{crate::host_session::HostPorts::persist(self,agent)}
    fn check_control(&mut self)->Result<()>{crate::host_session::HostPorts::check_control(self)}
    fn dispatch(&mut self,agent:&mut Agent,call_ref:String,name:String,arguments:Json)->Result<()>{crate::host_session::HostPorts::dispatch(self,agent,call_ref,name,arguments)}
    fn admit_answer(&self,state:&State,answer:&str)->Result<()>{crate::host_session::HostPorts::admit_answer(self,state,answer)}
    fn failure(&mut self,state:&mut State,reason:&str){crate::host_session::HostPorts::failure(self,state,reason)}
}
