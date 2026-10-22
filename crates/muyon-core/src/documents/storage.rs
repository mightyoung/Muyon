//! Document metadata and sidecars on the existing BusinessStore connection.
//! Trusted methods are host-only: no model dispatcher, file path or engine input.
use super::{
    identity::valid_id, AnchorStatus, AnnotationAuthor, AnnotationBody, AnnotationExport,
    AnnotationRecord, DocumentAnchor, DocumentFormat, DocumentOperation, DocumentRef,
    StoredAnchorState,
};
use crate::{
    blobs::FinishedBlob, business::BusinessStore, contract::*, sqlite::Transaction,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

type Result<T> = std::result::Result<T, ContractError>;
const MAX_ANNOTATIONS: usize = 1000;
const SCHEMA: &[(&str, &str)] = &[
    ("document_store_meta", "CREATE TABLE document_store_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)"),
    ("document_heads", "CREATE TABLE document_heads(project_id TEXT NOT NULL REFERENCES projects(id),document_id TEXT NOT NULL,revision TEXT NOT NULL,PRIMARY KEY(project_id,document_id))"),
    ("document_revisions", "CREATE TABLE document_revisions(project_id TEXT NOT NULL,document_id TEXT NOT NULL,revision TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(project_id,document_id,revision),FOREIGN KEY(project_id,document_id) REFERENCES document_heads(project_id,document_id))"),
    ("document_grants", "CREATE TABLE document_grants(grant_id TEXT PRIMARY KEY,generation TEXT NOT NULL,owner_epoch TEXT NOT NULL,document_json TEXT NOT NULL,permissions TEXT NOT NULL,expires_at_ms TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN(0,1)))"),
    ("document_annotations", "CREATE TABLE document_annotations(project_id TEXT NOT NULL,document_id TEXT NOT NULL,annotation_id TEXT NOT NULL,revision TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(project_id,document_id,annotation_id),FOREIGN KEY(project_id,document_id) REFERENCES document_heads(project_id,document_id))"),
    ("document_annotation_history", "CREATE TABLE document_annotation_history(project_id TEXT NOT NULL,document_id TEXT NOT NULL,annotation_id TEXT NOT NULL,revision TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(project_id,document_id,annotation_id,revision),FOREIGN KEY(project_id,document_id) REFERENCES document_heads(project_id,document_id))"),
];

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DocumentMetadata {
    pub document: DocumentRef,
    pub title: String,
    pub blob: BlobRef,
}
/// A request reference only; all authority is resolved against current SQL rows.
#[derive(Clone, Debug)]
pub struct DocumentAccess {
    pub document: DocumentRef,
    pub authority: AuthorityBinding,
}
fn sql<T>(value: crate::sqlite::Result<T>) -> Result<T> {
    value.map_err(|_| ContractError::Storage)
}
fn cell(row: &[Option<String>], index: usize) -> Result<&str> {
    row.get(index).and_then(Option::as_deref).ok_or(ContractError::StorageCorrupt)
}
fn encode<T: Serialize>(value: &T) -> Result<String> {
    serde_json::to_string(value).map_err(|_| ContractError::InvalidPayload)
}
fn decode<T: serde::de::DeserializeOwned>(raw: &str) -> Result<T> {
    serde_json::from_str(raw).map_err(|_| ContractError::StorageCorrupt)
}
fn now_ms() -> Result<u64> {
    SystemTime::now().duration_since(UNIX_EPOCH)
        .map_err(|_| ContractError::InvalidAuthority)?.as_millis()
        .try_into().map_err(|_| ContractError::InvalidAuthority)
}
fn identifier(value: &str) -> Result<()> {
    if valid_id(value) { Ok(()) } else { Err(ContractError::InvalidIdentity) }
}
fn binding_shape(binding: &AuthorityBinding) -> Result<()> {
    identifier(&binding.grant_id)?;
    identifier(&binding.owner_epoch)?;
    if binding.generation.value() == 0 { return Err(ContractError::InvalidAuthority); }
    Ok(())
}

impl BusinessStore {
    /// Explicit host initialization. Uses the existing lock, connection and schema
    /// namespace; a partial or unknown schema is rejected, never auto-migrated.
    pub fn initialize_documents_trusted(&self) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        let mut present = 0;
        for (name, _) in SCHEMA {
            present += sql(self.database().query("SELECT name FROM sqlite_master WHERE type='table' AND name=?", &[name]))?.len();
        }
        if present == 0 {
            for (_, ddl) in SCHEMA { sql(self.database().exec(ddl, &[]))?; }
            sql(self.database().exec("INSERT INTO document_store_meta VALUES('version','1')", &[]))?;
            sql(self.database().exec("INSERT INTO document_store_meta VALUES('workspace',?)", &[self.workspace_id()]))?;
        } else if present != SCHEMA.len() { return Err(ContractError::InvalidVersion); }
        self.document_schema()?;
        sql(tx.commit())
    }
    fn document_schema(&self) -> Result<()> {
        for (name, ddl) in SCHEMA {
            let rows = sql(self.database().query("SELECT sql FROM sqlite_master WHERE type='table' AND name=?", &[name]))?;
            if rows.len() != 1 || cell(&rows[0], 0)? != *ddl { return Err(ContractError::InvalidVersion); }
        }
        let rows = sql(self.database().query("SELECT key,value FROM document_store_meta ORDER BY key", &[]))?;
        if rows != vec![vec![Some("version".into()), Some("1".into())], vec![Some("workspace".into()), Some(self.workspace_id().into())]] {
            return Err(ContractError::InvalidVersion);
        }
        Ok(())
    }
    fn document_project<'a>(&self, document: &'a DocumentRef) -> Result<&'a str> {
        if document.scope().workspace_id != self.workspace_id() { return Err(ContractError::ScopeMismatch); }
        let project = document.scope().project_id.as_deref().ok_or(ContractError::ScopeMismatch)?;
        if self.project(project)?.deleted { return Err(ContractError::NotFound); }
        Ok(project)
    }
    fn current_document(&self, document: &DocumentRef) -> Result<DocumentMetadata> {
        let project = self.document_project(document)?;
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(h.revision AS BLOB))<=20 THEN h.revision ELSE NULL END,CASE WHEN length(CAST(r.revision AS BLOB))<=20 THEN r.revision ELSE NULL END,CASE WHEN length(CAST(r.payload AS BLOB))<=8192 THEN r.payload ELSE NULL END FROM document_heads h LEFT JOIN document_revisions r ON r.project_id=h.project_id AND r.document_id=h.document_id AND r.revision=h.revision WHERE h.project_id=? AND h.document_id=?", &[project, document.document_id()]))?;
        if rows.is_empty() { return Err(ContractError::NotFound); }
        let metadata: DocumentMetadata = decode(cell(&rows[0], 2)?)?;
        if metadata.document.revision().as_str() != cell(&rows[0], 0)?
            || metadata.document.revision().as_str() != cell(&rows[0], 1)?
            || metadata.document.scope() != document.scope()
            || metadata.document.document_id() != document.document_id()
        { return Err(ContractError::StorageCorrupt); }
        metadata.blob.validate()?;
        document.matches(&metadata.document).map_err(|reason| match reason {
            super::ReadInvalidation::StaleRevision => ContractError::RevisionConflict,
            _ => ContractError::BindingMismatch,
        })?;
        Ok(metadata)
    }
    /// Must only be called while this owner's transaction is open. SQL authority,
    /// project liveness and current document revision are checked on every access.
    fn document_access(&self, access: &DocumentAccess, required: &[DocumentOperation]) -> Result<DocumentMetadata> {
        self.document_schema()?;
        let metadata = self.current_document(&access.document)?;
        self.document_grant(access, required)?;
        Ok(metadata)
    }
    // Grant truth is separate from the current head: publication advances the
    // head inside the gateway transaction before its final grant/expiry check.
    fn document_grant(&self, access: &DocumentAccess, required: &[DocumentOperation]) -> Result<()> {
        self.document_schema()?;
        binding_shape(&access.authority)?;
        if access.authority.owner_epoch != self.owner_epoch() { return Err(ContractError::InvalidAuthority); }
        self.document_project(&access.document)?;
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(document_json AS BLOB))<=8192 THEN document_json ELSE NULL END,CASE WHEN length(CAST(permissions AS BLOB))<=1024 THEN permissions ELSE NULL END,CASE WHEN length(CAST(expires_at_ms AS BLOB))<=20 THEN expires_at_ms ELSE NULL END FROM document_grants WHERE grant_id=? AND generation=? AND owner_epoch=? AND active=1", &[&access.authority.grant_id, access.authority.generation.as_str(), self.owner_epoch()]))?;
        if rows.len() != 1 { return Err(ContractError::InvalidAuthority); }
        let granted: DocumentRef = decode(cell(&rows[0], 0)?)?;
        let operations: Vec<DocumentOperation> = decode(cell(&rows[0], 1)?)?;
        let expires = cell(&rows[0], 2)?.parse::<u64>().map_err(|_| ContractError::StorageCorrupt)?;
        if granted != access.document || expires <= now_ms()? || required.iter().any(|op| !operations.contains(op)) {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(())
    }
    /// Gateway integration seam: current persisted authority plus exact head
    /// revision under the gateway's existing transaction. Does not commit or
    /// imply engine support/confirmation. Propagate errors and roll back.
    pub(crate) fn document_access_in_transaction(&self, tx: &Transaction<'_>, access: &DocumentAccess, required: &[DocumentOperation]) -> Result<DocumentMetadata> {
        if !tx.belongs_to(self.database()) { return Err(ContractError::InvalidAuthority); }
        self.document_access(access, required)
    }
    /// Publication-tail check only: validates the original persisted grant,
    /// generation/epoch/expiry, operation and project liveness after CAS changed
    /// the head. Does not resolve or authorize reading an old document revision.
    /// Gateway must first use document_access_in_transaction and perform exact
    /// CAS; propagate failure and roll back publication/receipt together.
    pub(crate) fn document_grant_in_transaction(&self, tx: &Transaction<'_>, access: &DocumentAccess, required: &[DocumentOperation]) -> Result<()> {
        if !tx.belongs_to(self.database()) { return Err(ContractError::InvalidAuthority); }
        self.document_grant(access, required)
    }
    pub fn register_document_trusted(&self, project_id: &str, document_id: &str, title: &str, format: DocumentFormat, finished: &FinishedBlob) -> Result<DocumentMetadata> {
        let base = DocumentRef::new(Scope { workspace_id: self.workspace_id().into(), project_id: Some(project_id.into()) }, document_id, Revision::new(0), format).map_err(|_| ContractError::InvalidIdentity)?;
        self.publish_document_revision_trusted(&base, title, format, finished)
    }
    /// Host/gateway only. Publishes a new immutable blob reference and metadata;
    /// never overwrites earlier revision rows or original document bytes.
    pub fn publish_document_revision_trusted(&self, base: &DocumentRef, title: &str, format: DocumentFormat, finished: &FinishedBlob) -> Result<DocumentMetadata> {
        let tx = sql(self.database().transaction())?;
        let metadata = self.document_publish_in_transaction(&tx, base, title, format, finished)?;
        sql(tx.commit())?;
        Ok(metadata)
    }
    /// The transaction gateway can atomically add its receipt/journal on this same
    /// connection. This hook authenticates transaction ownership, NOT user intent.
    pub(crate) fn document_publish_in_transaction(&self, tx: &Transaction<'_>, base: &DocumentRef, title: &str, format: DocumentFormat, finished: &FinishedBlob) -> Result<DocumentMetadata> {
        if !tx.belongs_to(self.database()) { return Err(ContractError::InvalidAuthority); }
        self.document_schema()?;
        let project = self.document_project(base)?;
        let title = normalize_text(title, 500, true)?.ok_or(ContractError::Required)?;
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(revision AS BLOB))<=20 THEN revision ELSE NULL END FROM document_heads WHERE project_id=? AND document_id=?", &[project, base.document_id()]))?;
        if rows.is_empty() {
            if base.revision().value() != 0 { return Err(ContractError::RevisionConflict); }
        } else { self.current_document(base)?; }
        let revision = base.revision().next()?;
        let document = DocumentRef::new(base.scope().clone(), base.document_id(), revision.clone(), format).map_err(|_| ContractError::InvalidIdentity)?;
        let binding = encode(&document)?;
        let digest: String = Sha256::digest(binding.as_bytes()).iter().map(|byte| format!("{byte:02x}")).collect();
        let reference = format!("doc-{digest}");
        let blob = self.publish_blob_in_transaction(tx, &finished.upload_id, &reference, project, base.document_id(), &finished.blob)?;
        if rows.is_empty() {
            sql(self.database().exec("INSERT INTO document_heads VALUES(?,?,?)", &[project, base.document_id(), revision.as_str()]))?;
        } else {
            let changed = sql(self.database().exec("UPDATE document_heads SET revision=? WHERE project_id=? AND document_id=? AND revision=?", &[revision.as_str(), project, base.document_id(), base.revision().as_str()]))?;
            if changed != 1 { return Err(ContractError::RevisionConflict); }
        }
        let metadata = DocumentMetadata { document, title, blob };
        sql(self.database().exec("INSERT INTO document_revisions VALUES(?,?,?,?)", &[project, base.document_id(), revision.as_str(), &encode(&metadata)?]))?;
        Ok(metadata)
    }
    /// HOST ONLY, after authentic current policy/user authorization. No model or
    /// deserialized permission list may call this. Reissue must use next generation.
    pub fn issue_document_grant_trusted(&self, document: &DocumentRef, authority: &AuthorityBinding, operations: &[DocumentOperation], expires_at_ms: u64) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        self.document_schema()?;
        self.current_document(document)?;
        binding_shape(authority)?;
        let now = now_ms()?;
        if authority.owner_epoch != self.owner_epoch() || expires_at_ms <= now
            || expires_at_ms > now.checked_add(30_000).ok_or(ContractError::InvalidAuthority)?
            || operations.is_empty() || operations.len() > 9
        { return Err(ContractError::InvalidAuthority); }
        let old = sql(self.database().query("SELECT CASE WHEN length(CAST(generation AS BLOB))<=20 THEN generation ELSE NULL END FROM document_grants WHERE grant_id=?", &[&authority.grant_id]))?;
        let expected = if old.is_empty() { Revision::new(1) } else { Revision::parse(cell(&old[0], 0)?)?.next()? };
        if authority.generation != expected { return Err(ContractError::InvalidAuthority); }
        sql(self.database().exec("INSERT INTO document_grants VALUES(?,?,?,?,?,?,1) ON CONFLICT(grant_id) DO UPDATE SET generation=excluded.generation,owner_epoch=excluded.owner_epoch,document_json=excluded.document_json,permissions=excluded.permissions,expires_at_ms=excluded.expires_at_ms,active=1", &[&authority.grant_id, authority.generation.as_str(), self.owner_epoch(), &encode(document)?, &encode(&operations)?, &expires_at_ms.to_string()]))?;
        sql(tx.commit())
    }
    pub fn revoke_document_grant_trusted(&self, authority: &AuthorityBinding) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        self.document_schema()?;
        binding_shape(authority)?;
        if authority.owner_epoch != self.owner_epoch() { return Err(ContractError::InvalidAuthority); }
        let changed = sql(self.database().exec("UPDATE document_grants SET active=0 WHERE grant_id=? AND generation=? AND owner_epoch=?", &[&authority.grant_id, authority.generation.as_str(), self.owner_epoch()]))?;
        if changed != 1 { return Err(ContractError::InvalidAuthority); }
        sql(tx.commit())
    }
    pub fn read_document(&self, access: &DocumentAccess) -> Result<DocumentMetadata> {
        let tx = sql(self.database().transaction())?;
        let metadata = self.document_access(access, &[DocumentOperation::Inspect])?;
        sql(tx.commit())?;
        Ok(metadata)
    }
    fn annotation_rows(&self, document: &DocumentRef) -> Result<Vec<AnnotationRecord>> {
        let project = self.document_project(document)?;
        // SQL computes byte/count budgets before returning any payload TEXT to
        // the C ABI. Corrupt oversized strings never reach Rust's row allocator.
        let budget = sql(self.database().query("SELECT COUNT(*),COALESCE(SUM(length(CAST(payload AS BLOB))),0),COALESCE(MAX(length(CAST(payload AS BLOB))),0),COALESCE(MAX(length(CAST(annotation_id AS BLOB))),0),COALESCE(MAX(length(CAST(revision AS BLOB))),0) FROM document_annotations WHERE project_id=? AND document_id=?", &[project, document.document_id()]))?;
        let size = |index| -> Result<u64> { cell(&budget[0], index)?.parse().map_err(|_| ContractError::StorageCorrupt) };
        if size(0)? > MAX_ANNOTATIONS as u64 || size(1)? > 16 * 1024 * 1024
            || size(2)? > 256 * 1024 || size(3)? > 128 || size(4)? > 20
        { return Err(ContractError::TextLimit); }
        let rows = sql(self.database().query("SELECT annotation_id,revision,CASE WHEN length(CAST(payload AS BLOB))<=262144 THEN payload ELSE NULL END FROM document_annotations WHERE project_id=? AND document_id=? ORDER BY annotation_id LIMIT 1001", &[project, document.document_id()]))?;
        if rows.len() > MAX_ANNOTATIONS { return Err(ContractError::TextLimit); }
        rows.iter().map(|row| {
            let mut record: AnnotationRecord = decode(cell(row, 2)?)?;
            identifier(&record.id)?;
            record.body.validate()?;
            record.created_by.validate()?;
            record.modified_by.validate()?;
            if record.id != cell(row, 0)? || record.revision.as_str() != cell(row, 1)?
                || record.revision.value() == 0 || record.anchor.document.scope() != document.scope()
                || record.anchor.document.document_id() != document.document_id()
                || record.anchor.document.revision() > document.revision()
                || record.anchor.validate_for(&record.anchor.document) != Ok(AnchorStatus::StructurallyValid)
            { return Err(ContractError::StorageCorrupt); }
            record.anchor_state = if record.anchor.document == *document { StoredAnchorState::Current } else { StoredAnchorState::Stale };
            Ok(record)
        }).collect()
    }
    fn put_annotation(&self, document: &DocumentRef, record: &AnnotationRecord) -> Result<()> {
        let project = self.document_project(document)?;
        let payload = encode(record)?;
        if payload.len() > 256 * 1024 { return Err(ContractError::TextLimit); }
        // Preserve the read budget on writes too, so legitimate growth cannot
        // strand a document above the limit with no ability to edit/delete.
        let remaining = sql(self.database().query("SELECT COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM document_annotations WHERE project_id=? AND document_id=? AND annotation_id<>?", &[project, document.document_id(), &record.id]))?;
        let bytes: u64 = cell(&remaining[0], 0)?.parse().map_err(|_| ContractError::StorageCorrupt)?;
        if bytes.checked_add(payload.len() as u64).ok_or(ContractError::TextLimit)? > 16 * 1024 * 1024 {
            return Err(ContractError::TextLimit);
        }
        sql(self.database().exec("INSERT INTO document_annotation_history VALUES(?,?,?,?,?)", &[project, document.document_id(), &record.id, record.revision.as_str(), &payload]))?;
        sql(self.database().exec("INSERT INTO document_annotations VALUES(?,?,?,?,?) ON CONFLICT(project_id,document_id,annotation_id) DO UPDATE SET revision=excluded.revision,payload=excluded.payload", &[project, document.document_id(), &record.id, record.revision.as_str(), &payload]))?;
        Ok(())
    }
    /// Provenance is host-supplied authenticated actor/run metadata, never AI text.
    /// An annotation's original creator is immutable; current editor is separate.
    pub fn save_annotation_trusted(&self, access: &DocumentAccess, annotation_id: &str, expected: &Revision, anchor: &DocumentAnchor, body: &AnnotationBody, author: &AnnotationAuthor) -> Result<AnnotationRecord> {
        identifier(annotation_id)?;
        body.validate()?;
        author.validate()?;
        if anchor.validate_for(&access.document) != Ok(AnchorStatus::StructurallyValid) { return Err(ContractError::InvalidPayload); }
        let tx = sql(self.database().transaction())?;
        self.document_access(access, &[DocumentOperation::ReadText, DocumentOperation::Annotate])?;
        let records = self.annotation_rows(&access.document)?;
        let old = records.iter().find(|record| record.id == annotation_id);
        let created_by = if let Some(old) = old {
            if old.deleted || &old.revision != expected { return Err(ContractError::RevisionConflict); }
            old.created_by.clone()
        } else {
            if expected.value() != 0 { return Err(ContractError::RevisionConflict); }
            if records.len() >= MAX_ANNOTATIONS { return Err(ContractError::TextLimit); }
            author.clone()
        };
        let record = AnnotationRecord { id: annotation_id.into(), revision: expected.next()?, anchor: anchor.clone(), body: body.clone(), created_by, modified_by: author.clone(), deleted: false, anchor_state: StoredAnchorState::Current };
        self.put_annotation(&access.document, &record)?;
        sql(tx.commit())?;
        Ok(record)
    }
    pub fn delete_annotation_trusted(&self, access: &DocumentAccess, annotation_id: &str, expected: &Revision, author: &AnnotationAuthor) -> Result<AnnotationRecord> {
        identifier(annotation_id)?;
        author.validate()?;
        let tx = sql(self.database().transaction())?;
        self.document_access(access, &[DocumentOperation::ReadText, DocumentOperation::Annotate])?;
        let mut record = self.annotation_rows(&access.document)?.into_iter().find(|record| record.id == annotation_id).ok_or(ContractError::NotFound)?;
        if record.deleted || &record.revision != expected { return Err(ContractError::RevisionConflict); }
        record.revision = expected.next()?;
        record.modified_by = author.clone();
        record.deleted = true;
        self.put_annotation(&access.document, &record)?;
        sql(tx.commit())?;
        Ok(record)
    }
    pub fn list_annotations(&self, access: &DocumentAccess) -> Result<Vec<AnnotationRecord>> {
        let tx = sql(self.database().transaction())?;
        self.document_access(access, &[DocumentOperation::ReadText])?;
        let records = self.annotation_rows(&access.document)?;
        sql(tx.commit())?;
        Ok(records)
    }
    pub fn export_annotations(&self, access: &DocumentAccess) -> Result<AnnotationExport> {
        let tx = sql(self.database().transaction())?;
        let document = self.document_access(access, &[DocumentOperation::ReadText, DocumentOperation::Export])?;
        let export = AnnotationExport { schema: "muyon.annotation-sidecar.v1".into(), annotations: self.annotation_rows(&access.document)?, document };
        if encode(&export)?.len() > 16 * 1024 * 1024 { return Err(ContractError::TextLimit); }
        sql(tx.commit())?;
        Ok(export)
    }
}
