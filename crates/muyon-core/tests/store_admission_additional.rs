//! Additional local admission evidence. No production hooks or device namespaces.
use muyon_core::{business::BusinessStore, contract::*, sqlite::Db};
use serde_json::json;
use std::{
    fs,
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Child, ChildStdin, ChildStdout, Command, Stdio},
    sync::atomic::{AtomicU64, Ordering},
};

static COUNTER: AtomicU64 = AtomicU64::new(0);
const CHILD_MODE: &str = "MUYON_STORE_ADDITIONAL_CHILD_MODE";
const CHILD_PATH: &str = "MUYON_STORE_ADDITIONAL_CHILD_PATH";
const CHILD_COMMAND: &str = "MUYON_STORE_ADDITIONAL_CHILD_COMMAND";
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let dir = std::env::temp_dir().join(format!(
            "muyon-store-additional-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&dir).unwrap();
        Self(dir)
    }
    fn path(&self) -> PathBuf {
        self.0.join("store.sqlite")
    }
    fn initialize(&self) -> BusinessStore {
        BusinessStore::initialize(&self.path(), "workspace-a").unwrap();
        self.open()
    }
    fn open(&self) -> BusinessStore {
        BusinessStore::open_existing(&self.path(), "workspace-a", "epoch-a").unwrap()
    }
    fn inspect(&self) -> Db {
        Db::open(self.path().to_str().unwrap(), true, false).unwrap()
    }
    fn mutate_fixture(&self) -> Db {
        Db::open(self.path().to_str().unwrap(), false, false).unwrap()
    }
    fn command_file(&self, name: &str, c: &CommandEnvelope) -> PathBuf {
        let p = self.0.join(name);
        fs::write(&p, serde_json::to_vec(c).unwrap()).unwrap();
        p
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn supplier(name: &str) -> SupplierPayload {
    serde_json::from_value(json!({"name":name,"aliases":[],"address":null,"categories":[],"notes":null,"merged_into":null,"rating":null,"rating_note":null})).unwrap()
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
    c.plan_digest = c.expected_plan_digest().unwrap();
    c
}
fn create(intent: &str) -> CommandEnvelope {
    command(
        intent,
        0,
        Operation::SupplierCreate {
            supplier_id: "supplier-a".into(),
            payload: supplier("synthetic"),
        },
    )
}
fn count(db: &Db, table: &str) -> usize {
    db.query(&format!("SELECT COUNT(*) FROM {table}"), &[])
        .unwrap()[0][0]
        .as_deref()
        .unwrap()
        .parse()
        .unwrap()
}
fn no_business_effect(db: &Db) {
    for table in ["supplier", "supplier_history", "business_history"] {
        assert_eq!(count(db, table), 0, "unexpected persisted {table}");
    }
    assert_eq!(
        db.query(
            "SELECT COUNT(*) FROM intents WHERE status='committed' OR receipt_json IS NOT NULL",
            &[]
        )
        .unwrap()[0][0]
            .as_deref(),
        Some("0")
    );
}

#[test]
fn sqlite_rejects_pending_domain_history_business_history_and_receipt_writes_atomically() {
    let faults=[
        ("pending","CREATE TRIGGER fail_stage BEFORE INSERT ON intents BEGIN SELECT RAISE(ABORT,'fixture denied pending write'); END",false),
        ("domain-history","CREATE TRIGGER fail_stage BEFORE INSERT ON supplier_history BEGIN SELECT RAISE(ABORT,'fixture denied domain history write'); END",true),
        ("business-history","CREATE TRIGGER fail_stage BEFORE INSERT ON business_history BEGIN SELECT RAISE(ABORT,'fixture denied business history write'); END",true),
        ("receipt-status","CREATE TRIGGER fail_stage BEFORE UPDATE OF status,receipt_json ON intents WHEN NEW.status='committed' BEGIN SELECT RAISE(ABORT,'fixture denied receipt write'); END",true),
    ];
    for (stage, trigger, has_pending) in faults {
        let fixture = Fixture::new();
        let store = fixture.initialize();
        let writer = fixture.mutate_fixture();
        writer.exec(trigger, &[]).unwrap();
        let c = create("fault-intent");
        store.issue_grant_trusted(&c, None).unwrap();
        let result = store.execute(&c);
        if has_pending {
            assert_eq!(result.unwrap().status, ExecutionStatus::Unknown, "{stage}");
        } else {
            assert_eq!(result, Err(ContractError::StorageConstraint), "{stage}");
        }
        let db = fixture.inspect();
        no_business_effect(&db);
        assert_eq!(count(&db, "intents"), usize::from(has_pending));
        let grants = db
            .query("SELECT active,generation FROM business_grants", &[])
            .unwrap();
        assert_eq!(grants[0], vec![Some("1".into()), Some("1".into())]);
        writer.exec("DROP TRIGGER fail_stage", &[]).unwrap();
        if has_pending {
            assert_eq!(store.execute(&c).unwrap().status, ExecutionStatus::Unknown);
            no_business_effect(&db);
        }
        drop(store);
        let reopened = fixture.open();
        let expected = if has_pending {
            Some(ContractError::Unknown)
        } else {
            Some(ContractError::NotFound)
        };
        assert_eq!(reopened.lookup(&c.intent_id).unwrap().error, expected);
        no_business_effect(&fixture.inspect());
    }
}

struct Process {
    child: Child,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
}
impl Process {
    fn spawn(test: &str, mode: &str, path: &Path, command: &Path) -> Self {
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", test, "--nocapture"])
            .env(CHILD_MODE, mode)
            .env(CHILD_PATH, path)
            .env(CHILD_COMMAND, command)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .unwrap();
        let input = child.stdin.take().unwrap();
        let output = BufReader::new(child.stdout.take().unwrap());
        Self {
            child,
            input,
            output,
        }
    }
    fn gate(&mut self) -> String {
        loop {
            let mut line = String::new();
            assert_ne!(
                self.output.read_line(&mut line).unwrap(),
                0,
                "child exited before gate"
            );
            if let Some(gate) = line.trim().strip_prefix("GATE:") {
                return gate.to_owned();
            }
        }
    }
    fn release(&mut self) {
        self.input.write_all(b"continue\n").unwrap();
        self.input.flush().unwrap();
    }
    fn successful_exit(&mut self) {
        assert!(self.child.wait().unwrap().success());
    }
}
impl Drop for Process {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
fn signal(gate: &str) {
    println!("GATE:{gate}");
    std::io::stdout().flush().unwrap();
}
fn wait_for_parent() {
    let mut line = String::new();
    std::io::stdin().read_line(&mut line).unwrap();
}
fn child_input() -> (PathBuf, CommandEnvelope) {
    let path = PathBuf::from(std::env::var(CHILD_PATH).unwrap());
    let c = CommandEnvelope::decode(
        &fs::read_to_string(std::env::var(CHILD_COMMAND).unwrap()).unwrap(),
    )
    .unwrap();
    (path, c)
}

#[cfg(unix)]
#[test]
fn real_os_file_size_write_failure_has_no_business_or_receipt_effect() {
    if std::env::var(CHILD_MODE).as_deref() == Ok("write-limit") {
        let (path, c) = child_input();
        let store = BusinessStore::open_existing(&path, "workspace-a", "epoch-a").unwrap();
        store.issue_grant_trusted(&c, None).unwrap();
        #[repr(C)]
        struct Limit {
            current: u64,
            maximum: u64,
        }
        unsafe extern "C" {
            fn setrlimit(resource: i32, limit: *const Limit) -> i32;
            #[link_name = "signal"]
            fn os_signal(number: i32, handler: usize) -> usize;
        }
        let sigxfsz = 25;
        // Only this dedicated child loses its regular-file write quota; no disk is filled.
        unsafe {
            assert_ne!(os_signal(sigxfsz, 1), usize::MAX);
            assert_eq!(
                setrlimit(
                    1,
                    &Limit {
                        current: 0,
                        maximum: 0
                    }
                ),
                0
            );
        }
        let evidence = match store.execute(&c) {
            Err(ContractError::StorageIo) => "storage_io",
            Err(ContractError::Storage) => "storage",
            Ok(ExecutionResult {
                status: ExecutionStatus::Unknown,
                ..
            }) => "unknown",
            result => panic!("actual SQLite file write must fail: {result:?}"),
        };
        signal(&format!("SQLITE_WRITE_REFUSED:{evidence}"));
        return;
    }
    let fixture = Fixture::new();
    let store = fixture.initialize();
    drop(store);
    let c = create("write-limit-intent");
    let input = fixture.command_file("command.json", &c);
    let mut child = Process::spawn(
        "real_os_file_size_write_failure_has_no_business_or_receipt_effect",
        "write-limit",
        &fixture.path(),
        &input,
    );
    let evidence = child.gate();
    assert!(evidence.starts_with("SQLITE_WRITE_REFUSED:"));
    println!("{evidence}");
    child.successful_exit();
    no_business_effect(&fixture.inspect());
    let reopened = fixture.open();
    assert_eq!(
        reopened.lookup(&c.intent_id).unwrap().status,
        ExecutionStatus::Unknown
    );
    no_business_effect(&fixture.inspect());
}

#[test]
fn os_process_races_preserve_original_intent_and_reject_stale_cas_after_owner_exit() {
    if std::env::var(CHILD_MODE).as_deref() == Ok("race") {
        let (path, c) = child_input();
        signal("READY");
        wait_for_parent();
        let store = match BusinessStore::open_existing(&path, "workspace-a", "epoch-a") {
            Ok(store) => store,
            Err(ContractError::InvalidAuthority) => {
                signal("OWNER_DENIED");
                return;
            }
            Err(error) => panic!("unexpected owner failure: {error:?}"),
        };
        signal("OWNER_ACQUIRED");
        wait_for_parent();
        store.issue_grant_trusted(&c, None).unwrap();
        assert_eq!(
            store.execute(&c).unwrap().status,
            ExecutionStatus::Committed
        );
        signal("COMMITTED");
        return;
    }
    for cas in [false, true] {
        let fixture = Fixture::new();
        let store = fixture.initialize();
        if cas {
            let initial = create("initial");
            store.issue_grant_trusted(&initial, None).unwrap();
            assert_eq!(
                store.execute(&initial).unwrap().status,
                ExecutionStatus::Committed
            );
        }
        drop(store);
        let first = if cas {
            command(
                "edit-a",
                1,
                Operation::SupplierUpdate {
                    supplier_id: "supplier-a".into(),
                    payload: supplier("edit-a"),
                },
            )
        } else {
            create("same-intent")
        };
        let second = if cas {
            command(
                "edit-b",
                1,
                Operation::SupplierUpdate {
                    supplier_id: "supplier-a".into(),
                    payload: supplier("edit-b"),
                },
            )
        } else {
            first.clone()
        };
        let a = fixture.command_file("a.json", &first);
        let b = fixture.command_file("b.json", &second);
        let mut left = Process::spawn(
            "os_process_races_preserve_original_intent_and_reject_stale_cas_after_owner_exit",
            "race",
            &fixture.path(),
            &a,
        );
        let mut right = Process::spawn(
            "os_process_races_preserve_original_intent_and_reject_stale_cas_after_owner_exit",
            "race",
            &fixture.path(),
            &b,
        );
        assert_eq!(left.gate(), "READY");
        assert_eq!(right.gate(), "READY");
        left.release();
        right.release();
        let l = left.gate();
        let r = right.gate();
        assert!(
            (l == "OWNER_ACQUIRED" && r == "OWNER_DENIED")
                || (r == "OWNER_ACQUIRED" && l == "OWNER_DENIED"),
            "{l}/{r}"
        );
        let winner_left = l == "OWNER_ACQUIRED";
        let winner = if winner_left { &mut left } else { &mut right };
        winner.release();
        assert_eq!(winner.gate(), "COMMITTED");
        left.successful_exit();
        right.successful_exit();
        let store = fixture.open();
        let winning = if winner_left { &first } else { &second };
        let original = store.lookup(&winning.intent_id).unwrap();
        assert_eq!(original.status, ExecutionStatus::Committed);
        assert_eq!(store.execute(winning).unwrap(), original);
        if cas {
            let losing = if winner_left { &second } else { &first };
            store.issue_grant_trusted(losing, None).unwrap();
            let rejected = store.execute(losing).unwrap();
            assert_eq!(rejected.status, ExecutionStatus::Rejected);
            assert_eq!(rejected.error, Some(ContractError::RevisionConflict));
            assert_eq!(
                store.supplier("supplier-a").unwrap().revision,
                Revision::new(2)
            );
        } else {
            assert_eq!(store.execute(&second).unwrap(), original);
            assert_eq!(
                store.supplier("supplier-a").unwrap().revision,
                Revision::new(1)
            );
        }
        let db = fixture.inspect();
        assert_eq!(count(&db, "supplier"), 1);
        assert_eq!(count(&db, "supplier_history"), if cas { 2 } else { 1 });
        assert_eq!(count(&db, "business_history"), if cas { 2 } else { 1 });
    }
}
