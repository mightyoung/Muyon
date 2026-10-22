//! Durable private preparation only. No real validator exists: publication is disabled.
use super::{identity::valid_id, DocumentAccess, DocumentMetadata, DocumentOperation, DocumentRef};
use crate::{blobs::{BlobKind, MAX_CHUNK, MAX_DOCUMENT_BYTES}, business::BusinessStore, contract::*, sqlite::Transaction};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
type Result<T> = std::result::Result<T, ContractError>;
const DDL: &str = "CREATE TABLE document_candidates_v1(candidate_id TEXT PRIMARY KEY,workspace TEXT NOT NULL,project_id TEXT NOT NULL REFERENCES projects(id),upload_id TEXT NOT NULL UNIQUE REFERENCES blob_uploads(upload_id),expected_length TEXT NOT NULL,payload TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN('preparing','sealed_unvalidated','preparation_unknown')))";
const PERMISSIONS: &[DocumentOperation] = &[DocumentOperation::ReadText, DocumentOperation::StructuredEdit];

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CandidateState { Preparing, SealedUnvalidated, PreparationUnknown }
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct CandidateStatus {
    pub candidate_id: String,
    pub operation_id: String,
    pub base: DocumentRef,
    pub expected_blob: BlobRef,
    pub state: CandidateState,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Row {
    candidate_id: String,
    operation_id: String,
    base: DocumentRef,
    source_blob: BlobRef,
    authority: AuthorityBinding,
    expected_blob: BlobRef,
    upload_id: String,
}
fn sql<T>(result: crate::sqlite::Result<T>) -> Result<T> { result.map_err(|_| ContractError::Storage) }
fn cell(row: &[Option<String>], n: usize) -> Result<&str> { row.get(n).and_then(Option::as_deref).ok_or(ContractError::StorageCorrupt) }
fn encode<T: Serialize>(value: &T) -> Result<String> { serde_json::to_string(value).map_err(|_| ContractError::InvalidPayload) }
fn identifier(value: &str) -> Result<()> { if valid_id(value) { Ok(()) } else { Err(ContractError::InvalidIdentity) } }
impl BusinessStore {
    pub fn initialize_document_candidates_trusted(&self) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        // Requires the original canonical document store to be initialized.
        self.document_schema()?;
        let rows = sql(self.database().query("SELECT name FROM sqlite_master WHERE type='table' AND name='document_candidates_v1'", &[]))?;
        if rows.is_empty() { sql(self.database().exec(DDL, &[]))?; }
        self.candidate_schema()?;
        sql(tx.commit())
    }
    fn candidate_schema(&self) -> Result<()> {
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(sql AS BLOB))<=2048 THEN sql ELSE NULL END FROM sqlite_master WHERE type='table' AND name='document_candidates_v1'", &[]))?;
        if rows.len() != 1 || cell(&rows[0], 0)? != DDL { return Err(ContractError::InvalidVersion); }
        Ok(())
    }
    fn candidate_row(&self, candidate_id: &str) -> Result<(Row, CandidateState)> {
        identifier(candidate_id)?;
        self.candidate_schema()?;
        let rows = sql(self.database().query("SELECT workspace,project_id,upload_id,expected_length,CASE WHEN length(CAST(payload AS BLOB))<=8192 THEN payload ELSE NULL END,state FROM document_candidates_v1 WHERE candidate_id=?", &[candidate_id]))?;
        let raw = rows.first().ok_or(ContractError::NotFound)?;
        let row: Row = serde_json::from_str(cell(raw, 4)?).map_err(|_| ContractError::StorageCorrupt)?;
        identifier(&row.operation_id)?; identifier(&row.upload_id)?;
        row.source_blob.validate()?; row.expected_blob.validate()?;
        if row.candidate_id != candidate_id || cell(raw, 0)? != self.workspace_id()
            || row.base.scope().workspace_id != self.workspace_id()
            || row.base.scope().project_id.as_deref() != Some(cell(raw, 1)?)
            || row.upload_id != cell(raw, 2)? || row.expected_blob.byte_length.as_str() != cell(raw, 3)?
            || row.expected_blob.byte_length.value() == 0 || row.expected_blob.byte_length.value() > MAX_DOCUMENT_BYTES
        { return Err(ContractError::StorageCorrupt); }
        let state = match cell(raw, 5)? {
            "preparing" => CandidateState::Preparing,
            "sealed_unvalidated" => CandidateState::SealedUnvalidated,
            "preparation_unknown" => CandidateState::PreparationUnknown,
            _ => return Err(ContractError::StorageCorrupt),
        };
        Ok((row, state))
    }
    fn candidate_status(&self, row: &Row, recorded: CandidateState) -> CandidateStatus {
        // Any uncertain/interrupted preparation remains query-only, even if an
        // object happens to exist. A missing/mismatched sealed pin is unknown.
        let ready = self.candidate_upload_is_pinned(&row.upload_id, row.base.scope().project_id.as_deref().unwrap_or(""), &row.expected_blob).unwrap_or(false);
        let state = if recorded == CandidateState::SealedUnvalidated && ready { recorded } else { CandidateState::PreparationUnknown };
        CandidateStatus { candidate_id: row.candidate_id.clone(), operation_id: row.operation_id.clone(), base: row.base.clone(), expected_blob: row.expected_blob.clone(), state }
    }
    fn mark_candidate_unknown(&self, candidate_id: &str) {
        // Best effort factual status only; it never changes sealed output into
        // failure after an uncertain sealing COMMIT or replays any file work.
        if let Ok(tx) = self.database().transaction() {
            if self.database().exec("UPDATE document_candidates_v1 SET state='preparation_unknown' WHERE candidate_id=? AND workspace=? AND state='preparing'", &[candidate_id, self.workspace_id()]).is_ok() {
                let _ = tx.commit();
            }
        }
    }
    fn candidate_preflight(&self, access: &DocumentAccess) -> Result<DocumentMetadata> {
        let tx = sql(self.database().transaction())?;
        let metadata = self.document_access_in_transaction(&tx, access, PERMISSIONS)?;
        tx.commit().map_err(|_| ContractError::Unknown)?;
        Ok(metadata)
    }
    pub fn prepare_document_candidate_trusted(&self, access: &DocumentAccess, candidate_id: &str, operation_id: &str, bytes: &[u8]) -> Result<CandidateStatus> {
        identifier(candidate_id)?; identifier(operation_id)?;
        if bytes.is_empty() || bytes.len() as u64 > MAX_DOCUMENT_BYTES { return Err(ContractError::TextLimit); }
        let expected = BlobRef { digest: Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect(), byte_length: Revision::new(bytes.len() as u64) };
        let tx = sql(self.database().transaction())?;
        let source = self.document_access_in_transaction(&tx, access, PERMISSIONS)?;
        self.candidate_schema()?;
        match self.candidate_row(candidate_id) {
            Ok((row, state)) => {
                if row.base != access.document || row.authority != access.authority || row.expected_blob != expected || row.operation_id != operation_id || row.source_blob != source.blob {
                    return Err(ContractError::IntentConflict);
                }
                let status = self.candidate_status(&row, state);
                self.document_grant_in_transaction(&tx, access, PERMISSIONS)?;
                tx.commit().map_err(|_| ContractError::Unknown)?;
                return Ok(status);
            }
            Err(ContractError::NotFound) => {}
            Err(error) => return Err(error),
        }
        let project = access.document.scope().project_id.as_deref().ok_or(ContractError::ScopeMismatch)?;
        let budget = sql(self.database().query("SELECT COUNT(*),COALESCE(SUM(CAST(expected_length AS INTEGER)),0),COALESCE(SUM(CASE WHEN expected_length='' OR expected_length GLOB '*[^0-9]*' OR length(expected_length)>8 OR CAST(expected_length AS INTEGER) NOT BETWEEN 1 AND 31457280 THEN 1 ELSE 0 END),0) FROM document_candidates_v1 WHERE workspace=? AND project_id=?", &[self.workspace_id(), project]))?;
        let count: u64 = cell(&budget[0], 0)?.parse().map_err(|_| ContractError::StorageCorrupt)?;
        let used: u64 = cell(&budget[0], 1)?.parse().map_err(|_| ContractError::StorageCorrupt)?;
        if cell(&budget[0], 2)? != "0" { return Err(ContractError::StorageCorrupt); }
        if count >= 32 || used.checked_add(bytes.len() as u64).ok_or(ContractError::TextLimit)? > 128 * 1024 * 1024 { return Err(ContractError::TextLimit); }
        let upload = self.reserve_candidate_upload_in_transaction(&tx, project)?;
        let row = Row { candidate_id: candidate_id.into(), operation_id: operation_id.into(), base: access.document.clone(), source_blob: source.blob, authority: access.authority.clone(), expected_blob: expected, upload_id: upload.upload_id };
        let payload = encode(&row)?;
        if payload.len() > 8192 { return Err(ContractError::TextLimit); }
        sql(self.database().exec("INSERT INTO document_candidates_v1 VALUES(?,?,?,?,?,?,'preparing')", &[candidate_id, self.workspace_id(), project, &row.upload_id, row.expected_blob.byte_length.as_str(), &payload]))?;
        self.document_grant_in_transaction(&tx, access, PERMISSIONS)?;
        tx.commit().map_err(|_| ContractError::Unknown)?;
        // From here failures may leave real durable filesystem bytes. Never
        // interpret an error as rollback/permission to repeat the write sequence.
        let work = (|| -> Result<()> {
            self.candidate_preflight(access)?;
            self.materialize_candidate_upload_trusted(&row.upload_id)?;
            for chunk in bytes.chunks(MAX_CHUNK) {
                self.candidate_preflight(access)?;
                self.append_chunk(&row.upload_id, chunk)?;
            }
            self.candidate_preflight(access)?;
            let finished = self.finish_blob(&row.upload_id, BlobKind::Document)?;
            if finished.blob != row.expected_blob { return Err(ContractError::BindingMismatch); }
            let seal = sql(self.database().transaction())?;
            self.document_access_in_transaction(&seal, access, PERMISSIONS)?;
            let (actual, state) = self.candidate_row(candidate_id)?;
            if actual != row || state != CandidateState::Preparing || !self.candidate_upload_is_pinned(&row.upload_id, project, &row.expected_blob)? { return Err(ContractError::BindingMismatch); }
            let changed = sql(self.database().exec("UPDATE document_candidates_v1 SET state='sealed_unvalidated' WHERE candidate_id=? AND workspace=? AND state='preparing'", &[candidate_id, self.workspace_id()]))?;
            if changed != 1 { return Err(ContractError::IntentConflict); }
            self.document_grant_in_transaction(&seal, access, PERMISSIONS)?;
            seal.commit().map_err(|_| ContractError::Unknown)?;
            Ok(())
        })();
        if work.is_err() { self.mark_candidate_unknown(candidate_id); return Err(ContractError::Unknown); }
        self.lookup_document_candidate(access, candidate_id)
    }
    pub fn lookup_document_candidate(&self, access: &DocumentAccess, candidate_id: &str) -> Result<CandidateStatus> {
        let tx = sql(self.database().transaction())?;
        let source = self.document_access_in_transaction(&tx, access, PERMISSIONS)?;
        let (row, state) = self.candidate_row(candidate_id)?;
        if row.base != access.document || row.source_blob != source.blob { return Err(ContractError::BindingMismatch); }
        let status = self.candidate_status(&row, state);
        self.document_grant_in_transaction(&tx, access, PERMISSIONS)?;
        tx.commit().map_err(|_| ContractError::Unknown)?;
        Ok(status)
    }
    pub(crate) fn document_publish_candidate_in_transaction(&self, tx: &Transaction<'_>, access: &DocumentAccess, candidate_id: &str) -> Result<DocumentMetadata> {
        if !tx.belongs_to(self.database()) { return Err(ContractError::InvalidAuthority); }
        let source = self.document_access_in_transaction(tx, access, PERMISSIONS)?;
        let (row, _) = self.candidate_row(candidate_id)?;
        if row.base != access.document || row.source_blob != source.blob { return Err(ContractError::BindingMismatch); }
        // No real validator is integrated. There is deliberately no caller bool,
        // forged validation token, test-only success gate, CAS or reference write.
        Err(ContractError::UnsupportedOperation)
    }
    pub(crate) fn document_candidate_upload_retained(&self, upload_id: &str) -> Result<bool> {
        let exists = sql(self.database().query("SELECT name FROM sqlite_master WHERE type='table' AND name='document_candidates_v1'", &[]))?;
        if exists.is_empty() { return Ok(false); }
        self.candidate_schema()?;
        let rows = sql(self.database().query("SELECT 1 FROM document_candidates_v1 WHERE workspace=? AND upload_id=? LIMIT 1", &[self.workspace_id(), upload_id]))?;
        Ok(!rows.is_empty())
    }
}
