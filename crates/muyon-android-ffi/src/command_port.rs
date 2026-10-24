//! Trusted Rust host adapter for the existing ProductCore owner.
//!
//! This capability includes confirmation and cancellation. Keep it in the native
//! host: never register it in model/plugin dispatchers or export it over UniFFI.
//! The host must authorize the current scope, and call `confirm` only from the
//! visible review callback, exactly as for ProductCore::confirm_user_plan.
use crate::ProductCore;
use muyon_core::{
    contract::{CommandEnvelope, ExecutionResult, Operation, Revision},
    services::{
        commands::{
            decode_original, project_execution, unphased_host_error, HostCommandPort,
            OriginalLookup,
        },
        types::{decode_strict, EffectKnowledge, ErrorCode, IntentId, Retryability, ServiceError},
    },
};
use std::sync::Arc;

/// Native-host capability; constructing this does not grant any new authority.
/// It delegates to the original owner's review, intent, grant and receipt state.
pub struct ProductCommandPort {
    owner: Arc<ProductCore>,
}

impl ProductCommandPort {
    /// Only the trusted host may retain this value; review authorization remains
    /// the caller's responsibility, as with the owner's native confirmation API.
    pub fn new(owner: Arc<ProductCore>) -> Self {
        Self { owner }
    }
}

// No original identity is available when prepare's reply is unavailable. In
// particular, never invent an identity or infer that prepare did not persist.
fn unidentified_error() -> ServiceError {
    ServiceError {
        code: ErrorCode::UnknownOutcome,
        phase: "host_call".into(),
        retryability: Retryability::Never,
        effect_knowledge: EffectKnowledge::Unknown,
        original_intent_id: None,
        safe_message: "准备结果未知，请勿重复提交。".into(),
        details_ref: None,
    }
}

fn decode_bound(raw: &str, command: &CommandEnvelope) -> Result<OriginalLookup, ServiceError> {
    let intent = IntentId::parse(&command.intent_id)?;
    let original = decode_original(raw, &intent)?;
    if let OriginalLookup::Execution(result) = &original {
        project_execution(command, result, false)?;
    }
    Ok(original)
}

impl HostCommandPort for ProductCommandPort {
    fn prepare(
        &self,
        operation: Operation,
        project_id: Option<String>,
        expected_revision: Revision,
    ) -> Result<CommandEnvelope, ServiceError> {
        let raw = self
            .owner
            .prepare(
                serde_json::to_string(&operation).map_err(|_| unidentified_error())?,
                project_id.clone(),
                expected_revision.as_str().into(),
            )
            .map_err(|_| unidentified_error())?;
        let command: CommandEnvelope = decode_strict(&raw).map_err(|_| unidentified_error())?;
        command.validate().map_err(|_| unidentified_error())?;
        command.binding_digest().map_err(|_| unidentified_error())?;
        if command.command != operation
            || command.scope.project_id != project_id
            || command.scope.workspace_id != self.owner.workspace
            || command.authority.owner_epoch != self.owner.epoch
            || command.expected_revision != expected_revision
        {
            return Err(unidentified_error());
        }
        Ok(command)
    }

    fn confirm(&self, plan_id: &str) -> Result<OriginalLookup, ServiceError> {
        // Read the binding from the original owner rather than maintaining an
        // adapter ledger or accepting a caller-supplied intent/command binding.
        let command = {
            let state = self.owner.state.lock().map_err(|_| unidentified_error())?;
            state.prepared.get(plan_id).map(|p| p.command.clone())
        }
        .ok_or_else(|| ServiceError {
            code: ErrorCode::PermissionDenied,
            phase: "confirm".into(),
            retryability: Retryability::Never,
            effect_knowledge: EffectKnowledge::NotStarted,
            original_intent_id: None,
            safe_message: "原审核计划不可用，请核对原请求。".into(),
            details_ref: None,
        })?;
        let intent = IntentId::parse(&command.intent_id)?;
        let raw = self
            .owner
            .confirm_user_plan(plan_id.into())
            .map_err(|_| unphased_host_error(&intent))?;
        decode_bound(&raw, &command)
    }

    fn lookup_original(&self, intent: &IntentId) -> Result<OriginalLookup, ServiceError> {
        let raw = self
            .owner
            .lookup_original(intent.as_str().into())
            .map_err(|_| unphased_host_error(intent))?;
        decode_original(&raw, intent)
    }

    fn cancel_original(&self, intent: &IntentId) -> Result<ExecutionResult, ServiceError> {
        let raw = self
            .owner
            .cancel_original(intent.as_str().into())
            .map_err(|_| unphased_host_error(intent))?;
        match decode_original(&raw, intent)? {
            OriginalLookup::Execution(result) => Ok(*result),
            OriginalLookup::NotSubmitted { .. } => Err(unphased_host_error(intent)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use muyon_core::contract::ExecutionStatus;
    use std::path::PathBuf;

    struct Fixture {
        root: PathBuf,
    }
    impl Fixture {
        fn new() -> Self {
            Self {
                root: std::env::temp_dir()
                    .join(crate::opaque_id("command-port").unwrap().replace(':', "-")),
            }
        }
        fn open(&self, epoch: &str, initialize: bool) -> Arc<ProductCore> {
            ProductCore::open(
                self.root.to_str().unwrap().into(),
                "workspace".into(),
                epoch.into(),
                initialize,
            )
            .unwrap()
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.root);
        }
    }
    fn prepare(port: &ProductCommandPort) -> CommandEnvelope {
        port.prepare(
            Operation::ProjectCreate {
                project_id: "project".into(),
                name: "Project".into(),
            },
            None,
            Revision::new(0),
        )
        .unwrap()
    }

    #[test]
    fn real_owner_confirm_lookup_cancel_and_reopen_preserve_original_receipt() {
        let fixture = Fixture::new();
        let owner = fixture.open("epoch-1", true);
        let port = ProductCommandPort::new(owner.clone());
        let command = prepare(&port);
        let intent = IntentId::parse(&command.intent_id).unwrap();
        let confirmed = port.confirm(&command.plan_id).unwrap();
        let OriginalLookup::Execution(result) = &confirmed else {
            panic!("missing execution")
        };
        assert_eq!(result.status, ExecutionStatus::Committed);
        result
            .receipt
            .as_ref()
            .unwrap()
            .validate_for(&command)
            .unwrap();
        assert_eq!(port.lookup_original(&intent).unwrap(), confirmed);
        assert_eq!(port.confirm(&command.plan_id).unwrap(), confirmed);
        assert_eq!(port.cancel_original(&intent).unwrap(), **result);
        drop(port);
        drop(owner);
        let reopened = ProductCommandPort::new(fixture.open("epoch-2", false));
        assert_eq!(reopened.lookup_original(&intent).unwrap(), confirmed);
        // A restart recovers the original result, never dispatches the old plan.
        assert_eq!(
            reopened.confirm(&command.plan_id).unwrap_err().code,
            ErrorCode::PermissionDenied
        );
    }

    #[test]
    fn lost_confirmation_is_sealed_and_cannot_be_replayed() {
        let fixture = Fixture::new();
        let port = ProductCommandPort::new(fixture.open("epoch-1", true));
        let command = prepare(&port);
        let intent = IntentId::parse(&command.intent_id).unwrap();
        drop(port);
        let owner = fixture.open("epoch-2", false);
        let port = ProductCommandPort::new(owner.clone());
        assert_eq!(
            port.lookup_original(&intent).unwrap(),
            OriginalLookup::NotSubmitted {
                intent_id: intent.clone()
            }
        );
        assert_eq!(
            port.confirm(&command.plan_id).unwrap_err().retryability,
            Retryability::Never
        );
        assert_eq!(
            port.lookup_original(&intent).unwrap(),
            OriginalLookup::NotSubmitted { intent_id: intent }
        );
        assert!(owner
            .state
            .lock()
            .unwrap()
            .store
            .projects(10, 0)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn lost_prepare_reply_does_not_dispatch_or_issue_another_identity() {
        let fixture = Fixture::new();
        let owner = fixture.open("epoch-1", true);
        let port = ProductCommandPort::new(owner.clone());
        // The caller receives no usable reply. Inspect only the real owner's
        // existing state as a test fixture; the adapter has no recovery ledger.
        drop(prepare(&port));
        let intent = {
            let state = owner.state.lock().unwrap();
            assert_eq!(state.prepared.len(), 1);
            let prepared = state.prepared.values().next().unwrap();
            assert!(!prepared.dispatched);
            IntentId::parse(&prepared.command.intent_id).unwrap()
        };
        drop(port);
        drop(owner);
        let owner = fixture.open("epoch-2", false);
        let port = ProductCommandPort::new(owner.clone());
        assert_eq!(
            port.lookup_original(&intent).unwrap(),
            OriginalLookup::NotSubmitted { intent_id: intent }
        );
        let state = owner.state.lock().unwrap();
        assert!(state.prepared.is_empty());
        assert!(state.store.projects(10, 0).unwrap().is_empty());
    }

    #[test]
    fn preparation_failure_and_unknown_plan_never_retry_or_dispatch() {
        let fixture = Fixture::new();
        let owner = fixture.open("epoch-1", true);
        let port = ProductCommandPort::new(owner.clone());
        let error = port
            .prepare(
                Operation::ProjectCreate {
                    project_id: "".into(),
                    name: "Project".into(),
                },
                None,
                Revision::new(0),
            )
            .unwrap_err();
        assert_eq!(error.effect_knowledge, EffectKnowledge::Unknown);
        assert_eq!(error.retryability, Retryability::Never);
        assert_eq!(error.original_intent_id, None);
        assert_eq!(
            port.confirm("unknown-plan").unwrap_err().code,
            ErrorCode::PermissionDenied
        );
        assert!(owner.state.lock().unwrap().prepared.is_empty());
    }

    #[test]
    fn real_receipt_wrong_intent_scope_and_operation_bindings_are_rejected() {
        let fixture = Fixture::new();
        let owner = fixture.open("epoch-1", true);
        let port = ProductCommandPort::new(owner.clone());
        let command = prepare(&port);
        // Simulate an unavailable confirmation reply: recover by original ID.
        let raw = owner.confirm_user_plan(command.plan_id.clone()).unwrap();
        let wrong = IntentId::parse("another-intent").unwrap();
        assert_eq!(
            decode_original(&raw, &wrong).unwrap_err().code,
            ErrorCode::UnknownOutcome
        );
        let mut other = command.clone();
        other.scope.project_id = Some("other-project".into());
        assert!(decode_bound(&raw, &other).is_err());
        let mut other = command.clone();
        other.command = Operation::ProjectCreate {
            project_id: "other-project".into(),
            name: "Other".into(),
        };
        assert!(decode_bound(&raw, &other).is_err());
        assert_eq!(
            port.lookup_original(&IntentId::parse(&command.intent_id).unwrap())
                .unwrap(),
            decode_bound(&raw, &command).unwrap()
        );
    }
}
