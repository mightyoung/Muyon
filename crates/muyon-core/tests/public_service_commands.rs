use muyon_core::{
    contract::*,
    services::{
        commands::*,
        types::{EffectKnowledge, IntentId, Retryability},
    },
};
use serde_json::{json, Value};
fn command() -> CommandEnvelope {
    let mut command: CommandEnvelope = serde_json::from_value(json!({
        "protocol_version":1,"business_version":1,"intent_id":"intent:original",
        "scope":{"workspace_id":"w","project_id":null},"expected_revision":"0",
        "authority":{"grant_id":"grant:original","generation":"1","owner_epoch":"epoch:original"},
        "plan_id":"plan:original","plan_digest":"0".repeat(64),
        "command":{"operation":"project_create","project_id":"project:1","name":"Test"}
    }))
    .unwrap();
    command.plan_digest = command.expected_plan_digest().unwrap();
    command
}
fn result(status: ExecutionStatus) -> ExecutionResult {
    ExecutionResult {
        status,
        receipt: None,
        error: None,
        recovery_action: RecoveryAction::QueryOriginal,
    }
}
#[test]
fn lookup_special_case_preserves_identity() {
    let intent = IntentId::parse("intent:original").unwrap();
    let fixture: Value = serde_json::from_str(include_str!(
        "../../../docs/contracts/public-services-v02/fixtures/commands.json"
    ))
    .unwrap();
    for case in fixture["lookup_cases"].as_array().unwrap() {
        let reply = decode_original(case["json"].as_str().unwrap(), &intent);
        assert_eq!(
            reply.is_ok(),
            case["valid"].as_bool().unwrap(),
            "{}",
            case["id"]
        );
        if case["kind"] == "not_submitted" {
            assert!(
                matches!(reply.as_ref().unwrap(),OriginalLookup::NotSubmitted{intent_id} if intent_id==&intent)
            );
        }
        if case["kind"] == "unknown" {
            assert!(
                matches!(reply.as_ref().unwrap(),OriginalLookup::Execution(r) if r.status==ExecutionStatus::Unknown)
            );
        }
    }
}
#[test]
fn pending_and_cancel_are_not_success() {
    let command = command();
    for (status, cancel, expected) in [
        (ExecutionStatus::Pending, false, ReceiptPhase::Accepted),
        (
            ExecutionStatus::Pending,
            true,
            ReceiptPhase::CancelRequested,
        ),
        (
            ExecutionStatus::Unknown,
            false,
            ReceiptPhase::UnknownOutcome,
        ),
        (
            ExecutionStatus::Unknown,
            true,
            ReceiptPhase::CancelRequested,
        ),
    ] {
        let view = project_execution(&command, &result(status), cancel).unwrap();
        assert_eq!(view.phase, expected);
        assert_eq!(view.intent_id.as_str(), command.intent_id);
        assert!(view.receipt.is_none());
        assert_eq!(view.cancellation_requested, cancel);
    }
}
#[test]
fn committed_requires_original_receipt_and_command_binding() {
    let mut command = command();
    let receipt = Receipt {
        protocol_version: 1,
        intent_id: command.intent_id.clone(),
        binding_digest: command.binding_digest().unwrap(),
        scope: command.scope.clone(),
        authority: command.authority.clone(),
        admission_id: None,
        target_id: "project:1".into(),
        revision: Revision::new(1),
        status: ExecutionStatus::Committed,
        result: json!({}),
    };
    let mut result = ExecutionResult {
        status: ExecutionStatus::Committed,
        receipt: Some(receipt),
        error: None,
        recovery_action: RecoveryAction::None,
    };
    assert_eq!(
        project_execution(&command, &result, true).unwrap().phase,
        ReceiptPhase::Succeeded
    );
    command.plan_id = "plan:other".into();
    assert!(project_execution(&command, &result, false).is_err());
    assert!(decode_original(
        &serde_json::to_string(&result).unwrap(),
        &IntentId::parse("intent:other").unwrap()
    )
    .is_err());
    result.receipt = None;
    assert!(project_execution(&command, &result, false).is_err());
}
#[test]
fn terminal_rejection_and_cancel_remain_distinct() {
    let command = command();
    for (status, error, expected) in [
        (
            ExecutionStatus::Rejected,
            ContractError::RevisionConflict,
            ReceiptPhase::Failed,
        ),
        (
            ExecutionStatus::Cancelled,
            ContractError::Cancelled,
            ReceiptPhase::Cancelled,
        ),
    ] {
        let r = ExecutionResult {
            status,
            receipt: None,
            error: Some(error),
            recovery_action: RecoveryAction::None,
        };
        assert_eq!(
            project_execution(&command, &r, true).unwrap().phase,
            expected
        );
    }
}
#[test]
fn unphased_host_errors_never_claim_not_started() {
    let intent = IntentId::parse("intent:original").unwrap();
    let error = unphased_host_error(&intent);
    assert_eq!(error.effect_knowledge, EffectKnowledge::Unknown);
    assert_eq!(error.retryability, Retryability::AfterLookup);
    assert_eq!(error.original_intent_id, Some(intent));
}

#[test]
fn cancel_requested_retains_original_unknown_fact() {
    let command = command();
    let pending = project_execution(&command, &result(ExecutionStatus::Pending), true).unwrap();
    let unknown = project_execution(&command, &result(ExecutionStatus::Unknown), true).unwrap();
    assert_eq!(pending.phase, ReceiptPhase::CancelRequested);
    assert_eq!(unknown.phase, ReceiptPhase::CancelRequested);
    assert_eq!(pending.execution_status, ExecutionStatus::Pending);
    assert_eq!(unknown.execution_status, ExecutionStatus::Unknown);
    assert_ne!(pending, unknown);
}
