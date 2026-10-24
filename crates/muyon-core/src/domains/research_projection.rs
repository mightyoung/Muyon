//! Read-only projections of host-loaded research records; references grant no authority.
use crate::{
    contract::Revision,
    documents::DocumentRef,
    research::PaperRecord,
    services::types::{EffectKnowledge, ErrorCode, Retryability, ScopeRef, ServiceError},
};
use serde::{Deserialize, Serialize};

/// Public binding availability only. `Unbound` makes no claim about reading a file.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum DocumentBindingView {
    Bound(DocumentRef),
    Unbound { reason: String },
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResearchView {
    pub paper_id: String,
    pub project_id: String,
    pub revision: Revision,
    pub title: String,
    pub documents: Vec<DocumentBindingView>,
}

/// `paper` and `scope` must come from the trusted host's current authorized read.
/// `documents` must be that host's current mappings for this paper, never inferred
/// from paths or blob digests. This checks scope consistency, not authority or
/// mapping provenance; opening a reference still requires document-service checks.
pub fn project_paper(
    paper: &PaperRecord,
    scope: &ScopeRef,
    documents: &[DocumentRef],
) -> Result<ResearchView, ServiceError> {
    validate_scope(scope, documents)?;
    if scope.scope.project_id.as_deref() != Some(paper.project_id.as_str()) {
        return Err(projection_error(ErrorCode::ScopeChanged));
    }
    let bindings = if documents.is_empty() {
        paper.attachments.iter().map(|_| unbound()).collect()
    } else {
        documents
            .iter()
            .cloned()
            .map(DocumentBindingView::Bound)
            .collect()
    };
    Ok(ResearchView {
        paper_id: paper.id.clone(),
        project_id: paper.project_id.clone(),
        revision: paper.revision.clone(),
        title: paper.title.clone(),
        documents: bindings,
    })
}

pub(super) fn unbound() -> DocumentBindingView {
    DocumentBindingView::Unbound {
        reason: "document_binding_unavailable".into(),
    }
}
pub(super) fn validate_scope(
    scope: &ScopeRef,
    documents: &[DocumentRef],
) -> Result<(), ServiceError> {
    // Reuse the document identity constructor's exact scope validation rules.
    crate::documents::DocumentRef::new(
        scope.scope.clone(),
        "projection-scope-check",
        Revision::new(0),
        crate::documents::DocumentFormat::Pdf,
    )
    .map_err(|_| projection_error(ErrorCode::InvalidArgument))?;
    if documents
        .iter()
        .any(|document| document.scope() != &scope.scope)
    {
        return Err(projection_error(ErrorCode::ScopeChanged));
    }
    Ok(())
}
pub(super) fn projection_error(code: ErrorCode) -> ServiceError {
    ServiceError {
        code,
        phase: "domain_projection".into(),
        retryability: Retryability::Never,
        effect_knowledge: EffectKnowledge::NotStarted,
        original_intent_id: None,
        safe_message: "Domain projection unavailable.".into(),
        details_ref: None,
    }
}
