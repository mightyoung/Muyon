//! Thin product bridge. Models have no route to `confirm_user_plan`.
//! The private Android Service calls that method only from the visible review action.
use muyon_core::agent::owner::{AgentOwner, Settings as AgentSettings};
use muyon_core::agent::tools::{HostPreparedSuggestion, PreparedSuggestion, ToolsContext};
use muyon_core::{
    blobs::{BlobKind, ControlledReader},
    research::SnapshotEntry,
};
use muyon_core::{business::BusinessStore, contract::*};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    fmt,
    fs::File,
    io::Read,
    path::Path,
    sync::{Arc, Mutex},
};

mod document_bridge;
use document_bridge::DocumentBridge;
pub use document_bridge::{
    DocumentAccessRequest, DocumentEvidenceAnswerRequest, DocumentEvidenceKind,
    DocumentEvidenceUseRequest, DocumentPresentationChunkResult, DocumentPresentationOpenRequest,
    DocumentPresentationUseRequest, DocumentReadChunkResult, DocumentReadOperation,
    DocumentReadUseRequest, DocumentReaderScope,
};
#[cfg(test)]
mod document_bridge_tests;

uniffi::setup_scaffolding!();

/// Private host snapshot for a new, not-yet-released prepare API. Fields are
/// references/preconditions, never caller-issued authority or a saved assertion.
#[derive(uniffi::Record)]
pub struct LocalDraftPrepareRequest {
    pub conversation: String,
    pub project: Option<String>,
    pub namespace_id: String,
    pub draft_id: String,
    pub expected_generation: String,
    pub expected_stored_revision: String,
    pub attempt_id: String,
    pub exported_memory_revision: String,
    pub host_editor_revision: String,
    pub archive: Vec<u8>,
}

#[derive(Debug, uniffi::Error)]
pub enum ProductError {
    Failure { code: String },
}
impl fmt::Display for ProductError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Failure { code } => write!(f, "{code}"),
        }
    }
}
impl std::error::Error for ProductError {}
impl From<ContractError> for ProductError {
    fn from(error: ContractError) -> Self {
        Self::Failure {
            code: error.to_string(),
        }
    }
}
fn unavailable() -> ProductError {
    ProductError::Failure {
        code: "CORE_UNAVAILABLE".into(),
    }
}
fn encode<T: serde::Serialize>(value: &T) -> Result<String, ProductError> {
    serde_json::to_string(value).map_err(|_| unavailable())
}
fn opaque_id(prefix: &str) -> Result<String, ProductError> {
    let mut bytes = [0u8; 16];
    File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut bytes))
        .map_err(|_| unavailable())?;
    Ok(format!(
        "{prefix}:{}",
        bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
    ))
}
struct Prepared {
    command: CommandEnvelope,
    dispatched: bool,
}
struct State {
    store: DocumentBridge,
    agent: Option<AgentOwner>,
    prepared: BTreeMap<String, Prepared>,
    readers: BTreeMap<String, ControlledReader>,
    workflow: Option<muyon_core::agent::workflow::RunLedger>,
}

#[derive(uniffi::Object)]
pub struct ProductCore {
    workspace: String,
    epoch: String,
    agent_path: std::path::PathBuf,
    workflow_path: std::path::PathBuf,
    state: Mutex<State>,
}

#[uniffi::export]
impl ProductCore {
    /// HOST ONLY: root comes from Context.filesDir, never a model or file URI.
    /// Initializing is a separate visible user action, not a side effect of a query.
    #[uniffi::constructor]
    pub fn open(
        root: String,
        workspace: String,
        epoch: String,
        initialize: bool,
    ) -> Result<Arc<Self>, ProductError> {
        let root = Path::new(&root);
        if !root.is_absolute()
            || root
                .components()
                .any(|p| matches!(p, std::path::Component::ParentDir))
        {
            return Err(ContractError::InvalidIdentity.into());
        }
        if initialize {
            std::fs::create_dir_all(root).map_err(|_| unavailable())?;
        }
        let path = root.join("business-v2.sqlite");
        if initialize {
            BusinessStore::initialize(&path, &workspace)?;
        }
        let store = BusinessStore::open_existing(&path, &workspace, &epoch)?;
        // The exclusive OS owner lock has been acquired, so no predecessor can
        // still publish/read with its old epoch. Finish conservative recovery
        // before exposing any Service capability; existing refs, pins and
        // pending/unknown intents remain the authority for collection.
        store.reconcile_blobs_after_restart()?;
        store.collect_blobs()?;
        let agent_path = root.join("agent-v1.sqlite");
        let agent = if agent_path.is_file() {
            Some(AgentOwner::open(&agent_path, &workspace, &epoch).map_err(agent_error)?)
        } else {
            None
        };
        let document_store = DocumentBridge::new(store, workspace.clone(), epoch.clone());
        Ok(Arc::new(Self {
            workspace,
            epoch,
            agent_path,
            workflow_path: root.join("agent-workflows-v1.sqlite"),
            state: Mutex::new(State {
                store: document_store,
                agent,
                prepared: BTreeMap::new(),
                readers: BTreeMap::new(),
                workflow: None,
            }),
        }))
    }

    pub fn health(&self) -> String {
        json!({"protocol":1,"workspace":self.workspace,"epoch":self.epoch,
            "build_id":option_env!("MUYON_BUILD_ID").unwrap_or("unsealed"),"synthetic":false})
        .to_string()
    }
    /// HOST ONLY: explicit NEW local-workspace registration; no legacy import.
    pub fn local_draft_resolve(
        &self,
        conversation: String,
        project: Option<String>,
    ) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| ProductError::Failure {
            code: "local_draft_unavailable".into(),
        })?;
        let value =
            muyon_core::bot_drafts::resolve(&state.store, &conversation, project.as_deref())
                .map_err(|code| ProductError::Failure { code: code.into() })?;
        encode(&value)
    }

    pub fn local_draft_read(
        &self,
        conversation: String,
        project: Option<String>,
        namespace_id: String,
        draft_id: String,
        expected_generation: String,
        expected_stored_revision: String,
    ) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| ProductError::Failure {
            code: "local_draft_unavailable".into(),
        })?;
        let binding = muyon_core::bot_drafts::DraftBinding {
            namespace_id,
            draft_id,
            expected_generation,
            expected_stored_revision,
        };
        let value =
            muyon_core::bot_drafts::read(&state.store, &conversation, project.as_deref(), &binding)
                .map_err(|code| ProductError::Failure { code: code.into() })?;
        encode(&value)
    }

    /// HOST ONLY: durably register the exact original snapshot BEFORE dispatch.
    /// This neither stores the archive nor executes/replays a save after restart.
    pub fn local_draft_prepare_save(
        &self,
        request: LocalDraftPrepareRequest,
    ) -> Result<String, ProductError> {
        let LocalDraftPrepareRequest {
            conversation,
            project,
            namespace_id,
            draft_id,
            expected_generation,
            expected_stored_revision,
            attempt_id,
            exported_memory_revision,
            host_editor_revision,
            archive,
        } = request;
        let state = self.state.lock().map_err(|_| ProductError::Failure {
            code: "local_draft_unavailable".into(),
        })?;
        let binding = muyon_core::bot_drafts::DraftBinding {
            namespace_id,
            draft_id,
            expected_generation,
            expected_stored_revision,
        };
        let value = muyon_core::bot_drafts::prepare_save(
            &state.store,
            &conversation,
            project.as_deref(),
            &binding,
            &attempt_id,
            muyon_core::bot_drafts::SaveRevisions {
                exported_memory_revision: &exported_memory_revision,
                host_editor_revision: &host_editor_revision,
            },
            &archive,
        )
        .map_err(|code| ProductError::Failure { code: code.into() })?;
        encode(&value)
    }

    /// A committed receipt acknowledges only its exported snapshot. The host must
    /// compare its live reducer/scope/revision before displaying newer edits as saved.
    /// Any error after dispatch requires original-attempt lookup, never automatic resave.
    // Preserve the generated UniFFI ABI and the existing positional Service caller.
    // A request record requires a coordinated protocol/binding migration, not a lint fix.
    #[allow(clippy::too_many_arguments)]
    pub fn local_draft_save(
        &self,
        conversation: String,
        project: Option<String>,
        namespace_id: String,
        draft_id: String,
        expected_generation: String,
        expected_stored_revision: String,
        attempt_id: String,
        exported_memory_revision: String,
        archive: Vec<u8>,
    ) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| ProductError::Failure {
            code: "local_draft_unavailable".into(),
        })?;
        let binding = muyon_core::bot_drafts::DraftBinding {
            namespace_id,
            draft_id,
            expected_generation,
            expected_stored_revision,
        };
        let value = muyon_core::bot_drafts::save(
            &state.store,
            &conversation,
            project.as_deref(),
            &binding,
            &attempt_id,
            &exported_memory_revision,
            &archive,
        )
        .map_err(|code| ProductError::Failure { code: code.into() })?;
        encode(&value)
    }

    /// Queries the original only. An uncommitted preparation is atomically fenced;
    /// a queued save then refuses. Never retries or queries execution ledgers.
    pub fn local_draft_lookup_save(
        &self,
        conversation: String,
        project: Option<String>,
        namespace_id: String,
        draft_id: String,
        attempt_id: String,
    ) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| ProductError::Failure {
            code: "local_draft_unavailable".into(),
        })?;
        let value = muyon_core::bot_drafts::lookup_save(
            &state.store,
            &conversation,
            project.as_deref(),
            &namespace_id,
            &draft_id,
            &attempt_id,
        )
        .map_err(|code| ProductError::Failure { code: code.into() })?;
        encode(&value)
    }

    /// Private trusted Service only: exact existing grant references, no issuer.
    pub fn document_metadata(
        &self,
        request: DocumentAccessRequest,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.metadata(request))
    }
    pub fn document_annotations(
        &self,
        request: DocumentAccessRequest,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.annotations(request))
    }
    pub fn document_read_open(
        &self,
        request: DocumentAccessRequest,
        purpose: DocumentReadOperation,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.open(request, purpose))
    }
    pub fn document_read_check(
        &self,
        request: DocumentReadUseRequest,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.check(request))
    }
    pub fn document_read_chunk(
        &self,
        request: DocumentReadUseRequest,
        max_bytes: u32,
    ) -> Result<DocumentReadChunkResult, ProductError> {
        document_call(self, |bridge| bridge.chunk(request, max_bytes))
    }
    pub fn document_read_close(&self, request: DocumentReadUseRequest) -> Result<(), ProductError> {
        document_call(self, |bridge| bridge.close(request))
    }
    pub fn document_read_release_owner(&self, service_session: String) -> Result<(), ProductError> {
        document_call(self, |bridge| bridge.release_owner(&service_session))
    }
    /// Service lifecycle only: invalidate all document outputs and retry cleanup.
    pub fn document_read_shutdown(&self) -> Result<(), ProductError> {
        document_call(self, DocumentBridge::shutdown)
    }
    pub fn document_evidence_process(
        &self,
        request: DocumentAccessRequest,
        kind: DocumentEvidenceKind,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.process(request, kind))
    }
    pub fn document_evidence_query(
        &self,
        context: DocumentEvidenceUseRequest,
        query: String,
        limit: u32,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.query(context, query, limit))
    }
    pub fn document_evidence_quote(
        &self,
        context: DocumentEvidenceUseRequest,
        query_id: String,
        evidence_id: String,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.quote(context, query_id, evidence_id))
    }
    pub fn document_evidence_answer(
        &self,
        request: DocumentEvidenceAnswerRequest,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.answer(request))
    }
    pub fn document_evidence_close(
        &self,
        context: DocumentEvidenceUseRequest,
    ) -> Result<(), ProductError> {
        document_call(self, |bridge| bridge.close_evidence(context))
    }

    /// Synchronous real Service selection event, before asynchronous lookup.
    pub fn document_presentation_begin_selection(
        &self,
        scope: DocumentReaderScope,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.presentation_begin(scope))
    }
    pub fn document_presentation_open(
        &self,
        request: DocumentPresentationOpenRequest,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.presentation_open(request))
    }
    pub fn document_presentation_chunk(
        &self,
        request: DocumentPresentationUseRequest,
        max_bytes: u32,
    ) -> Result<DocumentPresentationChunkResult, ProductError> {
        document_call(self, |bridge| bridge.presentation_chunk(request, max_bytes))
    }
    pub fn document_presentation_check(
        &self,
        request: DocumentPresentationUseRequest,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.presentation_check(request))
    }
    pub fn document_presentation_advance_frame(
        &self,
        request: DocumentPresentationUseRequest,
    ) -> Result<String, ProductError> {
        document_call(self, |bridge| bridge.presentation_advance(request))
    }
    pub fn document_presentation_close(
        &self,
        request: DocumentPresentationUseRequest,
    ) -> Result<(), ProductError> {
        document_call(self, |bridge| bridge.presentation_close(request))
    }
    /// Trusted Service administrative drain; never expose as a client route.
    pub fn document_presentation_take_invalidations(&self) -> Result<String, ProductError> {
        document_call(self, DocumentBridge::take_invalidations)
    }

    pub fn agent_availability(&self) -> Result<String, ProductError> {
        encode(&muyon_core::agent::availability(None, None))
    }
    pub fn agent_read(
        &self,
        request: String,
        project_id: Option<String>,
    ) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        let scope = muyon_core::agent::ReadScope::current(&state.store, project_id.as_deref())?;
        encode(&muyon_core::agent::read_business(
            &state.store,
            &scope,
            &request,
        )?)
    }
    /// HOST ONLY: visible settings confirmation; no credential bytes cross FFI.
    pub fn agent_configure(&self, settings_json: String) -> Result<String, ProductError> {
        let settings: AgentSettings = serde_json::from_value(decode_json(&settings_json)?)
            .map_err(|_| ContractError::InvalidPayload)?;
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        if state.agent.is_none() {
            if !self.agent_path.exists() {
                AgentOwner::initialize(&self.agent_path, &self.workspace).map_err(agent_error)?;
            }
            state.agent = Some(
                AgentOwner::open(&self.agent_path, &self.workspace, &self.epoch)
                    .map_err(agent_error)?,
            );
        }
        encode(
            &state
                .agent
                .as_ref()
                .ok_or_else(unavailable)?
                .configure_trusted(settings)
                .map_err(agent_error)?,
        )
    }
    pub fn agent_prepare(
        &self,
        conversation: String,
        text: String,
        search: bool,
        count: u32,
    ) -> Result<String, ProductError> {
        self.agent_call(|owner| {
            if search {
                owner.prepare_search(&conversation, &text, u64::from(count))
            } else {
                owner.prepare_chat(&conversation, &text, None)
            }
        })
    }
    /// Host UI facade. Project comes from the live selected session, not action JSON.
    pub fn agent_prepare_scoped(
        &self,
        conversation: String,
        text: String,
        search: bool,
        count: u32,
        session: String,
        project: Option<String>,
    ) -> Result<String, ProductError> {
        use muyon_core::agent::workflow::{RunLedger, RunScope};
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        let scope = RunScope::current(&state.store, &session, &conversation, project.as_deref())
            .map_err(agent_error)?;
        if state.workflow.is_none() {
            state.workflow = Some(
                RunLedger::open(&self.workflow_path, &self.workspace, &self.epoch)
                    .map_err(agent_error)?,
            );
        }
        let owner = state
            .agent
            .as_ref()
            .ok_or_else(|| agent_error("agent_not_configured"))?;
        for request in state
            .workflow
            .as_ref()
            .ok_or_else(unavailable)?
            .remote_requests(&scope)
            .map_err(agent_error)?
        {
            for observation in owner.request_chain(&request).map_err(agent_error)? {
                if matches!(
                    observation.status.as_str(),
                    "reserved" | "unknown" | "tool_pending"
                ) {
                    return Err(agent_error("conversation_original_outcome_required"));
                }
            }
        }
        encode(
            &if search {
                owner.prepare_search(&conversation, &text, u64::from(count))
            } else {
                owner.prepare_chat(&conversation, &text, None)
            }
            .map_err(agent_error)?,
        )
    }
    pub fn agent_workflow(
        &self,
        action: String,
        session: String,
        conversation: String,
        project: Option<String>,
    ) -> Result<String, ProductError> {
        use muyon_core::agent::workflow::{RunLedger, RunScope};
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        let scope = RunScope::current(&state.store, &session, &conversation, project.as_deref())
            .map_err(agent_error)?;
        if state.workflow.is_none() {
            state.workflow = Some(
                RunLedger::open(&self.workflow_path, &self.workspace, &self.epoch)
                    .map_err(agent_error)?,
            );
        }
        let State {
            store,
            workflow,
            agent,
            ..
        } = &mut *state;
        let ledger = workflow.as_mut().ok_or_else(unavailable)?;
        let mut first = ledger
            .execute(&action, store, &scope)
            .map_err(agent_error)?;
        // The observation is authoritative owner data, never a model/UI status update.
        let action_value = serde_json::from_str::<Value>(&action)
            .map_err(|_| agent_error("workflow_action_invalid"))?;
        let snapshot = action_value["action"] == "snapshot";
        let revoke = action_value["action"] == "cancel"
            || (action_value["action"] == "set_skill" && action_value["enabled"] == false);
        if let (true, Some(owner), Some(runs)) = (
            snapshot,
            agent.as_ref(),
            first.get("runs").and_then(Value::as_array),
        ) {
            for run in runs {
                if !run["can_control"].as_bool().unwrap_or(false) {
                    continue;
                }
                if let (Some(id), Some(request)) =
                    (run["id"].as_str(), run["remote_request_id"].as_str())
                {
                    let observations = owner.request_chain(request).map_err(agent_error)?;
                    ledger
                        .observe_remote_chain(&scope, id, &observations)
                        .map_err(agent_error)?;
                }
            }
            return encode(
                &ledger
                    .execute(&action, store, &scope)
                    .map_err(agent_error)?,
            );
        }
        if let (Some(owner), Some(requests)) =
            (agent.as_ref(), first["remote_request_ids"].as_array())
        {
            let mut actual = std::collections::BTreeSet::new();
            for request in requests {
                for observation in owner
                    .request_chain(request.as_str().ok_or_else(unavailable)?)
                    .map_err(agent_error)?
                {
                    if revoke {
                        owner
                            .cancel_trusted(&observation.request_id)
                            .map_err(agent_error)?;
                    }
                    actual.insert(observation.request_id);
                }
            }
            first["remote_request_ids"] = json!(actual);
        }
        encode(&first)
    }
    /// Called only on the existing chat control queue. No transport or price bypass.
    pub fn agent_workflow_prepare(
        &self,
        run_id: String,
        session: String,
        conversation: String,
        project: Option<String>,
        generation: String,
    ) -> Result<String, ProductError> {
        use muyon_core::agent::workflow::RunScope;
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        let scope = RunScope::current(&state.store, &session, &conversation, project.as_deref())
            .map_err(agent_error)?;
        let ledger = state
            .workflow
            .as_ref()
            .ok_or_else(|| agent_error("workflow_not_found"))?;
        let context = ledger
            .remote_context(&scope, &run_id)
            .map_err(agent_error)?;
        let owner = state
            .agent
            .as_ref()
            .ok_or_else(|| agent_error("agent_not_configured"))?;
        owner
            .ensure_conversation_resolved(
                context["root_conversation"]
                    .as_str()
                    .ok_or_else(unavailable)?,
            )
            .map_err(agent_error)?;
        for request in ledger.remote_requests(&scope).map_err(agent_error)? {
            for observation in owner.request_chain(&request).map_err(agent_error)? {
                if matches!(
                    observation.status.as_str(),
                    "reserved" | "unknown" | "tool_pending"
                ) {
                    return Err(agent_error("conversation_original_outcome_required"));
                }
            }
        }
        let child_conversation = context["conversation_id"]
            .as_str()
            .ok_or_else(unavailable)?;
        let input = format!(
            "任务：{}\n\n已选择的技能说明（不授予额外权限）：\n{}",
            context["task"].as_str().ok_or_else(unavailable)?,
            context["skill_body"].as_str().ok_or_else(unavailable)?
        );
        let allowed: Vec<&str> = context["tool_names"]
            .as_array()
            .ok_or_else(unavailable)?
            .iter()
            .map(|name| name.as_str().ok_or_else(unavailable))
            .collect::<Result<_, _>>()?;
        let plan = owner
            .prepare_chat_restricted(child_conversation, &input, None, &allowed)
            .map_err(agent_error)?;
        let tool_scope = muyon_core::agent::tools::ToolsContext::current(
            &state.store,
            &session,
            &generation,
            project.as_deref(),
        )
        .map_err(agent_error)?;
        owner
            .bind_tool_scope_trusted(&plan.request_id, &tool_scope)
            .map_err(agent_error)?;
        state
            .workflow
            .as_mut()
            .ok_or_else(unavailable)?
            .bind_remote_plan(&scope, &run_id, &plan)
            .map_err(agent_error)?;
        let mut result = serde_json::to_value(&plan).map_err(|_| unavailable())?;
        result["workflow_id"] = json!(run_id);
        result["input_preview"] = json!(input);
        result["skill_digest"] = context["skill_digest"].clone();
        result["skill_id"] = context["skill_id"].clone();
        encode(&result)
    }
    pub fn agent_confirm(
        &self,
        request: String,
        configuration: String,
    ) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        authorize_agent_request(&state, &request)?;
        encode(
            &state
                .agent
                .as_ref()
                .ok_or_else(unavailable)?
                .confirm_trusted(&request, &configuration)
                .map_err(agent_error)?,
        )
    }
    /// Private transport port. Never registered as a UI/model operation.
    pub fn agent_claim(
        &self,
        request: String,
        configuration: String,
        generation: String,
    ) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        authorize_agent_request(&state, &request)?;
        encode(
            &state
                .agent
                .as_ref()
                .ok_or_else(unavailable)?
                .claim_dispatch(&request, &configuration, &generation)
                .map_err(agent_error)?,
        )
    }
    pub fn agent_allowed(
        &self,
        request: String,
        configuration: String,
        generation: String,
    ) -> bool {
        self.state
            .lock()
            .ok()
            .and_then(|state| {
                state.agent.as_ref().map(|owner| {
                    authorize_agent_request(&state, &request).is_ok()
                        && owner.dispatch_allowed(&request, &configuration, &generation)
                })
            })
            .unwrap_or(false)
    }
    /// Private transport port: UI cannot provide a fabricated usage/answer.
    pub fn agent_settle(&self, request: String, body: String) -> Result<String, ProductError> {
        self.agent_call(|owner| owner.settle_response(&request, &body))
    }
    pub fn agent_diagnostic(
        &self,
        request: String,
        stage: String,
        http_status: Option<u16>,
    ) -> Result<String, ProductError> {
        self.agent_call(|owner| owner.record_diagnostic(&request, &stage, http_status))
    }
    pub fn agent_lookup(&self, request: String) -> Result<String, ProductError> {
        self.agent_call(|owner| owner.lookup(&request))
    }
    pub fn agent_cancel(&self, request: String) -> Result<String, ProductError> {
        self.agent_call(|owner| owner.cancel_trusted(&request))
    }
    pub fn agent_budget(&self) -> Result<String, ProductError> {
        self.agent_call(AgentOwner::budget)
    }

    /// Private Service port. Session and generation come from the live lease and
    /// memory credential owner, never from model arguments.
    #[allow(clippy::too_many_arguments)]
    pub fn agent_tool_step(
        &self,
        action: String,
        request: String,
        session: String,
        generation: String,
        project: Option<String>,
        value: String,
        digest: String,
    ) -> Result<String, ProductError> {
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        authorize_agent_request(&state, &request)?;
        let context =
            ToolsContext::current(&state.store, &session, &generation, project.as_deref())
                .map_err(agent_error)?;
        let State {
            store,
            agent,
            prepared,
            ..
        } = &mut *state;
        let owner = agent
            .as_ref()
            .ok_or_else(|| agent_error("agent_not_configured"))?;
        match action.as_str() {
            "bind" => {
                owner
                    .bind_tool_scope_trusted(&request, &context)
                    .map_err(agent_error)?;
                encode(&())
            }
            "review_read" => encode(
                &owner
                    .review_tool_read(store, &context, &request)
                    .map_err(agent_error)?,
            ),
            "approve_read" => {
                owner
                    .approve_tool_read_trusted(store, &context, &request, &digest)
                    .map_err(agent_error)?;
                encode(&())
            }
            "prepare_suggestion" => {
                if prepared.len() >= 128 {
                    return Err(ContractError::TextLimit.into());
                }
                let mut envelope = None;
                let suggestion = owner
                    .prepare_tool_suggestion(&context, &request, |operation, revision, project| {
                        let command = prepare_envelope(
                            &self.workspace,
                            &self.epoch,
                            operation,
                            project.map(str::to_owned),
                            revision,
                        )
                        .map_err(|_| "tool_plan_invalid")?;
                        let result = HostPreparedSuggestion {
                            view: PreparedSuggestion {
                                plan_id: command.plan_id.clone(),
                                summary: "Review the complete business operation before confirming"
                                    .into(),
                            },
                            intent_id: command.intent_id.clone(),
                            binding_digest: command
                                .binding_digest()
                                .map_err(|_| "tool_plan_invalid")?,
                        };
                        envelope = Some(command);
                        Ok(result)
                    })
                    .map_err(agent_error)?;
                let command = envelope.ok_or_else(unavailable)?;
                store.prepare_review_trusted(&command)?;
                let reply = json!({"plan_id":suggestion.plan_id,"summary":suggestion.summary,"business_preview":command});
                prepared.insert(
                    command.plan_id.clone(),
                    Prepared {
                        command,
                        dispatched: false,
                    },
                );
                encode(&reply)
            }
            "review_suggestion" => encode(
                &owner
                    .review_tool_suggestion_result(store, &context, &request, &value)
                    .map_err(agent_error)?,
            ),
            "confirm_suggestion" => {
                owner
                    .validate_tool_suggestion_trusted(&context, &request, &value)
                    .map_err(agent_error)?;
                confirm_prepared(store, prepared, &value)
            }
            "approve_suggestion" => {
                owner
                    .approve_tool_suggestion_result_trusted(
                        store, &context, &request, &value, &digest,
                    )
                    .map_err(agent_error)?;
                encode(&())
            }
            "followup" => encode(
                &owner
                    .prepare_tool_followup_trusted(store, &context, &request, None)
                    .map_err(agent_error)?,
            ),
            _ => Err(ContractError::InvalidPayload.into()),
        }
    }

    /// Durable review preparation. No business grant, pending row or effect is created.
    /// The native plan, exact raw parameters and intent remain stable for review.
    pub fn prepare(
        &self,
        operation_json: String,
        project_id: Option<String>,
        expected_revision: String,
    ) -> Result<String, ProductError> {
        let command: Operation = serde_json::from_value(decode_json(&operation_json)?)
            .map_err(|_| ContractError::InvalidPayload)?;
        let envelope = prepare_envelope(
            &self.workspace,
            &self.epoch,
            command,
            project_id,
            Revision::parse(&expected_revision)?,
        )?;
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        if state.prepared.len() >= 128 {
            return Err(ContractError::TextLimit.into());
        }
        let reply = encode(&envelope)?;
        state.store.prepare_review_trusted(&envelope)?;
        state.prepared.insert(
            envelope.plan_id.clone(),
            Prepared {
                command: envelope,
                dispatched: false,
            },
        );
        Ok(reply)
    }

    /// HOST ONLY, called by a visible user-confirmation callback, not the generic
    /// tool dispatcher. Caller sends only the already reviewed opaque plan id.
    pub fn confirm_user_plan(&self, plan_id: String) -> Result<String, ProductError> {
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        let State {
            store, prepared, ..
        } = &mut *state;
        confirm_prepared(store, prepared, &plan_id)
    }

    pub fn lookup_original(&self, intent_id: String) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        lookup_json(&state.store, &intent_id)
    }

    pub fn list_suppliers(&self, limit: u32, offset: u32) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        encode(&state.store.suppliers(limit, offset)?)
    }

    pub fn supplier(&self, supplier_id: String) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        encode(&state.store.supplier(&supplier_id)?)
    }

    pub fn cancel_original(&self, intent_id: String) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        encode(&state.store.cancel_trusted(&intent_id)?)
    }
    pub fn discard_plan(&self, plan_id: String) -> Result<(), ProductError> {
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        state.prepared.remove(&plan_id);
        Ok(())
    }
    pub fn archive_manifest(&self, upload_id: String) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        if state.store.lookup_upload(&upload_id)?.kind != Some(BlobKind::Archive) {
            return Err(ContractError::InvalidPayload.into());
        }
        let mut reader = state.store.open_upload_reader(&upload_id)?;
        let parsed = (|| -> Result<String, ProductError> {
            let mut bytes = Vec::new();
            loop {
                let chunk = state.store.read_blob_chunk(&mut reader, 65536)?;
                if chunk.is_empty() {
                    break;
                }
                if bytes.len() + chunk.len() > 150 * 1024 * 1024 {
                    return Err(ContractError::TextLimit.into());
                }
                bytes.extend_from_slice(&chunk);
            }
            let manifest = muyon_core::archive::parse_archive(&bytes)?;
            let entries = manifest.to_contract_entries(reader.source())?;
            // The full manifest is checked in Rust. Return only the bounded
            // aggregate; the final seal verifies every decoded member again.
            encode(
                &json!({"entry_count":entries.len(),"archive_digest":manifest.archive_digest,
                "expanded_bytes":manifest.entries.iter().map(|e|e.expanded_length).sum::<u64>()}),
            )
        })();
        let closed = state.store.close_blob_reader(reader);
        closed?;
        parsed
    }

    pub fn list_deleted_suppliers(&self, limit: u32, offset: u32) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        encode(&state.store.deleted_suppliers(limit, offset)?)
    }
    pub fn list_projects(&self, limit: u32, offset: u32) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        encode(&state.store.projects(limit, offset)?)
    }
    pub fn list_papers(
        &self,
        project_id: String,
        limit: u32,
        offset: u32,
    ) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        let rows = state.store.papers(&project_id, limit, offset)?;
        encode(
            &rows
                .iter()
                .map(|row| paper_projection(row, false))
                .collect::<Vec<_>>(),
        )
    }
    pub fn research_sources(&self, project_id: String) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        encode(&state.store.research_sources(&project_id)?)
    }
    pub fn paper(&self, project_id: String, paper_id: String) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        encode(&paper_projection(
            &state.store.paper(&project_id, &paper_id)?,
            true,
        ))
    }
    pub fn begin_upload(&self, project_id: String) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        encode(&state.store.begin_upload(&project_id)?)
    }
    pub fn append_upload(&self, upload_id: String, bytes: Vec<u8>) -> Result<u64, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        Ok(state.store.append_chunk(&upload_id, &bytes)?)
    }
    pub fn finish_upload(&self, upload_id: String, kind: String) -> Result<String, ProductError> {
        let kind = match kind.as_str() {
            "pdf" => BlobKind::Pdf,
            "document" => BlobKind::Document,
            "archive" => BlobKind::Archive,
            _ => return Err(ContractError::InvalidPayload.into()),
        };
        let state = self.state.lock().map_err(|_| unavailable())?;
        encode(&state.store.finish_blob(&upload_id, kind)?)
    }
    pub fn abort_upload(&self, upload_id: String) -> Result<(), ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        Ok(state.store.abort_upload(&upload_id)?)
    }
    pub fn lookup_upload(&self, upload_id: String) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        encode(&state.store.lookup_upload(&upload_id)?)
    }
    /// Only upload ids created by the trusted file host are accepted. Contents
    /// are re-read and validated in Rust, never supplied as a model manifest.
    pub fn seal_snapshot(
        &self,
        project_id: String,
        entries_json: String,
        archive_upload_id: Option<String>,
    ) -> Result<String, ProductError> {
        let entries: Vec<SnapshotEntry> = serde_json::from_value(decode_json(&entries_json)?)
            .map_err(|_| ContractError::InvalidPayload)?;
        let state = self.state.lock().map_err(|_| unavailable())?;
        let sealed = state.store.seal_research_snapshot(
            &project_id,
            &entries,
            archive_upload_id.as_deref(),
        )?;
        // Large JSONL records stay in the immutable snapshot. The command uses
        // its source reference, never an unbounded Binder response.
        encode(
            &json!({"snapshot_upload_id":sealed.snapshot_upload_id,"snapshot":sealed.snapshot,
            "records_digest":sealed.records_digest,"record_count":sealed.records.len(),"layout":sealed.layout,"skill_root":sealed.skill_root}),
        )
    }
    pub fn open_attachment(
        &self,
        project_id: String,
        paper_id: String,
        digest: String,
    ) -> Result<String, ProductError> {
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        if state.readers.len() >= 16 {
            return Err(ContractError::TextLimit.into());
        }
        let reader = state
            .store
            .open_paper_attachment(&project_id, &paper_id, &digest)?;
        let id = opaque_id("reader")?;
        let response = encode(&json!({"reader_id":id,"source":reader.source()}))?;
        state.readers.insert(id, reader);
        Ok(response)
    }
    pub fn open_upload_reader(&self, upload_id: String) -> Result<String, ProductError> {
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        if state.readers.len() >= 16 {
            return Err(ContractError::TextLimit.into());
        }
        let reader = state.store.open_upload_reader(&upload_id)?;
        let id = opaque_id("reader")?;
        let response = encode(&json!({"reader_id":id,"source":reader.source()}))?;
        state.readers.insert(id, reader);
        Ok(response)
    }
    pub fn read_attachment(
        &self,
        reader_id: String,
        max_bytes: u32,
    ) -> Result<Vec<u8>, ProductError> {
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        let State { store, readers, .. } = &mut *state;
        let reader = readers.get_mut(&reader_id).ok_or(ContractError::NotFound)?;
        Ok(store.read_blob_chunk(reader, max_bytes as usize)?)
    }
    pub fn close_attachment(&self, reader_id: String) -> Result<(), ProductError> {
        let mut state = self.state.lock().map_err(|_| unavailable())?;
        let reader = state
            .readers
            .remove(&reader_id)
            .ok_or(ContractError::NotFound)?;
        Ok(state.store.close_blob_reader(reader)?)
    }
}

fn document_call<T>(
    core: &ProductCore,
    operation: impl FnOnce(&mut DocumentBridge) -> Result<T, ProductError>,
) -> Result<T, ProductError> {
    let mut state = core.state.lock().map_err(|_| ProductError::Failure {
        code: "DOCUMENT_UNAVAILABLE".into(),
    })?;
    let result = operation(&mut state.store);
    state.store.collect_invalidations();
    result
}

fn agent_error(code: &'static str) -> ProductError {
    ProductError::Failure { code: code.into() }
}

fn authorize_agent_request(state: &State, request: &str) -> Result<(), ProductError> {
    let owner = state.agent.as_ref().ok_or_else(unavailable)?;
    owner
        .ensure_request_resolved(request)
        .map_err(agent_error)?;
    if let Some(ledger) = &state.workflow {
        ledger
            .authorize_request(owner, request)
            .map_err(agent_error)?;
    }
    Ok(())
}
fn confirm_prepared(
    store: &BusinessStore,
    plans: &mut BTreeMap<String, Prepared>,
    plan_id: &str,
) -> Result<String, ProductError> {
    let prepared = plans.get_mut(plan_id).ok_or(ContractError::NotFound)?;
    let command = prepared.command.clone();
    if prepared.dispatched {
        return lookup_json(store, &command.intent_id);
    }
    store.claim_review_trusted(&command)?;
    // Claim before issuing any authority. Unknown results never grant another try.
    prepared.dispatched = true;
    store.issue_grant_trusted(&command, None)?;
    encode(&store.execute(&command)?)
}
fn prepare_envelope(
    workspace: &str,
    epoch: &str,
    command: Operation,
    project_id: Option<String>,
    expected_revision: Revision,
) -> Result<CommandEnvelope, ProductError> {
    let mut envelope = CommandEnvelope {
        protocol_version: PROTOCOL_VERSION,
        business_version: BUSINESS_VERSION,
        intent_id: opaque_id("intent")?,
        scope: Scope {
            workspace_id: workspace.into(),
            project_id,
        },
        expected_revision,
        authority: AuthorityBinding {
            grant_id: opaque_id("grant")?,
            generation: Revision::new(1),
            owner_epoch: epoch.into(),
        },
        plan_id: opaque_id("plan")?,
        plan_digest: "0".repeat(64),
        command,
    };
    envelope.plan_digest = envelope.expected_plan_digest()?;
    envelope.validate()?;
    Ok(envelope)
}
impl ProductCore {
    fn agent_call<T: serde::Serialize>(
        &self,
        action: impl FnOnce(&AgentOwner) -> Result<T, &'static str>,
    ) -> Result<String, ProductError> {
        let state = self.state.lock().map_err(|_| unavailable())?;
        let owner = state
            .agent
            .as_ref()
            .ok_or_else(|| agent_error("agent_not_configured"))?;
        encode(&action(owner).map_err(agent_error)?)
    }
}

fn paper_projection(row: &muyon_core::research::PaperRecord, detail: bool) -> Value {
    let preview: String = if detail {
        row.raw_json.chars().take(8192).collect()
    } else {
        String::new()
    };
    let title: String = row.title.chars().take(500).collect();
    let source_id_small = row
        .source_record_id
        .as_ref()
        .is_none_or(|id| id.to_string().len() <= 2048);
    json!({"id":row.id,"project_id":row.project_id,"kind":row.kind,"title":title,
        "title_truncated":title.len()!=row.title.len(),"source_id":row.source_id,
        "source_record_id":if source_id_small {row.source_record_id.clone()} else {None},
        "source_record_id_truncated":!source_id_small,"source_revision":row.source_revision,
        "revision":row.revision,"manual":row.manual,"attachments":row.attachments.iter().take(100).collect::<Vec<_>>(),
        "attachment_count":row.attachments.len(),"attachments_truncated":row.attachments.len()>100,
        "raw_json":preview,"raw_json_truncated":preview.len()!=row.raw_json.len(),
        "raw_json_byte_length":row.raw_json.len().to_string()})
}

fn lookup_json(store: &BusinessStore, intent: &str) -> Result<String, ProductError> {
    match store.lookup(intent) {
        Ok(result)
            if result.status == ExecutionStatus::Unknown
                && result.error == Some(ContractError::NotFound)
                && store.seal_unclaimed_review_trusted(intent)? =>
        {
            encode(&json!({"status":"not_submitted","receipt":Value::Null,
                "error":"confirmation_not_received","recovery_action":"edit_new_draft"}))
        }
        Ok(result) => encode(&result),
        Err(ContractError::NotFound) => encode(&json!({"status":"unknown","receipt":Value::Null,
            "error":"not_found","recovery_action":"query_original"})),
        Err(error) => Err(error.into()),
    }
}

#[uniffi::export]
pub fn product_protocol_version() -> u32 {
    PROTOCOL_VERSION
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn another_root_and_ordinary_chat_cannot_bypass_an_unknown_child() {
        use muyon_core::agent::{
            owner::{HostedCostBound, HostedCostVerifier},
            workflow::RunScope,
        };
        struct FixtureProof;
        impl HostedCostVerifier for FixtureProof {
            fn prove(
                &self,
                _: &[u8],
                _: &str,
            ) -> muyon_core::agent::owner::Result<HostedCostBound> {
                HostedCostBound::verified(16384, 128)
            }
        }
        let path = root();
        let core =
            ProductCore::open(path.clone(), "workspace".into(), "epoch".into(), true).unwrap();
        core.agent_configure(json!({"credential_generation":"generation","cap_micro_cny":"1000000","max_calls":"10","chat":true,"search":false,"price_revision":muyon_core::agent::owner::PRICE_REVISION}).to_string()).unwrap();
        let action = |value: Value| -> Value {
            serde_json::from_str(
                &core
                    .agent_workflow(
                        value.to_string(),
                        "session".into(),
                        "parent-chat".into(),
                        None,
                    )
                    .unwrap(),
            )
            .unwrap()
        };
        let first =
            action(json!({"action":"create_root","title":"first","task":"inspect suppliers"}));
        let child = action(
            json!({"action":"create_child","root_id":first["id"],"skill_id":"supplier-overview","task":"read","executor":"remote_chat","arguments":{"limit":1,"offset":0}}),
        );
        let original = {
            let mut state = core.state.lock().unwrap();
            let scope = RunScope::current(&state.store, "session", "parent-chat", None).unwrap();
            let context = state
                .workflow
                .as_ref()
                .unwrap()
                .remote_context(&scope, child["id"].as_str().unwrap())
                .unwrap();
            let plan = state
                .agent
                .as_ref()
                .unwrap()
                .prepare_chat_restricted(
                    context["conversation_id"].as_str().unwrap(),
                    "fixture child",
                    Some(&FixtureProof),
                    &["supplier_list"],
                )
                .unwrap();
            state
                .workflow
                .as_mut()
                .unwrap()
                .bind_remote_plan(&scope, child["id"].as_str().unwrap(), &plan)
                .unwrap();
            let owner = state.agent.as_ref().unwrap();
            owner
                .confirm_trusted(&plan.request_id, &plan.configuration_id)
                .unwrap();
            owner
                .claim_dispatch(&plan.request_id, &plan.configuration_id, "generation")
                .unwrap();
            plan
        };
        let second =
            action(json!({"action":"create_root","title":"second","task":"another request"}));
        let next = action(
            json!({"action":"create_child","root_id":second["id"],"skill_id":"supplier-overview","task":"read","executor":"remote_chat","arguments":{"limit":1,"offset":0}}),
        );
        assert!(core
            .agent_workflow_prepare(
                next["id"].as_str().unwrap().into(),
                "session".into(),
                "parent-chat".into(),
                None,
                "generation".into()
            )
            .unwrap_err()
            .to_string()
            .contains("conversation_original_outcome_required"));
        assert!(core
            .agent_prepare_scoped(
                "parent-chat".into(),
                "ordinary new request".into(),
                false,
                1,
                "session".into(),
                None
            )
            .unwrap_err()
            .to_string()
            .contains("conversation_original_outcome_required"));
        let state = core.state.lock().unwrap();
        let owner = state.agent.as_ref().unwrap();
        assert_eq!(
            owner.lookup(&original.request_id).unwrap().status,
            "unknown"
        );
        assert_eq!(
            owner.budget().unwrap().held_micro_cny,
            original.reserved_micro_cny
        );
        drop(state);
        drop(core);
        std::fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn child_plan_stays_blocked_and_cannot_bypass_an_unknown_root_request() {
        use muyon_core::agent::owner::{HostedCostBound, HostedCostVerifier};
        struct FixtureProof;
        impl HostedCostVerifier for FixtureProof {
            fn prove(
                &self,
                _: &[u8],
                _: &str,
            ) -> muyon_core::agent::owner::Result<HostedCostBound> {
                HostedCostBound::verified(16384, 128)
            }
        }
        let path = root();
        let core =
            ProductCore::open(path.clone(), "workspace".into(), "epoch".into(), true).unwrap();
        core.agent_configure(json!({"credential_generation":"generation","cap_micro_cny":"1000000","max_calls":"10","chat":true,"search":false,"price_revision":muyon_core::agent::owner::PRICE_REVISION}).to_string()).unwrap();
        let action = |value: Value| -> Value {
            serde_json::from_str(
                &core
                    .agent_workflow(
                        value.to_string(),
                        "session".into(),
                        "parent-chat".into(),
                        None,
                    )
                    .unwrap(),
            )
            .unwrap()
        };
        let parent = action(json!({"action":"create_root","title":"分派","task":"检查供应商"}));
        let child = action(
            json!({"action":"create_child","root_id":parent["id"],"skill_id":"supplier-overview","task":"只读供应商","executor":"remote_chat","arguments":{"limit":10,"offset":0}}),
        );
        let plan: Value = serde_json::from_str(
            &core
                .agent_workflow_prepare(
                    child["id"].as_str().unwrap().into(),
                    "session".into(),
                    "parent-chat".into(),
                    None,
                    "generation".into(),
                )
                .unwrap(),
        )
        .unwrap();
        assert_eq!(plan["send_allowed"], false);
        assert_eq!(plan["reserved_micro_cny"], "0");
        assert_ne!(plan["conversation_id"], "parent-chat");
        for _ in 0..3 {
            let snapshot =
                action(json!({"action":"snapshot","root_id":parent["id"],"after_seq":0}));
            assert_eq!(
                snapshot["runs"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .find(|r| r["id"] == child["id"])
                    .unwrap()["status"],
                "blocked"
            );
        }
        let pending = {
            let state = core.state.lock().unwrap();
            let owner = state.agent.as_ref().unwrap();
            let pending = owner
                .prepare_chat(
                    "parent-chat",
                    "unresolved root fixture",
                    Some(&FixtureProof),
                )
                .unwrap();
            owner
                .confirm_trusted(&pending.request_id, &pending.configuration_id)
                .unwrap();
            owner
                .claim_dispatch(&pending.request_id, &pending.configuration_id, "generation")
                .unwrap();
            pending
        };
        let other = action(
            json!({"action":"create_child","root_id":parent["id"],"skill_id":"supplier-overview","task":"另一项任务","executor":"remote_chat","arguments":{"limit":10,"offset":0}}),
        );
        let failure = core
            .agent_workflow_prepare(
                other["id"].as_str().unwrap().into(),
                "session".into(),
                "parent-chat".into(),
                None,
                "generation".into(),
            )
            .unwrap_err();
        assert!(failure
            .to_string()
            .contains("conversation_original_outcome_required"));
        let state = core.state.lock().unwrap();
        let original = state
            .agent
            .as_ref()
            .unwrap()
            .lookup(&pending.request_id)
            .unwrap();
        assert_eq!(original.status, "unknown");
        assert!(original.attempted);
        assert!(original.reserved_micro_cny.value() > 0);
        drop(state);
        drop(core);
        std::fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn configuring_a_new_budget_never_manufactures_pricing_authority_or_sends() {
        let root = root();
        let core =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-1".into(), true).unwrap();
        assert!(core.agent_budget().is_err());
        assert!(!std::path::Path::new(&root).join("agent-v1.sqlite").exists());
        core.agent_configure(json!({"credential_generation":"generation-1","cap_micro_cny":"50000",
            "max_calls":"2","chat":true,"search":true,"price_revision":muyon_core::agent::owner::PRICE_REVISION}).to_string()).unwrap();
        let mut plans = Vec::new();
        for search in [false, true] {
            let plan: Value = serde_json::from_str(
                &core
                    .agent_prepare("conversation".into(), "你好".into(), search, 5)
                    .unwrap(),
            )
            .unwrap();
            assert_eq!(plan["send_allowed"], false);
            assert_eq!(plan["reserved_micro_cny"], "0");
            if !search {
                let request = plan["request_id"].as_str().unwrap().to_owned();
                core.agent_tool_step(
                    "bind".into(),
                    request.clone(),
                    "live-session".into(),
                    "generation-1".into(),
                    None,
                    "".into(),
                    "".into(),
                )
                .unwrap();
                for action in ["review_read", "prepare_suggestion", "followup"] {
                    assert!(core
                        .agent_tool_step(
                            action.into(),
                            request.clone(),
                            "live-session".into(),
                            "generation-1".into(),
                            None,
                            "".into(),
                            "".into()
                        )
                        .is_err());
                }
                assert!(core.state.lock().unwrap().prepared.is_empty());
            }
            assert!(core
                .agent_confirm(
                    plan["request_id"].as_str().unwrap().into(),
                    plan["configuration_id"].as_str().unwrap().into()
                )
                .is_err());
            plans.push(plan);
        }
        let budget: Value = serde_json::from_str(&core.agent_budget().unwrap()).unwrap();
        assert_eq!(budget["held_micro_cny"], "0");
        assert_eq!(budget["used_calls"], "0");
        drop(core);
        let reopened =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-2".into(), false).unwrap();
        assert_eq!(
            serde_json::from_str::<Value>(&reopened.agent_budget().unwrap()).unwrap(),
            budget
        );
        for plan in plans {
            assert!(reopened
                .agent_claim(
                    plan["request_id"].as_str().unwrap().into(),
                    plan["configuration_id"].as_str().unwrap().into(),
                    "generation-1".into()
                )
                .is_err());
        }
        drop(reopened);
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn long_unicode_pages_are_bounded_and_the_201st_supplier_is_accessible() {
        let root = root();
        let core =
            ProductCore::open(root.clone(), "workspace".into(), "epoch".into(), true).unwrap();
        for n in 0..201 {
            let plan: Value = serde_json::from_str(&core.prepare(json!({"operation":"supplier_create",
                "supplier_id":format!("supplier-{n:04}"),"payload":{
                    "name":format!("{:04}{}",n,"名".repeat(196)),
                    "aliases":(0..20).map(|i|format!("{i:02}{}","别".repeat(198))).collect::<Vec<_>>(),
                    "categories":(0..20).map(|i|format!("{i:02}{}","类".repeat(98))).collect::<Vec<_>>(),
                    "address":"地".repeat(500),"notes":"注".repeat(1900),"rating_note":"评".repeat(500)
                }}).to_string(),None,"0".into()).unwrap()).unwrap();
            let id = plan["plan_id"].as_str().unwrap().to_owned();
            let result: Value =
                serde_json::from_str(&core.confirm_user_plan(id.clone()).unwrap()).unwrap();
            assert_eq!(result["status"], "committed");
            core.discard_plan(id).unwrap();
        }
        let first = core.list_suppliers(10, 0).unwrap();
        assert!(first.len() < 768 * 1024);
        assert_eq!(
            serde_json::from_str::<Value>(&first)
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            10
        );
        let tail: Value = serde_json::from_str(&core.list_suppliers(10, 200).unwrap()).unwrap();
        assert_eq!(tail.as_array().unwrap().len(), 1);
        assert_eq!(tail[0]["id"], "supplier-0200");
        assert_eq!(tail[0]["payload"]["notes"], "注".repeat(1900));
        drop(core);
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn imported_raw_metadata_is_preserved_but_never_an_unbounded_binder_reply() {
        let row = muyon_core::research::PaperRecord {
            id: "paper".into(),
            project_id: "project".into(),
            kind: "papers".into(),
            title: "题".repeat(2000),
            raw_json: "🧪".repeat(500_000),
            source_id: Some("source".into()),
            source_record_id: Some(json!("x".repeat(20_000))),
            source_revision: Some(Revision::new(1)),
            revision: Revision::new(1),
            manual: false,
            attachments: vec![],
        };
        let list = paper_projection(&row, false);
        assert_eq!(list["raw_json"], "");
        let detail = paper_projection(&row, true);
        assert_eq!(detail["raw_json_truncated"], true);
        assert_eq!(detail["source_record_id_truncated"], true);
        assert_eq!(detail["raw_json_byte_length"], "2000000");
        assert!(detail.to_string().len() < 40_000);
        assert_eq!(row.raw_json.len(), 2_000_000);
    }
    fn root() -> String {
        std::env::temp_dir()
            .join(opaque_id("muyon-ffi-test").unwrap().replace(':', "-"))
            .to_str()
            .unwrap()
            .to_owned()
    }
    fn create(core: &ProductCore) -> Value {
        serde_json::from_str(&core.prepare(json!({"operation":"supplier_create","supplier_id":"supplier-1",
            "payload":{"name":"supplier","aliases":[],"address":null,"categories":[],"notes":null,"merged_into":null}}).to_string(),None,"0".into()).unwrap()).unwrap()
    }
    #[test]
    fn production_open_recovers_interrupted_upload_and_collects_only_unreferenced_objects() {
        let root = root();
        let core =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-1".into(), true).unwrap();
        let project: Value = serde_json::from_str(&core.prepare(json!({"operation":"project_create", "project_id":"attachments", "name":"Attachments"}).to_string(), None, "0".into()).unwrap()).unwrap();
        core.confirm_user_plan(project["plan_id"].as_str().unwrap().into())
            .unwrap();
        let begin = || -> String {
            serde_json::from_str::<Value>(&core.begin_upload("attachments".into()).unwrap())
                .unwrap()["upload_id"]
                .as_str()
                .unwrap()
                .into()
        };
        let copying = begin();
        core.append_upload(copying.clone(), b"%PDF-1.4\ninterrupted".to_vec())
            .unwrap();
        let orphan = begin();
        core.append_upload(orphan.clone(), b"%PDF-1.4\nunreferenced\n%%EOF".to_vec())
            .unwrap();
        let orphan_blob: Value =
            serde_json::from_str(&core.finish_upload(orphan.clone(), "pdf".into()).unwrap())
                .unwrap();
        let retained = begin();
        core.append_upload(
            retained.clone(),
            b"%PDF-1.4\nretained attachment\n%%EOF".to_vec(),
        )
        .unwrap();
        let retained_blob: Value =
            serde_json::from_str(&core.finish_upload(retained.clone(), "pdf".into()).unwrap())
                .unwrap();
        let paper: Value = serde_json::from_str(&core.prepare(json!({"operation":"paper_create", "paper_id":"retained-paper", "payload":{"title":"Keep this paper", "attachment":retained_blob["blob"], "attachment_upload_id":retained}}).to_string(), Some("attachments".into()), "0".into()).unwrap()).unwrap();
        let receipt = core
            .confirm_user_plan(paper["plan_id"].as_str().unwrap().into())
            .unwrap();
        let reader: Value = serde_json::from_str(
            &core
                .open_attachment(
                    "attachments".into(),
                    "retained-paper".into(),
                    retained_blob["blob"]["digest"].as_str().unwrap().into(),
                )
                .unwrap(),
        )
        .unwrap();
        assert!(reader["reader_id"].is_string());
        // A competing open cannot run maintenance while this owner is live.
        assert!(
            ProductCore::open(root.clone(), "workspace".into(), "epoch-2".into(), false).is_err()
        );
        drop(core);
        let reopened =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-2".into(), false).unwrap();
        let state: Value =
            serde_json::from_str(&reopened.lookup_upload(copying.clone()).unwrap()).unwrap();
        assert_eq!(state["state"], "aborted");
        let files = Path::new(&root).join("business-v2.sqlite.blobs");
        assert!(!files.join("staging").join(copying).exists());
        assert!(!files
            .join("objects")
            .join(orphan_blob["blob"]["digest"].as_str().unwrap())
            .exists());
        assert!(files
            .join("objects")
            .join(retained_blob["blob"]["digest"].as_str().unwrap())
            .is_file());
        assert_eq!(
            reopened
                .lookup_original(paper["intent_id"].as_str().unwrap().into())
                .unwrap(),
            receipt
        );
        let db = muyon_core::sqlite::Db::open(
            Path::new(&root)
                .join("business-v2.sqlite")
                .to_str()
                .unwrap(),
            true,
            false,
        )
        .unwrap();
        assert_eq!(
            db.query("SELECT count(*) FROM blob_pins WHERE kind='reader'", &[])
                .unwrap()[0][0]
                .as_deref(),
            Some("0")
        );
        assert_eq!(
            serde_json::from_str::<Value>(
                &reopened.list_papers("attachments".into(), 10, 0).unwrap()
            )
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
            1
        );
        drop(db);
        drop(reopened);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn production_startup_never_collects_unknown_uploads_or_intent_retained_pins() {
        let root = root();
        let core =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-1".into(), true).unwrap();
        let project: Value = serde_json::from_str(&core.prepare(json!({"operation":"project_create", "project_id":"unknown-files", "name":"Unknown files"}).to_string(), None, "0".into()).unwrap()).unwrap();
        core.confirm_user_plan(project["plan_id"].as_str().unwrap().into())
            .unwrap();
        let upload: Value =
            serde_json::from_str(&core.begin_upload("unknown-files".into()).unwrap()).unwrap();
        let unknown = upload["upload_id"].as_str().unwrap();
        core.append_upload(unknown.into(), b"uncertain bytes".to_vec())
            .unwrap();
        let pinned: Value =
            serde_json::from_str(&core.begin_upload("unknown-files".into()).unwrap()).unwrap();
        let pinned_id = pinned["upload_id"].as_str().unwrap();
        core.append_upload(
            pinned_id.into(),
            b"%PDF-1.4\nkeep uncertain pinned bytes\n%%EOF".to_vec(),
        )
        .unwrap();
        let blob: Value =
            serde_json::from_str(&core.finish_upload(pinned_id.into(), "pdf".into()).unwrap())
                .unwrap();
        let uncertain: Value = serde_json::from_str(&core.prepare(json!({"operation":"project_create", "project_id":"unresolved", "name":"Unresolved"}).to_string(), None, "0".into()).unwrap()).unwrap();
        // Trusted store fault fixture, not a product API: model no authority to
        // manufacture lifecycle rows. Represent the exact persisted uncertainty.
        let command: CommandEnvelope = serde_json::from_value(uncertain.clone()).unwrap();
        let db = muyon_core::sqlite::Db::open(
            Path::new(&root)
                .join("business-v2.sqlite")
                .to_str()
                .unwrap(),
            false,
            false,
        )
        .unwrap();
        db.exec(
            "UPDATE blob_uploads SET state='unknown' WHERE upload_id=?",
            &[unknown],
        )
        .unwrap();
        db.exec("INSERT INTO intents(intent_id,binding_digest,command_json,status,owner_epoch) VALUES(?,?,?,'unknown','epoch-1')", &[&command.intent_id, &command.binding_digest().unwrap(), &uncertain.to_string()]).unwrap();
        drop(db);
        drop(core);
        let reopened =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-2".into(), false).unwrap();
        for (id, expected) in [(unknown, "unknown"), (pinned_id, "pinned")] {
            let status: Value =
                serde_json::from_str(&reopened.lookup_upload(id.into()).unwrap()).unwrap();
            assert_eq!(status["state"], expected);
        }
        let files = Path::new(&root).join("business-v2.sqlite.blobs");
        assert_eq!(
            std::fs::read(files.join("staging").join(unknown)).unwrap(),
            b"uncertain bytes"
        );
        assert!(files
            .join("objects")
            .join(blob["blob"]["digest"].as_str().unwrap())
            .is_file());
        assert_eq!(
            serde_json::from_str::<Value>(&reopened.lookup_original(command.intent_id).unwrap())
                .unwrap()["status"],
            "unknown"
        );
        drop(reopened);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn unreceived_confirmation_is_sealed_without_resubmitting_after_restart() {
        let root = root();
        let core =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-1".into(), true).unwrap();
        let plan = create(&core);
        // Android has persisted intent_id, but its confirm Binder message never arrived.
        drop(core);
        let reopened =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-2".into(), false).unwrap();
        let intent = plan["intent_id"].as_str().unwrap();
        let result: Value =
            serde_json::from_str(&reopened.lookup_original(intent.into()).unwrap()).unwrap();
        assert_eq!(result["status"], "not_submitted");
        assert!(result["receipt"].is_null());
        assert_eq!(
            reopened.lookup_original(intent.into()).unwrap(),
            result.to_string()
        );
        assert_eq!(reopened.list_suppliers(10, 0).unwrap(), "[]");
        drop(reopened);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn recovery_seal_refuses_an_already_queued_late_confirmation() {
        let root = root();
        let core =
            ProductCore::open(root.clone(), "workspace".into(), "epoch".into(), true).unwrap();
        let plan = create(&core);
        let intent = plan["intent_id"].as_str().unwrap();
        let sealed = core.lookup_original(intent.into()).unwrap();
        assert_eq!(
            serde_json::from_str::<Value>(&sealed).unwrap()["status"],
            "not_submitted"
        );
        // Same original in-memory plan still exists: sealing, rather than lost
        // process memory, must prevent this delayed confirmation from executing.
        assert!(core
            .confirm_user_plan(plan["plan_id"].as_str().unwrap().into())
            .is_err());
        assert_eq!(core.lookup_original(intent.into()).unwrap(), sealed);
        assert_eq!(core.list_suppliers(10, 0).unwrap(), "[]");
        drop(core);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn received_confirmation_and_legacy_unknown_are_never_cleared_or_replayed() {
        let root = root();
        let core =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-1".into(), true).unwrap();
        let plan = create(&core);
        {
            let state = core.state.lock().unwrap();
            let command = &state.prepared[plan["plan_id"].as_str().unwrap()].command;
            // Crash immediately after durable host acceptance, before grant or effect.
            state.store.claim_review_trusted(command).unwrap();
        }
        drop(core);
        let reopened =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-2".into(), false).unwrap();
        for intent in [plan["intent_id"].as_str().unwrap(), "legacy-unknown-intent"] {
            let result: Value =
                serde_json::from_str(&reopened.lookup_original(intent.into()).unwrap()).unwrap();
            assert_eq!(result["status"], "unknown");
            assert!(result["receipt"].is_null());
        }
        assert!(reopened
            .confirm_user_plan(plan["plan_id"].as_str().unwrap().into())
            .is_err());
        assert_eq!(reopened.list_suppliers(10, 0).unwrap(), "[]");
        drop(reopened);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn research_project_confirmation_not_received_recovers_without_a_write() {
        let root = root();
        let core =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-1".into(), true).unwrap();
        let plan: Value = serde_json::from_str(&core.prepare(
            json!({"operation":"project_create","project_id":"research-unreceived","name":"Research draft"}).to_string(),
            None, "0".into()).unwrap()).unwrap();
        drop(core);
        let reopened =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-2".into(), false).unwrap();
        let result: Value = serde_json::from_str(
            &reopened
                .lookup_original(plan["intent_id"].as_str().unwrap().into())
                .unwrap(),
        )
        .unwrap();
        assert_eq!(result["status"], "not_submitted");
        assert_eq!(reopened.list_projects(10, 0).unwrap(), "[]");
        drop(reopened);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn review_is_explicit_and_duplicate_confirmation_returns_original_receipt() {
        let root = root();
        let core =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-1".into(), true).unwrap();
        let plan = create(&core);
        assert_eq!(core.list_suppliers(20, 0).unwrap(), "[]");
        let id = plan["plan_id"].as_str().unwrap().to_owned();
        let first = core.confirm_user_plan(id.clone()).unwrap();
        assert_eq!(
            serde_json::from_str::<Value>(&first).unwrap()["status"],
            "committed"
        );
        assert_eq!(core.confirm_user_plan(id).unwrap(), first);
        assert_eq!(
            serde_json::from_str::<Value>(&core.list_suppliers(20, 0).unwrap())
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            1
        );
        drop(core);
        let reopened =
            ProductCore::open(root.clone(), "workspace".into(), "epoch-2".into(), false).unwrap();
        assert_eq!(
            reopened
                .lookup_original(plan["intent_id"].as_str().unwrap().into())
                .unwrap(),
            first
        );
        assert!(reopened
            .confirm_user_plan(plan["plan_id"].as_str().unwrap().into())
            .is_err());
        drop(reopened);
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn open_never_initializes_or_wipes_missing_or_existing_store() {
        let root = root();
        assert!(
            ProductCore::open(root.clone(), "workspace".into(), "epoch".into(), false).is_err()
        );
        let core =
            ProductCore::open(root.clone(), "workspace".into(), "epoch".into(), true).unwrap();
        assert!(ProductCore::open(root.clone(), "workspace".into(), "other".into(), true).is_err());
        assert_eq!(core.list_suppliers(1, 0).unwrap(), "[]");
        drop(core);
        std::fs::remove_dir_all(root).unwrap();
    }
}

#[cfg(test)]
mod local_draft_bridge_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    const CONVERSATION: &str = "12345678-1234-4234-8234-123456789abc";
    const ATTEMPT: &str = "22345678-1234-4234-8234-123456789abc";
    fn parse(raw: String) -> Value {
        serde_json::from_str(&raw).unwrap()
    }

    #[test]
    fn prepared_attempt_is_discovered_and_fenced_after_native_restart() {
        let root = std::env::temp_dir().join(format!(
            "muyon-local-prepared-ffi-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let core = ProductCore::open(
            root.to_str().unwrap().into(),
            "workspace".into(),
            "epoch".into(),
            true,
        )
        .unwrap();
        let desc = parse(core.local_draft_resolve(CONVERSATION.into(), None).unwrap());
        let text = |key: &str| desc[key].as_str().unwrap().to_owned();
        let hex = "4d59424400000001000000000000000100000000000000000000000000000000000000fbd7ab6104f8d45a51a4ae9335d359af13ab91abe8747df7952c7ef571c7cd2c";
        let archive: Vec<u8> = (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect();
        core.local_draft_prepare_save(LocalDraftPrepareRequest {
            conversation: CONVERSATION.into(),
            project: None,
            namespace_id: text("namespace_id"),
            draft_id: text("draft_id"),
            expected_generation: text("registry_generation"),
            expected_stored_revision: "0".into(),
            attempt_id: ATTEMPT.into(),
            exported_memory_revision: "17".into(),
            host_editor_revision: "42".into(),
            archive: archive.clone(),
        })
        .unwrap();
        drop(core);
        let core = ProductCore::open(
            root.to_str().unwrap().into(),
            "workspace".into(),
            "next-epoch".into(),
            false,
        )
        .unwrap();
        let recovered = parse(core.local_draft_resolve(CONVERSATION.into(), None).unwrap());
        assert_eq!(recovered["save_attempt"]["attempt_id"], ATTEMPT);
        assert_eq!(recovered["save_attempt"]["host_editor_revision"], "42");
        let result = parse(
            core.local_draft_lookup_save(
                CONVERSATION.into(),
                None,
                text("namespace_id"),
                text("draft_id"),
                ATTEMPT.into(),
            )
            .unwrap(),
        );
        assert_eq!(result["status"], "not_committed_local_storage");
        let error = core
            .local_draft_save(
                CONVERSATION.into(),
                None,
                text("namespace_id"),
                text("draft_id"),
                text("registry_generation"),
                "0".into(),
                ATTEMPT.into(),
                "17".into(),
                archive,
            )
            .unwrap_err();
        assert_eq!(error.to_string(), "local_draft_terminal");
        let unchanged = parse(core.local_draft_resolve(CONVERSATION.into(), None).unwrap());
        assert_eq!(unchanged["stored_revision"], "0");
        assert_eq!(unchanged["archive_present"], false);
        drop(core);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn local_draft_bridge_registers_reads_saves_and_looks_up_original_after_restart() {
        let root = std::env::temp_dir().join(format!(
            "muyon-local-draft-ffi-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let core = ProductCore::open(
            root.to_str().unwrap().into(),
            "workspace".into(),
            "epoch".into(),
            true,
        )
        .unwrap();
        let desc = parse(core.local_draft_resolve(CONVERSATION.into(), None).unwrap());
        let text = |key: &str| desc[key].as_str().unwrap().to_owned();
        let loaded = parse(
            core.local_draft_read(
                CONVERSATION.into(),
                None,
                text("namespace_id"),
                text("draft_id"),
                text("registry_generation"),
                "0".into(),
            )
            .unwrap(),
        );
        assert_eq!(loaded["status"], "not_saved");
        assert!(loaded.get("saved").is_none());
        // Canonical synthetic empty-fields MYBD v1, stored revision1 (no model/file).
        let archive_hex = "4d59424400000001000000000000000100000000000000000000000000000000000000fbd7ab6104f8d45a51a4ae9335d359af13ab91abe8747df7952c7ef571c7cd2c";
        let archive: Vec<u8> = (0..archive_hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&archive_hex[i..i + 2], 16).unwrap())
            .collect();
        let prepared = parse(
            core.local_draft_prepare_save(LocalDraftPrepareRequest {
                conversation: CONVERSATION.into(),
                project: None,
                namespace_id: text("namespace_id"),
                draft_id: text("draft_id"),
                expected_generation: text("registry_generation"),
                expected_stored_revision: "0".into(),
                attempt_id: ATTEMPT.into(),
                exported_memory_revision: "17".into(),
                host_editor_revision: "42".into(),
                archive: archive.clone(),
            })
            .unwrap(),
        );
        assert_eq!(prepared["state"], "prepared");
        assert_eq!(prepared["host_editor_revision"], "42");
        let receipt = parse(
            core.local_draft_save(
                CONVERSATION.into(),
                None,
                text("namespace_id"),
                text("draft_id"),
                text("registry_generation"),
                "0".into(),
                ATTEMPT.into(),
                "17".into(),
                archive,
            )
            .unwrap(),
        );
        assert_eq!(receipt["status"], "committed_local_storage");
        assert_eq!(receipt["exported_memory_revision"], "17");
        assert_eq!(receipt["host_editor_revision"], "42");
        assert!(core
            .local_draft_read(
                CONVERSATION.into(),
                None,
                text("namespace_id"),
                text("draft_id"),
                text("registry_generation"),
                "0".into()
            )
            .is_err());
        drop(core);
        let core = ProductCore::open(
            root.to_str().unwrap().into(),
            "workspace".into(),
            "next-epoch".into(),
            false,
        )
        .unwrap();
        assert_eq!(
            parse(
                core.local_draft_lookup_save(
                    CONVERSATION.into(),
                    None,
                    text("namespace_id"),
                    text("draft_id"),
                    ATTEMPT.into()
                )
                .unwrap()
            ),
            receipt
        );
        assert!(core
            .local_draft_lookup_save(
                CONVERSATION.into(),
                Some("missing".into()),
                text("namespace_id"),
                text("draft_id"),
                ATTEMPT.into()
            )
            .is_err());
        assert!(core.local_draft_resolve("legacy-key".into(), None).is_err());
        drop(core);
        std::fs::remove_dir_all(root).unwrap();
    }
}
