//! Native request mapping and bounded stdio provider boundary.
use crate::{Result,identifier,model::{ModelRequest,NativeMessage},wire_json::{self,Json,object,string}};
pub fn native_json(history:&[NativeMessage])->Result<Json>{
    let mut raw_size=0usize;
    if history.len()>512{return Err("wire_request_limit".into());}
    for message in history{let sizes:Vec<usize>=match message{NativeMessage::User(t)|NativeMessage::Assistant(t)=>vec![t.len()],NativeMessage::AssistantCall{call_ref,name,value}=>vec![call_ref.len(),name.len(),value.len()],NativeMessage::ToolResult{call_ref,value,receipt}=>vec![call_ref.len(),value.len(),receipt.len()]};for size in sizes{raw_size=raw_size.checked_add(size).ok_or("wire_request_limit")?;if raw_size>65536{return Err("wire_request_limit".into());}}}
    let mut messages=Vec::new();let mut pending:Option<(&str,&str)>=None;let mut identities=std::collections::BTreeMap::new();let mut receipts=std::collections::BTreeMap::new();
    for message in history {
        if pending.is_some()&&!matches!(message,NativeMessage::ToolResult{..}){return Err("wire_unpaired_history".into());}
        let item=match message {
            NativeMessage::User(text)=>object([("role",string("user")),("content",string(text))]),
            NativeMessage::Assistant(text)=>object([("role",string("assistant")),("content",string(text))]),
            NativeMessage::AssistantCall{call_ref,name,value}=>{
                if !identifier(call_ref)||name!="fixture.record"{return Err("wire_history_call".into());}if let Some((old_name,old_value))=identities.get(call_ref){if old_name!=name||old_value!=value{return Err("wire_history_conflict".into());}}else{identities.insert(call_ref.clone(),(name.clone(),value.clone()));}pending=Some((call_ref,value));
                let function=object([("name",string("fixture__record")),("arguments",string(object([("value",string(value))]).encode()))]);
                let call=object([("id",string(call_ref)),("type",string("function")),("function",function)]);
                object([("role",string("assistant")),("content",Json::Null),("tool_calls",Json::Array(vec![call]))])
            },
            NativeMessage::ToolResult{call_ref,value,receipt}=>{
                if pending!=Some((call_ref.as_str(),value.as_str()))||!identifier(receipt){return Err("wire_unpaired_history".into());}pending=None;
                if let Some(original)=receipts.get(call_ref){if original!=receipt{return Err("wire_history_receipt_conflict".into());}}else{receipts.insert(call_ref.clone(),receipt.clone());}
                object([("role",string("tool")),("tool_call_id",string(call_ref)),("content",string(object([("value",string(value)),("receipt",string(receipt))]).encode()))])
            },
        };messages.push(item);
    }
    if pending.is_some(){return Err("wire_unpaired_history".into());}Ok(Json::Array(messages))
}
pub fn encode_request(request:&ModelRequest,history:&[NativeMessage])->Result<Vec<u8>>{
    if !identifier(&request.task)||!identifier(&request.attempt)||request.turn==0||request.tools!=["fixture.record"]{return Err("wire_request_identity".into());}
    let properties=object([("value",object([("type",string("string"))]))]);
    let schema=object([("type",string("object")),("properties",properties),("required",Json::Array(vec![string("value")])),("additionalProperties",Json::Bool(false))]);
    let function=object([("name",string("fixture__record")),("parameters",schema)]);
    let tool=object([("type",string("function")),("function",function)]);
    let body=object([("model",string("fixture-model")),("stream",Json::Bool(true)),("stream_options",object([("include_usage",Json::Bool(true))])),("messages",native_json(history)?),("tools",Json::Array(vec![tool]))]);
    if body.encoded_len()?>65536{return Err("wire_request_limit".into());}let result=body.encode().into_bytes();
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
    let json=wire_json::parse_bounded(raw.as_bytes(),262144)?;let mut result=Vec::new();
    for row in json.array()?{let row=row.array()?;let s:Vec<&str>=row.iter().map(Json::string).collect::<Result<_>>()?;let m=match s.as_slice(){
        ["user",t]=>NativeMessage::User((*t).into()),["assistant",t]=>NativeMessage::Assistant((*t).into()),
        ["call",c,n,v]=>NativeMessage::AssistantCall{call_ref:(*c).into(),name:(*n).into(),value:(*v).into()},
        ["tool",c,v,r]=>NativeMessage::ToolResult{call_ref:(*c).into(),value:(*v).into(),receipt:(*r).into()},_=>return Err("wire_history".into())};result.push(m);
    }if result.len()>512{return Err("wire_history_limit".into());}Ok(result)
}

use std::{path::{Path,PathBuf},io::{Read,Write},os::fd::AsRawFd,process::{Command,Stdio},time::{Duration,Instant}};
use crate::{model::{Provider,ProviderControl,ModelEvent},wire_sse::{Decoder,Usage}};
#[derive(Clone,Debug)]
pub struct WireConfig {pub helper:PathBuf,pub fixtures:PathBuf,pub chunk:usize,pub idle_ms:u64,pub total_ms:u64,pub max_total:u64}
impl WireConfig {
    pub fn validate(&self)->Result<()>{if !self.helper.is_absolute()||!self.fixtures.is_absolute()||!self.helper.is_file()||!self.fixtures.is_dir()||!(1..=8192).contains(&self.chunk)||!(1..=10000).contains(&self.idle_ms)||!(1..=30000).contains(&self.total_ms)||!(1..=1048576).contains(&self.max_total){Err("wire_config".into())}else{Ok(())}}
    pub fn encode(&self)->String{object([("helper",string(self.helper.to_string_lossy().as_ref())),("fixtures",string(self.fixtures.to_string_lossy().as_ref())),("chunk",Json::Number(self.chunk.to_string())),("idle_ms",Json::Number(self.idle_ms.to_string())),("total_ms",Json::Number(self.total_ms.to_string())),("max_total",Json::Number(self.max_total.to_string()))]).encode()}
    pub fn decode(raw:&str)->Result<Self>{let value=wire_json::parse(raw.as_bytes())?;let o=value.object()?;if o.len()!=6{return Err("wire_config".into());}let get=|k:&str|o.get(k).ok_or_else(||"wire_config".to_string());let result=Self{helper:PathBuf::from(get("helper")?.string()?),fixtures:PathBuf::from(get("fixtures")?.string()?),chunk:usize::try_from(get("chunk")?.integer()?).map_err(|_|"wire_config")?,idle_ms:get("idle_ms")?.integer()?,total_ms:get("total_ms")?.integer()?,max_total:get("max_total")?.integer()?};result.validate()?;Ok(result)}
}
#[derive(Clone,Debug,Default)]
pub struct WireCounters {pub sent:u64,pub received:u64,pub inflight:bool,pub usage:Usage}
impl WireCounters {pub fn total(&self)->u64{self.sent.saturating_add(self.received)}}
pub struct WireProvider {config:WireConfig,dir:PathBuf,usage:Usage}
impl WireProvider {pub fn new(config:WireConfig,dir:&Path)->Self{Self{config,dir:dir.to_path_buf(),usage:Usage::default()}}}
#[cfg(target_os="linux")]
fn nonblocking(fd:i32)->Result<()>{unsafe extern "C"{fn fcntl(fd:i32,cmd:i32,...)->i32;}let flags=unsafe{fcntl(fd,3)};if flags<0||unsafe{fcntl(fd,4,flags|2048)}<0{Err("wire_pipe_setup".into())}else{Ok(())}}
#[cfg(not(target_os="linux"))]
fn nonblocking(_fd:i32)->Result<()>{Err("wire_linux_required".into())}
#[cfg(target_os="linux")]
fn pipe_end(fd:i32)->(bool,bool){
    #[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
    unsafe extern "C"{fn poll(fds:*mut PollFd,nfds:usize,timeout:i32)->i32;fn ioctl(fd:i32,request:usize,...)->i32;}
    let mut p=PollFd{fd,events:1,revents:0};let mut available:i32=0;
    let ready=unsafe{poll(&mut p,1,0)};let measured=unsafe{ioctl(fd,0x541B,&mut available)};
    (ready>0&&p.revents&16!=0&&measured==0&&available==0,measured!=0||available>0)
}
#[cfg(not(target_os="linux"))]
fn pipe_end(_fd:i32)->(bool,bool){(false,true)}
struct ExchangeDeadline {start:Instant,active:Instant,idle:Duration,total:Duration}
impl ExchangeDeadline {
    fn new(config:&WireConfig)->Self{let now=Instant::now();Self{start:now,active:now,idle:Duration::from_millis(config.idle_ms),total:Duration::from_millis(config.total_ms)}}
    fn check(&self,control:&mut dyn ProviderControl)->Result<()>{control.poll()?;if self.start.elapsed()>=self.total{return Err("wire_total_timeout".into());}if self.active.elapsed()>=self.idle{return Err("wire_idle_timeout".into());}Ok(())}
}
fn write_request_step(pipe:&mut dyn Write,bytes:&[u8],written:usize,chunk:usize,control:&mut dyn ProviderControl,deadline:&ExchangeDeadline)->Result<usize>{
    deadline.check(control)?;
    let end=written.saturating_add(chunk).min(bytes.len()).min(written.saturating_add(usize::try_from(control.remaining()).unwrap_or(usize::MAX)));
    if end==written{return Err("wire_total_limit".into());}
    match pipe.write(&bytes[written..end]){Ok(0)=>Err("wire_stdin_closed".into()),Ok(n)=>{control.charge(true,n)?;Ok(n)},Err(e) if e.kind()==std::io::ErrorKind::WouldBlock=>Ok(0),Err(_)=>Err("wire_write".into())}
}
impl Provider for WireProvider {
    fn respond(&mut self,_request:&ModelRequest,_position:usize)->Result<ModelEvent>{Err("wire_control_required".into())}
    fn reported_usage(&self)->(Option<u64>,Option<u64>){(self.usage.prompt,self.usage.completion)}
    fn respond_controlled(&mut self,request:&ModelRequest,_position:usize,history:&[NativeMessage],control:&mut dyn ProviderControl)->Result<ModelEvent>{
        control.poll()?;self.config.validate()?;let bytes=encode_request(request,history)?;
        if bytes.len() as u64>control.remaining(){return Err("wire_total_limit".into());}
        let mut deadline=ExchangeDeadline::new(&self.config);
        let mut child=Command::new("python3").arg("-B").arg(&self.config.helper).arg("--fixture-dir").arg(&self.config.fixtures).arg("--turn").arg(request.turn.to_string()).arg("--capture-dir").arg(self.dir.join("wire-capture"))
            .env_clear().env("PATH","/usr/bin:/bin").stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().map_err(|_|"wire_spawn")?;
        let result=(||{
            let mut input=Some(child.stdin.take().ok_or("wire_stdin")?);let mut output=child.stdout.take().ok_or("wire_stdout")?;
            nonblocking(input.as_ref().ok_or("wire_stdin")?.as_raw_fd())?;nonblocking(output.as_raw_fd())?;
            let mut written=0;let mut received=0usize;let mut eof=false;let mut decoder=Decoder::new();let mut buffer=vec![0u8;self.config.chunk];let mut exit=None;
            loop{
                deadline.check(control)?;
                let mut progress=false;
                if let Some(pipe)=input.as_mut(){let n=write_request_step(pipe,&bytes,written,self.config.chunk,control,&deadline)?;written+=n;progress|=n>0;
                    if written==bytes.len(){drop(input.take());control.checkpoint("wire-open")?;control.poll()?;}
                }
                if !eof {
                    let cap=self.config.chunk.min(65536usize.saturating_sub(received)).min(usize::try_from(control.remaining()).unwrap_or(usize::MAX));
                    if cap==0{let (ended,excess)=pipe_end(output.as_raw_fd());if ended{eof=true;}else if excess{return Err(if received>=65536{"wire_response_limit"}else{"wire_total_limit"}.into());}}
                    else{match output.read(&mut buffer[..cap]){
                        Ok(0)=>{eof=true;progress=true;},Ok(n)=>{received+=n;control.charge(false,n)?;progress=true;for byte in &buffer[..n]{if decoder.feed(*byte)?.is_some(){control.checkpoint("wire-args")?;control.poll()?;}}},
                        Err(e) if e.kind()==std::io::ErrorKind::WouldBlock=>{},Err(_)=>return Err("wire_read".into()),
                    }}
                }
                if exit.is_none(){exit=child.try_wait().map_err(|_|"wire_wait")?;}
                if exit.is_some_and(|status|!status.success()){return Err("wire_child_exit".into());}
                if eof&&input.is_none()&&exit.is_some(){control.poll()?;let turn=decoder.finish()?;self.usage=turn.usage;return Ok(turn.event);}
                if progress{deadline.active=Instant::now();}else{std::thread::sleep(Duration::from_millis(2));}
            }
        })();
        if result.is_err(){let _=child.kill();let _=child.wait();}result
    }
}

#[cfg(test)]
mod pump_tests {
    use super::*;
    #[derive(Default)]struct Control{cancel:bool,charged:usize,polls:usize}
    impl ProviderControl for Control{fn poll(&mut self)->Result<()>{self.polls+=1;if self.cancel{Err("wire_cancelled".into())}else{Ok(())}}fn remaining(&self)->u64{100}fn charge(&mut self,_sent:bool,n:usize)->Result<()>{self.charged+=n;Ok(())}fn checkpoint(&mut self,_name:&str)->Result<()>{Ok(())}}
    #[derive(Default)]struct Blocked{calls:usize}
    impl Write for Blocked{fn write(&mut self,_bytes:&[u8])->std::io::Result<usize>{self.calls+=1;Err(std::io::ErrorKind::WouldBlock.into())}fn flush(&mut self)->std::io::Result<()>{Ok(())}}
    #[test]
    fn actual_wouldblock_step_cannot_bypass_cancel_or_total_deadline(){
        let now=Instant::now();let mut deadline=ExchangeDeadline{start:now,active:now,idle:Duration::from_secs(10),total:Duration::from_secs(10)};let mut pipe=Blocked::default();let mut control=Control::default();
        assert_eq!(write_request_step(&mut pipe,b"request",0,8192,&mut control,&deadline).unwrap(),0);assert_eq!(pipe.calls,1);assert_eq!(control.charged,0);
        control.cancel=true;assert_eq!(write_request_step(&mut pipe,b"request",0,8192,&mut control,&deadline).unwrap_err(),"wire_cancelled");assert_eq!(pipe.calls,1);
        control.cancel=false;deadline.start=Instant::now().checked_sub(Duration::from_secs(11)).unwrap();assert_eq!(write_request_step(&mut pipe,b"request",0,8192,&mut control,&deadline).unwrap_err(),"wire_total_timeout");assert_eq!(pipe.calls,1);assert_eq!(control.charged,0);assert_eq!(control.polls,3);
    }
}
