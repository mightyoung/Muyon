//! Bounded durable lifecycle evidence. Never restores an Agent or grants authority.
use crate::{field, service_root::ServiceRoot, service_types::*, store::NativeStore, Result};
use muyon_core_agent_lab::store;
use muyon_plugin_contract_lab::{object, parse, string, Json};
use std::{fs, io::Read, path::Path};
fn read_bound(path: &Path, max: usize) -> Result<String> {
    let m = fs::symlink_metadata(path).map_err(|e| e.to_string())?;
    if !m.is_file() || m.file_type().is_symlink() || m.len() > max as u64 {
        return Err("service_evidence_file".into());
    }
    let mut bytes = Vec::new();
    fs::File::open(path)
        .map_err(|e| e.to_string())?
        .take(max as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() > max {
        return Err("service_evidence_bound".into());
    }
    String::from_utf8(bytes).map_err(|_| "service_evidence_utf8".into())
}
fn keys(j: &Json, names: &[&str]) -> Result<()> {
    let m = j.object()?;
    if m.len() != names.len() || names.iter().any(|n| !m.contains_key(*n)) {
        Err("service_summary_fields".into())
    } else {
        Ok(())
    }
}
pub(crate) fn receipt(dir: &Path, run: &AgentDurableRun) -> Result<AgentReceiptSummary> {
    let (receipts, _facts) = NativeStore::read_service_evidence(dir)?;
    if receipts.is_empty() {
        return Ok(AgentReceiptSummary {
            opaque_id: None,
            outcome: AgentReceiptOutcome::NotStarted,
        });
    }
    if receipts.len() != 1 {
        return Err("service_receipt_count".into());
    }
    let row = &receipts[0];
    let binding = field(row, "binding")?;
    let task = run
        .identity
        .actual_task
        .as_ref()
        .ok_or("service_receipt_task_missing")?;
    if field(binding, "task")?.string()? != task.task_id
        || field(binding, "attempt")?.string()? != task.attempt_id
    {
        return Err("service_receipt_task_mismatch".into());
    }
    use muyon_plugin_contract_lab::mappings::{declaration, renamed_equipment, MappingKind};
    let (decl, typ, key, native_key) = match &run.intent.variant {
        AgentReadVariant::Equipment => (
            declaration(MappingKind::Equipment)?,
            "equipment",
            "e1",
            "equipment_key",
        ),
        AgentReadVariant::Research => (declaration(MappingKind::Research)?, "project", "p1", "id"),
        AgentReadVariant::Inquiry => (declaration(MappingKind::Inquiry)?, "supplier", "s1", "id"),
        AgentReadVariant::SeededEquipment => {
            (renamed_equipment(0x7631)?, "asset", "e1", "equipment_key")
        }
    };
    let reference = object([
        ("module_id", field(&decl.bundle, "module_id")?.clone()),
        ("type", string(typ)),
        ("key", string(key)),
        ("revision", string("1")),
        ("schema_version", Json::Number("1".into())),
    ]);
    let args = if native_key == "id" {
        object([("type", string(typ)), ("id", string(key))])
    } else {
        object([
            ("equipment_key", string(key)),
            ("include_loans", Json::Bool(false)),
        ])
    };
    if field(binding, "operation")?.string()? != decl.operation
        || field(field(row, "identity")?, "binding_id")?.string()? != decl.binding_id
        || field(binding, "scope")?.string()? != "selected-record"
        || field(binding, "turn")?.integer()? != 1
        || field(binding, "args")? != &args
        || field(binding, "scope_refs")? != &Json::Array(vec![reference])
    {
        return Err("service_receipt_variant_mismatch".into());
    }
    let id = field(field(row, "identity")?, "identity")?
        .string()?
        .to_owned();
    let outcome = match field(row, "status")?.string()? {
        "succeeded" => AgentReceiptOutcome::RecordedSuccess,
        "failed" => AgentReceiptOutcome::RecordedFailure,
        "running" => AgentReceiptOutcome::Unknown,
        _ => return Err("service_receipt_status".into()),
    };
    Ok(AgentReceiptSummary {
        opaque_id: Some(id),
        outcome,
    })
}
#[derive(Debug)]
pub(crate) struct TaskEvidence {
    pub status: String,
    pub calls: u64,
    pub steps: u64,
}
fn task(dir: &Path, run: &AgentDurableRun) -> Result<TaskEvidence> {
    let expected = run
        .identity
        .actual_task
        .as_ref()
        .ok_or("service_task_missing")?;
    // Metadata reconciliation only: never State::load/resume/drive from persisted data.
    let rows = store::rows(
        &read_bound(&dir.join("task.db"), 128 * 1024)?,
        "CORE_TASK_V1",
    )?;
    let get = |k: &str| rows.get(k).map(String::as_str).ok_or("service_task_field");
    if get("task")? != expected.task_id
        || get("attempt")? != expected.attempt_id
        || get("scope_hex")? != muyon_core_agent_lab::hex("selected-record")
        || get("max_calls")? != "2"
        || get("max_steps")? != "2"
    {
        return Err("service_task_mismatch".into());
    }
    let calls = get("calls")?
        .parse::<u64>()
        .map_err(|_| "service_task_calls")?;
    let steps = get("steps")?
        .parse::<u64>()
        .map_err(|_| "service_task_steps")?;
    if calls > 2 || steps > 2 {
        return Err("service_task_budget".into());
    }
    let status = get("status")?.to_owned();
    if !matches!(
        status.as_str(),
        "ready"
            | "waiting"
            | "completed"
            | "denied"
            | "failed"
            | "cancelled"
            | "outcome_unknown"
            | "budget_exhausted"
    ) {
        return Err("service_task_status".into());
    }
    Ok(TaskEvidence {
        status,
        calls,
        steps,
    })
}
fn terminal_name(v: &AgentTerminal) -> &'static str {
    match v {
        AgentTerminal::Completed => "completed",
        AgentTerminal::Cancelled => "cancelled",
        AgentTerminal::Failed => "failed",
        AgentTerminal::BudgetExhausted => "budget_exhausted",
        AgentTerminal::OutcomeUnknown => "outcome_unknown",
    }
}
fn reason_name(v: &AgentReason) -> &'static str {
    match v {
        AgentReason::None => "none",
        AgentReason::Cancelled => "cancelled",
        AgentReason::AuthorityDenied => "authority_denied",
        AgentReason::PurposeDenied => "purpose_denied",
        AgentReason::ContractRejected => "contract_rejected",
        AgentReason::StorageFailure => "storage_failure",
        AgentReason::ProviderFailure => "provider_failure",
        AgentReason::DeadlineExceeded => "deadline_exceeded",
        AgentReason::BudgetExceeded => "budget_exceeded",
        AgentReason::Interrupted => "interrupted",
        AgentReason::InternalFailure => "internal_failure",
    }
}
fn outcome_name(v: &AgentReceiptOutcome) -> &'static str {
    match v {
        AgentReceiptOutcome::NotStarted => "not_started",
        AgentReceiptOutcome::Unknown => "unknown",
        AgentReceiptOutcome::RecordedSuccess => "recorded_success",
        AgentReceiptOutcome::RecordedFailure => "recorded_failure",
    }
}
fn encode(summary: &AgentRunSummary) -> Json {
    let run = AgentDurableRun {
        intent: AgentIntentBinding {
            request_id: summary.request_id.clone(),
            variant: summary.variant.clone(),
            source_build_identity: summary.source_build_identity.clone(),
        },
        identity: summary.identity.clone(),
    };
    object([
        ("version", string("agent-service-summary-1")),
        ("run", crate::service_root::encode_run(&run)),
        ("terminal", string(terminal_name(&summary.terminal))),
        ("reason", string(reason_name(&summary.reason))),
        (
            "receipt",
            object([
                (
                    "opaque_id",
                    summary
                        .receipt
                        .opaque_id
                        .as_ref()
                        .map(string)
                        .unwrap_or(Json::Null),
                ),
                ("outcome", string(outcome_name(&summary.receipt.outcome))),
            ]),
        ),
    ])
}
fn decode(j: &Json) -> Result<AgentRunSummary> {
    keys(j, &["version", "run", "terminal", "reason", "receipt"])?;
    if field(j, "version")? != &string("agent-service-summary-1") {
        return Err("service_summary_version".into());
    }
    let run = crate::service_root::decode_run(field(j, "run")?)?;
    let terminal = match field(j, "terminal")?.string()? {
        "completed" => AgentTerminal::Completed,
        "cancelled" => AgentTerminal::Cancelled,
        "failed" => AgentTerminal::Failed,
        "budget_exhausted" => AgentTerminal::BudgetExhausted,
        "outcome_unknown" => AgentTerminal::OutcomeUnknown,
        _ => return Err("service_summary_terminal".into()),
    };
    let reason = match field(j, "reason")?.string()? {
        "none" => AgentReason::None,
        "cancelled" => AgentReason::Cancelled,
        "authority_denied" => AgentReason::AuthorityDenied,
        "purpose_denied" => AgentReason::PurposeDenied,
        "contract_rejected" => AgentReason::ContractRejected,
        "storage_failure" => AgentReason::StorageFailure,
        "provider_failure" => AgentReason::ProviderFailure,
        "deadline_exceeded" => AgentReason::DeadlineExceeded,
        "budget_exceeded" => AgentReason::BudgetExceeded,
        "interrupted" => AgentReason::Interrupted,
        "internal_failure" => AgentReason::InternalFailure,
        _ => return Err("service_summary_reason".into()),
    };
    let r = field(j, "receipt")?;
    keys(r, &["opaque_id", "outcome"])?;
    let id = match field(r, "opaque_id")? {
        Json::Null => None,
        Json::String(s)
            if s.len() == 32
                && s.bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) =>
        {
            Some(s.clone())
        }
        _ => return Err("service_summary_receipt".into()),
    };
    let outcome = match field(r, "outcome")?.string()? {
        "not_started" => AgentReceiptOutcome::NotStarted,
        "unknown" => AgentReceiptOutcome::Unknown,
        "recorded_success" => AgentReceiptOutcome::RecordedSuccess,
        "recorded_failure" => AgentReceiptOutcome::RecordedFailure,
        _ => return Err("service_summary_outcome".into()),
    };
    Ok(AgentRunSummary {
        request_id: run.intent.request_id,
        variant: run.intent.variant,
        source_build_identity: run.intent.source_build_identity,
        identity: run.identity,
        terminal,
        reason,
        receipt: AgentReceiptSummary {
            opaque_id: id,
            outcome,
        },
    })
}
fn validate(dir: &Path, run: &AgentDurableRun, s: &AgentRunSummary) -> Result<()> {
    if s.request_id != run.intent.request_id
        || s.variant != run.intent.variant
        || s.source_build_identity != run.intent.source_build_identity
        || s.identity != run.identity
    {
        return Err("service_summary_binding".into());
    }
    let original = receipt(dir, run)?;
    if original != s.receipt {
        return Err("service_summary_receipt_mismatch".into());
    }
    if original.outcome == AgentReceiptOutcome::Unknown
        && s.terminal != AgentTerminal::OutcomeUnknown
    {
        return Err("service_summary_unknown".into());
    }
    let t = if run.identity.actual_task.is_some() {
        Some(task(dir, run)?)
    } else {
        None
    };
    match s.terminal {
        AgentTerminal::Completed => {
            let t = t.ok_or("service_completed_task")?;
            if s.reason != AgentReason::None
                || s.receipt.outcome != AgentReceiptOutcome::RecordedSuccess
                || s.receipt.opaque_id.is_none()
                || t.status != "completed"
                || t.calls != 2
                || t.steps != 2
            {
                return Err("service_completed_evidence".into());
            }
            let outbound = parse(read_bound(&dir.join("outbound.db"), 512 * 1024)?.as_bytes())?;
            keys(&outbound, &["status", "bytes"])?;
            let body = field(&outbound, "bytes")?.string()?;
            if field(&outbound, "status")?.string()? != "sent" || body.len() > 65536 {
                return Err("service_completed_outbound".into());
            }
            let payload = parse(body.as_bytes())?;
            if !field(&payload, "tools")?.array()?.is_empty()
                || !body.contains(
                    s.receipt
                        .opaque_id
                        .as_ref()
                        .ok_or("service_completed_receipt")?,
                )
            {
                return Err("service_completed_outbound".into());
            }
        }
        AgentTerminal::Cancelled => {
            if s.reason != AgentReason::Cancelled
                || t.as_ref().map(|t| t.status.as_str()) != Some("cancelled")
            {
                return Err("service_cancel_evidence".into());
            }
        }
        AgentTerminal::BudgetExhausted => {
            if !matches!(
                s.reason,
                AgentReason::BudgetExceeded | AgentReason::DeadlineExceeded
            ) || t.as_ref().map(|t| t.status.as_str()) != Some("budget_exhausted")
            {
                return Err("service_budget_evidence".into());
            }
        }
        AgentTerminal::Failed => {
            if matches!(s.reason, AgentReason::None | AgentReason::Cancelled)
                || !matches!(
                    t.as_ref().map(|t| t.status.as_str()),
                    Some("failed" | "denied")
                )
            {
                return Err("service_failure_evidence".into());
            }
        }
        AgentTerminal::OutcomeUnknown => {
            if matches!(s.reason, AgentReason::None) {
                return Err("service_unknown_reason".into());
            }
        }
    }
    Ok(())
}
pub(crate) fn persist(
    root: &mut ServiceRoot,
    run: &AgentDurableRun,
    summary: &AgentRunSummary,
) -> Result<()> {
    if root.is_poisoned() {
        return Err("service_root_poisoned".into());
    }
    let dir = root.run_dir(&run.identity.run_id)?;
    validate(&dir, run, summary)?;
    let data = encode(summary).encode();
    if data.len() > 4096 {
        return Err("service_summary_bound".into());
    }
    parse(data.as_bytes())?;
    if let Err(e) = store::atomic(&dir, "summary.db", &data) {
        root.poison();
        return Err(e);
    }
    Ok(())
}
pub(crate) fn unknown(run: &AgentDurableRun, receipt: AgentReceiptSummary) -> AgentRunSnapshot {
    AgentRunSnapshot::Unresolved {
        observation: AgentUnresolvedObservation {
            intent: run.intent.clone(),
            identity: Some(run.identity.clone()),
            receipt,
        },
    }
}
pub(crate) fn restore(root: &ServiceRoot) -> (Vec<AgentRunSnapshot>, bool) {
    let mut snapshots = Vec::new();
    let mut recovery = root.is_poisoned();
    for run in root.runs() {
        let result = (|| {
            let dir = root.run_dir(&run.identity.run_id)?;
            let value = parse(read_bound(&dir.join("summary.db"), 4096)?.as_bytes())?;
            let s = decode(&value)?;
            validate(&dir, run, &s)?;
            Ok::<_, String>(s)
        })();
        match result {
            Ok(s) => {
                if s.terminal == AgentTerminal::OutcomeUnknown {
                    recovery = true
                }
                snapshots.push(AgentRunSnapshot::Terminal { summary: s })
            }
            Err(_) => {
                recovery = true;
                let mut r = root
                    .run_dir(&run.identity.run_id)
                    .ok()
                    .and_then(|d| receipt(&d, run).ok())
                    .unwrap_or(AgentReceiptSummary {
                        opaque_id: None,
                        outcome: AgentReceiptOutcome::Unknown,
                    });
                if r.outcome == AgentReceiptOutcome::NotStarted {
                    r.outcome = AgentReceiptOutcome::Unknown;
                }
                snapshots.push(unknown(run, r));
            }
        }
    }
    (snapshots, recovery)
}
