//! Read-only projections of host-loaded suppliers; references grant no authority.
use super::research_projection::{projection_error, unbound, validate_scope, DocumentBindingView};
use crate::{
    business::SupplierRecord,
    contract::Revision,
    documents::DocumentRef,
    services::types::{ErrorCode, ScopeRef, ServiceError},
};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SupplierView {
    pub supplier_id: String,
    pub scope: ScopeRef,
    pub revision: Revision,
    pub name: String,
    pub documents: Vec<DocumentBindingView>,
}

/// The host supplies the supplier's current authorized read scope and current
/// document mappings for this supplier. SupplierRecord itself has no scope or
/// attachment fields: an empty mapping reports binding unavailability only,
/// without asserting that an attachment exists. Paths/digests cannot supply a
/// mapping. This checks consistency; document opening must recheck authority.
pub fn project_supplier(
    supplier: &SupplierRecord,
    scope: &ScopeRef,
    documents: &[DocumentRef],
) -> Result<SupplierView, ServiceError> {
    if supplier.deleted {
        return Err(projection_error(ErrorCode::ResourceExpired));
    }
    validate_scope(scope, documents)?;
    Ok(SupplierView {
        supplier_id: supplier.id.clone(),
        scope: scope.clone(),
        revision: supplier.revision.clone(),
        name: supplier.payload.name.clone(),
        documents: if documents.is_empty() {
            vec![unbound()]
        } else {
            documents
                .iter()
                .cloned()
                .map(DocumentBindingView::Bound)
                .collect()
        },
    })
}
