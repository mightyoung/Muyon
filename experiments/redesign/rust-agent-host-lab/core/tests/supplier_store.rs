#![cfg(target_os = "linux")]
use muyon_plugin_contract_lab::{object, parse, string, Json};
use muyon_rust_agent_host_lab::{
    supplier_store::SupplierReader, AuthoritySnapshot, AuthoritySource,
};
use std::{
    cell::{Cell, RefCell},
    path::PathBuf,
    process::Command,
    rc::Rc,
    sync::atomic::{AtomicUsize, Ordering},
};
static SERIAL: AtomicUsize = AtomicUsize::new(0);
const ID: &str = "11111111-1111-4111-8111-111111111111";
struct Host {
    value: RefCell<AuthoritySnapshot>,
    calls: Cell<usize>,
    revoke_at: Cell<usize>,
    mutation: RefCell<Option<(usize, PathBuf)>>,
}
impl AuthoritySource for Host {
    fn snapshot(&self) -> Result<AuthoritySnapshot, String> {
        let n = self.calls.get() + 1;
        self.calls.set(n);
        let mutate = self
            .mutation
            .borrow()
            .as_ref()
            .filter(|(at, _)| *at == n)
            .map(|(_, path)| path.clone());
        if let Some(path) = mutate {
            assert!(Command::new("python3").arg("-c").arg("import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute(\"UPDATE supplier SET data=json_set(data,'$.name','changed mid-read')\"); c.commit()").arg(path).status().unwrap().success());
        }
        if self.revoke_at.get() != 0 && n >= self.revoke_at.get() {
            return Err("host_authority_pending".into());
        }
        Ok(self.value.borrow().clone())
    }
}
fn host() -> Rc<Host> {
    Rc::new(Host { value: RefCell::new(AuthoritySnapshot { read: parse(format!(r#"{{"allowed":true,"available":true,"scope_allowed":true,"bindings":["host-supplier-name-read"],"revision":"host-owner:epoch1","binding_revision":"binding1","source_revision":"source-owner1","rule_revision":"rule1","scope":"selected-supplier","refs":[{{"module_id":"inquiry","type":"supplier","key":"{ID}","revision":"7","schema_version":1}}]}}"#).as_bytes()).unwrap(), model_allowed:false, profile:"local-read-only".into() }), calls:Cell::new(0), revoke_at:Cell::new(0), mutation:RefCell::new(None) })
}
struct Fixture {
    root: PathBuf,
    db: PathBuf,
}
impl Fixture {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!(
            "muyon-supplier-{}-{}",
            std::process::id(),
            SERIAL.fetch_add(1, Ordering::SeqCst)
        ));
        std::fs::create_dir(&root).unwrap();
        let db = root.join("inquiry.siq");
        let fixture = Self { root, db };
        fixture.python(r#"
import json, sqlite3
c=sqlite3.connect(path)
c.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)')
c.execute('CREATE TABLE supplier(id TEXT PRIMARY KEY, version INTEGER NOT NULL, updated_at TEXT NOT NULL, updated_by TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, data TEXT NOT NULL)')
c.executemany('INSERT INTO meta VALUES (?,?)',[('format','supplier-inquiry'),('schema_version','12')])
payload={'name':'合成供应商甲','aliases':None,'address':None,'categories':None,'notes':'DO_NOT_PROJECT_PRIVATE_NOTE','merged_into':None,'rating':None,'rating_note':None}
c.execute('INSERT INTO supplier VALUES (?,?,?,?,?,?)',('11111111-1111-4111-8111-111111111111',7,'2026-10-18T00:00:00Z','synthetic-device',0,json.dumps(payload,ensure_ascii=False)))
c.commit()
"#);
        fixture
    }
    fn python(&self, body: &str) {
        let code = format!("import sys\npath=sys.argv[1]\n{body}");
        let out = Command::new("python3")
            .arg("-c")
            .arg(code)
            .arg(&self.db)
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
    }
    fn update(&self, sql: &str) {
        let code="import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute(sys.argv[2]); c.commit()";
        assert!(Command::new("python3")
            .arg("-c")
            .arg(code)
            .arg(&self.db)
            .arg(sql)
            .status()
            .unwrap()
            .success());
    }
    fn reader(&self, h: Rc<Host>) -> Result<SupplierReader, String> {
        SupplierReader::install(&self.db, &self.root.join("receipts"), ID, h)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}
#[test]
fn registered_read_yields_business_name_and_original_durable_receipt_without_business_write() {
    let f = Fixture::new();
    let before = std::fs::read(&f.db).unwrap();
    let reader = f.reader(host()).unwrap();
    let result = reader.read_current(ID).unwrap();
    assert_eq!(result.projection.object().unwrap().len(), 2);
    assert_eq!(
        result.projection.object().unwrap()["name"],
        string("合成供应商甲")
    );
    assert!(!result.projection.encode().contains("PRIVATE_NOTE"));
    let entries: Vec<_> = std::fs::read_dir(f.root.join("receipts"))
        .unwrap()
        .map(|x| x.unwrap().path())
        .collect();
    assert_eq!(entries.len(), 1);
    let db = std::fs::read_to_string(entries[0].join("native.db")).unwrap();
    assert!(db.contains("host-supplier-name-read"));
    assert!(
        db.contains(&result.receipt_ref.encode()),
        "original receipt identity must be in durable store"
    );
    assert!(db.contains("合成供应商甲"));
    assert_eq!(before, std::fs::read(&f.db).unwrap());
    println!(
        "BUSINESS_READ_EVIDENCE {}",
        object([
            ("projection", result.projection),
            ("receipt_ref", result.receipt_ref)
        ])
        .encode()
    );
}
#[test]
fn identity_and_request_shape_are_not_sql_or_path_authority() {
    let f = Fixture::new();
    let reader = f.reader(host()).unwrap();
    for id in ["other", "' OR 1=1 --", "/tmp/inquiry.siq"] {
        assert!(reader.read_current(id).is_err());
    }
}
#[test]
fn unknown_schema_missing_deleted_malformed_and_oversized_sources_fail_closed() {
    for sql in [
        "UPDATE meta SET value='13' WHERE key='schema_version'",
        "UPDATE meta SET value='other' WHERE key='format'",
        "DELETE FROM supplier",
        "UPDATE supplier SET deleted=1",
        "UPDATE supplier SET data='not json'",
        "UPDATE supplier SET data='[]'",
        "UPDATE supplier SET data=json_object('name',printf('%070000d',0))",
        "ALTER TABLE supplier RENAME TO unsupported",
    ] {
        let f = Fixture::new();
        f.update(sql);
        let outcome = f.reader(host()).and_then(|r| r.read_current(ID));
        assert!(outcome.is_err(), "accepted {sql}");
    }
}
#[test]
fn current_reads_reject_pinned_revision_drift_and_pending_or_revoked_authority() {
    let f = Fixture::new();
    let h = host();
    let reader = f.reader(h.clone()).unwrap();
    f.update("UPDATE supplier SET version=8");
    assert!(reader.read_current(ID).is_err());
    f.update("UPDATE supplier SET version=7");
    set_source(&h, "source-owner1:epoch2");
    h.revoke_at.set(h.calls.get() + 1);
    assert!(reader.read_current(ID).is_err());
    h.revoke_at.set(0);
    if let Json::Object(m) = &mut h.value.borrow_mut().read {
        m.insert("allowed".into(), Json::Bool(false));
    }
    assert!(reader.read_current(ID).is_err());
}
#[test]
fn current_projection_rereads_name_while_historical_receipt_identity_stays_original() {
    let f = Fixture::new();
    let h = host();
    let reader = f.reader(h.clone()).unwrap();
    let old = reader.read_current(ID).unwrap();
    let identity = old.receipt_ref.clone();
    f.update("UPDATE supplier SET version=8,data=json_set(data,'$.name','合成供应商乙')");
    if let Json::Object(m) = &mut h.value.borrow_mut().read {
        if let Json::Array(refs) = m.get_mut("refs").unwrap() {
            if let Json::Object(reference) = &mut refs[0] {
                reference.insert("revision".into(), string("8"));
            }
        }
    }
    set_source(&h, "source-owner1:epoch2");
    let new = reader.read_current(ID).unwrap();
    assert_eq!(
        old.projection.object().unwrap()["name"],
        string("合成供应商甲")
    );
    assert_eq!(
        new.projection.object().unwrap()["name"],
        string("合成供应商乙")
    );
    assert_eq!(old.receipt_ref, identity);
    assert_ne!(new.receipt_ref, identity);
}
#[test]
fn replaced_file_symlinks_owner_mode_and_no_create_fail_closed() {
    let f = Fixture::new();
    let reader = f.reader(host()).unwrap();
    std::fs::rename(&f.db, f.root.join("old.siq")).unwrap();
    std::fs::copy(f.root.join("old.siq"), &f.db).unwrap();
    assert!(reader.read_current(ID).is_err());
    let missing = f.root.join("missing.siq");
    assert!(SupplierReader::install(&missing, &f.root.join("new-receipts"), ID, host()).is_err());
    assert!(!missing.exists());
    let link = f.root.join("link.siq");
    std::os::unix::fs::symlink(&f.db, &link).unwrap();
    assert!(SupplierReader::install(&link, &f.root.join("new-receipts"), ID, host()).is_err());
}
#[test]
fn authority_unavailable_during_registered_dispatch_revokes_publication() {
    let f = Fixture::new();
    let h = host();
    let reader = f.reader(h.clone()).unwrap();
    h.revoke_at.set(h.calls.get() + 7);
    assert!(reader.read_current(ID).is_err());
}

fn set_source(h: &Host, source: &str) {
    if let Json::Object(m) = &mut h.value.borrow_mut().read {
        m.insert("source_revision".into(), string(source));
    }
}
#[test]
fn same_revision_tamper_without_host_source_stamp_change_is_denied() {
    let f = Fixture::new();
    let reader = f.reader(host()).unwrap();
    reader.read_current(ID).unwrap();
    f.update("UPDATE supplier SET data=json_set(data,'$.name','tampered')");
    assert!(reader.read_current(ID).is_err());
}
#[test]
fn mode_change_and_symlink_ancestor_are_denied() {
    use std::os::unix::fs::PermissionsExt;
    let f = Fixture::new();
    let reader = f.reader(host()).unwrap();
    std::fs::set_permissions(&f.db, std::fs::Permissions::from_mode(0o400)).unwrap();
    assert!(reader.read_current(ID).is_err());
    let parent = f.root.join("alias");
    std::os::unix::fs::symlink(&f.root, &parent).unwrap();
    assert!(SupplierReader::install(
        &parent.join("inquiry.siq"),
        &f.root.join("other-receipts"),
        ID,
        host()
    )
    .is_err());
}

#[test]
fn actual_source_mutation_in_each_final_host_sample_denies_publication() {
    // Two host samples per current() call: include handler, post-read and
    // final facade publication samples. No production-only test hook exists.
    for offset in [2, 4, 6, 8, 10, 12, 14, 16, 18] {
        let f = Fixture::new();
        let h = host();
        let reader = f.reader(h.clone()).unwrap();
        *h.mutation.borrow_mut() = Some((h.calls.get() + offset, f.db.clone()));
        assert!(
            reader.read_current(ID).is_err(),
            "published after source mutation at sample {offset}"
        );
    }
}
#[test]
fn meta_shape_and_storage_types_are_checked() {
    for sql in [
        "UPDATE meta SET value=CAST(value AS BLOB) WHERE key='format'",
        "ALTER TABLE meta ADD COLUMN extra TEXT",
        "UPDATE supplier SET version=1.5",
        "UPDATE supplier SET deleted=0.5",
        "UPDATE supplier SET data=json_set(data,'$.name',NULL)",
        "UPDATE supplier SET data=json_set(data,'$.name',printf('%03000d',0))",
    ] {
        let f = Fixture::new();
        f.update(sql);
        assert!(
            f.reader(host()).and_then(|r| r.read_current(ID)).is_err(),
            "accepted {sql}"
        );
    }
}

#[test]
fn fixture_domain_contract_is_tied_to_actual_dart_schema_source() {
    let store = include_str!("../../../../../packages/supplier_core/lib/src/store.dart");
    assert!(store.contains("const schemaVersion = 12;"));
    assert!(store.contains("const fileFormat = 'supplier-inquiry';"));
    assert!(store
        .contains("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)"));
    assert!(store.contains("CREATE TABLE IF NOT EXISTS $type(id TEXT PRIMARY KEY, "));
    assert!(store.contains("version INTEGER NOT NULL, updated_at TEXT NOT NULL, "));
    assert!(store.contains("updated_by TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, "));
    assert!(store.contains("data TEXT NOT NULL)"));
    let entities = include_str!("../../../../../packages/supplier_core/lib/src/entities.dart");
    let supplier = entities
        .split("final class Supplier")
        .nth(1)
        .unwrap()
        .split("factory Supplier")
        .next()
        .unwrap();
    for field in [
        "name",
        "aliases",
        "address",
        "categories",
        "notes",
        "merged_into",
        "rating",
        "rating_note",
    ] {
        assert!(supplier.contains(&format!("'{field}'")));
    }
}
