//! Ordinary text intent on the existing Service worker and core Agent drive.
//! Synthetic and fixed live canary routes share the same Agent and durable owner.
use crate::{service_provider::{ProviderAdmission,ModelLocation}, field, service_host::{ServiceHostMode, ServiceHostPorts}, service_root::ServiceRoot, service_runtime::RunControl, service_types::*, supplier_business::BusinessRead, Json, Result};
use muyon_core_agent_lab::{agent::{Agent, State, Limits, Hooks}, agent_ports::AgentPorts, model::{Provider, ProviderControl, ModelRequest, ModelEvent, NativeMessage,Message,Role}, store};
use muyon_plugin_contract_lab::{object, string, parse};
use std::{path::Path, sync::Arc, rc::Rc, cell::RefCell, io::Read};
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
        Ok(())
    }
    pub fn json(&self)->Json { object([("workspace",string(&self.workspace)),("conversation",string(&self.conversation)),("owner",string(&self.owner)),("mode",string(&self.mode)),("policy_revision",string(&self.policy_revision)),("grant_revision",string(&self.grant_revision)),("input_rule",string(&self.rule_revision)),("restriction_revision",string(&self.restriction_revision)),("sensitivity",string(&self.sensitivity)),("output_rule",string("MODEL-TEXT-v1")),("synthetic",Json::Bool(self.synthetic))]) }
}
fn closed(j:&Json,names:&[&str])->Result<()>{let m=j.object()?;if m.len()!=names.len() || names.iter().any(|k|!m.contains_key(*k)){return Err("chat_evidence_fields".into())}Ok(())}
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
fn validate_binding(host:&ServiceHostPorts,payload:&Json,expected:&Json,parent:&Path)->Result<()> {
    let a=current(host,payload)?;
    if field(expected,"authority")?!=&a.json() {return Err("chat_authority_changed".into())}check_text(field(payload,"text")?.string()?)?;crate::chat_history::revalidate(parent,host,expected).map_err(crate::chat_history::failure)
}
pub(crate) fn disclose(b:&BusinessRead)->Result<()> { if b.events.iter().any(|e|field(e,"kind").ok()==Some(&string("answer_delta"))) {validate_binding(b.host.as_ref().ok_or("chat_owner_unavailable")?,&b.payload,b.source_binding.as_ref().ok_or("chat_binding_unavailable")?,b.dir.as_ref().and_then(|d|d.parent()).ok_or("chat_run_unavailable")?)?;let record=receipt(b.dir.as_ref().ok_or("chat_run_unavailable")?,b)?;if live(b){settled_success(b,&record)?;}}Ok(()) }
fn provider_evidence(a:&ProviderAdmission)->Json {
    let b=a.binding();let p=a.profile();object([("profile_id",string(&p.id)),("location",string(match p.location{ModelLocation::Remote=>"remote",ModelLocation::OwnDevice=>"own-device"})),("purpose",string("chat")),("credential_ref",string(&p.credential_ref)),("model_allowed",Json::Bool(b.model_allowed)),("outbound_allowed",Json::Bool(b.outbound_allowed)),("endpoint",string(&p.endpoint)),("endpoint_identity",string(&p.endpoint_identity)),("provider",string(&p.provider)),("model",string(&p.model)),("profile_revision",string(&b.profile_revision)),("policy_revision",string(&b.policy_revision)),("grant_revision",string(&b.grant_revision)),("authorization_owner",string(&b.authorization_owner)),("credential_identity",string(a.credential_handle().identity())),("credential_generation",Json::Number(a.credential_handle().generation().unwrap_or(0).to_string())),("budget_revision",string(&b.budget.revision)),("quota_proof",string(&b.budget.quota_proof)),("max_tokens",Json::Number(a.call_budget().max_tokens.to_string())),("max_micros",Json::Number(a.call_budget().max_micros.to_string()))])
}
pub const LIVE_BATCH:&str="muyon-ordinary-chat-20261019-cny1-two-requests";
pub const LIVE_QUOTA:&str="deepseek-flash-1017-full-prompt-bound-cny-v1";
pub const LIVE_COUNTING:&str="deepseek-flash-1017-bpe-upper-v1";
pub const LIVE_PRICE:&str="deepseek-cny-peak-miss-20261020-v1";
pub(crate) fn live(b:&BusinessRead)->bool { b.source_binding.as_ref().and_then(|c|field(c,"authority").ok()).and_then(|a|field(a,"synthetic").ok())==Some(&Json::Bool(false)) }
fn live_profile(profile:&crate::service_provider::ConfiguredProfile,budget:&crate::service_provider::CallBudget)->Result<()> {
    if profile.id!="ordinary-deepseek-flash-canary" || profile.endpoint!="https://api.deepseek.com/chat/completions" || profile.endpoint_identity!="deepseek-https-chat-v1" || profile.provider!="deepseek" || profile.model!="deepseek-flash" || profile.location!=ModelLocation::Remote || budget.max_tokens!=16512 || budget.max_micros!=33792 || budget.requires_tools || budget.requires_streaming {return Err("chat_live_configuration".into())}Ok(())
}
fn write_send(dir:&Path,context:&Json,body:&Json,state:&str,admission:Option<&ProviderAdmission>,response:Option<&ChatResponse>)->Result<()> {
    let is_live=field(field(context,"authority")?,"synthetic")?==&Json::Bool(false);
    let usage=response.map(|r|if is_live {object([("input",Json::Number(r.input_tokens.to_string())),("output",Json::Number(r.output_tokens.to_string())),("counting_rule",string(LIVE_COUNTING)),("price_rule",string(LIVE_PRICE)),("currency",string("CNY")),("batch",string(LIVE_BATCH)),("fee_upper_micro_cny",Json::Number((r.input_tokens*2+r.output_tokens*8).to_string()))])}else{object([("input",Json::Number(r.input_tokens.to_string())),("output",Json::Number(r.output_tokens.to_string())),("counting_rule",string("synthetic-byte-bound-v1"))])}).unwrap_or(Json::Null);
    let encoded=object([("version",string(if is_live{"ordinary-send-live-v1"}else{"ordinary-send-v1"})),("context",context.clone()),("payload",body.clone()),("state",string(state)),("admission",string(admission.map(|a|a.record_id()).unwrap_or(""))),("provider",admission.map(provider_evidence).unwrap_or(Json::Null)),("answer",string(response.map(|r|r.answer.as_str()).unwrap_or(""))),("usage",usage)]).encode();
    if encoded.len()>65536{return Err("chat_context_limit".into())}
    store::atomic(dir,"ordinary-send-v1.db",&encoded)
}
fn preflight(source:&BusinessRead,context:&Json,body:&Json,output:u64)->Result<()> {
    let mut worst=source.clone();worst.events.clear();
    worst.push("answer_delta",object([("text",string("\\".repeat(output as usize)))]));
    worst.push("provider_receipt",object([("owner",string("ServiceProviderOwner")),("identity",string("r".repeat(512))),("task",field(context,"task")?.clone()),("attempt",field(context,"attempt")?.clone()),("synthetic",Json::Bool(true))]));
    worst.push("terminal",object([("state",string("completed")),("reason",string("none"))]));
    if worst.ordinary_record().encode().len()>32768 || context.encode().len()+body.encode().len()+2*output as usize+32768>65536 {return Err("chat_context_limit".into())}Ok(())
}
struct Shared { record:Option<String>, admitted:bool }
struct ChatProvider<'a> { source:BusinessRead, usage:(Option<u64>,Option<u64>), host:&'a ServiceHostPorts, authority:ChatAuthority, intent:&'a Json, context:Json, dir:&'a Path, request:String, shared:Rc<RefCell<Shared>>, control:Arc<RunControl> }
impl Provider for ChatProvider<'_> {
    fn reported_usage(&self)->(Option<u64>,Option<u64>){self.usage}
    fn respond(&mut self,_:&ModelRequest,_:usize)->Result<ModelEvent>{Err("controlled_chat_required".into())}
    fn respond_controlled(&mut self,request:&ModelRequest,_:usize,_:&[NativeMessage],control:&mut dyn ProviderControl)->Result<ModelEvent> {
        let messages=crate::chat_history::wire_messages(&self.context,field(self.intent,"text")?.string()?)?;
        let expected:Vec<Message>=messages.iter().map(|m|Ok(Message{role:if field(m,"role")?.string()?=="user"{Role::User}else{Role::Assistant},text:field(m,"content")?.string()?.into()})).collect::<Result<_>>()?;
        if request.turn!=1 || !request.tools.is_empty() || request.messages!=expected || request.task!=field(&self.context,"task")?.string()? || request.attempt!=field(&self.context,"attempt")?.string()? {return Err("chat_request_binding".into())}
        control.poll()?;validate_binding(self.host,self.intent,&self.context,self.dir.parent().ok_or("chat_run_unavailable")?)?;
        let bridge=self.host.owner.provider()?;let profile=bridge.readiness(&self.host.budget)?;
        // max_tokens on the wire is OUTPUT; reserve max_tokens remains TOTAL.
        // This conservative synthetic proof counts UTF-8 bytes plus fixed framing.
        if self.host.budget.requires_tools || self.host.budget.requires_streaming {return Err("chat_budget".into())}
        let is_live=!self.authority.synthetic;
        if is_live {live_profile(&profile,&self.host.budget)?;}
        let mut output=if is_live{128}else{1024u64};
        let make_body=|limit:u64|{let mut body=object([("model",string(&profile.model)),("messages",Json::Array(messages.clone())),("n",Json::Number("1".into())),("stream",Json::Bool(false)),("max_tokens",Json::Number(limit.to_string()))]);if is_live {if let Json::Object(fields)=&mut body{fields.insert("thinking".into(),object([("type",string("disabled"))]));}}body};
        // Synthetic counting uses FULL serialized request bytes plus output bytes.
        // This is expressly not a real model tokenizer or currency price proof.
        let frame=make_body(output).encode().len() as u64;
        if !is_live {output=output.min(self.host.budget.max_tokens.checked_sub(frame).ok_or("chat_context_budget_exceeded")?);}
        if output==0{return Err("chat_context_budget_exceeded".into())}
        let body=make_body(output);
        let bytes=body.encode().into_bytes();if bytes.len()>8192{return Err("chat_context_budget_exceeded".into())}preflight(&self.source,&self.context,&body,output)?;write_send(self.dir,&self.context,&body,"prepared",None,None)?;
        let prepared=bridge.prepare_chat(&self.request,&bytes,self.host.budget.clone(),&self.context)?;
        validate_binding(self.host,self.intent,&self.context,self.dir.parent().ok_or("chat_run_unavailable")?)?;control.poll()?;
        let admission=bridge.final_admit(prepared)?;
        {let mut shared=self.shared.borrow_mut();shared.admitted=true;shared.record=Some(admission.record_id().into());}
        write_send(self.dir,&self.context,&body,"admitted",Some(&admission),None)?;
        if is_live && (admission.binding().budget.revision!=LIVE_BATCH || admission.binding().budget.quota_proof!=LIVE_QUOTA) {return Err("chat_live_configuration".into())}
        validate_binding(self.host,self.intent,&self.context,self.dir.parent().ok_or("chat_run_unavailable")?)?;control.poll()?;
        // The same owner atomically validates and one-shot records the handoff.
        // No retries, fallback transport or refunds after this boundary.
        let reply=if is_live{bridge.exchange_live_chat(&admission,&self.context,self.control.clone())?}else{bridge.exchange_chat(&admission,&self.context)?};
        if reply.synthetic!=self.authority.synthetic || reply.input_tokens==0 || reply.output_tokens==0 || (!is_live && (reply.input_tokens!=bytes.len() as u64 || reply.output_tokens!=reply.answer.len() as u64)) || (is_live && reply.input_tokens>16384) || reply.output_tokens>output || reply.input_tokens.checked_add(reply.output_tokens).filter(|n|*n<=self.host.budget.max_tokens).is_none() {return Err("chat_usage_unavailable".into())}
        check_text(&reply.answer)?;validate_binding(self.host,self.intent,&self.context,self.dir.parent().ok_or("chat_run_unavailable")?)?;control.poll()?;
        write_send(self.dir,&self.context,&body,"completed",Some(&admission),Some(&reply))?;
        self.usage=(Some(reply.input_tokens),Some(reply.output_tokens));
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
        if b.chat_synthetic!=Some(authority.synthetic){return Err("chat_authority_changed".into())}
        if !authority.synthetic {control.authorize_live_chat()?;}
        let mut state=State::runtime(field(&b.payload,"text")?.string()?.into(),authority.workspace.clone(),Limits{steps:1,calls:1,context:16384,output:4096,total:32768})?;
        root.attach_task(&run.identity.run_id,AgentTaskIdentity{task_id:state.task.clone(),attempt_id:state.attempt.clone()})?;
        run.identity.actual_task=Some(AgentTaskIdentity{task_id:state.task.clone(),attempt_id:state.attempt.clone()});summary.identity=run.identity.clone();
        let history=crate::chat_history::freeze(root,b).map_err(crate::chat_history::failure)?;
        let context=object([("history_version",string(crate::chat_history::VERSION)),("history",Json::Array(history)),("authority",authority.json()),("workspace",string(&authority.workspace)),("conversation",field(&b.payload,"conversation")?.clone()),("input_ref",string(format!("{}:{}",run.identity.run_id,run.intent.request_id))),("task",string(&state.task)),("attempt",string(&state.attempt)),("input_version",string("utf8-exact-v1"))]);
        if context.encode().len()>16384{return Err("chat_context_limit".into())}
        let wire=crate::chat_history::wire_messages(&context,field(&b.payload,"text")?.string()?)?;
        state.context=wire.iter().map(|m|Ok(Message{role:if field(m,"role")?.string()?=="user"{Role::User}else{Role::Assistant},text:field(m,"content")?.string()?.into()})).collect::<Result<_>>()?;
        if muyon_core_agent_lab::model::context_bytes(&state.context)>state.limits.context{return Err("chat_context_limit".into())}
        b.source_binding=Some(context.clone());b.save(dir)?;
        let mut agent=Agent{dir:dir.into(),state};let mut ports=ChatPorts{control:control.clone(),shared:shared.clone()};
        let synthetic=authority.synthetic;
        let mut provider=ChatProvider{source:b.clone(),usage:(None,None),host:&host,authority,intent:&b.payload,context,dir,request:run.intent.request_id.clone(),shared:shared.clone(),control:control.clone()};
        agent.run_with_runtime_ports(&mut provider,&mut ports,&Hooks::default())?;
        if agent.state.status!="completed" {return Err(if agent.state.reason.is_empty(){"chat_incomplete".into()}else{agent.state.reason})}
        let record=shared.borrow().record.clone().ok_or("chat_receipt_unavailable")?;
        b.push("answer_delta",object([("text",string(agent.state.answer))]));
        b.push("provider_receipt",object([("owner",string("ServiceProviderOwner")),("identity",string(&record)),("task",string(&agent.state.task)),("attempt",string(&agent.state.attempt)),("synthetic",Json::Bool(synthetic))]));
        summary.receipt=AgentReceiptSummary{opaque_id:Some(record),outcome:AgentReceiptOutcome::RecordedSuccess};summary.terminal=AgentTerminal::Completed;summary.reason=AgentReason::None;Ok::<(),String>(())
    })();
    let reason=if let Err(reason)=result {b.events.clear();if shared.borrow().admitted{summary.terminal=AgentTerminal::OutcomeUnknown;summary.receipt.outcome=AgentReceiptOutcome::Unknown;summary.receipt.opaque_id=shared.borrow().record.clone();}else if reason=="native_cancelled"{summary.terminal=AgentTerminal::Cancelled;summary.reason=AgentReason::Cancelled;}reason}else{"none".into()};
    let reason=if ["none","chat_authority_unconfigured","chat_authority_denied","chat_owner_unconfigured","chat_text_unreviewed","chat_credential_signal","provider_budget_reservation_failed","provider_config_unavailable","chat_credential_capability_unavailable","provider_credential_changed","provider_binding_changed","native_cancelled","native_deadline","chat_history_unavailable","chat_context_limit","chat_context_budget_exceeded"].contains(&reason.as_str()){reason}else{"chat_failed_or_unavailable".into()};
    let state=match summary.terminal{AgentTerminal::Completed=>"completed",AgentTerminal::Cancelled=>"cancelled",AgentTerminal::OutcomeUnknown=>"outcome_unknown",_=>"failed"};b.push("terminal",object([("state",string(state)),("reason",string(reason))]));
    // Never put rejected credential-bearing input into a durable business ledger.
    if b.source_binding.is_some() && b.save(dir).is_err(){root.poison();b.events.clear();b.push("terminal",object([("state",string("outcome_unknown")),("reason",string("chat_storage_failure"))]));summary.terminal=AgentTerminal::OutcomeUnknown;summary.receipt.outcome=AgentReceiptOutcome::Unknown;}
    summary
}
pub(crate) fn receipt(dir:&Path,b:&BusinessRead)->Result<String> {
    let path=dir.join("ordinary-send-v1.db");let meta=std::fs::symlink_metadata(&path).map_err(|_|"chat_receipt_missing")?;
    if !meta.is_file() || meta.file_type().is_symlink() || meta.len()>65536 {return Err("chat_receipt_bound".into())}
    let mut bytes=Vec::new();std::fs::File::open(path).map_err(|_|"chat_receipt_missing")?.take(65537).read_to_end(&mut bytes).map_err(|_|"chat_receipt_missing")?;
    if bytes.len()>65536{return Err("chat_receipt_bound".into())}let j=parse(&bytes)?;
    closed(&j,&["version","context","payload","state","admission","provider","answer","usage"])?;
    let is_live=live(b);
    if field(&j,"version")?!=&string(if is_live{"ordinary-send-live-v1"}else{"ordinary-send-v1"}) || field(&j,"state")?!=&string("completed") || b.source_binding.as_ref()!=Some(field(&j,"context")?) {return Err("chat_receipt_binding".into())}
    let answer=field(&j,"answer")?.string()?;check_text(answer)?;
    let e=b.events.iter().find(|e|field(e,"kind").ok()==Some(&string("answer_delta"))).ok_or("chat_answer_missing")?;
    if field(field(e,"payload")?,"text")?!=&string(answer){return Err("chat_answer_binding".into())}
    let r=field(&j,"admission")?.string()?;if !id(r,512){return Err("chat_receipt_identity".into())}
    let evidence=b.events.iter().find(|e|field(e,"kind").ok()==Some(&string("provider_receipt"))).ok_or("chat_receipt_missing")?;let event=field(evidence,"payload")?;
    let context=field(&j,"context")?;
    let versioned=crate::chat_history::versioned(context)?;
    if context.encode().len()>16384{return Err("chat_context_limit".into())}
    for k in ["workspace","conversation","input_ref","task","attempt"]{if !id(field(context,k)?.string()?,512){return Err("chat_context_evidence".into())}}
    if field(context,"input_version")?!=&string("utf8-exact-v1") || field(context,"conversation")?!=field(&b.payload,"conversation")? {return Err("chat_input_version".into())}
    let authority=field(context,"authority")?;
    closed(authority,&["workspace","conversation","owner","mode","policy_revision","grant_revision","input_rule","restriction_revision","sensitivity","output_rule","synthetic"])?;
    if field(authority,"workspace")?!=field(context,"workspace")? || field(authority,"conversation")?!=field(context,"conversation")? || field(authority,"input_rule")?!=&string("USER-TEXT-v1") || field(authority,"output_rule")?!=&string("MODEL-TEXT-v1") || field(authority,"synthetic")?!=&Json::Bool(!is_live) || !matches!(field(authority,"sensitivity")?.string()?,"personal"|"commercial") || !matches!(field(authority,"mode")?.string()?,"auto"|"full-allow"|"read-only"|"ask-every-time"){return Err("chat_rule_evidence".into())}
    let provider=field(&j,"provider")?;
    closed(provider,&["profile_id","location","purpose","credential_ref","model_allowed","outbound_allowed","endpoint","endpoint_identity","provider","model","profile_revision","policy_revision","grant_revision","authorization_owner","credential_identity","credential_generation","budget_revision","quota_proof","max_tokens","max_micros"])?;
    for k in ["profile_id","credential_ref","endpoint_identity","provider","model","profile_revision","policy_revision","grant_revision","authorization_owner","credential_identity","budget_revision","quota_proof"]{if !id(field(provider,k)?.string()?,512){return Err("chat_profile_evidence".into())}}
    if !crate::service_provider::https_endpoint(field(provider,"endpoint")?.string()?) || field(provider,"purpose")?!=&string("chat") || !matches!(field(provider,"location")?.string()?,"remote"|"own-device") || field(provider,"model_allowed")?!=&Json::Bool(true) || field(provider,"outbound_allowed")?!=&Json::Bool(true) || field(provider,"authorization_owner")?!=field(authority,"owner")? || field(provider,"policy_revision")?!=field(authority,"policy_revision")? || field(provider,"grant_revision")?!=field(authority,"grant_revision")? {return Err("chat_profile_evidence".into())}
    let total=field(provider,"max_tokens")?.integer()?;
    if total==0 || field(provider,"max_micros")?.integer()?==0 {return Err("chat_budget_evidence".into())}
    if field(event,"identity")?!=&string(r) || field(event,"owner")?!=&string("ServiceProviderOwner") || field(event,"synthetic")?!=&Json::Bool(!is_live) || field(event,"task")?!=field(context,"task")? || field(event,"attempt")?!=field(context,"attempt")? {return Err("chat_receipt_binding".into())}
    let wire=field(&j,"payload")?;
    if is_live {closed(wire,&["model","messages","n","stream","max_tokens","thinking"])?;closed(field(wire,"thinking")?,&["type"])?;if field(field(wire,"thinking")?,"type")?!=&string("disabled"){return Err("chat_wire_budget_evidence".into())}}
    else{closed(wire,&["model","messages","n","stream","max_tokens"])?;}
    let messages=field(wire,"messages")?.array()?;
    let output=field(wire,"max_tokens")?.integer()?;
    if output==0 || output>1024 || (!is_live && (wire.encode().len() as u64).checked_add(output).filter(|n|*n<=total).is_none()) || (is_live && output!=128) || field(wire,"n")?.integer()?!=1 || field(wire,"stream")?!=&Json::Bool(false){return Err("chat_wire_budget_evidence".into())}
    if messages!=crate::chat_history::wire_messages(context,field(&b.payload,"text")?.string()?)?.as_slice() || field(wire,"model")?!=field(field(&j,"provider")?,"model")? {return Err("chat_payload_binding".into())}
    let usage=field(&j,"usage")?;
    if is_live {closed(usage,&["input","output","counting_rule","price_rule","currency","batch","fee_upper_micro_cny"])?;}else{closed(usage,&["input","output","counting_rule"])?;}
    let used_in=field(usage,"input")?.integer()?;let used_out=field(usage,"output")?.integer()?;
    if !is_live && versioned && (used_in!=wire.encode().len() as u64 || used_out!=answer.len() as u64){return Err("chat_usage_evidence".into())}
    if field(usage,"counting_rule")?!=&string(if is_live{LIVE_COUNTING}else{"synthetic-byte-bound-v1"}) || used_in==0 || used_out==0 || used_out>output || used_in.checked_add(used_out).filter(|n|*n<=total).is_none() || field(provider,"credential_generation")?.integer()?==0 {return Err("chat_usage_evidence".into())}
    if is_live {
        for (key,value) in [("profile_id","ordinary-deepseek-flash-canary"),("endpoint","https://api.deepseek.com/chat/completions"),("endpoint_identity","deepseek-https-chat-v1"),("provider","deepseek"),("model","deepseek-flash"),("location","remote"),("budget_revision",LIVE_BATCH),("quota_proof",LIVE_QUOTA)] {if field(provider,key)?!=&string(value){return Err("chat_profile_evidence".into())}}
        if total!=16512 || field(provider,"max_micros")?.integer()?!=33792 || used_in>16384 || field(usage,"price_rule")?!=&string(LIVE_PRICE) || field(usage,"currency")?!=&string("CNY") || field(usage,"batch")?!=&string(LIVE_BATCH) || field(usage,"fee_upper_micro_cny")?.integer()?!=used_in*2+used_out*8 {return Err("chat_usage_evidence".into())}
    }
    Ok(r.into())
}
pub(crate) fn restore(dir:&Path,run:&AgentDurableRun,b:&BusinessRead)->Result<AgentRunSnapshot> {
    restore_with_host(dir,run,b,b.host.as_deref())
}
pub(crate) fn restore_with_host(dir:&Path,run:&AgentDurableRun,b:&BusinessRead,host:Option<&ServiceHostPorts>)->Result<AgentRunSnapshot> {
    // No Agent::open, send or resume. Interrupted chat is conservatively unknown.
    let completed=b.events.last().and_then(|e|field(e,"payload").ok()).and_then(|p|field(p,"state").ok())==Some(&string("completed"));
    if !completed{return Ok(crate::service_evidence::unknown(run,AgentReceiptSummary{opaque_id:None,outcome:AgentReceiptOutcome::Unknown}))}
    let record=receipt(dir,b)?;let context=b.source_binding.as_ref().ok_or("chat_binding_missing")?;let task=run.identity.actual_task.as_ref().ok_or("chat_task_missing")?;
    if live(b) && host.and_then(|h|h.owner.provider().ok()).and_then(|p|p.chat_settlement(&record).ok()).as_deref()!=Some("success"){return Ok(crate::service_evidence::unknown(run,AgentReceiptSummary{opaque_id:Some(record),outcome:AgentReceiptOutcome::Unknown}))}
    if field(context,"input_ref")?!=&string(format!("{}:{}",run.identity.run_id,run.intent.request_id)) || field(context,"task")?!=&string(&task.task_id) || field(context,"attempt")?!=&string(&task.attempt_id) || field(context,"conversation")?!=field(&b.payload,"conversation")? {return Err("chat_task_binding".into())}
    Ok(AgentRunSnapshot::Terminal{summary:AgentRunSummary{request_id:run.intent.request_id.clone(),variant:run.intent.variant.clone(),source_build_identity:run.intent.source_build_identity.clone(),identity:run.identity.clone(),terminal:AgentTerminal::Completed,reason:AgentReason::None,receipt:AgentReceiptSummary{opaque_id:Some(record),outcome:AgentReceiptOutcome::RecordedSuccess}}})
}
fn settled_success(b:&BusinessRead,record:&str)->Result<()> {
    if b.host.as_ref().ok_or("chat_owner_unavailable")?.owner.provider()?.chat_settlement(record)?!="success" {return Err("chat_settlement_unavailable".into())}Ok(())
}
/// Only called under the controller mutex after worker completion, immediately before Terminal.
/// A successful owner settlement is the final fallible commit: no disk writes or polls follow it.
pub(crate) fn finalize(root:&mut ServiceRoot,b:&mut BusinessRead,summary:&mut AgentRunSummary,control:Option<&RunControl>) {
    if !live(b){return}
    let record=summary.receipt.opaque_id.clone().ok_or_else(||"chat_receipt_missing".into()).or_else(|_:String| (||{
        let path=b.dir.as_ref().ok_or("chat_run_unavailable")?.join("ordinary-send-v1.db");
        let meta=std::fs::symlink_metadata(&path).map_err(|_|"chat_receipt_missing")?;
        if !meta.is_file() || meta.file_type().is_symlink() || meta.len()>65536{return Err("chat_receipt_bound".into())}
        let mut bytes=Vec::new();std::fs::File::open(path).map_err(|_|"chat_receipt_missing")?.take(65537).read_to_end(&mut bytes).map_err(|_|"chat_receipt_missing")?;
        if bytes.len()>65536{return Err("chat_receipt_bound".into())}
        let json=parse(&bytes)?;let record=field(&json,"admission")?.string()?;
        if !id(record,512){return Err("chat_receipt_identity".into())}Ok::<String,String>(record.into())
    })());
    let Ok(record)=record else {return};
    let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{
        let host=b.host.as_ref().ok_or("chat_owner_unavailable")?;
        let bridge=host.owner.provider()?;
        let accepted=summary.terminal==AgentTerminal::Completed && !root.is_poisoned() &&
            receipt(b.dir.as_ref().ok_or("chat_run_unavailable")?,b).is_ok() &&
            validate_binding(host,&b.payload,b.source_binding.as_ref().ok_or("chat_binding_unavailable")?,b.dir.as_ref().and_then(|d|d.parent()).ok_or("chat_run_unavailable")?).is_ok() &&
            control.is_some_and(|c|c.poll().is_ok());
        if accepted && bridge.settle_chat(&record,true).is_ok(){return Ok(())}
        let _=bridge.settle_chat(&record,false);
        Err::<(),String>("chat_settlement_unavailable".into())
    }));
    let result=match result {Ok(result)=>result,Err(_)=>{
        let _=std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            if let Some(host)=b.host.as_ref(){if let Ok(bridge)=host.owner.provider(){let _=bridge.settle_chat(&record,false);}}
        }));
        Err("chat_settlement_unavailable".into())
    }};
    if result.is_err() {
        summary.terminal=AgentTerminal::OutcomeUnknown;summary.reason=AgentReason::Interrupted;
        summary.receipt=AgentReceiptSummary{opaque_id:Some(record),outcome:AgentReceiptOutcome::Unknown};
        b.events.clear();b.push("terminal",object([("state",string("outcome_unknown")),("reason",string("chat_settlement_unavailable"))]));
        if b.save(b.dir.as_ref().unwrap()).is_err(){root.poison();}
    }
}
