use crate::{contract::Revision, documents::DocumentRef, services::types::*};
use serde::Serialize;
#[derive(Clone,Debug,PartialEq,Eq,Serialize)]
#[serde(rename_all="snake_case")]
pub enum PipelineStage {Parse,Ocr,Embedding,Index}
#[derive(Clone,Debug,PartialEq,Eq,Serialize)]
#[serde(rename_all="snake_case")]
pub enum JobPhase {Accepted,Running,Succeeded,Failed,UnknownOutcome,CancelRequested,Cancelled}
#[derive(Clone,Debug,PartialEq,Eq,Serialize)]
pub struct JobSnapshot {pub job_id:JobId,pub original_intent_id:IntentId,pub scope:ScopeRef,pub stage:PipelineStage,pub attempt:u32,pub phase:JobPhase,pub coverage:Coverage}
#[derive(Clone,Debug,PartialEq,Eq,Serialize)]
pub struct VectorDescriptor {pub model_version:String,pub tokenizer_version:String,pub dimensions:u32,pub chunk_version:String}
#[derive(Clone,Debug,PartialEq,Eq,Serialize)]
pub struct EmbeddingResult {pub reference:ResultRef,pub descriptor:VectorDescriptor}
#[derive(Clone,Debug,PartialEq,Eq,Serialize)]
pub struct IndexSnapshotRef {pub snapshot_id:String,pub scope:ScopeRef,pub revision:Revision,pub inputs:Vec<ResultId>,pub descriptor:VectorDescriptor}
fn failure(code:ErrorCode)->ServiceError {ServiceError {code,phase:"pipeline_validate".into(),retryability:Retryability::Never,effect_knowledge:EffectKnowledge::NotStarted,original_intent_id:None,safe_message:"资料处理来源不匹配。".into(),details_ref:None}}
pub fn can_publish_head(_expected:&DocumentRef,_current:&DocumentRef,_expected_generation:&Revision,_current_generation:&Revision)->Result<(),ServiceError> {Err(failure(ErrorCode::CapabilityUnavailable))}
pub fn validate_search(_snapshot:&IndexSnapshotRef,_query_descriptor:&VectorDescriptor,_inputs:&[ResultRef])->Result<(),ServiceError> {Err(failure(ErrorCode::CapabilityUnavailable))}
pub fn cancellation_target(_job:&JobSnapshot)->IntentId {IntentId::parse("unavailable").unwrap()}
