//! Durable host-only COPY transaction gateway. No Office editing engine is installed.
//! Uses the existing BusinessStore connection, document grants and blob owner.
use super::{Binding, Confirmation};
use crate::{
    blobs::{MAX_CHUNK, MAX_DOCUMENT_BYTES},
    business::BusinessStore,
    contract::{AuthorityBinding, BlobRef, ContractError, Revision, Scope},
    documents::{DocumentAccess, DocumentFormat, DocumentMetadata, DocumentOperation, DocumentRef},
    sqlite::Transaction as SqlTransaction,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
type Result<T> = std::result::Result<T, ContractError>;
const META: &str = "CREATE TABLE edit_journal_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)";
const INTENTS: &str = "CREATE TABLE edit_journal_intents(intent_id TEXT PRIMARY KEY,binding_json TEXT NOT NULL,source_json TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN('prepared','confirmed','copying','candidate','validated','publishing','committed','cancelled','conflict','failed')),authority_json TEXT,cancel_requested INTEGER NOT NULL CHECK(cancel_requested IN(0,1)),candidate_hex TEXT CHECK(length(candidate_hex)<=62914560),candidate_digest TEXT,receipt_json TEXT)";
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DurableState {
    Prepared,
    Confirmed,
    Candidate,
    Validated,
    Committed,
    Cancelled,
    Conflict,
    Failed,
    Unknown,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CopyOperation {
    ByteIdenticalCopy,
}
#[derive(Clone, Debug)]
pub struct CopyReceipt {
    pub operation: CopyOperation,
    pub intent_id: String,
    pub binding_digest: String,
    pub result: DocumentMetadata,
}
impl PartialEq for CopyReceipt {
    fn eq(&self, other: &Self) -> bool {
        self.operation == other.operation
            && self.intent_id == other.intent_id
            && self.binding_digest == other.binding_digest
            && self.result.document == other.result.document
            && self.result.title == other.result.title
            && self.result.blob == other.result.blob
    }
}
#[derive(Clone, Debug)]
pub struct DurableIntent {
    pub binding: Binding,
    pub state: DurableState,
    pub cancel_requested: bool,
    pub candidate: Option<BlobRef>,
    pub receipt: Option<CopyReceipt>,
}
/// In-process trusted service handle only; never construct from a model/wire request.
pub struct DocumentEditGateway<'a> {
    store: &'a BusinessStore,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct StoredDocument {
    scope: Scope,
    id: String,
    revision: Revision,
    format: String,
    title: String,
    blob: BlobRef,
}
fn sql<T>(r: crate::sqlite::Result<T>) -> Result<T> {
    r.map_err(|_| ContractError::Storage)
}
fn encode<T: Serialize>(v: &T) -> Result<String> {
    serde_json::to_string(v).map_err(|_| ContractError::InvalidPayload)
}
fn decode<T: serde::de::DeserializeOwned>(v: &str) -> Result<T> {
    serde_json::from_str(v).map_err(|_| ContractError::StorageCorrupt)
}
fn hash(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
fn unhex(s: &str) -> Result<Vec<u8>> {
    if s.is_empty()
        || !s.len().is_multiple_of(2)
        || s.len() as u64 > MAX_DOCUMENT_BYTES * 2
        || !s
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err(ContractError::StorageCorrupt);
    }
    (0..s.len())
        .step_by(2)
        .map(|n| u8::from_str_radix(&s[n..n + 2], 16).map_err(|_| ContractError::StorageCorrupt))
        .collect()
}
fn format_name(f: DocumentFormat) -> String {
    format!("{f:?}")
}
pub(super) fn document_json(m: &DocumentMetadata) -> Result<String> {
    encode(&StoredDocument {
        scope: m.document.scope().clone(),
        id: m.document.document_id().into(),
        revision: m.document.revision().clone(),
        format: format_name(m.document.format()),
        title: m.title.clone(),
        blob: m.blob.clone(),
    })
}
pub(super) fn document_decode(s: &str) -> Result<DocumentMetadata> {
    let m: StoredDocument = decode(s)?;
    m.blob.validate()?;
    let f = match m.format.as_str() {
        "Text" => DocumentFormat::Text,
        "Docx" => DocumentFormat::Docx,
        "Pptx" => DocumentFormat::Pptx,
        "Xlsx" => DocumentFormat::Xlsx,
        "Pdf" => DocumentFormat::Pdf,
        "Doc" => DocumentFormat::Doc,
        "Ppt" => DocumentFormat::Ppt,
        "Xls" => DocumentFormat::Xls,
        "Unknown" => DocumentFormat::Unknown,
        _ => return Err(ContractError::StorageCorrupt),
    };
    Ok(DocumentMetadata {
        document: DocumentRef::new(m.scope, &m.id, m.revision, f)
            .map_err(|_| ContractError::StorageCorrupt)?,
        title: m.title,
        blob: m.blob,
    })
}
pub(super) fn binding_json(b: &Binding) -> Result<String> {
    b.check().map_err(|_| ContractError::InvalidPayload)?;
    encode(&(
        b.document.scope(),
        b.document.document_id(),
        b.document.revision(),
        format_name(b.document.format()),
        hex(&b.patch_digest),
        &b.intent_id,
        &b.rollback_target,
    ))
}
fn copy_plan_digest(source: &DocumentMetadata, intent: &str) -> Result<[u8; 32]> {
    Ok(Sha256::digest(
        encode(&("byte_identical_copy_v1", document_json(source)?, intent))?.as_bytes(),
    )
    .into())
}
fn cell(row: &[Option<String>], n: usize) -> Result<&str> {
    row.get(n)
        .and_then(Option::as_deref)
        .ok_or(ContractError::StorageCorrupt)
}
/// Both journals share one bounded candidate-byte budget. Missing edited table
/// is valid on stores that only initialized the historical COPY gateway.
pub(super) fn journal_candidate_bytes(store: &BusinessStore) -> Result<usize> {
    let db = store.database();
    let mut total = 0usize;
    for table in ["edit_journal_intents", "edit_candidate_intents"] {
        if sql(db.query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            &[table],
        ))?
        .is_empty()
        {
            continue;
        }
        let rows = sql(db.query(
            &format!("SELECT COALESCE(SUM(length(candidate_hex)/2),0) FROM {table}"),
            &[],
        ))?;
        let n: usize = cell(&rows[0], 0)?
            .parse()
            .map_err(|_| ContractError::StorageCorrupt)?;
        total = total.checked_add(n).ok_or(ContractError::RawLimit)?;
    }
    Ok(total)
}
struct Record {
    source: DocumentMetadata,
    state: String,
    authority: Option<AuthorityBinding>,
    cancel: bool,
    bytes: Option<String>,
    digest: Option<String>,
    receipt: Option<String>,
}
impl<'a> DocumentEditGateway<'a> {
    pub fn initialize_trusted(store: &'a BusinessStore) -> Result<Self> {
        let db = store.database();
        let tx = sql(db.transaction())?;
        let mut found = Vec::new();
        for (name, ddl) in [
            ("edit_journal_meta", META),
            ("edit_journal_intents", INTENTS),
        ] {
            let rows = sql(db.query(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                &[name],
            ))?;
            if rows.is_empty() {
                found.push(false)
            } else if rows.len() == 1 && cell(&rows[0], 0)? == ddl {
                found.push(true)
            } else {
                return Err(ContractError::InvalidVersion);
            }
        }
        if found == [false, false] {
            sql(db.exec(META, &[]))?;
            sql(db.exec(INTENTS, &[]))?;
            sql(db.exec("INSERT INTO edit_journal_meta VALUES('version','1')", &[]))?;
            sql(db.exec(
                "INSERT INTO edit_journal_meta VALUES('workspace',?)",
                &[store.workspace_id()],
            ))?;
        } else if found != [true, true] {
            return Err(ContractError::InvalidVersion);
        }
        let meta = sql(db.query("SELECT key,value FROM edit_journal_meta ORDER BY key", &[]))?;
        if meta
            != vec![
                vec![Some("version".into()), Some("1".into())],
                vec![Some("workspace".into()), Some(store.workspace_id().into())],
            ]
        {
            return Err(ContractError::InvalidVersion);
        }
        sql(tx.commit())?;
        Ok(Self { store })
    }
    fn load(&self, b: &Binding) -> Result<Record> {
        if b.document.scope().workspace_id != self.store.workspace_id() {
            return Err(ContractError::ScopeMismatch);
        }
        let rows=sql(self.store.database().query("SELECT CASE WHEN length(CAST(binding_json AS BLOB))<=8192 THEN binding_json END,CASE WHEN length(CAST(source_json AS BLOB))<=8192 THEN source_json END,state,CASE WHEN length(CAST(authority_json AS BLOB))<=4096 THEN authority_json END,cancel_requested,CASE WHEN length(CAST(candidate_hex AS BLOB))<=62914560 THEN candidate_hex END,CASE WHEN length(CAST(candidate_digest AS BLOB))=64 THEN candidate_digest END,CASE WHEN length(CAST(receipt_json AS BLOB))<=8192 THEN receipt_json END FROM edit_journal_intents WHERE intent_id=?",&[&b.intent_id]))?;
        let r = rows.first().ok_or(ContractError::NotFound)?;
        if cell(r, 0)? != binding_json(b)? {
            return Err(ContractError::IntentConflict);
        }
        let source = document_decode(cell(r, 1)?)?;
        if source.document != b.document
            || b.rollback_target.is_some()
            || copy_plan_digest(&source, &b.intent_id)? != b.patch_digest
        {
            return Err(ContractError::StorageCorrupt);
        }
        Ok(Record {
            source,
            state: cell(r, 2)?.into(),
            authority: r[3].as_deref().map(decode).transpose()?,
            cancel: cell(r, 4)? == "1",
            bytes: r[5].clone(),
            digest: r[6].clone(),
            receipt: r[7].clone(),
        })
    }
    fn authorize(
        &self,
        tx: &SqlTransaction<'_>,
        b: &Binding,
        a: &DocumentAccess,
        op: DocumentOperation,
        query: bool,
    ) -> Result<DocumentMetadata> {
        if a.document.scope() != b.document.scope()
            || a.document.document_id() != b.document.document_id()
            || a.document.format() != b.document.format()
        {
            return Err(ContractError::ScopeMismatch);
        }
        if !query && a.document != b.document {
            return Err(ContractError::BindingMismatch);
        }
        self.store.document_access_in_transaction(tx, a, &[op])
    }
    fn effect(
        &self,
        tx: &SqlTransaction<'_>,
        b: &Binding,
        a: &DocumentAccess,
        r: &Record,
        op: DocumentOperation,
    ) -> Result<()> {
        let current = self.authorize(tx, b, a, op, false)?;
        if current.document != b.document || current.blob != r.source.blob {
            return Err(ContractError::RevisionConflict);
        }
        if r.authority.as_ref() != Some(&a.authority) {
            return Err(ContractError::InvalidAuthority);
        }
        if r.cancel || r.state == "cancelled" {
            return Err(ContractError::Cancelled);
        }
        Ok(())
    }
    fn checked_bytes(&self, r: &Record) -> Result<Vec<u8>> {
        let bytes = unhex(r.bytes.as_deref().ok_or(ContractError::Unknown)?)?;
        let digest = hash(&bytes);
        if Some(digest.as_str()) != r.digest.as_deref()
            || digest != r.source.blob.digest
            || bytes.len() as u64 != r.source.blob.byte_length.value()
        {
            return Err(ContractError::BindingMismatch);
        }
        Ok(bytes)
    }
    fn view(&self, b: &Binding, r: &Record) -> Result<DurableIntent> {
        let state = match r.state.as_str() {
            "prepared" => DurableState::Prepared,
            "confirmed" => DurableState::Confirmed,
            "candidate" => DurableState::Candidate,
            "validated" => DurableState::Validated,
            "committed" => DurableState::Committed,
            "cancelled" => DurableState::Cancelled,
            "conflict" => DurableState::Conflict,
            "failed" => DurableState::Failed,
            "copying" | "publishing" => DurableState::Unknown,
            _ => return Err(ContractError::StorageCorrupt),
        };
        let candidate = if r.bytes.is_some() {
            let bytes = self.checked_bytes(r)?;
            Some(BlobRef {
                digest: hash(&bytes),
                byte_length: Revision::new(bytes.len() as u64),
            })
        } else {
            None
        };
        let receipt = if let Some(text) = &r.receipt {
            let result = document_decode(text)?;
            let next = b.document.revision().next()?;
            if state != DurableState::Committed
                || result.document.scope() != b.document.scope()
                || result.document.document_id() != b.document.document_id()
                || result.document.format() != b.document.format()
                || result.document.revision() != &next
                || result.title != r.source.title
                || Some(&result.blob) != candidate.as_ref()
            {
                return Err(ContractError::StorageCorrupt);
            }
            Some(CopyReceipt {
                operation: CopyOperation::ByteIdenticalCopy,
                intent_id: b.intent_id.clone(),
                binding_digest: hash(binding_json(b)?.as_bytes()),
                result,
            })
        } else {
            if state == DurableState::Committed {
                return Err(ContractError::StorageCorrupt);
            }
            None
        };
        Ok(DurableIntent {
            binding: b.clone(),
            state,
            cancel_requested: r.cancel,
            candidate,
            receipt,
        })
    }
    pub fn prepare_copy(&self, a: &DocumentAccess, intent: &str) -> Result<DurableIntent> {
        if !super::opaque_id(intent) {
            return Err(ContractError::InvalidIdentity);
        }
        let db = self.store.database();
        let tx = sql(db.transaction())?;
        let source =
            self.store
                .document_access_in_transaction(&tx, a, &[DocumentOperation::ReadText])?;
        // Both operation families share the original-intent namespace and lock.
        let edited = sql(db.query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='edit_candidate_intents'",
            &[],
        ))?;
        if !edited.is_empty()
            && !sql(db.query(
                "SELECT intent_id FROM edit_candidate_intents WHERE intent_id=?",
                &[intent],
            ))?
            .is_empty()
        {
            return Err(ContractError::IntentConflict);
        }
        let digest = copy_plan_digest(&source, intent)?;
        let b = Binding {
            document: source.document.clone(),
            patch_digest: digest,
            intent_id: intent.into(),
            rollback_target: None,
        };
        let existing = sql(db.query(
            "SELECT intent_id FROM edit_journal_intents WHERE intent_id=?",
            &[intent],
        ))?;
        if existing.is_empty() {
            sql(db.exec("INSERT INTO edit_journal_intents(intent_id,binding_json,source_json,state,cancel_requested) VALUES(?,?,?,'prepared',0)",&[intent,&binding_json(&b)?,&document_json(&source)?]))?;
        }
        let r = self.load(&b)?;
        let v = self.view(&b, &r)?;
        self.store
            .document_access_in_transaction(&tx, a, &[DocumentOperation::ReadText])?;
        sql(tx.commit())?;
        Ok(v)
    }
    pub fn confirm_trusted(
        &self,
        b: &Binding,
        a: &DocumentAccess,
        confirmation: &Confirmation,
    ) -> Result<DurableIntent> {
        if &confirmation.binding != b || confirmation.authority != a.authority {
            return Err(ContractError::BindingMismatch);
        }
        let db = self.store.database();
        let tx = sql(db.transaction())?;
        let r = self.load(b)?;
        let current = self.authorize(&tx, b, a, DocumentOperation::StructuredEdit, false)?;
        if current.blob != r.source.blob {
            return Err(ContractError::RevisionConflict);
        }
        if r.cancel {
            return Err(ContractError::Cancelled);
        }
        if r.state == "prepared" {
            sql(db.exec("UPDATE edit_journal_intents SET state='confirmed',authority_json=? WHERE intent_id=? AND state='prepared'",&[&encode(&a.authority)?,&b.intent_id]))?;
        } else if matches!(r.state.as_str(), "confirmed" | "candidate" | "validated") {
            // An authentic fresh confirmation may renew a known completed stage;
            // it never replays a copy/commit or resumes an uncertain in-flight job.
            sql(db.exec("UPDATE edit_journal_intents SET authority_json=? WHERE intent_id=? AND state IN('confirmed','candidate','validated')",&[&encode(&a.authority)?,&b.intent_id]))?;
        } else {
            return Err(if matches!(r.state.as_str(), "copying" | "publishing") {
                ContractError::Unknown
            } else {
                ContractError::IntentConflict
            });
        }
        let view = self.view(b, &self.load(b)?)?;
        self.authorize(&tx, b, a, DocumentOperation::StructuredEdit, false)?;
        sql(tx.commit())?;
        Ok(view)
    }
    pub fn lookup_original(&self, b: &Binding, a: &DocumentAccess) -> Result<DurableIntent> {
        let tx = sql(self.store.database().transaction())?;
        self.authorize(&tx, b, a, DocumentOperation::Inspect, true)?;
        let v = self.view(b, &self.load(b)?)?;
        self.authorize(&tx, b, a, DocumentOperation::Inspect, true)?;
        sql(tx.commit())?;
        Ok(v)
    }
    pub fn candidate_bytes(&self, b: &Binding, a: &DocumentAccess) -> Result<Vec<u8>> {
        let tx = sql(self.store.database().transaction())?;
        let current = self.authorize(&tx, b, a, DocumentOperation::ReadText, true)?;
        let record = self.load(b)?;
        // A current-version read grant cannot disclose a different historical
        // payload. Equal content-addressed bytes are the same authorized data.
        if current.blob != record.source.blob {
            return Err(ContractError::InvalidAuthority);
        }
        let bytes = self.checked_bytes(&record)?;
        self.authorize(&tx, b, a, DocumentOperation::ReadText, true)?;
        sql(tx.commit())?;
        Ok(bytes)
    }
    pub fn cancel_trusted(&self, b: &Binding) -> Result<DurableState> {
        let db = self.store.database();
        let tx = sql(db.transaction())?;
        self.load(b)?;
        sql(db.exec("UPDATE edit_journal_intents SET cancel_requested=1,state=CASE WHEN state IN('prepared','confirmed','candidate','validated') THEN 'cancelled' ELSE state END WHERE intent_id=?",&[&b.intent_id]))?;
        // Local cancellation must still stop corrupt candidate work; it does not
        // read/return candidate bytes or a receipt and is not a rollback.
        let state = match self.load(b)?.state.as_str() {
            "committed" => DurableState::Committed,
            "copying" | "publishing" => DurableState::Unknown,
            "conflict" => DurableState::Conflict,
            "failed" => DurableState::Failed,
            _ => DurableState::Cancelled,
        };
        sql(tx.commit())?;
        Ok(state)
    }
    /// Schema mapping only. It neither launches an engine nor creates a validated
    /// journal record. Actual source/grant resolution remains on this connection.
    pub fn prepare_numeric_cell_request(
        &self,
        a: &DocumentAccess,
        intent: &str,
        op: super::engine_protocol::NumericCellEdit,
    ) -> Result<super::engine_protocol::PreparedEngineRequest> {
        let tx = sql(self.store.database().transaction())?;
        let source =
            self.store
                .document_access_in_transaction(&tx, a, &[DocumentOperation::ReadText])?;
        let request = super::engine_protocol::prepare_request_trusted(&source, intent, op)
            .map_err(|_| ContractError::InvalidPayload)?;
        self.store
            .document_access_in_transaction(&tx, a, &[DocumentOperation::ReadText])?;
        sql(tx.commit())?;
        Ok(request)
    }
    /// Trusted read-side observation mapping only; the subtree/locator must come
    /// from a host reader, never model JSON. No package eligibility is attested.
    pub fn prepare_text_request(
        &self,
        a: &DocumentAccess,
        intent: &str,
        edit: super::text_protocol::TextEdit,
    ) -> Result<super::engine_protocol::PreparedEngineRequest> {
        let tx = sql(self.store.database().transaction())?;
        let source =
            self.store
                .document_access_in_transaction(&tx, a, &[DocumentOperation::ReadText])?;
        let request = super::text_protocol::prepare_text_request_trusted(&source, intent, edit)
            .map_err(|_| ContractError::InvalidPayload)?;
        self.store
            .document_access_in_transaction(&tx, a, &[DocumentOperation::ReadText])?;
        sql(tx.commit())?;
        Ok(request)
    }
    pub fn apply_engine_patch(&self, _b: &Binding, _a: &DocumentAccess) -> Result<DurableIntent> {
        Err(ContractError::UnsupportedOperation)
    }
    fn failure(&self, b: &Binding, e: ContractError) -> ContractError {
        let state = match e {
            ContractError::RevisionConflict => "conflict",
            ContractError::Cancelled => "cancelled",
            ContractError::Storage | ContractError::StorageIo | ContractError::Unknown => {
                return ContractError::Unknown
            }
            _ => "failed",
        };
        let attempt = (|| {
            let db = self.store.database();
            let tx = sql(db.transaction())?;
            sql(db.exec("UPDATE edit_journal_intents SET state=? WHERE intent_id=? AND state IN('copying','publishing')",&[state,&b.intent_id]))?;
            sql(tx.commit())
        })();
        if attempt.is_err() {
            ContractError::Unknown
        } else {
            e
        }
    }
    pub fn copy_candidate(&self, b: &Binding, a: &DocumentAccess) -> Result<DurableIntent> {
        let source = {
            let db = self.store.database();
            let tx = sql(db.transaction())?;
            let r = self.load(b)?;
            if matches!(
                r.state.as_str(),
                "candidate" | "validated" | "committed" | "copying" | "publishing"
            ) {
                self.authorize(&tx, b, a, DocumentOperation::Inspect, true)?;
                if matches!(r.state.as_str(), "copying" | "publishing") {
                    return Err(ContractError::Unknown);
                }
                let v = self.view(b, &r)?;
                self.authorize(&tx, b, a, DocumentOperation::Inspect, true)?;
                sql(tx.commit())?;
                return Ok(v);
            }
            self.effect(&tx, b, a, &r, DocumentOperation::ReadText)?;
            if r.state != "confirmed" {
                return match r.state.as_str() {
                    "candidate" | "validated" | "committed" => self.view(b, &r),
                    "copying" | "publishing" => Err(ContractError::Unknown),
                    _ => Err(ContractError::InvalidAuthority),
                };
            }
            sql(db.exec("UPDATE edit_journal_intents SET state='copying' WHERE intent_id=? AND state='confirmed'",&[&b.intent_id]))?;
            sql(tx.commit())?;
            r.source
        };
        let result = (|| {
            let project = b
                .document
                .scope()
                .project_id
                .as_deref()
                .ok_or(ContractError::ScopeMismatch)?;
            let mut reader = self.store.open_blob_reader(project, &source.blob)?;
            let mut bytes = Vec::new();
            let read = (|| {
                loop {
                    let tx = sql(self.store.database().transaction())?;
                    let r = self.load(b)?;
                    self.effect(&tx, b, a, &r, DocumentOperation::ReadText)?;
                    let chunk = self.store.read_blob_chunk(&mut reader, MAX_CHUNK)?;
                    self.effect(&tx, b, a, &r, DocumentOperation::ReadText)?;
                    sql(tx.commit())?;
                    if chunk.is_empty() {
                        break;
                    }
                    if bytes.len() as u64 + chunk.len() as u64 > MAX_DOCUMENT_BYTES {
                        return Err(ContractError::TextLimit);
                    }
                    bytes.extend(chunk);
                }
                Ok(())
            })();
            let closed = self.store.close_blob_reader(reader);
            read?;
            closed?;
            if hash(&bytes) != source.blob.digest
                || bytes.len() as u64 != source.blob.byte_length.value()
            {
                return Err(ContractError::BindingMismatch);
            }
            let db = self.store.database();
            let tx = sql(db.transaction())?;
            let r = self.load(b)?;
            self.effect(&tx, b, a, &r, DocumentOperation::ReadText)?;
            if r.state != "copying" {
                return Err(ContractError::IntentConflict);
            }
            // Hard global bound as well as per-document bound. No unbounded hidden staging.
            let total = journal_candidate_bytes(self.store)?;
            if total
                .checked_add(bytes.len())
                .ok_or(ContractError::RawLimit)?
                > 150 * 1024 * 1024
            {
                return Err(ContractError::RawLimit);
            }
            sql(db.exec("UPDATE edit_journal_intents SET state='candidate',candidate_hex=?,candidate_digest=? WHERE intent_id=? AND state='copying'",&[&hex(&bytes),&hash(&bytes),&b.intent_id]))?;
            let v = self.view(b, &self.load(b)?)?;
            let tail = self.load(b)?;
            self.effect(&tx, b, a, &tail, DocumentOperation::ReadText)?;
            sql(tx.commit())?;
            Ok(v)
        })();
        result.map_err(|e| self.failure(b, e))
    }
    pub fn validate_copy(&self, b: &Binding, a: &DocumentAccess) -> Result<DurableIntent> {
        let db = self.store.database();
        let tx = sql(db.transaction())?;
        let r = self.load(b)?;
        self.effect(&tx, b, a, &r, DocumentOperation::Validate)?;
        if !matches!(r.state.as_str(), "candidate" | "validated") {
            return Err(ContractError::IntentConflict);
        }
        self.checked_bytes(&r)?;
        self.effect(&tx, b, a, &r, DocumentOperation::Validate)?;
        sql(db.exec("UPDATE edit_journal_intents SET state='validated' WHERE intent_id=? AND state='candidate'",&[&b.intent_id]))?;
        let v = self.view(b, &self.load(b)?)?;
        let tail = self.load(b)?;
        self.effect(&tx, b, a, &tail, DocumentOperation::Validate)?;
        sql(tx.commit())?;
        Ok(v)
    }
    pub fn commit_copy(&self, b: &Binding, a: &DocumentAccess) -> Result<DurableIntent> {
        let claimed = (|| {
            let db = self.store.database();
            let tx = sql(db.transaction())?;
            let r = self.load(b)?;
            if r.state == "committed" {
                self.authorize(&tx, b, a, DocumentOperation::Inspect, true)?;
                let view = self.view(b, &r)?;
                self.authorize(&tx, b, a, DocumentOperation::Inspect, true)?;
                sql(tx.commit())?;
                return Ok(Some(view));
            }
            if matches!(r.state.as_str(), "copying" | "publishing") {
                self.authorize(&tx, b, a, DocumentOperation::Inspect, true)?;
                return Err(ContractError::Unknown);
            }
            self.effect(&tx, b, a, &r, DocumentOperation::StructuredEdit)?;
            if r.state != "validated" {
                return Err(ContractError::InvalidAuthority);
            }
            self.checked_bytes(&r)?;
            b.document.revision().next()?;
            self.effect(&tx, b, a, &r, DocumentOperation::StructuredEdit)?;
            sql(db.exec("UPDATE edit_journal_intents SET state='publishing' WHERE intent_id=? AND state='validated'",&[&b.intent_id]))?;
            sql(tx.commit())?;
            Ok(None)
        })();
        match claimed {
            Ok(Some(v)) => return Ok(v),
            Ok(None) => {}
            Err(e) => {
                if e == ContractError::RevisionConflict {
                    let db = self.store.database();
                    let tx = sql(db.transaction())?;
                    sql(db.exec("UPDATE edit_journal_intents SET state='conflict' WHERE intent_id=? AND state='validated'",&[&b.intent_id]))?;
                    sql(tx.commit())?;
                }
                return Err(e);
            }
        }
        self.publish_clone(b, a).map_err(|e| self.failure(b, e))
    }
    fn publish_clone(&self, b: &Binding, a: &DocumentAccess) -> Result<DurableIntent> {
        let db = self.store.database();
        let tx = sql(db.transaction())?;
        let r = self.load(b)?;
        self.effect(&tx, b, a, &r, DocumentOperation::StructuredEdit)?;
        if r.state != "publishing" {
            return Err(ContractError::Unknown);
        }
        self.checked_bytes(&r)?;
        // COPY-only uses the already-published immutable source object. The
        // candidate bytes were independently persisted and checked identical.
        // No upload, staging, file write, or independent transaction remains.
        let result = self.store.document_clone_in_transaction(
            &tx,
            &b.document,
            &r.source.title,
            &r.source.blob,
        )?;
        if result.document.revision() != &b.document.revision().next()? {
            return Err(ContractError::InvalidRevision);
        }
        // A failure in the receipt tail rolls back document CAS and blob-reference
        // publication on this SAME connection. The durable publishing claim remains.
        let changed=sql(db.exec("UPDATE edit_journal_intents SET state='committed',receipt_json=? WHERE intent_id=? AND state='publishing' AND cancel_requested=0",&[&document_json(&result)?,&b.intent_id]))?;
        if changed != 1 {
            return Err(ContractError::Cancelled);
        }
        // Final expiry/revocation check must retain the originally granted base
        // identity while allowing the head to be the just-published next version.
        let v = self.view(b, &self.load(b)?)?;
        self.store
            .document_grant_in_transaction(&tx, a, &[DocumentOperation::StructuredEdit])?;
        // No work or write follows this final authority check except COMMIT.
        sql(tx.commit()).map_err(|_| ContractError::Unknown)?;
        Ok(v)
    }
}
