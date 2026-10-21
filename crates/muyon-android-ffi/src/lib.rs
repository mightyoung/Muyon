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

uniffi::setup_scaffolding!();

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
    store: BusinessStore,
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
        let agent_path = root.join("agent-v1.sqlite");
        let agent = if agent_path.is_file() {
            Some(AgentOwner::open(&agent_path, &workspace, &epoch).map_err(agent_error)?)
        } else {
            None
        };
        Ok(Arc::new(Self {
            workspace,
            epoch,
            agent_path,
            workflow_path: root.join("agent-workflows-v1.sqlite"),
            state: Mutex::new(State {
                store,
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
        let snapshot = serde_json::from_str::<Value>(&action)
            .map_err(|_| agent_error("workflow_action_invalid"))?["action"]
            == "snapshot";
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
        encode(&result)
    }
    pub fn agent_confirm(
        &self,
        request: String,
        configuration: String,
    ) -> Result<String, ProductError> {
        self.agent_call(|owner| owner.confirm_trusted(&request, &configuration))
    }
    /// Private transport port. Never registered as a UI/model operation.
    pub fn agent_claim(
        &self,
        request: String,
        configuration: String,
        generation: String,
    ) -> Result<String, ProductError> {
        self.agent_call(|owner| owner.claim_dispatch(&request, &configuration, &generation))
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
                state
                    .agent
                    .as_ref()
                    .map(|owner| owner.dispatch_allowed(&request, &configuration, &generation))
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

    /// Pure preparation. No business grant, pending row or effect is created.
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

fn agent_error(code: &'static str) -> ProductError {
    ProductError::Failure { code: code.into() }
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
