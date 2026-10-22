//! Host-only, NEW local-workspace edit drafts. No account, grant, execution or file import.
//! Registry, canonical archive and original save receipt share BusinessStore's transaction.
//! SHA256 detects corruption only; full-database adversarial rollback is out of scope.
use crate::{agent::ReadScope, business::BusinessStore, contract::ContractError};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{fs::File, io::Read};

type Result<T> = std::result::Result<T, &'static str>;
const MAX_ARCHIVE: usize = 32768;
const MAX_DRAFTS: usize = 128;
const MAX_ENCODED: usize = 8 * 1024 * 1024;
const MAX_RECEIPTS: usize = 4096;
const SCHEMA: &[(&str, &str)] = &[
    ("local_bot_draft_meta", "CREATE TABLE local_bot_draft_meta(id INTEGER PRIMARY KEY CHECK(id=1),schema_version TEXT NOT NULL,workspace TEXT NOT NULL,namespace_id TEXT NOT NULL)"),
    ("local_bot_drafts", "CREATE TABLE local_bot_drafts(draft_id TEXT PRIMARY KEY,scope_key TEXT NOT NULL UNIQUE,workspace TEXT NOT NULL,conversation_id TEXT NOT NULL,project_id TEXT,registry_generation TEXT NOT NULL,stored_revision TEXT NOT NULL,lifecycle TEXT NOT NULL,archive_hex TEXT,archive_digest TEXT,CHECK((archive_hex IS NULL)=(archive_digest IS NULL)))"),
    ("local_bot_draft_saves", "CREATE TABLE local_bot_draft_saves(attempt_id TEXT PRIMARY KEY,namespace_id TEXT NOT NULL,draft_id TEXT NOT NULL REFERENCES local_bot_drafts(draft_id),scope_key TEXT NOT NULL,registry_generation TEXT NOT NULL,expected_revision TEXT NOT NULL,stored_revision TEXT NOT NULL,exported_memory_revision TEXT NOT NULL,archive_digest TEXT NOT NULL,receipt_json TEXT NOT NULL)"),
];

#[derive(Clone, Debug)]
pub struct DraftBinding {
    pub namespace_id: String,
    pub draft_id: String,
    pub expected_generation: String,
    pub expected_stored_revision: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Receipt {
    schema: u8,
    owner_kind: String,
    namespace_id: String,
    workspace_id: String,
    conversation_id: String,
    project_id: Option<String>,
    draft_id: String,
    registry_generation: String,
    expected_stored_revision: String,
    stored_revision: String,
    lifecycle: String,
    archive_present: bool,
    attempt_id: String,
    exported_memory_revision: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    host_editor_revision: Option<String>,
    archive_digest: String,
    status: String,
}
struct Record {
    namespace: String,
    draft: String,
    conversation: String,
    project: Option<String>,
    generation: String,
    revision: String,
    archive: Option<String>,
    digest: Option<String>,
}
fn sql<T>(r: crate::sqlite::Result<T>) -> Result<T> {
    r.map_err(|_| "local_draft_storage_unknown")
}
fn cell(row: &[Option<String>], i: usize) -> Result<&str> {
    row.get(i)
        .and_then(Option::as_deref)
        .ok_or("local_draft_corrupt")
}
fn number(s: &str) -> Result<i64> {
    if s.is_empty()
        || s.len() > 19
        || !s.bytes().all(|b| b.is_ascii_digit())
        || (s.len() > 1 && s.starts_with('0'))
    {
        return Err("local_draft_version");
    }
    s.parse().map_err(|_| "local_draft_version")
}
fn uuid(s: &str) -> Result<()> {
    if s.len() != 36
        || !s.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_digit() || (b'a'..=b'f').contains(&b)
            }
        })
        || s == "00000000-0000-0000-0000-000000000000"
    {
        return Err("local_draft_identity");
    }
    Ok(())
}
fn new_uuid() -> Result<String> {
    let mut b = [0u8; 16];
    File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut b))
        .map_err(|_| "local_draft_unavailable")?;
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    let h = hex(&b);
    Ok(format!(
        "{}-{}-{}-{}-{}",
        &h[..8],
        &h[8..12],
        &h[12..16],
        &h[16..20],
        &h[20..]
    ))
}
fn hex(b: &[u8]) -> String {
    b.iter().map(|v| format!("{v:02x}")).collect()
}
fn unhex(s: &str) -> Result<Vec<u8>> {
    if s.len() > 2 * MAX_ARCHIVE
        || !s.len().is_multiple_of(2)
        || !s
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("local_draft_corrupt");
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(|_| "local_draft_corrupt"))
        .collect()
}
fn digest(b: &[u8]) -> String {
    hex(&Sha256::digest(b))
}
/// Structural envelope validation only. Canonical Kotlin restore validates text/template semantics.
/// No serialized field may act as authority, identity or a creation receipt.
fn archive_check(b: &[u8], revision: i64) -> Result<String> {
    if !(67..=MAX_ARCHIVE).contains(&b.len()) || &b[..8] != b"MYBD\0\0\0\x01" {
        return Err("local_draft_archive");
    }
    let payload = &b[..b.len() - 32];
    if Sha256::digest(payload)[..] != b[b.len() - 32..]
        || i64::from_be_bytes(b[8..16].try_into().map_err(|_| "local_draft_archive")?) != revision
    {
        return Err("local_draft_archive");
    }
    // Bound and validate the binary shape, rejecting appended/unknown fields even with a new hash.
    fn text(p: &[u8], pos: &mut usize, max: usize) -> Result<()> {
        let end = pos.checked_add(4).ok_or("local_draft_archive")?;
        let len = i32::from_be_bytes(
            p.get(*pos..end)
                .ok_or("local_draft_archive")?
                .try_into()
                .map_err(|_| "local_draft_archive")?,
        );
        *pos = end;
        let len = usize::try_from(len).map_err(|_| "local_draft_archive")?;
        if len > max * 3 {
            return Err("local_draft_archive");
        }
        let end = pos.checked_add(len).ok_or("local_draft_archive")?;
        let value = std::str::from_utf8(p.get(*pos..end).ok_or("local_draft_archive")?)
            .map_err(|_| "local_draft_archive")?;
        if value.encode_utf16().count() > max {
            return Err("local_draft_archive");
        }
        *pos = end;
        Ok(())
    }
    let mut pos = 16;
    for max in [60, 8000, 160] {
        let flags = payload.get(pos..pos + 2).ok_or("local_draft_archive")?;
        if flags.iter().any(|v| *v > 1) {
            return Err("local_draft_archive");
        }
        pos += 2;
        text(payload, &mut pos, max)?;
    }
    match payload.get(pos) {
        Some(0) => pos += 1,
        Some(1) => {
            pos += 1;
            text(payload, &mut pos, 64)?;
            pos = pos.checked_add(4).ok_or("local_draft_archive")?;
        }
        _ => return Err("local_draft_archive"),
    }
    if pos != payload.len() {
        return Err("local_draft_archive");
    }
    Ok(digest(b))
}
fn scope(store: &BusinessStore, conversation: &str, project: Option<&str>) -> Result<String> {
    uuid(conversation)?;
    ReadScope::current(store, project).map_err(|error| match error {
        ContractError::Storage
        | ContractError::StorageBusy
        | ContractError::StorageConstraint
        | ContractError::StorageCorrupt
        | ContractError::StorageIo
        | ContractError::Unknown => "local_draft_storage_unknown",
        _ => "local_draft_scope",
    })?;
    serde_json::to_string(&(store.workspace_id(), conversation, project))
        .map_err(|_| "local_draft_unavailable")
}
fn schema(store: &BusinessStore, initialize: bool) -> Result<String> {
    let db = store.database();
    let rows=sql(db.query("SELECT name,sql FROM sqlite_master WHERE type='table' AND name GLOB 'local_bot_draft*' ORDER BY name",&[]))?;
    if rows.is_empty() && initialize {
        for (_, ddl) in SCHEMA {
            sql(db.exec(ddl, &[]))?;
        }
        sql(db.exec(
            "INSERT INTO local_bot_draft_meta VALUES(1,'1',?,?)",
            &[store.workspace_id(), &new_uuid()?],
        ))?;
    } else {
        if rows.len() != SCHEMA.len() {
            return Err("local_draft_schema");
        }
        for (name, ddl) in SCHEMA {
            if !rows.iter().any(|r| {
                r.first().and_then(Option::as_deref) == Some(*name)
                    && r.get(1).and_then(Option::as_deref) == Some(*ddl)
            }) {
                return Err("local_draft_schema");
            }
        }
    }
    let rows = sql(db.query(
        "SELECT id,schema_version,workspace,namespace_id FROM local_bot_draft_meta",
        &[],
    ))?;
    if rows.len() != 1
        || cell(&rows[0], 0)? != "1"
        || cell(&rows[0], 1)? != "1"
        || cell(&rows[0], 2)? != store.workspace_id()
    {
        return Err("local_draft_schema");
    }
    let ns = cell(&rows[0], 3)?;
    uuid(ns).map_err(|_| "local_draft_corrupt")?;
    Ok(ns.into())
}
// Preserve SQL NULL before applying byte/type bounds: absent archive is a real new
// draft state, not an oversize value. Refuse SQLite's implicit BLOB-to-text coercion.
fn record(store: &BusinessStore, key: &str, ns: &str) -> Result<Record> {
    let rows=sql(store.database().query("SELECT draft_id,workspace,conversation_id,project_id,registry_generation,stored_revision,lifecycle,CASE WHEN archive_hex IS NULL THEN NULL WHEN typeof(archive_hex)!='text' THEN 'invalid_storage' WHEN LENGTH(CAST(archive_hex AS BLOB))<=65536 THEN archive_hex ELSE 'oversize' END,CASE WHEN archive_digest IS NULL THEN NULL WHEN typeof(archive_digest)='text' AND LENGTH(CAST(archive_digest AS BLOB))=64 THEN archive_digest ELSE 'invalid_storage' END FROM local_bot_drafts WHERE scope_key=?",&[key]))?;
    if rows.len() != 1 {
        return Err("local_draft_scope");
    }
    let r = &rows[0];
    if cell(r, 1)? != store.workspace_id() {
        return Err("local_draft_scope");
    }
    if cell(r, 6)? != "editing_only" {
        return Err("local_draft_lifecycle");
    }
    uuid(cell(r, 0)?).map_err(|_| "local_draft_corrupt")?;
    uuid(cell(r, 2)?).map_err(|_| "local_draft_corrupt")?;
    let gen = cell(r, 4)?;
    let rev = cell(r, 5)?;
    if number(gen)? < 1 {
        return Err("local_draft_corrupt");
    }
    let revision = number(rev)?;
    let rec = Record {
        namespace: ns.into(),
        draft: cell(r, 0)?.into(),
        conversation: cell(r, 2)?.into(),
        project: r[3].clone(),
        generation: gen.into(),
        revision: rev.into(),
        archive: r[7].clone(),
        digest: r[8].clone(),
    };
    let actual = serde_json::to_string(&(store.workspace_id(), &rec.conversation, &rec.project))
        .map_err(|_| "local_draft_corrupt")?;
    if actual != key {
        return Err("local_draft_scope");
    }
    match (&rec.archive, &rec.digest) {
        (None, None) if revision == 0 => {}
        (Some(a), Some(h)) if revision > 0 => {
            if archive_check(&unhex(a)?, revision).map_err(|_| "local_draft_corrupt")? != *h {
                return Err("local_draft_corrupt");
            }
        }
        _ => return Err("local_draft_corrupt"),
    }
    Ok(rec)
}
fn bound(rec: &Record, b: &DraftBinding, version: bool) -> Result<()> {
    uuid(&b.namespace_id)?;
    uuid(&b.draft_id)?;
    if rec.namespace != b.namespace_id || rec.draft != b.draft_id {
        return Err("local_draft_scope");
    }
    number(&b.expected_generation)?;
    number(&b.expected_stored_revision)?;
    if rec.generation != b.expected_generation
        || (version && rec.revision != b.expected_stored_revision)
    {
        return Err("local_draft_version");
    }
    Ok(())
}
fn descriptor(store: &BusinessStore, r: &Record) -> Result<Value> {
    let mut out = json!({"schema":1,"owner_kind":"local_workspace","namespace_id":r.namespace,"workspace_id":store.workspace_id(),"conversation_id":r.conversation,"project_id":r.project,"draft_id":r.draft,"registry_generation":r.generation,"stored_revision":r.revision,"lifecycle":"editing_only","archive_present":r.archive.is_some()});
    out["save_attempt"] =
        serde_json::to_value(journal_pointer(store, r)?).map_err(|_| "local_draft_unavailable")?;
    Ok(out)
}
fn scalar(store: &BusinessStore, query: &str) -> Result<usize> {
    let rows = sql(store.database().query(query, &[]))?;
    cell(rows.first().ok_or("local_draft_corrupt")?, 0)?
        .parse()
        .map_err(|_| "local_draft_corrupt")
}
/// Explicit registration only; never imports legacy files or binds historical unknowns.
pub fn resolve(store: &BusinessStore, conversation: &str, project: Option<&str>) -> Result<Value> {
    let tx = sql(store.database().transaction())?;
    let key = scope(store, conversation, project)?;
    let ns = schema(store, true)?;
    let rows = sql(store.database().query(
        "SELECT draft_id FROM local_bot_drafts WHERE scope_key=?",
        &[&key],
    ))?;
    if rows.is_empty() {
        if scalar(store, "SELECT COUNT(*) FROM local_bot_drafts")? >= MAX_DRAFTS {
            return Err("local_draft_capacity");
        }
        let id = new_uuid()?;
        // NULL and selected project have distinct structured keys and actual SQL values.
        if let Some(p) = project {
            sql(store.database().exec(
                "INSERT INTO local_bot_drafts VALUES(?,?,?,?,?,'1','0','editing_only',NULL,NULL)",
                &[&id, &key, store.workspace_id(), conversation, p],
            ))?;
        } else {
            sql(store.database().exec("INSERT INTO local_bot_drafts VALUES(?,?,?,?,NULL,'1','0','editing_only',NULL,NULL)",&[&id,&key,store.workspace_id(),conversation]))?;
        }
    }
    let r = record(store, &key, &ns)?;
    let out = descriptor(store, &r)?;
    sql(tx.commit())?;
    Ok(out)
}
pub fn read(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    b: &DraftBinding,
) -> Result<Value> {
    let tx = sql(store.database().transaction())?;
    let key = scope(store, conversation, project)?;
    let ns = schema(store, false)?;
    let r = record(store, &key, &ns)?;
    bound(&r, b, true)?;
    let mut out = descriptor(store, &r)?;
    out["status"] = json!(if r.archive.is_some() {
        "stored"
    } else {
        "not_saved"
    });
    out["archive_hex"] = json!(r.archive);
    out["archive_digest"] = json!(r.digest);
    sql(tx.commit())?;
    Ok(out)
}
fn original(
    store: &BusinessStore,
    key: &str,
    r: &Record,
    attempt: &str,
) -> Result<Option<Receipt>> {
    let rows=sql(store.database().query("SELECT namespace_id,draft_id,scope_key,registry_generation,expected_revision,stored_revision,exported_memory_revision,CASE WHEN typeof(archive_digest)='text' AND LENGTH(CAST(archive_digest AS BLOB))=64 THEN archive_digest ELSE 'invalid_storage' END,CASE WHEN typeof(receipt_json)!='text' THEN 'invalid_storage' WHEN LENGTH(CAST(receipt_json AS BLOB))<=4096 THEN receipt_json ELSE 'oversize' END FROM local_bot_draft_saves WHERE attempt_id=?",&[attempt]))?;
    if rows.is_empty() {
        return Ok(None);
    }
    if rows.len() != 1 {
        return Err("local_draft_corrupt");
    }
    let row = &rows[0];
    if cell(row, 0)? != r.namespace
        || cell(row, 1)? != r.draft
        || cell(row, 2)? != key
        || cell(row, 3)? != r.generation
    {
        return Err("local_draft_attempt_conflict");
    }
    let old = number(cell(row, 4)?)?;
    let new = number(cell(row, 5)?)?;
    number(cell(row, 6)?)?;
    let h = cell(row, 7)?;
    if old.checked_add(1) != Some(new)
        || new > number(&r.revision)?
        || h.len() != 64
        || !h
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("local_draft_corrupt");
    }
    let preparation = journal_attempt(store, key, r, attempt)?;
    if let Some(p) = &preparation {
        if p.state != "committed"
            || p.expected_stored_revision != cell(row, 4)?
            || p.next_stored_revision != cell(row, 5)?
            || p.exported_memory_revision != cell(row, 6)?
            || p.archive_digest != h
        {
            return Err("local_draft_corrupt");
        }
    }
    let expected = Receipt {
        schema: 1,
        owner_kind: "local_workspace".into(),
        namespace_id: r.namespace.clone(),
        workspace_id: store.workspace_id().into(),
        conversation_id: r.conversation.clone(),
        project_id: r.project.clone(),
        draft_id: r.draft.clone(),
        registry_generation: r.generation.clone(),
        expected_stored_revision: cell(row, 4)?.into(),
        stored_revision: cell(row, 5)?.into(),
        lifecycle: "editing_only".into(),
        archive_present: true,
        attempt_id: attempt.into(),
        exported_memory_revision: cell(row, 6)?.into(),
        host_editor_revision: preparation.map(|p| p.host_editor_revision),
        archive_digest: h.into(),
        status: "committed_local_storage".into(),
    };
    let raw = cell(row, 8)?;
    if raw.len() > 4096 {
        return Err("local_draft_corrupt");
    }
    let receipt: Receipt = serde_json::from_str(raw).map_err(|_| "local_draft_corrupt")?;
    if receipt != expected {
        return Err("local_draft_corrupt");
    }
    Ok(Some(receipt))
}
/// Same intent is idempotent; a stale CAS with a new attempt never overwrites edits.
/// Any storage/commit error is unknown; query the SAME attempt before deciding its outcome.
pub fn save(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    b: &DraftBinding,
    attempt: &str,
    exported_memory_revision: &str,
    archive: &[u8],
) -> Result<Value> {
    uuid(attempt)?;
    number(exported_memory_revision)?;
    let old = number(&b.expected_stored_revision)?;
    let next = old.checked_add(1).ok_or("local_draft_version")?;
    let h = archive_check(archive, next)?;
    let tx = sql(store.database().transaction())?;
    let key = scope(store, conversation, project)?;
    let ns = schema(store, false)?;
    let r = record(store, &key, &ns)?;
    bound(&r, b, false)?;
    if let Some(receipt) = original(store, &key, &r, attempt)? {
        if receipt.expected_stored_revision != b.expected_stored_revision
            || receipt.exported_memory_revision != exported_memory_revision
            || receipt.archive_digest != h
        {
            return Err("local_draft_attempt_conflict");
        }
        sql(tx.commit())?;
        return serde_json::to_value(receipt).map_err(|_| "local_draft_unavailable");
    }
    bound(&r, b, true)?;
    let preparation =
        journal_attempt(store, &key, &r, attempt)?.ok_or("local_draft_not_prepared")?;
    if preparation.state != "prepared" {
        return Err("local_draft_terminal");
    }
    if preparation.expected_stored_revision != b.expected_stored_revision
        || preparation.exported_memory_revision != exported_memory_revision
        || preparation.archive_digest != h
    {
        return Err("local_draft_attempt_conflict");
    }
    if journal_pointer(store, &r)?.as_ref() != Some(&preparation) {
        return Err("local_draft_corrupt");
    }
    let encoded = hex(archive);
    if scalar(store, "SELECT COUNT(*) FROM local_bot_draft_saves")? >= MAX_RECEIPTS
        || scalar(
            store,
            "SELECT COALESCE(SUM(LENGTH(archive_hex)),0) FROM local_bot_drafts",
        )?
        .checked_sub(r.archive.as_ref().map_or(0, String::len))
        .and_then(|v| v.checked_add(encoded.len()))
        .ok_or("local_draft_corrupt")?
            > MAX_ENCODED
    {
        return Err("local_draft_capacity");
    }
    let next = next.to_string();
    let receipt = Receipt {
        schema: 1,
        owner_kind: "local_workspace".into(),
        namespace_id: r.namespace.clone(),
        workspace_id: store.workspace_id().into(),
        conversation_id: r.conversation.clone(),
        project_id: r.project.clone(),
        draft_id: r.draft.clone(),
        registry_generation: r.generation.clone(),
        expected_stored_revision: b.expected_stored_revision.clone(),
        stored_revision: next.clone(),
        lifecycle: "editing_only".into(),
        archive_present: true,
        attempt_id: attempt.into(),
        exported_memory_revision: exported_memory_revision.into(),
        host_editor_revision: Some(preparation.host_editor_revision.clone()),
        archive_digest: h.clone(),
        status: "committed_local_storage".into(),
    };
    let raw = serde_json::to_string(&receipt).map_err(|_| "local_draft_unavailable")?;
    let changed=sql(store.database().exec("UPDATE local_bot_drafts SET stored_revision=?,archive_hex=?,archive_digest=? WHERE draft_id=? AND registry_generation=? AND stored_revision=? AND lifecycle='editing_only'",&[&next,&encoded,&h,&r.draft,&b.expected_generation,&b.expected_stored_revision]))?;
    if changed != 1 {
        return Err("local_draft_version");
    }
    sql(store.database().exec(
        "INSERT INTO local_bot_draft_saves VALUES(?,?,?,?,?,?,?,?,?,?)",
        &[
            attempt,
            &ns,
            &r.draft,
            &key,
            &r.generation,
            &b.expected_stored_revision,
            &next,
            exported_memory_revision,
            &h,
            &raw,
        ],
    ))?;
    transition_preparation(store, &preparation, "committed")?;
    sql(tx.commit())?;
    serde_json::to_value(receipt).map_err(|_| "local_draft_unavailable")
}
/// Reconcile the exact original outcome. A missing receipt requires an atomic
/// fence of its preparation; this never executes/replays an archive save.
pub fn lookup_save(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    namespace_id: &str,
    draft_id: &str,
    attempt: &str,
) -> Result<Value> {
    uuid(namespace_id)?;
    uuid(draft_id)?;
    uuid(attempt)?;
    let tx = sql(store.database().transaction())?;
    let key = scope(store, conversation, project)?;
    let ns = schema(store, false)?;
    let r = record(store, &key, &ns)?;
    if ns != namespace_id || r.draft != draft_id {
        return Err("local_draft_scope");
    }
    if let Some(receipt) = original(store, &key, &r, attempt)? {
        sql(tx.commit())?;
        return serde_json::to_value(receipt).map_err(|_| "local_draft_unavailable");
    }
    let p = journal_attempt(store, &key, &r, attempt)?.ok_or("local_draft_attempt_not_found")?;
    let terminal = if p.state == "prepared" {
        if journal_pointer(store, &r)?.as_ref() != Some(&p) {
            return Err("local_draft_corrupt");
        }
        // Atomic proof: after this COMMIT, any queued old save is fenced out.
        transition_preparation(store, &p, "not_committed")?
    } else if p.state == "not_committed" {
        p
    } else {
        return Err("local_draft_corrupt");
    };
    let mut out = serde_json::to_value(terminal).map_err(|_| "local_draft_unavailable")?;
    out["status"] = json!("not_committed_local_storage");
    sql(tx.commit())?;
    Ok(out)
}

// This is a separately versioned extension, not a mutation/reset of registry schema1.
const JOURNAL_SCHEMA: &[(&str, &str)] = &[
    ("local_bot_save_attempts_v1", "CREATE TABLE local_bot_save_attempts_v1(attempt_id TEXT PRIMARY KEY,draft_id TEXT NOT NULL REFERENCES local_bot_drafts(draft_id),scope_key TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN('prepared','committed','not_committed')),payload TEXT NOT NULL)"),
    ("local_bot_save_pointer_v1", "CREATE TABLE local_bot_save_pointer_v1(draft_id TEXT PRIMARY KEY REFERENCES local_bot_drafts(draft_id),attempt_id TEXT NOT NULL UNIQUE REFERENCES local_bot_save_attempts_v1(attempt_id))"),
];

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct SavePreparation {
    schema: u8,
    owner_kind: String,
    namespace_id: String,
    workspace_id: String,
    conversation_id: String,
    project_id: Option<String>,
    draft_id: String,
    registry_generation: String,
    attempt_id: String,
    expected_stored_revision: String,
    next_stored_revision: String,
    exported_memory_revision: String,
    host_editor_revision: String,
    archive_digest: String,
    state: String,
}
fn journal_schema(store: &BusinessStore, initialize: bool) -> Result<bool> {
    let rows = sql(store.database().query(
        "SELECT name,sql FROM sqlite_master WHERE type='table' AND name GLOB 'local_bot_save_*' ORDER BY name",
        &[],
    ))?;
    if rows.is_empty() {
        if initialize {
            for (_, ddl) in JOURNAL_SCHEMA {
                sql(store.database().exec(ddl, &[]))?;
            }
        }
        return Ok(initialize);
    }
    if rows.len() != JOURNAL_SCHEMA.len() {
        return Err("local_draft_schema");
    }
    for (name, ddl) in JOURNAL_SCHEMA {
        if !rows.iter().any(|r| {
            r.first().and_then(Option::as_deref) == Some(*name)
                && r.get(1).and_then(Option::as_deref) == Some(*ddl)
        }) {
            return Err("local_draft_schema");
        }
    }
    Ok(true)
}
fn scope_key(store: &BusinessStore, r: &Record) -> Result<String> {
    serde_json::to_string(&(store.workspace_id(), &r.conversation, &r.project))
        .map_err(|_| "local_draft_corrupt")
}
fn journal_attempt(
    store: &BusinessStore,
    key: &str,
    r: &Record,
    attempt: &str,
) -> Result<Option<SavePreparation>> {
    if !journal_schema(store, false)? {
        return Ok(None);
    }
    let rows = sql(store.database().query(
        "SELECT CASE WHEN typeof(draft_id)='text' AND LENGTH(CAST(draft_id AS BLOB))=36 THEN draft_id ELSE NULL END,CASE WHEN typeof(scope_key)='text' AND LENGTH(CAST(scope_key AS BLOB))<=1024 THEN scope_key ELSE NULL END,CASE WHEN typeof(state)='text' AND LENGTH(CAST(state AS BLOB))<=16 THEN state ELSE NULL END,CASE WHEN typeof(payload)='text' AND LENGTH(CAST(payload AS BLOB))<=4096 THEN payload ELSE NULL END FROM local_bot_save_attempts_v1 WHERE attempt_id=?",
        &[attempt],
    ))?;
    if rows.is_empty() {
        return Ok(None);
    }
    if rows.len() != 1 {
        return Err("local_draft_corrupt");
    }
    let row = &rows[0];
    if cell(row, 0)? != r.draft || cell(row, 1)? != key {
        return Err("local_draft_attempt_conflict");
    }
    let p: SavePreparation =
        serde_json::from_str(cell(row, 3)?).map_err(|_| "local_draft_corrupt")?;
    if p.schema != 1
        || p.owner_kind != "local_workspace"
        || p.namespace_id != r.namespace
        || p.workspace_id != store.workspace_id()
        || p.conversation_id != r.conversation
        || p.project_id != r.project
        || p.draft_id != r.draft
        || p.registry_generation != r.generation
        || p.attempt_id != attempt
        || p.state != cell(row, 2)?
        || !["prepared", "committed", "not_committed"].contains(&p.state.as_str())
        || p.archive_digest.len() != 64
        || !p
            .archive_digest
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("local_draft_corrupt");
    }
    uuid(&p.attempt_id).map_err(|_| "local_draft_corrupt")?;
    let base = number(&p.expected_stored_revision)?;
    let next = number(&p.next_stored_revision)?;
    number(&p.exported_memory_revision)?;
    number(&p.host_editor_revision)?;
    if base.checked_add(1) != Some(next)
        || base > number(&r.revision)?
        || (p.state == "prepared" && p.expected_stored_revision != r.revision)
        || (p.state == "committed" && next > number(&r.revision)?)
    {
        return Err("local_draft_corrupt");
    }
    Ok(Some(p))
}
fn journal_pointer(store: &BusinessStore, r: &Record) -> Result<Option<SavePreparation>> {
    if !journal_schema(store, false)? {
        return Ok(None);
    }
    let rows = sql(store.database().query(
        "SELECT CASE WHEN typeof(attempt_id)='text' AND LENGTH(CAST(attempt_id AS BLOB))=36 THEN attempt_id ELSE NULL END FROM local_bot_save_pointer_v1 WHERE draft_id=?",
        &[&r.draft],
    ))?;
    if rows.is_empty() {
        let attempts = sql(store.database().query(
            "SELECT 1 FROM local_bot_save_attempts_v1 WHERE draft_id=? LIMIT 1",
            &[&r.draft],
        ))?;
        if !attempts.is_empty() {
            return Err("local_draft_corrupt");
        }
        return Ok(None);
    }
    if rows.len() != 1 {
        return Err("local_draft_corrupt");
    }
    let attempt = cell(&rows[0], 0)?;
    uuid(attempt).map_err(|_| "local_draft_corrupt")?;
    let key = scope_key(store, r)?;
    let p = journal_attempt(store, &key, r, attempt)
        .map_err(|error| {
            if error == "local_draft_attempt_conflict" {
                "local_draft_corrupt"
            } else {
                error
            }
        })?
        .ok_or("local_draft_corrupt")?;
    let receipt = original(store, &key, r, attempt)?;
    if (p.state == "committed") != receipt.is_some() {
        return Err("local_draft_corrupt");
    }
    Ok(Some(p))
}
fn transition_preparation(
    store: &BusinessStore,
    p: &SavePreparation,
    next_state: &str,
) -> Result<SavePreparation> {
    let mut next = p.clone();
    next.state = next_state.into();
    let payload = serde_json::to_string(&next).map_err(|_| "local_draft_unavailable")?;
    let count = sql(store.database().exec(
        "UPDATE local_bot_save_attempts_v1 SET state=?,payload=? WHERE attempt_id=? AND draft_id=? AND scope_key=? AND state='prepared'",
        &[next_state, &payload, &p.attempt_id, &p.draft_id,
            &serde_json::to_string(&(&p.workspace_id, &p.conversation_id, &p.project_id))
                .map_err(|_| "local_draft_corrupt")?],
    ))?;
    if count != 1 {
        return Err("local_draft_terminal");
    }
    Ok(next)
}
pub struct SaveRevisions<'a> {
    pub exported_memory_revision: &'a str,
    pub host_editor_revision: &'a str,
}
/// Durably bind the original attempt BEFORE dispatch. This does not save/replay edits.
pub fn prepare_save(
    store: &BusinessStore,
    conversation: &str,
    project: Option<&str>,
    b: &DraftBinding,
    attempt: &str,
    revisions: SaveRevisions<'_>,
    archive: &[u8],
) -> Result<Value> {
    let SaveRevisions {
        exported_memory_revision,
        host_editor_revision,
    } = revisions;
    uuid(attempt)?;
    number(exported_memory_revision)?;
    number(host_editor_revision)?;
    let next = number(&b.expected_stored_revision)?
        .checked_add(1)
        .ok_or("local_draft_version")?;
    let h = archive_check(archive, next)?;
    let tx = sql(store.database().transaction())?;
    let key = scope(store, conversation, project)?;
    let ns = schema(store, false)?;
    let r = record(store, &key, &ns)?;
    bound(&r, b, false)?;
    journal_schema(store, true)?;
    let existing = journal_attempt(store, &key, &r, attempt)?;
    let p = SavePreparation {
        schema: 1,
        owner_kind: "local_workspace".into(),
        namespace_id: ns,
        workspace_id: store.workspace_id().into(),
        conversation_id: r.conversation.clone(),
        project_id: r.project.clone(),
        draft_id: r.draft.clone(),
        registry_generation: r.generation.clone(),
        attempt_id: attempt.into(),
        expected_stored_revision: b.expected_stored_revision.clone(),
        next_stored_revision: next.to_string(),
        exported_memory_revision: exported_memory_revision.into(),
        host_editor_revision: host_editor_revision.into(),
        archive_digest: h,
        state: existing
            .as_ref()
            .map_or("prepared", |old| old.state.as_str())
            .into(),
    };
    if let Some(old) = existing {
        if old != p {
            return Err("local_draft_attempt_conflict");
        }
        // Validate persisted terminal receipt as well; no new write on repeat prepare.
        let receipt = original(store, &key, &r, attempt)?;
        if (old.state == "committed") != receipt.is_some() {
            return Err("local_draft_corrupt");
        }
        sql(tx.commit())?;
        return serde_json::to_value(old).map_err(|_| "local_draft_unavailable");
    }
    bound(&r, b, true)?;
    if original(store, &key, &r, attempt)?.is_some() {
        return Err("local_draft_attempt_conflict");
    }
    if journal_pointer(store, &r)?.is_some_and(|old| old.state == "prepared") {
        return Err("local_draft_pending");
    }
    if scalar(store, "SELECT COUNT(*) FROM local_bot_save_attempts_v1")? >= MAX_RECEIPTS
        || scalar(store, "SELECT COUNT(*) FROM local_bot_draft_saves")?
            .checked_add(scalar(
                store,
                "SELECT COUNT(*) FROM local_bot_save_attempts_v1 WHERE state='prepared'",
            )?)
            .ok_or("local_draft_corrupt")?
            >= MAX_RECEIPTS
    {
        return Err("local_draft_capacity");
    }
    let payload = serde_json::to_string(&p).map_err(|_| "local_draft_unavailable")?;
    if payload.len() > 4096 {
        return Err("local_draft_capacity");
    }
    sql(store.database().exec(
        "INSERT INTO local_bot_save_attempts_v1 VALUES(?,?,?,?,?)",
        &[attempt, &r.draft, &key, "prepared", &payload],
    ))?;
    sql(store.database().exec(
        "INSERT INTO local_bot_save_pointer_v1 VALUES(?,?) ON CONFLICT(draft_id) DO UPDATE SET attempt_id=excluded.attempt_id",
        &[&r.draft, attempt],
    ))?;
    sql(tx.commit())?;
    serde_json::to_value(p).map_err(|_| "local_draft_unavailable")
}
