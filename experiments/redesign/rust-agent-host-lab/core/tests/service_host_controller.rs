#![cfg(target_os = "linux")]
use muyon_plugin_contract_lab::{parse, string, Json};
use muyon_rust_agent_host_lab::{service_controller::AgentServiceController, service_host::*, service_provider::{CallBudget, ServiceProviderBridge}, service_types::*, supplier_scope_bridge::{SupplierScopeDecision, SupplierSelection}};
use std::{path::PathBuf, sync::{Arc, Mutex, atomic::{AtomicUsize,Ordering}}};
type Result<T> = std::result::Result<T,String>;
static SERIAL: Mutex<()> = Mutex::new(());
static NEXT: AtomicUsize = AtomicUsize::new(0);
const ID: &str = "11111111-1111-4111-8111-111111111111";
struct Owner { root: PathBuf, current: Mutex<SupplierScopeDecision>, provider_calls: AtomicUsize }
impl ServiceHostOwner for Owner {
 fn current_scope(&self)->Result<ServiceHostScope> { let decision=self.current.lock().unwrap().clone(); Ok(ServiceHostScope { source_identity:decision.source_identity.clone(), namespace:decision.namespace.clone(), managed_root:self.root.clone(), database:self.root.join("source.siq"), decision }) }
 fn provider(&self)->Result<ServiceProviderBridge> { self.provider_calls.fetch_add(1,Ordering::SeqCst); Err("configured_profile_unavailable".into()) }
}
fn fixture()->(PathBuf,Arc<Owner>) {
 let root=std::env::temp_dir().join(format!("service-host-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::SeqCst))); std::fs::create_dir(&root).unwrap();
 let source=root.join("source"); std::fs::create_dir(&source).unwrap();
 std::fs::write(source.join("source.siq"),include_bytes!("../../../android-compose-lab/app/src/main/assets/synthetic-supplier-schema12.siq")).unwrap();
 let owner=Arc::new(Owner { root:source, current:Mutex::new(SupplierScopeDecision { source_identity:"test-host-owner".into(),namespace:"test-host-namespace".into(),allowed:true,available:true,scope_allowed:true,bindings:vec!["host-supplier-name-read".into()], revision:"policy1".into(),binding_revision:"binding1".into(),source_revision:"source1".into(),rule_revision:"rule1".into(),scope:"selected-supplier".into(),selected:vec![SupplierSelection{key:ID.into(),revision:"7".into()}] }),provider_calls:AtomicUsize::new(0) });
 (root,owner)
}
fn open(root:&PathBuf,owner:Arc<Owner>,mode:ServiceHostMode)->(AgentServiceController,AgentClientRef) {
 let private=root.join("service"); if !private.exists(){std::fs::create_dir(&private).unwrap();}
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
 owner.current.lock().unwrap().allowed=false;
 let denied=parse(c.supplier_read_events(client,"host1".into(),0).as_bytes()).unwrap(); assert_eq!(denied.object().unwrap()["reason"],string("DISCLOSURE_UNAVAILABLE")); assert!(denied.object().unwrap()["events"].array().unwrap().is_empty()); stop(c);
 let (c,client)=open(&root,owner.clone(),ServiceHostMode::LocalRead);
 let replay=parse(c.supplier_read_events(client,"host1".into(),0).as_bytes()).unwrap(); assert!(replay.object().unwrap()["events"].array().unwrap().is_empty()); assert_eq!(files_before,std::fs::read_dir(root.join("service")).unwrap().count()); assert_eq!(owner.provider_calls.load(Ordering::SeqCst),0); stop(c);
 // A different currently allowed owner at the same physical DB cannot inherit history.
 { let mut d=owner.current.lock().unwrap(); d.allowed=true;d.source_identity="replacement-owner".into();d.namespace="replacement-namespace".into(); }
 let (c,client)=open(&root,owner.clone(),ServiceHostMode::LocalRead);
 let replaced=parse(c.supplier_read_events(client,"host1".into(),0).as_bytes()).unwrap();assert!(replaced.object().unwrap()["events"].array().unwrap().is_empty());stop(c);std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn configured_session_missing_profile_fails_closed_without_synthetic_read(){
 let _serial=SERIAL.lock().unwrap_or_else(|e|e.into_inner());let(root,owner)=fixture();let(c,client)=open(&root,owner.clone(),ServiceHostMode::ConfiguredChat);
 c.submit_supplier_read(client.clone(),"configured1".into(),"chat".into(),ID.into(),"7".into());c.await_settled();
 let reply=parse(c.supplier_read_events(client,"configured1".into(),0).as_bytes()).unwrap();
 assert_eq!(reply.object().unwrap()["synthetic"],Json::Bool(false)); assert_eq!(owner.provider_calls.load(Ordering::SeqCst),1);
 assert!(reply.encode().contains("configured_profile_unavailable")); assert!(!reply.encode().contains("supplier_projection")); stop(c);std::fs::remove_dir_all(root).unwrap();
}
