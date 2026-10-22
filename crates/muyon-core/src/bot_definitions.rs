//! Host-only local Bot definitions in the existing BusinessStore connection.
//! Creation registers data only: no provider, credential, execution grant or automatic run.
use crate::{
    agent::ReadScope,
    bot_drafts::{self, DraftBinding},
    business::BusinessStore,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
type Result<T> = std::result::Result<T, &'static str>;
const SCHEMA: &[(&str,&str)] = &[
 ("local_bot_definition_meta","CREATE TABLE local_bot_definition_meta(id INTEGER PRIMARY KEY CHECK(id=1),version TEXT NOT NULL,workspace TEXT NOT NULL)"),
 ("local_bot_definition_intents","CREATE TABLE local_bot_definition_intents(intent_id TEXT PRIMARY KEY,scope_key TEXT NOT NULL,draft_key TEXT NOT NULL,binding_digest TEXT NOT NULL,frozen_json TEXT NOT NULL,owner_epoch TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN('prepared','pending','unknown','committed','rejected')),receipt_json TEXT)"),
 ("local_bot_definitions","CREATE TABLE local_bot_definitions(id TEXT PRIMARY KEY,scope_key TEXT NOT NULL,draft_key TEXT NOT NULL UNIQUE,definition_json TEXT NOT NULL)"),
];
// Exact consumed registry contract from fixed dependency 098d9aca. This is validation,
// not a second registry or schema initializer; a new owner version requires recombination.
const DRAFT_REGISTRY_SCHEMA: &[(&str, &str)] = &[
    ("local_bot_draft_meta", "CREATE TABLE local_bot_draft_meta(id INTEGER PRIMARY KEY CHECK(id=1),schema_version TEXT NOT NULL,workspace TEXT NOT NULL,namespace_id TEXT NOT NULL)"),
    ("local_bot_drafts", "CREATE TABLE local_bot_drafts(draft_id TEXT PRIMARY KEY,scope_key TEXT NOT NULL UNIQUE,workspace TEXT NOT NULL,conversation_id TEXT NOT NULL,project_id TEXT,registry_generation TEXT NOT NULL,stored_revision TEXT NOT NULL,lifecycle TEXT NOT NULL,archive_hex TEXT,archive_digest TEXT,CHECK((archive_hex IS NULL)=(archive_digest IS NULL)))"),
    ("local_bot_draft_saves", "CREATE TABLE local_bot_draft_saves(attempt_id TEXT PRIMARY KEY,namespace_id TEXT NOT NULL,draft_id TEXT NOT NULL REFERENCES local_bot_drafts(draft_id),scope_key TEXT NOT NULL,registry_generation TEXT NOT NULL,expected_revision TEXT NOT NULL,stored_revision TEXT NOT NULL,exported_memory_revision TEXT NOT NULL,archive_digest TEXT NOT NULL,receipt_json TEXT NOT NULL)"),
];
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BotDefinition {
    pub id: String,
    pub name: String,
    pub purpose: String,
    pub role: String,
    pub runnable: bool,
    pub unavailable_reason: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CreateStatus {
    Prepared,
    Unknown,
    Committed,
    Rejected,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateReceipt {
    pub intent_id: String,
    pub review_digest: String,
    pub status: CreateStatus,
    pub definition: Option<BotDefinition>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateReview {
    pub intent_id: String,
    pub review_digest: String,
    pub definition: BotDefinition,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Frozen {
    namespace: String,
    draft: String,
    generation: String,
    revision: String,
    archive_digest: String,
    conversation: String,
    project: Option<String>,
    workspace: String,
    definition: BotDefinition,
}
fn sql<T>(r: crate::sqlite::Result<T>) -> Result<T> {
    r.map_err(|_| "bot_storage_unknown_query_original")
}
fn cell(r: &[Option<String>], n: usize) -> Result<&str> {
    r.get(n).and_then(Option::as_deref).ok_or("bot_corrupt")
}
fn text<T: Serialize>(v: &T) -> Result<String> {
    serde_json::to_string(v).map_err(|_| "bot_payload")
}
fn digest(b: &[u8]) -> String {
    Sha256::digest(b)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
fn identity(s: &str) -> Result<()> {
    if s.len() == 36
        && s.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_digit() || (b'a'..=b'f').contains(&b)
            }
        })
        && s != "00000000-0000-0000-0000-000000000000"
    {
        Ok(())
    } else {
        Err("bot_identity")
    }
}
fn scope(store: &BusinessStore, conversation: &str, project: Option<&str>) -> Result<String> {
    identity(conversation)?;
    let workspace = sql(store
        .database()
        .query("SELECT value FROM meta WHERE key='workspace'", &[]))?;
    let version = sql(store
        .database()
        .query("SELECT value FROM meta WHERE key='schema_version'", &[]))?;
    if workspace.len() != 1
        || cell(&workspace[0], 0)? != store.workspace_id()
        || version.len() != 1
        || cell(&version[0], 0)? != crate::business::STORE_VERSION
    {
        return Err("bot_workspace_changed");
    }
    ReadScope::current(store, project).map_err(|_| "bot_scope")?;
    text(&(store.workspace_id(), conversation, project))
}
fn schema(store: &BusinessStore, initialize: bool) -> Result<()> {
    let db = store.database();
    let rows=sql(db.query("SELECT name,sql FROM sqlite_master WHERE type='table' AND name GLOB 'local_bot_definition*' ORDER BY name",&[]))?;
    if rows.is_empty() && initialize {
        for (_, ddl) in SCHEMA {
            sql(db.exec(ddl, &[]))?;
        }
        sql(db.exec(
            "INSERT INTO local_bot_definition_meta VALUES(1,'1',?)",
            &[store.workspace_id()],
        ))?;
    } else if rows.len() != SCHEMA.len()
        || SCHEMA.iter().any(|(name, ddl)| {
            !rows.iter().any(|r| {
                r.first().and_then(Option::as_deref) == Some(*name)
                    && r.get(1).and_then(Option::as_deref) == Some(*ddl)
            })
        })
    {
        return Err("bot_schema");
    }
    let rows = sql(db.query(
        "SELECT id,version,workspace FROM local_bot_definition_meta",
        &[],
    ))?;
    if rows.len() != 1
        || cell(&rows[0], 0)? != "1"
        || cell(&rows[0], 1)? != "1"
        || cell(&rows[0], 2)? != store.workspace_id()
    {
        return Err("bot_schema");
    }
    Ok(())
}
fn check_text(s: &str, max: usize) -> Result<()> {
    let format = |c: char| matches!(c,'\u{ad}'|'\u{600}'..='\u{605}'|'\u{61c}'|'\u{6dd}'|'\u{70f}'|'\u{890}'..='\u{891}'|'\u{8e2}'|'\u{180e}'|'\u{200b}'..='\u{200f}'|'\u{202a}'..='\u{202e}'|'\u{2060}'..='\u{206f}'|'\u{feff}'|'\u{fff9}'..='\u{fffb}'|'\u{110bd}'|'\u{110cd}'|'\u{13430}'..='\u{1343f}'|'\u{1bca0}'..='\u{1bca3}'|'\u{1d173}'..='\u{1d17a}'|'\u{e0001}'|'\u{e0020}'..='\u{e007f}');
    if s.encode_utf16().count() > max
        || !s.chars().any(|c| !c.is_whitespace())
        || s.chars().any(|c| c.is_control() || format(c))
    {
        Err("bot_payload")
    } else {
        Ok(())
    }
}
fn decode_archive(h: &str, expected_revision: &str) -> Result<(String, String, String, String)> {
    if h.len() > 65536
        || !h.len().is_multiple_of(2)
        || !h
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("bot_archive");
    }
    let b: Vec<u8> = (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16).map_err(|_| "bot_archive"))
        .collect::<Result<_>>()?;
    if b.len() < 67 || &b[..8] != b"MYBD\0\0\0\x01" {
        return Err("bot_archive");
    }
    let p = &b[..b.len() - 32];
    if Sha256::digest(p)[..] != b[b.len() - 32..]
        || i64::from_be_bytes(b[8..16].try_into().map_err(|_| "bot_archive")?).to_string()
            != expected_revision
    {
        return Err("bot_archive");
    }
    fn string(p: &[u8], pos: &mut usize, max: usize) -> Result<String> {
        let raw = p.get(*pos..*pos + 4).ok_or("bot_archive")?;
        *pos += 4;
        let n = i32::from_be_bytes(raw.try_into().map_err(|_| "bot_archive")?);
        let n = usize::try_from(n).map_err(|_| "bot_archive")?;
        if n > max * 3 {
            return Err("bot_archive");
        }
        let s = std::str::from_utf8(p.get(*pos..*pos + n).ok_or("bot_archive")?)
            .map_err(|_| "bot_archive")?
            .to_owned();
        *pos += n;
        check_text(&s, max)?;
        Ok(s)
    }
    let mut pos = 16;
    let mut fields = Vec::new();
    let mut role_template = false;
    for (i, max) in [60, 8000, 160].iter().enumerate() {
        let flags = p.get(pos..pos + 2).ok_or("bot_archive")?;
        pos += 2;
        if !(matches!(flags, [0, 1]) || i == 2 && matches!(flags, [1, 0])) {
            return Err("bot_archive");
        }
        if i == 2 {
            role_template = flags[0] == 1;
        }
        fields.push(string(p, &mut pos, *max)?);
    }
    let flag = *p.get(pos).ok_or("bot_archive")?;
    pos += 1;
    if role_template {
        if flag != 1 {
            return Err("bot_archive");
        }
        let id = string(p, &mut pos, 64)?;
        let v = p.get(pos..pos + 4).ok_or("bot_archive")?;
        pos += 4;
        if v != 1i32.to_be_bytes() {
            return Err("bot_archive");
        }
        let role = match id.as_str() {
            "paper-organizer" => "文献整理助手",
            "supplier-organizer" => "采购资料整理助手",
            "general-organizer" => "通用资料整理助手",
            _ => return Err("bot_archive"),
        };
        if fields[2] != role {
            return Err("bot_archive");
        }
    } else if flag != 0 {
        return Err("bot_archive");
    }
    if pos != p.len() {
        return Err("bot_archive");
    }
    Ok((
        fields[0].clone(),
        fields[1].clone(),
        fields[2].clone(),
        digest(&b),
    ))
}
fn load(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    b: &DraftBinding,
) -> Result<Frozen> {
    // Repeat actual scope checks under the caller's live transaction, including at its tail.
    let key = scope(store, conversation, project)?;
    let rows=sql(store.database().query("SELECT workspace,conversation_id,project_id,registry_generation,stored_revision,lifecycle,CASE WHEN archive_hex IS NULL THEN NULL WHEN typeof(archive_hex)!='text' THEN NULL WHEN LENGTH(CAST(archive_hex AS BLOB))<=65536 THEN archive_hex ELSE NULL END,CASE WHEN typeof(archive_digest)='text' AND LENGTH(CAST(archive_digest AS BLOB))=64 THEN archive_digest ELSE NULL END,scope_key FROM local_bot_drafts WHERE draft_id=? AND typeof(scope_key)='text' AND typeof(workspace)='text' AND typeof(conversation_id)='text' AND (project_id IS NULL OR typeof(project_id)='text') AND typeof(registry_generation)='text' AND typeof(stored_revision)='text' AND typeof(lifecycle)='text'",&[&b.draft_id]))?;
    let actual_schema = sql(store.database().query(
        "SELECT name,sql FROM sqlite_master WHERE type='table' AND name GLOB 'local_bot_draft*'",
        &[],
    ))?;
    if actual_schema.len() != DRAFT_REGISTRY_SCHEMA.len()
        || DRAFT_REGISTRY_SCHEMA.iter().any(|(name, ddl)| {
            !actual_schema.iter().any(|row| {
                row.first().and_then(Option::as_deref) == Some(*name)
                    && row.get(1).and_then(Option::as_deref) == Some(*ddl)
            })
        })
    {
        return Err("bot_source_registry_changed");
    }
    let ns = sql(store.database().query(
        "SELECT id,schema_version,workspace,namespace_id FROM local_bot_draft_meta",
        &[],
    ))?;
    if ns.len() != 1
        || cell(&ns[0], 0)? != "1"
        || cell(&ns[0], 1)? != "1"
        || cell(&ns[0], 2)? != store.workspace_id()
        || cell(&ns[0], 3)? != b.namespace_id
        || rows.len() != 1
    {
        return Err("bot_scope");
    }
    let r = &rows[0];
    if cell(r, 0)? != store.workspace_id()
        || cell(r, 1)? != conversation
        || r[2].as_deref() != project
        || cell(r, 3)? != b.expected_generation
        || cell(r, 4)? != b.expected_stored_revision
        || cell(r, 5)? != "editing_only"
        || cell(r, 8)? != key
    {
        return Err("bot_stale_draft");
    }
    let (name, purpose, role, archive_digest) =
        decode_archive(cell(r, 6)?, &b.expected_stored_revision)?;
    if cell(r, 7)? != archive_digest {
        return Err("bot_archive");
    }
    let draft_key = text(&(&b.namespace_id, &b.draft_id, &b.expected_generation))?;
    Ok(Frozen {
        namespace: b.namespace_id.clone(),
        draft: b.draft_id.clone(),
        generation: b.expected_generation.clone(),
        revision: b.expected_stored_revision.clone(),
        archive_digest,
        conversation: conversation.into(),
        project: project.map(str::to_owned),
        workspace: store.workspace_id().into(),
        definition: BotDefinition {
            id: format!("bot-{}", digest(draft_key.as_bytes())),
            name,
            purpose,
            role,
            runnable: false,
            unavailable_reason: "provider_not_configured".into(),
        },
    })
}
fn binding(f: &Frozen) -> DraftBinding {
    DraftBinding {
        namespace_id: f.namespace.clone(),
        draft_id: f.draft.clone(),
        expected_generation: f.generation.clone(),
        expected_stored_revision: f.revision.clone(),
    }
}
fn draft_key(f: &Frozen) -> Result<String> {
    text(&(&f.namespace, &f.draft, &f.generation))
}
struct Intent {
    frozen: Frozen,
    digest: String,
    epoch: String,
    status: String,
    receipt: Option<String>,
}
fn intent(store: &BusinessStore, key: &str, id: &str) -> Result<Intent> {
    identity(id)?;
    let rows=sql(store.database().query("SELECT scope_key,binding_digest,CASE WHEN LENGTH(CAST(frozen_json AS BLOB))<=32768 THEN frozen_json ELSE NULL END,owner_epoch,status,CASE WHEN LENGTH(CAST(receipt_json AS BLOB))<=32768 THEN receipt_json ELSE NULL END,draft_key FROM local_bot_definition_intents WHERE intent_id=? AND typeof(intent_id)='text' AND typeof(scope_key)='text' AND typeof(draft_key)='text' AND typeof(binding_digest)='text' AND typeof(frozen_json)='text' AND typeof(owner_epoch)='text' AND typeof(status)='text' AND (receipt_json IS NULL OR typeof(receipt_json)='text')",&[id]))?;
    if rows.len() != 1 {
        return Err("bot_intent_not_found");
    }
    let r = &rows[0];
    if cell(r, 0)? != key {
        return Err("bot_scope");
    }
    let frozen: Frozen = serde_json::from_str(cell(r, 2)?).map_err(|_| "bot_corrupt")?;
    let h = digest(text(&frozen)?.as_bytes());
    if h != cell(r, 1)?
        || text(&(&frozen.workspace, &frozen.conversation, &frozen.project))? != key
        || cell(r, 6)? != draft_key(&frozen)?
    {
        return Err("bot_corrupt");
    }
    Ok(Intent {
        frozen,
        digest: h,
        epoch: cell(r, 3)?.into(),
        status: cell(r, 4)?.into(),
        receipt: r[5].clone(),
    })
}
fn projection(store: &BusinessStore, id: &str, i: &Intent) -> Result<CreateReceipt> {
    let status = match i.status.as_str() {
        "prepared" => CreateStatus::Prepared,
        "pending" | "unknown" => CreateStatus::Unknown,
        "committed" => CreateStatus::Committed,
        "rejected" => CreateStatus::Rejected,
        _ => return Err("bot_corrupt"),
    };
    let expected = CreateReceipt {
        intent_id: id.into(),
        review_digest: i.digest.clone(),
        status: status.clone(),
        definition: if status == CreateStatus::Committed {
            Some(i.frozen.definition.clone())
        } else {
            None
        },
    };
    if status == CreateStatus::Committed {
        let actual: CreateReceipt =
            serde_json::from_str(i.receipt.as_deref().ok_or("bot_corrupt")?)
                .map_err(|_| "bot_corrupt")?;
        if actual != expected
            || get_inner(
                store,
                &scope(store, &i.frozen.conversation, i.frozen.project.as_deref())?,
                &i.frozen.definition.id,
            )? != i.frozen.definition
        {
            return Err("bot_corrupt");
        }
    } else if i.receipt.is_some() {
        return Err("bot_corrupt");
    }
    Ok(expected)
}
// Re-read persisted authority/identity, not just the caller's in-memory scope or receipt.
// Must be called within the effect transaction before effects AND after its last write.
fn verify_current(
    store: &BusinessStore,
    key: &str,
    id: &str,
    original: &Intent,
    status: &str,
    receipt: Option<&CreateReceipt>,
) -> Result<()> {
    schema(store, false)?;
    let current = intent(store, key, id)?;
    if current.frozen != original.frozen
        || current.digest != original.digest
        || current.epoch != original.epoch
        || current.epoch != store.owner_epoch()
        || current.status != status
    {
        return Err("bot_query_original");
    }
    if scope(
        store,
        &original.frozen.conversation,
        original.frozen.project.as_deref(),
    )? != key
        || load(
            store,
            &original.frozen.conversation,
            original.frozen.project.as_deref(),
            &binding(&original.frozen),
        )? != original.frozen
    {
        return Err("bot_query_original");
    }
    if let Some(expected) = receipt {
        if current.receipt.as_deref() != Some(text(expected)?.as_str())
            || projection(store, id, &current)? != *expected
        {
            return Err("bot_query_original");
        }
        let rows = sql(store.database().query(
            "SELECT scope_key,draft_key,definition_json FROM local_bot_definitions WHERE id=? AND typeof(scope_key)='text' AND typeof(draft_key)='text' AND typeof(definition_json)='text'",
            &[&original.frozen.definition.id],
        ))?;
        if rows.len() != 1
            || cell(&rows[0], 0)? != key
            || cell(&rows[0], 1)? != draft_key(&original.frozen)?
            || cell(&rows[0], 2)? != text(&original.frozen.definition)?
        {
            return Err("bot_query_original");
        }
    } else if current.receipt.is_some() {
        return Err("bot_query_original");
    }
    Ok(())
}

/// Creates only a durable review. Host must display its exact fields and keep the original intent.
pub fn prepare_create(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    b: &DraftBinding,
    id: &str,
) -> Result<CreateReview> {
    identity(id)?;
    bot_drafts::read(store, conversation, project, b)?;
    let tx = sql(store.database().transaction())?;
    let key = scope(store, conversation, project)?;
    schema(store, true)?;
    let f = load(store, conversation, project, b)?;
    let h = digest(text(&f)?.as_bytes());
    let dk = draft_key(&f)?;
    let old = sql(store.database().query(
        "SELECT intent_id FROM local_bot_definition_intents WHERE intent_id=?",
        &[id],
    ))?;
    if !old.is_empty() {
        let i = intent(store, &key, id)?;
        if i.frozen != f || i.status != "prepared" {
            return Err("bot_intent_conflict");
        }
    } else {
        let active=sql(store.database().query("SELECT intent_id FROM local_bot_definition_intents WHERE draft_key=? AND status!='rejected' LIMIT 1",&[&dk]))?;
        if !active.is_empty() {
            return Err("bot_original_intent_required");
        }
        let count = sql(store
            .database()
            .query("SELECT COUNT(*) FROM local_bot_definition_intents", &[]))?;
        if cell(&count[0], 0)?
            .parse::<usize>()
            .map_err(|_| "bot_corrupt")?
            >= 4096
        {
            return Err("bot_capacity");
        }
        sql(store.database().exec(
            "INSERT INTO local_bot_definition_intents VALUES(?,?,?,?,?,?,'prepared',NULL)",
            &[id, &key, &dk, &h, &text(&f)?, store.owner_epoch()],
        ))?;
    }
    sql(tx.commit())?;
    Ok(CreateReview {
        intent_id: id.into(),
        review_digest: h,
        definition: f.definition,
    })
}
/// HOST ONLY after explicit current review confirmation. No model-controlled dispatch or grants.
pub fn confirm_create_trusted(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    id: &str,
    review_digest: &str,
) -> Result<CreateReceipt> {
    confirm_create_with_boundary(store, conversation, project, id, review_digest, || Ok(()))
}

// Private deterministic test seam at the real durable pending/effect boundary.
fn confirm_create_with_boundary(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    id: &str,
    review_digest: &str,
    after_pending: impl FnOnce() -> Result<()>,
) -> Result<CreateReceipt> {
    let key = scope(store, conversation, project)?;
    let original = {
        let tx = sql(store.database().transaction())?;
        schema(store, false)?;
        let i = intent(store, &key, id)?;
        if i.digest != review_digest {
            return Err("bot_review_changed");
        }
        if i.status != "prepared" {
            if i.status == "rejected" {
                return Err("bot_rejected");
            }
            return projection(store, id, &i);
        }
        if i.epoch != store.owner_epoch() {
            return Err("bot_old_owner_query_original");
        }
        verify_current(store, &key, id, &i, "prepared", None)?;
        sql(store.database().exec("UPDATE local_bot_definition_intents SET status='pending' WHERE intent_id=? AND status='prepared'",&[id]))?;
        sql(tx.commit())?; // durable pending before effect; any uncertainty requires original lookup
        i
    };
    let outcome = (|| {
        after_pending()?;
        let tx = sql(store.database().transaction())?;
        let i = intent(store, &key, id)?;
        verify_current(store, &key, id, &original, "pending", None)?;
        let receipt = CreateReceipt {
            intent_id: id.into(),
            review_digest: i.digest.clone(),
            status: CreateStatus::Committed,
            definition: Some(i.frozen.definition.clone()),
        };
        sql(store.database().exec(
            "INSERT INTO local_bot_definitions VALUES(?,?,?,?)",
            &[
                &i.frozen.definition.id,
                &key,
                &draft_key(&i.frozen)?,
                &text(&i.frozen.definition)?,
            ],
        ))?;
        if sql(store.database().exec("UPDATE local_bot_definition_intents SET status='committed',receipt_json=? WHERE intent_id=? AND status='pending'",&[&text(&receipt)?,id]))?!=1{return Err("bot_query_original");}
        // SQL triggers can mutate scope/CAS/epoch/identity/receipt during either write.
        // This is the last fallible semantic check before COMMIT; any refusal rolls back both writes.
        verify_current(store, &key, id, &original, "committed", Some(&receipt))?;
        sql(tx.commit())?;
        Ok(receipt)
    })();
    outcome.map_err(|_| "bot_query_original")
}
/// Local recovery only; never resubmits pending effects or unlocks unknown with an archive.
pub fn recover_previous_owner(store: &BusinessStore) -> Result<()> {
    let tx = sql(store.database().transaction())?;
    schema(store, false)?;
    sql(store.database().exec("UPDATE local_bot_definition_intents SET status='unknown' WHERE status='pending' AND owner_epoch!=?",&[store.owner_epoch()]))?;
    sql(store.database().exec("UPDATE local_bot_definition_intents SET status='rejected' WHERE status='prepared' AND owner_epoch!=?",&[store.owner_epoch()]))?;
    sql(tx.commit())
}
pub fn cancel_prepared(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    id: &str,
) -> Result<()> {
    let tx = sql(store.database().transaction())?;
    let key = scope(store, conversation, project)?;
    schema(store, false)?;
    let i = intent(store, &key, id)?;
    if i.status != "prepared" {
        return Err("bot_cannot_cancel");
    }
    sql(store.database().exec("UPDATE local_bot_definition_intents SET status='rejected' WHERE intent_id=? AND status='prepared'",&[id]))?;
    sql(tx.commit())
}
pub fn lookup_create(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    id: &str,
) -> Result<CreateReceipt> {
    let tx = sql(store.database().transaction())?;
    let key = scope(store, conversation, project)?;
    schema(store, false)?;
    let out = projection(store, id, &intent(store, &key, id)?)?;
    sql(tx.commit())?;
    Ok(out)
}
fn get_inner(store: &BusinessStore, key: &str, id: &str) -> Result<BotDefinition> {
    let rows=sql(store.database().query("SELECT CASE WHEN LENGTH(CAST(definition_json AS BLOB))<=32768 THEN definition_json ELSE NULL END FROM local_bot_definitions WHERE id=? AND scope_key=? AND typeof(definition_json)='text' AND typeof(draft_key)='text' ",&[id,key]))?;
    if rows.len() != 1 {
        return Err("bot_not_found");
    }
    let d: BotDefinition = serde_json::from_str(cell(&rows[0], 0)?).map_err(|_| "bot_corrupt")?;
    check_text(&d.name, 60)?;
    check_text(&d.purpose, 8000)?;
    check_text(&d.role, 160)?;
    if d.id != id || d.runnable || d.unavailable_reason != "provider_not_configured" {
        return Err("bot_corrupt");
    }
    Ok(d)
}
pub fn get(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    id: &str,
) -> Result<BotDefinition> {
    let tx = sql(store.database().transaction())?;
    let key = scope(store, conversation, project)?;
    schema(store, false)?;
    let d = get_inner(store, &key, id)?;
    sql(tx.commit())?;
    Ok(d)
}
pub fn list(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
) -> Result<Vec<BotDefinition>> {
    let tx = sql(store.database().transaction())?;
    let key = scope(store, conversation, project)?;
    // First explicit local visit may initialize only this feature's tables, never legacy data.
    schema(store, true)?;
    let rows = sql(store.database().query(
        "SELECT id FROM local_bot_definitions WHERE scope_key=? ORDER BY id LIMIT 129",
        &[&key],
    ))?;
    if rows.len() > 128 {
        return Err("bot_capacity");
    }
    let out = rows
        .iter()
        .map(|r| get_inner(store, &key, cell(r, 0)?))
        .collect::<Result<_>>()?;
    sql(tx.commit())?;
    Ok(out)
}
#[cfg(test)]
#[path = "bot_definitions/tests.rs"]
mod tests;
