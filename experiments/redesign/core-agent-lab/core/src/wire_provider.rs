//! Native request mapping and bounded stdio provider boundary.
use crate::{Result,identifier,model::{ModelRequest,NativeMessage},wire_json::{self,Json,object,string}};
pub fn native_json(history:&[NativeMessage])->Result<Json>{
    let mut messages=Vec::new();let mut pending:Option<&str>=None;
    for message in history {
        if pending.is_some()&&!matches!(message,NativeMessage::ToolResult{..}){return Err("wire_unpaired_history".into());}
        let item=match message {
            NativeMessage::User(text)=>object([("role",string("user")),("content",string(text))]),
            NativeMessage::Assistant(text)=>object([("role",string("assistant")),("content",string(text))]),
            NativeMessage::AssistantCall{call_ref,name,value}=>{
                if !identifier(call_ref)||name!="fixture.record"{return Err("wire_history_call".into());}pending=Some(call_ref);
                object([("role",string("assistant")),("content",Json::Null),("tool_calls",Json::Array(vec![object([("id",string(call_ref)),("type",string("function")),("function",object([("name",string("fixture__record")),("arguments",string(object([("value",string(value))]).encode()))]))]))])
            },
            NativeMessage::ToolResult{call_ref,value,receipt}=>{
                if pending!=Some(call_ref.as_str())||!identifier(receipt){return Err("wire_unpaired_history".into());}pending=None;
                object([("role",string("tool")),("tool_call_id",string(call_ref)),("content",string(object([("value",string(value)),("receipt",string(receipt))]).encode()))])
            },
        };messages.push(item);
    }
    if pending.is_some(){return Err("wire_unpaired_history".into());}Ok(Json::Array(messages))
}
pub fn encode_request(request:&ModelRequest,history:&[NativeMessage])->Result<Vec<u8>>{
    if !identifier(&request.task)||!identifier(&request.attempt)||request.turn==0||request.tools!=["fixture.record"]{return Err("wire_request_identity".into());}
    let schema=object([("type",string("object")),("properties",object([("value",object([("type",string("string"))]))])),("required",Json::Array(vec![string("value")])),("additionalProperties",Json::Bool(false))]);
    let result=object([("model",string("fixture-model")),("stream",Json::Bool(true)),("stream_options",object([("include_usage",Json::Bool(true))])),("messages",native_json(history)?),("tools",Json::Array(vec![object([("type",string("function")),("function",object([("name",string("fixture__record")),("parameters",schema)]))])]))]).encode().into_bytes();
    if result.len()>65536{return Err("wire_request_limit".into());}Ok(result)
}
/// Private snapshot encoding is structured and is independent of semantic text.
pub fn encode_history(history:&[NativeMessage])->String{
    Json::Array(history.iter().map(|m|match m{
        NativeMessage::User(t)=>Json::Array(vec![string("user"),string(t)]),NativeMessage::Assistant(t)=>Json::Array(vec![string("assistant"),string(t)]),
        NativeMessage::AssistantCall{call_ref,name,value}=>Json::Array(vec![string("call"),string(call_ref),string(name),string(value)]),
        NativeMessage::ToolResult{call_ref,value,receipt}=>Json::Array(vec![string("tool"),string(call_ref),string(value),string(receipt)]),
    }).collect()).encode()
}
pub fn decode_history(raw:&str)->Result<Vec<NativeMessage>>{
    let json=wire_json::parse(raw.as_bytes())?;let mut result=Vec::new();
    for row in json.array()?{let row=row.array()?;let s:Vec<&str>=row.iter().map(Json::string).collect::<Result<_>>()?;let m=match s.as_slice(){
        ["user",t]=>NativeMessage::User((*t).into()),["assistant",t]=>NativeMessage::Assistant((*t).into()),
        ["call",c,n,v]=>NativeMessage::AssistantCall{call_ref:(*c).into(),name:(*n).into(),value:(*v).into()},
        ["tool",c,v,r]=>NativeMessage::ToolResult{call_ref:(*c).into(),value:(*v).into(),receipt:(*r).into()},_=>return Err("wire_history".into())};result.push(m);
    }if result.len()>512{return Err("wire_history_limit".into());}Ok(result)
}
