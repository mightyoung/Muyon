//! Metadata-only bindings to actual StoreEvidence output. Never a second text store.
use super::{local_interactions::*, *};
use crate::{
    contract::AuthorityBinding,
    documents::DocumentRef,
    evidence::{
        store::{StoreEvidence, StoreEvidenceError, StoredProcessing},
        EvidenceRef,
    },
};
use sha2::{Digest, Sha256};

const NAME: &str = "artifact_local_evidence_sources_v1";
const DDL: &str = "CREATE TABLE artifact_local_evidence_sources_v1(project_id TEXT NOT NULL REFERENCES projects(id),actor_id TEXT NOT NULL,object_id TEXT NOT NULL,document_id TEXT NOT NULL,payload TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN(0,1)),PRIMARY KEY(project_id,actor_id,object_id))";
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Snapshot {
    metadata: DocumentMetadata,
    authority: AuthorityBinding,
    evidence_id: String,
    // Exact serialized StoreEvidence reference (offsets/digests, never quote text).
    reference_json: String,
}
// Persisted reference decoder only; it cannot construct a resolution proof.
// SourceVersion serialization and content-addressed IDs follow fixed Evidence
// 78cdff. The actual initial quote is always checked by StoreEvidence::open.
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct StoredSource {
    document: DocumentRef,
    blob: crate::contract::BlobRef,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StoredReference {
    evidence_id: String,
    source_id: String,
    source: StoredSource,
    start_byte: usize,
    end_byte: usize,
    quote_digest: String,
    page_index_zero_based: Option<u32>,
}
fn hash(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
impl Snapshot {
    fn validate(&self) -> Result<()> {
        let r: StoredReference = decode(&self.reference_json)?;
        if r.source.document != self.metadata.document
            || r.source.blob != self.metadata.blob
            || r.evidence_id != self.evidence_id
            || r.source_id != format!("source-{}", hash(encode(&r.source)?.as_bytes()))
            || r.start_byte >= r.end_byte
            || r.end_byte as u64 > self.metadata.blob.byte_length.value()
            || r.page_index_zero_based.is_some()
            || self.metadata.document.format() != crate::documents::DocumentFormat::Text
            || r.quote_digest.len() != 64
            || !r
                .quote_digest
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
            || r.evidence_id
                != format!(
                    "evidence-{}",
                    hash(
                        format!(
                            "{}:{}:{}:{}",
                            r.source_id, r.start_byte, r.end_byte, r.quote_digest
                        )
                        .as_bytes()
                    )
                )
        {
            return Err(ContractError::StorageCorrupt);
        }
        Ok(())
    }
}
/// Constructed only by real source resolution; cannot be deserialized or forged
/// from a model/display ID. Holding it does not authorize subsequent operations.
pub struct ResolvedLocalEvidence<'a> {
    snapshot: Snapshot,
    actor: String,
    store: &'a BusinessStore,
}
impl std::fmt::Debug for ResolvedLocalEvidence<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ResolvedLocalEvidence")
            .field("target", &self.target())
            .finish_non_exhaustive()
    }
}
impl ResolvedLocalEvidence<'_> {
    pub fn target(&self) -> LocalTarget {
        LocalTarget::Evidence {
            evidence_id: self.snapshot.evidence_id.clone(),
            revision: self.snapshot.metadata.document.revision().clone(),
        }
    }
}
/// Trusted owner event only. Deliver after the caller's source mutation commits.
/// No source body, form values or receipt mutation is included.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct LocalSourceInvalidation {
    pub project_id: String,
    pub actor_id: String,
    pub object_id: String,
}
fn processing_error(error: StoreEvidenceError) -> ContractError {
    match error {
        StoreEvidenceError::Core(error) => error,
        StoreEvidenceError::Processing(_) => ContractError::BindingMismatch,
        StoreEvidenceError::Cleanup { .. } => ContractError::Unknown,
    }
}
impl BusinessStore {
    pub(super) fn initialize_local_sources_in_transaction(
        &self,
        tx: &Transaction<'_>,
    ) -> Result<()> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::InvalidAuthority);
        }
        let rows = sql(self.database().query(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
            &[NAME],
        ))?;
        if rows.is_empty() {
            sql(self.database().exec(DDL, &[]))?;
        }
        self.local_source_schema()
    }
    fn local_source_schema(&self) -> Result<()> {
        let rows = sql(self.database().query(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
            &[NAME],
        ))?;
        if rows.len() != 1 || cell(&rows[0], 0)? != DDL {
            return Err(ContractError::InvalidVersion);
        }
        Ok(())
    }
    /// Resolve the exact original passage against registered document bytes,
    /// controlled blob reader, UTF8 extraction, quote digest and current ReadText.
    /// Quote is discarded; only an immutable metadata reference is retained.
    pub fn resolve_local_evidence_trusted<'a>(
        &'a self,
        project: &ArtifactProjectAccess,
        purpose: ArtifactProjectOperation,
        access: &DocumentAccess,
        processing: &StoredProcessing,
        reference: &EvidenceRef,
    ) -> Result<ResolvedLocalEvidence<'a>> {
        if !matches!(
            purpose,
            ArtifactProjectOperation::LocalDraft | ArtifactProjectOperation::LocalFeedback
        ) {
            return Err(ContractError::UnsupportedOperation);
        }
        if &project.scope != access.document.scope() {
            return Err(ContractError::ScopeMismatch);
        }
        {
            let tx = sql(self.database().transaction())?;
            self.artifact_project_authorize(&tx, project, purpose)?;
            sql(tx.commit())?;
        }
        let _quote = StoreEvidence::new(self)
            .open(access, processing, reference)
            .map_err(processing_error)?;
        let tx = sql(self.database().transaction())?;
        let metadata =
            self.document_access_in_transaction(&tx, access, &[DocumentOperation::ReadText])?;
        if &metadata != processing.source_metadata()
            || metadata.document != reference.source.document
            || metadata.blob != reference.source.blob
        {
            return Err(ContractError::BindingMismatch);
        }
        let snapshot = Snapshot {
            metadata,
            authority: access.authority.clone(),
            evidence_id: reference.evidence_id.clone(),
            reference_json: encode(reference)?,
        };
        if encode(&snapshot)?.len() > 16 * 1024 {
            return Err(ContractError::TextLimit);
        }
        self.artifact_project_authorize(&tx, project, purpose)?;
        sql(tx.commit())?;
        Ok(ResolvedLocalEvidence {
            snapshot,
            actor: project.actor_id.clone(),
            store: self,
        })
    }
    pub fn issue_local_evidence_binding_trusted(
        &self,
        a: &LocalAccess,
        kind: &LocalKind,
        expires: u64,
        proof: &ResolvedLocalEvidence<'_>,
    ) -> Result<()> {
        if !std::ptr::eq(self, proof.store) || a.project.actor_id != proof.actor {
            return Err(ContractError::BindingMismatch);
        }
        a.object.validate()?;
        let tx = sql(self.database().transaction())?;
        self.local_source_schema()?;
        self.validate_local_evidence_snapshot(&tx, a, &proof.snapshot)?;
        let payload = encode(&proof.snapshot)?;
        let rows = self.local_source_rows(a)?;
        if let Some(row) = rows.first() {
            let old: Snapshot = decode(cell(row, 0)?)?;
            if old.metadata != proof.snapshot.metadata
                || old.evidence_id != proof.snapshot.evidence_id
                || old.reference_json != proof.snapshot.reference_json
            {
                return Err(ContractError::BindingMismatch);
            }
            // Explicit real re-resolution may renew source authority only. The
            // binding generation must still advance below; old reviews stay stale.
            sql(self.database().exec("UPDATE artifact_local_evidence_sources_v1 SET payload=?,active=1 WHERE project_id=? AND actor_id=? AND object_id=?",&[&payload,a.project.project_id()?,&a.project.actor_id,&a.object.object_id]))?;
        } else {
            sql(self.database().exec(
                "INSERT INTO artifact_local_evidence_sources_v1 VALUES(?,?,?,?,?,1)",
                &[
                    a.project.project_id()?,
                    &a.project.actor_id,
                    &a.object.object_id,
                    proof.snapshot.metadata.document.document_id(),
                    &payload,
                ],
            ))?;
        }
        self.issue_local_binding_in_transaction(&tx, a, kind, expires)?;
        // Last binding write is followed by actual source and project checks.
        self.validate_local_evidence_snapshot(&tx, a, &proof.snapshot)?;
        sql(tx.commit())
    }
    fn local_source_rows(&self, a: &LocalAccess) -> Result<Vec<Vec<Option<String>>>> {
        sql(self.database().query("SELECT CASE WHEN length(CAST(payload AS BLOB))<=16384 THEN payload ELSE NULL END,active FROM artifact_local_evidence_sources_v1 WHERE project_id=? AND actor_id=? AND object_id=?",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id]))
    }
    fn validate_local_evidence_snapshot(
        &self,
        tx: &Transaction<'_>,
        a: &LocalAccess,
        snapshot: &Snapshot,
    ) -> Result<()> {
        snapshot.validate()?;
        match &a.object.target {
            LocalTarget::Message { .. } => return Err(ContractError::UnsupportedOperation),
            LocalTarget::Evidence {
                evidence_id,
                revision,
            } if evidence_id == &snapshot.evidence_id
                && revision == snapshot.metadata.document.revision() => {}
            _ => return Err(ContractError::BindingMismatch),
        }
        if a.project.scope != *snapshot.metadata.document.scope() {
            return Err(ContractError::ScopeMismatch);
        }
        let access = DocumentAccess {
            document: snapshot.metadata.document.clone(),
            authority: snapshot.authority.clone(),
        };
        let current =
            self.document_access_in_transaction(tx, &access, &[DocumentOperation::ReadText])?;
        if current != snapshot.metadata {
            return Err(ContractError::BindingMismatch);
        }
        Ok(())
    }
    pub(super) fn local_source_binding(&self, tx: &Transaction<'_>, a: &LocalAccess) -> Result<()> {
        if matches!(a.object.target, LocalTarget::Message { .. }) {
            return Err(ContractError::UnsupportedOperation);
        }
        self.local_source_schema()?;
        let rows = self.local_source_rows(a)?;
        let row = rows.first().ok_or(ContractError::InvalidAuthority)?;
        if cell(row, 1)? != "1" {
            return Err(ContractError::InvalidAuthority);
        }
        let snapshot: Snapshot = decode(cell(row, 0)?)?;
        self.validate_local_evidence_snapshot(tx, a, &snapshot)
    }
    /// Core-owner integration hook: call AFTER source head/grant changes, inside
    /// that SAME BusinessStore transaction, then publish returned IDs only AFTER
    /// its commit. No hook wiring is implied. All public local reads/mutations
    /// independently revalidate the source, so missed notifications fail closed.
    /// This scans only exact document identity; it does not discover projects.
    pub fn invalidate_local_evidence_sources_in_transaction(
        &self,
        tx: &Transaction<'_>,
        changed: &DocumentRef,
    ) -> Result<Vec<LocalSourceInvalidation>> {
        if !tx.belongs_to(self.database()) || changed.scope().workspace_id != self.workspace_id() {
            return Err(ContractError::ScopeMismatch);
        }
        self.local_source_schema()?;
        let project = changed
            .scope()
            .project_id
            .as_deref()
            .ok_or(ContractError::ScopeMismatch)?;
        let mut events = Vec::new();
        let mut after_actor = String::new();
        let mut after_object = String::new();
        loop {
            let rows=sql(self.database().query("SELECT actor_id,object_id,CASE WHEN length(CAST(payload AS BLOB))<=16384 THEN payload ELSE NULL END FROM artifact_local_evidence_sources_v1 WHERE project_id=? AND document_id=? AND active=1 AND (actor_id>? OR (actor_id=? AND object_id>?)) ORDER BY actor_id,object_id LIMIT 256",&[project,changed.document_id(),&after_actor,&after_actor,&after_object]))?;
            if rows.is_empty() {
                break;
            }
            for row in rows {
                after_actor = cell(&row, 0)?.into();
                after_object = cell(&row, 1)?.into();
                let snapshot: Snapshot = decode(cell(&row, 2)?)?;
                snapshot.validate()?;
                if snapshot.metadata.document.scope() != changed.scope()
                    || snapshot.metadata.document.document_id() != changed.document_id()
                {
                    return Err(ContractError::StorageCorrupt);
                }
                let access = DocumentAccess {
                    document: snapshot.metadata.document.clone(),
                    authority: snapshot.authority.clone(),
                };
                let valid = match self.document_access_in_transaction(
                    tx,
                    &access,
                    &[DocumentOperation::ReadText],
                ) {
                    Ok(metadata) => metadata == snapshot.metadata,
                    Err(
                        ContractError::InvalidAuthority
                        | ContractError::RevisionConflict
                        | ContractError::NotFound
                        | ContractError::BindingMismatch,
                    ) => false,
                    Err(error) => return Err(error),
                };
                if !valid {
                    let actor = cell(&row, 0)?;
                    let object = cell(&row, 1)?;
                    sql(self.database().exec("UPDATE artifact_local_evidence_sources_v1 SET active=0 WHERE project_id=? AND actor_id=? AND object_id=?",&[project,actor,object]))?;
                    sql(self.database().exec("UPDATE artifact_local_bindings_v1 SET active=0 WHERE project_id=? AND actor_id=? AND object_id=?",&[project,actor,object]))?;
                    events.push(LocalSourceInvalidation {
                        project_id: project.into(),
                        actor_id: actor.into(),
                        object_id: object.into(),
                    });
                }
            }
        }
        Ok(events)
    }
}
