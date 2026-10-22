#![cfg(target_os = "linux")]
use muyon_plugin_contract_lab::{parse, string, Json};
use muyon_rust_agent_host_lab::{service_controller::AgentServiceController, service_host::*, service_provider::*, service_types::*, supplier_scope_bridge::{SupplierScopeDecision, SupplierSelection}};
use std::{path::PathBuf, sync::{Arc, Mutex, atomic::{AtomicBool,AtomicUsize,Ordering}}};
type Result<T> = std::result::Result<T,String>;
static SERIAL: Mutex<()> = Mutex::new(());
static NEXT: AtomicUsize = AtomicUsize::new(0);
const ID: &str = "11111111-1111-4111-8111-111111111111";
struct Owner { root: PathBuf, current: Mutex<SupplierScopeDecision>, provider_calls: AtomicUsize, configured_available: AtomicBool, scope_calls: AtomicUsize, handle_calls: Arc<AtomicUsize>, mutations: Arc<AtomicUsize> }
impl ServiceHostOwner for Owner {
 fn current_scope(&self)->Result<ServiceHostScope> { self.scope_calls.fetch_add(1,Ordering::SeqCst); let decision=self.current.lock().unwrap().clone(); Ok(ServiceHostScope { source_identity:decision.source_identity.clone(), namespace:decision.namespace.clone(), managed_root:self.root.clone(), database:self.root.join("source.siq"), decision }) }
 fn provider(&self)->Result<ServiceProviderBridge> { self.provider_calls.fetch_add(1,Ordering::SeqCst);
  if self.configured_available.load(Ordering::SeqCst) { Ok(ServiceProviderBridge::new(std::rc::Rc::new(ConfiguredOwner { handle_calls:self.handle_calls.clone(),mutations:self.mutations.clone() }))) }
  else { Err("configured_profile_unavailable".into()) } }
}
fn fixture()->(PathBuf,Arc<Owner>) {
 let root=std::env::temp_dir().join(format!("service-host-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::SeqCst))); muyon_core_agent_lab::store::create_dir(&root).unwrap();
 let source=root.join("source"); muyon_core_agent_lab::store::create_dir(&source).unwrap();
 std::fs::write(source.join("source.siq"),include_bytes!("../../../android-compose-lab/app/src/main/assets/synthetic-supplier-schema12.siq")).unwrap();
 let owner=Arc::new(Owner { root:source, current:Mutex::new(SupplierScopeDecision { source_identity:"test-host-owner".into(),namespace:"test-host-namespace".into(),allowed:true,available:true,scope_allowed:true,bindings:vec!["host-supplier-name-read".into()], revision:"policy1".into(),binding_revision:"binding1".into(),source_revision:"source1".into(),rule_revision:"rule1".into(),scope:"selected-supplier".into(),selected:vec![SupplierSelection{key:ID.into(),revision:"7".into()}] }),provider_calls:AtomicUsize::new(0),configured_available:AtomicBool::new(false),scope_calls:AtomicUsize::new(0),handle_calls:Arc::new(AtomicUsize::new(0)),mutations:Arc::new(AtomicUsize::new(0)) });
 (root,owner)
}
fn open(root:&PathBuf,owner:Arc<Owner>,mode:ServiceHostMode)->(AgentServiceController,AgentClientRef) {
 let private=root.join("service"); if !private.exists(){muyon_core_agent_lab::store::create_dir(&private).unwrap();}
 let ports=Arc::new(ServiceHostPorts::new(owner,mode,CallBudget{max_tokens:100,max_micros:10,requires_tools:true,requires_streaming:false}));
 let c=AgentServiceController::new_with_host(AgentHostServiceConfig{protocol:1,private_root:private.to_string_lossy().into(),build_identity:"a".repeat(40)},ports).unwrap(); c.await_settled();
 let r=c.connect(AgentConnectRequest{protocol:1,platform_client_key:"b".repeat(32)}); let AgentConnectOutcome::Connected{client_lease,..}=r.outcome else {panic!("connect")};
 let client=AgentClientRef{protocol:1,expected_service_epoch:r.meta.service_epoch,client_lease}; c.set_visibility(AgentVisibilityRequest{client:client.clone(),observation_generation:1,visible:true}); (c,client)
}
fn stop(c:AgentServiceController){c.retire_service();c.await_settled();}
#[test]
fn host_read_uses_same_controller_and_rechecks_revocation_on_redisclosure_and_restart(){
 let _serial=SERIAL.lock().unwrap_or_else(|e|e.into_inner()); let (root,owner)=fixture();
 let (c,client)=open(&root,owner.clone(),ServiceHostMode::LocalRead);
 let admitted=parse(c.submit_supplier_read(client.clone(),"host1".into(),"read supplier".into(),ID.into(),"7".into()).as_bytes()).unwrap(); assert_eq!(admitted.object().unwrap()["synthetic"],Json::Bool(false));
 c.await_settled(); let reply=parse(c.supplier_read_events(client.clone(),"host1".into(),0).as_bytes()).unwrap();
 assert_eq!(reply.object().unwrap()["synthetic"],Json::Bool(false)); assert_eq!(reply.object().unwrap()["events"].array().unwrap().len(),4);
 assert!(!reply.encode().contains("合成供应商："));
 let files_before=std::fs::read_dir(root.join("service")).unwrap().count();
 let run_id=reply.object().unwrap()["run_id"].string().unwrap();
 let receipt_path=root.join("service").join("native-agent-service-v1").join(run_id).join("native.db");
 let original_receipt=std::fs::read(&receipt_path).unwrap();
 owner.current.lock().unwrap().allowed=false;
 let denied=parse(c.supplier_read_events(client,"host1".into(),0).as_bytes()).unwrap(); assert_eq!(denied.object().unwrap()["reason"],string("DISCLOSURE_UNAVAILABLE")); assert!(denied.object().unwrap()["events"].array().unwrap().is_empty()); stop(c);
 let (c,client)=open(&root,owner.clone(),ServiceHostMode::LocalRead);
 let replay=parse(c.supplier_read_events(client,"host1".into(),0).as_bytes()).unwrap(); assert!(replay.object().unwrap()["events"].array().unwrap().is_empty()); assert_eq!(files_before,std::fs::read_dir(root.join("service")).unwrap().count());assert_eq!(original_receipt,std::fs::read(&receipt_path).unwrap()); assert_eq!(owner.provider_calls.load(Ordering::SeqCst),0); stop(c);
 // A different currently allowed owner at the same physical DB cannot inherit history.
 { let mut d=owner.current.lock().unwrap(); d.allowed=true;d.source_identity="replacement-owner".into();d.namespace="replacement-namespace".into(); }
 let (c,client)=open(&root,owner.clone(),ServiceHostMode::LocalRead);
 let replaced=parse(c.supplier_read_events(client,"host1".into(),0).as_bytes()).unwrap();assert!(replaced.object().unwrap()["events"].array().unwrap().is_empty());assert_eq!(original_receipt,std::fs::read(&receipt_path).unwrap());stop(c);std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn configured_session_missing_profile_fails_closed_without_synthetic_read(){
 let _serial=SERIAL.lock().unwrap_or_else(|e|e.into_inner());let(root,owner)=fixture();let(c,client)=open(&root,owner.clone(),ServiceHostMode::ConfiguredChat);
 c.submit_supplier_read(client.clone(),"configured1".into(),"chat".into(),ID.into(),"7".into());c.await_settled();
 let reply=parse(c.supplier_read_events(client,"configured1".into(),0).as_bytes()).unwrap();
 assert_eq!(reply.object().unwrap()["synthetic"],Json::Bool(false)); assert_eq!(owner.provider_calls.load(Ordering::SeqCst),1);
 assert!(reply.encode().contains("configured_profile_unavailable")); assert!(!reply.encode().contains("supplier_projection")); stop(c);std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn atomic_database_replacement_cannot_inherit_retained_projection_or_receipt_after_restart() {
    use std::os::unix::fs::MetadataExt;
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let (root, owner) = fixture();
    let (c, client) = open(&root, owner.clone(), ServiceHostMode::LocalRead);
    c.submit_supplier_read(client.clone(), "lineage1".into(), "read supplier".into(), ID.into(), "7".into());
    c.await_settled();
    let before = parse(c.supplier_read_events(client.clone(), "lineage1".into(), 0).as_bytes()).unwrap();
    assert_eq!(before.object().unwrap()["events"].array().unwrap().len(), 4);
    let receipt_path = root.join("service").join("native-agent-service-v1").join(before.object().unwrap()["run_id"].string().unwrap()).join("native.db");
    let receipt = std::fs::read(&receipt_path).unwrap();
    let database = owner.root.join("source.siq");
    let replacement = owner.root.join("replacement.siq");
    std::fs::copy(&database, &replacement).unwrap();
    assert_ne!(std::fs::metadata(&database).unwrap().ino(), std::fs::metadata(&replacement).unwrap().ino());
    // Exact same bytes, schema, key, revision and name; the trusted logical owner
    // and every authority stamp remain unchanged. Only physical lineage changes.
    std::fs::rename(&replacement, &database).unwrap();
    let retained = parse(c.supplier_read_events(client, "lineage1".into(), 0).as_bytes()).unwrap();
    let receipt_after_publication = std::fs::read(&receipt_path).unwrap();
    stop(c);
    let (c, client) = open(&root, owner.clone(), ServiceHostMode::LocalRead);
    let restarted = parse(c.supplier_read_events(client, "lineage1".into(), 0).as_bytes()).unwrap();
    let receipt_after_restart = std::fs::read(&receipt_path).unwrap();
    stop(c);
    std::fs::remove_dir_all(root).unwrap();
    assert!(retained.object().unwrap()["events"].array().unwrap().is_empty(), "a replacement database inherited cached projection disclosure");
    assert_eq!(retained.object().unwrap()["reason"], string("DISCLOSURE_UNAVAILABLE"));
    assert!(restarted.object().unwrap()["events"].array().unwrap().is_empty(), "restart accepted replacement database as the historical source");
    assert_eq!(receipt, receipt_after_publication);
    assert_eq!(receipt, receipt_after_restart);
}

#[test]
fn replacement_managed_root_with_same_database_inode_cannot_inherit_history() {
    use std::os::unix::fs::MetadataExt;
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let (root, owner) = fixture();
    let (c, client) = open(&root, owner.clone(), ServiceHostMode::LocalRead);
    c.submit_supplier_read(client.clone(), "lineage2".into(), "read supplier".into(), ID.into(), "7".into());
    c.await_settled();
    let before = parse(c.supplier_read_events(client.clone(), "lineage2".into(), 0).as_bytes()).unwrap();
    assert_eq!(before.object().unwrap()["events"].array().unwrap().len(), 4);
    let receipt_path = root.join("service").join("native-agent-service-v1").join(before.object().unwrap()["run_id"].string().unwrap()).join("native.db");
    let receipt = std::fs::read(&receipt_path).unwrap();
    let previous_root = root.join("previous-source");
    std::fs::rename(&owner.root, &previous_root).unwrap();
    muyon_core_agent_lab::store::create_dir(&owner.root).unwrap();
    std::fs::hard_link(previous_root.join("source.siq"), owner.root.join("source.siq")).unwrap();
    assert_eq!(std::fs::metadata(previous_root.join("source.siq")).unwrap().ino(), std::fs::metadata(owner.root.join("source.siq")).unwrap().ino());
    let retained = parse(c.supplier_read_events(client, "lineage2".into(), 0).as_bytes()).unwrap();
    stop(c);
    let (c, client) = open(&root, owner.clone(), ServiceHostMode::LocalRead);
    let restarted = parse(c.supplier_read_events(client, "lineage2".into(), 0).as_bytes()).unwrap();
    let receipt_after_restart = std::fs::read(&receipt_path).unwrap();
    stop(c);
    std::fs::remove_dir_all(root).unwrap();
    assert!(retained.object().unwrap()["events"].array().unwrap().is_empty(), "replacement root inherited cached source lineage");
    assert!(restarted.object().unwrap()["events"].array().unwrap().is_empty());
    assert_eq!(receipt, receipt_after_restart);
}


// In-memory trusted owner metadata only. No network, secret value, or ledger write.
struct ConfiguredOwner { handle_calls: Arc<AtomicUsize>, mutations: Arc<AtomicUsize> }
impl ServiceProviderHost for ConfiguredOwner {
    fn current_binding(&self) -> Result<Option<ProviderBinding>> { Ok(Some(ProviderBinding {
        profile: ConfiguredProfile { id:"fixture-profile".into(),endpoint:"https://provider.invalid/v1/chat/completions".into(),endpoint_identity:"fixture-endpoint".into(),provider:"openai-compatible".into(),model:"fixture-model".into(),location:ModelLocation::Remote,purpose:ModelPurpose::Chat,credential_ref:"fixture-handle-ref".into(),declared:Capabilities {tool_calls:true,streaming:false},tested:Capabilities {tool_calls:true,streaming:false} },
        profile_revision:"fixture-profile1".into(),policy_revision:"fixture-policy1".into(),grant_revision:"fixture-grant1".into(),authorization_owner:"fixture-authorizer".into(),model_allowed:true,outbound_allowed:true,
        budget:ProviderBudget {revision:"fixture-budget1".into(),quota_proof:"fixture-quota1".into(),remaining_calls:1,remaining_tokens:200,remaining_micros:100},
    })) }
    fn credential_handle(&self,p:&ConfiguredProfile)->Result<Option<CredentialHandle>> {
        self.handle_calls.fetch_add(1,Ordering::SeqCst);
        Ok(Some(CredentialHandle::new(&p.id,&p.credential_ref,"fixture-opaque-handle")?))
    }
    fn review_payload(&self,_:&ProviderBinding,_:&[u8])->Result<()> {self.mutations.fetch_add(1,Ordering::SeqCst);Err("unexpected_prepare".into())}
    fn reserve_budget(&self,_:&ProviderBinding,_:&str,_:&[u8],_:&CallBudget)->Result<String> {self.mutations.fetch_add(1,Ordering::SeqCst);Err("unexpected_reservation".into())}
    fn commit_admission(&self,_:&str,_:&ProviderBinding,_:&str,_:&[u8],_:&CredentialHandle)->Result<String> {self.mutations.fetch_add(1,Ordering::SeqCst);Err("unexpected_commit".into())}
}
#[test]
fn valid_configured_readiness_still_blocks_transport_without_scope_or_admission() {
    let _serial=SERIAL.lock().unwrap_or_else(|e|e.into_inner());
    let(root,owner)=fixture();owner.configured_available.store(true,Ordering::SeqCst);
    // A model profile does not grant source reads. This owner denies every read.
    owner.current.lock().unwrap().allowed=false;
    let(c,client)=open(&root,owner.clone(),ServiceHostMode::ConfiguredChat);
    c.submit_supplier_read(client.clone(),"configured-valid".into(),"chat".into(),ID.into(),"7".into());c.await_settled();
    let reply=parse(c.supplier_read_events(client,"configured-valid".into(),0).as_bytes()).unwrap();
    stop(c);std::fs::remove_dir_all(root).unwrap();
    assert!(reply.encode().contains("configured_transport_unavailable"),"valid profile/HANDLE must reach explicit transport gate");
    assert_eq!(reply.object().unwrap()["synthetic"],Json::Bool(false));
    assert_eq!(owner.provider_calls.load(Ordering::SeqCst),1);
    assert!(owner.handle_calls.load(Ordering::SeqCst)>0,"readiness must check HANDLE availability");
    assert_eq!(owner.mutations.load(Ordering::SeqCst),0,"no payload preparation, quota reservation, or outbound commit");
    assert_eq!(owner.scope_calls.load(Ordering::SeqCst),0,"configured readiness must not infer or consume a read grant");
    assert!(!reply.encode().contains("supplier_projection"));assert!(!reply.encode().contains("receipt"));
}
