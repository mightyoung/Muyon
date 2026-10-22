//! Research catalog and trusted immutable-file import. Wire records are never a file oracle.
use crate::{
    archive::{parse_archive, DecodedEntryValidator},
    blobs::{BlobKind, ControlledReader, MAX_CHUNK},
    business::BusinessStore,
    contract::*,
    sqlite::{Db, Transaction},
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use unicode_normalization::UnicodeNormalization;
#[cfg(test)]
thread_local! { static AGGREGATE_READS:std::cell::Cell<usize>=const {std::cell::Cell::new(0)}; }
type Result<T> = std::result::Result<T, ContractError>;
const KINDS: &[&str] = &[
    "sources",
    "papers",
    "claims",
    "assertions",
    "opportunities",
    "searches",
    "tensions",
    "experiments",
    "failures",
    "handoffs",
];

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SnapshotEntry {
    pub relative_path: String,
    pub upload_id: String,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SealedResearchSnapshot {
    pub snapshot_upload_id: String,
    pub snapshot: BlobRef,
    pub records_digest: String,
    pub record_count: usize,
    #[serde(skip_serializing, default)]
    pub records: Vec<ImportedPaper>,
    pub layout: String,
    pub skill_root: String,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct PaperRecord {
    pub id: String,
    pub project_id: String,
    pub kind: String,
    pub title: String,
    pub raw_json: String,
    pub source_id: Option<String>,
    pub source_record_id: Option<Value>,
    pub source_revision: Option<Revision>,
    pub revision: Revision,
    pub manual: bool,
    pub attachments: Vec<BlobRef>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DocumentRecord {
    pub id: String,
    pub project_id: String,
    pub relative_path: String,
    pub blob: BlobRef,
    pub retained: bool,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PaperBinding {
    pub document_id: String,
    pub paper_id: String,
    pub paper_revision: Revision,
    pub method: String,
    pub hash_ok: bool,
    pub ambiguous: bool,
    pub manual: bool,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResearchSourceRecord {
    pub source_id: String,
    pub project_id: String,
    pub revision: Revision,
    pub external_revision: Revision,
    pub layout: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct FrozenFile {
    path: String,
    upload_id: String,
    blob: BlobRef,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct FrozenManifest {
    format: String,
    project_id: String,
    project_revision: Revision,
    owner_epoch: String,
    files: Vec<FrozenFile>,
    archive: Option<FrozenFile>,
    records_digest: String,
}
#[derive(Clone, Debug)]
struct ParsedEntry {
    paper: ImportedPaper,
    kind: String,
    title: String,
    key: String,
    content_digest: String,
}
struct Prepared {
    manifest: FrozenManifest,
    entries: Vec<ParsedEntry>,
    documents: Vec<FrozenFile>,
    manifests: BTreeMap<String, Value>,
    layout: String,
    root: String,
}
fn sql<T>(result: crate::sqlite::Result<T>) -> Result<T> {
    result.map_err(|_| ContractError::Storage)
}
fn cell(row: &[Option<String>], i: usize) -> Result<&str> {
    row.get(i)
        .and_then(Option::as_deref)
        .ok_or(ContractError::StorageCorrupt)
}
fn text<T: Serialize>(v: &T) -> Result<String> {
    serde_json::to_string(v).map_err(|_| ContractError::InvalidPayload)
}
fn stable_id(prefix: &str, v: Value) -> Result<String> {
    Ok(format!("{prefix}-{}", stable_digest(&v)?))
}
fn path_valid(path: &str) -> Result<()> {
    if path.is_empty()
        || path.len() > 1024
        || path.contains(['\\', ':'])
        || path.chars().any(char::is_control)
        || path
            .split('/')
            .any(|p| p.is_empty() || p == "." || p == "..")
    {
        Err(ContractError::InvalidPayload)
    } else {
        Ok(())
    }
}
fn revision_of(record: &Value) -> Revision {
    match &record["rev"] {
        Value::String(s) => Revision::new(s.parse::<u64>().unwrap_or(0)),
        Value::Number(n) => Revision::new(n.as_u64().unwrap_or(0)),
        _ => Revision::new(0),
    }
}
fn record_title(record: &Value, fallback: &str) -> String {
    let value = [
        "title",
        "claim",
        "statement",
        "observation",
        "query",
        "step",
        "cause",
        "name",
        "id",
    ]
    .iter()
    .find_map(|key| record.get(*key).filter(|v| !v.is_null()));
    let raw = match value {
        Some(Value::String(s)) => s.clone(),
        Some(value) => value.to_string(),
        None => fallback.into(),
    };
    raw.chars().take(500).collect()
}
fn detect_root(files: &[FrozenFile]) -> Option<String> {
    let names: BTreeSet<_> = files.iter().map(|f| f.path.as_str()).collect();
    files
        .iter()
        .filter_map(|file| file.path.strip_suffix("research/papers.jsonl"))
        .filter(|prefix| prefix.is_empty() || prefix.ends_with('/'))
        .filter(|prefix| {
            ["papers", "claims", "sources", "opportunities"]
                .iter()
                .all(|kind| names.contains(format!("{prefix}research/{kind}.jsonl").as_str()))
        })
        .min_by_key(|root| root.len())
        .map(str::to_owned)
}
fn skipped(path: &str, root: &str) -> bool {
    let Some(path) = path.strip_prefix(root) else {
        return false;
    };
    let parts: Vec<_> = path.split('/').collect();
    parts
        .iter()
        .any(|p| ["__pycache__", ".shot-tmp", ".git"].contains(p))
        || parts.first() == Some(&"DataSet")
        || parts.first() == Some(&"experiment") && parts.contains(&"checkpoints")
        || path.to_lowercase().ends_with(".pt")
        || parts.first() == Some(&"related_work")
            && (parts.last() == Some(&".fetch.lock")
                || parts.iter().any(|p| p.starts_with(".stage-"))
                || parts.len() > 5 && parts[2] == "versions" && parts[4] == "source")
}

impl BusinessStore {
    fn read_private(&self, mut reader: ControlledReader) -> Result<Vec<u8>> {
        let result = (|| {
            let mut bytes = Vec::new();
            loop {
                let chunk = self.read_blob_chunk(&mut reader, MAX_CHUNK)?;
                if chunk.is_empty() {
                    break;
                }
                bytes.extend_from_slice(&chunk);
                if bytes.len() > 150 * 1024 * 1024 {
                    return Err(ContractError::TextLimit);
                }
            }
            Ok(bytes)
        })();
        let close = self.close_blob_reader(reader);
        match result {
            Ok(bytes) => {
                close?;
                Ok(bytes)
            }
            Err(error) => Err(error),
        }
    }
    fn upload_bytes(&self, project: &str, upload_id: &str) -> Result<(BlobRef, Vec<u8>)> {
        #[cfg(test)]
        AGGREGATE_READS.with(|counter| counter.set(counter.get() + 1));
        let reader = self.upload_reader(project, upload_id)?;
        let blob = reader.source().blob.clone();
        let bytes = self.read_private(reader)?;
        Ok((blob, bytes))
    }
    fn upload_reader(&self, project: &str, upload_id: &str) -> Result<ControlledReader> {
        let status = self.lookup_upload(upload_id)?;
        if status.project_id != project {
            return Err(ContractError::ScopeMismatch);
        }
        if status.state != "pinned" {
            return Err(ContractError::IntentConflict);
        }
        self.open_upload_reader(upload_id)
    }
    fn verify_pdf_reader(&self, mut reader: ControlledReader, expected: &BlobRef) -> Result<()> {
        let result = (|| {
            if &reader.source().blob != expected {
                return Err(ContractError::BindingMismatch);
            }
            let mut header = Vec::new();
            let mut tail = Vec::new();
            loop {
                let chunk = self.read_blob_chunk(&mut reader, MAX_CHUNK)?;
                if chunk.is_empty() {
                    break;
                }
                if header.len() < 5 {
                    header.extend_from_slice(&chunk[..chunk.len().min(5 - header.len())]);
                }
                if chunk.len() >= 1024 {
                    tail.clear();
                    tail.extend_from_slice(&chunk[chunk.len() - 1024..]);
                } else {
                    tail.extend_from_slice(&chunk);
                    if tail.len() > 1024 {
                        tail.drain(..tail.len() - 1024);
                    }
                }
            }
            if header != b"%PDF-" || !tail.windows(5).any(|bytes| bytes == b"%%EOF") {
                return Err(ContractError::InvalidPayload);
            }
            Ok(())
        })();
        let close = self.close_blob_reader(reader);
        result?;
        close
    }
    fn upload_descriptor(&self, project: &str, upload_id: &str) -> Result<BlobRef> {
        // P05 hashes the actual file in bounded chunks while opening this lease.
        let reader = self.upload_reader(project, upload_id)?;
        let blob = reader.source().blob.clone();
        self.close_blob_reader(reader)?;
        Ok(blob)
    }
    fn verify_decoded_upload(
        &self,
        project: &str,
        file: &FrozenFile,
        member: &crate::archive::ArchiveMember,
        archive: &[u8],
    ) -> Result<()> {
        let mut reader = self.upload_reader(project, &file.upload_id)?;
        let result = (|| {
            if reader.source().blob != file.blob {
                return Err(ContractError::BindingMismatch);
            }
            let mut validator = DecodedEntryValidator::new(member);
            let mut offset = member.data_offset as usize;
            loop {
                let chunk = self.read_blob_chunk(&mut reader, MAX_CHUNK)?;
                if chunk.is_empty() {
                    break;
                }
                validator.update(&chunk)?;
                if member.method == ArchiveMethod::Stored {
                    let end = offset
                        .checked_add(chunk.len())
                        .ok_or(ContractError::TextLimit)?;
                    if archive.get(offset..end) != Some(chunk.as_slice()) {
                        return Err(ContractError::BindingMismatch);
                    }
                    offset = end;
                }
            }
            validator.finish()
        })();
        let close = self.close_blob_reader(reader);
        result?;
        close
    }

    /// HOST FILE PORT ONLY. Reads real frozen private uploads, never caller JSON records.
    /// For ZIP, the trusted platform inflater supplies frozen decoded members;
    /// Rust independently checks A01 metadata plus every decoded CRC/length.
    pub fn seal_research_snapshot(
        &self,
        project_id: &str,
        entries: &[SnapshotEntry],
        original_archive_upload_id: Option<&str>,
    ) -> Result<SealedResearchSnapshot> {
        let project = self.project(project_id)?;
        if project.deleted {
            return Err(ContractError::NotFound);
        }
        if entries.is_empty() || entries.len() > 10_000 {
            return Err(ContractError::TextLimit);
        }
        let mut names = BTreeSet::new();
        let mut uploads = BTreeSet::new();
        let mut files = Vec::new();
        let mut total = 0u64;
        for entry in entries {
            path_valid(&entry.relative_path)?;
            if !names.insert(entry.relative_path.nfc().collect::<String>())
                || !uploads.insert(entry.upload_id.clone())
            {
                return Err(ContractError::InvalidPayload);
            }
        }
        for name in &names {
            let mut prefix = String::new();
            let parts: Vec<_> = name.split('/').collect();
            for part in parts.iter().take(parts.len() - 1) {
                if !prefix.is_empty() {
                    prefix.push('/');
                }
                prefix.push_str(part);
                if names.contains(&prefix) {
                    return Err(ContractError::InvalidPayload);
                }
            }
        }
        let candidates: Vec<_> = entries
            .iter()
            .map(|entry| FrozenFile {
                path: entry.relative_path.clone(),
                upload_id: entry.upload_id.clone(),
                blob: BlobRef {
                    digest: "0".repeat(64),
                    byte_length: Revision::new(1),
                },
            })
            .collect();
        let detected = detect_root(&candidates);
        for entry in entries {
            if detected
                .as_ref()
                .is_some_and(|root| skipped(&entry.relative_path, root))
            {
                continue;
            }
            let blob = self.upload_descriptor(project_id, &entry.upload_id)?;
            total = total
                .checked_add(blob.byte_length.value())
                .ok_or(ContractError::TextLimit)?;
            if blob.byte_length.value() > 30 * 1024 * 1024 || total > 150 * 1024 * 1024 {
                return Err(ContractError::TextLimit);
            }
            files.push(FrozenFile {
                path: entry.relative_path.clone(),
                upload_id: entry.upload_id.clone(),
                blob,
            });
        }
        files.sort_by(|a, b| a.path.cmp(&b.path));
        let root = detect_root(&files);
        let archive = if let Some(upload_id) = original_archive_upload_id {
            if uploads.contains(upload_id) {
                return Err(ContractError::InvalidPayload);
            }
            let (blob, bytes) = self.upload_bytes(project_id, upload_id)?;
            let manifest = parse_archive(&bytes)?;
            let kept: Vec<_> = manifest
                .entries
                .iter()
                .filter(|m| root.as_ref().is_none_or(|root| !skipped(&m.name, root)))
                .collect();
            let provided: Vec<_> = files
                .iter()
                .filter(|f| root.as_ref().is_none_or(|root| !skipped(&f.path, root)))
                .collect();
            if kept.len() != provided.len() {
                return Err(ContractError::BindingMismatch);
            }
            for member in kept {
                let file = files
                    .iter()
                    .find(|file| file.path == member.name)
                    .ok_or(ContractError::BindingMismatch)?;
                self.verify_decoded_upload(project_id, file, member, &bytes)?;
            }
            Some(FrozenFile {
                path: "archive.zip".into(),
                upload_id: upload_id.into(),
                blob,
            })
        } else {
            None
        };
        if let Some(root) = &root {
            files.retain(|file| !skipped(&file.path, root));
        }
        let (parsed, _, _, layout, skill_root) = parse_files(&files, |file| {
            self.upload_bytes(project_id, &file.upload_id)
                .map(|(_, bytes)| bytes)
        })?;
        let records_digest = record_fingerprint(&parsed)?;
        let records: Vec<_> = parsed.into_iter().map(|entry| entry.paper).collect();
        let manifest = FrozenManifest {
            format: "muyon-research-snapshot-v1".into(),
            project_id: project_id.into(),
            project_revision: project.revision,
            owner_epoch: self.owner_epoch().into(),
            files,
            archive,
            records_digest: records_digest.clone(),
        };
        let bytes = serde_json::to_vec(&manifest).map_err(|_| ContractError::InvalidPayload)?;
        if bytes.len() > 30 * 1024 * 1024 {
            return Err(ContractError::TextLimit);
        }
        let upload = self.begin_upload(project_id)?;
        let finished = (|| {
            for chunk in bytes.chunks(MAX_CHUNK) {
                self.append_chunk(&upload.upload_id, chunk)?;
            }
            self.finish_blob(&upload.upload_id, BlobKind::Document)
        })();
        let finished = match finished {
            Ok(value) => value,
            Err(error) => {
                let _ = self.abort_upload(&upload.upload_id);
                return Err(error);
            }
        };
        sql(self.database().exec("INSERT INTO research_snapshots(upload_id,project_id,project_revision,owner_epoch,digest,byte_length,records_digest) VALUES(?,?,?,?,?,?,?)",&[&finished.upload_id,project_id,manifest.project_revision.as_str(),self.owner_epoch(),&finished.blob.digest,finished.blob.byte_length.as_str(),&records_digest]))?;
        Ok(SealedResearchSnapshot {
            snapshot_upload_id: finished.upload_id,
            snapshot: finished.blob,
            records_digest,
            record_count: records.len(),
            records,
            layout,
            skill_root,
        })
    }

    fn load_prepared_snapshot(&self, command: &CommandEnvelope) -> Result<Prepared> {
        let Operation::ResearchImport {
            snapshot,
            snapshot_upload_id,
            records,
            ..
        } = &command.command
        else {
            return Err(ContractError::UnsupportedOperation);
        };
        let project = command
            .scope
            .project_id
            .as_deref()
            .ok_or(ContractError::ScopeMismatch)?;
        let upload_id = snapshot_upload_id
            .as_deref()
            .ok_or(ContractError::BindingMismatch)?;
        let rows=sql(self.database().query("SELECT project_id,project_revision,owner_epoch,digest,byte_length,records_digest FROM research_snapshots WHERE upload_id=?",&[upload_id]))?;
        let row = rows.first().ok_or(ContractError::BindingMismatch)?;
        if cell(row, 0)? != project
            || cell(row, 1)? != self.project(project)?.revision.as_str()
            || cell(row, 2)? != self.owner_epoch()
            || cell(row, 3)? != snapshot.digest
            || cell(row, 4)? != snapshot.byte_length.as_str()
        {
            return Err(ContractError::BindingMismatch);
        }
        let (actual, bytes) = self.upload_bytes(project, upload_id)?;
        if &actual != snapshot {
            return Err(ContractError::BindingMismatch);
        }
        let manifest: FrozenManifest =
            serde_json::from_slice(&bytes).map_err(|_| ContractError::InvalidPayload)?;
        drop(bytes);
        if manifest.format != "muyon-research-snapshot-v1"
            || manifest.project_id != project
            || manifest.project_revision != self.project(project)?.revision
            || manifest.owner_epoch != self.owner_epoch()
            || manifest.files.len() > 10_000
        {
            return Err(ContractError::BindingMismatch);
        }
        for file in &manifest.files {
            let blob = self.upload_descriptor(project, &file.upload_id)?;
            if blob != file.blob {
                return Err(ContractError::BindingMismatch);
            }
        }
        let (entries, documents, manifests, layout, root) = parse_files(&manifest.files, |file| {
            self.upload_bytes(project, &file.upload_id)
                .map(|(_, bytes)| bytes)
        })?;
        let digest = record_fingerprint(&entries)?;
        if digest != manifest.records_digest
            || digest != cell(row, 5)?
            || !records.is_empty() && !records.iter().eq(entries.iter().map(|entry| &entry.paper))
        {
            return Err(ContractError::BindingMismatch);
        }
        Ok(Prepared {
            manifest,
            entries,
            documents,
            manifests,
            layout,
            root,
        })
    }

    pub(crate) fn execute_research(&self, command: &CommandEnvelope) -> Result<ExecutionResult> {
        if let Some(result) = self.existing_execution(command)? {
            return Ok(result);
        }
        match &command.command {
            Operation::PaperCreate { payload, .. } => {
                let project = command
                    .scope
                    .project_id
                    .as_deref()
                    .ok_or(ContractError::ScopeMismatch)?;
                self.project(project)?;
                let reader = if let Some(upload) = &payload.attachment_upload_id {
                    if self.lookup_upload(upload)?.kind != Some(BlobKind::Pdf) {
                        return Err(ContractError::InvalidPayload);
                    }
                    self.upload_reader(project, upload)?
                } else {
                    self.open_blob_reader(project, &payload.attachment)?
                };
                self.verify_pdf_reader(reader, &payload.attachment)?;
                self.execute_with(command, |db, tx, command| {
                    self.create_manual_paper(db, tx, command)
                })
            }
            Operation::ResearchImport { .. } => {
                let prepared = self.load_prepared_snapshot(command)?;
                self.execute_with(command, |db, tx, command| {
                    self.import_prepared(db, tx, command, &prepared)
                })
            }
            _ => Err(ContractError::UnsupportedOperation),
        }
    }

    fn create_manual_paper(
        &self,
        db: &Db,
        tx: &Transaction<'_>,
        command: &CommandEnvelope,
    ) -> Result<Value> {
        let Operation::PaperCreate { paper_id, payload } = &command.command else {
            return Err(ContractError::UnsupportedOperation);
        };
        let project = command
            .scope
            .project_id
            .as_deref()
            .ok_or(ContractError::ScopeMismatch)?;
        self.project(project)?;
        if !sql(db.query("SELECT id FROM research_entries WHERE id=?", &[paper_id]))?.is_empty() {
            return Err(ContractError::RevisionConflict);
        }
        let reference_id = stable_id("ref", json!([command.intent_id, "manual-pdf"]))?;
        if let Some(upload) = &payload.attachment_upload_id {
            if self.lookup_upload(upload)?.kind != Some(BlobKind::Pdf) {
                return Err(ContractError::InvalidPayload);
            }
            self.publish_blob_in_transaction(
                tx,
                upload,
                &reference_id,
                project,
                paper_id,
                &payload.attachment,
            )?;
        } else {
            let refs = sql(db.query(
                "SELECT reference_id FROM blob_references WHERE project_id=? AND digest=?",
                &[project, &payload.attachment.digest],
            ))?;
            if refs.is_empty() {
                return Err(ContractError::InvalidAuthority);
            }
            sql(db.exec("INSERT INTO blob_references(reference_id,project_id,target_id,digest) VALUES(?,?,?,?)",&[&reference_id,project,paper_id,&payload.attachment.digest]))?;
        }
        let title = normalize_text(&payload.title, 500, true)?.unwrap();
        let metadata = json!({"title":title,"authors":payload.authors,"year":payload.year,"doi":payload.doi,"url":payload.url,"notes":payload.notes});
        let raw = text(&metadata)?;
        let digest = stable_digest(&metadata)?;
        sql(db.exec("INSERT INTO research_entries(id,project_id,source_id,entry_key,kind,title,raw_json,content_digest,source_record_id,source_revision,revision,manual) VALUES(?,?,NULL,?,'papers',?,?,?,NULL,NULL,'1',1)",&[paper_id,project,paper_id,&title,&raw,&digest]))?;
        let doc_id = stable_id("doc", json!([project, paper_id]))?;
        sql(db.exec("INSERT INTO research_documents(id,project_id,source_id,relative_path,digest,byte_length) VALUES(?,?,NULL,?,?,?)",&[&doc_id,project,&format!("manual/{paper_id}.pdf"),&payload.attachment.digest,payload.attachment.byte_length.as_str()]))?;
        sql(db.exec("INSERT INTO research_bindings(document_id,paper_id,paper_revision,method,hash_ok,ambiguous,manual) VALUES(?,?,'1','manual_pdf',1,0,1)",&[&doc_id,paper_id]))?;
        serde_json::to_value(self.paper(project, paper_id)?).map_err(|_| ContractError::Storage)
    }

    fn import_prepared(
        &self,
        db: &Db,
        tx: &Transaction<'_>,
        command: &CommandEnvelope,
        prepared: &Prepared,
    ) -> Result<Value> {
        let Operation::ResearchImport {
            source_id,
            source_revision,
            snapshot,
            snapshot_upload_id,
            ..
        } = &command.command
        else {
            return Err(ContractError::UnsupportedOperation);
        };
        let project = command
            .scope
            .project_id
            .as_deref()
            .ok_or(ContractError::ScopeMismatch)?;
        self.project(project)?;
        let previous = sql(db.query(
            "SELECT project_id,revision FROM research_sources WHERE source_id=?",
            &[source_id],
        ))?;
        if let Some(row) = previous.first() {
            if cell(row, 0)? != project {
                return Err(ContractError::ScopeMismatch);
            }
            if cell(row, 1)? != command.expected_revision.as_str() {
                return Err(ContractError::RevisionConflict);
            }
        } else if command.expected_revision.value() != 0 {
            return Err(ContractError::RevisionConflict);
        }
        let mut old: BTreeMap<String, Vec<PaperRecord>> = BTreeMap::new();
        let mut manual_choices: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for row in sql(db.query("SELECT b.document_id,b.paper_id FROM research_bindings b JOIN research_documents d ON d.id=b.document_id WHERE d.project_id=? AND d.source_id=? AND b.manual=1",&[project,source_id]))? {manual_choices.entry(cell(&row,0)?.into()).or_default().push(cell(&row,1)?.into());}
        for row in sql(db.query("SELECT id,entry_key FROM research_entries WHERE source_id=? AND project_id=? ORDER BY rowid",&[source_id,project]))? {old.entry(cell(&row,1)?.into()).or_default().push(self.entry(project,cell(&row,0)?)?);}
        let mut inserted = 0;
        let mut reused = 0;
        let mut incoming = BTreeSet::new();
        let mut local_entries = Vec::new();
        let mut duplicates = 0;
        for (index, entry) in prepared.entries.iter().enumerate() {
            if !incoming.insert(entry.key.clone()) {
                duplicates += 1;
            }
            let candidates = old.entry(entry.key.clone()).or_default();
            let mut pick = None;
            for (i, old) in candidates.iter().enumerate() {
                let same =
                    stable_digest(&decode_research_json(&old.raw_json)?)? == entry.content_digest;
                if same && self.entry_cited(&old.id)? {
                    pick = Some(i);
                    break;
                }
            }
            if pick.is_none() {
                pick = candidates.iter().position(|old| {
                    decode_research_json(&old.raw_json)
                        .and_then(|v| stable_digest(&v))
                        .ok()
                        .as_deref()
                        == Some(entry.content_digest.as_str())
                });
            }
            if pick.is_none() {
                for (i, old) in candidates.iter().enumerate() {
                    if !self.entry_cited(&old.id)? {
                        pick = Some(i);
                        break;
                    }
                }
            }
            let (id, entry_revision) = if let Some(i) = pick {
                reused += 1;
                let previous = candidates.remove(i);
                let next = previous.revision.next()?;
                (previous.id, next)
            } else {
                inserted += 1;
                (
                    stable_id("entry", json!([command.intent_id, index]))?,
                    Revision::new(1),
                )
            };
            let raw_id = entry
                .paper
                .record
                .get("id")
                .filter(|v| !v.is_null())
                .map(text)
                .transpose()?;
            sql(db.exec("INSERT INTO research_entries(id,project_id,source_id,entry_key,kind,title,raw_json,content_digest,source_record_id,source_revision,revision,manual) VALUES(?,?,?,?,?,?,?,?,NULL,?,?,0) ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,title=excluded.title,raw_json=excluded.raw_json,content_digest=excluded.content_digest,source_revision=excluded.source_revision,revision=excluded.revision",&[&id,project,source_id,&entry.key,&entry.kind,&entry.title,&entry.paper.raw_json,&entry.content_digest,entry.paper.source_revision.as_str(),entry_revision.as_str()]))?;
            if let Some(raw_id) = raw_id {
                sql(db.exec(
                    "UPDATE research_entries SET source_record_id=? WHERE id=?",
                    &[&raw_id, &id],
                ))?;
            }
            sql(db.exec("INSERT INTO research_import_members(intent_id,entry_id,raw_digest,content_digest,source_revision,title) VALUES(?,?,?,?,?,?)",&[&command.intent_id,&id,&stable_digest(&Value::String(entry.paper.raw_json.clone()))?,&entry.content_digest,entry.paper.source_revision.as_str(),&entry.title]))?;
            local_entries.push((id, entry));
        }
        let mut removed = 0;
        let mut retained = 0;
        for (key, records) in old {
            for old in records {
                if self.entry_cited(&old.id)? {
                    if incoming.contains(&key) {
                        return Err(ContractError::RevisionConflict);
                    }
                    retained += 1;
                } else {
                    sql(db.exec("DELETE FROM research_bindings WHERE paper_id=?", &[&old.id]))?;
                    sql(db.exec("DELETE FROM research_entries WHERE id=?", &[&old.id]))?;
                    removed += 1;
                }
            }
        }
        let mut old_docs: BTreeMap<String, DocumentRecord> = BTreeMap::new();
        for row in sql(db.query("SELECT id,relative_path FROM research_documents WHERE source_id=? AND project_id=? AND retained=0 ORDER BY rowid",&[source_id,project]))? {old_docs.insert(cell(&row,1)?.into(),self.document(project,cell(&row,0)?)?);}
        let mut documents = BTreeMap::new();
        let mut carry: Vec<(String, Vec<String>)> = Vec::new();
        for file in &prepared.documents {
            let path = project_path(&file.path, &prepared.root);
            let previous = old_docs.remove(&path);
            let choices = previous
                .as_ref()
                .and_then(|old| manual_choices.get(&old.id))
                .cloned();
            let keep = if let Some(old) = &previous {
                old.blob != file.blob && self.document_cited(&old.id)?
            } else {
                false
            };
            if keep {
                sql(db.exec(
                    "UPDATE research_documents SET retained=1 WHERE id=?",
                    &[&previous.as_ref().unwrap().id],
                ))?;
            }
            let id = if !keep {
                previous
                    .map(|d| d.id)
                    .unwrap_or(stable_id("doc", json!([command.intent_id, path]))?)
            } else {
                stable_id("doc", json!([command.intent_id, path]))?
            };
            sql(db.exec("DELETE FROM research_bindings WHERE document_id=?", &[&id]))?;
            sql(db.exec("INSERT INTO research_documents(id,project_id,source_id,relative_path,digest,byte_length) VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET relative_path=excluded.relative_path,digest=excluded.digest,byte_length=excluded.byte_length,retained=0",&[&id,project,source_id,&path,&file.blob.digest,file.blob.byte_length.as_str()]))?;
            if let Some(choices) = choices {
                carry.push((id.clone(), choices));
            }
            documents.insert(path, (id, file.blob.clone()));
        }
        for old in old_docs.into_values() {
            if self.document_cited(&old.id)? {
                sql(db.exec(
                    "UPDATE research_documents SET retained=1 WHERE id=?",
                    &[&old.id],
                ))?;
            } else {
                sql(db.exec(
                    "DELETE FROM research_bindings WHERE document_id=?",
                    &[&old.id],
                ))?;
                sql(db.exec("DELETE FROM research_documents WHERE id=?", &[&old.id]))?;
            }
        }
        self.bind_imported_papers(db, &local_entries, &documents, &prepared.manifests)?;
        for (doc, papers) in carry {
            for paper in papers {
                let rows = sql(db.query(
                    "SELECT ambiguous FROM research_bindings WHERE document_id=? AND paper_id=?",
                    &[&doc, &paper],
                ))?;
                if rows.first().and_then(|row| row[0].as_deref()) == Some("1") {
                    self.apply_binding_choice(db, project, &doc, &paper)?;
                }
            }
        }
        let mut publication = prepared.manifest.files.clone();
        if let Some(archive) = &prepared.manifest.archive {
            publication.push(archive.clone());
        }
        publication.push(FrozenFile {
            path: "sealed-manifest".into(),
            upload_id: snapshot_upload_id
                .clone()
                .ok_or(ContractError::BindingMismatch)?,
            blob: snapshot.clone(),
        });
        for (index, file) in publication.iter().enumerate() {
            self.publish_blob_in_transaction(
                tx,
                &file.upload_id,
                &stable_id("ref", json!([command.intent_id, index]))?,
                project,
                source_id,
                &file.blob,
            )?;
        }
        let next = command.expected_revision.next()?;
        sql(db.exec("INSERT INTO research_sources(source_id,project_id,revision,external_revision,snapshot_digest,snapshot_upload_id,records_digest,layout,skill_root) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(source_id) DO UPDATE SET revision=excluded.revision,external_revision=excluded.external_revision,snapshot_digest=excluded.snapshot_digest,snapshot_upload_id=excluded.snapshot_upload_id,records_digest=excluded.records_digest,layout=excluded.layout,skill_root=excluded.skill_root",&[source_id,project,next.as_str(),source_revision.as_str(),&snapshot.digest,snapshot_upload_id.as_deref().unwrap(),&prepared.manifest.records_digest,&prepared.layout,&prepared.root]))?;
        Ok(
            json!({"source_id":source_id,"project_id":project,"revision":next,"external_revision":source_revision,"entries":prepared.entries.len(),"documents":prepared.documents.len(),"inserted":inserted,"reused":reused,"removed":removed,"retained_cited":retained,"duplicate_id_revisions":duplicates,"records_digest":prepared.manifest.records_digest,"layout":prepared.layout}),
        )
    }

    fn entry_cited(&self, id: &str) -> Result<bool> {
        Ok(!sql(self.database().query(
            "SELECT citation_id FROM research_citations WHERE entry_id=?",
            &[id],
        ))?
        .is_empty())
    }
    fn document_cited(&self, id: &str) -> Result<bool> {
        Ok(!sql(self.database().query(
            "SELECT citation_id FROM research_citations WHERE document_id=?",
            &[id],
        ))?
        .is_empty())
    }
    pub fn entry(&self, project: &str, id: &str) -> Result<PaperRecord> {
        self.project(project)?;
        let rows=sql(self.database().query("SELECT id,project_id,kind,title,raw_json,source_id,source_record_id,source_revision,revision,manual FROM research_entries WHERE id=? AND project_id=?",&[id,project]))?;
        let row = rows.first().ok_or(ContractError::NotFound)?;
        let blobs=sql(self.database().query("SELECT DISTINCT d.digest,d.byte_length FROM research_documents d JOIN research_bindings b ON b.document_id=d.id WHERE b.paper_id=? AND d.project_id=? AND b.hash_ok=1 AND b.ambiguous=0",&[id,project]))?;
        Ok(PaperRecord {
            id: cell(row, 0)?.into(),
            project_id: cell(row, 1)?.into(),
            kind: cell(row, 2)?.into(),
            title: cell(row, 3)?.into(),
            raw_json: cell(row, 4)?.into(),
            source_id: row[5].clone(),
            source_record_id: row[6]
                .as_ref()
                .map(|v| serde_json::from_str(v).map_err(|_| ContractError::StorageCorrupt))
                .transpose()?,
            source_revision: row[7].as_deref().map(Revision::parse).transpose()?,
            revision: Revision::parse(cell(row, 8)?)?,
            manual: cell(row, 9)? == "1",
            attachments: blobs
                .iter()
                .map(|row| {
                    Ok(BlobRef {
                        digest: cell(row, 0)?.into(),
                        byte_length: Revision::parse(cell(row, 1)?)?,
                    })
                })
                .collect::<Result<_>>()?,
        })
    }
    pub fn paper(&self, project: &str, id: &str) -> Result<PaperRecord> {
        let entry = self.entry(project, id)?;
        if entry.kind != "papers" {
            Err(ContractError::NotFound)
        } else {
            Ok(entry)
        }
    }
    pub fn entries(&self, project: &str, limit: u32, offset: u32) -> Result<Vec<PaperRecord>> {
        self.list_entries(project, None, limit, offset)
    }
    pub fn papers(&self, project: &str, limit: u32, offset: u32) -> Result<Vec<PaperRecord>> {
        self.list_entries(project, Some("papers"), limit, offset)
    }
    pub fn research_sources(&self, project: &str) -> Result<Vec<ResearchSourceRecord>> {
        self.project(project)?;
        let rows=sql(self.database().query("SELECT source_id,revision,external_revision,layout FROM research_sources WHERE project_id=? ORDER BY source_id",&[project]))?;
        rows.iter()
            .map(|row| {
                Ok(ResearchSourceRecord {
                    source_id: cell(row, 0)?.into(),
                    project_id: project.into(),
                    revision: Revision::parse(cell(row, 1)?)?,
                    external_revision: Revision::parse(cell(row, 2)?)?,
                    layout: cell(row, 3)?.into(),
                })
            })
            .collect()
    }
    fn list_entries(
        &self,
        project: &str,
        kind: Option<&str>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<PaperRecord>> {
        self.project(project)?;
        if limit == 0 || limit > 200 {
            return Err(ContractError::TextLimit);
        }
        let rows = if let Some(kind) = kind {
            sql(self.database().query("SELECT id FROM research_entries WHERE project_id=? AND kind=? ORDER BY rowid LIMIT ? OFFSET ?",&[project,kind,&limit.to_string(),&offset.to_string()]))?
        } else {
            sql(self.database().query("SELECT id FROM research_entries WHERE project_id=? ORDER BY rowid LIMIT ? OFFSET ?",&[project,&limit.to_string(),&offset.to_string()]))?
        };
        rows.iter()
            .map(|row| self.entry(project, cell(row, 0)?))
            .collect()
    }
    pub fn document(&self, project: &str, id: &str) -> Result<DocumentRecord> {
        self.project(project)?;
        let rows=sql(self.database().query("SELECT id,relative_path,digest,byte_length,retained FROM research_documents WHERE project_id=? AND id=?",&[project,id]))?;
        let row = rows.first().ok_or(ContractError::NotFound)?;
        Ok(DocumentRecord {
            id: cell(row, 0)?.into(),
            project_id: project.into(),
            relative_path: cell(row, 1)?.into(),
            blob: BlobRef {
                digest: cell(row, 2)?.into(),
                byte_length: Revision::parse(cell(row, 3)?)?,
            },
            retained: cell(row, 4)? == "1",
        })
    }
    pub fn documents(&self, project: &str, limit: u32, offset: u32) -> Result<Vec<DocumentRecord>> {
        self.project(project)?;
        if limit == 0 || limit > 200 {
            return Err(ContractError::TextLimit);
        }
        let rows = sql(self.database().query(
            "SELECT id FROM research_documents WHERE project_id=? ORDER BY rowid LIMIT ? OFFSET ?",
            &[project, &limit.to_string(), &offset.to_string()],
        ))?;
        rows.iter()
            .map(|row| self.document(project, cell(row, 0)?))
            .collect()
    }
    pub fn paper_bindings(&self, project: &str, paper: &str) -> Result<Vec<PaperBinding>> {
        self.paper(project, paper)?;
        let rows=sql(self.database().query("SELECT document_id,paper_id,paper_revision,method,hash_ok,ambiguous,manual FROM research_bindings WHERE paper_id=?",&[paper]))?;
        rows.iter()
            .map(|row| {
                Ok(PaperBinding {
                    document_id: cell(row, 0)?.into(),
                    paper_id: cell(row, 1)?.into(),
                    paper_revision: Revision::parse(cell(row, 2)?)?,
                    method: cell(row, 3)?.into(),
                    hash_ok: cell(row, 4)? == "1",
                    ambiguous: cell(row, 5)? == "1",
                    manual: cell(row, 6)? == "1",
                })
            })
            .collect()
    }
    pub fn open_paper_attachment(
        &self,
        project: &str,
        paper: &str,
        digest: &str,
    ) -> Result<ControlledReader> {
        let paper = self.paper(project, paper)?;
        let blob = paper
            .attachments
            .iter()
            .find(|blob| blob.digest == digest)
            .ok_or(ContractError::NotFound)?;
        self.open_blob_reader(project, blob)
    }
    /// HOST ONLY: citation records are local facts used by refresh immutability.
    pub fn cite_entry_trusted(&self, project: &str, id: &str, citation: &str) -> Result<()> {
        self.entry(project, id)?;
        sql(self.database().exec("INSERT INTO research_citations(citation_id,project_id,entry_id,document_id) VALUES(?,?,?,NULL)",&[citation,project,id]))?;
        Ok(())
    }
    pub fn cite_document_trusted(&self, project: &str, id: &str, citation: &str) -> Result<()> {
        self.document(project, id)?;
        sql(self.database().exec("INSERT INTO research_citations(citation_id,project_id,entry_id,document_id) VALUES(?,?,NULL,?)",&[citation,project,id]))?;
        Ok(())
    }
    /// HOST ONLY: explicit choice among actual pending candidates in this project.
    pub fn choose_paper_binding_trusted(
        &self,
        project: &str,
        document: &str,
        paper: &str,
    ) -> Result<()> {
        self.document(project, document)?;
        self.paper(project, paper)?;
        let tx = sql(self.database().transaction())?;
        self.apply_binding_choice(self.database(), project, document, paper)?;
        sql(tx.commit())
    }
    fn apply_binding_choice(
        &self,
        db: &Db,
        project: &str,
        document: &str,
        paper: &str,
    ) -> Result<()> {
        let rows = sql(db.query(
            "SELECT ambiguous FROM research_bindings WHERE document_id=? AND paper_id=?",
            &[document, paper],
        ))?;
        if rows.first().and_then(|row| row[0].as_deref()) != Some("1") {
            return Err(ContractError::RevisionConflict);
        }
        sql(db.exec("DELETE FROM research_bindings WHERE (document_id=? OR paper_id=?) AND NOT(document_id=? AND paper_id=?) AND ambiguous=1 AND document_id IN(SELECT id FROM research_documents WHERE project_id=?)",&[document,paper,document,paper,project]))?;
        sql(db.exec("UPDATE research_bindings SET ambiguous=0,manual=1,method=method||'+manual' WHERE document_id=? AND paper_id=? AND manual=0",&[document,paper]))?;
        Ok(())
    }

    pub(crate) fn verify_research_effect_tail(
        &self,
        command: &CommandEnvelope,
        receipt: &Receipt,
    ) -> Result<()> {
        let project = command
            .scope
            .project_id
            .as_deref()
            .ok_or(ContractError::ScopeMismatch)?;
        match &command.command {
            Operation::PaperCreate { paper_id, payload } => {
                let actual = self.paper(project, paper_id)?;
                if serde_json::to_value(&actual).map_err(|_| ContractError::Storage)?
                    != receipt.result
                    || actual.attachments != vec![payload.attachment.clone()]
                {
                    return Err(ContractError::Storage);
                }
                if let Some(upload) = &payload.attachment_upload_id {
                    if self.lookup_upload(upload)?.state != "committed" {
                        return Err(ContractError::Storage);
                    }
                }
            }
            Operation::ResearchImport {
                source_id,
                source_revision,
                snapshot,
                snapshot_upload_id,
                ..
            } => {
                let rows=sql(self.database().query("SELECT project_id,revision,external_revision,snapshot_digest,snapshot_upload_id,records_digest FROM research_sources WHERE source_id=?",&[source_id]))?;
                let row = rows.first().ok_or(ContractError::Storage)?;
                if cell(row, 0)? != project
                    || cell(row, 1)? != receipt.revision.as_str()
                    || cell(row, 2)? != source_revision.as_str()
                    || cell(row, 3)? != snapshot.digest
                    || Some(cell(row, 4)?) != snapshot_upload_id.as_deref()
                    || receipt.result["records_digest"] != cell(row, 5)?
                {
                    return Err(ContractError::Storage);
                }
                let members=sql(self.database().query("SELECT m.raw_digest,m.content_digest,m.source_revision,m.title,e.raw_json,e.content_digest,e.source_revision,e.title,e.project_id,e.source_id FROM research_import_members m LEFT JOIN research_entries e ON e.id=m.entry_id WHERE m.intent_id=?",&[&command.intent_id]))?;
                if receipt.result["entries"].as_u64() != Some(members.len() as u64) {
                    return Err(ContractError::Storage);
                }
                for row in members {
                    let raw = cell(&row, 4)?;
                    if cell(&row, 0)? != stable_digest(&Value::String(raw.into()))?
                        || cell(&row, 1)? != stable_digest(&decode_research_json(raw)?)?
                        || cell(&row, 1)? != cell(&row, 5)?
                        || cell(&row, 2)? != cell(&row, 6)?
                        || cell(&row, 3)? != cell(&row, 7)?
                        || cell(&row, 8)? != project
                        || cell(&row, 9)? != source_id
                    {
                        return Err(ContractError::Storage);
                    }
                }
                if self
                    .lookup_upload(
                        snapshot_upload_id
                            .as_deref()
                            .ok_or(ContractError::Storage)?,
                    )?
                    .state
                    != "committed"
                {
                    return Err(ContractError::Storage);
                }
            }
            _ => return Err(ContractError::UnsupportedOperation),
        }
        Ok(())
    }
}

fn project_path(path: &str, root: &str) -> String {
    path.strip_prefix(root).unwrap_or(path).into()
}
type ParsedFiles = (
    Vec<ParsedEntry>,
    Vec<FrozenFile>,
    BTreeMap<String, Value>,
    String,
    String,
);
fn record_fingerprint(entries: &[ParsedEntry]) -> Result<String> {
    let hashes = entries
        .iter()
        .map(|entry| {
            stable_digest(
                &serde_json::to_value(&entry.paper).map_err(|_| ContractError::InvalidPayload)?,
            )
            .map(Value::String)
        })
        .collect::<Result<Vec<_>>>()?;
    stable_digest(&Value::Array(hashes))
}
fn parse_files<F>(files: &[FrozenFile], mut read: F) -> Result<ParsedFiles>
where
    F: FnMut(&FrozenFile) -> Result<Vec<u8>>,
{
    let root = detect_root(files);
    let mut entries = Vec::new();
    let mut documents = Vec::new();
    let mut manifests = BTreeMap::new();
    let mut found = 0;
    let mut v2 = false;
    for file in files {
        let lower = file.path.to_lowercase();
        let project_relative = root.as_ref().and_then(|root| file.path.strip_prefix(root));
        if [".md", ".markdown", ".pdf"]
            .iter()
            .any(|extension| lower.ends_with(extension))
        {
            documents.push(file.clone());
            found += 1;
        }
        let arxiv_manifest = project_relative.is_some_and(|path| {
            let parts: Vec<_> = path.split('/').collect();
            parts.len() == 5
                && parts[0] == "related_work"
                && parts[2] == "versions"
                && parts[4] == "manifest.json"
        });
        if file.path != "manifest.json" && !arxiv_manifest && !lower.ends_with(".jsonl") {
            continue;
        }
        // Only a single bounded textual file is aggregated; opaque PDF/MD never are.
        let bytes = read(file)?;
        if file.path == "manifest.json" {
            let value = decode_research_json(
                std::str::from_utf8(&bytes).map_err(|_| ContractError::InvalidPayload)?,
            )?;
            if value["format"] == "research-package-v1" {
                return Err(ContractError::UnsupportedOperation);
            }
        }
        if let Some(path) = project_relative {
            let parts: Vec<_> = path.split('/').collect();
            if parts.len() == 5
                && parts[0] == "related_work"
                && parts[2] == "versions"
                && parts[4] == "manifest.json"
            {
                if let Ok(text) = std::str::from_utf8(&bytes) {
                    if let Ok(value) = decode_research_json(text) {
                        if value.is_object() {
                            manifests.insert(path.into(), json!({"arxiv_id":value["arxiv_id"],"sha256":{"paper.pdf":value["sha256"]["paper.pdf"]}}));
                        }
                    }
                }
            }
        }
        if !lower.ends_with(".jsonl") {
            continue;
        }
        let name = file
            .path
            .rsplit('/')
            .next()
            .unwrap()
            .trim_end_matches(".jsonl");
        let is_log = project_relative == Some(format!("research/{name}.jsonl").as_str());
        let kind = if KINDS.contains(&name) && (root.is_none() || is_log) {
            name
        } else {
            "other"
        };
        let source = std::str::from_utf8(&bytes)
            .map_err(|_| ContractError::InvalidPayload)?
            .trim_start_matches('\u{feff}');
        for (line, raw) in source.lines().enumerate() {
            if raw.trim().is_empty() {
                continue;
            }
            let record = decode_research_json(raw)?;
            if !record.is_object() {
                return Err(ContractError::InvalidPayload);
            }
            found += 1;
            if entries.len() >= 10_000 {
                return Err(ContractError::TextLimit);
            }
            v2 |= is_log && record["schema_version"] == 2;
            let content_digest = stable_digest(&record)?;
            let identity = record.get("id").filter(|v| !v.is_null());
            let key = if let Some(id) = identity {
                stable_digest(&json!([
                    kind,
                    id,
                    record.get("rev").unwrap_or(&Value::Null)
                ]))?
            } else {
                stable_digest(&json!([kind, content_digest]))?
            };
            let source_id = stable_id(
                "record",
                json!([kind, identity.cloned().unwrap_or(json!([file.path, line]))]),
            )?;
            entries.push(ParsedEntry {
                kind: kind.into(),
                title: record_title(&record, &format!("{name}:{}", line + 1)),
                key,
                content_digest,
                paper: ImportedPaper {
                    source_id,
                    source_revision: revision_of(&record),
                    record,
                    raw_json: raw.into(),
                    attachments: Vec::new(),
                    attachment_upload_ids: BTreeMap::new(),
                },
            });
        }
    }
    if found == 0 {
        return Err(ContractError::InvalidPayload);
    }
    Ok((
        entries,
        documents,
        manifests,
        if root.is_some() {
            if v2 {
                "research-skill-v2"
            } else {
                "research-skill-v1"
            }
        } else {
            "generic"
        }
        .into(),
        root.unwrap_or_default(),
    ))
}

impl BusinessStore {
    fn bind_imported_papers(
        &self,
        db: &Db,
        entries: &[(String, &ParsedEntry)],
        docs: &BTreeMap<String, (String, BlobRef)>,
        manifests: &BTreeMap<String, Value>,
    ) -> Result<()> {
        let mut sources = BTreeMap::new();
        let mut current: BTreeMap<String, &(String, &ParsedEntry)> = BTreeMap::new();
        for entry in entries {
            let data = &entry.1.paper.record;
            if entry.1.kind == "sources" {
                sources.insert(text(&json!([data["id"], data["rev"]]))?, data);
            }
            if entry.1.kind == "papers" && !data["id"].is_null() {
                let key = text(&data["id"])?;
                if current
                    .get(&key)
                    .is_none_or(|old| entry.1.paper.source_revision >= old.1.paper.source_revision)
                {
                    current.insert(key, entry);
                }
            }
        }
        let mut candidates = Vec::new();
        for (id, entry) in current.into_values() {
            let data = &entry.paper.record;
            if data["active"] == false {
                continue;
            }
            let mut found = Vec::new();
            let source = sources.get(&text(&json!([data["source_id"], data["source_rev"]]))?);
            let material = source.and_then(|source| source.get("material_binding"));
            if let Some(path) = material.and_then(|m| m["path"].as_str()) {
                if let Some((doc, blob)) = docs.get(path) {
                    found.push((
                        doc.clone(),
                        "material_binding",
                        material.unwrap()["sha256"] == blob.digest,
                    ));
                }
            }
            if found.is_empty() {
                if let (Some(arxiv), Some(version)) =
                    (data["arxiv_id"].as_str(), data["version"].as_str())
                {
                    for (path, manifest) in manifests {
                        if manifest["arxiv_id"] != format!("{arxiv}{version}") {
                            continue;
                        }
                        let pdf = format!(
                            "{}/paper.pdf",
                            path.rsplit_once('/').map(|p| p.0).unwrap_or("")
                        );
                        if let Some((doc, blob)) = docs.get(&pdf) {
                            found.push((
                                doc.clone(),
                                "arxiv_manifest",
                                manifest["sha256"]["paper.pdf"] == blob.digest,
                            ));
                        }
                    }
                }
            }
            for (doc, method, hash_ok) in found {
                candidates.push((
                    doc,
                    id.clone(),
                    entry.paper.source_revision.clone(),
                    method,
                    hash_ok,
                ));
            }
        }
        for (doc, paper, revision, method, hash_ok) in &candidates {
            let ambiguous = candidates.iter().filter(|c| &c.0 == doc).count() > 1
                || candidates.iter().filter(|c| &c.1 == paper).count() > 1;
            sql(db.exec("INSERT INTO research_bindings(document_id,paper_id,paper_revision,method,hash_ok,ambiguous,manual) VALUES(?,?,?,?,?,?,0)",&[doc,paper,revision.as_str(),method,if *hash_ok{"1"}else{"0"},if ambiguous{"1"}else{"0"}]))?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod resource_tests {
    use super::*;
    #[test]
    fn real_opaque_uploads_are_not_aggregated_when_sealing_or_importing() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "muyon-research-resource-{}-{unique}",
            std::process::id()
        ));
        std::fs::create_dir(&dir).unwrap();
        let path = dir.join("business.sqlite");
        BusinessStore::initialize(&path, "workspace-a").unwrap();
        let store = BusinessStore::open_existing(&path, "workspace-a", "epoch-a").unwrap();
        let mut command:CommandEnvelope=serde_json::from_value(json!({"protocol_version":1,"business_version":1,"intent_id":"project-a","scope":{"workspace_id":"workspace-a","project_id":"project-a"},"expected_revision":"0","authority":{"grant_id":"grant-project","generation":"1","owner_epoch":"epoch-a"},"plan_id":"plan-project","plan_digest":"0".repeat(64),"command":{"operation":"project_create","project_id":"project-a","name":"research"}})).unwrap();
        command.plan_digest = command.expected_plan_digest().unwrap();
        store.issue_grant_trusted(&command, None).unwrap();
        assert_eq!(
            store.execute(&command).unwrap().status,
            ExecutionStatus::Committed
        );
        let mut pdf = b"%PDF-1.4\n".to_vec();
        pdf.extend(std::iter::repeat_n(b'x', 2 * 1024 * 1024));
        pdf.extend_from_slice(b"\n%%EOF");
        let markdown = vec![b'm'; 2 * 1024 * 1024];
        let mut entries = Vec::new();
        for (name, bytes, kind) in [
            ("paper.pdf", pdf, BlobKind::Pdf),
            ("notes.md", markdown, BlobKind::Document),
        ] {
            let upload = store.begin_upload("project-a").unwrap();
            for chunk in bytes.chunks(MAX_CHUNK) {
                store.append_chunk(&upload.upload_id, chunk).unwrap();
            }
            store.finish_blob(&upload.upload_id, kind).unwrap();
            entries.push(SnapshotEntry {
                relative_path: name.into(),
                upload_id: upload.upload_id,
            });
        }
        AGGREGATE_READS.with(|counter| counter.set(0));
        let sealed = store
            .seal_research_snapshot("project-a", &entries, None)
            .unwrap();
        assert_eq!(
            AGGREGATE_READS.with(|counter| counter.get()),
            0,
            "opaque PDF/MD must never reach aggregate upload_bytes"
        );
        command.intent_id = "import-a".into();
        command.authority.grant_id = "grant-import".into();
        command.plan_id = "plan-import".into();
        command.command = Operation::ResearchImport {
            source_id: "source-a".into(),
            source_revision: Revision::new(1),
            snapshot: sealed.snapshot,
            snapshot_upload_id: Some(sealed.snapshot_upload_id),
            records: Vec::new(),
        };
        command.plan_digest = command.expected_plan_digest().unwrap();
        store.issue_grant_trusted(&command, None).unwrap();
        assert_eq!(
            store.execute(&command).unwrap().status,
            ExecutionStatus::Committed
        );
        assert_eq!(
            AGGREGATE_READS.with(|counter| counter.get()),
            1,
            "only the small sealed manifest may be aggregated during import"
        );
        assert_eq!(store.documents("project-a", 200, 0).unwrap().len(), 2);
        drop(store);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
