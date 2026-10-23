use super::documents::{describe_processing, owner_error, read_error};
use crate::{
    business::BusinessStore,
    documents::{DocumentAccess, DocumentRef},
    evidence::{
        store::{StoreEvidence, StoredProcessing},
        EvidenceRef,
    },
    services::types::*,
};
use serde::Serialize;
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SourceLocator {
    pub text_result_ref: ResultId,
    pub text_digest: Digest,
    pub normalization_version: String,
    pub evidence: EvidenceRef,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct OpenedSource {
    pub document: DocumentRef,
    pub locator: SourceLocator,
    pub quote: String,
}
/// Metadata binding only. Forged ranges/identifiers are rejected by owner.open;
/// a locator is not a permission token or proof that the quote remains available.
pub fn source_locator(
    processing: &StoredProcessing,
    evidence: &EvidenceRef,
) -> Result<SourceLocator, ServiceError> {
    let result = describe_processing(processing)?;
    if evidence.source != processing.receipt().source
        || evidence.source_id != processing.receipt().source_id
    {
        return Err(read_error(ErrorCode::InvalidArgument));
    }
    Ok(SourceLocator {
        text_result_ref: result.reference.result_id,
        text_digest: result.text_digest,
        normalization_version: result.normalization_version,
        evidence: evidence.clone(),
    })
}
pub fn resolve_anchor(
    store: &BusinessStore,
    access: &DocumentAccess,
    processing: &StoredProcessing,
    locator: &SourceLocator,
) -> Result<OpenedSource, ServiceError> {
    let expected = source_locator(processing, &locator.evidence)?;
    if *locator != expected {
        return Err(read_error(ErrorCode::InvalidArgument));
    }
    let quote = StoreEvidence::new(store)
        .open(access, processing, &locator.evidence)
        .map_err(owner_error)?;
    Ok(OpenedSource {
        document: processing.receipt().source.document.clone(),
        locator: locator.clone(),
        quote,
    })
}
