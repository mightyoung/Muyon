//! Project discovery returns inventory metadata only; no document/source content.
use super::*;
use crate::documents::DocumentRef;
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ArtifactCatalogEntry {
    pub artifact_id: String,
    pub revision: Revision,
    pub document: DocumentRef,
    pub title: String,
    pub human_edited: bool,
}
impl BusinessStore {
    /// Independent project Discover permission, not any document permission.
    /// Stable artifact-ID cursor (exclusive). A catalog record remains an inventory
    /// snapshot; content/history requires separate exact document authorization.
    pub fn discover_project_artifacts(
        &self,
        access: &ArtifactProjectAccess,
        after: Option<&str>,
        limit: u32,
    ) -> Result<Vec<ArtifactCatalogEntry>> {
        if limit == 0 || limit > MAX_PAGE {
            return Err(ContractError::InvalidPayload);
        }
        if let Some(after) = after {
            identifier(after)?;
        }
        let tx = sql(self.database().transaction())?;
        self.artifact_project_authorize(&tx, access, ArtifactProjectOperation::Discover)?;
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(artifact_id AS BLOB))<=128 THEN artifact_id ELSE NULL END,CASE WHEN length(CAST(document_id AS BLOB))<=128 THEN document_id ELSE NULL END,CASE WHEN length(CAST(revision AS BLOB))<=20 THEN revision ELSE NULL END FROM artifact_heads WHERE project_id=? AND artifact_id>? ORDER BY artifact_id LIMIT ?", &[access.project_id()?, after.unwrap_or(""), &limit.to_string()]))?;
        let mut entries = Vec::new();
        for row in rows {
            let id = cell(&row, 0)?;
            identifier(id)?;
            let document_id = cell(&row, 1)?;
            identifier(document_id)?;
            let revision =
                Revision::parse(cell(&row, 2)?).map_err(|_| ContractError::StorageCorrupt)?;
            // Structural/canonical validation only. Independent project Discover
            // permission above explicitly authorizes this inventory metadata;
            // no synthetic DocumentAccess or widened document grant is created.
            let record =
                self.artifact_record_for_scope(id, &revision, &access.scope, document_id)?;
            entries.push(ArtifactCatalogEntry {
                artifact_id: record.artifact_id,
                revision: record.revision,
                document: record.document.document,
                title: record.document.title,
                human_edited: record.human_edited,
            });
        }
        self.artifact_project_authorize(&tx, access, ArtifactProjectOperation::Discover)?;
        sql(tx.commit())?;
        Ok(entries)
    }
}
