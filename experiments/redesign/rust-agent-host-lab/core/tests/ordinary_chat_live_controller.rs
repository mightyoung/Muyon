//! Exact offline fixture target. No network, credentials, task.db or old HTTP runner.
use muyon_plugin_contract_lab::{parse,string,Json};
use muyon_rust_agent_host_lab::{ordinary_chat::*,service_controller::AgentServiceController,service_host::*,service_provider::*,service_runtime::RunControl,service_types::*};
use std::{collections::{BTreeMap,BTreeSet},path::PathBuf,rc::Rc,sync::{Arc,Mutex,Condvar}};
type Result<T>=std::result::Result<T,String>;
#[derive(Default)]
struct Facts { sends:usize, held:BTreeSet<String>, admissions:BTreeSet<String>, sent:BTreeSet<String>, contexts:BTreeMap<String,Json>, payloads:Vec<Json>, settlements:BTreeMap<String,String>, lose:bool, settle_fail:bool, cancel_response:bool, cancel_final:bool, after_response:usize, control:Option<Arc<RunControl>>, wrong_usage:bool, panic_response:bool, panic_settle:bool, authority_calls:usize, authority_gate:Option<Arc<(Mutex<(bool,bool)>,Condvar)>> }
struct Owner(Arc<Mutex<Facts>>);
fn binding()->ProviderBinding {
    ProviderBinding{profile:ConfiguredProfile{id:"ordinary-deepseek-flash-canary".into(),endpoint:"https://api.deepseek.com/chat/completions".into(),endpoint_identity:"deepseek-https-chat-v1".into(),provider:"deepseek".into(),model:"deepseek-flash".into(),location:ModelLocation::Remote,purpose:ModelPurpose::Chat,credential_ref:"local-ephemeral-canary".into(),declared:Capabilities{tool_calls:false,streaming:false},tested:Capabilities{tool_calls:false,streaming:false}},profile_revision:"p1".into(),policy_revision:"policy1".into(),grant_revision:"grant1".into(),authorization_owner:"fixture-owner".into(),model_allowed:true,outbound_allowed:true,budget:ProviderBudget{revision:LIVE_BATCH.into(),quota_proof:LIVE_QUOTA.into(),remaining_calls:2,remaining_tokens:33024,remaining_micros:1_000_000}}
}
impl ServiceHostOwner for Owner {
    fn current_scope(&self)->Result<ServiceHostScope>{panic!("chat must not use supplier scope")}
    fn provider(&self)->Result<ServiceProviderBridge>{Ok(ServiceProviderBridge::new(Rc::new(Owner(self.0.clone()))))}
    fn chat_authority(&self,conversation:&str,_:&str)->Result<ChatAuthority>{
        let mut f=self.0.lock().unwrap();
        if f.control.is_some(){f.after_response+=1;if f.cancel_final && f.after_response==2{f.control.as_ref().unwrap().request_cancel();}}
        f.authority_calls+=1;let gate=if f.authority_calls==2{f.authority_gate.clone()}else{None};drop(f);
        if let Some(gate)=gate {let(lock,signal)=&*gate;let mut state=lock.lock().unwrap();state.0=true;signal.notify_all();while !state.1{state=signal.wait(state).unwrap();}}
        Ok(ChatAuthority{workspace:"fixture-workspace".into(),conversation:conversation.into(),owner:"fixture-owner".into(),mode:"full-allow".into(),policy_revision:"policy1".into(),grant_revision:"grant1".into(),rule_revision:"USER-TEXT-v1".into(),restriction_revision:"restriction1".into(),sensitivity:"personal".into(),active:true,model_allowed:true,outbound_allowed:true,inherited_allowed:true,synthetic:false})
    }
}
impl ServiceProviderHost for Owner {
    fn current_binding(&self)->Result<Option<ProviderBinding>>{Ok(Some(binding()))}
    fn credential_handle(&self,p:&ConfiguredProfile)->Result<Option<CredentialHandle>>{Ok(Some(CredentialHandle::with_generation(&p.id,&p.credential_ref,"ephemeral-fixture-capability",1)?))}
    fn review_payload(&self,_:&ProviderBinding,p:&[u8])->Result<()>{let j=parse(p)?;assert_eq!(j.object()?["thinking"].object()?["type"],string("disabled"));assert_eq!(j.object()?["max_tokens"],Json::Number("128".into()));Ok(())}
    fn reserve_budget(&self,_:&ProviderBinding,id:&str,_:&[u8],budget:&CallBudget)->Result<String>{let mut f=self.0.lock().unwrap();if f.held.contains(id)||f.admissions.contains(id)||f.held.len()+f.admissions.len()>=2{return Err("fixture-quota".into())}assert_eq!((budget.max_tokens,budget.max_micros),(16512,33792));f.held.insert(id.into());Ok(id.into())}
    fn release_reservation(&self,id:&str)->Result<()>{let mut f=self.0.lock().unwrap();f.held.remove(id);f.admissions.insert(id.into());Ok(())}
    fn bind_chat_context(&self,reservation:&str,_:&ProviderBinding,_:&str,_:&[u8],_:&CredentialHandle,context:&Json)->Result<()>{self.0.lock().unwrap().contexts.insert(format!("admission-{reservation}"),context.clone());Ok(())}
    fn commit_admission(&self,reservation:&str,_:&ProviderBinding,_:&str,_:&[u8],_:&CredentialHandle)->Result<String>{let mut f=self.0.lock().unwrap();if !f.held.remove(reservation){return Err("fixture-admission".into())}f.admissions.insert(reservation.into());let id=format!("admission-{reservation}");f.settlements.insert(id.clone(),"pending".into());Ok(id)}
    fn exchange_chat(&self,_:&ProviderAdmission,_:&Json)->Result<ChatResponse>{panic!("live must not fall back to synthetic")}
    fn exchange_live_chat(&self,a:&ProviderAdmission,ctx:&Json,control:Arc<RunControl>)->Result<ChatResponse>{
        control.poll()?;let mut f=self.0.lock().unwrap();if !f.sent.insert(a.record_id().into()) || f.contexts.get(a.record_id())!=Some(ctx){return Err("fixture-replay".into())}
        f.sends+=1;f.payloads.push(parse(a.payload())?);f.control=Some(control.clone());f.after_response=0;
        if f.panic_response{drop(f);panic!("offline fixture crash after owner handoff")}
        if f.lose{return Err("fixture-unknown".into())}if f.cancel_response{control.request_cancel();}
        Ok(ChatResponse{answer:"remember blue".into(),input_tokens:if f.wrong_usage{16385}else{20},output_tokens:3,synthetic:false})
    }
    fn settle_chat(&self,id:&str,accepted:bool)->Result<()>{let mut f=self.0.lock().unwrap();if accepted && f.panic_settle{drop(f);panic!("offline local settlement fault")}if accepted && f.settle_fail{return Err("fixture-settlement-failure".into())}let old=f.settlements.get(id).ok_or("fixture-missing")?;if old=="unknown" && accepted{return Err("fixture-stopped".into())}f.settlements.insert(id.into(),if accepted{"success"}else{"unknown"}.into());Ok(())}
    fn chat_settlement(&self,id:&str)->Result<String>{self.0.lock().unwrap().settlements.get(id).cloned().ok_or_else(||"fixture-missing".into())}
}
fn start(path:&PathBuf,f:Arc<Mutex<Facts>>)->(AgentServiceController,AgentClientRef){
    let host=Arc::new(ServiceHostPorts::new(Arc::new(Owner(f)),ServiceHostMode::ConfiguredChat,CallBudget{max_tokens:16512,max_micros:33792,requires_tools:false,requires_streaming:false}));
    let c=AgentServiceController::new_with_host(AgentHostServiceConfig{protocol:1,private_root:path.to_string_lossy().into(),build_identity:"a".repeat(40)},host).unwrap();c.await_settled();
    let r=c.connect(AgentConnectRequest{protocol:1,platform_client_key:"b".repeat(32)});let AgentConnectOutcome::Connected{client_lease,..}=r.outcome else{panic!("connect")};
    let client=AgentClientRef{protocol:1,expected_service_epoch:r.meta.service_epoch,client_lease};c.set_visibility(AgentVisibilityRequest{client:client.clone(),observation_generation:1,visible:true});(c,client)
}
fn open(f:Arc<Mutex<Facts>>)->(PathBuf,AgentServiceController,AgentClientRef){let path=PathBuf::from("/private/tmp").join(format!("ordinary-live-fixture-{}-{}",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));muyon_core_agent_lab::store::create_dir(&path).unwrap();let(c,client)=start(&path,f);(path,c,client)}
fn submit(c:&AgentServiceController,client:&AgentClientRef,id:&str,text:&str)->Json{c.submit_ordinary_chat(client.clone(),id.into(),"fixture-conversation".into(),text.into());c.await_settled();events(c,client,id)}
fn events(c:&AgentServiceController,client:&AgentClientRef,id:&str)->Json{parse(c.supplier_read_events(client.clone(),id.into(),0).as_bytes()).unwrap()}
fn completed(j:&Json)->bool{j.encode().contains("\"state\":\"completed\"")}
fn clean(path:PathBuf,c:AgentServiceController){c.retire_service();c.await_settled();drop(c);std::fs::remove_dir_all(path).unwrap();}
#[test]
fn live_two_turns_use_same_agent_full_history_actual_token_units_and_owner_settlement(){
    let f=Arc::new(Mutex::new(Facts::default()));let(path,c,client)=open(f.clone());
    let first=submit(&c,&client,"first","remember a synthetic blue color");assert!(completed(&first),"{}",first.encode());
    assert_eq!(first.object().unwrap()["synthetic"],Json::Bool(false));
    let second=submit(&c,&client,"second","what synthetic color did you remember");assert!(completed(&second),"{}",second.encode());
    assert_eq!(second.object().unwrap()["synthetic"],Json::Bool(false));
    let f=f.lock().unwrap();assert_eq!(f.sends,2);assert!(f.settlements.values().all(|s|s=="success"));let messages=f.payloads[1].object().unwrap()["messages"].array().unwrap();assert_eq!(messages.len(),3);assert_eq!(messages[1].object().unwrap()["content"],string("remember blue"));drop(f);
    let run=first.object().unwrap()["run_id"].string().unwrap();let receipt=parse(&std::fs::read(path.join("native-agent-service-v1").join(run).join("ordinary-send-v1.db")).unwrap()).unwrap();
    assert_eq!(receipt.object().unwrap()["version"],string("ordinary-send-live-v1"));let usage=receipt.object().unwrap()["usage"].object().unwrap();assert_eq!(usage["input"],Json::Number("20".into()));assert_eq!(usage["fee_upper_micro_cny"],Json::Number("64".into()));assert_ne!(receipt.object().unwrap()["payload"].encode().len(),20);
    assert!(completed(&submit(&c,&client,"first","remember a synthetic blue color")));clean(path,c);
}
#[test]
fn post_response_final_poll_cancel_unknown_and_settlement_failure_never_publish_or_resend(){
    for facts in [Facts{cancel_response:true,..Facts::default()},Facts{cancel_final:true,..Facts::default()},Facts{lose:true,..Facts::default()},Facts{settle_fail:true,..Facts::default()},Facts{wrong_usage:true,..Facts::default()},Facts{panic_response:true,..Facts::default()},Facts{panic_settle:true,..Facts::default()}] {
        let f=Arc::new(Mutex::new(facts));let(path,c,client)=open(f.clone());let reply=submit(&c,&client,"uncertain","synthetic input");assert!(!completed(&reply),"{}",reply.encode());assert!(reply.encode().contains("outcome_unknown"));assert!(!reply.encode().contains("remember blue"));assert_eq!(reply.object().unwrap()["synthetic"],Json::Bool(false));
        for _ in 0..2{let replay=submit(&c,&client,"uncertain","synthetic input");assert!(!completed(&replay));}
        let facts=f.lock().unwrap();assert_eq!(facts.sends,1);assert_eq!(facts.settlements.get("admission-uncertain").map(String::as_str),Some("unknown"));drop(facts);clean(path,c);
    }
}
#[test]
fn live_source_is_frozen_before_first_admitted_run_id_and_never_flips_on_unknown_or_read_error(){
    for cancel in [false,true] {
        let gate=Arc::new((Mutex::new((false,false)),Condvar::new()));
        let f=Arc::new(Mutex::new(Facts{authority_gate:Some(gate.clone()),..Facts::default()}));let(path,c,client)=open(f.clone());
        let queued=parse(c.submit_ordinary_chat(client.clone(),"early".into(),"fixture-conversation".into(),"synthetic input".into()).as_bytes()).unwrap();
        assert_eq!(queued.object().unwrap()["synthetic"],Json::Bool(false));
        let(lock,signal)=&*gate;let state=lock.lock().unwrap();let(state,timeout)=signal.wait_timeout_while(state,std::time::Duration::from_secs(10),|s|!s.0).unwrap();assert!(!timeout.timed_out() && state.0);drop(state);
        let admitted=events(&c,&client,"early");assert_eq!(admitted.object().unwrap()["synthetic"],Json::Bool(false));assert_ne!(admitted.object().unwrap()["run_id"],Json::Null);assert!(admitted.object().unwrap()["events"].array().unwrap().is_empty());
        let run=admitted.object().unwrap()["run_id"].string().unwrap().to_owned();
        assert!(!path.join("native-agent-service-v1").join(&run).join("source.db").exists(),"the test must observe admission before context freeze");
        if cancel{c.cancel(AgentCancelRequest{client:client.clone(),run:AgentRunRef{request_id:"early".into(),variant:AgentReadVariant::Inquiry,run_id:None}});}
        {let mut state=lock.lock().unwrap();state.1=true;signal.notify_all();}c.await_settled();
        let final_reply=events(&c,&client,"early");assert_eq!(final_reply.object().unwrap()["synthetic"],Json::Bool(false));assert_eq!(completed(&final_reply),!cancel);
        let bad_cursor=parse(c.supplier_read_events(client.clone(),"early".into(),-1).as_bytes()).unwrap();assert_eq!(bad_cursor.object().unwrap()["synthetic"],Json::Bool(false));
        let conflict=parse(c.submit_ordinary_chat(client.clone(),"early".into(),"fixture-conversation".into(),"different synthetic input".into()).as_bytes()).unwrap();assert_eq!(conflict.object().unwrap()["synthetic"],Json::Bool(false));assert!(!conflict.encode().contains("remember blue"));
        if !cancel{std::fs::write(path.join("native-agent-service-v1").join(run).join("ordinary-send-v1.db"),b"malformed-current-fixture").unwrap();let unavailable=events(&c,&client,"early");assert_eq!(unavailable.object().unwrap()["synthetic"],Json::Bool(false));assert!(!unavailable.encode().contains("remember blue"));}
        clean(path,c);
    }
}
#[test]
fn restore_requires_owner_success_pending_unknown_absent_never_resend(){
    for settlement in [Some("success"),Some("pending"),Some("unknown"),None] {
        let f=Arc::new(Mutex::new(Facts::default()));let(path,c,client)=open(f.clone());let reply=submit(&c,&client,"restored","synthetic input");assert!(completed(&reply),"{}",reply.encode());c.retire_service();c.await_settled();drop(c);
        {let mut facts=f.lock().unwrap();facts.control=None;match settlement{Some(value)=>{facts.settlements.insert("admission-restored".into(),value.into());},None=>{facts.settlements.clear();}}}
        let(c,client)=start(&path,f.clone());let restored=events(&c,&client,"restored");assert_eq!(completed(&restored),settlement==Some("success"),"{}",restored.encode());assert_eq!(f.lock().unwrap().sends,1);clean(path,c);
    }
}
#[test]
fn corrupted_business_missing_on_restore_keeps_installed_live_owner_source_false(){
    let f=Arc::new(Mutex::new(Facts::default()));let(path,c,client)=open(f.clone());
    let first=submit(&c,&client,"missing-source","synthetic input");assert!(completed(&first));
    let run=first.object().unwrap()["run_id"].string().unwrap().to_owned();c.retire_service();c.await_settled();drop(c);
    std::fs::write(path.join("native-agent-service-v1").join(run).join("source.db"),b"current-fixture-corrupt").unwrap();
    let(c,client)=start(&path,f.clone());let restored=events(&c,&client,"missing-source");
    assert_eq!(restored.object().unwrap()["synthetic"],Json::Bool(false));assert!(!completed(&restored));assert!(!restored.encode().contains("remember blue"));
    let duplicate=parse(c.submit_ordinary_chat(client.clone(),"missing-source".into(),"fixture-conversation".into(),"synthetic input".into()).as_bytes()).unwrap();assert_eq!(duplicate.object().unwrap()["synthetic"],Json::Bool(false));
    assert_eq!(f.lock().unwrap().sends,1);clean(path,c);
}
