//! Provider-neutral ordinary-Send route on the existing admitted Service worker.
use crate::{
    field, service_root::ServiceRoot, service_runtime::RunControl, service_types::*,
    store::NativeStore, supplier_business::BusinessRead, Json, Result,
};
use muyon_core_agent_lab::{agent::State, store};
use muyon_plugin_contract_lab::{object, parse, string};
use std::{io::Read, path::Path, sync::Arc};
pub struct RegisteredChatResult {
    pub state: String,
    pub reason: String,
    pub answer: String,
    pub projection: Option<Json>,
    pub receipt: Option<Json>,
}
/// Trusted installation; no UI authority, transport, secret or model-budget API.
pub trait RegisteredChatRoute: Send + Sync {
    /// Only explicitly disabled returns None. Freeze errors as a failed route.
    fn prepare(&self, conversation: &str, text: &str) -> Result<Option<Json>>;
    fn execute(
        &self,
        dir: &Path,
        input: &Json,
        route: &Json,
        control: Arc<RunControl>,
        admitted: &mut dyn FnMut(&State) -> Result<()>,
    ) -> Result<RegisteredChatResult>;
    /// Passive verification only: no execution, model send or route preparation.
    fn restore(&self, dir: &Path, input: &Json, route: &Json, result: &Json) -> Result<()>;
    /// Revalidate current authority/config/handle/purpose before each disclosure.
    fn disclose(&self, dir: &Path, input: &Json, route: &Json, result: &Json) -> Result<()>;
}
pub(crate) fn is_registered(b: &BusinessRead) -> bool {
    field(&b.payload, "intent").ok() == Some(&string("registered-chat-v1"))
}
pub(crate) fn is_synthetic(b: &BusinessRead) -> bool {
    b.source_binding.as_ref().and_then(|route| field(route, "synthetic").ok()) == Some(&Json::Bool(true))
}
pub(crate) fn make(conversation: String, text: String, route: Json) -> Result<BusinessRead> {
    let mut b = BusinessRead::ordinary(conversation, text)?;
    if route.encode().len() > 4096 || route.object().is_err() {
        return Err("tool_route_invalid".into());
    }
    if !matches!(field(&route, "synthetic")?, Json::Bool(_)) {
        return Err("tool_route_invalid".into());
    }
    if let Json::Object(m) = &mut b.payload {
        m.insert("intent".into(), string("registered-chat-v1"));
    }
    b.source_binding = Some(route);
    Ok(b)
}
pub(crate) fn record(b: &BusinessRead) -> Json {
    object([
        ("version", string("registered-chat-1")),
        ("payload", b.payload.clone()),
        ("route", b.source_binding.clone().unwrap_or(Json::Null)),
        ("events", Json::Array(b.events.clone())),
    ])
}
pub(crate) fn load(j: &Json, dir: &Path) -> Result<BusinessRead> {
    closed(j, &["version", "payload", "route", "events"])?;
    let p = field(j, "payload")?;
    closed(p, &["intent", "conversation", "text"])?;
    let mut b = make(
        field(p, "conversation")?.string()?.into(),
        field(p, "text")?.string()?.into(),
        field(j, "route")?.clone(),
    )?;
    if b.payload != *p {
        return Err("tool_input_identity".into());
    }
    b.events = field(j, "events")?.array()?.to_vec();
    b.dir = Some(dir.into());
    validate_events(&b)?;
    Ok(b)
}
fn closed(j: &Json, fields: &[&str]) -> Result<()> {
    let m = j.object()?;
    if m.len() != fields.len() || fields.iter().any(|k| !m.contains_key(*k)) {
        Err("tool_record_shape".into())
    } else {
        Ok(())
    }
}
fn result_record(dir: &Path) -> Result<Json> {
    let path = dir.join("registered-result.db");
    let m = std::fs::symlink_metadata(&path).map_err(|_| "tool_result_missing")?;
    if !m.is_file() || m.file_type().is_symlink() || m.len() > 32768 {
        return Err("tool_result_bound".into());
    }
    let mut bytes = Vec::new();
    std::fs::File::open(path)
        .map_err(|_| "tool_result_missing")?
        .take(32769)
        .read_to_end(&mut bytes)
        .map_err(|_| "tool_result_missing")?;
    if bytes.len() > 32768 {
        return Err("tool_result_bound".into());
    }
    parse(&bytes)
}
pub(crate) fn validate_events(b: &BusinessRead) -> Result<()> {
    if b.events.is_empty() {
        return Ok(());
    }
    if b.events.len() > 4 {
        return Err("tool_event_bound".into());
    }
    for (i, e) in b.events.iter().enumerate() {
        closed(e, &["cursor", "kind", "payload"])?;
        if field(e, "cursor")?.integer()? != i as u64 + 1 {
            return Err("tool_cursor".into());
        }
    }
    let end = b.events.last().ok_or("tool_terminal")?;
    if field(end, "kind")? != &string("terminal") {
        return Err("tool_terminal".into());
    }
    closed(field(end, "payload")?, &["state", "reason"])?;
    let state = field(field(end, "payload")?, "state")?.string()?;
    if state == "completed" {
        if b.events.len() != 4 {
            return Err("tool_event_order".into());
        }
        for (e, k) in b.events.iter().zip([
            "answer_delta",
            "tool_projection",
            "tool_receipt",
            "terminal",
        ]) {
            if field(e, "kind")? != &string(k) {
                return Err("tool_event_order".into());
            }
        }
        closed(field(&b.events[0], "payload")?, &["text"])?;
        crate::ordinary_chat::check_text(
            field(field(&b.events[0], "payload")?, "text")?.string()?,
        )?;
        closed(field(&b.events[1], "payload")?, &["tool", "result"])?;
        let p = field(field(&b.events[1], "payload")?, "result")?;
        if p.encode().len() > 16384
            || field(p, "tainted")? != &Json::Bool(true)
            || field(p, "instruction_authority")? != &Json::Bool(false)
        {
            return Err("tool_projection_invalid".into());
        }
        closed(
            field(&b.events[2], "payload")?,
            &["owner", "invocation_id", "binding_id", "identity"],
        )?;
    } else if !matches!(state, "failed" | "cancelled" | "outcome_unknown") || b.events.len() != 1 {
        return Err("tool_event_state".into());
    }
    Ok(())
}
fn verify(dir: &Path, run: &AgentDurableRun, b: &BusinessRead) -> Result<Json> {
    validate_events(b)?;
    let r = result_record(dir)?;
    closed(
        &r,
        &[
            "version",
            "request",
            "run",
            "payload",
            "route",
            "task",
            "attempt",
            "state",
            "reason",
            "answer",
            "projection",
            "receipt",
        ],
    )?;
    if field(&r, "version")? != &string("registered-result-1")
        || field(&r, "request")? != &string(&run.intent.request_id)
        || field(&r, "run")? != &string(&run.identity.run_id)
        || field(&r, "payload")? != &b.payload
        || b.source_binding.as_ref() != Some(field(&r, "route")?)
    {
        return Err("tool_result_identity".into());
    }
    let terminal = field(b.events.last().ok_or("tool_terminal")?, "payload")?;
    if field(terminal, "state")? != field(&r, "state")?
        || field(terminal, "reason")? != field(&r, "reason")?
    {
        return Err("tool_terminal_identity".into());
    }
    if field(&r, "state")? == &string("completed") {
        let task = run
            .identity
            .actual_task
            .as_ref()
            .ok_or("tool_task_missing")?;
        if field(&r, "task")? != &string(&task.task_id)
            || field(&r, "attempt")? != &string(&task.attempt_id)
        {
            return Err("tool_task_identity".into());
        }
        let (rows, _) = NativeStore::read_service_evidence(dir)?;
        if rows.len() != 1 {
            return Err("tool_receipt_count".into());
        }
        let row = &rows[0];
        let binding = field(row, "binding")?;
        let route = b.source_binding.as_ref().ok_or("tool_route_missing")?;
        let op = field(binding, "operation")?.string()?;
        let (qualified, _) = op.rsplit_once('@').ok_or("tool_operation_identity")?;
        let (module, name) = qualified.split_once('/').ok_or("tool_operation_identity")?;
        if field(route, "tool")? != &string(format!("{module}.{name}"))
            || field(binding, "scope")? != field(route, "scope")?
            || field(binding, "scope_refs")? != field(route, "scope_refs")?
            || field(binding, "args")? != field(route, "arguments")?
            || field(field(&b.events[1], "payload")?, "tool")? != field(route, "tool")?
        {
            return Err("tool_dispatch_identity".into());
        }

        if field(row, "status")? != &string("succeeded")
            || field(row, "raw")? != field(&r, "projection")?
            || field(row, "identity")? != field(&r, "receipt")?
            || field(binding, "task")? != field(&r, "task")?
            || field(binding, "attempt")? != field(&r, "attempt")?
        {
            return Err("tool_receipt_identity".into());
        }
        if field(field(&b.events[0], "payload")?, "text")? != field(&r, "answer")?
            || field(field(&b.events[1], "payload")?, "result")? != field(&r, "projection")?
            || field(&b.events[2], "payload")? != field(&r, "receipt")?
        {
            return Err("tool_event_identity".into());
        }
    }
    Ok(r)
}
pub(crate) fn restore(
    dir: &Path,
    run: &AgentDurableRun,
    b: &BusinessRead,
) -> Result<AgentRunSnapshot> {
    let r = verify(dir, run, b)?;
    let state = field(&r, "state")?.string()?;
    let terminal = match state {
        "completed" => AgentTerminal::Completed,
        "failed" => AgentTerminal::Failed,
        "cancelled" => AgentTerminal::Cancelled,
        _ => {
            return Ok(crate::service_evidence::unknown(
                run,
                AgentReceiptSummary {
                    opaque_id: None,
                    outcome: AgentReceiptOutcome::Unknown,
                },
            ))
        }
    };
    let receipt = if state == "completed" {
        AgentReceiptSummary {
            opaque_id: Some(
                field(field(&r, "receipt")?, "invocation_id")?
                    .string()?
                    .into(),
            ),
            outcome: AgentReceiptOutcome::RecordedSuccess,
        }
    } else {
        AgentReceiptSummary {
            opaque_id: None,
            outcome: AgentReceiptOutcome::NotStarted,
        }
    };
    Ok(AgentRunSnapshot::Terminal {
        summary: AgentRunSummary {
            request_id: run.intent.request_id.clone(),
            variant: run.intent.variant.clone(),
            source_build_identity: run.intent.source_build_identity.clone(),
            identity: run.identity.clone(),
            terminal,
            reason: if state == "completed" {
                AgentReason::None
            } else {
                AgentReason::InternalFailure
            },
            receipt,
        },
    })
}
pub(crate) fn disclose(b: &BusinessRead, identity: &AgentRunIdentity, request: &str) -> Result<()> {
    let run = AgentDurableRun {
        intent: AgentIntentBinding {
            request_id: request.into(),
            variant: AgentReadVariant::Inquiry,
            source_build_identity: String::new(),
        },
        identity: identity.clone(),
    };
    let dir = b.dir.as_ref().ok_or("tool_run_missing")?;
    let r = verify(dir, &run, b)?;
    let router = b
        .host
        .as_ref()
        .and_then(|h| h.tools.as_ref())
        .ok_or("tool_router_unavailable")?;
    router.restore(
        dir,
        &b.payload,
        b.source_binding.as_ref().ok_or("tool_route_missing")?,
        &r,
    )?;
    if field(&r, "state")? == &string("completed") {
        router.disclose(
            dir,
            &b.payload,
            b.source_binding.as_ref().ok_or("tool_route_missing")?,
            &r,
        )?;
    }
    Ok(())
}
pub(crate) fn execute(
    root: &mut ServiceRoot,
    run: &mut AgentDurableRun,
    dir: &Path,
    b: &mut BusinessRead,
    control: Arc<RunControl>,
) -> AgentRunSummary {
    b.dir = Some(dir.into());
    let mut actual = None;
    let result = (|| {
        crate::ordinary_chat::check_text(field(&b.payload, "text")?.string()?)?;
        control.poll()?;
        let router = b
            .host
            .as_ref()
            .and_then(|h| h.tools.clone())
            .ok_or("tool_router_unavailable")?;
        let route = b.source_binding.as_ref().ok_or("tool_route_missing")?;
        let mut admitted = |state: &State| {
            let task = AgentTaskIdentity {
                task_id: state.task.clone(),
                attempt_id: state.attempt.clone(),
            };
            root.attach_task(&run.identity.run_id, task.clone())?;
            run.identity.actual_task = Some(task.clone());
            actual = Some(task);
            Ok(())
        };
        router.execute(dir, &b.payload, route, control.clone(), &mut admitted)
    })();
    let mut done = result.unwrap_or_else(|reason| RegisteredChatResult {
        state: if dir.join("native.db").exists() {
            "outcome_unknown"
        } else if reason == "native_cancelled" {
            "cancelled"
        } else {
            "failed"
        }
        .into(),
        reason: if [
            "search_unconfigured",
            "search_transport_unavailable",
            "search_config_corrupt",
            "search_config_changed",
            "chat_credential_signal",
            "chat_text_unreviewed",
            "native_cancelled",
        ]
        .contains(&reason.as_str())
        {
            reason
        } else {
            "registered_tool_failed".into()
        },
        answer: String::new(),
        projection: None,
        receipt: None,
    });
    if !matches!(
        done.state.as_str(),
        "completed" | "failed" | "cancelled" | "outcome_unknown"
    ) {
        done.state = "outcome_unknown".into();
    }
    if done.state == "completed" {
        b.push("answer_delta", object([("text", string(&done.answer))]));
        b.push(
            "tool_projection",
            object([
                (
                    "tool",
                    string(
                        field(b.source_binding.as_ref().unwrap(), "tool")
                            .and_then(Json::string)
                            .unwrap_or("unavailable"),
                    ),
                ),
                ("result", done.projection.clone().unwrap_or(Json::Null)),
            ]),
        );
        b.push("tool_receipt", done.receipt.clone().unwrap_or(Json::Null));
    }
    b.push(
        "terminal",
        object([
            ("state", string(&done.state)),
            ("reason", string(&done.reason)),
        ]),
    );
    let r = object([
        ("version", string("registered-result-1")),
        ("request", string(&run.intent.request_id)),
        ("run", string(&run.identity.run_id)),
        ("payload", b.payload.clone()),
        ("route", b.source_binding.clone().unwrap_or(Json::Null)),
        (
            "task",
            string(actual.as_ref().map(|a| a.task_id.as_str()).unwrap_or("")),
        ),
        (
            "attempt",
            string(actual.as_ref().map(|a| a.attempt_id.as_str()).unwrap_or("")),
        ),
        ("state", string(&done.state)),
        ("reason", string(&done.reason)),
        ("answer", string(&done.answer)),
        ("projection", done.projection.clone().unwrap_or(Json::Null)),
        ("receipt", done.receipt.clone().unwrap_or(Json::Null)),
    ]);
    // Rejected credential input never enters the durable source/result ledger.
    let saved = crate::ordinary_chat::check_text(
        field(&b.payload, "text")
            .and_then(Json::string)
            .unwrap_or(""),
    )
    .is_ok()
        && r.encode().len() <= 32768
        && store::atomic(dir, "registered-result.db", &r.encode()).is_ok()
        && b.save(dir).is_ok();
    if !saved || (done.state == "completed" && verify(dir, run, b).is_err()) {
        done.state = "outcome_unknown".into();
        b.events.clear();
        b.push(
            "terminal",
            object([
                ("state", string("outcome_unknown")),
                ("reason", string("tool_evidence_unavailable")),
            ]),
        );
    }
    let terminal = match done.state.as_str() {
        "completed" => AgentTerminal::Completed,
        "failed" => AgentTerminal::Failed,
        "cancelled" => AgentTerminal::Cancelled,
        _ => AgentTerminal::OutcomeUnknown,
    };
    AgentRunSummary {
        request_id: run.intent.request_id.clone(),
        variant: run.intent.variant.clone(),
        source_build_identity: run.intent.source_build_identity.clone(),
        identity: run.identity.clone(),
        reason: if terminal == AgentTerminal::Completed {
            AgentReason::None
        } else {
            AgentReason::InternalFailure
        },
        receipt: AgentReceiptSummary {
            opaque_id: done
                .receipt
                .as_ref()
                .and_then(|r| field(r, "invocation_id").ok())
                .and_then(|v| v.string().ok())
                .map(str::to_owned),
            outcome: if terminal == AgentTerminal::Completed {
                AgentReceiptOutcome::RecordedSuccess
            } else if terminal == AgentTerminal::OutcomeUnknown {
                AgentReceiptOutcome::Unknown
            } else {
                AgentReceiptOutcome::NotStarted
            },
        },
        terminal,
    }
}
