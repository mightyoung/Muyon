//! Synthetic data only. The host must separately test canonical Kotlin codec semantics.
use muyon_core::{bot_drafts::*, business::BusinessStore, sqlite::Db};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicUsize, Ordering},
};
static NEXT: AtomicUsize = AtomicUsize::new(0);
const C: &str = "12345678-1234-4234-8234-123456789abc";
const A: &str = "22345678-1234-4234-8234-123456789abc";
const B: &str = "32345678-1234-4234-8234-123456789abc";
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "bot-drafts-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&p).unwrap();
        BusinessStore::initialize(&p.join("business.sqlite"), "workspace").unwrap();
        Self(p)
    }
    fn open(&self) -> BusinessStore {
        BusinessStore::open_existing(&self.0.join("business.sqlite"), "workspace", "epoch").unwrap()
    }
    fn db(&self) -> Db {
        Db::open(
            self.0.join("business.sqlite").to_str().unwrap(),
            false,
            false,
        )
        .unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn archive(rev: i64) -> Vec<u8> {
    let mut b = b"MYBD\0\0\0\x01".to_vec();
    b.extend(rev.to_be_bytes());
    for _ in 0..3 {
        b.extend([0u8; 6]);
    }
    b.push(0);
    let hash = Sha256::digest(&b);
    b.extend_from_slice(&hash);
    b
}
fn binding(v: &Value) -> DraftBinding {
    DraftBinding {
        namespace_id: v["namespace_id"].as_str().unwrap().into(),
        draft_id: v["draft_id"].as_str().unwrap().into(),
        expected_generation: v["registry_generation"].as_str().unwrap().into(),
        expected_stored_revision: v["stored_revision"].as_str().unwrap().into(),
    }
}
#[test]
fn restart_and_null_project_are_real_registry_facts() {
    let f = Fixture::new();
    let s = f.open();
    let d = resolve(&s, C, None).unwrap();
    assert_eq!(d["archive_present"], false);
    assert_eq!(d["stored_revision"], "0");
    assert_eq!(d["owner_kind"], "local_workspace");
    drop(s);
    let s = f.open();
    assert_eq!(resolve(&s, C, None).unwrap(), d);
    assert!(resolve(&s, "legacy-conversation", None).is_err());
    assert!(resolve(&s, C, Some("missing")).is_err());
}
#[test]
fn original_receipt_is_atomic_idempotent_and_survives_callback_loss() {
    let f = Fixture::new();
    let s = f.open();
    let d = resolve(&s, C, None).unwrap();
    let b = binding(&d);
    let r = save(&s, C, None, &b, A, "17", &archive(1)).unwrap();
    assert_eq!(r["exported_memory_revision"], "17");
    assert_eq!(r["stored_revision"], "1");
    assert_eq!(save(&s, C, None, &b, A, "17", &archive(1)).unwrap(), r);
    assert!(save(&s, C, None, &b, A, "18", &archive(1)).is_err());
    assert!(save(&s, C, None, &b, B, "17", &archive(1)).is_err());
    assert!(read(&s, C, None, &b).is_err());
    drop(s);
    let s = f.open();
    assert_eq!(
        lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).unwrap(),
        r
    );
    let d = resolve(&s, C, None).unwrap();
    let b = binding(&d);
    let loaded = read(&s, C, None, &b).unwrap();
    assert_eq!(loaded["status"], "stored");
    assert!(loaded.get("saved").is_none());
    save(&s, C, None, &b, B, "18", &archive(2)).unwrap();
    assert_eq!(
        lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).unwrap(),
        r
    );
}
#[test]
fn wrong_scope_binding_generation_lifecycle_and_missing_attempt_refuse() {
    let f = Fixture::new();
    let s = f.open();
    let d = resolve(&s, C, None).unwrap();
    let mut b = binding(&d);
    assert!(read(&s, A, None, &b).is_err());
    assert!(lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).is_err());
    b.expected_generation = "2".into();
    assert!(read(&s, C, None, &b).is_err());
    b = binding(&d);
    b.namespace_id = A.into();
    assert!(read(&s, C, None, &b).is_err());
    b = binding(&d);
    b.draft_id = A.into();
    assert!(read(&s, C, None, &b).is_err());
    f.db()
        .exec("UPDATE local_bot_drafts SET lifecycle='pending'", &[])
        .unwrap();
    assert!(resolve(&s, C, None).is_err());
    assert!(read(&s, C, None, &binding(&d)).is_err());
}
#[test]
fn canonical_envelope_tamper_limit_revision_and_trailing_data_refuse() {
    let f = Fixture::new();
    let s = f.open();
    let b = binding(&resolve(&s, C, None).unwrap());
    let mut bad = archive(1);
    bad[16] ^= 1;
    for bytes in [bad, vec![0; 32769], archive(0), archive(-1), vec![0; 67]] {
        assert!(save(&s, C, None, &b, A, "0", &bytes).is_err());
    }
    assert!(save(&s, C, None, &b, A, "01", &archive(1)).is_err());
    assert!(save(&s, C, None, &b, A, "9223372036854775808", &archive(1)).is_err());
    assert_eq!(resolve(&s, C, None).unwrap()["stored_revision"], "0");
}
#[test]
fn failed_receipt_insert_rolls_back_archive_revision_and_attempt() {
    let f = Fixture::new();
    let s = f.open();
    let b = binding(&resolve(&s, C, None).unwrap());
    f.db().exec("CREATE TRIGGER reject_save BEFORE INSERT ON local_bot_draft_saves BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",&[]).unwrap();
    assert!(save(&s, C, None, &b, A, "0", &archive(1)).is_err());
    assert_eq!(resolve(&s, C, None).unwrap()["stored_revision"], "0");
    assert!(lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).is_err());
    f.db().exec("DROP TRIGGER reject_save", &[]).unwrap();
    save(&s, C, None, &b, A, "0", &archive(1)).unwrap();
}
#[test]
fn partial_schema_never_resets_or_imports() {
    let f = Fixture::new();
    let s = f.open();
    f.db()
        .exec("CREATE TABLE local_bot_draft_meta(x TEXT)", &[])
        .unwrap();
    assert!(resolve(&s, C, None).is_err());
    assert_eq!(
        f.db()
            .query(
                "SELECT sql FROM sqlite_master WHERE name='local_bot_draft_meta'",
                &[]
            )
            .unwrap()[0][0]
            .as_deref(),
        Some("CREATE TABLE local_bot_draft_meta(x TEXT)")
    );
}
#[test]
fn stored_archive_and_receipt_tamper_refuse() {
    let f = Fixture::new();
    let s = f.open();
    let b = binding(&resolve(&s, C, None).unwrap());
    save(&s, C, None, &b, A, "0", &archive(1)).unwrap();
    f.db()
        .exec("UPDATE local_bot_drafts SET archive_hex='00'", &[])
        .unwrap();
    let mut next = b.clone();
    next.expected_stored_revision = "1".into();
    assert!(read(&s, C, None, &next).is_err());
    // Restore the archive so receipt validation, not record integrity, is exercised.
    let good: String = archive(1).iter().map(|b| format!("{b:02x}")).collect();
    f.db()
        .exec("UPDATE local_bot_drafts SET archive_hex=?", &[&good])
        .unwrap();
    f.db()
        .exec("UPDATE local_bot_draft_saves SET receipt_json='{}'", &[])
        .unwrap();
    assert!(lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).is_err());
}
#[test]
fn live_project_revocation_is_checked_even_for_original_receipts() {
    let f = Fixture::new();
    let s = f.open();
    f.db()
        .exec(
            "INSERT INTO projects VALUES('p','workspace','synthetic','1',0)",
            &[],
        )
        .unwrap();
    let d = resolve(&s, C, Some("p")).unwrap();
    let b = binding(&d);
    assert_ne!(resolve(&s, C, None).unwrap()["draft_id"], d["draft_id"]);
    save(&s, C, Some("p"), &b, A, "0", &archive(1)).unwrap();
    f.db()
        .exec("UPDATE projects SET deleted=1 WHERE id='p'", &[])
        .unwrap();
    assert!(resolve(&s, C, Some("p")).is_err());
    assert!(read(&s, C, Some("p"), &b).is_err());
    assert!(lookup_save(&s, C, Some("p"), &b.namespace_id, &b.draft_id, A).is_err());
}
#[test]
fn original_unknown_and_reserved_ledgers_are_untouched() {
    let f = Fixture::new();
    let s = f.open();
    for (id, status) in [
        ("original-unknown-a", "unknown"),
        ("original-unknown-b", "unknown"),
        ("reserved", "pending"),
    ] {
        f.db()
            .exec(
                "INSERT INTO intents VALUES(?, 'synthetic','{}',?,NULL,NULL,'old')",
                &[id, status],
            )
            .unwrap();
    }
    let before = f
        .db()
        .query("SELECT * FROM intents ORDER BY intent_id", &[])
        .unwrap();
    let b = binding(&resolve(&s, C, None).unwrap());
    save(&s, C, None, &b, A, "0", &archive(1)).unwrap();
    lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).unwrap();
    assert_eq!(
        before,
        f.db()
            .query("SELECT * FROM intents ORDER BY intent_id", &[])
            .unwrap()
    );
}
#[test]
fn exclusive_owner_and_competing_editors_do_not_lose_updates() {
    let f = Fixture::new();
    let s = f.open();
    assert!(
        BusinessStore::open_existing(&f.0.join("business.sqlite"), "workspace", "second").is_err()
    );
    let b = binding(&resolve(&s, C, None).unwrap());
    let s = std::sync::Arc::new(std::sync::Mutex::new(s));
    let handles: Vec<_> = [A, B]
        .into_iter()
        .map(|attempt| {
            let s = s.clone();
            let b = b.clone();
            std::thread::spawn(move || {
                save(&s.lock().unwrap(), C, None, &b, attempt, "0", &archive(1))
            })
        })
        .collect();
    let results: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();
    assert_eq!(results.iter().filter(|r| r.is_ok()).count(), 1);
    assert_eq!(
        results
            .iter()
            .filter(|r| r.as_ref().err() == Some(&"local_draft_version"))
            .count(),
        1
    );
}
#[test]
fn draft_capacity_preserves_existing_records_and_receipts() {
    let f = Fixture::new();
    let s = f.open();
    let first = resolve(&s, C, None).unwrap();
    for n in 0..127 {
        resolve(&s, &format!("12345678-1234-4234-8234-{n:012x}"), None).unwrap();
    }
    assert_eq!(resolve(&s, A, None).unwrap_err(), "local_draft_capacity");
    assert_eq!(resolve(&s, C, None).unwrap(), first);
    let b = binding(&first);
    save(&s, C, None, &b, A, "0", &archive(1)).unwrap();
    assert!(lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).is_ok());
}
#[test]
fn receipt_capacity_does_not_evict_originals() {
    let f = Fixture::new();
    let s = f.open();
    let b = binding(&resolve(&s, C, None).unwrap());
    for n in 0..4096 {
        f.db()
            .exec(
                "INSERT INTO local_bot_draft_saves VALUES(?,?,?,?,?,'0','1','0',?,'{}')",
                &[
                    &format!("32345678-1234-4234-8234-{n:012x}"),
                    &b.namespace_id,
                    &b.draft_id,
                    "synthetic",
                    "1",
                    &"0".repeat(64),
                ],
            )
            .unwrap();
    }
    assert_eq!(
        save(&s, C, None, &b, A, "0", &archive(1)).unwrap_err(),
        "local_draft_capacity"
    );
    assert_eq!(resolve(&s, C, None).unwrap()["stored_revision"], "0");
    assert_eq!(
        f.db()
            .query("SELECT COUNT(*) FROM local_bot_draft_saves", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("4096")
    );
}
#[test]
fn altered_schema_workspace_and_signed_long_overflow_refuse() {
    let f = Fixture::new();
    let s = f.open();
    let b = binding(&resolve(&s, C, None).unwrap());
    let mut overflow = b.clone();
    overflow.expected_stored_revision = i64::MAX.to_string();
    assert_eq!(
        save(&s, C, None, &overflow, A, "0", &archive(1)).unwrap_err(),
        "local_draft_version"
    );
    f.db()
        .exec("UPDATE local_bot_draft_meta SET workspace='other'", &[])
        .unwrap();
    assert!(resolve(&s, C, None).is_err());
    f.db()
        .exec(
            "UPDATE local_bot_draft_meta SET workspace='workspace',schema_version='2'",
            &[],
        )
        .unwrap();
    assert!(read(&s, C, None, &b).is_err());
}
#[test]
fn structurally_invalid_rehashed_archive_cannot_add_fields() {
    let f = Fixture::new();
    let s = f.open();
    let b = binding(&resolve(&s, C, None).unwrap());
    let mut payload = archive(1);
    payload.truncate(payload.len() - 32);
    payload.push(0);
    let hash = Sha256::digest(&payload);
    payload.extend_from_slice(&hash);
    assert_eq!(
        save(&s, C, None, &b, A, "0", &payload).unwrap_err(),
        "local_draft_archive"
    );
}
#[test]
fn project_query_storage_fault_is_unknown_not_scope_denial() {
    let f = Fixture::new();
    let s = f.open();
    resolve(&s, C, None).unwrap();
    f.db()
        .exec(
            "ALTER TABLE projects RENAME TO synthetic_unavailable_projects",
            &[],
        )
        .unwrap();
    assert_eq!(
        resolve(&s, C, Some("p")).unwrap_err(),
        "local_draft_storage_unknown"
    );
}

#[test]
fn empty_archive_null_projection_survives_read_and_restart() {
    let f = Fixture::new();
    let s = f.open();
    let first = resolve(&s, C, None).unwrap();
    let b = binding(&first);
    let loaded = read(&s, C, None, &b).unwrap();
    assert_eq!(loaded["status"], "not_saved");
    assert_eq!(loaded["archive_present"], false);
    assert!(loaded["archive_hex"].is_null());
    assert!(loaded["archive_digest"].is_null());
    assert_eq!(resolve(&s, C, None).unwrap(), first);
    drop(s);
    assert_eq!(read(&f.open(), C, None, &b).unwrap(), loaded);
}

#[test]
fn archive_storage_null_oversize_blob_and_invalid_text_refuse() {
    let f = Fixture::new();
    let s = f.open();
    let b = binding(&resolve(&s, C, None).unwrap());
    save(&s, C, None, &b, A, "0", &archive(1)).unwrap();
    let mut next = b.clone();
    next.expected_stored_revision = "1".into();
    let good: String = archive(1).iter().map(|v| format!("{v:02x}")).collect();
    // A well-formed archive stored as BLOB must not become text implicitly.
    f.db()
        .exec(
            "UPDATE local_bot_drafts SET archive_hex=CAST(? AS BLOB)",
            &[&good],
        )
        .unwrap();
    assert_eq!(read(&s, C, None, &next).unwrap_err(), "local_draft_corrupt");
    for bad in [
        "0".repeat(65536),
        "0".repeat(65537),
        "0".repeat(65538),
        String::new(),
    ] {
        f.db()
            .exec("UPDATE local_bot_drafts SET archive_hex=?", &[&bad])
            .unwrap();
        assert_eq!(read(&s, C, None, &next).unwrap_err(), "local_draft_corrupt");
    }
    f.db()
        .exec(
            "UPDATE local_bot_drafts SET archive_hex=? || char(0) || ?",
            &[&good, &"0".repeat(65536)],
        )
        .unwrap();
    assert_eq!(read(&s, C, None, &next).unwrap_err(), "local_draft_corrupt");
    f.db()
        .exec("UPDATE local_bot_drafts SET archive_hex=42", &[])
        .unwrap();
    assert_eq!(read(&s, C, None, &next).unwrap_err(), "local_draft_corrupt");
    f.db()
        .exec(
            "UPDATE local_bot_drafts SET archive_hex=?,archive_digest=CAST(archive_digest AS BLOB)",
            &[&good],
        )
        .unwrap();
    assert_eq!(read(&s, C, None, &next).unwrap_err(), "local_draft_corrupt");
    f.db()
        .exec(
            "UPDATE local_bot_drafts SET archive_digest=CAST(archive_digest AS TEXT)",
            &[],
        )
        .unwrap();
    assert_eq!(read(&s, C, None, &next).unwrap()["status"], "stored");
    f.db()
        .exec(
            "UPDATE local_bot_drafts SET archive_hex=NULL,archive_digest=NULL",
            &[],
        )
        .unwrap();
    assert_eq!(read(&s, C, None, &next).unwrap_err(), "local_draft_corrupt");
}

#[test]
fn original_receipt_blob_or_oversize_storage_refuses() {
    let f = Fixture::new();
    let s = f.open();
    let b = binding(&resolve(&s, C, None).unwrap());
    let receipt = save(&s, C, None, &b, A, "17", &archive(1)).unwrap();
    f.db()
        .exec(
            "UPDATE local_bot_draft_saves SET receipt_json=CAST(receipt_json AS BLOB)",
            &[],
        )
        .unwrap();
    assert_eq!(
        lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).unwrap_err(),
        "local_draft_corrupt"
    );
    f.db()
        .exec(
            "UPDATE local_bot_draft_saves SET receipt_json=CAST(receipt_json AS TEXT)",
            &[],
        )
        .unwrap();
    assert_eq!(
        lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).unwrap(),
        receipt
    );
    f.db()
        .exec(
            "UPDATE local_bot_draft_saves SET archive_digest=CAST(archive_digest AS BLOB)",
            &[],
        )
        .unwrap();
    assert_eq!(
        lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).unwrap_err(),
        "local_draft_corrupt"
    );
    f.db()
        .exec(
            "UPDATE local_bot_draft_saves SET archive_digest=CAST(archive_digest AS TEXT)",
            &[],
        )
        .unwrap();
    assert_eq!(
        lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).unwrap(),
        receipt
    );
    f.db()
        .exec(
            "UPDATE local_bot_draft_saves SET receipt_json=?",
            &[&"x".repeat(4097)],
        )
        .unwrap();
    assert_eq!(
        lookup_save(&s, C, None, &b.namespace_id, &b.draft_id, A).unwrap_err(),
        "local_draft_corrupt"
    );
}

#[test]
fn large_valid_canonical_archive_roundtrips_without_projection_truncation() {
    let f = Fixture::new();
    let s = f.open();
    let b = binding(&resolve(&s, C, None).unwrap());
    let mut payload = b"MYBD\0\0\0\x01".to_vec();
    payload.extend(1i64.to_be_bytes());
    for units in [60, 8000, 160] {
        let text = "中".repeat(units);
        payload.extend([0u8, 1u8]); // Canonical nonempty USER field, locked.
        payload.extend((text.len() as i32).to_be_bytes());
        payload.extend(text.as_bytes());
    }
    payload.push(0); // No template.
    let hash = Sha256::digest(&payload);
    payload.extend_from_slice(&hash);
    assert!(payload.len() < 32768);
    save(&s, C, None, &b, A, "0", &payload).unwrap();
    let mut next = b;
    next.expected_stored_revision = "1".into();
    assert_eq!(
        read(&s, C, None, &next).unwrap()["archive_hex"]
            .as_str()
            .unwrap()
            .len(),
        payload.len() * 2
    );
}
