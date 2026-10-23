use crate::{contract::Revision, documents::DocumentRef, services::types::*};
use serde::Serialize;
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PipelineStage {
    Parse,
    Ocr,
    Embedding,
    Index,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum JobPhase {
    Accepted,
    Running,
    Succeeded,
    Failed,
    UnknownOutcome,
    CancelRequested,
    Cancelled,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct JobSnapshot {
    pub job_id: JobId,
    pub original_intent_id: IntentId,
    pub scope: ScopeRef,
    pub stage: PipelineStage,
    pub attempt: u32,
    pub phase: JobPhase,
    pub coverage: Coverage,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct VectorDescriptor {
    pub model_version: String,
    pub tokenizer_version: String,
    pub dimensions: u32,
    pub chunk_version: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct EmbeddingResult {
    pub reference: ResultRef,
    pub descriptor: VectorDescriptor,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct IndexSnapshotRef {
    pub snapshot_id: String,
    pub scope: ScopeRef,
    pub revision: Revision,
    pub inputs: Vec<ResultId>,
    pub descriptor: VectorDescriptor,
}
fn failure(code: ErrorCode) -> ServiceError {
    ServiceError {
        code,
        phase: "pipeline_validate".into(),
        retryability: Retryability::Never,
        effect_knowledge: EffectKnowledge::NotStarted,
        original_intent_id: None,
        safe_message: "资料处理来源不匹配。".into(),
        details_ref: None,
    }
}
/// Pure CAS precondition only. A caller must publish under the existing owner's
/// lock/transaction; this function cannot atomically update a current pointer.
pub fn can_publish_head(
    expected: &DocumentRef,
    current: &DocumentRef,
    expected_generation: &Revision,
    current_generation: &Revision,
) -> Result<(), ServiceError> {
    if expected.scope() != current.scope() || expected_generation != current_generation {
        return Err(failure(ErrorCode::ScopeChanged));
    }
    if expected != current {
        return Err(failure(ErrorCode::StaleRevision));
    }
    Ok(())
}
/// Validates a declared snapshot against the already authorized query descriptor
/// and exact direct input set. It never embeds a query or starts an index build.
/// ResultRef carries document scope, not account/generation authority; the trusted
/// owner must resolve those separately before delivery and again on source open.
pub fn validate_search(
    snapshot: &IndexSnapshotRef,
    query_descriptor: &VectorDescriptor,
    inputs: &[ResultRef],
) -> Result<(), ServiceError> {
    let d = &snapshot.descriptor;
    if d != query_descriptor
        || d.dimensions == 0
        || [&d.model_version, &d.tokenizer_version, &d.chunk_version]
            .iter()
            .any(|v| v.trim().is_empty())
        || ResultId::parse(&snapshot.snapshot_id).is_err()
    {
        return Err(failure(ErrorCode::InvalidArgument));
    }
    if inputs
        .iter()
        .any(|v| v.input_document_ref.scope() != &snapshot.scope.scope)
    {
        return Err(failure(ErrorCode::ScopeChanged));
    }
    let declared: std::collections::BTreeSet<_> =
        snapshot.inputs.iter().map(ResultId::as_str).collect();
    let supplied: std::collections::BTreeSet<_> =
        inputs.iter().map(|r| r.result_id.as_str()).collect();
    if declared.len() != snapshot.inputs.len()
        || supplied.len() != inputs.len()
        || declared != supplied
    {
        return Err(failure(ErrorCode::InvalidArgument));
    }
    Ok(())
}
/// Projection accessor only: consume a snapshot obtained from the trusted task
/// owner. Wire JobSnapshot fields never authorize HostCommandPort cancellation.
/// No task ledger, dispatch, attempt increment, or state transition is performed.
pub fn cancellation_target(job: &JobSnapshot) -> IntentId {
    job.original_intent_id.clone()
}

/// Stronger preflight for an index/search owner that has resolved actual
/// embedding results. This is still validation, not query execution/authority.
pub fn validate_embedding_search(
    snapshot: &IndexSnapshotRef,
    query_descriptor: &VectorDescriptor,
    inputs: &[EmbeddingResult],
) -> Result<(), ServiceError> {
    let references: Vec<_> = inputs.iter().map(|input| input.reference.clone()).collect();
    validate_search(snapshot, query_descriptor, &references)
}
