//! Private Android host facade. Durable namespace identity and live Binder
//! authorization are distinct: the Service owns its current lease and revokes
//! this object on scope/session changes. No method is a registered model tool.
use crate::{
    command_port::ProductCommandPort, development_session::DevelopmentSession, ProductCore,
    ProductError,
};
use muyon_core::{
    contract::{CommandEnvelope, ContractError, Operation, Revision},
    development_drafts::{
        ConversationDraft, DraftItem, DraftPatch, DraftText, ItemKind, ProjectChoice, SourceBinding,
    },
    services::{
        commands::{HostCommandPort, OriginalLookup},
        draft_store::DraftStore,
        drafts::{validate_save_ack, DraftEnvelope, DraftRef},
        types::{decode_strict, IntentId, ScopeRef},
    },
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{
    fs::{File, OpenOptions},
    io::{Read, Write},
    os::unix::fs::MetadataExt,
    sync::{Arc, Mutex},
};

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct LocalNamespace {
    version: u32,
    workspace: String,
    business_identity: String,
    generation: Revision,
}
fn namespace_scope(
    owner: &ProductCore,
    project: Option<String>,
    create: bool,
) -> Result<ScopeRef, ProductError> {
    let root = owner.agent_path.parent().ok_or_else(crate::unavailable)?;
    let business =
        std::fs::metadata(root.join("business-v2.sqlite")).map_err(|_| crate::unavailable())?;
    let identity = format!("{}:{}", business.dev(), business.ino());
    let path = root.join("development-namespace-v1.json");
    // The existing owner mutex serializes initialization. Never replace a partial
    // namespace or silently attach old drafts to a replaced business database.
    let state = owner.state.lock().map_err(|_| crate::unavailable())?;
    muyon_core::agent::ReadScope::current(&state.store, project.as_deref())?;
    let namespace = if path.try_exists().map_err(|_| crate::unavailable())? {
        let bytes = std::fs::read_to_string(&path).map_err(|_| crate::unavailable())?;
        let record: LocalNamespace =
            decode_strict(&bytes).map_err(|_| ContractError::StorageCorrupt)?;
        if record.version != 1
            || record.workspace != owner.workspace
            || record.business_identity != identity
        {
            return Err(ContractError::BindingMismatch.into());
        }
        record
    } else {
        if !create {
            return Err(ContractError::NotFound.into());
        }
        let mut bytes = [0u8; 8];
        File::open("/dev/urandom")
            .and_then(|mut f| f.read_exact(&mut bytes))
            .map_err(|_| crate::unavailable())?;
        let record = LocalNamespace {
            version: 1,
            workspace: owner.workspace.clone(),
            business_identity: identity,
            generation: Revision::new(u64::from_le_bytes(bytes).max(1)),
        };
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&path)
            .map_err(|_| crate::unavailable())?;
        file.write_all(crate::encode(&record)?.as_bytes())
            .and_then(|()| file.sync_all())
            .map_err(|_| crate::unavailable())?;
        File::open(root)
            .and_then(|f| f.sync_all())
            .map_err(|_| crate::unavailable())?;
        record
    };
    Ok(ScopeRef {
        scope: muyon_core::contract::Scope {
            workspace_id: owner.workspace.clone(),
            project_id: project,
        },
        account_id: None,
        scope_generation: namespace.generation,
    })
}

fn original_json(lookup: &OriginalLookup) -> Result<String, ProductError> {
    match lookup {
        OriginalLookup::Execution(result) => crate::encode(result),
        OriginalLookup::NotSubmitted { .. } => Ok(json!({"status":"not_submitted","receipt":null,
            "error":"confirmation_not_received","recovery_action":"edit_new_draft"})
        .to_string()),
    }
}
fn save_intent() -> Result<IntentId, ProductError> {
    IntentId::parse(&crate::opaque_id("development-save")?)
        .map_err(|_| ContractError::InvalidIdentity.into())
}
fn conversation_of(draft: &ConversationDraft) -> Result<String, ProductError> {
    draft.envelope()?.content["conversation_id"]
        .as_str()
        .map(str::to_owned)
        .ok_or_else(crate::unavailable)
}

#[derive(Clone)]
struct PendingDraftSave {
    envelope: DraftEnvelope,
    intent: IntentId,
    candidates: Vec<CommandEnvelope>,
    new_plan: Option<CommandEnvelope>,
}
struct ActiveDraft {
    session: DevelopmentSession,
    namespace: ScopeRef,
    conversation: String,
    // Keep the original envelope/intent until its acknowledgement and current
    // draft can be read. A failed read never permits another preparation.
    pending_save: Option<PendingDraftSave>,
}

/// Native capability owned by the private Service, never the model dispatcher.
/// All methods use one lock order: this object, then ProductCore; no core method
/// calls back into this object while retaining the core mutex.
#[derive(uniffi::Object)]
pub struct DevelopmentDraftHost {
    owner: Arc<ProductCore>,
    active: Mutex<Option<ActiveDraft>>,
}

#[uniffi::export]
impl DevelopmentDraftHost {
    #[uniffi::constructor]
    pub fn open(
        core: Arc<ProductCore>,
        conversation: String,
        project: Option<String>,
        draft_id: Option<String>,
        create: bool,
    ) -> Result<Arc<Self>, ProductError> {
        let namespace = namespace_scope(&core, project, create)?;
        let digest = muyon_core::contract::stable_digest(&json!([
            conversation,
            namespace.scope.project_id
        ]))?;
        let id = draft_id.unwrap_or_else(|| format!("development-{}", &digest[..40]));
        if create {
            let path = super::development_session::scope_path(&core, &namespace)?;
            if !path.try_exists().map_err(|_| crate::unavailable())? {
                DevelopmentSession::initialize_namespace(&core, &namespace)?;
            }
        }
        let session = match DevelopmentSession::restore(core.clone(), namespace.clone(), &id) {
            Ok(session) => session,
            Err(ProductError::Failure { code }) if create && code == "NotFound" => {
                DevelopmentSession::create(
                    core.clone(),
                    namespace.clone(),
                    id,
                    conversation.clone(),
                    &save_intent()?,
                )?
            }
            Err(error) => return Err(error),
        };
        if conversation_of(session.draft())? != conversation {
            return Err(ContractError::BindingMismatch.into());
        }
        Ok(Arc::new(Self {
            owner: core,
            active: Mutex::new(Some(ActiveDraft {
                session,
                namespace,
                conversation,
                pending_save: None,
            })),
        }))
    }

    pub fn snapshot(&self) -> Result<String, ProductError> {
        self.read(|active| crate::encode(&active.session.draft().envelope()?))
    }

    pub fn set_project_name(
        &self,
        name: String,
        expected_revision: String,
    ) -> Result<String, ProductError> {
        self.mutate(|active| {
            active.session.apply_patch(
                &Revision::parse(&expected_revision)?,
                DraftPatch {
                    project_name: Some(name),
                    items: vec![],
                },
                true,
            )
        })
    }

    pub fn add_item(
        &self,
        kind: String,
        text: String,
        expected_revision: String,
    ) -> Result<String, ProductError> {
        self.mutate(|active| {
            let kind = match kind.as_str() {
                "requirement" => ItemKind::Requirement,
                "bug" => ItemKind::Bug,
                "question" => ItemKind::Question,
                _ => return Err(ContractError::InvalidPayload.into()),
            };
            let item = DraftItem {
                item_id: crate::opaque_id("manual-item")?,
                kind,
                text: DraftText {
                    text: text.clone(),
                    manually_edited: true,
                },
                sources: vec![SourceBinding {
                    conversation_id: active.conversation.clone(),
                    message_id: crate::opaque_id("manual")?,
                    message_revision: Revision::new(0),
                    start: 0,
                    end: text.len(),
                    original_message: text,
                }],
            };
            active.session.apply_patch(
                &Revision::parse(&expected_revision)?,
                DraftPatch {
                    project_name: None,
                    items: vec![item],
                },
                true,
            )
        })
    }

    pub fn edit_item(
        &self,
        item_id: String,
        text: String,
        expected_revision: String,
    ) -> Result<String, ProductError> {
        self.mutate(|active| {
            let mut item = active
                .session
                .draft()
                .items()
                .iter()
                .find(|item| item.item_id == item_id)
                .cloned()
                .ok_or(ContractError::NotFound)?;
            item.text.text = text;
            active.session.apply_patch(
                &Revision::parse(&expected_revision)?,
                DraftPatch {
                    project_name: None,
                    items: vec![item],
                },
                true,
            )
        })
    }

    pub fn choose_new_project(&self, expected_revision: String) -> Result<String, ProductError> {
        self.mutate(|active| {
            if active.namespace.scope.project_id.is_some() {
                return Err(ContractError::ScopeMismatch.into());
            }
            active.session.choose_project(
                &Revision::parse(&expected_revision)?,
                crate::opaque_id("project")?,
                true,
            )
        })
    }

    pub fn prepare_project(&self) -> Result<String, ProductError> {
        let mut guard = self.active.lock().map_err(|_| crate::unavailable())?;
        let active = guard.as_mut().ok_or(ContractError::InvalidAuthority)?;
        self.reconcile_pending_save(active)?;
        // Never prepare another identity for an already reviewed original.
        if let Some(command) = active.session.draft().project_command() {
            return Ok(
                json!({"plan":command,"binding_digest":command.binding_digest()?}).to_string(),
            );
        }
        let ProjectChoice::New { project_id } = active.session.draft().project() else {
            return Err(ContractError::Required.into());
        };
        let name = active
            .session
            .draft()
            .project_name()
            .ok_or(ContractError::Required)?
            .text
            .clone();
        // Allocate the save identity before creating a new owner preparation.
        let review_intent = save_intent()?;
        let command = ProductCommandPort::new(self.owner.clone())
            .prepare(
                Operation::ProjectCreate {
                    project_id: project_id.clone(),
                    name,
                },
                active.namespace.scope.project_id.clone(),
                Revision::new(0),
            )
            .map_err(|_| crate::agent_error("development_prepare_unknown_do_not_repeat"))?;
        let envelope = (|| -> Result<DraftEnvelope, ProductError> {
            let mut candidate = active.session.draft().clone();
            candidate.prepare_project(&candidate.revision().clone(), command.clone())?;
            Ok(candidate.envelope()?)
        })();
        let envelope = match envelope {
            Ok(envelope) => envelope,
            Err(error) => {
                self.discard_unsubmitted_exact(&command)?;
                return Err(error);
            }
        };
        active.pending_save = Some(PendingDraftSave {
            envelope,
            intent: review_intent.clone(),
            candidates: vec![command.clone()],
            new_plan: Some(command.clone()),
        });
        if let Err(error) = active
            .session
            .review_prepared(command.clone(), &review_intent)
        {
            // First query this exact save. None permits retiring the fresh plan;
            // an unreadable outcome retains both identity and the retry barrier.
            self.reconcile_pending_save(active)?;
            return Err(error);
        }
        active.pending_save = None;
        Ok(json!({"plan":command,"binding_digest":command.binding_digest()?}).to_string())
    }

    /// Called only by the private Service's visible project review action.
    pub fn confirm_project(
        &self,
        plan_id: String,
        binding_digest: String,
    ) -> Result<String, ProductError> {
        let mut guard = self.active.lock().map_err(|_| crate::unavailable())?;
        let active = guard.as_mut().ok_or(ContractError::InvalidAuthority)?;
        self.reconcile_pending_save(active)?;
        let command = active
            .session
            .draft()
            .project_command()
            .ok_or(ContractError::Required)?;
        if command.plan_id != plan_id || command.binding_digest()? != binding_digest {
            return Err(ContractError::BindingMismatch.into());
        }
        original_json(
            &active
                .session
                .confirm_visible(&save_intent()?, &save_intent()?)?,
        )
    }

    pub fn recover_original(&self) -> Result<String, ProductError> {
        self.read(|active| original_json(&active.session.recover_original()?))
    }

    /// A proposal is a source-bound local preview, not a business plan.
    pub fn preview_proposal(
        &self,
        request: String,
        session: String,
        generation: String,
    ) -> Result<String, ProductError> {
        self.read(|active| {
            let state = self.owner.state.lock().map_err(|_| crate::unavailable())?;
            let context = muyon_core::agent::tools::ToolsContext::current(&state.store, &session, &generation, active.namespace.scope.project_id.as_deref()).map_err(crate::agent_error)?;
            let proposal = state.agent.as_ref().ok_or_else(|| crate::agent_error("agent_not_configured"))?
                .development_proposal_review(&request, &context).map_err(crate::agent_error)?;
            if proposal.conversation_id != active.conversation { return Err(ContractError::BindingMismatch.into()); }
            let mut draft = ConversationDraft::new(DraftRef { owner_plugin_id: "development".into(), draft_id: proposal.draft_id.clone(), scope: active.namespace.clone(), revision: Revision::new(0) }, active.conversation.clone())?;
            draft.apply(&Revision::new(0), proposal.patch, false)?;
            Ok(json!({"review_digest":proposal.digest,"request_id":request,"draft_id":proposal.draft_id,"snapshot":draft.envelope()?}).to_string())
        })
    }

    /// Explicit local acceptance freezes the original request before saving.
    /// The model never invokes this entry or any project confirmation entry.
    pub fn accept_proposal(
        &self,
        request: String,
        session: String,
        generation: String,
        review_digest: String,
    ) -> Result<String, ProductError> {
        let mut guard = self.active.lock().map_err(|_| crate::unavailable())?;
        let active = guard.as_mut().ok_or(ContractError::InvalidAuthority)?;
        let acceptance = {
            let state = self.owner.state.lock().map_err(|_| crate::unavailable())?;
            let context = muyon_core::agent::tools::ToolsContext::current(
                &state.store,
                &session,
                &generation,
                active.namespace.scope.project_id.as_deref(),
            )
            .map_err(crate::agent_error)?;
            let agent = state
                .agent
                .as_ref()
                .ok_or_else(|| crate::agent_error("agent_not_configured"))?;
            let (envelope, intent, digest) = match agent.development_acceptance_original(&request) {
                Ok(original) => {
                    if original.scope != active.namespace
                        || original.conversation_id != active.conversation
                    {
                        return Err(ContractError::BindingMismatch.into());
                    }
                    (
                        original.envelope,
                        original.save_intent,
                        original.review_digest,
                    )
                }
                Err("development_acceptance_missing") => {
                    let proposal = agent
                        .development_proposal_review(&request, &context)
                        .map_err(crate::agent_error)?;
                    if proposal.conversation_id != active.conversation {
                        return Err(ContractError::BindingMismatch.into());
                    }
                    let mut draft = ConversationDraft::new(
                        DraftRef {
                            owner_plugin_id: "development".into(),
                            draft_id: proposal.draft_id,
                            scope: active.namespace.clone(),
                            revision: Revision::new(0),
                        },
                        active.conversation.clone(),
                    )?;
                    draft.apply(&Revision::new(0), proposal.patch, false)?;
                    let intent = IntentId::parse(&format!("development-accept-{request}"))
                        .map_err(|_| ContractError::InvalidIdentity)?;
                    (draft.envelope()?, intent, proposal.digest)
                }
                Err(error) => return Err(crate::agent_error(error)),
            };
            if digest != review_digest {
                return Err(ContractError::BindingMismatch.into());
            }
            agent
                .begin_development_acceptance_trusted(&request, &context, &envelope, &intent)
                .map_err(crate::agent_error)?
        };
        let store = DraftStore::open_existing(
            &super::development_session::scope_path(&self.owner, &active.namespace)?,
            &active.namespace,
        )?;
        let ack = store.save(&acceptance.envelope, &acceptance.save_intent)?;
        {
            let state = self.owner.state.lock().map_err(|_| crate::unavailable())?;
            let context = muyon_core::agent::tools::ToolsContext::current(
                &state.store,
                &session,
                &generation,
                active.namespace.scope.project_id.as_deref(),
            )
            .map_err(crate::agent_error)?;
            state
                .agent
                .as_ref()
                .ok_or_else(|| crate::agent_error("agent_not_configured"))?
                .complete_development_acceptance_trusted(&request, &context, &ack)
                .map_err(crate::agent_error)?;
        }
        self.select_saved(active, &acceptance.envelope.draft_ref.draft_id)?;
        Ok(json!({"status":"saved","request_id":request,"draft_id":acceptance.envelope.draft_ref.draft_id,"snapshot":active.session.draft().envelope()?}).to_string())
    }

    pub fn reject_proposal(
        &self,
        request: String,
        session: String,
        generation: String,
        review_digest: String,
    ) -> Result<String, ProductError> {
        self.read(|active| {
            let state = self.owner.state.lock().map_err(|_| crate::unavailable())?;
            let context = muyon_core::agent::tools::ToolsContext::current(
                &state.store,
                &session,
                &generation,
                active.namespace.scope.project_id.as_deref(),
            )
            .map_err(crate::agent_error)?;
            let agent = state
                .agent
                .as_ref()
                .ok_or_else(|| crate::agent_error("agent_not_configured"))?;
            let proposal = agent
                .development_proposal_review(&request, &context)
                .map_err(crate::agent_error)?;
            if proposal.conversation_id != active.conversation || proposal.digest != review_digest {
                return Err(ContractError::BindingMismatch.into());
            }
            agent
                .reject_development_proposal_trusted(&request, &context)
                .map_err(crate::agent_error)?;
            Ok(json!({"rejected":true,"request_id":request}).to_string())
        })
    }

    /// New Binder/epoch recovery checks only the original save acknowledgement.
    /// It cannot apply a proposal, save another envelope or call a provider.
    pub fn recover_proposal(&self, request: String) -> Result<String, ProductError> {
        let mut guard = self.active.lock().map_err(|_| crate::unavailable())?;
        let active = guard.as_mut().ok_or(ContractError::InvalidAuthority)?;
        let record = {
            let state = self.owner.state.lock().map_err(|_| crate::unavailable())?;
            state
                .agent
                .as_ref()
                .ok_or_else(|| crate::agent_error("agent_not_configured"))?
                .development_acceptance_original(&request)
                .map_err(crate::agent_error)?
        };
        if record.scope != active.namespace || record.conversation_id != active.conversation {
            return Err(ContractError::BindingMismatch.into());
        }
        let store = DraftStore::open_existing(
            &super::development_session::scope_path(&self.owner, &active.namespace)?,
            &active.namespace,
        )?;
        let Some(ack) = store.lookup_save(&record.envelope.draft_ref, &record.save_intent)? else {
            return Ok(json!({"status":"not_saved","request_id":request,"draft_id":record.envelope.draft_ref.draft_id}).to_string());
        };
        {
            let state = self.owner.state.lock().map_err(|_| crate::unavailable())?;
            state
                .agent
                .as_ref()
                .ok_or_else(|| crate::agent_error("agent_not_configured"))?
                .complete_development_acceptance_original_trusted(&request, &ack)
                .map_err(crate::agent_error)?;
        }
        self.select_saved(active, &record.envelope.draft_ref.draft_id)?;
        Ok(json!({"status":"saved","request_id":request,"draft_id":record.envelope.draft_ref.draft_id,"snapshot":active.session.draft().envelope()?}).to_string())
    }

    /// Revocation invalidates even a leaked old generated Kotlin handle.
    pub fn revoke(&self) -> Result<(), ProductError> {
        let mut guard = self.active.lock().map_err(|_| crate::unavailable())?;
        if let Some(active) = guard.take() {
            if let Some(command) = active.session.draft().project_command() {
                self.owner.discard_plan(command.plan_id.clone())?;
            }
        }
        Ok(())
    }
}

impl DevelopmentDraftHost {
    /// Atomically retire only this exact, still-unsubmitted owner preparation.
    /// Never removes a dispatched original or changes its durable receipt.
    fn discard_unsubmitted_exact(&self, command: &CommandEnvelope) -> Result<(), ProductError> {
        let mut state = self.owner.state.lock().map_err(|_| crate::unavailable())?;
        if state
            .prepared
            .get(&command.plan_id)
            .is_some_and(|prepared| !prepared.dispatched && prepared.command == *command)
        {
            state.prepared.remove(&command.plan_id);
        }
        Ok(())
    }
    fn retire_obsolete(
        &self,
        candidates: &[CommandEnvelope],
        current: Option<&CommandEnvelope>,
    ) -> Result<(), ProductError> {
        for command in candidates {
            if current != Some(command) {
                self.discard_unsubmitted_exact(command)?;
            }
        }
        Ok(())
    }
    fn reconcile_pending_save(&self, active: &mut ActiveDraft) -> Result<(), ProductError> {
        let Some(pending) = active.pending_save.clone() else {
            return Ok(());
        };
        let unknown = || crate::agent_error("development_save_unknown_do_not_repeat");
        let ack = active
            .session
            .lookup_saved(&pending.envelope.draft_ref, &pending.intent)
            .map_err(|_| unknown())?;
        if let Some(ack) = ack {
            validate_save_ack(
                &pending.envelope,
                &pending.envelope.draft_ref.revision,
                &pending.intent,
                &ack,
            )
            .map_err(|_| unknown())?;
        } else if let Some(command) = &pending.new_plan {
            // Only the fresh review command is unreferenced when its save is
            // known absent. An older edit candidate may still be the current plan.
            self.discard_unsubmitted_exact(command)?;
        }
        let restored = DevelopmentSession::restore(
            self.owner.clone(),
            active.namespace.clone(),
            &pending.envelope.draft_ref.draft_id,
        )
        .map_err(|_| unknown())?;
        self.retire_obsolete(&pending.candidates, restored.draft().project_command())?;
        active.session = restored;
        active.pending_save = None;
        Ok(())
    }
    fn select_saved(&self, active: &mut ActiveDraft, draft_id: &str) -> Result<(), ProductError> {
        self.reconcile_pending_save(active)?;
        let restored =
            DevelopmentSession::restore(self.owner.clone(), active.namespace.clone(), draft_id)?;
        if conversation_of(restored.draft())? != active.conversation {
            return Err(ContractError::BindingMismatch.into());
        }
        if let Some(command) = active.session.draft().project_command() {
            if restored.draft().project_command() != Some(command) {
                self.owner.discard_plan(command.plan_id.clone())?;
            }
        }
        active.session = restored;
        Ok(())
    }
    fn read<T>(
        &self,
        action: impl FnOnce(&ActiveDraft) -> Result<T, ProductError>,
    ) -> Result<T, ProductError> {
        let guard = self.active.lock().map_err(|_| crate::unavailable())?;
        action(guard.as_ref().ok_or(ContractError::InvalidAuthority)?)
    }
    fn mutate(
        &self,
        action: impl FnOnce(&mut ActiveDraft) -> Result<(), ProductError>,
    ) -> Result<String, ProductError> {
        let mut guard = self.active.lock().map_err(|_| crate::unavailable())?;
        let active = guard.as_mut().ok_or(ContractError::InvalidAuthority)?;
        self.reconcile_pending_save(active)?;
        let id = active.session.draft().envelope()?.draft_ref.draft_id;
        let mut candidates: Vec<_> = active
            .session
            .draft()
            .project_command()
            .cloned()
            .into_iter()
            .collect();
        let mut next = ActiveDraft {
            session: DevelopmentSession::restore(
                self.owner.clone(),
                active.namespace.clone(),
                &id,
            )?,
            namespace: active.namespace.clone(),
            conversation: active.conversation.clone(),
            pending_save: None,
        };
        if let Some(command) = next.session.draft().project_command() {
            if !candidates.contains(command) {
                candidates.push(command.clone());
            }
        }
        if let Err(error) = action(&mut next) {
            // No save was attempted. Reconcile only with a successfully read
            // current draft; a failed read is not proof an older plan is obsolete.
            if let Ok(current) =
                DevelopmentSession::restore(self.owner.clone(), active.namespace.clone(), &id)
            {
                self.retire_obsolete(&candidates, current.draft().project_command())?;
                active.session = current;
            }
            return Err(error);
        }
        let intent = save_intent()?;
        active.pending_save = Some(PendingDraftSave {
            envelope: next.session.draft().envelope()?,
            intent: intent.clone(),
            candidates: candidates.clone(),
            new_plan: None,
        });
        if let Err(error) = next.session.save(&intent) {
            self.reconcile_pending_save(active)?;
            return Err(error);
        }
        *active = next;
        self.retire_obsolete(&candidates, active.session.draft().project_command())?;
        crate::encode(&active.session.draft().envelope()?)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use muyon_core::agent::{
        owner::{HostedCostBound, HostedCostVerifier, MODEL, PRICE_REVISION},
        tools::ToolsContext,
    };
    use muyon_core::services::drafts::DraftEnvelope;
    use serde_json::Value;
    use std::path::PathBuf;
    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            Self(std::env::temp_dir().join(crate::opaque_id("development-native").unwrap()))
        }
        fn owner(&self, epoch: &str, init: bool) -> Arc<ProductCore> {
            ProductCore::open(
                self.0.to_str().unwrap().into(),
                "workspace".into(),
                epoch.into(),
                init,
            )
            .unwrap()
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    fn value(host: &DevelopmentDraftHost) -> Value {
        serde_json::from_str(&host.snapshot().unwrap()).unwrap()
    }
    fn revision(host: &DevelopmentDraftHost) -> String {
        value(host)["content"]["edit_revision"]
            .as_str()
            .unwrap()
            .into()
    }
    struct FixtureProof;
    impl HostedCostVerifier for FixtureProof {
        fn prove(&self, _: &[u8], _: &str) -> muyon_core::agent::owner::Result<HostedCostBound> {
            HostedCostBound::verified(16384, 128)
        }
    }
    fn model_pending(core: &ProductCore) -> String {
        core.agent_configure(json!({"credential_generation":"fixture-generation","cap_micro_cny":"1000000","max_calls":"10","chat":true,"search":false,"price_revision":PRICE_REVISION}).to_string()).unwrap();
        let state = core.state.lock().unwrap();
        let agent = state.agent.as_ref().unwrap();
        let config = agent.configuration().unwrap();
        let plan = agent
            .prepare_chat_restricted(
                "conversation",
                "请整理开发需求：增加离线草稿并修复导出错误",
                Some(&FixtureProof),
                &["development_draft_propose"],
            )
            .unwrap();
        let context =
            ToolsContext::current(&state.store, "model-session", "model-generation", None).unwrap();
        agent
            .bind_tool_scope_trusted(&plan.request_id, &context)
            .unwrap();
        agent.confirm_trusted(&plan.request_id, &config.id).unwrap();
        agent
            .claim_dispatch(
                &plan.request_id,
                &config.id,
                &config.settings.credential_generation,
            )
            .unwrap();
        let arguments = json!({"project_name":"离线工作台","items":[{"kind":"requirement","text":"增加离线草稿"},{"kind":"bug","text":"修复导出错误"}]}).to_string();
        let response = json!({"id":"fixture-development-response","model":MODEL,"choices":[{"index":0,"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"tool_calls":[{"id":"fixture_call","type":"function","function":{"name":"product_development_draft_propose","arguments":arguments}}]}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string();
        assert_eq!(
            agent
                .settle_response(&plan.request_id, &response)
                .unwrap()
                .status,
            "tool_pending"
        );
        plan.request_id
    }
    fn preview(host: &DevelopmentDraftHost, request: &str) -> Value {
        serde_json::from_str(
            &host
                .preview_proposal(
                    request.into(),
                    "model-session".into(),
                    "model-generation".into(),
                )
                .unwrap(),
        )
        .unwrap()
    }
    fn freeze(
        core: &ProductCore,
        request: &str,
        view: &Value,
    ) -> muyon_core::agent::tools::DevelopmentAcceptance {
        let envelope: DraftEnvelope = serde_json::from_value(view["snapshot"].clone()).unwrap();
        let state = core.state.lock().unwrap();
        let context =
            ToolsContext::current(&state.store, "model-session", "model-generation", None).unwrap();
        state
            .agent
            .as_ref()
            .unwrap()
            .begin_development_acceptance_trusted(
                request,
                &context,
                &envelope,
                &IntentId::parse(&format!("development-accept-{request}")).unwrap(),
            )
            .unwrap()
    }

    #[test]
    fn model_script_preview_explicit_accept_preserves_provenance_and_unlocks_later_chat() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host =
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, true)
                .unwrap();
        let original = value(&host);
        let request = model_pending(&core);
        let proposal = preview(&host, &request);
        assert_eq!(
            value(&host),
            original,
            "preview cannot save or select a model draft"
        );
        assert!(core
            .state
            .lock()
            .unwrap()
            .agent
            .as_ref()
            .unwrap()
            .prepare_chat("conversation", "继续", Some(&FixtureProof))
            .is_err());
        assert!(host
            .accept_proposal(
                request.clone(),
                "model-session".into(),
                "model-generation".into(),
                "wrong-digest".into()
            )
            .is_err());
        assert_eq!(value(&host), original);
        let saved: Value = serde_json::from_str(
            &host
                .accept_proposal(
                    request.clone(),
                    "model-session".into(),
                    "model-generation".into(),
                    proposal["review_digest"].as_str().unwrap().into(),
                )
                .unwrap(),
        )
        .unwrap();
        assert_eq!(saved["status"], "saved");
        let snapshot = value(&host);
        assert_eq!(snapshot["draft_ref"]["draft_id"], proposal["draft_id"]);
        assert_eq!(snapshot["draft_ref"]["revision"], "1");
        assert_eq!(
            snapshot["content"]["items"][0]["text"]["manually_edited"],
            false
        );
        assert_eq!(
            snapshot["content"]["items"][0]["sources"][0]["original_message"],
            "请整理开发需求：增加离线草稿并修复导出错误"
        );
        assert_eq!(snapshot["content"]["submission"], Value::Null);
        {
            let state = core.state.lock().unwrap();
            let agent = state.agent.as_ref().unwrap();
            assert_eq!(agent.lookup(&request).unwrap().status, "tool_consumed");
            assert_eq!(agent.request_chain(&request).unwrap().len(), 1);
            let next = agent
                .prepare_chat("conversation", "继续", Some(&FixtureProof))
                .unwrap();
            assert_eq!(
                next.outbound_preview["messages"],
                json!([{"role":"user","content":"继续"}])
            );
            assert!(state.store.projects(10, 0).unwrap().is_empty());
        }
        let draft_id = snapshot["draft_ref"]["draft_id"]
            .as_str()
            .unwrap()
            .to_owned();
        drop(host);
        drop(core);
        let restored = DevelopmentDraftHost::open(
            f.owner("epoch-2", false),
            "conversation".into(),
            None,
            Some(draft_id),
            false,
        )
        .unwrap();
        assert_eq!(value(&restored), snapshot);
    }

    #[test]
    fn model_original_save_ack_recovers_after_restart_without_overwriting_manual_edits() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host =
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, true)
                .unwrap();
        let request = model_pending(&core);
        let proposal = preview(&host, &request);
        let record = freeze(&core, &request, &proposal);
        let store = DraftStore::open_existing(
            &super::super::development_session::scope_path(&core, &record.scope).unwrap(),
            &record.scope,
        )
        .unwrap();
        store.save(&record.envelope, &record.save_intent).unwrap();
        let editor = DevelopmentDraftHost::open(
            core.clone(),
            "conversation".into(),
            None,
            Some(record.envelope.draft_ref.draft_id.clone()),
            false,
        )
        .unwrap();
        let item = value(&editor)["content"]["items"][0]["item_id"]
            .as_str()
            .unwrap()
            .to_owned();
        editor
            .edit_item(item, "人工修改必须保留".into(), revision(&editor))
            .unwrap();
        let manually_saved = value(&editor);
        drop(store);
        drop(editor);
        drop(host);
        drop(core);
        let core = f.owner("epoch-2", false);
        let host =
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, false)
                .unwrap();
        assert!(host
            .accept_proposal(
                request.clone(),
                "new-session".into(),
                "new-generation".into(),
                proposal["review_digest"].as_str().unwrap().into()
            )
            .is_err());
        let result: Value =
            serde_json::from_str(&host.recover_proposal(request.clone()).unwrap()).unwrap();
        assert_eq!(result["status"], "saved");
        assert_eq!(value(&host), manually_saved);
        assert_eq!(
            host.recover_proposal(request.clone()).unwrap(),
            result.to_string()
        );
        let state = core.state.lock().unwrap();
        assert_eq!(
            state
                .agent
                .as_ref()
                .unwrap()
                .lookup(&request)
                .unwrap()
                .status,
            "tool_consumed"
        );
        assert_eq!(
            state
                .agent
                .as_ref()
                .unwrap()
                .request_chain(&request)
                .unwrap()
                .len(),
            1
        );
        assert!(state.store.projects(10, 0).unwrap().is_empty());
    }

    #[test]
    fn model_recovery_missing_save_is_query_only_and_scope_mismatch_is_rejected() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host =
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, true)
                .unwrap();
        let original = value(&host);
        let request = model_pending(&core);
        let proposal = preview(&host, &request);
        let record = freeze(&core, &request, &proposal);
        assert!(host
            .preview_proposal(
                request.clone(),
                "wrong-session".into(),
                "model-generation".into()
            )
            .is_err());
        let other =
            DevelopmentDraftHost::open(core.clone(), "other-conversation".into(), None, None, true)
                .unwrap();
        assert!(other
            .preview_proposal(
                request.clone(),
                "model-session".into(),
                "model-generation".into()
            )
            .is_err());
        assert!(other.recover_proposal(request.clone()).is_err());
        drop(other);
        drop(host);
        drop(core);
        let core = f.owner("epoch-2", false);
        let host =
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, false)
                .unwrap();
        let result: Value =
            serde_json::from_str(&host.recover_proposal(request.clone()).unwrap()).unwrap();
        assert_eq!(result["status"], "not_saved");
        assert_eq!(value(&host), original);
        let store = DraftStore::open_existing(
            &super::super::development_session::scope_path(&core, &record.scope).unwrap(),
            &record.scope,
        )
        .unwrap();
        assert_eq!(
            store
                .lookup_save(&record.envelope.draft_ref, &record.save_intent)
                .unwrap(),
            None
        );
        assert_eq!(
            store
                .load("development", &record.envelope.draft_ref.draft_id)
                .unwrap(),
            None
        );
        assert_eq!(
            core.state
                .lock()
                .unwrap()
                .agent
                .as_ref()
                .unwrap()
                .lookup(&request)
                .unwrap()
                .status,
            "tool_pending"
        );
        let cancelled: Value =
            serde_json::from_str(&core.agent_cancel(request.clone()).unwrap()).unwrap();
        assert_eq!(cancelled["status"], "cancelled");
        assert_eq!(
            serde_json::from_str::<Value>(&host.recover_proposal(request.clone()).unwrap())
                .unwrap()["status"],
            "not_saved"
        );
        assert_eq!(
            store
                .lookup_save(&record.envelope.draft_ref, &record.save_intent)
                .unwrap(),
            None
        );
        assert_eq!(
            store
                .load("development", &record.envelope.draft_ref.draft_id)
                .unwrap(),
            None
        );
        core.agent_configure(json!({"credential_generation":"new-generation","cap_micro_cny":"1000000","max_calls":"10","chat":true,"search":false,"price_revision":PRICE_REVISION}).to_string()).unwrap();
        {
            let state = core.state.lock().unwrap();
            let agent = state.agent.as_ref().unwrap();
            assert_eq!(agent.request_chain(&request).unwrap().len(), 1);
            let next = agent
                .prepare_chat(
                    "conversation",
                    "取消未保存的原建议后继续",
                    Some(&FixtureProof),
                )
                .unwrap();
            assert_ne!(next.request_id, request);
            assert_eq!(
                next.outbound_preview["messages"],
                json!([{"role":"user","content":"取消未保存的原建议后继续"}])
            );
        }
        host.active
            .lock()
            .unwrap()
            .as_mut()
            .unwrap()
            .namespace
            .scope_generation = record.scope.scope_generation.next().unwrap();
        assert!(host.recover_proposal(request).is_err());
    }
    #[test]
    fn native_host_persists_manual_content_reopens_and_revokes_old_handles() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        assert!(
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, false)
                .is_err()
        );
        let host =
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, true)
                .unwrap();
        host.set_project_name("Project".into(), revision(&host))
            .unwrap();
        host.add_item("requirement".into(), "保留草稿".into(), revision(&host))
            .unwrap();
        let saved = value(&host);
        host.revoke().unwrap();
        assert!(host.snapshot().is_err());
        assert!(host.set_project_name("Wrong".into(), "0".into()).is_err());
        drop(host);
        drop(core);
        let core = f.owner("epoch-2", false);
        let restored =
            DevelopmentDraftHost::open(core, "conversation".into(), None, None, false).unwrap();
        assert_eq!(value(&restored), saved);
    }
    #[test]
    fn native_review_and_explicit_confirmation_keep_one_original_after_reopen() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host =
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, true)
                .unwrap();
        host.set_project_name("Project".into(), revision(&host))
            .unwrap();
        host.choose_new_project(revision(&host)).unwrap();
        let first = host.prepare_project().unwrap();
        assert_eq!(host.prepare_project().unwrap(), first);
        assert!(core
            .state
            .lock()
            .unwrap()
            .store
            .projects(10, 0)
            .unwrap()
            .is_empty());
        let review: Value = serde_json::from_str(&first).unwrap();
        let plan_id = review["plan"]["plan_id"].as_str().unwrap().to_owned();
        let binding_digest = review["binding_digest"].as_str().unwrap().to_owned();
        assert!(host
            .confirm_project("wrong-plan".into(), binding_digest.clone())
            .is_err());
        assert!(host
            .confirm_project(plan_id.clone(), "wrong-binding".into())
            .is_err());
        assert!(core
            .state
            .lock()
            .unwrap()
            .store
            .projects(10, 0)
            .unwrap()
            .is_empty());
        let result = host
            .confirm_project(plan_id.clone(), binding_digest.clone())
            .unwrap();
        assert_eq!(
            host.confirm_project(plan_id, binding_digest).unwrap(),
            result
        );
        drop(host);
        drop(core);
        let core = f.owner("epoch-2", false);
        let restored =
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, false)
                .unwrap();
        assert_eq!(restored.recover_original().unwrap(), result);
        assert_eq!(
            core.state
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
    fn native_cas_and_conversation_binding_reject_wrong_editor() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let a = DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, true)
            .unwrap();
        let id = value(&a)["draft_ref"]["draft_id"]
            .as_str()
            .unwrap()
            .to_owned();
        assert!(
            DevelopmentDraftHost::open(core.clone(), "other".into(), None, Some(id), false)
                .is_err()
        );
        let b = DevelopmentDraftHost::open(core, "conversation".into(), None, None, false).unwrap();
        a.set_project_name("First".into(), "0".into()).unwrap();
        assert!(b.set_project_name("Second".into(), "0".into()).is_err());
        assert_eq!(value(&b)["content"]["project_name"]["text"], "First");
    }

    #[test]
    fn model_recovery_keeps_same_draft_prepared_project_confirmation() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host =
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, true)
                .unwrap();
        let request = model_pending(&core);
        let proposal = preview(&host, &request);
        host.accept_proposal(
            request.clone(),
            "model-session".into(),
            "model-generation".into(),
            proposal["review_digest"].as_str().unwrap().into(),
        )
        .unwrap();
        host.choose_new_project(revision(&host)).unwrap();
        let reviewed = host.prepare_project().unwrap();
        let review: Value = serde_json::from_str(&reviewed).unwrap();
        host.recover_proposal(request).unwrap();
        assert_eq!(host.prepare_project().unwrap(), reviewed);
        assert!(core
            .state
            .lock()
            .unwrap()
            .store
            .projects(10, 0)
            .unwrap()
            .is_empty());
        let result: Value = serde_json::from_str(
            &host
                .confirm_project(
                    review["plan"]["plan_id"].as_str().unwrap().into(),
                    review["binding_digest"].as_str().unwrap().into(),
                )
                .unwrap(),
        )
        .unwrap();
        assert_eq!(result["status"], "committed");
        assert_eq!(
            core.state
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
    fn namespace_corruption_and_replaced_business_identity_fail_without_replacement() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host =
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, true)
                .unwrap();
        let namespace_path = f.0.join("development-namespace-v1.json");
        let original = std::fs::read_to_string(&namespace_path).unwrap();
        std::fs::write(&namespace_path, "{partial").unwrap();
        assert!(
            DevelopmentDraftHost::open(core.clone(), "conversation".into(), None, None, false)
                .is_err()
        );
        assert_eq!(
            std::fs::read_to_string(&namespace_path).unwrap(),
            "{partial"
        );
        std::fs::write(&namespace_path, &original).unwrap();
        drop(host);
        drop(core);
        let business_path = f.0.join("business-v2.sqlite");
        let bytes = std::fs::read(&business_path).unwrap();
        std::fs::rename(&business_path, f.0.join("previous-business.sqlite")).unwrap();
        std::fs::write(&business_path, bytes).unwrap();
        let core = f.owner("epoch-2", false);
        assert!(
            DevelopmentDraftHost::open(core, "conversation".into(), None, None, false).is_err()
        );
        assert_eq!(std::fs::read_to_string(&namespace_path).unwrap(), original);
    }

    fn lifecycle_ready(core: Arc<ProductCore>, conversation: &str) -> Arc<DevelopmentDraftHost> {
        let host = DevelopmentDraftHost::open(core, conversation.into(), None, None, true).unwrap();
        host.set_project_name("Project".into(), revision(&host))
            .unwrap();
        host.choose_new_project(revision(&host)).unwrap();
        host
    }
    fn lifecycle_db(host: &DevelopmentDraftHost) -> muyon_core::sqlite::Db {
        let scope = host
            .active
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .namespace
            .clone();
        let path = super::super::development_session::scope_path(&host.owner, &scope).unwrap();
        muyon_core::sqlite::Db::open(path.to_str().unwrap(), false, false).unwrap()
    }
    #[test]
    fn lifecycle_129_prepare_edit_cycles_do_not_exhaust_global_prepared_capacity() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host = lifecycle_ready(core.clone(), "capacity");
        for attempt in 0..129 {
            let plan = host
                .prepare_project()
                .unwrap_or_else(|e| panic!("prepare {attempt}: {e:?}"));
            assert_eq!(host.prepare_project().unwrap(), plan, "duplicate click");
            host.set_project_name(format!("Project {attempt}"), revision(&host))
                .unwrap();
        }
        assert!(core.state.lock().unwrap().prepared.is_empty());
        assert!(core
            .state
            .lock()
            .unwrap()
            .store
            .projects(10, 0)
            .unwrap()
            .is_empty());
    }
    #[test]
    fn lifecycle_edit_retires_only_its_own_unsubmitted_plan() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let a = lifecycle_ready(core.clone(), "a");
        let b = lifecycle_ready(core.clone(), "b");
        let pa: Value = serde_json::from_str(&a.prepare_project().unwrap()).unwrap();
        let pb: Value = serde_json::from_str(&b.prepare_project().unwrap()).unwrap();
        a.add_item("question".into(), "Local edit".into(), revision(&a))
            .unwrap();
        let state = core.state.lock().unwrap();
        assert!(!state
            .prepared
            .contains_key(pa["plan"]["plan_id"].as_str().unwrap()));
        assert!(state
            .prepared
            .contains_key(pb["plan"]["plan_id"].as_str().unwrap()));
        assert_eq!(state.prepared.len(), 1);
    }
    #[test]
    fn lifecycle_failed_review_cas_retires_new_plan_and_restores_current_draft() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let winner = lifecycle_ready(core.clone(), "cas");
        let stale =
            DevelopmentDraftHost::open(core.clone(), "cas".into(), None, None, false).unwrap();
        winner
            .set_project_name("Newest".into(), revision(&winner))
            .unwrap();
        assert!(stale.prepare_project().is_err());
        assert!(core.state.lock().unwrap().prepared.is_empty());
        assert_eq!(value(&stale), value(&winner));
        assert!(core
            .state
            .lock()
            .unwrap()
            .store
            .projects(10, 0)
            .unwrap()
            .is_empty());
    }
    #[test]
    fn lifecycle_failed_review_save_releases_plan_only_after_original_save_lookup() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host = lifecycle_ready(core.clone(), "save-failure");
        let db = lifecycle_db(&host);
        db.exec("CREATE TRIGGER reject_review BEFORE INSERT ON draft_save_intents BEGIN SELECT RAISE(ABORT,'fixture'); END", &[]).unwrap();
        assert!(host.prepare_project().is_err());
        assert!(core.state.lock().unwrap().prepared.is_empty());
        db.exec("DROP TRIGGER reject_review", &[]).unwrap();
        let first = host.prepare_project().unwrap();
        assert_eq!(host.prepare_project().unwrap(), first);
        assert_eq!(core.state.lock().unwrap().prepared.len(), 1);
    }
    #[test]
    fn lifecycle_unknown_save_lookup_blocks_new_preparation_until_original_is_resolved() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host = lifecycle_ready(core.clone(), "unknown-save");
        let db = lifecycle_db(&host);
        db.exec(
            "ALTER TABLE draft_save_intents RENAME TO temporarily_unavailable",
            &[],
        )
        .unwrap();
        assert!(host.prepare_project().is_err());
        let original = core
            .state
            .lock()
            .unwrap()
            .prepared
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        assert_eq!(original.len(), 1);
        assert!(host.prepare_project().is_err());
        assert_eq!(
            core.state
                .lock()
                .unwrap()
                .prepared
                .keys()
                .cloned()
                .collect::<Vec<_>>(),
            original
        );
        // ALTER ... RENAME back changes sqlite_master quoting. Recreate the
        // exact original schema so recovery still exercises the strict store.
        db.exec("CREATE TABLE draft_save_intents(intent_id TEXT PRIMARY KEY,request_digest TEXT NOT NULL,ack TEXT NOT NULL)", &[]).unwrap();
        db.exec(
            "INSERT INTO draft_save_intents SELECT * FROM temporarily_unavailable",
            &[],
        )
        .unwrap();
        db.exec("DROP TABLE temporarily_unavailable", &[]).unwrap();
        let plan: Value = serde_json::from_str(&host.prepare_project().unwrap()).unwrap();
        let state = core.state.lock().unwrap();
        assert_eq!(state.prepared.len(), 1);
        assert!(!state.prepared.contains_key(&original[0]));
        assert!(state
            .prepared
            .contains_key(plan["plan"]["plan_id"].as_str().unwrap()));
        assert!(state.store.projects(10, 0).unwrap().is_empty());
    }
    #[test]
    fn lifecycle_dispatched_original_receipt_is_not_retired_by_rejected_edit() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host = lifecycle_ready(core.clone(), "dispatched");
        let plan: Value = serde_json::from_str(&host.prepare_project().unwrap()).unwrap();
        let plan_id = plan["plan"]["plan_id"].as_str().unwrap().to_owned();
        let receipt = host
            .confirm_project(
                plan_id.clone(),
                plan["binding_digest"].as_str().unwrap().into(),
            )
            .unwrap();
        assert!(host
            .set_project_name("Forbidden".into(), revision(&host))
            .is_err());
        let original = core.state.lock().unwrap().prepared[&plan_id]
            .command
            .clone();
        host.discard_unsubmitted_exact(&original).unwrap();
        assert!(core.state.lock().unwrap().prepared[&plan_id].dispatched);
        assert_eq!(host.recover_original().unwrap(), receipt);
    }

    #[test]
    fn lifecycle_stale_edit_cas_preserves_the_other_editors_current_review() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let a = lifecycle_ready(core.clone(), "review-cas");
        let old: Value = serde_json::from_str(&a.prepare_project().unwrap()).unwrap();
        let old_revision = revision(&a);
        let b = DevelopmentDraftHost::open(core.clone(), "review-cas".into(), None, None, false)
            .unwrap();
        b.set_project_name("Newest".into(), revision(&b)).unwrap();
        let current: Value = serde_json::from_str(&b.prepare_project().unwrap()).unwrap();
        assert!(a.set_project_name("Stale".into(), old_revision).is_err());
        let state = core.state.lock().unwrap();
        assert!(!state
            .prepared
            .contains_key(old["plan"]["plan_id"].as_str().unwrap()));
        assert!(state
            .prepared
            .contains_key(current["plan"]["plan_id"].as_str().unwrap()));
        assert_eq!(state.prepared.len(), 1);
        drop(state);
        assert_eq!(a.prepare_project().unwrap(), b.prepare_project().unwrap());
    }
    #[test]
    fn lifecycle_existing_save_ack_recovers_original_review_without_another_prepare() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host = lifecycle_ready(core.clone(), "lost-ack");
        let mut guard = host.active.lock().unwrap();
        let active = guard.as_mut().unwrap();
        let original_session = DevelopmentSession::restore(
            core.clone(),
            active.namespace.clone(),
            &active
                .session
                .draft()
                .envelope()
                .unwrap()
                .draft_ref
                .draft_id,
        )
        .unwrap();
        let ProjectChoice::New { project_id } = active.session.draft().project() else {
            panic!("new project fixture")
        };
        let command = ProductCommandPort::new(core.clone())
            .prepare(
                Operation::ProjectCreate {
                    project_id: project_id.clone(),
                    name: "Project".into(),
                },
                None,
                Revision::new(0),
            )
            .unwrap();
        let mut candidate = active.session.draft().clone();
        candidate
            .prepare_project(&candidate.revision().clone(), command.clone())
            .unwrap();
        let intent = IntentId::parse("save:lost-review-ack").unwrap();
        active
            .session
            .review_prepared(command.clone(), &intent)
            .unwrap();
        // Simulate loss of the completion boundary after the real store commit;
        // retain the exact pending envelope/intent, rather than a new request.
        active.session = original_session;
        active.pending_save = Some(PendingDraftSave {
            envelope: candidate.envelope().unwrap(),
            intent,
            candidates: vec![command.clone()],
            new_plan: Some(command.clone()),
        });
        drop(guard);
        let recovered: Value = serde_json::from_str(&host.prepare_project().unwrap()).unwrap();
        assert_eq!(recovered["plan"]["plan_id"], command.plan_id);
        assert_eq!(recovered["plan"]["intent_id"], command.intent_id);
        assert_eq!(core.state.lock().unwrap().prepared.len(), 1);
        assert!(host
            .active
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .pending_save
            .is_none());
        assert_eq!(host.prepare_project().unwrap(), recovered.to_string());
    }

    #[test]
    fn lifecycle_edit_unknown_save_fences_confirm_and_keeps_original_until_lookup() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let host = lifecycle_ready(core.clone(), "edit-unknown");
        let review = host.prepare_project().unwrap();
        let plan: Value = serde_json::from_str(&review).unwrap();
        let db = lifecycle_db(&host);
        let expected = Revision::parse(&revision(&host)).unwrap();
        assert!(host
            .mutate(|active| {
                active.session.apply_patch(
                    &expected,
                    DraftPatch {
                        project_name: Some("Unsaved".into()),
                        items: vec![],
                    },
                    true,
                )?;
                db.exec(
                    "ALTER TABLE draft_save_intents RENAME TO temporarily_unavailable",
                    &[],
                )
                .unwrap();
                Ok(())
            })
            .is_err());
        assert!(host.prepare_project().is_err());
        assert!(host
            .confirm_project(
                plan["plan"]["plan_id"].as_str().unwrap().into(),
                plan["binding_digest"].as_str().unwrap().into()
            )
            .is_err());
        assert_eq!(core.state.lock().unwrap().prepared.len(), 1);
        assert!(core
            .state
            .lock()
            .unwrap()
            .store
            .projects(10, 0)
            .unwrap()
            .is_empty());
        db.exec("CREATE TABLE draft_save_intents(intent_id TEXT PRIMARY KEY,request_digest TEXT NOT NULL,ack TEXT NOT NULL)", &[]).unwrap();
        db.exec(
            "INSERT INTO draft_save_intents SELECT * FROM temporarily_unavailable",
            &[],
        )
        .unwrap();
        db.exec("DROP TABLE temporarily_unavailable", &[]).unwrap();
        assert_eq!(host.prepare_project().unwrap(), review);
        host.set_project_name("Known edit".into(), revision(&host))
            .unwrap();
        assert!(core.state.lock().unwrap().prepared.is_empty());
    }
    #[test]
    fn lifecycle_edit_retires_a_review_loaded_after_the_host_snapshot() {
        let f = Fixture::new();
        let core = f.owner("epoch-1", true);
        let a = lifecycle_ready(core.clone(), "loaded-review");
        let b = DevelopmentDraftHost::open(core.clone(), "loaded-review".into(), None, None, false)
            .unwrap();
        b.prepare_project().unwrap();
        // Review save advances storage revision but not the edit revision.
        a.set_project_name("Edited after review".into(), revision(&a))
            .unwrap();
        assert!(core.state.lock().unwrap().prepared.is_empty());
        assert_eq!(value(&a)["content"]["submission"], Value::Null);
    }
}
