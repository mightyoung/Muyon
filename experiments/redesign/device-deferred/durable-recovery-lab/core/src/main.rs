//! Linux-only provisional private-file laboratory. Not product storage or authority.
use std::{collections::BTreeMap, fs::{self,File,OpenOptions}, io::{Read,Write}, os::fd::AsRawFd, path::{Path,PathBuf}};
use serde::{Deserialize,Serialize,de::DeserializeOwned};
use sha2::{Sha256,Digest};
const LIMIT:u64=2*1024*1024;
type Result<T>=std::result::Result<T,&'static str>;
#[derive(Clone,Debug,Serialize,Deserialize,PartialEq,Eq)]
#[serde(deny_unknown_fields)]
struct Domain{store:String,scope:String,stream:String}
fn domain()->Domain{Domain{store:"synthetic-store".into(),scope:"synthetic-scope".into(),stream:"synthetic-stream".into()}}
#[derive(Clone,Debug,Serialize,Deserialize,PartialEq,Eq)]
#[serde(deny_unknown_fields)]
struct Args{raw_utf16:Vec<u16>}
#[derive(Clone,Debug,Serialize,Deserialize,PartialEq,Eq)]
#[serde(deny_unknown_fields)]
struct Command{domain:Domain,intent:String,operation:String,args:Args}
#[derive(Clone,Debug,Serialize,Deserialize,PartialEq,Eq)]
#[serde(deny_unknown_fields)]
struct Cursor{store:String,scope:String,stream:String,seq:String}
fn cursor(seq:u64)->Cursor{let d=domain();Cursor{store:d.store,scope:d.scope,stream:d.stream,seq:seq.to_string()}}
#[derive(Clone,Debug,Serialize,Deserialize,PartialEq,Eq)]
#[serde(deny_unknown_fields)]
struct Pair{cursor:Cursor,state:String}
#[derive(Clone,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
struct Projection{pair:Pair,epoch:String}
#[derive(Clone,Debug,Serialize,Deserialize,PartialEq,Eq)]
#[serde(deny_unknown_fields)]
struct Receipt{id:String,pair_id:String,command:Command,effect_count:String}
#[derive(Clone,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
struct Entry{command:Command,receipt:Option<Receipt>}
#[derive(Clone,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
struct Ledger{domain:Domain,entries:BTreeMap<String,Entry>}
#[derive(Clone,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
struct EffectRecord{command:Command,count:String}
#[derive(Clone,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
struct Effects{owner:String,pair_id:String,count:String,entries:Vec<EffectRecord>}
#[derive(Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
struct Owner{effect_dir:String,pair_id:String}
#[derive(Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
struct Envelope<T>{format:u32,payload:T,checksum:String}
#[derive(Deserialize,PartialEq)]
#[serde(rename_all="snake_case")]
enum Op{Submit,Lookup,Snapshot,Reconnect,InstallSnapshot}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request{
 protocol:u32,op:Op,domain:Domain,epoch:String,
 #[serde(default,deserialize_with="nonnull")]intent:Option<String>,
 #[serde(default,deserialize_with="nonnull")]operation:Option<String>,
 #[serde(default,deserialize_with="nonnull")]args:Option<Args>,
 #[serde(default,deserialize_with="nonnull")]snapshot:Option<Pair>
}
fn nonnull<'de,D,T>(d:D)->std::result::Result<Option<T>,D::Error>where D:serde::Deserializer<'de>,T:Deserialize<'de>{T::deserialize(d).map(Some)}
#[derive(Serialize)]
struct Reply{kind:&'static str,reason:Option<&'static str>,receipt:Option<Receipt>,snapshot:Option<Pair>,display_admission:&'static str}
fn num(s:&str)->Result<u64>{if s.is_empty() || (s.len()>1&&s.starts_with('0')) || !s.bytes().all(|b|b.is_ascii_digit()){return Err("invalid_counter");}s.parse().map_err(|_|"invalid_counter")}
fn label(s:&str)->bool{!s.is_empty()&&s.len()<=128}
fn checksum<T:Serialize>(value:&T)->Result<String>{let bytes=serde_json::to_vec(value).map_err(|_|"serialization")?;Ok(Sha256::digest(bytes).iter().map(|b|format!("{b:02x}")).collect())}
fn die(fault:&str,point:&str){
 if fault==point{std::process::exit(90);}
 if fault==format!("pause_{point}"){eprintln!("fault_barrier");unsafe{raise(19);}}
}
fn write<T:Serialize>(path:&Path,value:&T,fault:&str)->Result<()> {
 let parent=path.parent().ok_or("path")?;
 let envelope=Envelope{format:0,payload:value,checksum:checksum(value)?};
 let data=serde_json::to_vec(&envelope).map_err(|_|"serialization")?;if data.len() as u64>LIMIT{return Err("storage_limit");}
 let temporary=parent.join(format!(".write-{}",std::process::id()));
 let mut file=OpenOptions::new().create_new(true).write(true).open(&temporary).map_err(|_|"storage_write")?;
 file.write_all(&data).and_then(|_|file.sync_all()).map_err(|_|"storage_write")?;
 if path.file_name().is_some_and(|s|s=="projection.json"){die(fault,"during_pair_temp");}
 fs::rename(&temporary,path).map_err(|_|"storage_write")?;
 File::open(parent).and_then(|f|f.sync_all()).map_err(|_|"storage_sync")?;
 Ok(())
}
fn read<T:DeserializeOwned+Serialize>(path:&Path)->Result<T>{
 if fs::symlink_metadata(path).map_err(|_|"storage_read")?.file_type().is_symlink(){return Err("storage_read");}
 let file=File::open(path).map_err(|_|"storage_read")?;
 let mut bytes=Vec::new();file.take(LIMIT+1).read_to_end(&mut bytes).map_err(|_|"storage_read")?;
 if bytes.len() as u64>LIMIT{return Err("storage_limit");}
 let envelope:Envelope<T>=serde_json::from_slice(&bytes).map_err(|_|"storage_corrupt")?;
 if envelope.format!=0 || checksum(&envelope.payload)?!=envelope.checksum{return Err("storage_corrupt");}Ok(envelope.payload)
}
// flock locks the open file description; process termination closes it. Never
// unlink a lock path: that would create a second independent lock inode.
unsafe extern "C" {fn flock(fd:i32,operation:i32)->i32;fn raise(signal:i32)->i32;}
fn create_dirs(dir:&Path)->Result<()>{
 let mut missing=Vec::new();let mut current=dir;
 while !current.exists(){missing.push(current.to_path_buf());current=current.parent().ok_or("storage_directory")?;}
 fs::create_dir_all(dir).map_err(|_|"storage_directory")?;
 for path in missing.iter().rev(){let parent=path.parent().ok_or("storage_directory")?;File::open(parent).and_then(|f|f.sync_all()).map_err(|_|"storage_sync")?;}
 Ok(())
}
fn lock_existing(dir:&Path)->Result<File>{
 if fs::symlink_metadata(dir).map_err(|_|"storage_directory")?.file_type().is_symlink(){return Err("storage_directory");}
 let path=dir.join(".lock");if fs::symlink_metadata(&path).map_err(|_|"storage_lock")?.file_type().is_symlink(){return Err("storage_lock");}
 let f=File::open(path).map_err(|_|"storage_lock")?;
 if unsafe{flock(f.as_raw_fd(),2)}!=0{return Err("storage_lock");}Ok(f)
}
fn lock(dir:&Path)->Result<File>{
 create_dirs(dir)?;
 if fs::symlink_metadata(dir).map_err(|_|"storage_directory")?.file_type().is_symlink(){return Err("storage_directory");}
 let f=OpenOptions::new().create(true).truncate(false).read(true).write(true).open(dir.join(".lock")).map_err(|_|"storage_lock")?;
 if unsafe{flock(f.as_raw_fd(),2)}!=0{return Err("storage_lock");}Ok(f)
}
fn shape(req:&Request)->Result<Option<Command>>{
 if req.protocol!=0 || req.domain!=domain() || !label(&req.epoch){return Err("invalid_request");}
 if matches!(req.op,Op::Submit|Op::Lookup){
  if req.snapshot.is_some(){return Err("invalid_request");}
  let c=Command{domain:req.domain.clone(),intent:req.intent.clone().ok_or("invalid_request")?,operation:req.operation.clone().ok_or("invalid_request")?,args:req.args.clone().ok_or("invalid_request")?};
  if !label(&c.intent)||c.operation!="synthetic_increment"||c.args.raw_utf16.len()>2000{return Err("invalid_request");}Ok(Some(c))
 }else{
  if req.intent.is_some()||req.operation.is_some()||req.args.is_some(){return Err("invalid_request");}
  if (req.op==Op::InstallSnapshot)!=req.snapshot.is_some(){return Err("invalid_request");}Ok(None)
 }
}
struct Store{state:PathBuf,effect:PathBuf,ledger:Ledger,projection:Option<Projection>,effects:Effects,_state_lock:File,_effect_lock:File}
impl Store{
 fn open(state:&Path,effect:&Path,lookup:bool)->Result<Self>{
  let state_lock=if lookup{lock_existing(state)?}else{lock(state)?};
  if !lookup{create_dirs(effect)?;}
  if fs::canonicalize(state).map_err(|_|"storage_directory")?==fs::canonicalize(effect).map_err(|_|"storage_directory")?{return Err("same_directory");}
  let effect_lock=if lookup{lock_existing(effect)?}else{lock(effect)?};
  let state=fs::canonicalize(state).map_err(|_|"storage_directory")?;let effect=fs::canonicalize(effect).map_err(|_|"storage_directory")?;
  if state==effect{return Err("same_directory");}
  let owner=state.join("owner.json");
  if !owner.exists(){
   if lookup{return Err("storage_read");}
   // An existing orphan/foreign business file is not an empty new store.
   if state.join("ledger.json").exists()||state.join("projection.json").exists()||effect.join("effects.json").exists(){return Err("partial_initialization");}
   write(&state.join("ledger.json"),&Ledger{domain:domain(),entries:BTreeMap::new()},"")?;
   write(&state.join("projection.json"),&Projection{pair:Pair{cursor:cursor(0),state:"initial".into()},epoch:"epoch-0".into()},"")?;
   let mut random=[0u8;16];File::open("/dev/urandom").and_then(|mut f|f.read_exact(&mut random)).map_err(|_|"pair_identity_unavailable")?;
   let pair_id:String=random.iter().map(|b|format!("{b:02x}")).collect();
   write(&effect.join("effects.json"),&Effects{owner:state.to_string_lossy().into(),pair_id:pair_id.clone(),count:"0".into(),entries:Vec::new()},"")?;
   write(&owner,&Owner{effect_dir:effect.to_string_lossy().into(),pair_id},"")?;
  }
  let binding:Owner=read(&owner)?;if binding.effect_dir!=effect.to_string_lossy(){return Err("store_binding");}
  let ledger:Ledger=read(&state.join("ledger.json"))?;let mut projection:Option<Projection>=if lookup{read(&state.join("projection.json")).ok()}else{Some(read(&state.join("projection.json"))?)};let effects:Effects=read(&effect.join("effects.json"))?;
  if ledger.domain!=domain()||effects.owner!=state.to_string_lossy()||num(&effects.count)? as usize!=effects.entries.len()||effects.pair_id!=binding.pair_id||binding.pair_id.len()!=32{return Err("storage_corrupt");}
  for (index,entry) in effects.entries.iter().enumerate(){if num(&entry.count)?!=index as u64+1||entry.command.domain!=domain(){return Err("storage_corrupt");}}
  for (intent,entry) in &ledger.entries{
   if &entry.command.intent!=intent||entry.command.domain!=domain()||entry.command.operation!="synthetic_increment"||entry.command.args.raw_utf16.len()>2000{return Err("storage_corrupt");}
   if let Some(receipt)=&entry.receipt{if receipt.command!=entry.command||!Self::verify(receipt,&effects){return Err("receipt_corrupt");}}
  }
  if let Some(p)=&projection{
   let seq=num(&p.pair.cursor.seq);
   let valid=seq.is_ok_and(|seq|p.pair.cursor==cursor(seq)&&seq<=num(&effects.count).unwrap()&&p.pair.state==if seq==0{"initial".to_string()}else{format!("effect:{seq}")})&&label(&p.epoch);
   if !valid{if lookup{projection=None;}else{return Err("projection_corrupt");}}
  }
  Ok(Self{state,effect,ledger,projection,effects,_state_lock:state_lock,_effect_lock:effect_lock})
 }
 fn verify(r:&Receipt,e:&Effects)->bool{
  let Ok(count)=num(&r.effect_count)else{return false;};
  count>0&&r.pair_id==e.pair_id&&r.id==format!("receipt-{}-{count}",e.pair_id)&&e.entries.get(count as usize-1).is_some_and(|entry|entry.command==r.command&&entry.count==r.effect_count)
 }
 fn reply(&self,epoch:&str,kind:&'static str,reason:Option<&'static str>,receipt:Option<Receipt>)->Reply{
  Reply{kind,reason,receipt,snapshot:self.projection.as_ref().map(|p|p.pair.clone()),display_admission:if self.projection.as_ref().is_some_and(|p|epoch==p.epoch){"current"}else{"stale"}}
 }
 fn handle(&mut self,req:Request,command:Option<Command>,fault:&str)->Result<Reply>{
  if let Some(c)=command{
   if let Some(entry)=self.ledger.entries.get(&c.intent){
    if entry.command!=c{return Ok(self.reply(&req.epoch,"conflict",Some("intent_binding"),None));}
    if let Some(r)=entry.receipt.clone(){
     if !Self::verify(&r,&self.effects){return Err("receipt_unverified");}
     return Ok(self.reply(&req.epoch,"committed",None,Some(r)));
    }
    // UNKNOWN_GUARD: possible dispatch is never retried, even if effect count 0.
    return Ok(self.reply(&req.epoch,"unknown",Some("pending_without_receipt"),None));
   }
   // SOURCE_HISTORY_GUARD: a restored pre-pending state never permits replay
   // over the still-existing independent external effect source.
   if let Some(existing)=self.effects.entries.iter().find(|e|e.command.intent==c.intent){
    return Ok(self.reply(&req.epoch,if existing.command==c{"unknown"}else{"conflict"},Some("effect_without_receipt_ledger"),None));
   }
   if req.op==Op::Lookup{return Ok(self.reply(&req.epoch,"unknown",Some("not_found"),None));}
   self.ledger.entries.insert(c.intent.clone(),Entry{command:c.clone(),receipt:None});
   // PENDING_ORDER: persisted and fsynced before any external synthetic effect.
   write(&self.state.join("ledger.json"),&self.ledger,"")?;
   die(fault,"after_pending");die(fault,"before_effect");
   let count=num(&self.effects.count)?.checked_add(1).ok_or("counter_overflow")?;
   self.effects.count=count.to_string();self.effects.entries.push(EffectRecord{command:c.clone(),count:count.to_string()});
   write(&self.effect.join("effects.json"),&self.effects,"")?;
   die(fault,"after_effect");die(fault,"before_receipt");
   let receipt=Receipt{id:format!("receipt-{}-{count}",self.effects.pair_id),pair_id:self.effects.pair_id.clone(),command:c.clone(),effect_count:count.to_string()};
   self.ledger.entries.get_mut(&c.intent).unwrap().receipt=Some(receipt.clone());
   write(&self.state.join("ledger.json"),&self.ledger,"")?;
   die(fault,"after_receipt");die(fault,"before_pair");
   self.projection.as_mut().ok_or("projection_unavailable")?.pair=Pair{cursor:cursor(count),state:format!("effect:{count}")};
   write(&self.state.join("projection.json"),self.projection.as_ref().ok_or("projection_unavailable")?,fault)?;
   die(fault,"after_pair");
   return Ok(self.reply(&req.epoch,"committed",None,Some(receipt)));
  }
  match req.op{
   Op::Snapshot=>Ok(self.reply(&req.epoch,"snapshot",None,None)),
   Op::Reconnect=>{self.projection.as_mut().ok_or("projection_unavailable")?.epoch=req.epoch.clone();write(&self.state.join("projection.json"),self.projection.as_ref().ok_or("projection_unavailable")?,"")?;Ok(self.reply(&req.epoch,"snapshot",None,None))},
   Op::InstallSnapshot=>{
    let candidate=req.snapshot.unwrap();let seq=num(&candidate.cursor.seq)?;let current=num(&self.projection.as_ref().ok_or("projection_unavailable")?.pair.cursor.seq)?;
    if candidate.cursor!=cursor(seq)||seq<current||seq>num(&self.effects.count)?||candidate.state!=if seq==0{"initial".into()}else{format!("effect:{seq}")}{return Ok(self.reply(&req.epoch,"rejected",Some("snapshot_invalid_or_stale"),None));}
    self.projection.as_mut().ok_or("projection_unavailable")?.pair=candidate;write(&self.state.join("projection.json"),self.projection.as_ref().ok_or("projection_unavailable")?,fault)?;
    Ok(self.reply(&req.epoch,"snapshot",None,None))
   },_=>Err("invalid_request")
  }
 }
}
fn failure(kind:&'static str,reason:&'static str)->Reply{Reply{kind,reason:Some(reason),receipt:None,snapshot:None,display_admission:"stale"}}
fn run()->Reply{
 let args:Vec<_>=std::env::args().collect();
 if args.len()!=7&&args.len()!=9{return failure("rejected","cli_arguments");}
 if args[1]!="--state-dir"||args[3]!="--effect-dir"||args[5]!="--request"||(args.len()==9&&args[7]!="--fault"){return failure("rejected","cli_arguments");}
 let fault=if args.len()==9{args[8].as_str()}else{""};
 if !["","after_pending","before_effect","after_effect","before_receipt","after_receipt","before_pair","after_pair","during_pair_temp","pause_after_pending","pause_after_effect"].contains(&fault){return failure("rejected","invalid_fault");}
 if args[6].len()>32768{return failure("rejected","request_limit");}
 let req:Request=match serde_json::from_str(&args[6]){Ok(r)=>r,Err(_)=>return failure("rejected","invalid_request")};
 let command=match shape(&req){Ok(c)=>c,Err(e)=>return failure("rejected",e)};
 if req.op==Op::Lookup&&!Path::new(&args[2]).exists()&&!Path::new(&args[4]).exists(){return failure("unknown","not_found");}
 let mut store=match Store::open(Path::new(&args[2]),Path::new(&args[4]),req.op==Op::Lookup){Ok(s)=>s,Err(e)=>return failure("unavailable",e)};
 match store.handle(req,command,fault){Ok(r)=>r,Err(e)=>failure("unavailable",e)}
}
fn main(){let reply=run();println!("{}",serde_json::to_string(&reply).unwrap());}
