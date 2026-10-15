use crate::{hex, identifier, unhex, Result};
use std::{collections::BTreeMap, fs::{self, File, OpenOptions}, io::{Read,Write}, os::{fd::AsRawFd, unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt}}, path::{Path,PathBuf}, sync::atomic::{AtomicU64,Ordering}};
const MAX_FILE: u64=1_048_576;
static SERIAL: AtomicU64=AtomicU64::new(0);
unsafe extern "C" { fn flock(fd:i32, operation:i32)->i32; fn geteuid()->u32; }
pub struct DirectoryLock { _file: File }
pub fn validate_dir(dir:&Path)->Result<()> {
    let m=fs::symlink_metadata(dir).map_err(|e|e.to_string())?;
    if !m.is_dir() || m.file_type().is_symlink() || m.permissions().mode() & 0o777 != 0o700 || m.uid()!=unsafe{geteuid()} {return Err("private_directory_required".into());}
    // Reject symlink ancestors too: fixture paths must be structurally private.
    for p in dir.ancestors().filter(|p| !p.as_os_str().is_empty()) {
        if fs::symlink_metadata(p).map_err(|e|e.to_string())?.file_type().is_symlink(){return Err("symlink_directory".into());}
    }
    Ok(())
}
pub fn create_dir(dir:&Path)->Result<()> { fs::create_dir(dir).map_err(|e|e.to_string())?; fs::set_permissions(dir,fs::Permissions::from_mode(0o700)).map_err(|e|e.to_string())?; validate_dir(dir) }
pub fn lock(dir:&Path)->Result<DirectoryLock> {
    validate_dir(dir)?;
    let path=dir.join(".lock");
    if let Ok(m)=fs::symlink_metadata(&path) { if !m.is_file() || m.file_type().is_symlink(){return Err("invalid_lock".into());} }
    let f=OpenOptions::new().read(true).write(true).create(true).mode(0o600).open(path).map_err(|e|e.to_string())?;
    if unsafe{flock(f.as_raw_fd(),2|4)}!=0 {return Err("directory_locked".into());}
    Ok(DirectoryLock{_file:f})
}
pub fn read(path:&Path)->Result<String> {
    let m=fs::symlink_metadata(path).map_err(|e|e.to_string())?;
    if !m.is_file() || m.file_type().is_symlink() || m.len()>MAX_FILE {return Err("invalid_store_file".into());}
    let mut bytes=Vec::new();
    File::open(path).map_err(|e|e.to_string())?.take(MAX_FILE+1).read_to_end(&mut bytes).map_err(|e|e.to_string())?;
    if bytes.len() as u64>MAX_FILE{return Err("store_bound".into());}
    String::from_utf8(bytes).map_err(|_|"store_utf8".into())
}
pub fn atomic(dir:&Path,name:&str,text:&str)->Result<()> {
    if text.len() as u64>MAX_FILE{return Err("store_bound".into());}
    let target=dir.join(name);
    if let Ok(m)=fs::symlink_metadata(&target) {if !m.is_file() || m.file_type().is_symlink(){return Err("invalid_store_target".into());}}
    let temp=dir.join(format!(".{name}.{}.{}",std::process::id(),SERIAL.fetch_add(1,Ordering::SeqCst)));
    let mut f=OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temp).map_err(|e|e.to_string())?;
    f.write_all(text.as_bytes()).and_then(|_|f.sync_all()).map_err(|e|e.to_string())?;
    fs::rename(&temp,target).map_err(|e|e.to_string())?;
    File::open(dir).and_then(|f|f.sync_all()).map_err(|e|e.to_string())
}
pub fn rows(text:&str,header:&str)->Result<BTreeMap<String,String>> {
    if !text.ends_with('\n'){return Err("store_truncated".into());}
    let mut lines=text.lines(); if lines.next()!=Some(header){return Err("store_version".into());}
    let mut map=BTreeMap::new();
    for line in lines {let (k,v)=line.split_once('\t').ok_or("store_row")?; if !identifier(k)||v.contains('\t')||map.insert(k.to_string(),v.to_string()).is_some(){return Err("store_duplicate_or_invalid".into());}}
    Ok(map)
}
#[derive(Clone,Debug,PartialEq,Eq)]
pub struct Binding { pub invocation:String,pub task:String,pub attempt:String,pub turn:u64,pub scope:String,pub value:String }
impl Binding {
    pub fn encode(&self)->String {format!("{}\t{}\t{}\t{}\t{}\t{}",self.invocation,self.task,self.attempt,self.turn,hex(&self.scope),hex(&self.value))}
    pub fn decode(text:&str)->Result<Self> {let p:Vec<_>=text.split('\t').collect(); if p.len()!=6 || !p[..3].iter().all(|s|identifier(s)){return Err("binding_invalid".into());} let turn=p[3].parse::<u64>().map_err(|_|"binding_turn")?; if turn==0{return Err("binding_turn".into());} Ok(Self{invocation:p[0].into(),task:p[1].into(),attempt:p[2].into(),turn,scope:unhex(p[4])?,value:unhex(p[5])?})}
}
#[derive(Clone,Debug,PartialEq,Eq)]
pub struct Receipt {pub binding:Binding,pub id:String}
impl Receipt {pub fn message(&self)->String{format!("receipt={};value={}",self.id,self.binding.value)}}
#[derive(Clone,Debug)]
pub struct EffectStore {pub value:String,pub receipts:Vec<Receipt>}
pub trait ToolPort {fn lookup(&self,binding:&Binding)->Result<Option<Receipt>>;fn execute_once(&mut self,binding:&Binding)->Result<Receipt>;}
pub struct FixtureTool {pub dir:PathBuf}
impl EffectStore {
    pub fn empty()->Self{Self{value:String::new(),receipts:Vec::new()}}
    pub fn encode(&self)->String {let mut out=format!("CORE_EFFECT_V1\ncount\t{}\nvalue\t{}\n",self.receipts.len(),hex(&self.value));for r in &self.receipts{out.push_str(&format!("receipt\t{}\t{}\n",r.binding.encode(),r.id));}out}
    pub fn load(dir:&Path)->Result<Self> {
        let text=read(&dir.join("effects.db"))?;if !text.ends_with('\n'){return Err("effect_truncated".into());}
        let mut lines=text.lines();if lines.next()!=Some("CORE_EFFECT_V1"){return Err("effect_version".into());}
        let count=lines.next().and_then(|l|l.strip_prefix("count\t")).ok_or("effect_count")?.parse::<usize>().map_err(|_|"effect_count")?;
        if count>128{return Err("effect_count".into());}
        let value=unhex(lines.next().and_then(|l|l.strip_prefix("value\t")).ok_or("effect_value")?)?;
        let mut receipts:Vec<Receipt>=Vec::new();
        for line in lines {let raw=line.strip_prefix("receipt\t").ok_or("receipt_row")?;let (binding,id)=raw.rsplit_once('\t').ok_or("receipt_row")?;let binding=Binding::decode(binding)?;if !identifier(id)||id!=format!("r-{}",binding.invocation)||receipts.iter().any(|r|r.binding.invocation==binding.invocation){return Err("receipt_identity".into());}receipts.push(Receipt{binding,id:id.into()});}
        if receipts.len()!=count || receipts.last().map(|r|r.binding.value.as_str()).unwrap_or("")!=value {return Err("effect_atomic_invariant".into());}
        Ok(Self{value,receipts})
    }
}
impl ToolPort for FixtureTool {
    fn lookup(&self,b:&Binding)->Result<Option<Receipt>> {let state=EffectStore::load(&self.dir)?;if let Some(r)=state.receipts.iter().find(|r|r.binding.invocation==b.invocation){if &r.binding!=b{return Err("binding_conflict".into());}return Ok(Some(r.clone()));}Ok(None)}
    fn execute_once(&mut self,b:&Binding)->Result<Receipt> {
        let mut state=EffectStore::load(&self.dir)?;
        if let Some(r)=state.receipts.iter().find(|r|r.binding.invocation==b.invocation){if &r.binding!=b{return Err("binding_conflict".into());}return Ok(r.clone());}
        if state.receipts.len()>=128{return Err("effect_limit".into());}
        let r=Receipt{binding:b.clone(),id:format!("r-{}",b.invocation)};
        state.value=b.value.clone();state.receipts.push(r.clone());atomic(&self.dir,"effects.db",&state.encode())?;Ok(r)
    }
}
