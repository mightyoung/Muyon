//! New-root, no-network ordinary chat acceptance. Never invokes old HTTP/reopen paths.
use muyon_plugin_contract_lab::{parse, string, Json};
use muyon_rust_agent_host_lab::{service_controller::AgentServiceController, service_host::*, service_provider::*, service_types::*, ordinary_chat::*};
use std::{collections::{BTreeSet,BTreeMap}, path::PathBuf, rc::Rc, sync::{Arc, Mutex}};
type Result<T> = std::result::Result<T,String>;
#[derive(Default)]
struct Facts { revoked: bool, generation: u64, sends: usize, held: BTreeSet<String>, used: BTreeSet<String>, payloads: Vec<Vec<u8>>, lose: bool, rotate_on_reserve: bool, rotate_on_commit:bool, output_secret:bool, profile_drift:bool, contexts:BTreeMap<String,Json>, attempts:BTreeSet<String> }
struct Owner(Arc<Mutex<Facts>>);
fn binding() -> ProviderBinding {
    ProviderBinding { profile: ConfiguredProfile { id:"fixture-profile".into(),endpoint:"https://ordinary-chat.invalid/v1/chat/completions".into(),endpoint_identity:"fixture-endpoint".into(),provider:"synthetic".into(),model:"fixture-chat-model".into(),location:ModelLocation::OwnDevice,purpose:ModelPurpose::Chat,credential_ref:"fixture-handle".into(),declared:Capabilities{tool_calls:false,streaming:false},tested:Capabilities{tool_calls:false,streaming:false}},profile_revision:"p1".into(),policy_revision:"policy1".into(),grant_revision:"grant1".into(),authorization_owner:"fixture-owner".into(),model_allowed:true,outbound_allowed:true,budget:ProviderBudget{revision:"synthetic-epoch1".into(),quota_proof:"synthetic-total-byte-bound1".into(),remaining_calls:2,remaining_tokens:16384,remaining_micros:2} }
}
impl ServiceHostOwner for Owner {
    fn current_scope(&self)->Result<ServiceHostScope> { panic!("ordinary chat must not invent supplier scope") }
    fn provider(&self)->Result<ServiceProviderBridge> { Ok(ServiceProviderBridge::new(Rc::new(Owner(self.0.clone())))) }
    fn chat_authority(&self, conversation:&str, _text:&str)->Result<ChatAuthority> {
        let f=self.0.lock().unwrap();
        Ok(ChatAuthority { workspace:"fixture-workspace".into(), conversation:conversation.into(), owner:"fixture-owner".into(), mode:"full-allow".into(), policy_revision:"policy1".into(), grant_revision:"grant1".into(), rule_revision:"USER-TEXT-v1".into(), restriction_revision:"source1".into(), sensitivity:"personal".into(), active:!f.revoked, model_allowed:true, outbound_allowed:true, inherited_allowed:true, synthetic:true })
    }
}
impl ServiceProviderHost for Owner {
    fn current_binding(&self)->Result<Option<ProviderBinding>> {let mut b=binding();if self.0.lock().unwrap().profile_drift{b.profile_revision="changed".into()}Ok(Some(b)) }
    fn credential_handle(&self,p:&ConfiguredProfile)->Result<Option<CredentialHandle>> { let f=self.0.lock().unwrap();Ok(Some(CredentialHandle::with_generation(&p.id,&p.credential_ref,&format!("fixture-generation-{}",f.generation),f.generation+1)?)) }
    fn review_payload(&self,_:&ProviderBinding,p:&[u8])->Result<()> { if self.0.lock().unwrap().revoked || p.is_empty(){Err("denied".into())}else{Ok(())} }
    fn reserve_budget(&self,_:&ProviderBinding,id:&str,_:&[u8],_:&CallBudget)->Result<String> { let mut f=self.0.lock().unwrap();if f.used.contains(id)||f.held.contains(id)||f.used.len()+f.held.len()>=2{return Err("quota".into())}f.held.insert(id.into());if f.rotate_on_reserve{f.generation+=1;}Ok(id.into()) }
    fn release_reservation(&self,id:&str)->Result<()> {let mut f=self.0.lock().unwrap();f.held.remove(id);f.used.insert(id.into());Ok(())}
    fn commit_admission(&self,r:&str,_:&ProviderBinding,_:&str,_:&[u8],_:&CredentialHandle)->Result<String>{let mut f=self.0.lock().unwrap();if !f.held.remove(r)||f.revoked{return Err("denied".into())}f.used.insert(r.into());if f.rotate_on_commit{f.generation+=1;}Ok(format!("admission-{r}"))}
    fn bind_chat_context(&self,reservation:&str,_:&ProviderBinding,_:&str,_:&[u8],_:&CredentialHandle,context:&Json)->Result<()> {
        let mut f=self.0.lock().unwrap();if !f.held.contains(reservation)||f.contexts.insert(format!("admission-{reservation}"),context.clone()).is_some(){return Err("context".into())}Ok(())
    }
    fn exchange_chat(&self,admission:&ProviderAdmission,context:&Json)->Result<ChatResponse>{let mut f=self.0.lock().unwrap();if f.revoked || admission.credential_handle().identity()!=format!("fixture-generation-{}",f.generation) || admission.credential_handle().generation()!=Some(f.generation+1) || f.contexts.get(admission.record_id())!=Some(context) || !f.attempts.insert(admission.record_id().into()){return Err("changed".into())}assert_eq!(context.object()?["workspace"],string("fixture-workspace"));f.sends+=1;f.payloads.push(admission.payload().to_vec());if f.lose{return Err("lost".into())}Ok(ChatResponse{answer:if f.output_secret{"Bearer synthetic-output-canary".into()}else{"离线普通文本响应".into()},input_tokens:16,output_tokens:16,synthetic:true})}
}
fn open(facts:Arc<Mutex<Facts>>)->(PathBuf,AgentServiceController,AgentClientRef) {
    let path=std::env::temp_dir().join(format!("ordinary-chat-new-{}-{}",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
    muyon_core_agent_lab::store::create_dir(&path).unwrap();
    let ports=Arc::new(ServiceHostPorts::new(Arc::new(Owner(facts)),ServiceHostMode::ConfiguredChat,CallBudget{max_tokens:8192,max_micros:1,requires_tools:false,requires_streaming:false}));
    let c=AgentServiceController::new_with_host(AgentHostServiceConfig{protocol:1,private_root:path.to_string_lossy().into(),build_identity:"a".repeat(40)},ports).unwrap();c.await_settled();
    let reply=c.connect(AgentConnectRequest{protocol:1,platform_client_key:"b".repeat(32)});let AgentConnectOutcome::Connected{client_lease,..}=reply.outcome else {panic!("connect")};
    let client=AgentClientRef{protocol:1,expected_service_epoch:reply.meta.service_epoch,client_lease};c.set_visibility(AgentVisibilityRequest{client:client.clone(),observation_generation:1,visible:true});(path,c,client)
}
fn submit(c:&AgentServiceController,client:&AgentClientRef,id:&str,text:&str)->Json {
    c.submit_ordinary_chat(client.clone(),id.into(),"conversation-current".into(),text.into());c.await_settled();parse(c.supplier_read_events(client.clone(),id.into(),0).as_bytes()).unwrap()
}
fn clean(path:PathBuf,c:AgentServiceController){c.retire_service();c.await_settled();drop(c);std::fs::remove_dir_all(path).unwrap();}
#[test]
fn compose_contract_reaches_same_agent_with_frozen_plain_text_and_no_supplier_authority(){
    let f=Arc::new(Mutex::new(Facts::default()));let(path,c,client)=open(f.clone());let reply=submit(&c,&client,"chat1","请概括普通文本");
    assert_eq!(reply.object().unwrap()["terminal"],Json::Bool(true));let events=reply.object().unwrap()["events"].array().unwrap();assert_eq!(events.len(),3,"{}",reply.encode());assert_eq!(events[0].object().unwrap()["payload"].object().unwrap()["text"],string("离线普通文本响应"));assert!(!reply.encode().contains("supplier_projection"));assert!(reply.encode().contains("provider_receipt"));assert!(reply.encode().contains("completed"));
    let run=reply.object().unwrap()["run_id"].string().unwrap();let dir=path.join("native-agent-service-v1").join(run);assert!(dir.join("ordinary-agent-v1.db").is_file());assert!(!dir.join("task.db").exists());assert!(!dir.join("native.db").exists());
    let frozen=parse(&std::fs::read(dir.join("ordinary-send-v1.db")).unwrap()).unwrap();assert_eq!(frozen.object().unwrap()["context"].object().unwrap()["conversation"],string("conversation-current"));assert!(frozen.encode().contains("USER-TEXT-v1"));
    let sent=f.lock().unwrap().payloads[0].clone();assert_eq!(parse(&sent).unwrap().object().unwrap()["model"],string("fixture-chat-model"));assert_eq!(parse(&sent).unwrap().object().unwrap()["messages"].array().unwrap()[0].object().unwrap()["content"],string("请概括普通文本"));assert_eq!(frozen.object().unwrap()["payload"],parse(&sent).unwrap());
    let duplicate=submit(&c,&client,"chat1","请概括普通文本");assert!(duplicate.encode().contains("completed"));assert_eq!(f.lock().unwrap().sends,1);
    f.lock().unwrap().revoked=true;let denied=c.supplier_read_events(client,"chat1".into(),0);assert!(denied.contains("DISCLOSURE_UNAVAILABLE"));assert!(!denied.contains("离线普通文本响应"));clean(path,c);
}
#[test]
fn credentials_and_generation_rotation_never_reach_fake_transport(){
    let f=Arc::new(Mutex::new(Facts::default()));let(path,c,client)=open(f.clone());let reply=submit(&c,&client,"secret1","Bearer synthetic-canary-do-not-send");assert!(!reply.encode().contains("synthetic-canary"));assert!(!reply.encode().contains("completed"));assert_eq!(f.lock().unwrap().sends,0);clean(path,c);
    let f=Arc::new(Mutex::new(Facts{rotate_on_reserve:true,..Facts::default()}));let(path,c,client)=open(f.clone());let reply=submit(&c,&client,"rotate1","hello");assert!(!reply.encode().contains("completed"));assert_eq!(f.lock().unwrap().sends,0);clean(path,c);
}
#[test]
fn lost_response_is_unknown_and_polling_or_duplicate_never_retries(){
    let f=Arc::new(Mutex::new(Facts{lose:true,..Facts::default()}));let(path,c,client)=open(f.clone());let reply=submit(&c,&client,"lost1","hello");assert!(reply.encode().contains("outcome_unknown"));for _ in 0..3 {let _=submit(&c,&client,"lost1","hello");}assert_eq!(f.lock().unwrap().sends,1);clean(path,c);
}

#[test]
fn output_signals_post_commit_rotation_and_quota_preserve_no_retry_boundary(){
    for facts in [Facts{output_secret:true,..Facts::default()},Facts{rotate_on_commit:true,..Facts::default()}] {
        let f=Arc::new(Mutex::new(facts));let(path,c,client)=open(f.clone());let reply=submit(&c,&client,"bounded1","hello");assert!(reply.encode().contains("outcome_unknown"));assert!(!reply.encode().contains("synthetic-output-canary"));let sent=f.lock().unwrap().sends;submit(&c,&client,"bounded1","hello");assert_eq!(f.lock().unwrap().sends,sent);clean(path,c);
    }
    let f=Arc::new(Mutex::new(Facts::default()));let(path,c,client)=open(f.clone());
    let first=submit(&c,&client,"quota1","first ordinary input");
    let second=submit(&c,&client,"quota2","second ordinary input");
    let mut contexts=Vec::new();let mut receipts=Vec::new();
    for (reply,request,text) in [(&first,"quota1","first ordinary input"),(&second,"quota2","second ordinary input")] {
        assert_eq!(reply.object().unwrap()["terminal"],Json::Bool(true));
        let events=reply.object().unwrap()["events"].array().unwrap();assert_eq!(events.len(),3);
        assert_eq!(events[0].object().unwrap()["kind"],string("answer_delta"));
        assert_eq!(events[2].object().unwrap()["payload"].object().unwrap()["state"],string("completed"));
        let run=reply.object().unwrap()["run_id"].string().unwrap();
        let frozen=parse(&std::fs::read(path.join("native-agent-service-v1").join(run).join("ordinary-send-v1.db")).unwrap()).unwrap();
        let context=frozen.object().unwrap()["context"].clone();
        assert_eq!(context.object().unwrap()["conversation"],string("conversation-current"));
        assert_eq!(context.object().unwrap()["input_ref"],string(format!("{run}:{request}")));
        let wire=&frozen.object().unwrap()["payload"];
        let messages=wire.object().unwrap()["messages"].array().unwrap();assert_eq!(messages.len(),1);
        assert_eq!(messages[0].object().unwrap()["content"],string(text));
        contexts.push(context);receipts.push(frozen.object().unwrap()["admission"].clone());
    }
    assert_ne!(first.object().unwrap()["run_id"],second.object().unwrap()["run_id"]);
    assert_eq!(first.object().unwrap()["admitted_service_epoch"],second.object().unwrap()["admitted_service_epoch"]);
    assert_ne!(contexts[0].object().unwrap()["task"],contexts[1].object().unwrap()["task"]);
    assert_ne!(contexts[0].object().unwrap()["attempt"],contexts[1].object().unwrap()["attempt"]);
    assert_ne!(receipts[0],receipts[1]);
    let third=submit(&c,&client,"quota3","third ordinary input");
    let events=third.object().unwrap()["events"].array().unwrap();assert_eq!(events.len(),1);
    assert_eq!(events[0].object().unwrap()["kind"],string("terminal"));
    let terminal=events[0].object().unwrap()["payload"].object().unwrap();
    assert_eq!(terminal["state"],string("failed"));
    assert_eq!(terminal["reason"],string("provider_budget_reservation_failed"));
    let replay=submit(&c,&client,"quota3","third ordinary input");assert_eq!(third,replay);
    for _ in 0..2 {
        let lookup=parse(c.supplier_read_events(client.clone(),"quota3".into(),1).as_bytes()).unwrap();
        assert_eq!(lookup.object().unwrap()["terminal"],Json::Bool(true));
        assert!(lookup.object().unwrap()["events"].array().unwrap().is_empty());
        assert_eq!(lookup.object().unwrap()["next_cursor"],Json::Number("1".into()));
        for key in ["request_id","run_id","admitted_service_epoch"] {assert_eq!(lookup.object().unwrap()[key],third.object().unwrap()[key]);}
    }
    let facts=f.lock().unwrap();assert_eq!(facts.sends,2);assert_eq!(facts.attempts.len(),2);assert_eq!(facts.payloads.len(),2);drop(facts);
    clean(path,c);
}
#[test]
fn changed_frozen_usage_or_profile_evidence_cannot_disclose_completed_answer(){
    for change in ["usage","profile"] {
        let f=Arc::new(Mutex::new(Facts::default()));let(path,c,client)=open(f);let reply=submit(&c,&client,"evidence1","hello");
        let run=reply.object().unwrap()["run_id"].string().unwrap();let file=path.join("native-agent-service-v1").join(run).join("ordinary-send-v1.db");let mut data=parse(&std::fs::read(&file).unwrap()).unwrap();
        if let Json::Object(fields)=&mut data {if change=="usage"{fields.insert("usage".into(),parse(br#"{"input":1,"output":999999,"counting_rule":"synthetic-byte-bound-v1"}"#).unwrap());}else if let Some(Json::Object(provider))=fields.get_mut("provider"){provider.remove("endpoint");}}
        std::fs::write(file,data.encode()).unwrap();let denied=c.supplier_read_events(client,"evidence1".into(),0);assert!(denied.contains("DISCLOSURE_UNAVAILABLE"));assert!(!denied.contains("离线普通文本响应"));clean(path,c);
    }
}
#[test]
fn missing_owner_and_revoked_grant_deny_without_supplier_lookup(){
    let f=Arc::new(Mutex::new(Facts{revoked:true,..Facts::default()}));let(path,c,client)=open(f.clone());let reply=submit(&c,&client,"revoked1","hello");assert!(!reply.encode().contains("completed"));assert_eq!(f.lock().unwrap().sends,0);clean(path,c);
    // New dedicated root only. Constructor without host cannot select a supplier fallback for chat.
    let path=std::env::temp_dir().join(format!("ordinary-unconfigured-{}",std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));muyon_core_agent_lab::store::create_dir(&path).unwrap();
    let c=AgentServiceController::new(AgentHostServiceConfig{protocol:1,private_root:path.to_string_lossy().into(),build_identity:"a".repeat(40)}).unwrap();c.await_settled();let reply=c.connect(AgentConnectRequest{protocol:1,platform_client_key:"c".repeat(32)});let AgentConnectOutcome::Connected{client_lease,..}=reply.outcome else{panic!("connect")};let client=AgentClientRef{protocol:1,expected_service_epoch:reply.meta.service_epoch,client_lease};c.set_visibility(AgentVisibilityRequest{client:client.clone(),observation_generation:1,visible:true});let reply=submit(&c,&client,"missing1","hello");assert!(reply.encode().contains("chat_owner_unconfigured"));assert!(!reply.encode().contains("supplier_projection"));clean(path,c);
}
