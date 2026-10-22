use muyon_core::{business::BusinessStore, contract::*, sqlite::Db};
use serde_json::json;
use std::{
    fs,
    io::{BufRead, BufReader},
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Barrier,
    },
    time::{Duration, Instant},
};
static COUNTER: AtomicU64 = AtomicU64::new(1);
struct TestDir(PathBuf);
impl TestDir {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "muyon-business-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&p).unwrap();
        Self(p)
    }
    fn path(&self) -> PathBuf {
        self.0.join("business.sqlite")
    }
    fn store(&self) -> BusinessStore {
        BusinessStore::initialize(&self.path(), "workspace-a").unwrap();
        self.reopen("epoch-a")
    }
    fn reopen(&self, epoch: &str) -> BusinessStore {
        BusinessStore::open_existing(&self.path(), "workspace-a", epoch).unwrap()
    }
    fn db(&self) -> Db {
        Db::open(self.path().to_str().unwrap(), false, false).unwrap()
    }
}
impl Drop for TestDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
struct Worker(Child);
impl Drop for Worker {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}
fn payload(name: &str) -> SupplierPayload {
    serde_json::from_value(json!({"name":name,"aliases":["乙","甲","甲"],"address":" 地址 ","categories":["设备"],"notes":"备注","merged_into":null,"rating":"preferred","rating_note":"推荐理由"})).unwrap()
}
fn command(intent: &str, revision: u64, operation: Operation) -> CommandEnvelope {
    let mut c = CommandEnvelope {
        protocol_version: 1,
        business_version: 1,
        intent_id: intent.into(),
        scope: Scope {
            workspace_id: "workspace-a".into(),
            project_id: None,
        },
        expected_revision: Revision::new(revision),
        authority: AuthorityBinding {
            grant_id: format!("grant-{intent}"),
            generation: Revision::new(1),
            owner_epoch: "epoch-a".into(),
        },
        plan_id: format!("plan-{intent}"),
        plan_digest: "0".repeat(64),
        command: operation,
    };
    seal(&mut c);
    c
}
fn seal(c: &mut CommandEnvelope) {
    c.plan_digest = c.expected_plan_digest().unwrap();
}
fn create(intent: &str, id: &str) -> CommandEnvelope {
    command(
        intent,
        0,
        Operation::SupplierCreate {
            supplier_id: id.into(),
            payload: payload("  e\u{301}  "),
        },
    )
}
fn execute(store: &BusinessStore, c: &CommandEnvelope) -> ExecutionResult {
    store.issue_grant_trusted(c, Some("admission-a")).unwrap();
    store.execute(c).unwrap()
}
fn count(db: &Db, table: &str) -> usize {
    db.query(&format!("SELECT COUNT(*) FROM {table}"), &[])
        .unwrap()[0][0]
        .as_ref()
        .unwrap()
        .parse()
        .unwrap()
}
fn worker(temp: &TestDir, mode: &str, c: Option<&CommandEnvelope>, expected: &str) -> Worker {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_business_worker"));
    cmd.arg(mode)
        .arg(temp.path())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(c) = c {
        let p = temp.0.join("command.json");
        fs::write(&p, serde_json::to_vec(c).unwrap()).unwrap();
        cmd.arg(p);
    }
    let mut child = Worker(cmd.spawn().unwrap());
    let mut line = String::new();
    BufReader::new(child.0.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    assert_eq!(line.trim(), expected);
    child
}

#[test]
fn initialize_is_explicit_and_never_truncates_or_migrates() {
    let temp = TestDir::new();
    assert!(BusinessStore::open_existing(&temp.path(), "workspace-a", "epoch-a").is_err());
    assert!(!temp.path().exists());
    let store = temp.store();
    let db = temp.db();
    assert!(BusinessStore::initialize(&temp.path(), "workspace-a").is_err());
    assert_eq!(count(&db, "meta"), 2);
    drop(store);
    assert!(matches!(
        BusinessStore::open_existing(&temp.path(), "other", "epoch-a"),
        Err(ContractError::ScopeMismatch)
    ));
    db.exec("UPDATE meta SET value='99' WHERE key='schema_version'", &[])
        .unwrap();
    assert!(matches!(
        BusinessStore::open_existing(&temp.path(), "workspace-a", "epoch-a"),
        Err(ContractError::InvalidVersion)
    ));
    assert_eq!(
        db.query("SELECT value FROM meta WHERE key='schema_version'", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("99")
    );
}

#[test]
fn supplier_full_payload_update_soft_delete_restore_and_original_receipt() {
    let temp = TestDir::new();
    let store = temp.store();
    let first = create("create-a", "supplier-a");
    let original = execute(&store, &first);
    assert_eq!(original.status, ExecutionStatus::Committed);
    original
        .receipt
        .as_ref()
        .unwrap()
        .validate_for(&first)
        .unwrap();
    assert_eq!(
        original.receipt.as_ref().unwrap().admission_id.as_deref(),
        Some("admission-a")
    );
    execute(&store, &create("create-b", "supplier-b"));
    assert_eq!(store.suppliers(200, 0).unwrap().len(), 2);
    let created = store.supplier("supplier-a").unwrap();
    assert_eq!(created.payload.name, "é");
    assert_eq!(created.payload.address.as_deref(), Some("地址"));
    assert_eq!(created.payload.aliases, ["乙", "甲"]);
    let mut changed = payload("新名称");
    changed.rating = Some("caution".into());
    changed.notes = None;
    let update = command(
        "update-a",
        1,
        Operation::SupplierUpdate {
            supplier_id: "supplier-a".into(),
            payload: changed.clone(),
        },
    );
    assert_eq!(execute(&store, &update).status, ExecutionStatus::Committed);
    assert_eq!(
        store.supplier("supplier-a").unwrap().payload,
        changed.normalize().unwrap()
    );
    store
        .add_reference_trusted("old-reference", "supplier-a")
        .unwrap();
    let delete = command(
        "delete-a",
        2,
        Operation::SupplierDelete {
            supplier_id: "supplier-a".into(),
        },
    );
    assert_eq!(execute(&store, &delete).status, ExecutionStatus::Committed);
    assert_eq!(store.suppliers(200, 0).unwrap().len(), 1);
    assert!(store.reference_supplier("old-reference").unwrap().deleted);
    assert_eq!(
        store.add_reference_trusted("new-reference", "supplier-a"),
        Err(ContractError::NotFound)
    );
    let restore = command(
        "restore-a",
        3,
        Operation::SupplierRestore {
            supplier_id: "supplier-a".into(),
        },
    );
    execute(&store, &restore);
    assert_eq!(
        store.supplier("supplier-a").unwrap().revision,
        Revision::new(4)
    );
    assert!(!store.reference_supplier("old-reference").unwrap().deleted);
    assert_eq!(store.lookup(&first.intent_id).unwrap(), original);
    assert_eq!(count(&temp.db(), "supplier_history"), 5);
    drop(store);
    let reopened = temp.reopen("epoch-b");
    assert_eq!(reopened.suppliers(200, 0).unwrap().len(), 2);
    assert_eq!(
        reopened.supplier("supplier-a").unwrap().revision,
        Revision::new(4)
    );
    assert_eq!(reopened.lookup(&first.intent_id).unwrap(), original);
}

#[test]
fn real_grants_expiry_revoke_generation_scope_and_epoch_are_required() {
    let temp = TestDir::new();
    let store = temp.store();
    let c = create("a", "supplier-a");
    assert_eq!(store.execute(&c), Err(ContractError::InvalidAuthority));
    assert_eq!(count(&temp.db(), "intents"), 0);
    store.issue_grant_trusted(&c, None).unwrap();
    store
        .revoke_grant_trusted(&c.authority.grant_id, &c.authority.generation)
        .unwrap();
    assert_eq!(store.execute(&c), Err(ContractError::InvalidAuthority));
    let mut next = c.clone();
    next.authority.generation = Revision::new(2);
    store.issue_grant_trusted(&next, None).unwrap();
    assert_eq!(store.execute(&c), Err(ContractError::InvalidAuthority));
    temp.db()
        .exec(
            "UPDATE business_grants SET expires_at_ms='0' WHERE grant_id=?",
            &[&next.authority.grant_id],
        )
        .unwrap();
    assert_eq!(store.execute(&next), Err(ContractError::InvalidAuthority));
    let mut wrong = next.clone();
    wrong.scope.workspace_id = "other".into();
    seal(&mut wrong);
    assert_eq!(store.execute(&wrong), Err(ContractError::ScopeMismatch));
    drop(store);
    let reopened = temp.reopen("epoch-b");
    assert_eq!(
        reopened.execute(&next),
        Err(ContractError::InvalidAuthority)
    );
    assert_eq!(count(&temp.db(), "supplier"), 0);
}

#[test]
fn duplicate_binding_conflict_cas_and_same_name_new_intent() {
    let temp = TestDir::new();
    let store = temp.store();
    let c = create("a", "supplier-a");
    let original = execute(&store, &c);
    assert_eq!(store.execute(&c).unwrap(), original);
    assert_eq!(count(&temp.db(), "supplier_history"), 1);
    let mut changed = c.clone();
    if let Operation::SupplierCreate { payload, .. } = &mut changed.command {
        payload.name = "changed".into();
    }
    seal(&mut changed);
    assert_eq!(store.execute(&changed), Err(ContractError::IntentConflict));
    let edit1 = command(
        "edit1",
        1,
        Operation::SupplierUpdate {
            supplier_id: "supplier-a".into(),
            payload: payload("é"),
        },
    );
    let edit2 = command(
        "edit2",
        1,
        Operation::SupplierUpdate {
            supplier_id: "supplier-a".into(),
            payload: payload("other"),
        },
    );
    store.issue_grant_trusted(&edit1, None).unwrap();
    store.issue_grant_trusted(&edit2, None).unwrap();
    assert_eq!(
        store.execute(&edit1).unwrap().status,
        ExecutionStatus::Committed
    );
    let rejected = store.execute(&edit2).unwrap();
    assert_eq!(rejected.status, ExecutionStatus::Rejected);
    assert_eq!(rejected.error, Some(ContractError::RevisionConflict));
    assert_eq!(
        store.supplier("supplier-a").unwrap().revision,
        Revision::new(2)
    );
    assert_eq!(count(&temp.db(), "supplier_history"), 2);
    assert_eq!(store.execute(&edit2).unwrap(), rejected);
}

#[test]
fn corrupt_receipt_tail_rolls_back_all_effects_and_never_reexecutes_pending() {
    let temp = TestDir::new();
    let store = temp.store();
    let db = temp.db();
    db.exec("CREATE TRIGGER corrupt_receipt AFTER UPDATE OF status ON intents WHEN NEW.status='committed' BEGIN UPDATE intents SET receipt_json='{}' WHERE intent_id=NEW.intent_id; END",&[]).unwrap();
    let c = create("a", "supplier-a");
    let result = execute(&store, &c);
    assert_eq!(result.status, ExecutionStatus::Unknown);
    assert_eq!(count(&db, "supplier"), 0);
    assert_eq!(count(&db, "supplier_history"), 0);
    assert_eq!(count(&db, "business_history"), 0);
    assert_eq!(
        db.query("SELECT status,receipt_json FROM intents", &[])
            .unwrap()[0],
        vec![Some("pending".into()), None]
    );
    db.exec("DROP TRIGGER corrupt_receipt", &[]).unwrap();
    assert_eq!(store.execute(&c).unwrap().status, ExecutionStatus::Unknown);
    assert_eq!(count(&db, "supplier"), 0);
    let before = db.query("SELECT * FROM intents", &[]).unwrap();
    assert_eq!(
        store.lookup("missing").unwrap().error,
        Some(ContractError::NotFound)
    );
    assert_eq!(store.lookup("a").unwrap().status, ExecutionStatus::Unknown);
    assert_eq!(db.query("SELECT * FROM intents", &[]).unwrap(), before);
    assert_eq!(
        store.cancel_trusted("a").unwrap().status,
        ExecutionStatus::Cancelled
    );
    assert_eq!(
        store.execute(&c).unwrap().status,
        ExecutionStatus::Cancelled
    );
}

#[test]
fn sqlite_revocation_transaction_barrier_precedes_business_admission() {
    let temp = TestDir::new();
    let store = temp.store();
    let c = create("a", "supplier-a");
    store.issue_grant_trusted(&c, None).unwrap();
    let barrier = Arc::new(Barrier::new(2));
    let other = barrier.clone();
    let path = temp.path();
    let grant = c.authority.grant_id.clone();
    let revoke = std::thread::spawn(move || {
        let db = Db::open(path.to_str().unwrap(), false, false).unwrap();
        let tx = db.transaction().unwrap();
        db.exec(
            "UPDATE business_grants SET active=0 WHERE grant_id=?",
            &[&grant],
        )
        .unwrap();
        other.wait();
        std::thread::sleep(Duration::from_millis(100));
        tx.commit().unwrap();
    });
    let start = Instant::now();
    barrier.wait();
    assert_eq!(store.execute(&c), Err(ContractError::InvalidAuthority));
    revoke.join().unwrap();
    assert!(start.elapsed() >= Duration::from_millis(70));
    assert_eq!(count(&temp.db(), "supplier"), 0);
    assert_eq!(count(&temp.db(), "intents"), 0);
}

#[test]
fn cross_process_owner_lock_is_released_only_after_process_exit() {
    let temp = TestDir::new();
    BusinessStore::initialize(&temp.path(), "workspace-a").unwrap();
    let mut child = worker(&temp, "hold-owner", None, "OWNER_READY");
    assert!(matches!(
        BusinessStore::open_existing(&temp.path(), "workspace-a", "epoch-b"),
        Err(ContractError::InvalidAuthority)
    ));
    child.0.kill().unwrap();
    child.0.wait().unwrap();
    let _store = temp.reopen("epoch-b");
}

#[test]
fn sigkill_after_actual_sql_rolls_back_and_original_pending_cannot_redispatch() {
    let temp = TestDir::new();
    BusinessStore::initialize(&temp.path(), "workspace-a").unwrap();
    let c = create("a", "supplier-a");
    let mut child = worker(&temp, "after-sql", Some(&c), "SQL_APPLIED_UNCOMMITTED");
    child.0.kill().unwrap();
    let status = child.0.wait().unwrap();
    assert!(!status.success());
    let store = temp.reopen("epoch-a");
    let db = temp.db();
    assert_eq!(count(&db, "supplier"), 0);
    assert_eq!(count(&db, "supplier_history"), 0);
    assert_eq!(count(&db, "business_history"), 0);
    assert_eq!(store.lookup("a").unwrap().status, ExecutionStatus::Unknown);
    assert_eq!(store.execute(&c).unwrap().status, ExecutionStatus::Unknown);
    assert_eq!(count(&db, "supplier"), 0);
}

#[test]
fn sigkill_after_commit_before_reply_recovers_exact_original_receipt() {
    let temp = TestDir::new();
    BusinessStore::initialize(&temp.path(), "workspace-a").unwrap();
    let c = create("a", "supplier-a");
    let mut child = worker(&temp, "after-commit", Some(&c), "COMMITTED_REPLY_WITHHELD");
    child.0.kill().unwrap();
    child.0.wait().unwrap();
    let store = temp.reopen("epoch-a");
    let db = temp.db();
    let original = store.lookup("a").unwrap();
    assert_eq!(original.status, ExecutionStatus::Committed);
    original.receipt.as_ref().unwrap().validate_for(&c).unwrap();
    assert_eq!(store.execute(&c).unwrap(), original);
    assert_eq!(count(&db, "supplier"), 1);
    assert_eq!(count(&db, "supplier_history"), 1);
    assert_eq!(count(&db, "business_history"), 1);
    assert_eq!(store.cancel_trusted("a").unwrap(), original);
    assert_eq!(
        store.supplier("supplier-a").unwrap().revision,
        Revision::new(1)
    );
}

#[test]
fn project_create_and_reads_are_persistent_workspace_bound_operations() {
    let temp = TestDir::new();
    let store = temp.store();
    let c = command(
        "project-a",
        0,
        Operation::ProjectCreate {
            project_id: "project-a".into(),
            name: "  科研工作台  ".into(),
        },
    );
    let result = execute(&store, &c);
    assert_eq!(result.status, ExecutionStatus::Committed);
    assert_eq!(store.project("project-a").unwrap().name, "科研工作台");
    assert_eq!(store.projects(200, 0).unwrap().len(), 1);
    assert_eq!(store.projects(200, 1).unwrap().len(), 0);
    assert!(store.projects(201, 0).is_err());
    assert_eq!(count(&temp.db(), "business_history"), 1);
    drop(store);
    let reopened = temp.reopen("epoch-b");
    assert_eq!(
        reopened.project("project-a").unwrap().revision,
        Revision::new(1)
    );
    assert_eq!(reopened.lookup(&c.intent_id).unwrap(), result);
}

#[test]
fn grant_expiring_during_actual_sql_rejects_and_rolls_back_the_effect() {
    let temp = TestDir::new();
    let store = temp.store();
    let db = temp.db();
    db.exec("CREATE TRIGGER expire_during_effect AFTER INSERT ON supplier BEGIN UPDATE business_grants SET expires_at_ms='0'; END",&[]).unwrap();
    let c = create("a", "supplier-a");
    let result = execute(&store, &c);
    assert_eq!(result.status, ExecutionStatus::Rejected);
    assert_eq!(result.error, Some(ContractError::InvalidAuthority));
    assert_eq!(count(&db, "supplier"), 0);
    assert_eq!(count(&db, "supplier_history"), 0);
    assert_eq!(count(&db, "business_history"), 0);
}

#[test]
fn sqlite_constraints_and_corrupt_files_have_fixed_typed_errors() {
    let temp = TestDir::new();
    let store = temp.store();
    execute(&store, &create("a", "supplier-a"));
    store.add_reference_trusted("ref-a", "supplier-a").unwrap();
    assert_eq!(
        store.add_reference_trusted("ref-a", "supplier-a"),
        Err(ContractError::StorageConstraint)
    );
    drop(store);
    let corrupt = temp.0.join("corrupt.sqlite");
    fs::write(&corrupt, b"not a SQLite database").unwrap();
    assert!(matches!(
        BusinessStore::open_existing(&corrupt, "workspace-a", "epoch-a"),
        Err(ContractError::StorageCorrupt)
    ));
}

#[test]
fn old_schema_v1_missing_tail_table_is_refused_without_changing_pending_identity() {
    let temp = TestDir::new();
    let store = temp.store();
    drop(store);
    let db = temp.db();
    db.exec("UPDATE meta SET value='1' WHERE key='schema_version'", &[])
        .unwrap();
    db.exec("DROP TABLE research_import_members", &[]).unwrap();
    let command = create("preserved-old-intent", "supplier-a");
    let binding = command.binding_digest().unwrap();
    let raw = serde_json::to_string(&command).unwrap();
    db.exec("INSERT INTO intents(intent_id,binding_digest,command_json,status,owner_epoch) VALUES(?,?,?,'pending','epoch-a')",&[&command.intent_id,&binding,&raw]).unwrap();
    let before = db.query("SELECT * FROM intents", &[]).unwrap();
    assert!(
        matches!(
            BusinessStore::open_existing(&temp.path(), "workspace-a", "epoch-b"),
            Err(ContractError::InvalidVersion)
        ),
        "incomplete v1 store must not be accepted as current"
    );
    assert_eq!(db.query("SELECT * FROM intents", &[]).unwrap(), before);
    assert_eq!(
        db.query("SELECT value FROM meta WHERE key='schema_version'", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
    assert!(db
        .query(
            "SELECT name FROM sqlite_master WHERE name='research_import_members'",
            &[]
        )
        .unwrap()
        .is_empty());
}

#[test]
fn current_schema_label_does_not_authorize_a_missing_required_table_or_column() {
    let temp = TestDir::new();
    let store = temp.store();
    drop(store);
    let db = temp.db();
    db.exec("DROP TABLE research_import_members", &[]).unwrap();
    assert!(
        matches!(
            BusinessStore::open_existing(&temp.path(), "workspace-a", "epoch-a"),
            Err(ContractError::InvalidVersion)
        ),
        "version marker alone cannot prove the required table exists"
    );
    let other = TestDir::new();
    let store = other.store();
    drop(store);
    let db = other.db();
    db.exec(
        "ALTER TABLE research_sources RENAME COLUMN records_digest TO missing_required_digest",
        &[],
    )
    .unwrap();
    assert!(
        matches!(
            BusinessStore::open_existing(&other.path(), "workspace-a", "epoch-a"),
            Err(ContractError::InvalidVersion)
        ),
        "version marker alone cannot prove required columns and constraints"
    );
}
