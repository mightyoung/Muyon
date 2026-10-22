//! Immutable metadata. These values are never proof of host authority.
use crate::contract::{Revision, Scope};
use super::{DocumentFormat, ReadInvalidation};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DocumentRef {
    scope: Scope,
    document_id: String,
    revision: Revision,
    format: DocumentFormat,
}
impl DocumentRef {
    pub fn new(scope: Scope, document_id: &str, revision: Revision, format: DocumentFormat) -> Result<Self, ReadInvalidation> {
        if !valid_id(&scope.workspace_id)
            || scope.project_id.as_deref().is_some_and(|s| !valid_id(s))
            || !valid_id(document_id)
        {
            return Err(ReadInvalidation::InvalidIdentity);
        }
        Ok(Self { scope, document_id: document_id.into(), revision, format })
    }
    pub fn scope(&self) -> &Scope { &self.scope }
    pub fn document_id(&self) -> &str { &self.document_id }
    pub fn revision(&self) -> &Revision { &self.revision }
    pub fn format(&self) -> DocumentFormat { self.format }
    pub(crate) fn matches(&self, current: &Self) -> Result<(), ReadInvalidation> {
        if self.scope != current.scope { return Err(ReadInvalidation::ScopeMismatch); }
        if self.document_id != current.document_id { return Err(ReadInvalidation::DocumentMismatch); }
        if self.revision != current.revision { return Err(ReadInvalidation::StaleRevision); }
        if self.format != current.format { return Err(ReadInvalidation::FormatMismatch); }
        Ok(())
    }
}

/// Same restricted opaque-ID alphabet as the existing owner contracts. No paths.
pub(crate) fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 128 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
}
