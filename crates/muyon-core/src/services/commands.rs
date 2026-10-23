//! Original owner projections only. No dispatch, identity issuance or retry loop.
use super::types::*;
use crate::contract::{
    CommandEnvelope, ExecutionResult, ExecutionStatus, Operation, Receipt, Revision,
};
#[derive(Clone, Debug, PartialEq)]
pub enum OriginalLookup {
    Execution(Box<ExecutionResult>),
    NotSubmitted { intent_id: IntentId },
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ReceiptPhase {
    WaitingForConfirmation,
    Accepted,
    Running,
    Succeeded,
    Failed,
    UnknownOutcome,
    CancelRequested,
    Cancelled,
}
#[derive(Clone, Debug, PartialEq)]
pub struct ReceiptView {
    pub execution_status: ExecutionStatus,
    pub intent_id: IntentId,
    pub phase: ReceiptPhase,
    pub receipt: Option<Receipt>,
    pub cancellation_requested: bool,
}
pub trait HostCommandPort {
    fn prepare(
        &self,
        operation: Operation,
        project_id: Option<String>,
        expected_revision: Revision,
    ) -> Result<CommandEnvelope, ServiceError>;
    fn confirm(&self, plan_id: &str) -> Result<OriginalLookup, ServiceError>;
    fn lookup_original(&self, intent_id: &IntentId) -> Result<OriginalLookup, ServiceError>;
    fn cancel_original(&self, intent_id: &IntentId) -> Result<ExecutionResult, ServiceError>;
}
pub fn decode_original(raw: &str, expected: &IntentId) -> Result<OriginalLookup, ServiceError> {
    let value: serde_json::Value = decode_strict(raw).map_err(|_| unphased_host_error(expected))?;
    if value.get("status").and_then(|s| s.as_str()) == Some("not_submitted") {
        let fields = value
            .as_object()
            .ok_or_else(|| unphased_host_error(expected))?;
        if fields.len() != 4
            || fields.get("receipt") != Some(&serde_json::Value::Null)
            || fields.get("error").and_then(|v| v.as_str()) != Some("confirmation_not_received")
            || fields.get("recovery_action").and_then(|v| v.as_str()) != Some("edit_new_draft")
        {
            return Err(unphased_host_error(expected));
        }
        return Ok(OriginalLookup::NotSubmitted {
            intent_id: expected.clone(),
        });
    }
    let result: ExecutionResult =
        serde_json::from_value(value).map_err(|_| unphased_host_error(expected))?;
    result
        .validate()
        .map_err(|_| unphased_host_error(expected))?;
    if result
        .receipt
        .as_ref()
        .is_some_and(|r| r.intent_id != expected.as_str())
    {
        return Err(unphased_host_error(expected));
    }
    Ok(OriginalLookup::Execution(Box::new(result)))
}
pub fn project_execution(
    command: &CommandEnvelope,
    result: &ExecutionResult,
    cancellation_requested: bool,
) -> Result<ReceiptView, ServiceError> {
    let intent = IntentId::parse(&command.intent_id)?;
    command
        .binding_digest()
        .map_err(|_| unphased_host_error(&intent))?;
    result
        .validate()
        .map_err(|_| unphased_host_error(&intent))?;
    let phase = match result.status {
        ExecutionStatus::Pending if cancellation_requested => ReceiptPhase::CancelRequested,
        ExecutionStatus::Pending => ReceiptPhase::Accepted,
        ExecutionStatus::Unknown if cancellation_requested => ReceiptPhase::CancelRequested,
        ExecutionStatus::Unknown => ReceiptPhase::UnknownOutcome,
        ExecutionStatus::Rejected => ReceiptPhase::Failed,
        ExecutionStatus::Cancelled => ReceiptPhase::Cancelled,
        ExecutionStatus::Committed => {
            result
                .receipt
                .as_ref()
                .ok_or_else(|| unphased_host_error(&intent))?
                .validate_for(command)
                .map_err(|_| unphased_host_error(&intent))?;
            ReceiptPhase::Succeeded
        }
    };
    Ok(ReceiptView {
        execution_status: result.status.clone(),
        intent_id: intent,
        phase,
        receipt: result.receipt.clone(),
        cancellation_requested,
    })
}
/// Use when a host/IPC error supplies no trusted proof that dispatch did not occur.
/// The call-site label does not establish an execution stage.
pub fn unphased_host_error(intent: &IntentId) -> ServiceError {
    ServiceError {
        code: ErrorCode::UnknownOutcome,
        phase: "host_call".into(),
        retryability: Retryability::AfterLookup,
        effect_knowledge: EffectKnowledge::Unknown,
        original_intent_id: Some(intent.clone()),
        safe_message: "结果未知，请核对原请求。".into(),
        details_ref: None,
    }
}
