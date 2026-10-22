//! Product-local reads and existing provider contracts. No live owner is fabricated.
//!
//! Reading a local record is not permission to transmit it. These replies are
//! local UI data; a future model composition must purpose-review their actual
//! bytes against current workspace/project authority before admission.
#[path = "/tmp/mig20-second-history-independent-review/base-owner.rs"]
pub mod owner;
#[path = "/tmp/mig20-second-history-independent-review/base-tools.rs"]
pub mod tools;
#[path = "/tmp/mig20-second-history-independent-review/base-workflow.rs"]
pub mod workflow;
use crate::{
    business::BusinessStore,
    contract::{decode_json, ContractError},
};
use muyon_core_agent_lab::{model::ModelEvent, wire_sse::Decoder};
use muyon_rust_agent_host_lab::{
    ordinary_chat::check_text,
    service_provider::{CallBudget, ServiceProviderBridge},
};
use muyon_web_search_lab::{SearchHost, SearchProvider};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum UnavailableReason {
    ProviderOwnerNotBound,
    ProviderConfigurationUnavailable,
    SearchHostNotBound,
    SearchConfigurationUnavailable,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct CapabilityStatus {
    pub configured: bool,
    pub transport_bound: bool,
    pub reason: Option<UnavailableReason>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct AgentAvailability {
    pub chat: CapabilityStatus,
    pub search: CapabilityStatus,
    pub local_reads: bool,
    pub synthetic: bool,
}

/// The product currently has no trusted transport owner. Configuration probes
/// reuse existing authority checks, never reserve, admit or issue a request.
pub fn availability(
    provider: Option<&ServiceProviderBridge>,
    search: Option<(&dyn SearchHost, &dyn SearchProvider)>,
) -> AgentAvailability {
    let chat = match provider {
        None => CapabilityStatus {
            configured: false,
            transport_bound: false,
            reason: Some(UnavailableReason::ProviderOwnerNotBound),
        },
        Some(bridge) => {
            let configured = bridge
                .readiness(&CallBudget {
                    max_tokens: 1,
                    max_micros: 1,
                    requires_tools: true,
                    requires_streaming: true,
                })
                .is_ok();
            CapabilityStatus {
                configured,
                transport_bound: false,
                reason: Some(if configured {
                    UnavailableReason::ProviderOwnerNotBound
                } else {
                    UnavailableReason::ProviderConfigurationUnavailable
                }),
            }
        }
    };
    let search = match search {
        None => CapabilityStatus {
            configured: false,
            transport_bound: false,
            reason: Some(UnavailableReason::SearchHostNotBound),
        },
        Some((host, provider)) => {
            let ready = muyon_web_search_lab::availability(host, provider).is_ok();
            CapabilityStatus {
                configured: ready,
                transport_bound: false,
                reason: Some(if ready {
                    UnavailableReason::SearchHostNotBound
                } else {
                    UnavailableReason::SearchConfigurationUnavailable
                }),
            }
        }
    };
    AgentAvailability {
        chat,
        search,
        local_reads: true,
        synthetic: false,
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "tool", rename_all = "snake_case", deny_unknown_fields)]
pub enum ReadTool {
    SupplierList { limit: u32, offset: u32 },
    SupplierGet { id: String },
    PaperList { limit: u32, offset: u32 },
    PaperGet { id: String },
}

/// Construct only from the Service's selected project/session, never from a
/// model-supplied workspace/epoch/project in tool arguments.
pub struct ReadScope {
    workspace: String,
    owner_epoch: String,
    project: Option<String>,
}
impl ReadScope {
    pub fn current(store: &BusinessStore, project: Option<&str>) -> Result<Self, ContractError> {
        if let Some(project) = project {
            if store.project(project)?.deleted {
                return Err(ContractError::NotFound);
            }
        }
        Ok(Self {
            workspace: store.workspace_id().into(),
            owner_epoch: store.owner_epoch().into(),
            project: project.map(str::to_owned),
        })
    }
}

pub fn read_business(
    store: &BusinessStore,
    scope: &ReadScope,
    raw: &str,
) -> Result<Value, ContractError> {
    if store.workspace_id() != scope.workspace || store.owner_epoch() != scope.owner_epoch {
        return Err(ContractError::ScopeMismatch);
    }
    if raw.len() > 8192 {
        return Err(ContractError::RawLimit);
    }
    let request: ReadTool =
        serde_json::from_value(decode_json(raw)?).map_err(|_| ContractError::InvalidPayload)?;
    let page = |limit: u32, offset: u32| {
        if (1..=50).contains(&limit) && offset <= 10_000 {
            Ok(())
        } else {
            Err(ContractError::RawLimit)
        }
    };
    let records = match request {
        ReadTool::SupplierList { limit, offset } => {
            page(limit, offset)?;
            serde_json::to_value(store.suppliers(limit, offset)?)
        }
        ReadTool::SupplierGet { id } => {
            let record = store.supplier(&id)?;
            if record.deleted {
                return Err(ContractError::NotFound);
            }
            serde_json::to_value(vec![record])
        }
        ReadTool::PaperList { limit, offset } => {
            page(limit, offset)?;
            let project = scope
                .project
                .as_deref()
                .ok_or(ContractError::ScopeMismatch)?;
            Ok(Value::Array(
                store
                    .papers(project, limit, offset)?
                    .iter()
                    .map(paper_summary)
                    .collect(),
            ))
        }
        ReadTool::PaperGet { id } => {
            let project = scope
                .project
                .as_deref()
                .ok_or(ContractError::ScopeMismatch)?;
            Ok(json!([paper_summary(&store.paper(project, &id)?)]))
        }
    }
    .map_err(|_| ContractError::InvalidPayload)?;
    let reply = json!({"source":"current_local_business", "workspace_id":scope.workspace,
        "project_id":scope.project, "owner_epoch":scope.owner_epoch, "records":records,
        "outbound_authorized":false, "synthetic":false});
    if serde_json::to_vec(&reply)
        .map_err(|_| ContractError::InvalidPayload)?
        .len()
        > 262_144
    {
        return Err(ContractError::RawLimit);
    }
    Ok(reply)
}

fn paper_summary(paper: &crate::research::PaperRecord) -> Value {
    // Imported raw JSON and private attachment paths are not automatic context.
    json!({"id":paper.id,"project_id":paper.project_id,"title":paper.title,
        "revision":paper.revision,"source_id":paper.source_id,"source_revision":paper.source_revision,
        "manual":paper.manual,"attachment_count":paper.attachments.len()})
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct AcceptedAnswer {
    pub answer: String,
    pub input_tokens: u64,
    pub output_tokens: u64,
}

/// Parser regression seam only. This proves framing/usage, not admission,
/// settlement or that any HTTP transport ran. Caller must retain those proofs.
pub fn decode_answer_sse(bytes: &[u8], cancelled: bool) -> Result<AcceptedAnswer, &'static str> {
    if bytes.len() > 1_048_576 {
        return Err("response_limit");
    }
    let mut decoder = Decoder::new();
    if cancelled {
        decoder.cancel();
    }
    for byte in bytes {
        decoder.feed(*byte).map_err(|_| "response_unknown")?;
    }
    let turn = decoder.finish().map_err(|_| "response_unknown")?;
    let ModelEvent::Answer(answer) = turn.event else {
        return Err("tool_turn_requires_dispatch");
    };
    if check_text(&answer).is_err() {
        return Err("answer_disclosure_denied");
    }
    Ok(AcceptedAnswer {
        answer,
        input_tokens: turn.usage.prompt.ok_or("usage_unknown")?,
        output_tokens: turn.usage.completion.ok_or("usage_unknown")?,
    })
}
