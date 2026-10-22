#![cfg(target_os = "linux")]
use muyon_plugin_contract_lab::string;
use muyon_rust_agent_host_lab::{
    supplier_scope_bridge::{HostSupplierScopeBridge, HostSupplierSource, SupplierScopeDecision, SupplierSelection},
    supplier_store::SupplierReader,
    AuthoritySource,
};
use std::{cell::{Cell, RefCell}, path::PathBuf, process::Command, rc::Rc, sync::atomic::{AtomicUsize, Ordering}};

static SERIAL: AtomicUsize = AtomicUsize::new(0);
const ID: &str = "11111111-1111-4111-8111-111111111111";
fn decision() -> SupplierScopeDecision {
    SupplierScopeDecision {
        source_identity: "host-user-store-owner1".into(), namespace: "user-store:inquiry1".into(),
        allowed: true, available: true, scope_allowed: true,
        bindings: vec!["host-supplier-name-read".into()], revision: "authority1".into(),
        binding_revision: "binding1".into(), source_revision: "source1".into(), rule_revision: "rule1".into(),
        scope: "selected-supplier".into(), selected: vec![SupplierSelection { key: ID.into(), revision: "7".into() }],
    }
}
struct Fixture { root: PathBuf, db: PathBuf }
impl Fixture {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!("muyon-scope-{}-{}", std::process::id(), SERIAL.fetch_add(1, Ordering::SeqCst)));
        std::fs::create_dir(&root).unwrap();
        let db = root.join("inquiry.siq");
        let output = Command::new("python3").arg("-c").arg(r#"
import sqlite3,sys,json
c=sqlite3.connect(sys.argv[1])
c.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)')
c.executemany('INSERT INTO meta VALUES (?,?)',[('format','supplier-inquiry'),('schema_version','12')])
c.execute('CREATE TABLE supplier(id TEXT PRIMARY KEY, version INTEGER NOT NULL, updated_at TEXT NOT NULL, updated_by TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, data TEXT NOT NULL)')
d={k:None for k in ['name','aliases','address','categories','notes','merged_into','rating','rating_note']};d['name']='synthetic supplier';d['notes']='PRIVATE'
c.execute('INSERT INTO supplier VALUES (?,7,?,?,0,?)',('11111111-1111-4111-8111-111111111111','2026-10-18','synthetic',json.dumps(d)));c.commit()
"#).arg(&db).output().unwrap();
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        Self { root, db }
    }
    fn bridge(&self, value: Rc<RefCell<SupplierScopeDecision>>) -> Result<Rc<HostSupplierScopeBridge>, String> {
        let source = HostSupplierSource::new("host-user-store-owner1", "user-store:inquiry1", &self.root, &self.db)?;
        Ok(Rc::new(HostSupplierScopeBridge::new(source, Rc::new(move || Ok(value.borrow().clone())))?))
    }
}
impl Drop for Fixture { fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.root); } }

#[test]
fn trusted_typed_resolver_installs_registered_read_without_grant_or_path_from_request() {
    let f = Fixture::new();
    let bridge = f.bridge(Rc::new(RefCell::new(decision()))).unwrap();
    let before = std::fs::read(&f.db).unwrap();
    let snapshot = bridge.snapshot().unwrap();
    assert!(!snapshot.model_allowed);
    assert_eq!(snapshot.read.object().unwrap()["refs"].array().unwrap().len(), 1);
    let reader = SupplierReader::install_host_scope(&f.root.join("receipts"), ID, bridge).unwrap();
    let read = reader.read_current(ID).unwrap();
    assert_eq!(read.projection.object().unwrap()["name"], string("synthetic supplier"));
    reader.validate_current_projection(&read.projection).unwrap();
    assert!(!read.projection.encode().contains("PRIVATE"));
    assert_eq!(before, std::fs::read(&f.db).unwrap());
    assert!(reader.read_current("/tmp/other.siq").is_err());
}

#[test]
fn each_missing_or_denied_scope_proof_fails_closed() {
    let f = Fixture::new();
    for change in 0..15 {
        let mut d = decision();
        match change {
            0 => d.allowed = false, 1 => d.available = false, 2 => d.scope_allowed = false,
            3 => d.bindings.clear(), 4 => d.revision.clear(), 5 => d.binding_revision.clear(),
            6 => d.source_revision.clear(), 7 => d.rule_revision.clear(), 8 => d.scope.clear(),
            9 => d.selected.clear(), 10 => d.selected.push(d.selected[0].clone()),
            11 => d.selected[0].revision.clear(), 12 => d.source_identity = "other-owner".into(),
            13 => d.namespace = "other-namespace".into(), 14 => d.selected[0].key.clear(), _ => unreachable!(),
        }
        assert!(f.bridge(Rc::new(RefCell::new(d))).and_then(|b| b.snapshot()).is_err(), "accepted case {change}");
    }
}

#[test]
fn revoked_current_authority_blocks_new_read_and_redisclosure() {
    let f = Fixture::new();
    let current = Rc::new(RefCell::new(decision()));
    let reader = SupplierReader::install_host_scope(&f.root.join("receipts"), ID, f.bridge(current.clone()).unwrap()).unwrap();
    let read = reader.read_current(ID).unwrap();
    current.borrow_mut().allowed = false;
    assert!(reader.read_current(ID).is_err());
    assert!(reader.validate_current_projection(&read.projection).is_err());
}

#[test]
fn source_owner_namespace_revision_and_selection_changes_are_current_evidence() {
    let f = Fixture::new();
    let current = Rc::new(RefCell::new(decision()));
    let bridge = f.bridge(current.clone()).unwrap();
    let original = bridge.snapshot().unwrap();
    current.borrow_mut().rule_revision = "rule2".into();
    assert_ne!(original, bridge.snapshot().unwrap());
    current.borrow_mut().selected[0].revision = "8".into();
    assert!(SupplierReader::install_host_scope(&f.root.join("receipts"), ID, bridge.clone()).is_err());
    current.borrow_mut().namespace = "changed-owner-namespace".into();
    assert!(bridge.snapshot().is_err());
}

#[test]
fn unsupported_or_ambiguous_host_source_path_is_denied() {
    let f = Fixture::new();
    for (identity, namespace, root, db) in [
        ("", "ns", f.root.clone(), f.db.clone()),
        ("owner", "", f.root.clone(), f.db.clone()),
        ("owner", "ns", PathBuf::from("relative"), f.db.clone()),
        ("owner", "ns", f.root.join("unrelated"), f.db.clone()),
        ("owner", "ns", f.root.clone(), f.root.join("../inquiry.siq")),
    ] { assert!(HostSupplierSource::new(identity, namespace, &root, &db).is_err()); }
    let link = f.root.join("alias");
    std::os::unix::fs::symlink(&f.db, &link).unwrap();
    let source = HostSupplierSource::new("host-user-store-owner1", "user-store:inquiry1", &f.root, &link);
    assert!(source.and_then(|s| HostSupplierScopeBridge::new(s, Rc::new(|| Ok(decision()))))
        .and_then(|b| SupplierReader::install_host_scope(&f.root.join("receipts"), ID, Rc::new(b))).is_err());
}

#[test]
fn missing_current_resolver_never_falls_back_to_a_cached_grant() {
    let f = Fixture::new();
    let source = HostSupplierSource::new("host-user-store-owner1", "user-store:inquiry1", &f.root, &f.db).unwrap();
    assert!(HostSupplierScopeBridge::new(source, Rc::new(|| Err("scope_owner_unavailable".into()))).is_err());
}

#[test]
fn owner_revocation_during_final_sample_prevents_installation() {
    let f = Fixture::new();
    let calls = Rc::new(Cell::new(0));
    let revoke_at = Rc::new(Cell::new(usize::MAX));
    let source = HostSupplierSource::new("host-user-store-owner1", "user-store:inquiry1", &f.root, &f.db).unwrap();
    let callback_calls = calls.clone();
    let callback_revoke = revoke_at.clone();
    let bridge = Rc::new(HostSupplierScopeBridge::new(source, Rc::new(move || {
        let call = callback_calls.get() + 1;
        callback_calls.set(call);
        let mut current = decision();
        current.allowed = call < callback_revoke.get();
        Ok(current)
    })).unwrap());
    revoke_at.set(calls.get() + 2);
    assert!(SupplierReader::install_host_scope(&f.root.join("receipts"), ID, bridge).is_err());
    assert!(!f.root.join("receipts").exists());
}
