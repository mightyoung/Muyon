use super::documents::read_error;
use crate::{business::BusinessStore, documents::{DocumentAccess,DocumentRef}, evidence::{store::StoredProcessing,EvidenceRef}, services::types::*};
use serde::Serialize;
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SourceLocator { pub text_result_ref:ResultId,pub text_digest:Digest,pub normalization_version:String,pub evidence:EvidenceRef }
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct OpenedSource {pub document:DocumentRef,pub locator:SourceLocator,pub quote:String}
pub fn source_locator(_processing:&StoredProcessing,_evidence:&EvidenceRef)->Result<SourceLocator,ServiceError> {Err(read_error(ErrorCode::CapabilityUnavailable))}
pub fn resolve_anchor(_store:&BusinessStore,_access:&DocumentAccess,_processing:&StoredProcessing,_locator:&SourceLocator)->Result<OpenedSource,ServiceError> {Err(read_error(ErrorCode::CapabilityUnavailable))}
