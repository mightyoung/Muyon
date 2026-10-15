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
