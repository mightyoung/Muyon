//! Incremental SSE collector. Observed arguments have no execution authority.
use crate::{Result,identifier,model::ModelEvent,wire_json::{self,Json}};
#[derive(Clone,Debug,Default,PartialEq,Eq)]
pub struct Usage {pub prompt:Option<u64>,pub completion:Option<u64>}
#[derive(Clone,Debug,PartialEq,Eq)]
pub struct ArgumentObservation {pub call_ref:String,pub name:String,pub value:String}
#[derive(Clone,Debug,PartialEq,Eq)]
pub struct DecodedTurn {pub event:ModelEvent,pub usage:Usage}
#[derive(Default)]
pub struct Decoder {
    line:Vec<u8>,data:Vec<u8>,data_present:bool,bytes:usize,text:String,
    call_seen:bool,call_ref:String,name:String,args:String,reason:Option<String>,
    done:bool,observed:bool,usage:Usage,failure:Option<String>,
}
fn nullable_text(value:Option<&Json>)->Result<Option<&str>>{match value{None|Some(Json::Null)=>Ok(None),Some(v)=>Ok(Some(v.string()?))}}
fn freeze(target:&mut String,value:Option<&Json>)->Result<()>{if let Some(s)=nullable_text(value)?{if !s.is_empty(){if !target.is_empty()&&target!=s{return Err("wire_metadata_conflict".into());}if s.len()>64{return Err("wire_metadata_size".into());}*target=s.into();}}Ok(())}
impl Decoder {
    pub fn new()->Self{Self::default()}
    pub fn with_tools(_tools:&[crate::model::ToolDefinition])->Result<Self>{Err("native_protocol_unsupported".into())}
    pub fn cancel(&mut self){self.failure=Some("wire_cancelled".into());}
    pub fn feed(&mut self,byte:u8)->Result<Option<ArgumentObservation>>{
        if let Some(e)=&self.failure{return Err(e.clone());}
        let result=self.feed_inner(byte);if let Err(e)=&result{self.failure=Some(e.clone());}result
    }
    fn feed_inner(&mut self,byte:u8)->Result<Option<ArgumentObservation>>{
        self.bytes=self.bytes.checked_add(1).ok_or("wire_response_limit")?;if self.bytes>65536{return Err("wire_response_limit".into());}
        if byte!=b'\n'{if self.line.len()>=16384{return Err("wire_line_limit".into());}self.line.push(byte);return Ok(None);}
        let mut line=std::mem::take(&mut self.line);if line.last()==Some(&b'\r'){line.pop();}std::str::from_utf8(&line).map_err(|_|"wire_utf8")?;
        if line.is_empty(){if !self.data_present{return Ok(None);}self.data_present=false;let data=std::mem::take(&mut self.data);return self.event(&data);}
        if line[0]==b':'{return Ok(None);}
        let colon=line.iter().position(|b|*b==b':').unwrap_or(line.len());let name=&line[..colon];let mut value=if colon<line.len(){&line[colon+1..]}else{&[]};if value.first()==Some(&b' '){value=&value[1..];}
        if name==b"data"{let extra=value.len()+usize::from(self.data_present);if self.data.len().checked_add(extra).ok_or("wire_event_limit")?>16384{return Err("wire_event_limit".into());}if self.data_present{self.data.push(b'\n');}self.data.extend_from_slice(value);self.data_present=true;}Ok(None)
    }
    fn event(&mut self,data:&[u8])->Result<Option<ArgumentObservation>>{
        if self.done{return Err("wire_data_after_done".into());}
        if data==b"[DONE]"{if self.reason.is_none(){return Err("wire_missing_finish".into());}self.done=true;return Ok(None);}
        let json=wire_json::parse(data)?;let root=json.object()?;if root.contains_key("error"){return Err("wire_provider_error".into());}
        if let Some(usage)=root.get("usage"){if !matches!(usage,Json::Null){let usage=usage.object()?;for(key,target)in[("prompt_tokens",&mut self.usage.prompt),("completion_tokens",&mut self.usage.completion)]{if let Some(value)=usage.get(key){if !matches!(value,Json::Null){let value=value.integer()?;if target.is_some_and(|old|old!=value){return Err("wire_usage_conflict".into());}*target=Some(value);}}}}}
        let choices=root.get("choices").ok_or("wire_choices")?.array()?;
        if choices.is_empty(){if !matches!(root.get("usage"),Some(Json::Object(_))){return Err("wire_choices".into());}return Ok(None);}
        if choices.len()!=1||self.reason.is_some(){return Err("wire_choice_or_terminal".into());}
        let choice=choices[0].object()?;if choice.get("index").ok_or("wire_choice_index")?.integer()?!=0{return Err("wire_choice_index".into());}
        let delta=choice.get("delta").ok_or("wire_delta")?.object()?;
        if delta.contains_key("function_call"){return Err("wire_legacy_function_call".into());}
        if let Some(role)=nullable_text(delta.get("role"))?{if role!="assistant"{return Err("wire_role".into());}}
        if let Some(text)=nullable_text(delta.get("content"))?{if self.text.len().checked_add(text.len()).ok_or("wire_text_limit")?>65536{return Err("wire_text_limit".into());}self.text.push_str(text);}
        if let Some(calls)=delta.get("tool_calls"){if !matches!(calls,Json::Null){let calls=calls.array()?;if calls.len()>1{return Err("wire_multiple_calls".into());}if let Some(call)=calls.first(){let call=call.object()?;if call.get("index").ok_or("wire_call_index")?.integer()?!=0{return Err("wire_call_index".into());}self.call_seen=true;freeze(&mut self.call_ref,call.get("id"))?;if let Some(kind)=nullable_text(call.get("type"))?{if kind!="function"{return Err("wire_call_type".into());}}
            if let Some(function)=call.get("function"){if !matches!(function,Json::Null){let function=function.object()?;freeze(&mut self.name,function.get("name"))?;if let Some(args)=nullable_text(function.get("arguments"))?{if self.args.len().checked_add(args.len()).ok_or("wire_arguments_limit")?>8192{return Err("wire_arguments_limit".into());}self.args.push_str(args);}}}
        }}}
        if !self.name.is_empty()&&self.name!="fixture__record"{return Err("wire_unknown_tool".into());}
        if self.call_seen&&!self.text.is_empty(){return Err("wire_mixed_turn".into());}
        if let Some(reason)=nullable_text(choice.get("finish_reason"))?{if !matches!(reason,"stop"|"tool_calls"){return Err("wire_finish_reason".into());}self.reason=Some(reason.into());}
        if !self.observed&&self.reason.is_none()&&self.call_seen {if let Ok(call)=self.complete_call(){self.observed=true;return Ok(Some(call));}}
        Ok(None)
    }
    fn complete_call(&self)->Result<ArgumentObservation>{
        if !identifier(&self.call_ref)||self.name!="fixture__record"{return Err("wire_call_metadata".into());}
        let args=wire_json::parse(self.args.as_bytes())?;let args=args.object()?;if args.len()!=1{return Err("wire_arguments_schema".into());}let value=args.get("value").ok_or("wire_arguments_schema")?.string()?;
        Ok(ArgumentObservation{call_ref:self.call_ref.clone(),name:"fixture.record".into(),value:value.into()})
    }
    pub fn finish(self)->Result<DecodedTurn>{
        if let Some(e)=&self.failure{return Err(e.clone());}if !self.line.is_empty()||self.data_present||!self.done{return Err("wire_stream_truncated".into());}
        let event=if self.call_seen{if self.reason.as_deref()!=Some("tool_calls"){return Err("wire_tool_finish".into());}let call=self.complete_call()?;ModelEvent::Tool{call_ref:call.call_ref,name:call.name,value:call.value}}
        else{if self.reason.as_deref()!=Some("stop"){return Err("wire_answer_finish".into());}ModelEvent::Answer(self.text.clone())};
        Ok(DecodedTurn{event,usage:self.usage})
    }
}
