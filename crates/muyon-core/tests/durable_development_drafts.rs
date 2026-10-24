use muyon_core::{
    contract::*,
    development_drafts::*,
    services::{draft_store::DraftStore, drafts::*, types::*},
    sqlite::Db,
};
use serde_json::json;
use std::{
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};

static NEXT: AtomicU64 = AtomicU64::new(0);
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "muyon-durable-drafts-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn path(&self) -> PathBuf {
        self.0.join("drafts.sqlite")
    }
    fn init(&self) -> DraftStore {
        DraftStore::initialize(&self.path(), &scope()).unwrap();
        self.open()
    }
    fn open(&self) -> DraftStore {
        DraftStore::open_existing(&self.path(), &scope()).unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn scope() -> ScopeRef {
    ScopeRef {
        scope: Scope {
            workspace_id: "workspace:one".into(),
            project_id: None,
        },
        account_id: Some("account:one".into()),
        scope_generation: Revision::new(1),
    }
}
fn intent(id: &str) -> IntentId {
    IntentId::parse(id).unwrap()
}
fn envelope() -> DraftEnvelope {
    DraftEnvelope {
        draft_ref: DraftRef {
            owner_plugin_id: OWNER_PLUGIN_ID.into(),
            draft_id: "draft:one".into(),
            scope: scope(),
            revision: Revision::new(0),
        },
        schema_version: 1,
        content: json!({"note":"保留原文"}),
    }
}
fn draft() -> ConversationDraft {
    let mut draft =
        ConversationDraft::new(envelope().draft_ref, "conversation:one".into()).unwrap();
    draft
        .apply(
            &Revision::new(0),
            DraftPatch {
                project_name: Some("项目一".into()),
                items: vec![],
            },
            true,
        )
        .unwrap();
    draft
        .choose_project(&draft.revision().clone(), "project:one".into(), true)
        .unwrap();
    draft
}
fn command() -> CommandEnvelope {
    let mut command = CommandEnvelope {
        protocol_version: 1,
        business_version: 1,
        intent_id: "intent:project".into(),
        scope: scope().scope,
        expected_revision: Revision::new(0),
        authority: AuthorityBinding {
            grant_id: "grant:one".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch:one".into(),
        },
        plan_id: "plan:one".into(),
        plan_digest: "a".repeat(64),
        command: Operation::ProjectCreate {
            project_id: "project:one".into(),
            name: "项目一".into(),
        },
    };
    command.plan_digest = command.expected_plan_digest().unwrap();
    command
}
#[test]
fn actual_database_reopen_preserves_draft_and_original_save_ack() {
    let f = Fixture::new();
    let store = f.init();
    let before = envelope();
    let ack = store.save(&before, &intent("save:one")).unwrap();
    validate_save_ack(&before, &Revision::new(0), &intent("save:one"), &ack).unwrap();
    drop(store);
    let store = f.open();
    let saved = store.load(OWNER_PLUGIN_ID, "draft:one").unwrap().unwrap();
    assert_eq!(saved.content, before.content);
    assert_eq!(saved.draft_ref.revision, Revision::new(1));
    assert_eq!(
        store
            .lookup_save(&before.draft_ref, &intent("save:one"))
            .unwrap(),
        Some(ack.clone())
    );
    assert_eq!(store.save(&before, &intent("save:one")).unwrap(), ack);
    assert_eq!(
        store.load(OWNER_PLUGIN_ID, "draft:one").unwrap().unwrap(),
        saved
    );
}
#[test]
fn conflicting_connection_and_reused_intent_do_not_overwrite() {
    let f = Fixture::new();
    let a = f.init();
    let b = f.open();
    let before = envelope();
    let ack = a.save(&before, &intent("save:one")).unwrap();
    let mut other = before.clone();
    other.content = json!({"note":"另一个编辑器"});
    assert_eq!(
        b.save(&other, &intent("save:two")),
        Err(ContractError::RevisionConflict)
    );
    assert_eq!(
        b.save(&other, &intent("save:one")),
        Err(ContractError::IntentConflict)
    );
    other.draft_ref = ack.draft_ref;
    b.save(&other, &intent("save:two")).unwrap();
    // Retrying an older successful request returns its historical ack, never rolls back.
    a.save(&before, &intent("save:one")).unwrap();
    let saved = a.load(OWNER_PLUGIN_ID, "draft:one").unwrap().unwrap();
    assert_eq!(saved.content, other.content);
    assert_eq!(saved.draft_ref.revision, Revision::new(2));
}
#[test]
fn plugin_namespace_and_scope_are_isolated() {
    let f = Fixture::new();
    let store = f.init();
    let first = envelope();
    store.save(&first, &intent("save:one")).unwrap();
    let mut second = envelope();
    second.draft_ref.owner_plugin_id = "research".into();
    second.content = json!({"different":true});
    store.save(&second, &intent("save:two")).unwrap();
    assert_eq!(
        store
            .load("research", "draft:one")
            .unwrap()
            .unwrap()
            .content,
        second.content
    );
    assert_eq!(
        store
            .load(OWNER_PLUGIN_ID, "draft:one")
            .unwrap()
            .unwrap()
            .content,
        first.content
    );
    for field in 0..4 {
        let mut changed = scope();
        match field {
            0 => changed.account_id = Some("account:other".into()),
            1 => changed.scope.workspace_id = "workspace:other".into(),
            2 => changed.scope.project_id = Some("project:other".into()),
            _ => changed.scope_generation = Revision::new(2),
        }
        assert!(matches!(
            DraftStore::open_existing(&f.path(), &changed),
            Err(ContractError::ScopeMismatch)
        ));
        let mut input = envelope();
        input.draft_ref.scope = changed;
        assert_eq!(
            store.save(&input, &intent("save:bad")),
            Err(ContractError::ScopeMismatch)
        );
    }
    assert!(store
        .lookup_save(&second.draft_ref, &intent("save:one"))
        .is_err());
}
#[test]
fn rejects_existing_partial_or_future_schema_without_replacing_files() {
    let f = Fixture::new();
    let store = f.init();
    drop(store);
    assert!(DraftStore::initialize(&f.path(), &scope()).is_err());
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    db.exec("UPDATE draft_meta SET value='2' WHERE key='version'", &[])
        .unwrap();
    assert!(matches!(
        DraftStore::open_existing(&f.path(), &scope()),
        Err(ContractError::InvalidVersion)
    ));
    let missing = f.0.join("missing.sqlite");
    assert!(DraftStore::open_existing(&missing, &scope()).is_err());
    assert!(!missing.exists());
}
#[test]
fn unrecognized_schema_objects_do_not_run_during_a_save() {
    let f = Fixture::new();
    drop(f.init());
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    db.exec("CREATE TRIGGER sqliteXunexpected AFTER INSERT ON plugin_drafts BEGIN DELETE FROM draft_save_intents; END", &[]).unwrap();
    assert!(matches!(
        DraftStore::open_existing(&f.path(), &scope()),
        Err(ContractError::InvalidVersion)
    ));
}
#[test]
fn invalid_or_oversized_envelope_creates_no_save_ack() {
    let f = Fixture::new();
    let store = f.init();
    let mut input = envelope();
    input.schema_version = 2;
    assert_eq!(
        store.save(&input, &intent("save:bad")),
        Err(ContractError::InvalidVersion)
    );
    input.schema_version = 1;
    input.content = json!({"large":"x".repeat(MAX_COMMAND_BYTES)});
    assert_eq!(
        store.save(&input, &intent("save:bad")),
        Err(ContractError::RawLimit)
    );
    assert_eq!(
        store
            .lookup_save(&envelope().draft_ref, &intent("save:bad"))
            .unwrap(),
        None
    );
    assert_eq!(store.load(OWNER_PLUGIN_ID, "draft:one").unwrap(), None);
}
#[test]
fn development_save_keeps_editor_revision_and_recovers_original_content() {
    let f = Fixture::new();
    let store = f.init();
    let mut draft = draft();
    let editor_revision = draft.revision().clone();
    draft.persist(&store, &intent("save:one")).unwrap();
    assert_eq!(draft.revision(), &editor_revision);
    assert_eq!(draft.stored_revision(), &Revision::new(1));
    drop(store);
    assert_eq!(
        ConversationDraft::load_persisted(&f.open(), "draft:one").unwrap(),
        Some(draft)
    );
}
#[test]
fn failed_marker_save_does_not_return_a_dispatch_or_change_editor() {
    let f = Fixture::new();
    let store = f.init();
    let mut draft = draft();
    draft
        .prepare_project(&draft.revision().clone(), command())
        .unwrap();
    let before = draft.clone();
    // An editor with the same baseline wins first.
    before
        .clone()
        .persist(&store, &intent("save:other"))
        .unwrap();
    assert_eq!(
        draft.begin_persisted_project_dispatch(&store, &intent("save:marker")),
        Err(ContractError::RevisionConflict)
    );
    assert_eq!(draft, before);
    assert_eq!(
        store
            .lookup_save(&draft.envelope().unwrap().draft_ref, &intent("save:marker"))
            .unwrap(),
        None
    );
}
struct LookupOnly {
    count: usize,
}
impl ProjectHost for LookupOnly {
    fn query_original(&mut self, command: &CommandEnvelope) -> ExecutionResult {
        assert_eq!(command.intent_id, "intent:project");
        self.count += 1;
        ExecutionResult {
            status: ExecutionStatus::Unknown,
            receipt: None,
            error: Some(ContractError::Unknown),
            recovery_action: RecoveryAction::QueryOriginal,
        }
    }
}
#[test]
fn stale_editor_replaying_marker_ack_can_only_query_original() {
    let f = Fixture::new();
    let store = f.init();
    let mut first = draft();
    first
        .prepare_project(&first.revision().clone(), command())
        .unwrap();
    let mut stale = first.clone();
    assert_eq!(
        first
            .begin_persisted_project_dispatch(&store, &intent("save:marker"))
            .unwrap(),
        command()
    );
    assert_eq!(
        stale.begin_persisted_project_dispatch(&store, &intent("save:marker")),
        Err(ContractError::IntentConflict)
    );
    let mut host = LookupOnly { count: 0 };
    stale.recover_project(&mut host).unwrap();
    assert_eq!(host.count, 1);
    assert_eq!(
        stale.begin_project_dispatch(),
        Err(ContractError::IntentConflict)
    );
}
#[test]
fn child_commits_marker_then_exits_without_dispatch() {
    let Ok(path) = std::env::var("MUYON_DRAFT_CRASH_TEST_PATH") else {
        return;
    };
    let store = DraftStore::open_existing(std::path::Path::new(&path), &scope()).unwrap();
    let mut draft = draft();
    draft
        .prepare_project(&draft.revision().clone(), command())
        .unwrap();
    assert_eq!(
        draft
            .begin_persisted_project_dispatch(&store, &intent("save:marker"))
            .unwrap(),
        command()
    );
    std::process::exit(0);
}
#[test]
fn committed_marker_survives_process_exit_and_recovery_only_queries() {
    let f = Fixture::new();
    drop(f.init());
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "child_commits_marker_then_exits_without_dispatch",
            "--nocapture",
        ])
        .env("MUYON_DRAFT_CRASH_TEST_PATH", f.path())
        .status()
        .unwrap();
    assert!(status.success());
    let store = f.open();
    let mut restored = ConversationDraft::load_persisted(&store, "draft:one")
        .unwrap()
        .unwrap();
    assert_eq!(
        restored.begin_persisted_project_dispatch(&store, &intent("save:again")),
        Err(ContractError::IntentConflict)
    );
    let mut host = LookupOnly { count: 0 };
    restored.recover_project(&mut host).unwrap();
    restored.recover_project(&mut host).unwrap();
    assert_eq!(host.count, 2);
    assert!(store
        .lookup_save(&envelope().draft_ref, &intent("save:again"))
        .unwrap()
        .is_none());
}
