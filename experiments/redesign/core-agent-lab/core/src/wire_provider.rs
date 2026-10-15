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
                let function=object([("name",string("fixture__record")),("arguments",string(object([("value",string(value))]).encode()))]);
                let call=object([("id",string(call_ref)),("type",string("function")),("function",function)]);
                object([("role",string("assistant")),("content",Json::Null),("tool_calls",Json::Array(vec![call]))])
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
    let properties=object([("value",object([("type",string("string"))]))]);
    let schema=object([("type",string("object")),("properties",properties),("required",Json::Array(vec![string("value")])),("additionalProperties",Json::Bool(false))]);
    let function=object([("name",string("fixture__record")),("parameters",schema)]);
    let tool=object([("type",string("function")),("function",function)]);
    let result=object([("model",string("fixture-model")),("stream",Json::Bool(true)),("stream_options",object([("include_usage",Json::Bool(true))])),("messages",native_json(history)?),("tools",Json::Array(vec![tool]))]).encode().into_bytes();
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
fn clean_pipe_end(fd:i32)->bool{
    #[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
    unsafe extern "C"{fn poll(fds:*mut PollFd,nfds:usize,timeout:i32)->i32;fn ioctl(fd:i32,request:usize,...)->i32;}
    let mut p=PollFd{fd,events:1,revents:0};let mut available:i32=0;
    unsafe{poll(&mut p,1,0)>0&&p.revents&16!=0&&ioctl(fd,0x541B,&mut available)==0&&available==0}
}
#[cfg(not(target_os="linux"))]
fn clean_pipe_end(_fd:i32)->bool{false}
impl Provider for WireProvider {
    fn respond(&mut self,_request:&ModelRequest,_position:usize)->Result<ModelEvent>{Err("wire_control_required".into())}
    fn reported_usage(&self)->(Option<u64>,Option<u64>){(self.usage.prompt,self.usage.completion)}
    fn respond_controlled(&mut self,request:&ModelRequest,_position:usize,history:&[NativeMessage],control:&mut dyn ProviderControl)->Result<ModelEvent>{
        control.poll()?;self.config.validate()?;let bytes=encode_request(request,history)?;
        if bytes.len() as u64>control.remaining(){return Err("wire_total_limit".into());}
        let start=Instant::now();let mut active=start;
        let mut child=Command::new("python3").arg("-B").arg(&self.config.helper).arg("--fixture-dir").arg(&self.config.fixtures).arg("--turn").arg(request.turn.to_string()).arg("--capture-dir").arg(self.dir.join("wire-capture"))
            .env_clear().env("PATH","/usr/bin:/bin").stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().map_err(|_|"wire_spawn")?;
        let result=(||{
            let mut input=Some(child.stdin.take().ok_or("wire_stdin")?);let mut output=child.stdout.take().ok_or("wire_stdout")?;
            nonblocking(input.as_ref().ok_or("wire_stdin")?.as_raw_fd())?;nonblocking(output.as_raw_fd())?;
            let mut written=0;let mut received=0usize;let mut eof=false;let mut decoder=Decoder::new();let mut buffer=vec![0u8;self.config.chunk];let mut exit=None;
            loop{
                control.poll()?;
                if start.elapsed()>=Duration::from_millis(self.config.total_ms){return Err("wire_total_timeout".into());}
                if active.elapsed()>=Duration::from_millis(self.config.idle_ms){return Err("wire_idle_timeout".into());}
                let mut progress=false;
                if let Some(pipe)=input.as_mut(){let end=(written+self.config.chunk).min(bytes.len());let allowance=usize::try_from(control.remaining()).unwrap_or(usize::MAX);let end=end.min(written.saturating_add(allowance));if end==written{return Err("wire_total_limit".into());}
                    match pipe.write(&bytes[written..end]){Ok(0)=>return Err("wire_stdin_closed".into()),Ok(n)=>{written+=n;control.charge(true,n)?;progress=true;},Err(e) if e.kind()==std::io::ErrorKind::WouldBlock=>{},Err(_)=>return Err("wire_write".into())}
                    if written==bytes.len(){drop(input.take());control.checkpoint("wire-open")?;control.poll()?;}
                }
                if !eof {
                    let cap=self.config.chunk.min(65536usize.saturating_sub(received)).min(usize::try_from(control.remaining()).unwrap_or(usize::MAX));
                    if cap==0{if clean_pipe_end(output.as_raw_fd()){eof=true;}else{return Err(if received>=65536{"wire_response_limit"}else{"wire_total_limit"}.into());}}
                    else{match output.read(&mut buffer[..cap]){
                        Ok(0)=>{eof=true;progress=true;},Ok(n)=>{received+=n;control.charge(false,n)?;progress=true;for byte in &buffer[..n]{if decoder.feed(*byte)?.is_some(){control.checkpoint("wire-args")?;control.poll()?;}}},
                        Err(e) if e.kind()==std::io::ErrorKind::WouldBlock=>{},Err(_)=>return Err("wire_read".into()),
                    }}
                }
                if exit.is_none(){exit=child.try_wait().map_err(|_|"wire_wait")?;}
                if exit.is_some_and(|status|!status.success()){return Err("wire_child_exit".into());}
                if eof&&input.is_none()&&exit.is_some(){control.poll()?;let turn=decoder.finish()?;self.usage=turn.usage;return Ok(turn.event);}
                if progress{active=Instant::now();}else{std::thread::sleep(Duration::from_millis(2));}
            }
        })();
        if result.is_err(){let _=child.kill();let _=child.wait();}result
    }
}
