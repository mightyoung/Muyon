//! Native host service joining development drafts to their real storage and owner.
//! Not a model tool or UniFFI dispatcher. The host derives current ScopeRef, drops
//! the session on account/scope-generation changes, and invokes confirm only from
//! a visible review action. Requirements and bugs remain draft-only.
use crate::{command_port::ProductCommandPort, ProductCore, ProductError};
use muyon_core::{
    agent::ReadScope,
    contract::{stable_digest, CommandEnvelope, ContractError, Revision},
    development_drafts::{ConversationDraft, DraftPatch, OWNER_PLUGIN_ID},
    services::{
        commands::{project_execution, HostCommandPort, OriginalLookup},
        draft_store::DraftStore,
        drafts::DraftRef,
        types::{IntentId, ScopeRef},
    },
};
use std::{path::PathBuf, sync::Arc};

pub struct DevelopmentSession {
    owner: Arc<ProductCore>,
    store: DraftStore,
    draft: ConversationDraft,
}

pub(crate) fn scope_path(owner: &ProductCore, scope: &ScopeRef) -> Result<PathBuf, ProductError> {
    if scope.scope.workspace_id != owner.workspace {
        return Err(ContractError::ScopeMismatch.into());
    }
    let state = owner.state.lock().map_err(|_| crate::unavailable())?;
    ReadScope::current(&state.store, scope.scope.project_id.as_deref())?;
    let digest =
        stable_digest(&serde_json::to_value(scope).map_err(|_| ContractError::InvalidPayload)?)?;
    Ok(owner
        .agent_path
        .parent()
        .ok_or_else(crate::unavailable)?
        .join(format!("plugin-drafts-v1-{digest}.sqlite")))
}

impl DevelopmentSession {
    /// Explicit namespace creation, called by the host as part of a new draft
    /// action. Restore never initializes storage or replaces an existing file.
    pub fn initialize_namespace(owner: &ProductCore, scope: &ScopeRef) -> Result<(), ProductError> {
        DraftStore::initialize(&scope_path(owner, scope)?, scope)?;
        Ok(())
    }

    pub fn create(
        owner: Arc<ProductCore>,
        scope: ScopeRef,
        draft_id: String,
        conversation_id: String,
        save_intent: &IntentId,
    ) -> Result<Self, ProductError> {
        let store = DraftStore::open_existing(&scope_path(&owner, &scope)?, &scope)?;
        if store.load(OWNER_PLUGIN_ID, &draft_id)?.is_some() {
            return Err(ContractError::IntentConflict.into());
        }
        let mut draft = ConversationDraft::new(
            DraftRef {
                owner_plugin_id: OWNER_PLUGIN_ID.into(),
                draft_id,
                scope,
                revision: Revision::new(0),
            },
            conversation_id,
        )?;
        draft.persist(&store, save_intent)?;
        Ok(Self {
            owner,
            store,
            draft,
        })
    }

    pub fn restore(
        owner: Arc<ProductCore>,
        scope: ScopeRef,
        draft_id: &str,
    ) -> Result<Self, ProductError> {
        let store = DraftStore::open_existing(&scope_path(&owner, &scope)?, &scope)?;
        let draft =
            ConversationDraft::load_persisted(&store, draft_id)?.ok_or(ContractError::NotFound)?;
        Ok(Self {
            owner,
            store,
            draft,
        })
    }

    pub fn draft(&self) -> &ConversationDraft {
        &self.draft
    }
    pub fn apply_patch(
        &mut self,
        expected: &Revision,
        patch: DraftPatch,
        manual: bool,
    ) -> Result<(), ProductError> {
        self.draft.apply(expected, patch, manual)?;
        Ok(())
    }

    pub fn choose_project(
        &mut self,
        expected: &Revision,
        project_id: String,
        new: bool,
    ) -> Result<(), ProductError> {
        self.draft.choose_project(expected, project_id, new)?;
        Ok(())
    }

    pub fn save(&mut self, intent: &IntentId) -> Result<(), ProductError> {
        self.draft.persist(&self.store, intent)?;
        Ok(())
    }

    /// Accept only the real owner's exact prepared envelope. This cannot create
    /// a new operation, grant or plan from model-generated JSON.
    pub fn review_prepared(
        &mut self,
        command: CommandEnvelope,
        save_intent: &IntentId,
    ) -> Result<(), ProductError> {
        {
            let state = self.owner.state.lock().map_err(|_| crate::unavailable())?;
            if !state
                .prepared
                .get(&command.plan_id)
                .is_some_and(|prepared| !prepared.dispatched && prepared.command == command)
            {
                return Err(ContractError::BindingMismatch.into());
            }
        }
        let mut draft = self.draft.clone();
        draft.prepare_project(&draft.revision().clone(), command)?;
        draft.persist(&self.store, save_intent)?;
        self.draft = draft;
        Ok(())
    }

    /// HOST ONLY: visible user review callback. Persisting the marker precedes
    /// original-owner confirmation; any repeated/restored marker is query-only.
    pub fn confirm_visible(
        &mut self,
        marker_intent: &IntentId,
        result_save_intent: &IntentId,
    ) -> Result<OriginalLookup, ProductError> {
        let original = self
            .draft
            .project_command()
            .ok_or(ContractError::Required)?;
        let may_confirm = {
            let state = self.owner.state.lock().map_err(|_| crate::unavailable())?;
            match state.prepared.get(&original.plan_id) {
                Some(prepared) if &prepared.command != original => {
                    return Err(ContractError::BindingMismatch.into());
                }
                Some(prepared) => !prepared.dispatched,
                None => false,
            }
        };
        if !may_confirm {
            return self.recover_original();
        }
        let command = match self
            .draft
            .begin_persisted_project_dispatch(&self.store, marker_intent)
        {
            Ok(command) => command,
            Err(ContractError::IntentConflict) => return self.recover_original(),
            Err(error) => return Err(error.into()),
        };
        let port = ProductCommandPort::new(self.owner.clone());
        let lookup = port
            .confirm(&command.plan_id)
            .map_err(|_| ProductError::Failure {
                code: "development_original_unknown".into(),
            })?;
        if let OriginalLookup::Execution(result) = &lookup {
            project_execution(&command, result, false)
                .map_err(|_| ContractError::BindingMismatch)?;
            let mut updated = self.draft.clone();
            updated.observe_project_result((**result).clone())?;
            updated.persist(&self.store, result_save_intent)?;
            self.draft = updated;
        }
        Ok(lookup)
    }

    /// Query-only, including NotSubmitted after a lost confirmation. The host
    /// retains that distinction instead of pretending cancellation or success.
    pub fn recover_original(&self) -> Result<OriginalLookup, ProductError> {
        let command = self
            .draft
            .project_command()
            .ok_or(ContractError::Required)?;
        let intent =
            IntentId::parse(&command.intent_id).map_err(|_| ContractError::InvalidIdentity)?;
        let lookup = ProductCommandPort::new(self.owner.clone())
            .lookup_original(&intent)
            .map_err(|_| ProductError::Failure {
                code: "development_original_unknown".into(),
            })?;
        if let OriginalLookup::Execution(result) = &lookup {
            project_execution(command, result, false)
                .map_err(|_| ContractError::BindingMismatch)?;
        }
        Ok(lookup)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use muyon_core::{
        contract::{ExecutionStatus, Operation},
        development_drafts::DraftPatch,
    };
    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            Self(std::env::temp_dir().join(crate::opaque_id("dm-host").unwrap()))
        }
        fn owner(&self, epoch: &str, initialize: bool) -> Arc<ProductCore> {
            ProductCore::open(
                self.0.to_str().unwrap().into(),
                "workspace".into(),
                epoch.into(),
                initialize,
            )
            .unwrap()
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    fn scope() -> ScopeRef {
        ScopeRef {
            scope: muyon_core::contract::Scope {
                workspace_id: "workspace".into(),
                project_id: None,
            },
            account_id: None,
            scope_generation: Revision::new(1),
        }
    }
    fn save(id: &str) -> IntentId {
        IntentId::parse(id).unwrap()
    }
    fn ready(owner: Arc<ProductCore>) -> DevelopmentSession {
        DevelopmentSession::initialize_namespace(&owner, &scope()).unwrap();
        let mut session = DevelopmentSession::create(
            owner.clone(),
            scope(),
            "draft".into(),
            "conversation".into(),
            &save("save:create"),
        )
        .unwrap();
        session
            .apply_patch(
                &session.draft().revision().clone(),
                DraftPatch {
                    project_name: Some("Project".into()),
                    items: vec![],
                },
                true,
            )
            .unwrap();
        session
            .choose_project(&session.draft().revision().clone(), "project".into(), true)
            .unwrap();
        let command = ProductCommandPort::new(owner)
            .prepare(
                Operation::ProjectCreate {
                    project_id: "project".into(),
                    name: "Project".into(),
                },
                None,
                Revision::new(0),
            )
            .unwrap();
        session
            .review_prepared(command, &save("save:review"))
            .unwrap();
        session
    }
    #[test]
    fn durable_draft_real_owner_confirmation_and_restart_share_one_original() {
        let f = Fixture::new();
        let owner = f.owner("epoch-1", true);
        let mut s = ready(owner.clone());
        let original = s.draft().project_command().unwrap().clone();
        let result = s
            .confirm_visible(&save("save:marker"), &save("save:result"))
            .unwrap();
        let OriginalLookup::Execution(ref execution) = result else {
            panic!("missing execution")
        };
        assert_eq!(execution.status, ExecutionStatus::Committed);
        assert_eq!(
            s.confirm_visible(&save("save:again"), &save("save:again-result"))
                .unwrap(),
            result
        );
        drop(s);
        drop(owner);
        let owner = f.owner("epoch-2", false);
        let mut restored = DevelopmentSession::restore(owner.clone(), scope(), "draft").unwrap();
        assert_eq!(restored.draft().project_command(), Some(&original));
        assert_eq!(
            restored
                .confirm_visible(&save("save:restart"), &save("save:restart-result"))
                .unwrap(),
            result
        );
        assert_eq!(
            owner
                .state
                .lock()
                .unwrap()
                .store
                .projects(10, 0)
                .unwrap()
                .len(),
            1
        );
    }
    #[test]
    fn crash_between_marker_and_confirmation_queries_not_submitted() {
        let f = Fixture::new();
        let owner = f.owner("epoch-1", true);
        let mut s = ready(owner.clone());
        let command = s
            .draft
            .begin_persisted_project_dispatch(&s.store, &save("save:marker"))
            .unwrap();
        drop(s);
        drop(owner);
        let owner = f.owner("epoch-2", false);
        let mut restored = DevelopmentSession::restore(owner.clone(), scope(), "draft").unwrap();
        assert_eq!(
            restored
                .confirm_visible(&save("save:restart"), &save("save:restart-result"))
                .unwrap(),
            OriginalLookup::NotSubmitted {
                intent_id: IntentId::parse(&command.intent_id).unwrap()
            }
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
    fn stale_editor_cannot_confirm_a_marker_saved_by_another_session() {
        let f = Fixture::new();
        let owner = f.owner("epoch-1", true);
        let mut first = ready(owner.clone());
        let mut stale = DevelopmentSession::restore(owner.clone(), scope(), "draft").unwrap();
        let expected = first
            .confirm_visible(&save("save:marker"), &save("save:result"))
            .unwrap();
        assert_eq!(
            stale
                .confirm_visible(&save("save:marker"), &save("save:stale-result"))
                .unwrap(),
            expected
        );
        assert_eq!(
            owner
                .state
                .lock()
                .unwrap()
                .store
                .projects(10, 0)
                .unwrap()
                .len(),
            1
        );
    }
    #[test]
    fn restore_is_read_only_and_wrong_scope_or_forged_plan_is_rejected() {
        let f = Fixture::new();
        let owner = f.owner("epoch-1", true);
        assert!(DevelopmentSession::restore(owner.clone(), scope(), "draft").is_err());
        let mut s = ready(owner.clone());
        let mut wrong = scope();
        wrong.scope.workspace_id = "other".into();
        assert!(DevelopmentSession::restore(owner, wrong, "draft").is_err());
        let mut forged = s.draft().project_command().unwrap().clone();
        forged.plan_id = "forged".into();
        assert!(s.review_prepared(forged, &save("save:forged")).is_err());
    }
    #[test]
    fn valid_but_different_stored_command_is_rejected_before_any_effect() {
        let f = Fixture::new();
        let owner = f.owner("epoch-1", true);
        let mut s = ready(owner.clone());
        let original = s.draft().project_command().unwrap().clone();
        let mut altered = original.clone();
        altered.authority.grant_id = "different-grant".into();
        altered.plan_digest = altered.expected_plan_digest().unwrap();
        altered.validate().unwrap();
        // Simulate a domain-valid stored envelope that does not match the owner plan.
        let mut envelope = s.draft.envelope().unwrap();
        envelope.content["submission"]["command"] = serde_json::to_value(altered).unwrap();
        s.draft = ConversationDraft::restore(&serde_json::to_string(&envelope).unwrap(), &scope())
            .unwrap();
        assert!(
            matches!(s.confirm_visible(&save("save:marker"), &save("save:result")), Err(ProductError::Failure { code }) if code == "BindingMismatch")
        );
        let state = owner.state.lock().unwrap();
        assert!(!state.prepared[&original.plan_id].dispatched);
        assert!(state.store.projects(10, 0).unwrap().is_empty());
        assert!(s
            .store
            .lookup_save(&s.draft.envelope().unwrap().draft_ref, &save("save:marker"))
            .unwrap()
            .is_none());
    }
}
