//! Save intent journal on the same BusinessStore connection, not another store.
//! A pending row is durably recorded before any effect. Lookup never runs effects.
use super::*;
use crate::{contract::RecoveryAction, documents::DocumentRef};
use sha2::{Digest, Sha256};
const MAX_REQUEST: usize = 64 * 1024;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum ArtifactSaveOperation {
    Archive { artifact_id: String, origin: ArtifactOrigin },
    Revise { artifact_id: String, expected_revision: Revision, finished: FinishedBlob, title: String, origin: ArtifactOrigin },
}
impl ArtifactSaveOperation {
    fn artifact_id(&self) -> &str { match self { Self::Archive { artifact_id, .. } | Self::Revise { artifact_id, .. } => artifact_id } }
    fn origin(&self) -> &ArtifactOrigin { match self { Self::Archive { origin, .. } | Self::Revise { origin, .. } => origin } }
    fn validate(&self, actor: &str) -> Result<()> {
        identifier(self.artifact_id())?; self.origin().validate()?;
        if let AnnotationAuthor::Human { actor_id } = &self.origin().author {
            if actor_id != actor { return Err(ContractError::InvalidAuthority); }
        }
        if let Self::Revise { expected_revision, finished, title, .. } = self {
            if expected_revision.value() == 0 || title.len() > 4096 || title.contains('\0') { return Err(ContractError::InvalidPayload); }
            identifier(&finished.upload_id)?; identifier(&finished.snapshot_id)?; finished.blob.validate()?;
        }
        Ok(())
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactSaveStatus { Committed, Rejected, Unknown }
/// Historical operation receipt, not permission to read content/current state.
/// Deliberately excludes body, title, author details and source snapshots.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactSaveReceipt {
    pub intent_id: String,
    pub binding_digest: String,
    pub scope: Scope,
    pub actor_id: String,
    pub artifact_id: String,
    pub artifact_revision: Revision,
    pub document: DocumentRef,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArtifactSaveOutcome {
    pub status: ArtifactSaveStatus,
    pub receipt: Option<ArtifactSaveReceipt>,
    pub error: Option<ContractError>,
    pub recovery_action: RecoveryAction,
}
impl ArtifactSaveOutcome {
    fn unknown(error: ContractError) -> Self {
        Self { status: ArtifactSaveStatus::Unknown, receipt: None, error: Some(error), recovery_action: RecoveryAction::QueryOriginal }
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct SaveRequest {
    version: u32,
    intent_id: String,
    scope: Scope,
    actor_id: String,
    project_revision: Revision,
    output: DocumentRef,
    sources: Vec<DocumentRef>,
    operation: ArtifactSaveOperation,
}
impl SaveRequest {
    fn binding(&self) -> Result<(String, String)> {
        let json = encode(self)?;
        if json.len() > MAX_REQUEST { return Err(ContractError::TextLimit); }
        let mut hash = Sha256::new(); hash.update(b"muyon.artifact-save.v1\0"); hash.update(json.as_bytes());
        let digest = hash.finalize().iter().map(|byte| format!("{byte:02x}")).collect();
        Ok((json, digest))
    }
    fn validate_receipt(&self, receipt: &ArtifactSaveReceipt, digest: &str) -> Result<()> {
        let (artifact_revision, document_revision) = match &self.operation {
            ArtifactSaveOperation::Archive { .. } => (Revision::new(1), self.output.revision().clone()),
            ArtifactSaveOperation::Revise { expected_revision, .. } => (expected_revision.next()?, self.output.revision().next()?),
        };
        if receipt.intent_id != self.intent_id || receipt.binding_digest != digest
            || receipt.scope != self.scope || receipt.actor_id != self.actor_id
            || receipt.artifact_id != self.operation.artifact_id() || receipt.artifact_revision != artifact_revision
            || receipt.document.scope() != &self.scope || receipt.document.document_id() != self.output.document_id()
            || receipt.document.format() != self.output.format() || receipt.document.revision() != &document_revision {
            return Err(ContractError::StorageCorrupt);
        }
        Ok(())
    }
}
pub(super) fn requires_original_lookup(error: &ContractError) -> bool {
    matches!(error, ContractError::Unknown | ContractError::Storage | ContractError::StorageBusy | ContractError::StorageConstraint | ContractError::StorageCorrupt | ContractError::StorageIo)
}

#[derive(Clone, Copy)]
pub(super) enum JournalDomain { Artifact, Local }
/// Internal pending-row inputs borrowed from the already frozen original request.
/// No FFI/serialization contract: both callers remain inside this artifact module.
pub(super) struct PendingJournal<'a> {
    pub(super) target: PendingJournalTarget<'a>,
    pub(super) intent_id: &'a str,
    pub(super) project_id: &'a str,
    pub(super) actor_id: &'a str,
    pub(super) binding_digest: &'a str,
    pub(super) request_json: &'a str,
}
pub(super) enum PendingJournalTarget<'a> {
    Artifact,
    Local { object_id: &'a str },
}
/// Internal effect phase: a receipt-tail invalidation cannot become a durable
/// rejection. Its effect transaction must roll back, leaving the original pending.
pub(super) enum ArtifactSaveFailure {
    BeforeReceipt(ContractError),
    ReceiptTail(ContractError),
}
impl From<ContractError> for ArtifactSaveFailure {
    fn from(error: ContractError) -> Self { Self::BeforeReceipt(error) }
}
impl BusinessStore {
    fn artifact_save_rows(&self, intent: &str) -> Result<Vec<Vec<Option<String>>>> { self.journal_rows(JournalDomain::Artifact, intent) }
    pub(super) fn journal_rows(&self, domain: JournalDomain, intent: &str) -> Result<Vec<Vec<Option<String>>>> {
        let query = match domain {
            JournalDomain::Artifact => "SELECT CASE WHEN length(CAST(binding_digest AS BLOB))<=64 THEN binding_digest ELSE NULL END,CASE WHEN length(CAST(request_json AS BLOB))<=65536 THEN request_json ELSE NULL END,CASE WHEN length(CAST(status AS BLOB))<=16 THEN status ELSE NULL END,CASE WHEN length(CAST(receipt_json AS BLOB))<=8192 THEN receipt_json ELSE NULL END,CASE WHEN length(CAST(error AS BLOB))<=128 THEN error ELSE NULL END FROM artifact_save_intents_v1 WHERE intent_id=?",
            JournalDomain::Local => "SELECT CASE WHEN length(CAST(binding_digest AS BLOB))<=64 THEN binding_digest ELSE NULL END,CASE WHEN length(CAST(request_json AS BLOB))<=65536 THEN request_json ELSE NULL END,CASE WHEN length(CAST(status AS BLOB))<=16 THEN status ELSE NULL END,CASE WHEN length(CAST(receipt_json AS BLOB))<=8192 THEN receipt_json ELSE NULL END,CASE WHEN length(CAST(error AS BLOB))<=128 THEN error ELSE NULL END FROM artifact_local_intents_v1 WHERE intent_id=?",
        };
        sql(self.database().query(query, &[intent]))
    }
    pub(super) fn journal_pending(&self, pending: PendingJournal<'_>) -> Result<()> {
        let PendingJournal { target, intent_id, project_id, actor_id, binding_digest, request_json } = pending;
        match target {
            PendingJournalTarget::Artifact => sql(self.database().exec("INSERT INTO artifact_save_intents_v1 VALUES(?,?,?,?,?,'pending',NULL,NULL)", &[intent_id, project_id, actor_id, binding_digest, request_json]))?,
            PendingJournalTarget::Local { object_id } => sql(self.database().exec("INSERT INTO artifact_local_intents_v1 VALUES(?,?,?,?,?,'pending',NULL,NULL,?)", &[intent_id, project_id, actor_id, binding_digest, request_json, object_id]))?,
        };
        Ok(())
    }
    pub(super) fn journal_commit_receipt(&self, domain: JournalDomain, intent: &str, digest: &str, receipt: &str) -> Result<()> {
        if receipt.len() > 8192 { return Err(ContractError::TextLimit); }
        let query = match domain {
            JournalDomain::Artifact => "UPDATE artifact_save_intents_v1 SET status='committed',receipt_json=?,error=NULL WHERE intent_id=? AND binding_digest=? AND status='pending'",
            JournalDomain::Local => "UPDATE artifact_local_intents_v1 SET status='committed',receipt_json=?,error=NULL WHERE intent_id=? AND binding_digest=? AND status='pending'",
        };
        if sql(self.database().exec(query, &[receipt, intent, digest]))? != 1 { return Err(ContractError::StorageCorrupt); }
        Ok(())
    }
    fn artifact_save_projection(&self, intent: &str, row: &[Option<String>], access: &ArtifactProjectAccess) -> Result<ArtifactSaveOutcome> {
        let request: SaveRequest = decode(cell(row, 1)?)?;
        let (_, digest) = request.binding()?;
        if request.version != 1 || request.intent_id != intent || cell(row, 0)? != digest { return Err(ContractError::StorageCorrupt); }
        if request.scope != access.scope || request.actor_id != access.actor_id { return Err(ContractError::InvalidAuthority); }
        match cell(row, 2)? {
            "pending" => Ok(ArtifactSaveOutcome::unknown(ContractError::Unknown)),
            "committed" => {
                let receipt: ArtifactSaveReceipt = decode(cell(row, 3)?)?;
                request.validate_receipt(&receipt, &digest)?;
                Ok(ArtifactSaveOutcome { status: ArtifactSaveStatus::Committed, receipt: Some(receipt), error: None, recovery_action: RecoveryAction::None })
            }
            "rejected" => {
                let error: ContractError = decode(cell(row, 4)?)?;
                if requires_original_lookup(&error) { return Err(ContractError::StorageCorrupt); }
                Ok(ArtifactSaveOutcome { status: ArtifactSaveStatus::Rejected, receipt: None, error: Some(error), recovery_action: RecoveryAction::None })
            },
            _ => Err(ContractError::StorageCorrupt),
        }
    }
    /// Explicit host save only. The caller must retain this intent and exact
    /// request until resolved. Storage errors yield Unknown/QueryOriginal; callers
    /// MUST query this original intent, never automatically submit a replacement.
    /// A durable pending/committed/rejected intent never invokes effects again.
    pub fn submit_artifact_save_trusted(&self, intent: &str, access: &ArtifactProjectAccess, operation: &ArtifactSaveOperation, output: &DocumentAccess, sources: &[DocumentAccess]) -> Result<ArtifactSaveOutcome> {
        identifier(intent)?; operation.validate(&access.actor_id)?;
        if access.scope != *output.document.scope() { return Err(ContractError::ScopeMismatch); }
        if sources.len() > MAX_SOURCES { return Err(ContractError::TextLimit); }
        let request = SaveRequest { version: 1, intent_id: intent.into(), scope: access.scope.clone(), actor_id: access.actor_id.clone(), project_revision: access.project_revision.clone(), output: output.document.clone(), sources: sources.iter().map(|source| source.document.clone()).collect(), operation: operation.clone() };
        let (json, digest) = request.binding()?;
        match self.artifact_save_execute(intent, access, operation, output, sources, &json, &digest) {
            Err(error) if requires_original_lookup(&error) => Ok(ArtifactSaveOutcome::unknown(error)),
            result => result,
        }
    }
    #[allow(clippy::too_many_arguments)]
    fn artifact_save_execute(&self, intent: &str, access: &ArtifactProjectAccess, operation: &ArtifactSaveOperation, output: &DocumentAccess, sources: &[DocumentAccess], json: &str, digest: &str) -> Result<ArtifactSaveOutcome> {
        {
            let tx = sql(self.database().transaction())?;
            self.artifact_project_authorize(&tx, access, ArtifactProjectOperation::Save)?;
            let rows = self.artifact_save_rows(intent)?;
            if let Some(row) = rows.first() {
                if cell(row, 0)? != digest || cell(row, 1)? != json { return Err(ContractError::IntentConflict); }
                let result = self.artifact_save_projection(intent, row, access)?;
                self.artifact_project_authorize(&tx, access, ArtifactProjectOperation::Save)?;
                sql(tx.commit())?; return Ok(result);
            }
            self.artifact_access(&tx, output, true)?;
            self.artifact_sources(&tx, output, sources)?;
            self.journal_pending(PendingJournal { target: PendingJournalTarget::Artifact, intent_id: intent, project_id: access.project_id()?, actor_id: &access.actor_id, binding_digest: digest, request_json: json })?;
            self.artifact_project_authorize(&tx, access, ArtifactProjectOperation::Save)?;
            sql(tx.commit())?; // PENDING_DURABLE: no artifact/document effect yet.
        }
        let outcome = (|| -> std::result::Result<ArtifactSaveOutcome, ArtifactSaveFailure> {
            let tx = sql(self.database().transaction())?;
            self.artifact_project_authorize(&tx, access, ArtifactProjectOperation::Save)?;
            let rows = self.artifact_save_rows(intent)?;
            let row = rows.first().ok_or(ContractError::StorageCorrupt)?;
            if cell(row, 0)? != digest || cell(row, 1)? != json || cell(row, 2)? != "pending" { return Err(ContractError::IntentConflict.into()); }
            let record = match operation {
                ArtifactSaveOperation::Archive { artifact_id, origin } => self.archive_artifact_in_transaction(&tx, artifact_id, output, sources, origin)?,
                ArtifactSaveOperation::Revise { artifact_id, expected_revision, finished, title, origin } => self.revise_artifact_in_transaction(&tx, artifact_id, expected_revision, output, finished, title, sources, origin)?,
            };
            let receipt = ArtifactSaveReceipt { intent_id: intent.into(), binding_digest: digest.into(), scope: access.scope.clone(), actor_id: access.actor_id.clone(), artifact_id: record.artifact_id.clone(), artifact_revision: record.revision.clone(), document: record.document.document.clone() };
            let request: SaveRequest = decode(json)?; request.validate_receipt(&receipt, digest)?;
            self.journal_commit_receipt(JournalDomain::Artifact, intent, digest, &encode(&receipt)?)
                .map_err(ArtifactSaveFailure::ReceiptTail)?;
            // This is the last write. A receipt trigger can invalidate grants
            // after the helpers' earlier checks; recheck every authority here.
            // The output head has advanced on revise: grant-only is correct for
            // this publication tail, and never used to authorize history reads.
            self.document_grant_in_transaction(&tx, output, &[DocumentOperation::ReadText, DocumentOperation::StructuredEdit])
                .map_err(ArtifactSaveFailure::ReceiptTail)?;
            self.artifact_authorize_snapshots(&tx, output, &record.sources, sources)
                .map_err(ArtifactSaveFailure::ReceiptTail)?;
            self.artifact_project_authorize(&tx, access, ArtifactProjectOperation::Save)
                .map_err(ArtifactSaveFailure::ReceiptTail)?;
            sql(tx.commit())?; // EFFECT_COMMIT: canonical document + artifact + original receipt.
            Ok(ArtifactSaveOutcome { status: ArtifactSaveStatus::Committed, receipt: Some(receipt), error: None, recovery_action: RecoveryAction::None })
        })();
        match outcome {
            Ok(result) => Ok(result),
            Err(failure) => self.artifact_save_failure_outcome(intent, digest, failure),
        }
    }
    pub(super) fn artifact_save_failure_outcome(&self, intent: &str, digest: &str, failure: ArtifactSaveFailure) -> Result<ArtifactSaveOutcome> { self.journal_failure_outcome(JournalDomain::Artifact, intent, digest, failure) }
    pub(super) fn journal_failure_outcome(&self, domain: JournalDomain, intent: &str, digest: &str, failure: ArtifactSaveFailure) -> Result<ArtifactSaveOutcome> {
        let error = match failure {
            ArtifactSaveFailure::ReceiptTail(error) => return Ok(ArtifactSaveOutcome::unknown(error)),
            ArtifactSaveFailure::BeforeReceipt(error) => error,
        };
        // Unknown from any future effect hook is uncertainty, never a semantic
        // rejection. Keep the original pending row untouched and query it.
        if requires_original_lookup(&error) {
            return Ok(ArtifactSaveOutcome::unknown(error));
        }
        // Failed effect transaction has dropped and rolled back before a
        // determinate semantic rejection is journaled in a separate transaction.
        let tx = sql(self.database().transaction())?;
        let query = match domain {
            JournalDomain::Artifact => "UPDATE artifact_save_intents_v1 SET status='rejected',error=? WHERE intent_id=? AND binding_digest=? AND status='pending'",
            JournalDomain::Local => "UPDATE artifact_local_intents_v1 SET status='rejected',error=? WHERE intent_id=? AND binding_digest=? AND status='pending'",
        };
        let changed = sql(self.database().exec(query, &[&encode(&error)?, intent, digest]))?;
        if changed != 1 { return Err(ContractError::StorageCorrupt); }
        sql(tx.commit())?;
        Ok(ArtifactSaveOutcome { status: ArtifactSaveStatus::Rejected, receipt: None, error: Some(error), recovery_action: RecoveryAction::None })
    }
    /// Read only and actor scoped. Does not create/reconcile a pending save,
    /// retry a failed upload, publish content, or authorize historical bytes.
    pub fn lookup_artifact_save(&self, intent: &str, access: &ArtifactProjectAccess) -> Result<ArtifactSaveOutcome> {
        identifier(intent)?;
        let outcome = (|| {
            let tx = sql(self.database().transaction())?;
            self.artifact_project_authorize(&tx, access, ArtifactProjectOperation::LookupOwnSaves)?;
            // Filter ownership inside SQL so another actor cannot distinguish a
            // private intent from an absent one. Submit retains global ID conflict checks.
            let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(binding_digest AS BLOB))<=64 THEN binding_digest ELSE NULL END,CASE WHEN length(CAST(request_json AS BLOB))<=65536 THEN request_json ELSE NULL END,CASE WHEN length(CAST(status AS BLOB))<=16 THEN status ELSE NULL END,CASE WHEN length(CAST(receipt_json AS BLOB))<=8192 THEN receipt_json ELSE NULL END,CASE WHEN length(CAST(error AS BLOB))<=128 THEN error ELSE NULL END FROM artifact_save_intents_v1 WHERE intent_id=? AND project_id=? AND actor_id=?", &[intent, access.project_id()?, &access.actor_id]))?;
            let result = match rows.first() {
                Some(row) => self.artifact_save_projection(intent, row, access)?,
                None => ArtifactSaveOutcome::unknown(ContractError::NotFound),
            };
            self.artifact_project_authorize(&tx, access, ArtifactProjectOperation::LookupOwnSaves)?;
            sql(tx.commit())?; Ok(result)
        })();
        match outcome { Err(error) if requires_original_lookup(&error) => Ok(ArtifactSaveOutcome::unknown(error)), result => result }
    }
}
