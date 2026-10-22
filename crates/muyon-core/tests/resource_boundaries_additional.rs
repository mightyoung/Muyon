//! Public-API resource boundaries. Disk fixtures deduplicate identical content;
//! declared ZIP expansion limits are deliberately separate from decoded bytes.
use muyon_core::{
    archive::{parse_archive, DecodedEntryValidator},
    blobs::{BlobKind, FinishedBlob, MAX_CHUNK, MAX_DOCUMENT_BYTES, MAX_UPLOAD_BYTES},
    business::BusinessStore,
    contract::{CommandEnvelope, ContractError, ExecutionStatus},
    research::SnapshotEntry,
    sqlite::Db,
};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::Read,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};

static COUNTER: AtomicU64 = AtomicU64::new(0);
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "muyon-resource-boundaries-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn path(&self) -> PathBuf {
        self.0.join("business.sqlite")
    }
    fn root(&self) -> PathBuf {
        self.0.join("business.sqlite.blobs")
    }
    fn store(&self) -> BusinessStore {
        BusinessStore::initialize(&self.path(), "workspace-a").unwrap();
        let store = BusinessStore::open_existing(&self.path(), "workspace-a", "epoch-a").unwrap();
        let mut command: CommandEnvelope = serde_json::from_value(json!({
            "protocol_version":1,"business_version":1,"intent_id":"create-project",
            "scope":{"workspace_id":"workspace-a","project_id":"project-a"},
            "expected_revision":"0","authority":{"grant_id":"grant-project","generation":"1","owner_epoch":"epoch-a"},
            "plan_id":"plan-project","plan_digest":"0".repeat(64),
            "command":{"operation":"project_create","project_id":"project-a","name":"Boundary research"}
        })).unwrap();
        command.plan_digest = command.expected_plan_digest().unwrap();
        store.issue_grant_trusted(&command, None).unwrap();
        assert_eq!(
            store.execute(&command).unwrap().status,
            ExecutionStatus::Committed
        );
        store
    }
    fn counts(&self) -> Vec<Vec<Option<String>>> {
        let db = Db::open(self.path().to_str().unwrap(), true, false).unwrap();
        db.query("SELECT (SELECT COUNT(*) FROM blob_uploads),(SELECT COUNT(*) FROM blobs),(SELECT COUNT(*) FROM blob_pins),(SELECT COUNT(*) FROM blob_references),(SELECT COUNT(*) FROM research_entries),(SELECT COUNT(*) FROM business_history)", &[]).unwrap()
    }
    fn assert_no_business_publication(&self) {
        let counts = self.counts();
        assert_eq!(counts[0][3].as_deref(), Some("0"));
        assert_eq!(counts[0][4].as_deref(), Some("0"));
        assert_eq!(
            counts[0][5].as_deref(),
            Some("1"),
            "only project setup has history"
        );
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// Sends actual bytes through append_chunk, not sparse files or injected rows.
/// The payload has only a basic PDF envelope; this is not a PDF parser test.
fn stage_thirty_mib(store: &BusinessStore, extra: bool) -> (String, String) {
    let upload = store.begin_upload("project-a").unwrap();
    let mut digest = Sha256::new();
    let chunks = MAX_DOCUMENT_BYTES as usize / MAX_CHUNK;
    for index in 0..chunks {
        let mut buffer = [b'x'; MAX_CHUNK];
        if index == 0 {
            buffer[..9].copy_from_slice(b"%PDF-1.7\n");
        }
        if index + 1 == chunks {
            buffer[MAX_CHUNK - 7..].copy_from_slice(b"\n%%EOF\n");
        }
        store.append_chunk(&upload.upload_id, &buffer).unwrap();
        digest.update(buffer);
    }
    if extra {
        store.append_chunk(&upload.upload_id, b"x").unwrap();
        digest.update(b"x");
    }
    (
        upload.upload_id,
        digest
            .finalize()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect(),
    )
}
fn read_verified(store: &BusinessStore, upload: &str, expected_length: u64, expected_digest: &str) {
    let mut reader = store.open_upload_reader(upload).unwrap();
    let mut actual = Sha256::new();
    let mut length = 0u64;
    loop {
        let chunk = store.read_blob_chunk(&mut reader, MAX_CHUNK).unwrap();
        if chunk.is_empty() {
            break;
        }
        length += chunk.len() as u64;
        actual.update(chunk);
    }
    store.close_blob_reader(reader).unwrap();
    assert_eq!(length, expected_length);
    assert_eq!(
        actual
            .finalize()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>(),
        expected_digest
    );
}
fn file_digest(path: PathBuf) -> String {
    let mut file = fs::File::open(path).unwrap();
    let mut digest = Sha256::new();
    let mut buffer = [0; MAX_CHUNK];
    loop {
        let read = file.read(&mut buffer).unwrap();
        if read == 0 {
            break;
        }
        digest.update(&buffer[..read]);
    }
    digest
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

#[test]
fn actual_pdf_and_document_exact_thirty_mib_and_one_extra_byte() {
    let fixture = Fixture::new();
    let store = fixture.store();
    for kind in [BlobKind::Pdf, BlobKind::Document] {
        let (valid, expected_digest) = stage_thirty_mib(&store, false);
        let blob = store.finish_blob(&valid, kind).unwrap();
        assert_eq!(blob.blob.byte_length.value(), MAX_DOCUMENT_BYTES);
        assert_eq!(blob.blob.digest, expected_digest);
        let (oversized, oversized_digest) = stage_thirty_mib(&store, true);
        let before = fixture.counts();
        assert_eq!(
            store.finish_blob(&oversized, kind),
            Err(ContractError::TextLimit)
        );
        assert_eq!(
            fixture.counts(),
            before,
            "quota rejection must not issue pins or references"
        );
        let original = fixture.root().join("staging").join(&oversized);
        assert_eq!(
            fs::metadata(&original).unwrap().len(),
            MAX_DOCUMENT_BYTES + 1
        );
        assert_eq!(
            file_digest(original),
            oversized_digest,
            "rejected source bytes retained"
        );
        let state = store.lookup_upload(&oversized).unwrap();
        assert_eq!(state.state, "copying");
        assert_eq!(state.byte_length.value(), MAX_DOCUMENT_BYTES + 1);
        read_verified(&store, &valid, MAX_DOCUMENT_BYTES, &expected_digest);
        fixture.assert_no_business_publication();
        store.abort_upload(&oversized).unwrap();
    }
    assert_eq!(
        fs::read_dir(fixture.root().join("objects"))
            .unwrap()
            .count(),
        1,
        "equal actual payloads deduplicate without manufacturing ledger data"
    );
}

fn u16le(out: &mut Vec<u8>, value: u16) {
    out.extend(value.to_le_bytes());
}
fn u32le(out: &mut Vec<u8>, value: u32) {
    out.extend(value.to_le_bytes());
}
/// Real ZIP32 local/CEN/EOCD bytes. Nonzero sizes are declarations only: the
/// tiny raw-DEFLATE empty stream must fail a later actual decoded-size check.
fn metadata_zip(expanded: &[u32]) -> Vec<u8> {
    let mut archive = Vec::new();
    let mut central = Vec::new();
    for (index, length) in expanded.iter().copied().enumerate() {
        let name = format!("file-{index:05}.bin");
        let method = if length == 0 { 0 } else { 8 };
        let payload: &[u8] = if length == 0 { &[] } else { &[3, 0] };
        let offset = archive.len() as u32;
        u32le(&mut archive, 0x04034b50);
        for value in [20, 0, method, 0, 0] {
            u16le(&mut archive, value);
        }
        for value in [0, payload.len() as u32, length] {
            u32le(&mut archive, value);
        }
        u16le(&mut archive, name.len() as u16);
        u16le(&mut archive, 0);
        archive.extend(name.as_bytes());
        archive.extend(payload);
        u32le(&mut central, 0x02014b50);
        for value in [20, 20, 0, method, 0, 0] {
            u16le(&mut central, value);
        }
        for value in [0, payload.len() as u32, length] {
            u32le(&mut central, value);
        }
        for value in [name.len() as u16, 0, 0, 0, 0] {
            u16le(&mut central, value);
        }
        u32le(&mut central, 0);
        u32le(&mut central, offset);
        central.extend(name.as_bytes());
    }
    let offset = archive.len() as u32;
    let size = central.len() as u32;
    archive.extend(central);
    u32le(&mut archive, 0x06054b50);
    for value in [0, 0, expanded.len() as u16, expanded.len() as u16] {
        u16le(&mut archive, value);
    }
    u32le(&mut archive, size);
    u32le(&mut archive, offset);
    u16le(&mut archive, 0);
    archive
}
#[test]
fn zip_metadata_exact_expansion_and_member_count_and_one_over() {
    let mut expanded = vec![MAX_DOCUMENT_BYTES as u32; 5];
    let manifest = parse_archive(&metadata_zip(&expanded)).unwrap();
    assert_eq!(
        manifest
            .entries
            .iter()
            .map(|e| e.expanded_length)
            .sum::<u64>(),
        MAX_UPLOAD_BYTES
    );
    assert_eq!(
        DecodedEntryValidator::new(&manifest.entries[0]).finish(),
        Err(ContractError::BindingMismatch),
        "metadata acceptance never certifies nonexistent 30MiB decoded contents"
    );
    expanded.push(1);
    assert_eq!(
        parse_archive(&metadata_zip(&expanded)),
        Err(ContractError::TextLimit)
    );
    assert_eq!(
        parse_archive(&metadata_zip(&vec![0; 10_000]))
            .unwrap()
            .entries
            .len(),
        10_000
    );
    assert_eq!(
        parse_archive(&metadata_zip(&vec![0; 10_001])),
        Err(ContractError::TextLimit)
    );
}

#[test]
fn seal_actual_total_exact_one_fifty_mib_then_one_byte_and_member_count_refuse_without_effects() {
    let fixture = Fixture::new();
    let store = fixture.store();
    let mut entries = Vec::new();
    let mut first: Option<FinishedBlob> = None;
    for index in 0..5 {
        let (upload, digest) = stage_thirty_mib(&store, false);
        let finished = store.finish_blob(&upload, BlobKind::Pdf).unwrap();
        assert_eq!(finished.blob.digest, digest);
        if first.is_none() {
            first = Some(finished);
        }
        entries.push(SnapshotEntry {
            relative_path: format!("paper-{index}.pdf"),
            upload_id: upload,
        });
    }
    let sealed = store
        .seal_research_snapshot("project-a", &entries, None)
        .unwrap();
    read_verified(
        &store,
        &sealed.snapshot_upload_id,
        sealed.snapshot.byte_length.value(),
        &sealed.snapshot.digest,
    );
    let extra = store.begin_upload("project-a").unwrap();
    store.append_chunk(&extra.upload_id, b"x").unwrap();
    store
        .finish_blob(&extra.upload_id, BlobKind::Document)
        .unwrap();
    let mut over_bytes = entries.clone();
    over_bytes.push(SnapshotEntry {
        relative_path: "extra.md".into(),
        upload_id: extra.upload_id,
    });
    let before = fixture.counts();
    assert_eq!(
        store.seal_research_snapshot("project-a", &over_bytes, None),
        Err(ContractError::TextLimit)
    );
    assert_eq!(fixture.counts(), before);
    let mut too_many = entries;
    for index in too_many.len()..10_001 {
        too_many.push(SnapshotEntry {
            relative_path: format!("extra-{index}.md"),
            upload_id: format!("up_{index:032x}"),
        });
    }
    assert_eq!(
        store.seal_research_snapshot("project-a", &too_many, None),
        Err(ContractError::TextLimit),
        "count preflight must reject before resolving unissued upload IDs"
    );
    assert_eq!(fixture.counts(), before);
    let first = first.unwrap();
    read_verified(
        &store,
        &first.upload_id,
        MAX_DOCUMENT_BYTES,
        &first.blob.digest,
    );
    read_verified(
        &store,
        &sealed.snapshot_upload_id,
        sealed.snapshot.byte_length.value(),
        &sealed.snapshot.digest,
    );
    fixture.assert_no_business_publication();
}
