use crate::{hex, identifier, unhex, Result};
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Role { User, Assistant, Tool }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Message { pub role: Role, pub text: String }
#[derive(Clone, Debug)]
pub struct ModelRequest { pub task: String, pub attempt: String, pub turn: u64, pub messages: Vec<Message>, pub tools: Vec<String> }
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelEvent { Tool { call_ref: String, name: String, value: String }, Answer(String), Fail(String) }
pub trait Provider { fn respond(&mut self, request: &ModelRequest, position: usize) -> Result<ModelEvent>; }
#[derive(Clone, Debug)]
pub struct ScriptedProvider { pub events: Vec<ModelEvent> }
impl ScriptedProvider {
    pub fn parse(script: &str) -> Result<Self> {
        if script.is_empty() || script.len()>65536 { return Err("script_size".into()); }
        let mut events=Vec::new();
        for line in script.lines() {
            let p: Vec<_> = line.split('\t').collect();
            let event=match p.as_slice() {
                ["tool", call, "fixture.record", value] if identifier(call) => ModelEvent::Tool { call_ref:call.to_string(), name:"fixture.record".into(), value:unhex(value)? },
                ["answer", text] => ModelEvent::Answer(unhex(text)?),
                ["fail", reason] if identifier(reason) => ModelEvent::Fail(reason.to_string()),
                _ => return Err("invalid_complete_event".into()),
            };
            events.push(event);
            if events.len()>128 { return Err("script_event_limit".into()); }
        }
        if events.is_empty() { return Err("empty_script".into()); }
        Ok(Self { events })
    }
}
impl Provider for ScriptedProvider {
    fn respond(&mut self, request: &ModelRequest, position: usize) -> Result<ModelEvent> {
        if !identifier(&request.task) || !identifier(&request.attempt) || request.turn==0 || request.tools != ["fixture.record"] { return Err("invalid_model_request".into()); }
        let event=self.events.get(position).cloned().ok_or("provider_exhausted")?;
        match event {
            ModelEvent::Answer(text) => {
                let result=request.messages.iter().rev().find(|m| m.role==Role::Tool).map(|m| m.text.as_str()).unwrap_or("");
                if text.len().saturating_add(text.matches("{{tool_result}}").count().saturating_mul(result.len()))>65536 { return Err("provider_output_bound".into()); }
                Ok(ModelEvent::Answer(text.replace("{{tool_result}}", result)))
            },
            other => Ok(other),
        }
    }
}
pub fn encode_context(messages: &[Message]) -> String {
    messages.iter().map(|m| format!("{}\t{}\n", match m.role { Role::User=>"user",Role::Assistant=>"assistant",Role::Tool=>"tool" }, hex(&m.text))).collect()
}
pub fn decode_context(text: &str) -> Result<Vec<Message>> {
    let mut out=Vec::new();
    for line in text.lines() {
        let (role,value)=line.split_once('\t').ok_or("context_record")?;
        let role=match role { "user"=>Role::User,"assistant"=>Role::Assistant,"tool"=>Role::Tool,_=>return Err("context_role".into()) };
        out.push(Message { role,text:unhex(value)? });
        if out.len()>512 {return Err("context_count".into());}
    }
    Ok(out)
}
pub fn context_bytes(messages: &[Message]) -> u64 { messages.iter().map(|m| m.text.len() as u64).sum() }
pub fn event_bytes(e: &ModelEvent) -> u64 { match e { ModelEvent::Tool{call_ref,name,value} => (call_ref.len()+name.len()+value.len()) as u64, ModelEvent::Answer(s)|ModelEvent::Fail(s)=>s.len() as u64 } }

/// Structural native history. Never reconstructed from message text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NativeMessage {
    User(String),
    Assistant(String),
    AssistantCall { call_ref:String, name:String, value:String },
    ToolResult { call_ref:String, value:String, receipt:String },
}
