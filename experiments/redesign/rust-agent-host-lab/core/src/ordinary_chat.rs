//! Ordinary text intent on the existing Service worker and core Agent drive.
//! Only explicitly synthetic, no-network transports are supported in this slice.
use crate::{field, service_host::{ServiceHostMode, ServiceHostPorts}, service_root::ServiceRoot, service_runtime::RunControl, service_types::*, supplier_business::BusinessRead, Json, Result};
use muyon_core_agent_lab::{agent::{Agent, State, Limits, Hooks}, agent_ports::AgentPorts, model::{Provider, ProviderControl, ModelRequest, ModelEvent, NativeMessage}, store};
use muyon_plugin_contract_lab::{object, string, parse};
use std::{path::Path, sync::Arc, rc::Rc, cell::RefCell};
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChatAuthority {
    pub workspace:String, pub conversation:String, pub owner:String, pub mode:String,
    pub policy_revision:String, pub grant_revision:String, pub rule_revision:String,
    pub restriction_revision:String, pub sensitivity:String,
    pub active:bool, pub model_allowed:bool, pub outbound_allowed:bool,
    pub inherited_allowed:bool, pub synthetic:bool,
}
pub struct ChatResponse { pub answer:String, pub input_tokens:u64, pub output_tokens:u64, pub synthetic:bool }
impl ChatAuthority {
    pub fn validate(&self, conversation:&str) -> Result<()> {
        for v in [&self.workspace,&self.conversation,&self.owner,&self.policy_revision,&self.grant_revision,&self.restriction_revision] { if !id(v,128) { return Err("chat_authority_invalid".into()) } }
        if self.conversation!=conversation || !self.active || !self.model_allowed || !self.outbound_allowed || !self.inherited_allowed
            || !matches!(self.sensitivity.as_str(),"personal"|"commercial") || self.rule_revision!="USER-TEXT-v1"
            || !matches!(self.mode.as_str(),"auto"|"full-allow"|"read-only"|"ask-every-time") { return Err("chat_authority_denied".into()) }
        // No production price, currency or transport has been installed/authorized.
        if !self.synthetic { return Err("chat_production_configuration_unavailable".into()) }
        Ok(())
    }
    pub fn json(&self)->Json { object([("workspace",string(&self.workspace)),("conversation",string(&self.conversation)),("owner",string(&self.owner)),("mode",string(&self.mode)),("policy_revision",string(&self.policy_revision)),("grant_revision",string(&self.grant_revision)),("input_rule",string(&self.rule_revision)),("restriction_revision",string(&self.restriction_revision)),("sensitivity",string(&self.sensitivity)),("output_rule",string("MODEL-TEXT-v1")),("synthetic",Json::Bool(self.synthetic))]) }
}
fn id(v:&str,max:usize)->bool { !v.is_empty() && v.len()<=max && v.trim()==v && !v.chars().any(char::is_control) }
/// Finite, versioned whole-string scan. Exact UTF-8 identity normalization;
/// combining marks/control formats are unsupported, not silently normalized.
/// Pattern coverage is limited: arbitrary unlabeled unknown secrets may be missed.
pub fn check_text(text:&str)->Result<()> {
    if text.trim().is_empty() || text.len()>4096 || text.chars().any(|c| (c.is_control() && !matches!(c,'\n'|'\t')) || matches!(c as u32,0x300..=0x36f|0x200b..=0x200f|0x202a..=0x202e|0x2060..=0x206f|0xfffe..=0xffff)) { return Err("chat_text_unreviewed".into()) }
    let lower=text.to_lowercase();
    if ["sk-","bearer ","api_key","api-key","apikey","password","private key","secret","token=","token:","密钥","密码"].iter().any(|s|lower.contains(s)) { return Err("chat_credential_signal".into()) }
    Ok(())
}
pub(crate) fn payload(conversation:String,text:String)->Result<Json> { if !id(&conversation,128) || text.trim().is_empty() || text.len()>4096 {return Err("INVALID_PAYLOAD".into())} Ok(object([("intent",string("ordinary-chat-v1")),("conversation",string(conversation)),("text",string(text))])) }
pub(crate) fn is_chat(b:&BusinessRead)->bool { field(&b.payload,"intent").ok()==Some(&string("ordinary-chat-v1")) }
fn current(host:&ServiceHostPorts,payload:&Json)->Result<ChatAuthority> { if host.mode!=ServiceHostMode::ConfiguredChat {return Err("chat_mode_unavailable".into())} let a=host.owner.chat_authority(field(payload,"conversation")?.string()?,field(payload,"text")?.string()?)?;a.validate(field(payload,"conversation")?.string()?)?;Ok(a) }
fn validate_binding(host:&ServiceHostPorts,payload:&Json,expected:&Json)->Result<()> {
    let a=current(host,payload)?;
    if field(expected,"authority")?!=&a.json() {return Err("chat_authority_changed".into())}check_text(field(payload,"text")?.string()?)
}
pub(crate) fn disclose(b:&BusinessRead)->Result<()> { if b.events.iter().any(|e|field(e,"kind").ok()==Some(&string("answer_delta"))) {validate_binding(b.host.as_ref().ok_or("chat_owner_unavailable")?,&b.payload,b.source_binding.as_ref().ok_or("chat_binding_unavailable")?)?;receipt(b.dir.as_ref().ok_or("chat_run_unavailable")?,b)?;}Ok(()) }
fn write_send(dir:&Path,context:&Json,body:&Json,state:&str,admission:&str,answer:&str)->Result<()> {store::atomic(dir,"ordinary-send-v1.db",&object([("version",string("ordinary-send-v1")),("context",context.clone()),("payload",body.clone()),("state",string(state)),("admission",string(admission)),("answer",string(answer))]).encode())}
struct Shared { record:Option<String>, admitted:bool }
struct ChatProvider<'a> { host:&'a ServiceHostPorts, authority:ChatAuthority, intent:&'a Json, context:Json, dir:&'a Path, request:String, shared:Rc<RefCell<Shared>> }
impl Provider for ChatProvider<'_> {
    fn respond(&mut self,_:&ModelRequest,_:usize)->Result<ModelEvent>{Err("controlled_chat_required".into())}
    fn respond_controlled(&mut self,request:&ModelRequest,_:usize,_:&[NativeMessage],control:&mut dyn ProviderControl)->Result<ModelEvent> {
        if request.turn!=1 || !request.tools.is_empty() || request.messages.len()!=1 || request.messages[0].text!=field(self.intent,"text")?.string()? || request.task!=field(&self.context,"task")?.string()? || request.attempt!=field(&self.context,"attempt")?.string()? {return Err("chat_request_binding".into())}
        control.poll()?;validate_binding(self.host,self.intent,&self.context)?;
        let bridge=self.host.owner.provider()?;let profile=bridge.readiness(&self.host.budget)?;
        // max_tokens on the wire is OUTPUT; reserve max_tokens remains TOTAL.
        // This conservative synthetic proof counts UTF-8 bytes plus fixed framing.
        let input_bound=(request.messages[0].text.len() as u64).checked_add(512).ok_or("chat_budget")?;
        let output=self.host.budget.max_tokens.checked_sub(input_bound).ok_or("chat_budget")?.min(1024);
        if output==0 || self.host.budget.requires_tools || self.host.budget.requires_streaming {return Err("chat_budget".into())}
        let body=object([("model",string(&profile.model)),("messages",Json::Array(vec![object([("role",string("user")),("content",string(&request.messages[0].text))])])),("n",Json::Number("1".into())),("stream",Json::Bool(false)),("max_tokens",Json::Number(output.to_string()))]);
        let bytes=body.encode().into_bytes();write_send(self.dir,&self.context,&body,"prepared","","")?;
        let prepared=bridge.prepare_chat(&self.request,&bytes,self.host.budget.clone())?;
        validate_binding(self.host,self.intent,&self.context)?;control.poll()?;
        let admission=bridge.final_admit(prepared)?;
        self.shared.borrow_mut().admitted=true;
        write_send(self.dir,&self.context,&body,"admitted",admission.record_id(),"")?;
        validate_binding(self.host,self.intent,&self.context)?;control.poll()?;
        // The same owner atomically validates and one-shot records the handoff.
        // No retries, fallback transport or refunds after this boundary.
        let reply=bridge.exchange_chat(&admission,&self.context)?;
        if !reply.synthetic || !self.authority.synthetic || reply.input_tokens==0 || reply.output_tokens==0 || reply.output_tokens>output || reply.input_tokens.checked_add(reply.output_tokens).filter(|n|*n<=self.host.budget.max_tokens).is_none() {return Err("chat_usage_unavailable".into())}
        check_text(&reply.answer)?;validate_binding(self.host,self.intent,&self.context)?;control.poll()?;
        write_send(self.dir,&self.context,&body,"completed",admission.record_id(),&reply.answer)?;
        self.shared.borrow_mut().record=Some(admission.record_id().into());
        Ok(ModelEvent::Answer(reply.answer))
    }
}
struct ChatPorts {control:Arc<RunControl>,shared:Rc<RefCell<Shared>>}
impl AgentPorts for ChatPorts {
    fn advertised_tools(&self,_:&State)->Result<Vec<String>>{Ok(vec![])}
    fn persist(&self,agent:&Agent)->Result<()>{store::atomic(&agent.dir,"ordinary-agent-v1.db",&agent.state.encode())}
    fn check_control(&mut self)->Result<()>{self.control.poll()}
    fn dispatch(&mut self,_:&mut Agent,_:String,_:String,_:Json)->Result<()>{Err("chat_tools_unsupported".into())}
    fn admit_answer(&self,_:&State,text:&str)->Result<()>{check_text(text)}
    fn failure(&mut self,state:&mut State,reason:&str){state.status=if self.shared.borrow().admitted {"outcome_unknown"}else if reason=="native_cancelled" {"cancelled"}else{"failed"}.into();state.reason=reason.into();}
}
pub(crate) fn execute(root:&mut ServiceRoot,run:&mut AgentDurableRun,dir:&Path,b:&mut BusinessRead,control:Arc<RunControl>)->AgentRunSummary {
    b.dir=Some(dir.into());let shared=Rc::new(RefCell::new(Shared{record:None,admitted:false}));
    let mut summary=AgentRunSummary{request_id:run.intent.request_id.clone(),variant:run.intent.variant.clone(),source_build_identity:run.intent.source_build_identity.clone(),identity:run.identity.clone(),terminal:AgentTerminal::Failed,reason:AgentReason::InternalFailure,receipt:AgentReceiptSummary{opaque_id:None,outcome:AgentReceiptOutcome::NotStarted}};
    let result=(||{
        let host=b.host.clone().ok_or("chat_owner_unconfigured")?;let authority=current(&host,&b.payload)?;check_text(field(&b.payload,"text")?.string()?)?;
        let state=State::runtime(field(&b.payload,"text")?.string()?.into(),authority.workspace.clone(),Limits{steps:1,calls:1,context:16384,output:4096,total:32768})?;
        root.attach_task(&run.identity.run_id,AgentTaskIdentity{task_id:state.task.clone(),attempt_id:state.attempt.clone()})?;
        run.identity.actual_task=Some(AgentTaskIdentity{task_id:state.task.clone(),attempt_id:state.attempt.clone()});summary.identity=run.identity.clone();
        let context=object([("authority",authority.json()),("workspace",string(&authority.workspace)),("conversation",field(&b.payload,"conversation")?.clone()),("input_ref",string(format!("{}:{}",run.identity.run_id,run.intent.request_id))),("task",string(&state.task)),("attempt",string(&state.attempt)),("input_version",string("utf8-exact-v1"))]);
        b.source_binding=Some(context.clone());b.save(dir)?;
        let mut agent=Agent{dir:dir.into(),state};let mut ports=ChatPorts{control:control.clone(),shared:shared.clone()};
        let mut provider=ChatProvider{host:&host,authority,intent:&b.payload,context,dir,request:run.intent.request_id.clone(),shared:shared.clone()};
        agent.run_with_runtime_ports(&mut provider,&mut ports,&Hooks::default())?;
        if agent.state.status!="completed" {return Err(if agent.state.reason.is_empty(){"chat_incomplete".into()}else{agent.state.reason})}
        let record=shared.borrow().record.clone().ok_or("chat_receipt_unavailable")?;
        b.push("answer_delta",object([("text",string(agent.state.answer))]));
        b.push("provider_receipt",object([("owner",string("ServiceProviderOwner")),("identity",string(&record)),("task",string(&agent.state.task)),("attempt",string(&agent.state.attempt)),("synthetic",Json::Bool(true))]));
        summary.receipt=AgentReceiptSummary{opaque_id:Some(record),outcome:AgentReceiptOutcome::RecordedSuccess};summary.terminal=AgentTerminal::Completed;summary.reason=AgentReason::None;Ok::<(),String>(())
    })();
    let reason=if let Err(reason)=result {b.events.clear();if shared.borrow().admitted{summary.terminal=AgentTerminal::OutcomeUnknown;summary.receipt.outcome=AgentReceiptOutcome::Unknown;}else if reason=="native_cancelled"{summary.terminal=AgentTerminal::Cancelled;summary.reason=AgentReason::Cancelled;}reason}else{"none".into()};
    let state=match summary.terminal{AgentTerminal::Completed=>"completed",AgentTerminal::Cancelled=>"cancelled",AgentTerminal::OutcomeUnknown=>"outcome_unknown",_=>"failed"};b.push("terminal",object([("state",string(state)),("reason",string(reason))]));
    // Never put rejected credential-bearing input into a durable business ledger.
    if b.source_binding.is_some() && b.save(dir).is_err(){root.poison();b.events.clear();b.push("terminal",object([("state",string("outcome_unknown")),("reason",string("chat_storage_failure"))]));summary.terminal=AgentTerminal::OutcomeUnknown;summary.receipt.outcome=AgentReceiptOutcome::Unknown;}
    summary
}
pub(crate) fn receipt(dir:&Path,b:&BusinessRead)->Result<String> {
    let path=dir.join("ordinary-send-v1.db");let meta=std::fs::symlink_metadata(&path).map_err(|_|"chat_receipt_missing")?;
    if !meta.is_file() || meta.file_type().is_symlink() || meta.len()>32768 {return Err("chat_receipt_bound".into())}
    let j=parse(&std::fs::read(path).map_err(|_|"chat_receipt_missing")?)?;
    if field(&j,"version")?!=&string("ordinary-send-v1") || field(&j,"state")?!=&string("completed") || b.source_binding.as_ref()!=Some(field(&j,"context")?) {return Err("chat_receipt_binding".into())}
    let answer=field(&j,"answer")?.string()?;check_text(answer)?;
    let e=b.events.iter().find(|e|field(e,"kind").ok()==Some(&string("answer_delta"))).ok_or("chat_answer_missing")?;
    if field(field(e,"payload")?,"text")?!=&string(answer){return Err("chat_answer_binding".into())}
    let r=field(&j,"admission")?.string()?;if !id(r,512){return Err("chat_receipt_identity".into())}Ok(r.into())
}
pub(crate) fn restore(dir:&Path,run:&AgentDurableRun,b:&BusinessRead)->Result<AgentRunSnapshot> {
    // No Agent::open, send or resume. Interrupted chat is conservatively unknown.
    let completed=b.events.last().and_then(|e|field(e,"payload").ok()).and_then(|p|field(p,"state").ok())==Some(&string("completed"));
    if !completed{return Ok(crate::service_evidence::unknown(run,AgentReceiptSummary{opaque_id:None,outcome:AgentReceiptOutcome::Unknown}))}
    let record=receipt(dir,b)?;let context=b.source_binding.as_ref().ok_or("chat_binding_missing")?;let task=run.identity.actual_task.as_ref().ok_or("chat_task_missing")?;
    if field(context,"task")?!=&string(&task.task_id) || field(context,"attempt")?!=&string(&task.attempt_id) || field(context,"conversation")?!=field(&b.payload,"conversation")? {return Err("chat_task_binding".into())}
    Ok(AgentRunSnapshot::Terminal{summary:AgentRunSummary{request_id:run.intent.request_id.clone(),variant:run.intent.variant.clone(),source_build_identity:run.intent.source_build_identity.clone(),identity:run.identity.clone(),terminal:AgentTerminal::Completed,reason:AgentReason::None,receipt:AgentReceiptSummary{opaque_id:Some(record),outcome:AgentReceiptOutcome::RecordedSuccess}}})
}
