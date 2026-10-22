use super::*;
use std::{
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};
static NEXT: AtomicU64 = AtomicU64::new(1);
const CONVERSATION: &str = "11111111-1111-4111-8111-111111111111";
const INTENT: &str = "22222222-2222-4222-8222-222222222222";
const OTHER: &str = "33333333-3333-4333-8333-333333333333";
struct Fixture {
    path: PathBuf,
    store: Option<BusinessStore>,
    binding: DraftBinding,
}
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "muyon-definition-{}-{}.db",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::SeqCst)
        ));
        BusinessStore::initialize(&path, "synthetic").unwrap();
        let store = BusinessStore::open_existing(&path, "synthetic", "epoch1").unwrap();
        let d = crate::bot_drafts::resolve(&store, CONVERSATION, None).unwrap();
        let mut binding = DraftBinding {
            namespace_id: d["namespace_id"].as_str().unwrap().into(),
            draft_id: d["draft_id"].as_str().unwrap().into(),
            expected_generation: "1".into(),
            expected_stored_revision: "0".into(),
        };
        save_draft(
            &store,
            CONVERSATION,
            None,
            &binding,
            OTHER,
            "3",
            &archive(1),
        )
        .unwrap();
        binding.expected_stored_revision = "1".into();
        Self {
            path,
            store: Some(store),
            binding,
        }
    }
    fn store(&self) -> &BusinessStore {
        self.store.as_ref().unwrap()
    }
    fn reopen(&mut self) {
        self.store.take();
        self.store = Some(BusinessStore::open_existing(&self.path, "synthetic", "epoch2").unwrap());
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        self.store.take();
        for suffix in ["", "-wal", "-shm", ".owner.lock"] {
            let _ = std::fs::remove_file(format!("{}{suffix}", self.path.display()));
        }
    }
}
fn archive(revision: i64) -> Vec<u8> {
    let mut b = b"MYBD\0\0\0\x01".to_vec();
    b.extend(revision.to_be_bytes());
    for s in ["论文助手", "整理文献", "研究员"] {
        b.extend([0, 1]);
        b.extend((s.len() as i32).to_be_bytes());
        b.extend(s.as_bytes());
    }
    b.push(0);
    let h = Sha256::digest(&b);
    b.extend(h);
    b
}
fn prepare(f: &Fixture) -> CreateReview {
    prepare_create(f.store(), CONVERSATION, None, &f.binding, INTENT).unwrap()
}
#[test]
fn creates_only_after_confirm_and_original_intent_is_idempotent() {
    let f = Fixture::new();
    let r = prepare(&f);
    assert!(list(f.store(), CONVERSATION, None).unwrap().is_empty());
    let a =
        confirm_create_trusted(f.store(), CONVERSATION, None, INTENT, &r.review_digest).unwrap();
    assert_eq!(a.status, CreateStatus::Committed);
    let bot = a.definition.as_ref().unwrap();
    assert_eq!(bot.name, "论文助手");
    assert!(!bot.runnable);
    assert_eq!(bot.unavailable_reason, "provider_not_configured");
    let b =
        confirm_create_trusted(f.store(), CONVERSATION, None, INTENT, &r.review_digest).unwrap();
    assert_eq!(a, b);
    assert_eq!(
        lookup_create(f.store(), CONVERSATION, None, INTENT).unwrap(),
        a
    );
    assert_eq!(list(f.store(), CONVERSATION, None).unwrap().len(), 1);
    assert_eq!(get(f.store(), CONVERSATION, None, &bot.id).unwrap(), *bot);
    assert!(prepare_create(f.store(), CONVERSATION, None, &f.binding, OTHER).is_err());
    assert_eq!(
        f.store()
            .database()
            .query("SELECT COUNT(*) FROM business_grants", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("0")
    );
}
#[test]
fn cas_scope_and_changed_confirmation_reject_without_definition() {
    let f = Fixture::new();
    let r = prepare(&f);
    assert!(confirm_create_trusted(f.store(), CONVERSATION, None, INTENT, "wrong").is_err());
    assert!(lookup_create(f.store(), OTHER, None, INTENT).is_err());
    save_draft(
        f.store(),
        CONVERSATION,
        None,
        &f.binding,
        "44444444-4444-4444-8444-444444444444",
        "4",
        &archive(2),
    )
    .unwrap();
    assert!(
        confirm_create_trusted(f.store(), CONVERSATION, None, INTENT, &r.review_digest).is_err()
    );
    assert!(list(f.store(), CONVERSATION, None).unwrap().is_empty());
}
#[test]
fn pending_unknown_never_reexecutes_and_archive_replay_cannot_clear_stop() {
    let mut f = Fixture::new();
    let r = prepare(&f);
    f.store().database().exec("CREATE TRIGGER fail_bot BEFORE INSERT ON local_bot_definitions BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",&[]).unwrap();
    assert!(
        confirm_create_trusted(f.store(), CONVERSATION, None, INTENT, &r.review_digest).is_err()
    );
    f.reopen();
    recover_previous_owner(f.store()).unwrap();
    let unknown = lookup_create(f.store(), CONVERSATION, None, INTENT).unwrap();
    assert_eq!(unknown.status, CreateStatus::Unknown);
    f.store()
        .database()
        .exec("DROP TRIGGER fail_bot", &[])
        .unwrap();
    assert_eq!(
        confirm_create_trusted(f.store(), CONVERSATION, None, INTENT, &r.review_digest).unwrap(),
        unknown
    );
    save_draft(
        f.store(),
        CONVERSATION,
        None,
        &f.binding,
        "44444444-4444-4444-8444-444444444444",
        "4",
        &archive(2),
    )
    .unwrap();
    f.binding.expected_stored_revision = "2".into();
    // Restored/newly saved editing data cannot erase the durable creation guard.
    assert!(prepare_create(f.store(), CONVERSATION, None, &f.binding, OTHER).is_err());
    assert!(save_draft(
        f.store(),
        CONVERSATION,
        None,
        &f.binding,
        "55555555-5555-4555-8555-555555555555",
        "3",
        &archive(1)
    )
    .is_err());
    assert_eq!(
        lookup_create(f.store(), CONVERSATION, None, INTENT).unwrap(),
        unknown
    );
    assert!(list(f.store(), CONVERSATION, None).unwrap().is_empty());
}
#[test]
fn committed_receipt_and_definition_survive_restart_without_replaying() {
    if let Some(path) = std::env::var_os("MUYON_SYNTHETIC_BOT_CHILD_DB") {
        let store =
            BusinessStore::open_existing(std::path::Path::new(&path), "synthetic", "epoch1")
                .unwrap();
        confirm_create_trusted(
            &store,
            CONVERSATION,
            None,
            INTENT,
            &std::env::var("MUYON_SYNTHETIC_BOT_REVIEW").unwrap(),
        )
        .unwrap();
        panic!("child should be killed while original effect transaction is held");
    }
    let mut f = Fixture::new();
    let r = prepare(&f);
    let receipt =
        confirm_create_trusted(f.store(), CONVERSATION, None, INTENT, &r.review_digest).unwrap();
    f.reopen();
    recover_previous_owner(f.store()).unwrap();
    assert_eq!(
        lookup_create(f.store(), CONVERSATION, None, INTENT).unwrap(),
        receipt
    );
    assert_eq!(list(f.store(), CONVERSATION, None).unwrap().len(), 1);
}
#[test]
fn old_prepared_review_is_sealed_and_explicit_cancel_allows_new_review() {
    let mut f = Fixture::new();
    prepare(&f);
    f.reopen();
    assert!(confirm_create_trusted(
        f.store(),
        CONVERSATION,
        None,
        INTENT,
        &prepare(&f).review_digest
    )
    .is_err());
    recover_previous_owner(f.store()).unwrap();
    assert_eq!(
        lookup_create(f.store(), CONVERSATION, None, INTENT)
            .unwrap()
            .status,
        CreateStatus::Rejected
    );
    let r = prepare_create(f.store(), CONVERSATION, None, &f.binding, OTHER).unwrap();
    cancel_prepared(f.store(), CONVERSATION, None, OTHER).unwrap();
    assert!(
        confirm_create_trusted(f.store(), CONVERSATION, None, OTHER, &r.review_digest).is_err()
    );
}
#[test]
fn corrupted_archive_and_unknown_schema_fail_closed() {
    let f = Fixture::new();
    f.store()
        .database()
        .exec("UPDATE local_bot_drafts SET archive_hex='00'", &[])
        .unwrap();
    assert!(prepare_create(f.store(), CONVERSATION, None, &f.binding, INTENT).is_err());
    assert!(list(f.store(), CONVERSATION, None).unwrap().is_empty());
    f.store()
        .database()
        .exec("UPDATE local_bot_definition_meta SET version='2'", &[])
        .unwrap();
    assert!(list(f.store(), CONVERSATION, None).is_err());
}

#[test]
fn receipt_update_failure_rolls_back_definition_and_keeps_original_pending() {
    let f = Fixture::new();
    let r = prepare(&f);
    f.store().database().exec("CREATE TRIGGER fail_receipt BEFORE UPDATE OF status ON local_bot_definition_intents WHEN NEW.status='committed' BEGIN SELECT RAISE(ABORT,'synthetic receipt failure'); END", &[]).unwrap();
    assert!(
        confirm_create_trusted(f.store(), CONVERSATION, None, INTENT, &r.review_digest).is_err()
    );
    let independent = crate::sqlite::Db::open(f.path.to_str().unwrap(), true, false).unwrap();
    assert_eq!(
        independent
            .query("SELECT COUNT(*) FROM local_bot_definitions", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("0")
    );
    assert_eq!(
        lookup_create(f.store(), CONVERSATION, None, INTENT)
            .unwrap()
            .status,
        CreateStatus::Unknown
    );
    f.store()
        .database()
        .exec("DROP TRIGGER fail_receipt", &[])
        .unwrap();
    assert_eq!(
        confirm_create_trusted(f.store(), CONVERSATION, None, INTENT, &r.review_digest)
            .unwrap()
            .status,
        CreateStatus::Unknown
    );
    assert!(list(f.store(), CONVERSATION, None).unwrap().is_empty());
}

#[test]
fn real_child_process_kill_preserves_pending_and_original_lookup() {
    let mut f = Fixture::new();
    let r = prepare(&f);
    f.store().database().exec("CREATE TRIGGER slow_bot BEFORE INSERT ON local_bot_definitions BEGIN SELECT (WITH RECURSIVE work(n) AS (VALUES(0) UNION ALL SELECT n+1 FROM work WHERE n<1000000000) SELECT SUM(n) FROM work); END", &[]).unwrap();
    f.store.take();
    let mut child = std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "bot_definitions::tests::committed_receipt_and_definition_survive_restart_without_replaying", "--nocapture"])
        .env("MUYON_SYNTHETIC_BOT_CHILD_DB", &f.path)
        .env("MUYON_SYNTHETIC_BOT_REVIEW", &r.review_digest)
        .spawn().unwrap();
    let db = crate::sqlite::Db::open(f.path.to_str().unwrap(), true, false).unwrap();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let mut saw_pending = false;
    while std::time::Instant::now() < deadline {
        let rows = db
            .query(
                "SELECT status FROM local_bot_definition_intents WHERE intent_id=?",
                &[INTENT],
            )
            .unwrap();
        if rows[0][0].as_deref() == Some("pending") {
            saw_pending = true;
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
    child.kill().unwrap();
    let killed = child.wait().unwrap();
    assert!(!killed.success());
    assert!(
        saw_pending,
        "observed durable pending before killing owned synthetic child"
    );
    drop(db);
    f.reopen();
    recover_previous_owner(f.store()).unwrap();
    assert_eq!(
        lookup_create(f.store(), CONVERSATION, None, INTENT)
            .unwrap()
            .status,
        CreateStatus::Unknown
    );
    assert!(list(f.store(), CONVERSATION, None).unwrap().is_empty());
    assert!(prepare_create(f.store(), CONVERSATION, None, &f.binding, OTHER).is_err());
}

fn project_fixture() -> Fixture {
    let mut f = Fixture::new();
    f.store()
        .database()
        .exec(
            "INSERT INTO projects VALUES('p1','synthetic','Synthetic project','1',0)",
            &[],
        )
        .unwrap();
    let d = crate::bot_drafts::resolve(f.store(), CONVERSATION, Some("p1")).unwrap();
    f.binding = DraftBinding {
        namespace_id: d["namespace_id"].as_str().unwrap().into(),
        draft_id: d["draft_id"].as_str().unwrap().into(),
        expected_generation: "1".into(),
        expected_stored_revision: "0".into(),
    };
    save_draft(
        f.store(),
        CONVERSATION,
        Some("p1"),
        &f.binding,
        "44444444-4444-4444-8444-444444444444",
        "3",
        &archive(1),
    )
    .unwrap();
    f.binding.expected_stored_revision = "1".into();
    f
}
fn assert_original_pending_zero_definitions(f: &Fixture) {
    let db = crate::sqlite::Db::open(f.path.to_str().unwrap(), true, false).unwrap();
    assert_eq!(
        db.query("SELECT COUNT(*) FROM local_bot_definitions", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("0")
    );
    assert_eq!(
        db.query(
            "SELECT status FROM local_bot_definition_intents WHERE intent_id=?",
            &[INTENT]
        )
        .unwrap()[0][0]
            .as_deref(),
        Some("pending")
    );
    assert!(db
        .query(
            "SELECT receipt_json FROM local_bot_definition_intents WHERE intent_id=?",
            &[INTENT]
        )
        .unwrap()[0][0]
        .is_none());
}
#[test]
fn project_deleted_exactly_between_pending_and_effect_must_not_commit() {
    let f = project_fixture();
    let r = prepare_create(f.store(), CONVERSATION, Some("p1"), &f.binding, INTENT).unwrap();
    let result = confirm_create_with_boundary(
        f.store(),
        CONVERSATION,
        Some("p1"),
        INTENT,
        &r.review_digest,
        || {
            sql(f
                .store()
                .database()
                .exec("UPDATE projects SET deleted=1 WHERE id='p1'", &[]))?;
            Ok(())
        },
    );
    assert_eq!(result.unwrap_err(), "bot_query_original");
    assert_original_pending_zero_definitions(&f);
    assert_eq!(
        f.store()
            .database()
            .query("SELECT deleted FROM projects WHERE id='p1'", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
}
fn check_receipt_tail_trigger(body: &str) {
    check_mutation_trigger(body, false)
}
fn check_mutation_trigger(body: &str, after_insert: bool) {
    let f = project_fixture();
    let r = prepare_create(f.store(), CONVERSATION, Some("p1"), &f.binding, INTENT).unwrap();
    let ddl = if after_insert {
        format!(
            "CREATE TRIGGER mutate_tail AFTER INSERT ON local_bot_definitions BEGIN {body}; END"
        )
    } else {
        format!("CREATE TRIGGER mutate_tail AFTER UPDATE OF status ON local_bot_definition_intents WHEN NEW.status='committed' BEGIN {body}; END")
    };
    f.store().database().exec(&ddl, &[]).unwrap();
    let result = confirm_create_trusted(
        f.store(),
        CONVERSATION,
        Some("p1"),
        INTENT,
        &r.review_digest,
    );
    assert_eq!(
        result.unwrap_err(),
        "bot_query_original",
        "tail mutation: {body}"
    );
    assert_original_pending_zero_definitions(&f);
    assert_eq!(
        f.store()
            .database()
            .query("SELECT deleted FROM projects WHERE id='p1'", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("0")
    );
    assert_eq!(
        f.store()
            .database()
            .query(
                "SELECT stored_revision FROM local_bot_drafts WHERE draft_id=?",
                &[&f.binding.draft_id]
            )
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
    assert_eq!(
        f.store()
            .database()
            .query(
                "SELECT owner_epoch FROM local_bot_definition_intents WHERE intent_id=?",
                &[INTENT]
            )
            .unwrap()[0][0]
            .as_deref(),
        Some("epoch1")
    );
    f.store()
        .database()
        .exec("DROP TRIGGER mutate_tail", &[])
        .unwrap();
    assert_eq!(
        lookup_create(f.store(), CONVERSATION, Some("p1"), INTENT)
            .unwrap()
            .status,
        CreateStatus::Unknown
    );
    assert_eq!(
        confirm_create_trusted(
            f.store(),
            CONVERSATION,
            Some("p1"),
            INTENT,
            &r.review_digest
        )
        .unwrap()
        .status,
        CreateStatus::Unknown
    );
    assert!(prepare_create(f.store(), CONVERSATION, Some("p1"), &f.binding, OTHER).is_err());
}
#[test]
fn tail_project_deletion_rolls_back() {
    check_receipt_tail_trigger("UPDATE projects SET deleted=1 WHERE id='p1'");
}
#[test]
fn tail_draft_revision_rolls_back() {
    check_receipt_tail_trigger("UPDATE local_bot_drafts SET stored_revision='2'");
}
#[test]
fn tail_owner_epoch_rolls_back() {
    check_receipt_tail_trigger(
        "UPDATE local_bot_definition_intents SET owner_epoch='changed-epoch'",
    );
}
#[test]
fn tail_workspace_change_rolls_back() {
    check_receipt_tail_trigger("UPDATE meta SET value='changed-workspace' WHERE key='workspace'");
}
#[test]
fn tail_definition_tampering_rolls_back() {
    check_receipt_tail_trigger(
        "UPDATE local_bot_definitions SET definition_json=replace(definition_json,'研究员','篡改')",
    );
}
#[test]
fn tail_definition_identity_tampering_rolls_back() {
    check_receipt_tail_trigger("UPDATE local_bot_definitions SET draft_key='forged'");
}
#[test]
fn tail_receipt_tampering_rolls_back() {
    check_receipt_tail_trigger("UPDATE local_bot_definition_intents SET receipt_json=replace(receipt_json,'committed','unknown')");
}
#[test]
fn tail_intent_identity_tampering_rolls_back() {
    check_receipt_tail_trigger("UPDATE local_bot_definition_intents SET draft_key='forged'");
}

fn save_draft(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    binding: &DraftBinding,
    attempt: &str,
    memory: &str,
    bytes: &[u8],
) -> Result<serde_json::Value> {
    crate::bot_drafts::prepare_save(
        store,
        conversation,
        project,
        binding,
        attempt,
        crate::bot_drafts::SaveRevisions {
            exported_memory_revision: memory,
            host_editor_revision: memory,
        },
        bytes,
    )?;
    crate::bot_drafts::save(
        store,
        conversation,
        project,
        binding,
        attempt,
        memory,
        bytes,
    )
}

#[test]
fn pending_update_project_deletion_cannot_commit_effect() {
    let f = project_fixture();
    let r = prepare_create(f.store(), CONVERSATION, Some("p1"), &f.binding, INTENT).unwrap();
    f.store().database().exec("CREATE TRIGGER revoke_at_pending AFTER UPDATE OF status ON local_bot_definition_intents WHEN NEW.status='pending' BEGIN UPDATE projects SET deleted=1 WHERE id='p1'; END",&[]).unwrap();
    assert!(confirm_create_trusted(
        f.store(),
        CONVERSATION,
        Some("p1"),
        INTENT,
        &r.review_digest
    )
    .is_err());
    assert_original_pending_zero_definitions(&f);
    assert_eq!(
        f.store()
            .database()
            .query("SELECT deleted FROM projects WHERE id='p1'", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
}
#[test]
fn insert_draft_revision_rolls_back() {
    check_mutation_trigger("UPDATE local_bot_drafts SET stored_revision='2'", true);
}
#[test]
fn insert_draft_lifecycle_rolls_back() {
    check_mutation_trigger("UPDATE local_bot_drafts SET lifecycle='invalid'", true);
}
#[test]
fn insert_draft_scope_rolls_back() {
    check_mutation_trigger(
        "UPDATE local_bot_drafts SET scope_key='changed' WHERE project_id='p1'",
        true,
    );
}
#[test]
fn tail_draft_lifecycle_rolls_back() {
    check_receipt_tail_trigger("UPDATE local_bot_drafts SET lifecycle='invalid'");
}
#[test]
fn tail_draft_scope_rolls_back() {
    check_receipt_tail_trigger(
        "UPDATE local_bot_drafts SET scope_key='changed' WHERE project_id='p1'",
    );
}

#[test]
fn tail_original_intent_rename_rolls_back() {
    check_receipt_tail_trigger(
        "UPDATE local_bot_definition_intents SET intent_id='33333333-3333-4333-8333-333333333333'",
    );
}
