use crate::{hex, unhex, identifier, Result, model::{self, Message, Role, ModelRequest, ModelEvent, Provider, ScriptedProvider}, policy::{HostFacts,Mode,Decision,Authorizer,FixtureAuthorizer}, store::{self,Binding,Receipt,EffectStore,FixtureTool,ToolPort}};
use std::{collections::BTreeMap, io::{self,Write}, path::{Path,PathBuf}, time::{SystemTime,UNIX_EPOCH}};
#[derive(Clone,Debug)]
pub struct Limits {pub steps:u64,pub calls:u64,pub context:u64,pub output:u64,pub total:u64}
impl Default for Limits {fn default()->Self{Self{steps:16,calls:16,context:65536,output:16384,total:262144}}}
impl Limits {pub fn validate(&self)->Result<()>{if [self.steps,self.calls,self.context,self.output,self.total].iter().any(|n|*n==0||*n>1_000_000){Err("invalid_limits".into())}else{Ok(())}}}
#[derive(Clone,Debug,Default)]
pub struct Counters {pub steps:u64,pub calls:u64,pub output:u64,pub total:u64,pub confirmations:u64}
#[derive(Clone,Debug)]
pub struct State {
    pub task:String,pub attempt:String,pub status:String,pub reason:String,pub script:String,pub scope:String,
    pub facts:HostFacts,pub limits:Limits,pub counters:Counters,pub context:Vec<Message>,pub position:usize,
    pub binding:Option<Binding>,pub unresolved:bool,pub receipt:String,pub answer:String,pub cancelled:bool,
    pub correlations:BTreeMap<String,Binding>,pub behavior:String,
    pub resume_status:String,pub resume_reason:String,pub result_pending:bool,
    pub receipt_binding:Option<Binding>,pub evidence_hold:bool,
}
fn mode_name(mode:Mode)->&'static str {match mode{Mode::ReadOnly=>"read-only",Mode::AskEveryTime=>"ask-every-time",Mode::Auto=>"auto",Mode::FullAllow=>"full-allow"}}
pub fn parse_mode(s:&str)->Result<Mode>{match s{"read-only"=>Ok(Mode::ReadOnly),"ask-every-time"=>Ok(Mode::AskEveryTime),"auto"=>Ok(Mode::Auto),"full-allow"=>Ok(Mode::FullAllow),_=>Err("invalid_mode".into())}}
pub fn boolean(s:&str)->Result<bool>{match s{"true"=>Ok(true),"false"=>Ok(false),_=>Err("invalid_boolean".into())}}
impl State {
    pub fn new(script:String,input:String,scope:String,facts:HostFacts,limits:Limits,behavior:String)->Result<Self>{
        ScriptedProvider::parse(&script)?; limits.validate()?;
        if input.len()>65536||scope.is_empty()||scope.len()>1024||!matches!(behavior.as_str(),"normal"|"fail"|"lose-response"){return Err("invalid_start".into());}
        if input.len() as u64>limits.context{return Err("input_context_limit".into());}
        let nonce=SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_|"clock")?.as_nanos();
        let task=format!("t-{}-{nonce}",std::process::id());
        Ok(Self{attempt:format!("a-{}-{nonce}",std::process::id()),task,status:"ready".into(),reason:String::new(),script,scope,facts,limits,counters:Counters::default(),context:vec![Message{role:Role::User,text:input}],position:0,binding:None,unresolved:false,receipt:String::new(),answer:String::new(),cancelled:false,correlations:BTreeMap::new(),behavior,resume_status:String::new(),resume_reason:String::new(),result_pending:false,receipt_binding:None,evidence_hold:false})
    }
    pub fn encode(&self)->String{
        let mut m=BTreeMap::new();
        macro_rules! put {($k:expr,$v:expr)=>{m.insert($k.to_string(),$v.to_string());};}
        put!("task",self.task);put!("attempt",self.attempt);put!("status",self.status);put!("reason",self.reason);
        put!("script_hex",hex(&self.script));put!("scope_hex",hex(&self.scope));put!("mode",mode_name(self.facts.mode));
        put!("high",self.facts.high);put!("hard_ok",self.facts.hard_ok);put!("revoked",self.facts.revoked);put!("scope_ok",self.facts.scope_ok);put!("classification_ok",self.facts.classification_ok);put!("confirmed",self.facts.confirmed);put!("tainted",self.facts.tainted);put!("new_destination",self.facts.new_destination);
        put!("max_steps",self.limits.steps);put!("max_calls",self.limits.calls);put!("max_context",self.limits.context);put!("max_output",self.limits.output);put!("max_total",self.limits.total);
        put!("steps",self.counters.steps);put!("calls",self.counters.calls);put!("output",self.counters.output);put!("total",self.counters.total);put!("confirmations",self.counters.confirmations);
        put!("context_hex",hex(&model::encode_context(&self.context)));put!("position",self.position);
        put!("pending_hex",hex(&self.binding.as_ref().map(|b|b.encode()).unwrap_or_default()));put!("unresolved",self.unresolved);put!("receipt",self.receipt);put!("answer_hex",hex(&self.answer));put!("cancelled",self.cancelled);put!("correlations_hex",hex(&self.correlations.iter().map(|(k,b)|format!("{}\t{}\n",k,hex(&b.encode()))).collect::<String>()));put!("behavior",self.behavior);
        put!("receipt_binding_hex",hex(&self.receipt_binding.as_ref().map(|b|b.encode()).unwrap_or_default()));put!("evidence_hold",self.evidence_hold);
        put!("resume_status",self.resume_status);put!("resume_reason",self.resume_reason);put!("result_pending",self.result_pending);
        let mut out=String::from("CORE_TASK_V1\n");for(k,v)in m{out.push_str(&format!("{k}\t{v}\n"));}out
    }
    pub fn load(dir:&Path)->Result<Self>{
        let mut m=store::rows(&store::read(&dir.join("task.db"))?,"CORE_TASK_V1")?;
        fn take(m:&mut BTreeMap<String,String>,k:&str)->Result<String>{m.remove(k).ok_or_else(||format!("missing_{k}"))}
        fn number(m:&mut BTreeMap<String,String>,k:&str)->Result<u64>{take(m,k)?.parse().map_err(|_|format!("invalid_{k}"))}
        fn flag(m:&mut BTreeMap<String,String>,k:&str)->Result<bool>{boolean(&take(m,k)?)}
        let task=take(&mut m,"task")?;let attempt=take(&mut m,"attempt")?;let status=take(&mut m,"status")?;let reason=take(&mut m,"reason")?;
        let script=unhex(&take(&mut m,"script_hex")?)?;let scope=unhex(&take(&mut m,"scope_hex")?)?;
        let facts=HostFacts{mode:parse_mode(&take(&mut m,"mode")?)?,high:flag(&mut m,"high")?,hard_ok:flag(&mut m,"hard_ok")?,revoked:flag(&mut m,"revoked")?,scope_ok:flag(&mut m,"scope_ok")?,classification_ok:flag(&mut m,"classification_ok")?,confirmed:flag(&mut m,"confirmed")?,tainted:flag(&mut m,"tainted")?,new_destination:flag(&mut m,"new_destination")?};
        let limits=Limits{steps:number(&mut m,"max_steps")?,calls:number(&mut m,"max_calls")?,context:number(&mut m,"max_context")?,output:number(&mut m,"max_output")?,total:number(&mut m,"max_total")?};limits.validate()?;
        let counters=Counters{steps:number(&mut m,"steps")?,calls:number(&mut m,"calls")?,output:number(&mut m,"output")?,total:number(&mut m,"total")?,confirmations:number(&mut m,"confirmations")?};
        let context=model::decode_context(&unhex(&take(&mut m,"context_hex")?)?)?;let position=usize::try_from(number(&mut m,"position")?).map_err(|_|"position_overflow")?;
        let raw=unhex(&take(&mut m,"pending_hex")?)?;let binding=if raw.is_empty(){None}else{Some(Binding::decode(&raw)?)};
        let unresolved=flag(&mut m,"unresolved")?;let receipt=take(&mut m,"receipt")?;let answer=unhex(&take(&mut m,"answer_hex")?)?;let cancelled=flag(&mut m,"cancelled")?;
        let mut correlations=BTreeMap::new();
        for line in unhex(&take(&mut m,"correlations_hex")?)?.lines(){
            let (call,raw)=line.split_once('\t').ok_or("correlation_row")?;
            if !identifier(call)||correlations.insert(call.to_string(),Binding::decode(&unhex(raw)?)?).is_some(){return Err("correlation_identity".into());}
        }
        let behavior=take(&mut m,"behavior")?;
        let raw_receipt_binding=unhex(&take(&mut m,"receipt_binding_hex")?)?;
        let receipt_binding=if raw_receipt_binding.is_empty(){None}else{Some(Binding::decode(&raw_receipt_binding)?)};
        let evidence_hold=flag(&mut m,"evidence_hold")?;
        let resume_status=take(&mut m,"resume_status")?;let resume_reason=take(&mut m,"resume_reason")?;let result_pending=flag(&mut m,"result_pending")?;
        if !m.is_empty() || !identifier(&task)||!identifier(&attempt)||!matches!(status.as_str(),"ready"|"waiting"|"completed"|"denied"|"failed"|"cancelled"|"outcome_unknown"|"budget_exhausted") || !matches!(behavior.as_str(),"normal"|"fail"|"lose-response") || scope.is_empty()||scope.len()>1024 || position>128 || counters.steps>1_000_000||counters.calls>1_000_000||counters.output>2_000_000||counters.total>4_000_000 || correlations.len()>128 || (!receipt.is_empty()&&!identifier(&receipt)) {return Err("invalid_task_state".into());}
        if (unresolved||status=="waiting")&&binding.is_none(){return Err("missing_binding".into());}
        if let Some(b)=&binding{if b.task!=task||b.attempt!=attempt||b.scope!=scope||b.turn>counters.steps{return Err("task_binding_mismatch".into());}}
        if !matches!(resume_status.as_str(),""|"ready"|"waiting"|"outcome_unknown"|"completed"|"cancelled"|"denied"|"failed"|"budget_exhausted")||evidence_hold!=!resume_status.is_empty(){return Err("invalid_resume_barrier".into());}
        if receipt.is_empty()!=receipt_binding.is_none() || (evidence_hold&&receipt_binding.is_none()){return Err("missing_receipt_binding".into());}
        if let Some(b)=&receipt_binding{if receipt!=format!("r-{}",b.invocation)||!correlations.values().any(|original|original==b){return Err("receipt_binding_identity".into());}}
        for b in correlations.values(){if b.task!=task||b.attempt!=attempt||b.scope!=scope||b.turn>counters.steps{return Err("correlation_binding_mismatch".into());}}
        if let Some(b)=&binding{if !correlations.values().any(|original|original==b){return Err("missing_correlation_binding".into());}}
        ScriptedProvider::parse(&script)?;
        Ok(Self{task,attempt,status,reason,script,scope,facts,limits,counters,context,position,binding,unresolved,receipt,answer,cancelled,correlations,behavior,resume_status,resume_reason,result_pending,receipt_binding,evidence_hold})
    }
    pub fn save(&self,dir:&Path)->Result<()>{store::atomic(dir,"task.db",&self.encode())}
    fn stop(&mut self,status:&str,reason:&str){self.status=status.into();self.reason=reason.into();}
}
#[derive(Default)]
pub struct Hooks {pub checkpoint:Option<String>,pub io_fault:Option<String>}
impl Hooks {
    fn checkpoint(&self,name:&str)->Result<()>{if self.checkpoint.as_deref()==Some(name){println!("checkpoint={name}");io::stdout().flush().map_err(|e|e.to_string())?;let mut line=String::new();if io::stdin().read_line(&mut line).map_err(|e|e.to_string())?==0{return Err("checkpoint_eof".into());}}Ok(())}
    fn fault(&self,name:&str)->Result<()>{if self.io_fault.as_deref()==Some(name){Err(format!("injected_io_{name}"))}else{Ok(())}}
}
pub struct Agent {pub dir:PathBuf,pub state:State}
impl Agent {
    pub fn start(dir:&Path,state:State)->Result<Self>{store::create_dir(dir)?;let _lock=store::lock(dir)?;store::atomic(dir,"effects.db",&EffectStore::empty().encode())?;state.save(dir)?;Ok(Self{dir:dir.to_path_buf(),state})}
    pub fn open(dir:&Path)->Result<Self>{
        let mut state=State::load(dir)?;
        // Historical receipt evidence owns a binding distinct from the next pending call.
        if !state.evidence_hold {
            if let Some(binding)=state.receipt_binding.clone() {
                if !matches!((FixtureTool{dir:dir.to_path_buf()}).lookup(&binding),Ok(Some(_))) {
                    state.resume_status=state.status.clone();state.resume_reason=state.reason.clone();
                    state.evidence_hold=true;state.stop("outcome_unknown","receipt_unavailable");
                }
            }
        }
        Ok(Self{dir:dir.to_path_buf(),state})
    }
    fn cancelled(&mut self)->Result<bool>{
        let path=self.dir.join("cancel.request");
        match std::fs::symlink_metadata(&path){Ok(_)=>{if store::read(&path)?!="CORE_CANCEL_V1\n"{return Err("invalid_cancel_signal".into());}self.state.cancelled=true;},Err(e) if e.kind()==io::ErrorKind::NotFound=>{},Err(e)=>return Err(e.to_string())}
        Ok(self.state.cancelled)
    }
    fn apply_receipt(&mut self,r:Receipt)->Result<()> {
        if self.state.binding.as_ref()!=Some(&r.binding){return Err("receipt_binding_mismatch".into());}
        self.state.receipt_binding=Some(r.binding.clone());
        if self.state.result_pending || self.state.receipt!=r.id {
            let text=r.message();self.state.receipt=r.id;self.state.result_pending=false;
            if model::context_bytes(&self.state.context).saturating_add(text.len() as u64)>self.state.limits.context {self.state.unresolved=false;self.state.stop("budget_exhausted","context");return Ok(());}
            self.state.context.push(Message{role:Role::Tool,text});
        }
        self.state.unresolved=false;
        if self.state.cancelled{self.state.stop("cancelled","cancel_after_commit");}
        else{self.state.stop("ready","");}Ok(())
    }
    pub fn lookup(&mut self)->Result<()> {
        if !self.state.evidence_hold && !self.state.unresolved{return Ok(());}
        self.cancelled()?;
        if self.state.evidence_hold {
            let original=self.state.receipt_binding.clone().ok_or("missing_receipt_binding")?;
            match (FixtureTool{dir:self.dir.clone()}).lookup(&original) {
                Ok(Some(r)) if r.id==self.state.receipt=>{
                    self.state.evidence_hold=false;
                    let resume_status=std::mem::take(&mut self.state.resume_status);
                    let resume_reason=std::mem::take(&mut self.state.resume_reason);
                    if self.state.cancelled && !self.state.unresolved{self.state.stop("cancelled","cancel_requested");}
                    else{self.state.stop(&resume_status,&resume_reason);}
                },
                _=>{self.state.stop("outcome_unknown","receipt_unavailable");return self.state.save(&self.dir);},
            }
        }
        // Restoring historical evidence alone never dispatches the newer prepared call.
        if !self.state.unresolved{return self.state.save(&self.dir);}
        let binding=self.state.binding.clone().ok_or("missing_binding")?;
        match (FixtureTool{dir:self.dir.clone()}).lookup(&binding) {
            Ok(Some(r))=>self.apply_receipt(r)?,
            Ok(None)=>self.state.stop("outcome_unknown","receipt_not_found"),
            Err(_)=>self.state.stop("outcome_unknown","receipt_unavailable"),
        }
        self.state.save(&self.dir)
    }
    pub fn cancel(&mut self)->Result<()> {
        self.state.cancelled=true;
        if self.state.evidence_hold || self.state.unresolved {self.lookup()?;} else {self.state.stop("cancelled","cancel_requested");}
        self.state.save(&self.dir)
    }
    fn dispatch(&mut self,h:&Hooks)->Result<()> {
        if self.cancelled()?{self.state.stop("cancelled","before_dispatch");return self.state.save(&self.dir);}
        let binding=self.state.binding.clone().ok_or("missing_binding")?;
        // Fixed fixture receipt shape is known before execution; reserve its context space.
        let result_bytes=Receipt{binding:binding.clone(),id:format!("r-{}",binding.invocation)}.message().len() as u64;
        if model::context_bytes(&self.state.context).saturating_add(result_bytes)>self.state.limits.context {
            self.state.stop("budget_exhausted","tool_result_context");return self.state.save(&self.dir);
        }
        match FixtureAuthorizer.check(&self.state.facts){Decision::Denied=>{self.state.stop("denied","host_policy");return self.state.save(&self.dir);},Decision::ConfirmationRequired=>{self.state.stop("waiting","confirmation_required");return self.state.save(&self.dir);},Decision::Permit=>{}}
        if self.state.facts.confirmed{self.state.counters.confirmations+=1;self.state.facts.confirmed=false;}
        self.state.unresolved=true;self.state.stop("outcome_unknown","dispatch_started");
        h.fault("dispatch")?;self.state.save(&self.dir)?;
        h.checkpoint("dispatch")?;
        if self.cancelled()?{self.state.unresolved=false;self.state.stop("cancelled","before_effect");return self.state.save(&self.dir);}
        // Recheck current trusted hard facts at the last boundary; confirmation was consumed above.
        if !self.state.facts.hard_ok||self.state.facts.revoked||!self.state.facts.scope_ok||!self.state.facts.classification_ok{self.state.unresolved=false;self.state.stop("denied","host_policy");return self.state.save(&self.dir);}
        if self.state.behavior=="fail"{self.state.unresolved=false;self.state.stop("failed","tool_definite_failure");return self.state.save(&self.dir);}
        if h.fault("effect").is_err(){self.state.stop("outcome_unknown","effect_io_failure");return self.state.save(&self.dir);}
        let receipt=match (FixtureTool{dir:self.dir.clone()}).execute_once(&binding){Ok(r)=>r,Err(_)=>{self.state.stop("outcome_unknown","effect_io_failure");return self.state.save(&self.dir);}};
        h.checkpoint("effect")?;self.cancelled()?;
        if self.state.behavior=="lose-response"&&!self.state.cancelled{self.state.stop("outcome_unknown","tool_response_lost");return self.state.save(&self.dir);}
        h.fault("projection")?;self.apply_receipt(receipt)?;self.state.save(&self.dir)?;h.checkpoint("projection")?;Ok(())
    }
    pub fn run(&mut self,h:&Hooks)->Result<()> {
        if self.state.evidence_hold || self.state.unresolved{return Ok(());}
        if self.cancelled()?{self.state.stop("cancelled","cancel_requested");return self.state.save(&self.dir);}
        if self.state.status=="waiting"{self.dispatch(h)?;}
        let mut provider=ScriptedProvider::parse(&self.state.script)?;
        while self.state.status=="ready" {
            if self.cancelled()?{self.state.stop("cancelled","cancel_requested");break;}
            let size=model::context_bytes(&self.state.context);
            if self.state.counters.steps>=self.state.limits.steps||self.state.counters.calls>=self.state.limits.calls||size>self.state.limits.context||self.state.counters.total.saturating_add(size)>self.state.limits.total||self.state.counters.output>=self.state.limits.output {self.state.stop("budget_exhausted","admission");break;}
            self.state.counters.steps+=1;self.state.counters.calls+=1;self.state.counters.total+=size;
            self.state.stop("failed","provider_interrupted");self.state.save(&self.dir)?;
            let request=ModelRequest{task:self.state.task.clone(),attempt:self.state.attempt.clone(),turn:self.state.counters.steps,messages:self.state.context.clone(),tools:vec!["fixture.record".into()]};
            let event=match provider.respond(&request,self.state.position){Ok(e)=>e,Err(_)=>{self.state.stop("failed","provider_error");break;}};
            self.state.position+=1;let bytes=model::event_bytes(&event);self.state.counters.output+=bytes;self.state.counters.total+=bytes;
            if self.state.counters.output>self.state.limits.output||self.state.counters.total>self.state.limits.total {self.state.stop("budget_exhausted","response");break;}
            self.state.stop("ready","");
            match event {
                ModelEvent::Fail(reason)=>self.state.stop("failed",&reason),
                ModelEvent::Answer(text)=>{
                    if size.saturating_add(text.len() as u64)>self.state.limits.context{self.state.stop("budget_exhausted","context");}else{self.state.answer=text.clone();self.state.context.push(Message{role:Role::Assistant,text});self.state.stop("completed","");}
                },
                ModelEvent::Tool{call_ref,name,value}=>{
                    if name!="fixture.record"{self.state.stop("failed","unknown_tool");break;}
                    let original=self.state.correlations.get(&call_ref).cloned();
                    if let Some(b)=&original{if b.value!=value||b.scope!=self.state.scope{self.state.stop("failed","binding_conflict");break;}}
                    let call_text=format!("tool={name};call={call_ref};value={value}");
                    if size.saturating_add(call_text.len() as u64)>self.state.limits.context{self.state.stop("budget_exhausted","context");break;}
                    self.state.context.push(Message{role:Role::Assistant,text:call_text});self.state.result_pending=true;
                    if let Some(binding)=original {
                        self.state.binding=Some(binding.clone());
                        // Existing correlation is a receipt lookup, never new authorization or execution.
                        self.state.unresolved=true;self.state.stop("outcome_unknown","receipt_lookup");self.state.save(&self.dir)?;
                        match (FixtureTool{dir:self.dir.clone()}).lookup(&binding){
                            Ok(Some(r))=>self.apply_receipt(r)?,
                            Ok(None)=>self.state.stop("outcome_unknown","receipt_not_found"),
                            Err(_)=>self.state.stop("outcome_unknown","receipt_unavailable"),
                        }
                    } else {
                        let binding=Binding{invocation:format!("i-{}",self.state.counters.steps),task:self.state.task.clone(),attempt:self.state.attempt.clone(),turn:self.state.counters.steps,scope:self.state.scope.clone(),value};
                        self.state.correlations.insert(call_ref,binding.clone());self.state.binding=Some(binding);
                        self.dispatch(h)?;
                    }
                },
            }
            self.state.save(&self.dir)?;
        }
        self.state.save(&self.dir)
    }
    pub fn observe(&self)->String {
        let effect=EffectStore::load(&self.dir);let (count,value)=match effect{Ok(s)=>(s.receipts.len().to_string(),hex(&s.value)),Err(_)=>("unknown".into(),String::new())};
        format!("status={}\ntask={}\nattempt={}\nturn={}\ninvocation={}\nreceipt={}\neffects={}\nvalue_hex={}\nanswer_hex={}\nmodel_calls={}\nsteps={}\ncontext_bytes={}\noutput_bytes={}\ntotal_units={}\nprovider_position={}\ncancelled={}\nconfirmations={}\nreason={}\nevidence_hold={}\ndispatch_unresolved={}\n",self.state.status,self.state.task,self.state.attempt,self.state.counters.steps,self.state.binding.as_ref().map(|b|b.invocation.as_str()).unwrap_or(""),self.state.receipt,count,value,hex(&self.state.answer),self.state.counters.calls,self.state.counters.steps,model::context_bytes(&self.state.context),self.state.counters.output,self.state.counters.total,self.state.position,self.state.cancelled,self.state.counters.confirmations,self.state.reason,self.state.evidence_hold,self.state.unresolved)
    }
}
