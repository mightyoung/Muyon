//! Durable project artifacts are a catalog of canonical document revisions.
//! No document bytes, grants, chat state or engine capability are duplicated here.
//! All entry points are trusted-host operations; provenance is authenticated by
//! the host, never inferred from generated content. Call only on explicit save.
use crate::{
    blobs::FinishedBlob,
    business::BusinessStore,
    contract::{ContractError, Revision, Scope},
    documents::{AnnotationAuthor, DocumentAccess, DocumentMetadata, DocumentOperation},
    sqlite::Transaction,
};
use serde::{Deserialize, Serialize};
mod project_access;
mod save_journal;
mod catalog;
pub mod local_interactions;
pub use project_access::{ArtifactProjectAccess, ArtifactProjectOperation};
pub use save_journal::{ArtifactSaveOperation, ArtifactSaveOutcome, ArtifactSaveReceipt, ArtifactSaveStatus};
pub use catalog::ArtifactCatalogEntry;

type Result<T> = std::result::Result<T, ContractError>;
const MAX_SOURCES: usize = 16;
const MAX_RECORD_BYTES: usize = 160 * 1024;
const MAX_PAGE: u32 = 32;
const SCHEMA: &[(&str, &str)] = &[
    ("artifact_store_meta", "CREATE TABLE artifact_store_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)"),
    ("artifact_heads", "CREATE TABLE artifact_heads(project_id TEXT NOT NULL REFERENCES projects(id),artifact_id TEXT NOT NULL,document_id TEXT NOT NULL,revision TEXT NOT NULL,PRIMARY KEY(project_id,artifact_id),UNIQUE(project_id,document_id))"),
    ("artifact_revisions", "CREATE TABLE artifact_revisions(project_id TEXT NOT NULL,artifact_id TEXT NOT NULL,revision TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(project_id,artifact_id,revision),FOREIGN KEY(project_id,artifact_id) REFERENCES artifact_heads(project_id,artifact_id))"),
];
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactContext {
    pub message_id: String,
    pub attempt_id: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactOrigin {
    pub author: AnnotationAuthor,
    pub context: Option<ArtifactContext>,
}
impl ArtifactOrigin {
    fn validate(&self) -> Result<()> {
        self.author.validate()?;
        if let Some(context) = &self.context {
            identifier(&context.message_id)?;
            identifier(&context.attempt_id)?;
        }
        Ok(())
    }
    fn is_human(&self) -> bool { matches!(self.author, AnnotationAuthor::Human { .. }) }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactRevision {
    pub artifact_id: String,
    pub revision: Revision,
    /// Canonical output document metadata, never a second copy of its body.
    pub document: DocumentMetadata,
    /// Exact source revisions at the explicit initial archive. Never retargeted.
    pub sources: Vec<DocumentMetadata>,
    pub created_by: ArtifactOrigin,
    pub modified_by: ArtifactOrigin,
    /// Sticky protection: no generated save may overwrite a human revision.
    pub human_edited: bool,
}
fn identifier(s: &str) -> Result<()> {
    if s.is_empty() || s.len() > 128 || !s.bytes().all(|c| c.is_ascii_alphanumeric() || b"-_.:".contains(&c)) {
        Err(ContractError::InvalidIdentity)
    } else { Ok(()) }
}
fn sql<T>(r: crate::sqlite::Result<T>) -> Result<T> { r.map_err(|_| ContractError::Storage) }
fn cell(row: &[Option<String>], at: usize) -> Result<&str> {
    row.get(at).and_then(Option::as_deref).ok_or(ContractError::StorageCorrupt)
}
fn encode<T: Serialize>(v: &T) -> Result<String> { serde_json::to_string(v).map_err(|_| ContractError::InvalidPayload) }
fn decode<T: serde::de::DeserializeOwned>(v: &str) -> Result<T> { serde_json::from_str(v).map_err(|_| ContractError::StorageCorrupt) }
fn same_document(a: &DocumentMetadata, access: &DocumentAccess) -> bool {
    a.document.scope() == access.document.scope() && a.document.document_id() == access.document.document_id()
}
fn project(access: &DocumentAccess) -> Result<&str> {
    access.document.scope().project_id.as_deref().ok_or(ContractError::ScopeMismatch)
}
impl BusinessStore {
    /// Explicit namespace initialization on the existing owner connection only.
    /// Partial/unknown schemas are rejected; no migrations or replacement occur.
    pub fn initialize_artifacts_trusted(&self) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        let mut count = 0;
        for (name, _) in SCHEMA {
            count += sql(self.database().query("SELECT name FROM sqlite_master WHERE type='table' AND name=?", &[name]))?.len();
        }
        if count == 0 {
            for (_, ddl) in SCHEMA { sql(self.database().exec(ddl, &[]))?; }
            sql(self.database().exec("INSERT INTO artifact_store_meta VALUES('version','1')", &[]))?;
            sql(self.database().exec("INSERT INTO artifact_store_meta VALUES('workspace',?)", &[self.workspace_id()]))?;
        } else if count != SCHEMA.len() { return Err(ContractError::InvalidVersion); }
        self.artifact_schema()?;
        sql(tx.commit())
    }
    fn artifact_schema(&self) -> Result<()> {
        for (name, ddl) in SCHEMA {
            let rows = sql(self.database().query("SELECT sql FROM sqlite_master WHERE type='table' AND name=?", &[name]))?;
            if rows.len() != 1 || cell(&rows[0], 0)? != *ddl { return Err(ContractError::InvalidVersion); }
        }
        let rows = sql(self.database().query("SELECT key,value FROM artifact_store_meta ORDER BY key", &[]))?;
        if rows != vec![vec![Some("version".into()), Some("1".into())], vec![Some("workspace".into()), Some(self.workspace_id().into())]] {
            return Err(ContractError::InvalidVersion);
        }
        Ok(())
    }
    fn artifact_access(&self, tx: &Transaction<'_>, access: &DocumentAccess, write: bool) -> Result<DocumentMetadata> {
        self.document_access_in_transaction(tx, access, if write {
            &[DocumentOperation::ReadText, DocumentOperation::StructuredEdit]
        } else { &[DocumentOperation::ReadText] })
    }
    fn artifact_sources(&self, tx: &Transaction<'_>, output: &DocumentAccess, sources: &[DocumentAccess]) -> Result<Vec<DocumentMetadata>> {
        if sources.len() > MAX_SOURCES { return Err(ContractError::TextLimit); }
        let mut captured = Vec::new();
        for access in sources {
            if access.document.scope() != output.document.scope() { return Err(ContractError::ScopeMismatch); }
            if access.document.document_id() == output.document.document_id()
                || captured.iter().any(|old| same_document(old, access)) {
                return Err(ContractError::InvalidPayload);
            }
            captured.push(self.artifact_access(tx, access, false)?);
        }
        Ok(captured)
    }
    fn artifact_head(&self, id: &str, access: &DocumentAccess) -> Result<Option<Revision>> {
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(document_id AS BLOB))<=128 THEN document_id ELSE NULL END,CASE WHEN length(CAST(revision AS BLOB))<=20 THEN revision ELSE NULL END FROM artifact_heads WHERE project_id=? AND artifact_id=?", &[project(access)?, id]))?;
        if rows.is_empty() { return Ok(None); }
        if cell(&rows[0], 0)? != access.document.document_id() { return Err(ContractError::BindingMismatch); }
        let revision = Revision::parse(cell(&rows[0], 1)?).map_err(|_| ContractError::StorageCorrupt)?;
        if revision.value() == 0 { return Err(ContractError::StorageCorrupt); }
        Ok(Some(revision))
    }
    fn artifact_record(&self, id: &str, revision: &Revision, access: &DocumentAccess) -> Result<ArtifactRevision> {
        self.artifact_record_for_scope(id, revision, access.document.scope(), access.document.document_id())
    }
    fn artifact_record_for_scope(&self, id: &str, revision: &Revision, scope: &Scope, document_id: &str) -> Result<ArtifactRevision> {
        let project_id = scope.project_id.as_deref().ok_or(ContractError::ScopeMismatch)?;
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(payload AS BLOB))<=163840 THEN payload ELSE NULL END FROM artifact_revisions WHERE project_id=? AND artifact_id=? AND revision=?", &[project_id, id, revision.as_str()]))?;
        if rows.is_empty() { return Err(ContractError::NotFound); }
        let record: ArtifactRevision = decode(cell(&rows[0], 0)?)?;
        if record.artifact_id != id || &record.revision != revision || revision.value() == 0
            || record.document.document.scope() != scope || record.document.document.document_id() != document_id || record.sources.len() > MAX_SOURCES
            || (record.modified_by.is_human() && !record.human_edited)
            || (record.created_by.is_human() && !record.human_edited) {
            return Err(ContractError::StorageCorrupt);
        }
        record.created_by.validate()?;
        record.modified_by.validate()?;
        // Catalog snapshots must equal existing immutable canonical SQL metadata.
        for metadata in std::iter::once(&record.document).chain(record.sources.iter()) {
            if metadata.document.scope() != scope { return Err(ContractError::StorageCorrupt); }
            let canonical = sql(self.database().query("SELECT CASE WHEN length(CAST(payload AS BLOB))<=8192 THEN payload ELSE NULL END FROM document_revisions WHERE project_id=? AND document_id=? AND revision=?", &[project_id, metadata.document.document_id(), metadata.document.revision().as_str()]))?;
            if canonical.len() != 1 || decode::<DocumentMetadata>(cell(&canonical[0], 0)?)? != *metadata {
                return Err(ContractError::StorageCorrupt);
            }
            metadata.blob.validate()?;
        }
        Ok(record)
    }
    fn artifact_authorize_record(&self, tx: &Transaction<'_>, record: &ArtifactRevision, output: &DocumentAccess, sources: &[DocumentAccess]) -> Result<()> {
        if !same_document(&record.document, output) { return Err(ContractError::BindingMismatch); }
        // Current grant alone never authorizes old content. Core explicitly checks
        // exact historical policy and canonical immutable metadata in this tx.
        let metadata = self.document_history_access_in_transaction(tx, output, &record.document.document, &[DocumentOperation::ReadText])?;
        if metadata != record.document { return Err(ContractError::StorageCorrupt); }
        self.artifact_authorize_snapshots(tx, output, &record.sources, sources)
    }
    fn artifact_authorize_snapshots(&self, tx: &Transaction<'_>, output: &DocumentAccess, snapshots: &[DocumentMetadata], sources: &[DocumentAccess]) -> Result<()> {
        self.artifact_sources(tx, output, sources)?;
        for snapshot in snapshots {
            let access = sources.iter().find(|access| access.document.document_id() == snapshot.document.document_id()).ok_or(ContractError::InvalidAuthority)?;
            let metadata = self.document_history_access_in_transaction(tx, access, &snapshot.document, &[DocumentOperation::ReadText])?;
            if metadata != *snapshot { return Err(ContractError::StorageCorrupt); }
        }
        Ok(())
    }
    fn artifact_put(&self, record: &ArtifactRevision, output: &DocumentAccess, expected: &Revision) -> Result<()> {
        let payload = encode(record)?;
        if payload.len() > MAX_RECORD_BYTES { return Err(ContractError::TextLimit); }
        if expected.value() == 0 {
            sql(self.database().exec("INSERT INTO artifact_heads VALUES(?,?,?,?)", &[project(output)?, &record.artifact_id, output.document.document_id(), record.revision.as_str()]))?;
        } else {
            let changed = sql(self.database().exec("UPDATE artifact_heads SET revision=? WHERE project_id=? AND artifact_id=? AND document_id=? AND revision=?", &[record.revision.as_str(), project(output)?, &record.artifact_id, output.document.document_id(), expected.as_str()]))?;
            if changed != 1 { return Err(ContractError::RevisionConflict); }
        }
        sql(self.database().exec("INSERT INTO artifact_revisions VALUES(?,?,?,?)", &[project(output)?, &record.artifact_id, record.revision.as_str(), &payload]))?;
        Ok(())
    }
    /// Explicit save of an already-published canonical document. A duplicate ID
    /// conflicts: this API never implies retry/idempotent business execution.
    #[cfg(test)]
    pub(crate) fn archive_artifact_trusted(&self, id: &str, output: &DocumentAccess, sources: &[DocumentAccess], origin: &ArtifactOrigin) -> Result<ArtifactRevision> {
        let tx = sql(self.database().transaction())?;
        let record = self.archive_artifact_in_transaction(&tx, id, output, sources, origin)?;
        sql(tx.commit())?;
        Ok(record)
    }
    fn archive_artifact_in_transaction(&self, tx: &Transaction<'_>, id: &str, output: &DocumentAccess, sources: &[DocumentAccess], origin: &ArtifactOrigin) -> Result<ArtifactRevision> {
        identifier(id)?; origin.validate()?;
        self.artifact_schema()?;
        let document = self.artifact_access(tx, output, true)?;
        if self.artifact_head(id, output)?.is_some() { return Err(ContractError::RevisionConflict); }
        let record = ArtifactRevision { artifact_id: id.into(), revision: Revision::new(1), document, sources: self.artifact_sources(tx, output, sources)?, created_by: origin.clone(), modified_by: origin.clone(), human_edited: origin.is_human() };
        self.artifact_put(&record, output, &Revision::new(0))?;
        self.artifact_access(tx, output, true)?;
        self.artifact_sources(tx, output, sources)?;
        Ok(record)
    }
    /// Publishes immutable canonical document + artifact revision atomically.
    /// Sources stay at their captured revisions; current grants are still needed.
    /// No automatic recommendation may replace a human-edited artifact, even
    /// with a fresh expected revision. Save generated results under a new ID/doc.
    #[allow(clippy::too_many_arguments)]
    #[cfg(test)]
    pub(crate) fn revise_artifact_trusted(&self, id: &str, expected: &Revision, output: &DocumentAccess, finished: &FinishedBlob, title: &str, current_sources: &[DocumentAccess], origin: &ArtifactOrigin) -> Result<ArtifactRevision> {
        let tx = sql(self.database().transaction())?;
        let record = self.revise_artifact_in_transaction(&tx, id, expected, output, finished, title, current_sources, origin)?;
        sql(tx.commit())?;
        Ok(record)
    }
    #[allow(clippy::too_many_arguments)]
    fn revise_artifact_in_transaction(&self, tx: &Transaction<'_>, id: &str, expected: &Revision, output: &DocumentAccess, finished: &FinishedBlob, title: &str, current_sources: &[DocumentAccess], origin: &ArtifactOrigin) -> Result<ArtifactRevision> {
        identifier(id)?; origin.validate()?;
        self.artifact_schema()?;
        self.artifact_access(tx, output, true)?;
        if self.artifact_head(id, output)?.as_ref() != Some(expected) { return Err(ContractError::RevisionConflict); }
        let old = self.artifact_record(id, expected, output)?;
        // Reject external document edits rather than silently absorbing them.
        if old.document.document != output.document { return Err(ContractError::RevisionConflict); }
        self.artifact_authorize_record(tx, &old, output, current_sources)?;
        if old.human_edited && !origin.is_human() { return Err(ContractError::IntentConflict); }
        let document = self.document_publish_in_transaction(tx, &output.document, title, output.document.format(), finished)?;
        let record = ArtifactRevision { artifact_id: id.into(), revision: expected.next()?, document, sources: old.sources, created_by: old.created_by, modified_by: origin.clone(), human_edited: old.human_edited || origin.is_human() };
        self.artifact_put(&record, output, expected)?;
        self.document_grant_in_transaction(tx, output, &[DocumentOperation::ReadText, DocumentOperation::StructuredEdit])?;
        self.artifact_authorize_snapshots(tx, output, &record.sources, current_sources)?;
        Ok(record)
    }
    /// Recovery lookup only: returns exact archived refs under current + explicit
    /// core historical policy for both output and sources. No latest substitution,
    /// implicit historical grant, head restoration or byte delivery occurs.
    /// Byte delivery must remain behind the trusted host's current access checks.
    pub fn read_artifact_revision(&self, id: &str, revision: &Revision, output: &DocumentAccess, current_sources: &[DocumentAccess]) -> Result<ArtifactRevision> {
        identifier(id)?;
        let tx = sql(self.database().transaction())?;
        self.artifact_schema()?; self.artifact_access(&tx, output, false)?;
        let head = self.artifact_head(id, output)?.ok_or(ContractError::NotFound)?;
        if revision > &head { return Err(ContractError::NotFound); }
        let record = self.artifact_record(id, revision, output)?;
        self.artifact_authorize_record(&tx, &record, output, current_sources)?;
        sql(tx.commit())?; Ok(record)
    }
    /// Descending exclusive revision cursor; decimal revisions sort by length
    /// then text to preserve u64 order. One page returns at most 32 bounded rows.
    pub fn artifact_history(&self, id: &str, before: Option<&Revision>, limit: u32, output: &DocumentAccess, current_sources: &[DocumentAccess]) -> Result<Vec<ArtifactRevision>> {
        identifier(id)?;
        if limit == 0 || limit > MAX_PAGE { return Err(ContractError::InvalidPayload); }
        let tx = sql(self.database().transaction())?;
        self.artifact_schema()?; self.artifact_access(&tx, output, false)?;
        let head = self.artifact_head(id, output)?.ok_or(ContractError::NotFound)?;
        let cursor = before.map(Revision::as_str).unwrap_or("18446744073709551616");
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(revision AS BLOB))<=20 THEN revision ELSE NULL END FROM artifact_revisions WHERE project_id=? AND artifact_id=? AND (length(revision)<length(?) OR (length(revision)=length(?) AND revision<?)) ORDER BY length(revision) DESC,revision DESC LIMIT ?", &[project(output)?, id, cursor, cursor, cursor, &limit.to_string()]))?;
        let mut records = Vec::new();
        for row in rows {
            let revision = Revision::parse(cell(&row, 0)?).map_err(|_| ContractError::StorageCorrupt)?;
            if revision > head { return Err(ContractError::StorageCorrupt); }
            let record = self.artifact_record(id, &revision, output)?;
            self.artifact_authorize_record(&tx, &record, output, current_sources)?;
            records.push(record);
        }
        // Even an empty page never bypasses fresh source grant validation.
        let current = self.artifact_record(id, &head, output)?;
        self.artifact_authorize_record(&tx, &current, output, current_sources)?;
        sql(tx.commit())?; Ok(records)
    }
}
#[cfg(test)]
mod tests;

#[cfg(test)]
mod workflow_tests;
