use crate::{hex, unhex, identifier, Result, model::{self, Message, Role, ModelRequest, ModelEvent, Provider, ScriptedProvider}, policy::{HostFacts,Mode,Decision,Authorizer,FixtureAuthorizer}, store::{self,Binding,Receipt,EffectStore,FixtureTool,ToolPort}};
use crate::{wire_provider::{WireConfig,WireCounters,WireProvider,encode_history,decode_history},model::{NativeMessage,ProviderControl}};
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
    pub wire:Option<WireConfig>,pub wire_counters:WireCounters,pub native:Vec<NativeMessage>,pub pending_call_ref:String,
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
        Ok(Self{attempt:format!("a-{}-{nonce}",std::process::id()),task,status:"ready".into(),reason:String::new(),script,scope,facts,limits,counters:Counters::default(),context:vec![Message{role:Role::User,text:input}],position:0,binding:None,unresolved:false,receipt:String::new(),answer:String::new(),cancelled:false,correlations:BTreeMap::new(),behavior,resume_status:String::new(),resume_reason:String::new(),result_pending:false,receipt_binding:None,evidence_hold:false,wire:None,wire_counters:WireCounters::default(),native:Vec::new(),pending_call_ref:String::new()})
    }
    /// Native host owns persistence and authority; this does not create fixture effects.
    pub fn runtime(input:String,scope:String,limits:Limits)->Result<Self>{
        limits.validate()?;
        if input.len()>65536 || input.len() as u64>limits.context || scope.is_empty() || scope.len()>1024{return Err("invalid_start".into());}
        let nonce=SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_|"clock")?.as_nanos();
        let task=format!("t-{}-{nonce}",std::process::id());
        Ok(Self{attempt:format!("a-{}-{nonce}",std::process::id()),task,status:"ready".into(),reason:String::new(),script:String::new(),scope,facts:HostFacts{mode:Mode::ReadOnly,high:true,hard_ok:false,revoked:true,scope_ok:false,classification_ok:false,confirmed:false,tainted:true,new_destination:true},limits,counters:Counters::default(),context:vec![Message{role:Role::User,text:input}],position:0,binding:None,unresolved:false,receipt:String::new(),answer:String::new(),cancelled:false,correlations:BTreeMap::new(),behavior:"normal".into(),resume_status:String::new(),resume_reason:String::new(),result_pending:false,receipt_binding:None,evidence_hold:false,wire:None,wire_counters:WireCounters::default(),native:Vec::new(),pending_call_ref:String::new()})
    }
    pub fn with_wire(mut self,config:WireConfig)->Result<Self>{config.validate()?;self.native=self.context.iter().map(|m|NativeMessage::User(m.text.clone())).collect();self.script.clear();self.wire=Some(config);Ok(self)}
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
        put!("provider",if self.wire.is_some(){"chat-sse"}else{"script"});
        put!("wire_config_hex",hex(&self.wire.as_ref().map(WireConfig::encode).unwrap_or_default()));put!("native_history_hex",hex(&encode_history(&self.native)));put!("pending_call_ref",self.pending_call_ref);
        put!("wire_sent_bytes",self.wire_counters.sent);put!("wire_received_bytes",self.wire_counters.received);put!("wire_total_bytes",self.wire_counters.total());put!("provider_inflight",self.wire_counters.inflight);
        put!("usage_prompt",self.wire_counters.usage.prompt.map(|n|n.to_string()).unwrap_or_else(||"unknown".into()));put!("usage_completion",self.wire_counters.usage.completion.map(|n|n.to_string()).unwrap_or_else(||"unknown".into()));
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
        let provider=take(&mut m,"provider")?;let wire_raw=unhex(&take(&mut m,"wire_config_hex")?)?;
        let wire=match provider.as_str(){"script" if wire_raw.is_empty()=>None,"chat-sse" if script.is_empty()=>Some(WireConfig::decode(&wire_raw)?),_=>return Err("invalid_provider".into())};
        let native=decode_history(&unhex(&take(&mut m,"native_history_hex")?)?)?;let pending_call_ref=take(&mut m,"pending_call_ref")?;
        let sent=number(&mut m,"wire_sent_bytes")?;let received=number(&mut m,"wire_received_bytes")?;let total=number(&mut m,"wire_total_bytes")?;let inflight=flag(&mut m,"provider_inflight")?;
        let usage_value=|v:String|->Result<Option<u64>>{if v=="unknown"{Ok(None)}else{Ok(Some(v.parse().map_err(|_|"invalid_usage")?))}};
        let usage=crate::wire_sse::Usage{prompt:usage_value(take(&mut m,"usage_prompt")?)?,completion:usage_value(take(&mut m,"usage_completion")?)?};
        let wire_counters=WireCounters{sent,received,inflight,usage};
        if sent.checked_add(received)!=Some(total)||total>wire.as_ref().map(|c|c.max_total).unwrap_or(0)||(!pending_call_ref.is_empty()&&!identifier(&pending_call_ref))||wire.is_none()&&(!native.is_empty()||inflight){return Err("invalid_wire_state".into());}
        if !m.is_empty() || !identifier(&task)||!identifier(&attempt)||!matches!(status.as_str(),"ready"|"waiting"|"completed"|"denied"|"failed"|"cancelled"|"outcome_unknown"|"budget_exhausted") || !matches!(behavior.as_str(),"normal"|"fail"|"lose-response") || scope.is_empty()||scope.len()>1024 || position>128 || counters.steps>1_000_000||counters.calls>1_000_000||counters.output>2_000_000||counters.total>4_000_000 || correlations.len()>128 || (!receipt.is_empty()&&!identifier(&receipt)) {return Err("invalid_task_state".into());}
        if (unresolved||status=="waiting")&&binding.is_none(){return Err("missing_binding".into());}
        if let Some(b)=&binding{if b.task!=task||b.attempt!=attempt||b.scope!=scope||b.turn>counters.steps{return Err("task_binding_mismatch".into());}}
        if !matches!(resume_status.as_str(),""|"ready"|"waiting"|"outcome_unknown"|"completed"|"cancelled"|"denied"|"failed"|"budget_exhausted")||evidence_hold!=!resume_status.is_empty(){return Err("invalid_resume_barrier".into());}
        if receipt.is_empty()!=receipt_binding.is_none() || (evidence_hold&&receipt_binding.is_none()){return Err("missing_receipt_binding".into());}
        if let Some(b)=&receipt_binding{if receipt!=format!("r-{}",b.invocation)||!correlations.values().any(|original|original==b){return Err("receipt_binding_identity".into());}}
        for b in correlations.values(){if b.task!=task||b.attempt!=attempt||b.scope!=scope||b.turn>counters.steps{return Err("correlation_binding_mismatch".into());}}
        if let Some(b)=&binding{if !correlations.values().any(|original|original==b){return Err("missing_correlation_binding".into());}}
        if wire.is_none(){ScriptedProvider::parse(&script)?;}
        Ok(Self{task,attempt,status,reason,script,scope,facts,limits,counters,context,position,binding,unresolved,receipt,answer,cancelled,correlations,behavior,resume_status,resume_reason,result_pending,receipt_binding,evidence_hold,wire,wire_counters,native,pending_call_ref})
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
        if state.wire_counters.inflight{state.stop("failed","wire_interrupted");}
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
            let text=r.message();self.state.receipt=r.id.clone();self.state.result_pending=false;
            if self.state.wire.is_some(){if self.state.pending_call_ref.is_empty(){return Err("wire_missing_pair".into());}self.state.native.push(NativeMessage::ToolResult{call_ref:self.state.pending_call_ref.clone(),value:r.binding.value.clone(),receipt:r.id.clone()});}
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
        if let Some(config)=self.state.wire.clone(){let mut provider=WireProvider::new(config,&self.dir);self.run_with_provider(&mut provider,h)}else{let mut provider=ScriptedProvider::parse(&self.state.script)?;self.run_with_provider(&mut provider,h)}
    }
    pub fn run_with_provider(&mut self,provider:&mut dyn Provider,h:&Hooks)->Result<()> {
        self.drive(provider,None,h)
    }
    /// Product host ports share this exact model/admission/control loop with fixtures.
    pub fn run_with_ports(&mut self,provider:&mut dyn Provider,ports:&mut crate::host_session::HostPorts,h:&Hooks)->Result<()> {
        self.drive(provider,Some(ports),h)
    }
    pub fn run_with_runtime_ports(&mut self,provider:&mut dyn Provider,ports:&mut dyn crate::agent_ports::AgentPorts,h:&Hooks)->Result<()> {
        self.drive(provider,Some(ports),h)
    }
    fn save_drive(&self,ports:Option<&dyn crate::agent_ports::AgentPorts>)->Result<()> {
        if let Some(ports)=ports{ports.persist(self)}else{self.state.save(&self.dir)}
    }
    fn drive(&mut self,provider:&mut dyn Provider,mut ports:Option<&mut dyn crate::agent_ports::AgentPorts>,h:&Hooks)->Result<()> {
        if self.state.wire_counters.inflight{self.state.stop("failed","wire_interrupted");return self.save_drive(ports.as_deref());}
        if self.state.evidence_hold || self.state.unresolved{return Ok(());}
        if self.cancelled()?{self.state.stop("cancelled","cancel_requested");return self.save_drive(ports.as_deref());}
        if self.state.status=="waiting"{if ports.is_some(){self.state.stop("failed","host_protocol");return self.save_drive(ports.as_deref());}self.dispatch(h)?;}
        while self.state.status=="ready" {
            if let Some(host)=ports.as_deref_mut(){if let Err(reason)=host.check_control(){host.failure(&mut self.state,&reason);break;}}
            if self.cancelled()?{self.state.stop("cancelled","cancel_requested");break;}
            let size=model::context_bytes(&self.state.context);
            if self.state.counters.steps>=self.state.limits.steps||self.state.counters.calls>=self.state.limits.calls||size>self.state.limits.context||self.state.counters.total.saturating_add(size)>self.state.limits.total||self.state.counters.output>=self.state.limits.output {self.state.stop("budget_exhausted","admission");break;}
            self.state.counters.steps+=1;self.state.counters.calls+=1;self.state.counters.total+=size;
            self.state.wire_counters.inflight=self.state.wire.is_some();
            if self.state.wire.is_some(){self.state.wire_counters.usage=crate::wire_sse::Usage::default();}
            self.state.stop("failed","provider_interrupted");self.save_drive(ports.as_deref())?;
            let tools=if let Some(host)=ports.as_deref_mut(){match host.advertised_tools(&self.state){Ok(tools)=>tools,Err(reason)=>{host.failure(&mut self.state,&reason);break;}}}else{vec!["fixture.record".into()]};
            let request=ModelRequest{task:self.state.task.clone(),attempt:self.state.attempt.clone(),turn:self.state.counters.steps,messages:self.state.context.clone(),tools};
            let position=self.state.position;let history=self.state.native.clone();
            let response=provider.respond_controlled(&request,position,&history,&mut AgentControl{agent:self,h,host:ports.is_some()});
            self.state.wire_counters.inflight=false;
            let event=match response{Ok(e)=>e,Err(reason)=>{if let Some(host)=ports.as_deref_mut(){host.failure(&mut self.state,&reason);}else if self.state.wire.is_some(){if reason=="wire_cancelled"{self.state.stop("cancelled",&reason);}else if reason.ends_with("_limit"){self.state.stop("budget_exhausted",&reason);}else{self.state.stop("failed",&reason);}}else{self.state.stop("failed","provider_error");}break;}};
            let (prompt,completion)=provider.reported_usage();self.state.wire_counters.usage=crate::wire_sse::Usage{prompt,completion};
            if self.cancelled()?{self.state.stop("cancelled","cancel_requested");break;}
            if let Some(host)=ports.as_deref_mut(){if let Err(reason)=host.check_control(){host.failure(&mut self.state,&reason);break;}}
            self.state.position+=1;let bytes=model::event_bytes(&event);self.state.counters.output+=bytes;self.state.counters.total+=bytes;
            if self.state.counters.output>self.state.limits.output||self.state.counters.total>self.state.limits.total {self.state.stop("budget_exhausted","response");break;}
            self.state.stop("ready","");
            match event {
                ModelEvent::HostTool{call_ref,name,arguments}=>{
                    if let Some(host)=ports.as_deref_mut(){if let Err(reason)=host.dispatch(self,call_ref,name,arguments){host.failure(&mut self.state,&reason);}}
                    else{self.state.stop("failed","unknown_tool");}
                },
                ModelEvent::Fail(reason)=>self.state.stop("failed",&reason),
                ModelEvent::Answer(text)=>{
                    if let Some(host)=ports.as_deref_mut(){if let Err(reason)=host.admit_answer(&self.state,&text){host.failure(&mut self.state,&reason);break;}}
                    if size.saturating_add(text.len() as u64)>self.state.limits.context{self.state.stop("budget_exhausted","context");}else{if self.state.wire.is_some(){self.state.native.push(NativeMessage::Assistant(text.clone()));}self.state.answer=text.clone();self.state.context.push(Message{role:Role::Assistant,text});self.state.stop("completed","");}
                },
                ModelEvent::Tool{call_ref,name,value}=>{
                    if ports.is_some(){self.state.stop("failed","host_protocol");break;}
                    if name!="fixture.record"{self.state.stop("failed","unknown_tool");break;}
                    let original=self.state.correlations.get(&call_ref).cloned();
                    if let Some(b)=&original{if b.value!=value||b.scope!=self.state.scope{self.state.stop("failed","binding_conflict");break;}}
                    let call_text=format!("tool={name};call={call_ref};value={value}");
                    if size.saturating_add(call_text.len() as u64)>self.state.limits.context{self.state.stop("budget_exhausted","context");break;}
                    if self.state.wire.is_some(){self.state.native.push(NativeMessage::AssistantCall{call_ref:call_ref.clone(),name:name.clone(),value:value.clone()});self.state.pending_call_ref=call_ref.clone();}
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
            self.save_drive(ports.as_deref())?;
        }
        if ports.is_some() && self.state.status=="budget_exhausted"{self.state.reason="host_budget".into();}
        self.save_drive(ports.as_deref())
    }
    pub fn observe(&self)->String {
        let effect=EffectStore::load(&self.dir);let (count,value)=match effect{Ok(s)=>(s.receipts.len().to_string(),hex(&s.value)),Err(_)=>("unknown".into(),String::new())};
        let base=format!("status={}\ntask={}\nattempt={}\nturn={}\ninvocation={}\nreceipt={}\neffects={}\nvalue_hex={}\nanswer_hex={}\nmodel_calls={}\nsteps={}\ncontext_bytes={}\noutput_bytes={}\ntotal_units={}\nprovider_position={}\ncancelled={}\nconfirmations={}\nreason={}\nevidence_hold={}\ndispatch_unresolved={}\n",self.state.status,self.state.task,self.state.attempt,self.state.counters.steps,self.state.binding.as_ref().map(|b|b.invocation.as_str()).unwrap_or(""),self.state.receipt,count,value,hex(&self.state.answer),self.state.counters.calls,self.state.counters.steps,model::context_bytes(&self.state.context),self.state.counters.output,self.state.counters.total,self.state.position,self.state.cancelled,self.state.counters.confirmations,self.state.reason,self.state.evidence_hold,self.state.unresolved);
        format!("{base}wire_sent_bytes={}\nwire_received_bytes={}\nwire_total_bytes={}\nprovider_inflight={}\nusage_prompt={}\nusage_completion={}\n",self.state.wire_counters.sent,self.state.wire_counters.received,self.state.wire_counters.total(),self.state.wire_counters.inflight,self.state.wire_counters.usage.prompt.map(|n|n.to_string()).unwrap_or_else(||"unknown".into()),self.state.wire_counters.usage.completion.map(|n|n.to_string()).unwrap_or_else(||"unknown".into()))
    }
}

struct AgentControl<'a>{agent:&'a mut Agent,h:&'a Hooks,host:bool}
impl ProviderControl for AgentControl<'_>{
    fn poll(&mut self)->Result<()>{if self.agent.cancelled()?{Err("wire_cancelled".into())}else{Ok(())}}
    fn remaining(&self)->u64{self.agent.state.wire.as_ref().map(|c|c.max_total.saturating_sub(self.agent.state.wire_counters.total())).unwrap_or(u64::MAX)}
    fn charge(&mut self,sent:bool,bytes:usize)->Result<()>{if self.host{return Err("host_control_unsupported".into());}if bytes as u64>self.remaining(){return Err("wire_total_limit".into());}let counters=&mut self.agent.state.wire_counters;let target=if sent{&mut counters.sent}else{&mut counters.received};*target=target.checked_add(bytes as u64).ok_or("wire_total_limit")?;self.agent.state.save(&self.agent.dir).map_err(|_|"wire_journal".into())}
    fn checkpoint(&mut self,name:&str)->Result<()>{if self.host{return Err("host_control_unsupported".into());}self.agent.state.save(&self.agent.dir).map_err(|_|"wire_journal".to_string())?;self.h.checkpoint(name)}
}
