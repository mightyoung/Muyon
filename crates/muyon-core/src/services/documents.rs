use crate::{business::BusinessStore, documents::{DocumentAccess, DocumentMetadata}, evidence::{store::StoredProcessing, EvidenceRef}, services::types::*};
use serde::Serialize;
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct TextResult { pub reference: ResultRef, pub text_digest: Digest, pub normalization_version: String, pub coverage: Coverage }
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ResourceHandle { pub id:String, pub scope:ScopeRef, pub purpose:String, pub expires_at_unix_ms:UnixMs }
pub(super) fn read_error(code:ErrorCode)->ServiceError { ServiceError {code, phase:"document_read".into(),retryability:Retryability::Never,effect_knowledge:EffectKnowledge::NotStarted,original_intent_id:None,safe_message:"资料读取不可用。".into(),details_ref:None} }
pub fn get_metadata(_store:&BusinessStore,_access:&DocumentAccess)->Result<DocumentMetadata,ServiceError> {Err(read_error(ErrorCode::CapabilityUnavailable))}
pub fn describe_processing(_processing:&StoredProcessing)->Result<TextResult,ServiceError> {Err(read_error(ErrorCode::CapabilityUnavailable))}
pub fn read_blocks(_store:&BusinessStore,_access:&DocumentAccess,_processing:&StoredProcessing,_blocks:&[EvidenceRef])->Result<Vec<String>,ServiceError> {Err(read_error(ErrorCode::CapabilityUnavailable))}
