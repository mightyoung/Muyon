//! Sidecar data only. Native format comments/flattening and AI endorsement are not implied.
use super::{identity::valid_id, DocumentAnchor, DocumentMetadata};
use crate::contract::{ContractError, Revision};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum AnnotationAuthor {
    Human { actor_id: String },
    Ai { agent_id: String, run_id: String },
}
impl AnnotationAuthor {
    pub(crate) fn validate(&self) -> Result<(), ContractError> {
        let valid = match self {
            Self::Human { actor_id } => valid_id(actor_id),
            Self::Ai { agent_id, run_id } => valid_id(agent_id) && valid_id(run_id),
        };
        if valid { Ok(()) } else { Err(ContractError::InvalidIdentity) }
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum AnnotationBody {
    Comment { text: String },
    Highlight { quote: String, note: Option<String> },
}
impl AnnotationBody {
    pub(crate) fn validate(&self) -> Result<(), ContractError> {
        let text = |value: &str, limit: usize| {
            if value.trim().is_empty() || value.len() > limit || value.contains('\0') {
                Err(ContractError::InvalidPayload)
            } else { Ok(()) }
        };
        match self {
            Self::Comment { text: value } => text(value, 8192),
            Self::Highlight { quote, note } => {
                text(quote, 16384)?;
                if let Some(note) = note { text(note, 8192)?; }
                Ok(())
            }
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StoredAnchorState { Current, Stale }
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AnnotationRecord {
    pub id: String,
    pub revision: Revision,
    pub anchor: DocumentAnchor,
    pub body: AnnotationBody,
    pub created_by: AnnotationAuthor,
    pub modified_by: AnnotationAuthor,
    pub deleted: bool,
    pub anchor_state: StoredAnchorState,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AnnotationExport {
    pub schema: String,
    pub document: DocumentMetadata,
    /// Stable ID order, including tombstones and explicit stale revision anchors.
    pub annotations: Vec<AnnotationRecord>,
}
