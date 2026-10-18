#![cfg(target_os = "linux")]
use muyon_rust_agent_host_lab::{supplier_lab_source::{run_lab_supplier_read,validate_lab_supplier_projection,LAB_SUPPLIER_KEY,LAB_SUPPLIER_REVISION},service_runtime::RunControl};
use muyon_plugin_contract_lab::{object,string};
use std::{path::PathBuf,sync::{Arc,atomic::{AtomicUsize,Ordering}}};
static SERIAL:AtomicUsize=AtomicUsize::new(0);
struct Run(PathBuf);
impl Run {fn new()->Self{let dir=std::env::temp_dir().join(format!("muyon-supplier-lab-source-{}-{}",std::process::id(),SERIAL.fetch_add(1,Ordering::SeqCst)));muyon_core_agent_lab::store::create_dir(&dir).unwrap();Self(dir)}}
impl Drop for Run {fn drop(&mut self){let _=std::fs::remove_dir_all(&self.0);}}
#[test]
fn synthetic_schema12_read_uses_same_run_original_durable_receipt(){
 let run=Run::new();
 let result=run_lab_supplier_read(&run.0,"读取当前供应商名称",LAB_SUPPLIER_KEY,LAB_SUPPLIER_REVISION,Arc::new(RunControl::new())).unwrap();
 assert_eq!(result.projection.object().unwrap()["name"],string("合成供应商甲"));
 assert_eq!(std::fs::read(run.0.join("lab-supplier.siq")).unwrap(),include_bytes!("../../../android-compose-lab/app/src/main/assets/synthetic-supplier-schema12.siq"));
 let durable=std::fs::read_to_string(run.0.join("native.db")).unwrap();
 assert!(durable.contains(&result.receipt_ref.encode()));
 assert!(durable.contains(&result.task_id));assert!(durable.contains(&result.attempt_id));
 assert!(!std::fs::read_dir(&run.0).unwrap().any(|e|e.unwrap().file_type().unwrap().is_dir()));
 validate_lab_supplier_projection(&run.0,LAB_SUPPLIER_KEY,LAB_SUPPLIER_REVISION,&result.projection).unwrap();
 println!("SYNTHETIC_REGISTERED_SUPPLIER_READ projection={} receipt={}",result.projection.encode(),result.receipt_ref.encode());
}
#[test]
fn ui_request_cannot_install_other_scope_or_source(){
 for (key,revision) in [("production-supplier",LAB_SUPPLIER_REVISION),(LAB_SUPPLIER_KEY,"8"),("/tmp/user.siq","7")]{
  let run=Run::new();assert!(run_lab_supplier_read(&run.0,"读取供应商",key,revision,Arc::new(RunControl::new())).is_err());
  assert_eq!(std::fs::read_dir(&run.0).unwrap().count(),0);
 }
}
#[test]
fn cancellation_cannot_publish_or_create_receipt(){
 let run=Run::new();let control=Arc::new(RunControl::new());control.request_cancel();
 assert!(run_lab_supplier_read(&run.0,"读取供应商",LAB_SUPPLIER_KEY,LAB_SUPPLIER_REVISION,control).is_err());
 assert!(!run.0.join("native.db").exists());
}
#[test]
fn replay_revalidates_source_and_exact_projection_without_creating_new_receipt(){
 let run=Run::new();let result=run_lab_supplier_read(&run.0,"读取供应商",LAB_SUPPLIER_KEY,LAB_SUPPLIER_REVISION,Arc::new(RunControl::new())).unwrap();
 let before=std::fs::read(run.0.join("native.db")).unwrap();
 assert!(validate_lab_supplier_projection(&run.0,LAB_SUPPLIER_KEY,LAB_SUPPLIER_REVISION,&object([("name",string("forged"))])).is_err());
 assert_eq!(before,std::fs::read(run.0.join("native.db")).unwrap());
 std::fs::write(run.0.join("lab-supplier.siq"),b"tampered").unwrap();
 assert!(validate_lab_supplier_projection(&run.0,LAB_SUPPLIER_KEY,LAB_SUPPLIER_REVISION,&result.projection).is_err());
 assert!(run_lab_supplier_read(&run.0,"读取供应商",LAB_SUPPLIER_KEY,LAB_SUPPLIER_REVISION,Arc::new(RunControl::new())).is_err());
 assert_eq!(std::fs::read(run.0.join("lab-supplier.siq")).unwrap(),b"tampered");
}
#[test]
fn symlink_synthetic_source_is_refused(){
 let run=Run::new();let other=Run::new();let target=other.0.join("user.siq");std::fs::write(&target,b"user database").unwrap();
 std::os::unix::fs::symlink(&target,run.0.join("lab-supplier.siq")).unwrap();
 assert!(run_lab_supplier_read(&run.0,"读取供应商",LAB_SUPPLIER_KEY,LAB_SUPPLIER_REVISION,Arc::new(RunControl::new())).is_err());
 assert_eq!(std::fs::read(&target).unwrap(),b"user database");
}
