// Adapts existing owner results only; never starts processing or issues authority.
use crate::{
    business::BusinessStore,
    contract::{stable_digest, ContractError},
    documents::{DocumentAccess, DocumentMetadata},
    evidence::{
        store::{StoreEvidence, StoreEvidenceError, StoredProcessing},
        EvidenceError, EvidenceRef, InputKind, ProcessingState,
    },
    services::types::*,
};
use serde::Serialize;

pub const NORMALIZATION_VERSION: &str = "utf8-original-v1";
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct TextResult {
    pub reference: ResultRef,
    pub text_digest: Digest,
    pub normalization_version: String,
    /// Complete original UTF-8 bytes, not pages or OCR units.
    pub coverage: Coverage,
}
/// Contract declaration only. This adapter never issues a resource/FD lease.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ResourceHandle {
    pub id: String,
    pub scope: ScopeRef,
    pub purpose: String,
    pub expires_at_unix_ms: UnixMs,
}
pub(super) fn read_error(code: ErrorCode) -> ServiceError {
    ServiceError {
        code,
        // A diagnostic call-site label; not trusted dispatch-stage evidence.
        phase: "document_read".into(),
        retryability: Retryability::Never,
        effect_knowledge: EffectKnowledge::NotStarted,
        original_intent_id: None,
        safe_message: "资料读取不可用。".into(),
        details_ref: None,
    }
}
fn core_error(error: ContractError) -> ServiceError {
    let code = match error {
        ContractError::RevisionConflict => ErrorCode::StaleRevision,
        ContractError::ScopeMismatch => ErrorCode::ScopeChanged,
        ContractError::InvalidAuthority => ErrorCode::PermissionDenied,
        ContractError::Unsupported | ContractError::UnsupportedOperation => {
            ErrorCode::CapabilityUnavailable
        }
        ContractError::NotFound => ErrorCode::ResourceExpired,
        // Owner storage/cleanup errors must not disclose raw database details.
        ContractError::Storage
        | ContractError::StorageBusy
        | ContractError::StorageConstraint
        | ContractError::StorageCorrupt
        | ContractError::StorageIo
        | ContractError::Unknown => ErrorCode::CapabilityUnavailable,
        _ => ErrorCode::InvalidArgument,
    };
    read_error(code)
}
pub(super) fn owner_error(error: StoreEvidenceError) -> ServiceError {
    match error {
        StoreEvidenceError::Core(error) => core_error(error),
        StoreEvidenceError::Processing(error) => read_error(match error {
            EvidenceError::Denied => ErrorCode::PermissionDenied,
            EvidenceError::NotAvailable => ErrorCode::CapabilityUnavailable,
            _ => ErrorCode::InvalidArgument,
        }),
        StoreEvidenceError::Cleanup { .. } => read_error(ErrorCode::CapabilityUnavailable),
    }
}
pub fn get_metadata(
    store: &BusinessStore,
    access: &DocumentAccess,
) -> Result<DocumentMetadata, ServiceError> {
    store.read_document(access).map_err(core_error)
}
/// Historical result metadata; this does not authorize opening its source.
pub fn describe_processing(processing: &StoredProcessing) -> Result<TextResult, ServiceError> {
    let receipt = processing.receipt();
    if receipt.input_kind != InputKind::Utf8Text || receipt.extraction != ProcessingState::Available
    {
        return Err(read_error(ErrorCode::CapabilityUnavailable));
    }
    let text_digest = Digest::parse(&receipt.source.blob.digest)?;
    let parameters = stable_digest(&serde_json::json!({"input_kind": "utf8_text"}))
        .map_err(|_| read_error(ErrorCode::InvalidArgument))?;
    let bytes = receipt.source.blob.byte_length.value();
    Ok(TextResult {
        reference: ResultRef {
            // Legacy deterministic processing identity, never a business Receipt.
            result_id: ResultId::parse(&receipt.receipt_id)?,
            input_document_ref: receipt.source.document.clone(),
            input_result_refs: vec![],
            content_digest: text_digest.clone(),
            producer_version: receipt.processor.into(),
            parameters_digest: Digest::parse(&parameters)?,
        },
        text_digest,
        normalization_version: NORMALIZATION_VERSION.into(),
        coverage: Coverage {
            state: CoverageState::Complete,
            processed: bytes,
            total: Some(bytes),
            failed_units: vec![],
        },
    })
}
/// Only bounded existing EvidenceRefs; each quote is authorized by the original
/// owner transaction. No arbitrary-range read, batch snapshot, or text cache API.
pub fn read_blocks(
    store: &BusinessStore,
    access: &DocumentAccess,
    processing: &StoredProcessing,
    blocks: &[EvidenceRef],
) -> Result<Vec<String>, ServiceError> {
    describe_processing(processing)?;
    if blocks.is_empty() || blocks.len() > 100 {
        return Err(read_error(ErrorCode::InvalidArgument));
    }
    let owner = StoreEvidence::new(store);
    blocks
        .iter()
        .map(|reference| {
            owner
                .open(access, processing, reference)
                .map_err(owner_error)
        })
        .collect()
}
