//! One in-flight private JSON-line request, with bounded nonblocking pipes.
use std::{io::{Read,Write},os::fd::AsRawFd,path::Path,process::{Child,ChildStdin,ChildStdout,Command,Stdio},time::{Duration,Instant}};
use muyon_plugin_contract_lab::{Json,parse};
use muyon_core_agent_lab::Result;
unsafe extern "C" { fn fcntl(fd:i32,cmd:i32,...)->i32; }
fn nonblock(fd:i32)->Result<()> {let flags=unsafe{fcntl(fd,3)};if flags<0||unsafe{fcntl(fd,4,flags|2048)}<0{return Err("plugin_pipe_flags".into())}Ok(())}
pub struct PluginProcess {child:Child,input:Option<ChildStdin>,output:ChildStdout,closed:bool,timeout:Duration}
impl PluginProcess {
 pub fn spawn(binary:&Path,timeout:Duration)->Result<Self>{Self::spawn_with_args(binary,&[],timeout)}
 pub fn spawn_with_args(binary:&Path,args:&[&str],timeout:Duration)->Result<Self>{
  if !binary.is_absolute()||timeout.is_zero()||timeout>Duration::from_secs(5){return Err("plugin_config".into())}
  let mut child=Command::new(binary).args(args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).env_clear().spawn().map_err(|_|"plugin_spawn")?;
  let input=child.stdin.take().ok_or("plugin_stdin")?;let output=child.stdout.take().ok_or("plugin_stdout")?;
  if nonblock(input.as_raw_fd()).and_then(|_|nonblock(output.as_raw_fd())).is_err(){let _=child.kill();let _=child.wait();return Err("plugin_pipe_flags".into())}
  Ok(Self{child,input:Some(input),output,closed:false,timeout})
 }
 pub fn pid(&self)->u32{self.child.id()}
 pub fn request(&mut self,request:Json)->Result<Json>{
  if self.closed{return Err("plugin_closed".into())}
  let result=self.exchange(request);if result.is_err(){self.close();}result
 }
 fn exchange(&mut self,request:Json)->Result<Json>{
  let text=request.encode();if text.len()>65536{return Err("plugin_frame_limit".into())}
  let bytes=format!("{text}\n").into_bytes();let deadline=Instant::now()+self.timeout;let mut sent=0;let mut received=Vec::new();
  while sent<bytes.len(){match self.input.as_mut().ok_or("plugin_closed")?.write(&bytes[sent..]){Ok(0)=>return Err("plugin_eof".into()),Ok(n)=>sent+=n,Err(e) if e.kind()==std::io::ErrorKind::WouldBlock=>{},Err(_)=>return Err("plugin_io".into())}if Instant::now()>=deadline{return Err("plugin_deadline".into())}if sent<bytes.len(){std::thread::sleep(Duration::from_millis(1));}}
  loop {let mut chunk=[0u8;4096];match self.output.read(&mut chunk){
   Ok(0)=>return Err("plugin_eof".into()),Ok(n)=>{received.extend_from_slice(&chunk[..n]);if received.len()>65537{return Err("plugin_frame_limit".into())}if let Some(end)=received.iter().position(|b|*b==b'\n'){if end+1!=received.len(){return Err("plugin_extra_frame".into())}return parse(&received[..end]).map_err(|_|"plugin_invalid_json".into())}},
   Err(e) if e.kind()==std::io::ErrorKind::WouldBlock=>{},Err(_)=>return Err("plugin_io".into())}
   if Instant::now()>=deadline{return Err("plugin_deadline".into())}std::thread::sleep(Duration::from_millis(1));
  }
 }
 pub fn close(&mut self){if self.closed{return}self.closed=true;self.input.take();let until=Instant::now()+Duration::from_millis(100);loop {if self.child.try_wait().ok().flatten().is_some(){return}if Instant::now()>=until{break}std::thread::sleep(Duration::from_millis(1));}let _=self.child.kill();let until=Instant::now()+Duration::from_secs(1);while self.child.try_wait().ok().flatten().is_none()&&Instant::now()<until{std::thread::sleep(Duration::from_millis(1));}}
}
impl Drop for PluginProcess{fn drop(&mut self){self.close();}}
