use muyon_core::{
    blobs::{BlobKind, FinishedBlob, MAX_CHUNK},
    business::BusinessStore,
    contract::*,
    research::{SealedResearchSnapshot, SnapshotEntry},
    sqlite::Db,
};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs,
    io::{BufRead, BufReader},
    path::PathBuf,
    process::{Command, Stdio},
    sync::atomic::{AtomicU64, Ordering},
};
static COUNT: AtomicU64 = AtomicU64::new(0);
const PDF: &[u8] = b"%PDF-1.4 synthetic research\n%%EOF\n";
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "muyon-research-{}-{}",
            std::process::id(),
            COUNT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&p).unwrap();
        Self(p)
    }
    fn path(&self) -> PathBuf {
        self.0.join("business.sqlite")
    }
    fn store(&self) -> BusinessStore {
        BusinessStore::initialize(&self.path(), "workspace-a").unwrap();
        let store = self.reopen();
        project(&store, "project-a");
        store
    }
    fn reopen(&self) -> BusinessStore {
        BusinessStore::open_existing(&self.path(), "workspace-a", "epoch-a").unwrap()
    }
    fn db(&self) -> Db {
        Db::open(self.path().to_str().unwrap(), false, false).unwrap()
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn hash(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|v| format!("{v:02x}"))
        .collect()
}
fn cmd(intent: &str, project: &str, revision: u64, command: Operation) -> CommandEnvelope {
    let mut c = CommandEnvelope {
        protocol_version: 1,
        business_version: 1,
        intent_id: intent.into(),
        scope: Scope {
            workspace_id: "workspace-a".into(),
            project_id: Some(project.into()),
        },
        expected_revision: Revision::new(revision),
        authority: AuthorityBinding {
            grant_id: format!("grant-{intent}"),
            generation: Revision::new(1),
            owner_epoch: "epoch-a".into(),
        },
        plan_id: format!("plan-{intent}"),
        plan_digest: "0".repeat(64),
        command,
    };
    seal(&mut c);
    c
}
fn seal(c: &mut CommandEnvelope) {
    c.plan_digest = c.expected_plan_digest().unwrap();
}
fn run(store: &BusinessStore, c: &CommandEnvelope) -> ExecutionResult {
    store.issue_grant_trusted(c, None).unwrap();
    store.execute(c).unwrap()
}
fn project(store: &BusinessStore, id: &str) {
    let c = cmd(
        &format!("create-{id}"),
        id,
        0,
        Operation::ProjectCreate {
            project_id: id.into(),
            name: id.into(),
        },
    );
    assert_eq!(run(store, &c).status, ExecutionStatus::Committed);
}
fn upload(store: &BusinessStore, project: &str, bytes: &[u8], kind: BlobKind) -> FinishedBlob {
    let h = store.begin_upload(project).unwrap();
    for chunk in bytes.chunks(MAX_CHUNK) {
        store.append_chunk(&h.upload_id, chunk).unwrap();
    }
    store.finish_blob(&h.upload_id, kind).unwrap()
}
fn manual(store: &BusinessStore, intent: &str, paper: &str) -> (CommandEnvelope, FinishedBlob) {
    let blob = upload(store, "project-a", PDF, BlobKind::Pdf);
    let c = cmd(
        intent,
        "project-a",
        0,
        Operation::PaperCreate {
            paper_id: paper.into(),
            payload: PaperPayload {
                title: "  合成论文  ".into(),
                authors: vec!["甲".into()],
                year: Some(2026),
                doi: Some("10.synthetic/example".into()),
                url: Some("https://example.invalid/paper".into()),
                notes: None,
                attachment: blob.blob.clone(),
                attachment_upload_id: Some(blob.upload_id.clone()),
            },
        },
    );
    (c, blob)
}
fn snapshot(
    store: &BusinessStore,
    files: &BTreeMap<String, Vec<u8>>,
    archive: Option<&[u8]>,
) -> SealedResearchSnapshot {
    let mut entries = Vec::new();
    for (path, bytes) in files {
        let blob = upload(
            store,
            "project-a",
            bytes,
            if path.ends_with(".pdf") {
                BlobKind::Pdf
            } else {
                BlobKind::Document
            },
        );
        entries.push(SnapshotEntry {
            relative_path: path.clone(),
            upload_id: blob.upload_id,
        });
    }
    let archive = archive.map(|bytes| upload(store, "project-a", bytes, BlobKind::Archive));
    store
        .seal_research_snapshot(
            "project-a",
            &entries,
            archive.as_ref().map(|blob| blob.upload_id.as_str()),
        )
        .unwrap()
}
fn import(intent: &str, revision: u64, sealed: &SealedResearchSnapshot) -> CommandEnvelope {
    cmd(
        intent,
        "project-a",
        revision,
        Operation::ResearchImport {
            source_id: "collection-a".into(),
            source_revision: Revision::new(17),
            snapshot: sealed.snapshot.clone(),
            snapshot_upload_id: Some(sealed.snapshot_upload_id.clone()),
            records: Vec::new(),
        },
    )
}
fn files(title: &str, rev: u64) -> BTreeMap<String, Vec<u8>> {
    BTreeMap::from([
 ("research/papers.jsonl".into(),format!("  {{\"schema_version\":2,\"id\":\"p1\",\"rev\":{rev},\"title\":\"{title}\",\"source_id\":\"s1\",\"source_rev\":1}}  \n").into_bytes()),
 ("research/sources.jsonl".into(),serde_json::to_vec(&json!({"schema_version":2,"id":"s1","rev":1,"material_binding":{"path":"related_work/paper.pdf","sha256":hash(PDF)}})).unwrap()),
 ("research/claims.jsonl".into(),b"\n".to_vec()),("research/opportunities.jsonl".into(),b"\n".to_vec()),("related_work/paper.pdf".into(),PDF.to_vec()),
])
}
fn count(db: &Db, table: &str) -> usize {
    db.query(&format!("SELECT COUNT(*) FROM {table}"), &[])
        .unwrap()[0][0]
        .as_ref()
        .unwrap()
        .parse()
        .unwrap()
}

#[test]
fn manual_pdf_is_real_private_persistent_and_shares_catalog_with_import() {
    let temp = Temp::new();
    let store = temp.store();
    let source = temp.0.join("source.pdf");
    fs::write(&source, PDF).unwrap();
    let (c, blob) = manual(&store, "manual-a", "paper-manual");
    fs::remove_file(source).unwrap();
    let result = run(&store, &c);
    assert_eq!(result.status, ExecutionStatus::Committed);
    let paper = store.paper("project-a", "paper-manual").unwrap();
    assert_eq!(paper.title, "合成论文");
    assert!(paper.manual);
    assert_eq!(paper.source_id, None);
    assert_eq!(paper.attachments, vec![blob.blob.clone()]);
    let sealed = snapshot(&store, &files("导入论文", 1), None);
    assert_eq!(
        run(&store, &import("import-a", 0, &sealed)).status,
        ExecutionStatus::Committed
    );
    assert_eq!(store.papers("project-a", 200, 0).unwrap().len(), 2);
    drop(store);
    let reopened = temp.reopen();
    let mut reader = reopened
        .open_paper_attachment("project-a", "paper-manual", &blob.blob.digest)
        .unwrap();
    assert_eq!(
        reopened.read_blob_chunk(&mut reader, MAX_CHUNK).unwrap(),
        PDF
    );
    reopened.close_blob_reader(reader).unwrap();
    assert_eq!(reopened.lookup("manual-a").unwrap(), result);
}

#[test]
fn manual_kind_project_and_exact_upload_binding_cannot_be_forged() {
    let temp = Temp::new();
    let store = temp.store();
    project(&store, "project-b");
    let (c, blob) = manual(&store, "manual-a", "paper-a");
    let mut wrong = c.clone();
    wrong.scope.project_id = Some("project-b".into());
    seal(&mut wrong);
    store.issue_grant_trusted(&wrong, None).unwrap();
    assert_eq!(store.execute(&wrong), Err(ContractError::ScopeMismatch));
    let document = upload(&store, "project-a", PDF, BlobKind::Document);
    let mut wrong = c.clone();
    wrong.intent_id = "manual-wrong-kind".into();
    wrong.authority.grant_id = "grant-wrong-kind".into();
    if let Operation::PaperCreate { payload, .. } = &mut wrong.command {
        payload.attachment_upload_id = Some(document.upload_id);
    }
    seal(&mut wrong);
    store.issue_grant_trusted(&wrong, None).unwrap();
    assert_eq!(store.execute(&wrong), Err(ContractError::InvalidPayload));
    assert_eq!(count(&temp.db(), "research_entries"), 0);
    assert_eq!(
        store.lookup_upload(&blob.upload_id).unwrap().state,
        "pinned"
    );
}

#[test]
fn imported_raw_json_duplicate_revisions_and_material_binding_are_preserved() {
    let temp = Temp::new();
    let store = temp.store();
    let mut f = files("导入论文", 1);
    let line = f["research/papers.jsonl"].clone();
    f.get_mut("research/papers.jsonl")
        .unwrap()
        .extend_from_slice(&line);
    f.insert("DataSet/ignored.jsonl".into(), b"not valid json".to_vec());
    let sealed = snapshot(&store, &f, None);
    assert_eq!(sealed.layout, "research-skill-v2");
    assert_eq!(sealed.record_count, 3);
    let c = import("import-a", 0, &sealed);
    let result = run(&store, &c);
    assert_eq!(result.status, ExecutionStatus::Committed);
    assert_eq!(
        result.receipt.as_ref().unwrap().result["duplicate_id_revisions"],
        1
    );
    let papers = store.papers("project-a", 200, 0).unwrap();
    assert_eq!(papers.len(), 2);
    assert_ne!(papers[0].id, papers[1].id);
    assert_eq!(papers[0].source_record_id, Some(json!("p1")));
    assert_eq!(papers[0].source_revision, Some(Revision::new(1)));
    assert!(papers[0].raw_json.starts_with("  {"));
    assert!(papers[0].raw_json.ends_with("  "));
    assert_eq!(
        papers.iter().filter(|p| !p.attachments.is_empty()).count(),
        1
    );
    let bound = papers.iter().find(|p| !p.attachments.is_empty()).unwrap();
    assert_eq!(
        store.paper_bindings("project-a", &bound.id).unwrap()[0].method,
        "material_binding"
    );
    assert_eq!(store.execute(&c).unwrap(), result);
    assert_eq!(
        store.research_sources("project-a").unwrap()[0].revision,
        Revision::new(1)
    );
}

#[test]
fn cited_same_revision_changes_reject_atomically_and_next_revision_is_retained() {
    let temp = Temp::new();
    let store = temp.store();
    let first = snapshot(&store, &files("original", 1), None);
    run(&store, &import("import-a", 0, &first));
    let old = store.papers("project-a", 200, 0).unwrap()[0].clone();
    store
        .cite_entry_trusted("project-a", &old.id, "citation-a")
        .unwrap();
    let changed = snapshot(&store, &files("changed-with-same-rev", 1), None);
    let result = run(&store, &import("import-b", 1, &changed));
    assert_eq!(result.status, ExecutionStatus::Rejected);
    assert_eq!(result.error, Some(ContractError::RevisionConflict));
    assert_eq!(store.paper("project-a", &old.id).unwrap(), old);
    assert_eq!(
        store
            .lookup_upload(&changed.snapshot_upload_id)
            .unwrap()
            .state,
        "pinned"
    );
    assert_eq!(
        store.research_sources("project-a").unwrap()[0].revision,
        Revision::new(1)
    );
    let next = snapshot(&store, &files("next-rev", 2), None);
    let result = run(&store, &import("import-c", 1, &next));
    assert_eq!(result.status, ExecutionStatus::Committed);
    let papers = store.papers("project-a", 200, 0).unwrap();
    assert_eq!(papers.len(), 2);
    assert!(papers
        .iter()
        .any(|p| p.id == old.id && p.source_revision == Some(Revision::new(1))));
    assert!(papers
        .iter()
        .any(|p| p.source_revision == Some(Revision::new(2))));
}

#[test]
fn refresh_only_removes_missing_uncited_entries_and_keeps_cited_document_bytes() {
    let temp = Temp::new();
    let store = temp.store();
    let mut first_files = files("first", 1);
    first_files.insert(
        "extra.jsonl".into(),
        b"{\"id\":\"extra\",\"rev\":1,\"name\":\"uncited\"}\n".to_vec(),
    );
    let first = snapshot(&store, &first_files, None);
    run(&store, &import("import-a", 0, &first));
    let doc = store.documents("project-a", 200, 0).unwrap()[0].clone();
    store
        .cite_document_trusted("project-a", &doc.id, "doc-note")
        .unwrap();
    let mut next_files = files("next", 2);
    next_files.insert(
        "related_work/paper.pdf".into(),
        b"%PDF-1.4 changed private bytes\n%%EOF\n".to_vec(),
    );
    let next = snapshot(&store, &next_files, None);
    assert_eq!(
        run(&store, &import("import-b", 1, &next)).status,
        ExecutionStatus::Committed
    );
    assert_eq!(store.entries("project-a", 200, 0).unwrap().len(), 2);
    let docs = store.documents("project-a", 200, 0).unwrap();
    assert_eq!(docs.len(), 2);
    assert!(docs
        .iter()
        .any(|d| d.id == doc.id && d.retained && d.blob == doc.blob));
    let papers = store.papers("project-a", 200, 0).unwrap();
    assert_eq!(papers.len(), 1);
    assert!(papers[0].attachments.is_empty());
    assert!(!store.paper_bindings("project-a", &papers[0].id).unwrap()[0].hash_ok);
}

#[test]
fn forged_wire_records_and_snapshot_project_changes_do_not_become_imports() {
    let temp = Temp::new();
    let store = temp.store();
    project(&store, "project-b");
    let sealed = snapshot(&store, &files("actual", 1), None);
    let mut forged = import("forged", 0, &sealed);
    if let Operation::ResearchImport { records, .. } = &mut forged.command {
        *records = sealed.records.clone();
        records[0].record["title"] = json!("forged");
        records[0].raw_json = records[0].record.to_string();
    }
    seal(&mut forged);
    store.issue_grant_trusted(&forged, None).unwrap();
    assert_eq!(store.execute(&forged), Err(ContractError::BindingMismatch));
    assert!(store.entries("project-a", 200, 0).unwrap().is_empty());
    let mut wrong = import("wrong-project", 0, &sealed);
    wrong.scope.project_id = Some("project-b".into());
    seal(&mut wrong);
    store.issue_grant_trusted(&wrong, None).unwrap();
    assert_eq!(store.execute(&wrong), Err(ContractError::BindingMismatch));
    assert_eq!(count(&temp.db(), "research_sources"), 0);
}

#[test]
fn malformed_jsonl_paths_and_no_recognized_material_are_rejected_before_publication() {
    let temp = Temp::new();
    let store = temp.store();
    let upload = upload(
        &store,
        "project-a",
        b"{\"id\":1,\"id\":2}\n",
        BlobKind::Document,
    );
    let entry = SnapshotEntry {
        relative_path: "research/papers.jsonl".into(),
        upload_id: upload.upload_id.clone(),
    };
    assert!(store
        .seal_research_snapshot("project-a", std::slice::from_ref(&entry), None)
        .is_err());
    for path in ["../paper.jsonl", "/paper.jsonl", "a//b.jsonl", "a\\b.jsonl"] {
        assert!(store
            .seal_research_snapshot(
                "project-a",
                &[SnapshotEntry {
                    relative_path: path.into(),
                    ..entry.clone()
                }],
                None
            )
            .is_err());
    }
    let value = upload_bytes(&store, b"binary asset");
    assert!(store
        .seal_research_snapshot(
            "project-a",
            &[SnapshotEntry {
                relative_path: "asset.bin".into(),
                upload_id: value
            }],
            None
        )
        .is_err());
    assert_eq!(count(&temp.db(), "research_entries"), 0);
}
fn upload_bytes(store: &BusinessStore, bytes: &[u8]) -> String {
    upload(store, "project-a", bytes, BlobKind::Document).upload_id
}

#[test]
fn jsonl_larger_than_wire_limit_uses_small_verified_source_ref_command() {
    let temp = Temp::new();
    let store = temp.store();
    let mut data = Vec::new();
    for index in 0..80 {
        data.extend_from_slice(
            serde_json::to_string(
                &json!({"id":format!("p-{index}"),"rev":1,"title":"x","body":"a".repeat(20_000)}),
            )
            .unwrap()
            .as_bytes(),
        );
        data.push(b'\n');
    }
    assert!(data.len() > MAX_COMMAND_BYTES);
    let f = BTreeMap::from([("papers.jsonl".into(), data)]);
    let sealed = snapshot(&store, &f, None);
    assert_eq!(sealed.record_count, 80);
    assert!(!serde_json::to_value(&sealed)
        .unwrap()
        .as_object()
        .unwrap()
        .contains_key("records"));
    let c = import("import-a", 0, &sealed);
    let wire = serde_json::to_string(&c).unwrap();
    assert!(wire.len() < 4096);
    assert!(CommandEnvelope::decode(&wire).is_ok());
    assert_eq!(run(&store, &c).status, ExecutionStatus::Committed);
    assert_eq!(store.papers("project-a", 200, 0).unwrap().len(), 80);
}

#[test]
fn receipt_fault_rolls_back_paper_publication_and_cancel_blocks_original_retry() {
    let temp = Temp::new();
    let store = temp.store();
    let (c, blob) = manual(&store, "manual-a", "paper-a");
    let db = temp.db();
    db.exec("CREATE TRIGGER corrupt_paper_receipt AFTER UPDATE OF status ON intents WHEN NEW.status='committed' AND NEW.intent_id='manual-a' BEGIN UPDATE intents SET receipt_json='{}' WHERE intent_id=NEW.intent_id; END",&[]).unwrap();
    let result = run(&store, &c);
    assert_eq!(result.status, ExecutionStatus::Unknown);
    assert_eq!(count(&db, "research_entries"), 0);
    assert_eq!(count(&db, "research_documents"), 0);
    assert_eq!(count(&db, "blob_references"), 0);
    assert_eq!(
        store.lookup_upload(&blob.upload_id).unwrap().state,
        "pinned"
    );
    db.exec("DROP TRIGGER corrupt_paper_receipt", &[]).unwrap();
    assert_eq!(store.execute(&c).unwrap().status, ExecutionStatus::Unknown);
    assert_eq!(
        store.cancel_trusted(&c.intent_id).unwrap().status,
        ExecutionStatus::Cancelled
    );
    assert_eq!(
        store.execute(&c).unwrap().status,
        ExecutionStatus::Cancelled
    );
}

#[test]
fn committed_paper_after_process_kill_recovers_original_receipt_and_private_pdf() {
    let temp = Temp::new();
    let store = temp.store();
    let (c, blob) = manual(&store, "manual-a", "paper-a");
    let path = temp.0.join("command.json");
    fs::write(&path, serde_json::to_vec(&c).unwrap()).unwrap();
    drop(store);
    let mut child = Command::new(env!("CARGO_BIN_EXE_business_worker"))
        .arg("after-commit")
        .arg(temp.path())
        .arg(path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    assert_eq!(line.trim(), "COMMITTED_REPLY_WITHHELD");
    child.kill().unwrap();
    assert!(!child.wait().unwrap().success());
    let reopened = temp.reopen();
    let receipt = reopened.lookup("manual-a").unwrap();
    assert_eq!(receipt.status, ExecutionStatus::Committed);
    assert_eq!(reopened.execute(&c).unwrap(), receipt);
    assert_eq!(reopened.papers("project-a", 200, 0).unwrap().len(), 1);
    let reader = reopened
        .open_paper_attachment("project-a", "paper-a", &blob.blob.digest)
        .unwrap();
    reopened.close_blob_reader(reader).unwrap();
}

fn crc(bytes: &[u8]) -> u32 {
    let mut crc = !0u32;
    for byte in bytes {
        crc ^= *byte as u32;
        for _ in 0..8 {
            crc = (crc >> 1) ^ (0xedb88320 & (0u32.wrapping_sub(crc & 1)));
        }
    }
    !crc
}
fn put16(out: &mut Vec<u8>, v: u16) {
    out.extend_from_slice(&v.to_le_bytes());
}
fn put32(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_le_bytes());
}
fn stored_zip(files: &BTreeMap<String, Vec<u8>>) -> Vec<u8> {
    let mut out = Vec::new();
    let mut central = Vec::new();
    for (name, bytes) in files {
        let offset = out.len() as u32;
        let crc = crc(bytes);
        put32(&mut out, 0x04034b50);
        for v in [20, 0x800, 0, 0, 0] {
            put16(&mut out, v);
        }
        for v in [crc, bytes.len() as u32, bytes.len() as u32] {
            put32(&mut out, v);
        }
        put16(&mut out, name.len() as u16);
        put16(&mut out, 0);
        out.extend_from_slice(name.as_bytes());
        out.extend_from_slice(bytes);
        put32(&mut central, 0x02014b50);
        for v in [(3 << 8) | 20, 20, 0x800, 0, 0, 0] {
            put16(&mut central, v);
        }
        for v in [crc, bytes.len() as u32, bytes.len() as u32] {
            put32(&mut central, v);
        }
        for v in [name.len() as u16, 0, 0, 0, 0] {
            put16(&mut central, v);
        }
        put32(&mut central, 0o100600 << 16);
        put32(&mut central, offset);
        central.extend_from_slice(name.as_bytes());
    }
    let start = out.len() as u32;
    out.extend_from_slice(&central);
    put32(&mut out, 0x06054b50);
    for v in [0, 0, files.len() as u16, files.len() as u16] {
        put16(&mut out, v);
    }
    put32(&mut out, central.len() as u32);
    put32(&mut out, start);
    put16(&mut out, 0);
    out
}

#[test]
fn directory_and_real_stored_zip_produce_equivalent_records_and_bad_decoded_crc_fails() {
    let temp = Temp::new();
    let store = temp.store();
    let f = files("same", 1);
    let zip = stored_zip(&f);
    let directory = snapshot(&store, &f, None);
    let zipped = snapshot(&store, &f, Some(&zip));
    assert_eq!(directory.records_digest, zipped.records_digest);
    assert_eq!(directory.records, zipped.records);
    assert_eq!(
        run(&store, &import("zip-import", 0, &zipped)).status,
        ExecutionStatus::Committed
    );
    let mut altered = f.clone();
    altered.get_mut("research/papers.jsonl").unwrap()[5] ^= 1;
    let mut entries = Vec::new();
    for (path, bytes) in &altered {
        let file = upload(&store, "project-a", bytes, BlobKind::Document);
        entries.push(SnapshotEntry {
            relative_path: path.clone(),
            upload_id: file.upload_id,
        });
    }
    let archive = upload(&store, "project-a", &zip, BlobKind::Archive);
    assert!(matches!(
        store.seal_research_snapshot("project-a", &entries, Some(&archive.upload_id)),
        Err(ContractError::BindingMismatch)
    ));
}

#[test]
fn explicit_ambiguous_binding_choice_survives_refresh() {
    let temp = Temp::new();
    let store = temp.store();
    let mut f = files("first", 1);
    let second = json!({"schema_version":2,"id":"p2","rev":1,"title":"second","source_id":"s1","source_rev":1});
    f.get_mut("research/papers.jsonl")
        .unwrap()
        .extend_from_slice(format!("{}\n", second).as_bytes());
    let first = snapshot(&store, &f, None);
    run(&store, &import("import-a", 0, &first));
    let paper = store.papers("project-a", 200, 0).unwrap()[0].clone();
    let candidates = store.paper_bindings("project-a", &paper.id).unwrap();
    assert!(candidates[0].ambiguous);
    assert!(paper.attachments.is_empty());
    let doc = candidates[0].document_id.clone();
    store
        .choose_paper_binding_trusted("project-a", &doc, &paper.id)
        .unwrap();
    assert!(!store
        .paper("project-a", &paper.id)
        .unwrap()
        .attachments
        .is_empty());
    let next = snapshot(&store, &f, None);
    assert_eq!(
        run(&store, &import("import-b", 1, &next)).status,
        ExecutionStatus::Committed
    );
    let choice = store.paper_bindings("project-a", &paper.id).unwrap();
    assert_eq!(choice.len(), 1);
    assert!(choice[0].manual);
    assert!(!choice[0].ambiguous);
    assert!(choice[0].method.ends_with("+manual"));
}

#[test]
fn import_domain_tail_tampering_rolls_back_records_source_and_publication() {
    let temp = Temp::new();
    let store = temp.store();
    let frozen = snapshot(&store, &files("actual", 1), None);
    let db = temp.db();
    db.exec("CREATE TRIGGER corrupt_import AFTER UPDATE OF status ON intents WHEN NEW.status='committed' AND NEW.intent_id='import-a' BEGIN UPDATE research_entries SET raw_json='{}'; END",&[]).unwrap();
    let c = import("import-a", 0, &frozen);
    assert_eq!(run(&store, &c).status, ExecutionStatus::Unknown);
    assert_eq!(count(&db, "research_entries"), 0);
    assert_eq!(count(&db, "research_sources"), 0);
    assert_eq!(count(&db, "research_documents"), 0);
    assert_eq!(count(&db, "blob_references"), 0);
    assert_eq!(
        store
            .lookup_upload(&frozen.snapshot_upload_id)
            .unwrap()
            .state,
        "pinned"
    );
    assert_eq!(store.execute(&c).unwrap().status, ExecutionStatus::Unknown);
}

#[test]
fn loose_imported_metadata_uses_fallback_title_and_does_not_apply_manual_constraints() {
    let temp = Temp::new();
    let store = temp.store();
    let raw="  {\"title\":null,\"claim\":\"fallback claim\",\"rev\":\"01\",\"custom\":{\"score\":0.125}}  \n";
    let f = BTreeMap::from([("papers.jsonl".into(), raw.as_bytes().to_vec())]);
    let frozen = snapshot(&store, &f, None);
    assert_eq!(frozen.records[0].source_revision, Revision::new(1));
    let c = import("import-a", 0, &frozen);
    assert_eq!(run(&store, &c).status, ExecutionStatus::Committed);
    let paper = store.papers("project-a", 200, 0).unwrap()[0].clone();
    assert_eq!(paper.title, "fallback claim");
    assert_eq!(paper.raw_json, raw.trim_end_matches('\n'));
    assert!(paper.source_record_id.is_none());
}

#[test]
fn prefixed_skill_root_arxiv_manifest_binds_verified_pdf_hash() {
    let temp = Temp::new();
    let store = temp.store();
    let mut original = files("arxiv", 1);
    original.insert("research/papers.jsonl".into(),b"{\"schema_version\":2,\"id\":\"p1\",\"rev\":1,\"arxiv_id\":\"2301.00001\",\"version\":\"v1\"}\n".to_vec());
    original.insert("research/sources.jsonl".into(), b"\n".to_vec());
    original.remove("related_work/paper.pdf");
    original.insert("related_work/p1/versions/v1/paper.pdf".into(), PDF.to_vec());
    original.insert(
        "related_work/p1/versions/v1/manifest.json".into(),
        serde_json::to_vec(&json!({"arxiv_id":"2301.00001v1","sha256":{"paper.pdf":hash(PDF)}}))
            .unwrap(),
    );
    let f = original
        .into_iter()
        .map(|(path, bytes)| (format!("project/{path}"), bytes))
        .collect();
    let frozen = snapshot(&store, &f, None);
    assert_eq!(frozen.skill_root, "project/");
    assert_eq!(
        run(&store, &import("import-a", 0, &frozen)).status,
        ExecutionStatus::Committed
    );
    let paper = store.papers("project-a", 200, 0).unwrap()[0].clone();
    assert_eq!(paper.attachments.len(), 1);
    let binding = store.paper_bindings("project-a", &paper.id).unwrap();
    assert_eq!(binding[0].method, "arxiv_manifest");
    assert!(binding[0].hash_ok);
}

#[test]
fn api26_eleven_record_deflated_import_with_three_identical_empty_logs_commits() {
    let temp = Temp::new();
    let store = temp.store();
    let projects: Vec<_> = (0..11)
        .map(|index| format!("00000000-0000-4000-8000-{index:012x}"))
        .collect();
    for id in &projects {
        project(&store, id);
    }
    let selected = projects.iter().max().unwrap();
    let papers=(0..11).map(|index|json!({"schema_version":2,"id":format!("p{index}"),"rev":1,"title":format!("Imported-api26-{index}")}).to_string()).collect::<Vec<_>>().join("\n")+"\n";
    let files: BTreeMap<String, Vec<u8>> = BTreeMap::from([
        ("research/papers.jsonl".into(), papers.into_bytes()),
        ("research/sources.jsonl".into(), b"\n".to_vec()),
        ("research/claims.jsonl".into(), b"\n".to_vec()),
        ("research/opportunities.jsonl".into(), b"\n".to_vec()),
    ]);
    let mut entries = Vec::new();
    for (path, bytes) in &files {
        entries.push(SnapshotEntry {
            relative_path: path.clone(),
            upload_id: upload(&store, selected, bytes, BlobKind::Document).upload_id,
        });
    }
    let zip = deflated_zip(&files);
    let archive = upload(&store, selected, &zip, BlobKind::Archive);
    let frozen = store
        .seal_research_snapshot(selected, &entries, Some(&archive.upload_id))
        .unwrap();
    assert_eq!(frozen.record_count, 11);
    let c = cmd(
        "api26-import",
        selected,
        0,
        Operation::ResearchImport {
            source_id: "ffffffff-ffff-4fff-8fff-ffffffffffff".into(),
            source_revision: Revision::new(1),
            snapshot: frozen.snapshot,
            snapshot_upload_id: Some(frozen.snapshot_upload_id),
            records: Vec::new(),
        },
    );
    let result = run(&store, &c);
    assert_eq!(result.status, ExecutionStatus::Committed, "{result:?}");
    assert_eq!(store.papers(selected, 200, 0).unwrap().len(), 11);
}

fn deflated_zip(files: &BTreeMap<String, Vec<u8>>) -> Vec<u8> {
    let mut out = Vec::new();
    let mut central = Vec::new();
    for (name, bytes) in files {
        assert!(bytes.len() < 65536);
        // A real raw-DEFLATE final stored block, no external compression dependency.
        let n = bytes.len() as u16;
        let mut compressed = vec![1];
        put16(&mut compressed, n);
        put16(&mut compressed, !n);
        compressed.extend_from_slice(bytes);
        let offset = out.len() as u32;
        let crc = crc(bytes);
        put32(&mut out, 0x04034b50);
        for v in [20, 0x800, 8, 0, 0] {
            put16(&mut out, v);
        }
        for v in [crc, compressed.len() as u32, bytes.len() as u32] {
            put32(&mut out, v);
        }
        put16(&mut out, name.len() as u16);
        put16(&mut out, 0);
        out.extend_from_slice(name.as_bytes());
        out.extend_from_slice(&compressed);
        put32(&mut central, 0x02014b50);
        for v in [(3 << 8) | 20, 20, 0x800, 8, 0, 0] {
            put16(&mut central, v);
        }
        for v in [crc, compressed.len() as u32, bytes.len() as u32] {
            put32(&mut central, v);
        }
        for v in [name.len() as u16, 0, 0, 0, 0] {
            put16(&mut central, v);
        }
        put32(&mut central, 0o100600 << 16);
        put32(&mut central, offset);
        central.extend_from_slice(name.as_bytes());
    }
    let start = out.len() as u32;
    out.extend_from_slice(&central);
    put32(&mut out, 0x06054b50);
    for v in [0, 0, files.len() as u16, files.len() as u16] {
        put16(&mut out, v);
    }
    put32(&mut out, central.len() as u32);
    put32(&mut out, start);
    put16(&mut out, 0);
    out
}
