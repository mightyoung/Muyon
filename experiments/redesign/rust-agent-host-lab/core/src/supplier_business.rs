//! Private bounded synthetic business protocol, owned by the existing Service worker.
//! No model, endpoint, production authority, or UI supplied path is accepted here.
use crate::{
    field, service_root::ServiceRoot, service_runtime::RunControl, service_types::*,
    store::NativeStore, Result,
};
use muyon_core_agent_lab::store;
use muyon_plugin_contract_lab::{object, parse, string, Json};
use std::{
    collections::BTreeMap,
    io::Read,
    path::{Path, PathBuf},
    sync::Arc,
};
#[derive(Clone)]
pub(crate) struct BusinessRead {
    pub payload: Json,
    events: Vec<Json>,
    dir: Option<PathBuf>,
}
impl BusinessRead {
    pub fn new(text: String, key: String, revision: String) -> Result<Self> {
        if text.trim().is_empty()
            || text.len() > 4096
            || key.is_empty()
            || key.len() > 128
            || revision.is_empty()
            || revision.len() > 128
            || key.contains('\0')
            || revision.contains('\0')
        {
            return Err("INVALID_PAYLOAD".into());
        }
        Ok(Self {
            payload: object([
                ("text", string(text)),
                ("key", string(key)),
                ("revision", string(revision)),
            ]),
            events: Vec::new(),
            dir: None,
        })
    }
    pub(crate) fn cancel_before_admission(&mut self) {
        self.events.clear();
        self.push(
            "terminal",
            object([
                ("state", string("cancelled")),
                ("reason", string("cancelled_before_admission")),
            ]),
        );
    }
    fn save(&self, dir: &Path) -> Result<()> {
        let data = object([
            ("version", string("supplier-business-1")),
            ("payload", self.payload.clone()),
            ("events", Json::Array(self.events.clone())),
        ])
        .encode();
        if data.len() > 16384 {
            return Err("BUSINESS_LEDGER_BOUND".into());
        }
        store::atomic(dir, "source.db", &data)
    }
    fn push(&mut self, kind: &str, payload: Json) {
        self.events.push(object([
            ("cursor", Json::Number((self.events.len() + 1).to_string())),
            ("kind", string(kind)),
            ("payload", payload),
        ]));
    }
}
fn closed(j: &Json, names: &[&str]) -> Result<()> {
    let m = j.object()?;
    if m.len() != names.len() || names.iter().any(|k| !m.contains_key(*k)) {
        return Err("BUSINESS_FIELDS".into());
    }
    Ok(())
}
pub(crate) fn load(dir: &Path) -> Result<BusinessRead> {
    let path = dir.join("source.db");
    let m = std::fs::symlink_metadata(&path).map_err(|_| "BUSINESS_MISSING")?;
    if !m.is_file() || m.file_type().is_symlink() || m.len() > 16384 {
        return Err("BUSINESS_LEDGER_BOUND".into());
    }
    let mut bytes = Vec::new();
    std::fs::File::open(path)
        .map_err(|_| "BUSINESS_READ")?
        .take(16385)
        .read_to_end(&mut bytes)
        .map_err(|_| "BUSINESS_READ")?;
    if bytes.len() > 16384 {
        return Err("BUSINESS_LEDGER_BOUND".into());
    }
    let j = parse(&bytes)?;
    closed(&j, &["version", "payload", "events"])?;
    if field(&j, "version")? != &string("supplier-business-1") {
        return Err("BUSINESS_VERSION".into());
    }
    let payload = field(&j, "payload")?;
    closed(payload, &["text", "key", "revision"])?;
    let mut b = BusinessRead::new(
        field(payload, "text")?.string()?.into(),
        field(payload, "key")?.string()?.into(),
        field(payload, "revision")?.string()?.into(),
    )?;
    b.events = field(&j, "events")?.array()?.to_vec();
    b.dir = Some(dir.into());
    if b.events.len() > 4 {
        return Err("BUSINESS_EVENT_BOUND".into());
    }
    for (i, e) in b.events.iter().enumerate() {
        closed(e, &["cursor", "kind", "payload"])?;
        if field(e, "cursor")?.integer()? != (i + 1) as u64 {
            return Err("BUSINESS_CURSOR".into());
        }
    }
    validate_events(&b)?;
    Ok(b)
}
fn validate_events(b: &BusinessRead) -> Result<()> {
    if b.events.is_empty() {
        return Ok(());
    }
    let last = b.events.last().ok_or("BUSINESS_EVENTS")?;
    if field(last, "kind")? != &string("terminal") {
        return Err("BUSINESS_EVENTS".into());
    }
    let terminal = field(last, "payload")?;
    closed(terminal, &["state", "reason"])?;
    match field(terminal, "state")?.string()? {
        "completed" => {
            if b.events.len() != 4 || field(terminal, "reason")? != &string("none") {
                return Err("BUSINESS_COMPLETION".into());
            }
            for (e, kind) in
                b.events
                    .iter()
                    .zip(["answer_delta", "supplier_projection", "receipt", "terminal"])
            {
                if field(e, "kind")? != &string(kind) {
                    return Err("BUSINESS_ORDER".into());
                }
            }
            let delta = field(&b.events[0], "payload")?;
            closed(delta, &["text"])?;
            let projection = field(&b.events[1], "payload")?;
            closed(projection, &["supplier", "name"])?;
            let name = field(projection, "name")?.string()?;
            if name.len() > 512 || field(delta, "text")? != &string(format!("合成供应商：{name}"))
            {
                return Err("BUSINESS_ANSWER_BINDING".into());
            }
        }
        "cancelled" | "outcome_unknown" if b.events.len() == 1 => (),
        _ => return Err("BUSINESS_TERMINAL".into()),
    }
    Ok(())
}
pub(crate) fn restore_all(root: &ServiceRoot) -> BTreeMap<String, BusinessRead> {
    root.runs()
        .iter()
        .filter_map(|run| {
            Some((
                run.intent.request_id.clone(),
                load(&root.run_dir(&run.identity.run_id).ok()?).ok()?,
            ))
        })
        .collect()
}
fn receipt_evidence(
    dir: &Path,
    run: &AgentDurableRun,
    b: &BusinessRead,
) -> Result<AgentReceiptSummary> {
    let (rows, _) = NativeStore::read_service_evidence(dir)?;
    if rows.len() != 1 {
        return Err("BUSINESS_RECEIPT_COUNT".into());
    }
    let row = &rows[0];
    let binding = field(row, "binding")?;
    let task = run
        .identity
        .actual_task
        .as_ref()
        .ok_or("BUSINESS_TASK_MISSING")?;
    let key = field(&b.payload, "key")?;
    let reference = object([
        ("module_id", string("inquiry")),
        ("type", string("supplier")),
        ("key", key.clone()),
        ("revision", field(&b.payload, "revision")?.clone()),
        ("schema_version", Json::Number("1".into())),
    ]);
    if field(binding, "task")? != &string(&task.task_id)
        || field(binding, "attempt")? != &string(&task.attempt_id)
        || field(binding, "operation")? != &string("inquiry/supplier_name@1")
        || field(binding, "args")? != &object([("id", key.clone())])
        || field(binding, "scope_refs")? != &Json::Array(vec![reference])
        || field(field(row, "identity")?, "binding_id")? != &string("host-supplier-name-read")
        || field(row, "status")? != &string("succeeded")
    {
        return Err("BUSINESS_RECEIPT_BINDING".into());
    }
    let projection = b
        .events
        .iter()
        .find(|e| field(e, "kind").ok() == Some(&string("supplier_projection")))
        .ok_or("BUSINESS_PROJECTION_MISSING")?;
    let receipt = b
        .events
        .iter()
        .find(|e| field(e, "kind").ok() == Some(&string("receipt")))
        .ok_or("BUSINESS_RECEIPT_MISSING")?;
    if field(receipt, "payload")? != field(row, "identity")?
        || field(projection, "payload")? != field(row, "raw")?
    {
        return Err("BUSINESS_ORIGINAL_MISMATCH".into());
    }
    Ok(AgentReceiptSummary {
        opaque_id: Some(field(field(row, "identity")?, "identity")?.string()?.into()),
        outcome: AgentReceiptOutcome::RecordedSuccess,
    })
}
pub(crate) fn restore_snapshot(dir: &Path, run: &AgentDurableRun) -> Result<AgentRunSnapshot> {
    let b = load(dir)?;
    let last = b.events.last().ok_or("BUSINESS_INTERRUPTED")?;
    if field(last, "kind")? != &string("terminal") {
        return Err("BUSINESS_INTERRUPTED".into());
    }
    let state = field(field(last, "payload")?, "state")?.string()?;
    let (terminal, reason, receipt) = if state == "completed" {
        (
            AgentTerminal::Completed,
            AgentReason::None,
            receipt_evidence(dir, run, &b)?,
        )
    } else if state == "cancelled" {
        (
            AgentTerminal::Cancelled,
            AgentReason::Cancelled,
            AgentReceiptSummary {
                opaque_id: None,
                outcome: AgentReceiptOutcome::NotStarted,
            },
        )
    } else {
        let recovered = (|| {
            let (rows, _) = NativeStore::read_service_evidence(dir)?;
            if rows.len() != 1 {
                return Err("BUSINESS_RECEIPT_COUNT".into());
            }
            let row = &rows[0];
            let mut check = b.clone();
            check.events.clear();
            check.push("supplier_projection", field(row, "raw")?.clone());
            check.push("receipt", field(row, "identity")?.clone());
            receipt_evidence(dir, run, &check)
        })()
        .unwrap_or(AgentReceiptSummary {
            opaque_id: None,
            outcome: AgentReceiptOutcome::Unknown,
        });
        return Ok(crate::service_evidence::unknown(run, recovered));
    };
    // A cancelled record must not conceal a receipt-bearing read.
    if terminal == AgentTerminal::Cancelled && dir.join("native.db").exists() {
        let (rows, _) = NativeStore::read_service_evidence(dir)?;
        if !rows.is_empty() {
            return Err("BUSINESS_CANCEL_RECEIPT".into());
        }
    }
    Ok(AgentRunSnapshot::Terminal {
        summary: AgentRunSummary {
            request_id: run.intent.request_id.clone(),
            variant: run.intent.variant.clone(),
            source_build_identity: run.intent.source_build_identity.clone(),
            identity: run.identity.clone(),
            terminal,
            reason,
            receipt,
        },
    })
}
pub(crate) fn execute(
    root: &mut ServiceRoot,
    run: &mut AgentDurableRun,
    dir: &Path,
    b: &mut BusinessRead,
    control: Arc<RunControl>,
) -> AgentRunSummary {
    b.dir = Some(dir.into());
    let mut summary = AgentRunSummary {
        request_id: run.intent.request_id.clone(),
        variant: run.intent.variant.clone(),
        source_build_identity: run.intent.source_build_identity.clone(),
        identity: run.identity.clone(),
        terminal: AgentTerminal::OutcomeUnknown,
        reason: AgentReason::StorageFailure,
        receipt: AgentReceiptSummary {
            opaque_id: None,
            outcome: AgentReceiptOutcome::Unknown,
        },
    };
    // Durable semantic identity precedes any physical business read.
    let result = (|| {
        b.save(dir)?;
        control.poll()?;
        let result = crate::supplier_lab_source::run_lab_supplier_read(
            dir,
            field(&b.payload, "text")?.string()?,
            field(&b.payload, "key")?.string()?,
            field(&b.payload, "revision")?.string()?,
            control.clone(),
        )?;
        let (rows, _) = NativeStore::read_service_evidence(dir)?;
        let row = rows.first().ok_or("BUSINESS_RECEIPT_MISSING")?;
        let binding = field(row, "binding")?;
        let actual = AgentTaskIdentity {
            task_id: field(binding, "task")?.string()?.into(),
            attempt_id: field(binding, "attempt")?.string()?.into(),
        };
        root.attach_task(&run.identity.run_id, actual.clone())?;
        run.identity.actual_task = Some(actual);
        summary.identity = run.identity.clone();
        let name = field(&result.projection, "name")?.string()?;
        if name.len() > 512 {
            return Err("BUSINESS_NAME_BOUND".into());
        }
        b.push(
            "answer_delta",
            object([("text", string(format!("合成供应商：{name}")))]),
        );
        b.push("supplier_projection", result.projection);
        b.push("receipt", result.receipt_ref);
        summary.receipt = receipt_evidence(dir, run, b)?;
        summary.terminal = AgentTerminal::Completed;
        summary.reason = AgentReason::None;
        Ok::<(), String>(())
    })();
    if let Err(error) = result {
        // A cancellation before any receipt is definite; any receipt-bearing interruption is UNKNOWN.
        if error == "native_cancelled"
            && NativeStore::read_service_evidence(dir)
                .map(|(rows, _)| rows.is_empty())
                .unwrap_or(!dir.join("native.db").exists())
        {
            summary.terminal = AgentTerminal::Cancelled;
            summary.reason = AgentReason::Cancelled;
            summary.receipt = AgentReceiptSummary {
                opaque_id: None,
                outcome: AgentReceiptOutcome::NotStarted,
            };
        }
        // Preserve a genuinely recorded receipt even if cancellation/disclosure loses
        // the race after physical execution. Do not republish its business values.
        let recovered = (|| {
            let (rows, _) = NativeStore::read_service_evidence(dir)?;
            if rows.len() != 1 {
                return Err("BUSINESS_RECEIPT_COUNT".into());
            }
            let row = &rows[0];
            let binding = field(row, "binding")?;
            let task = AgentTaskIdentity {
                task_id: field(binding, "task")?.string()?.into(),
                attempt_id: field(binding, "attempt")?.string()?.into(),
            };
            root.attach_task(&run.identity.run_id, task.clone())?;
            run.identity.actual_task = Some(task);
            summary.identity = run.identity.clone();
            let mut check = b.clone();
            check.events.clear();
            check.push("supplier_projection", field(row, "raw")?.clone());
            check.push("receipt", field(row, "identity")?.clone());
            receipt_evidence(dir, run, &check)
        })();
        if let Ok(receipt) = recovered {
            summary.receipt = receipt;
        }
        b.events.clear();
    }
    let state = match summary.terminal {
        AgentTerminal::Completed => "completed",
        AgentTerminal::Cancelled => "cancelled",
        _ => "outcome_unknown",
    };
    b.push(
        "terminal",
        object([
            ("state", string(state)),
            (
                "reason",
                string(if state == "completed" {
                    "none"
                } else if state == "cancelled" {
                    "cancelled"
                } else {
                    "storage_or_authority_failure"
                }),
            ),
        ]),
    );
    if b.save(dir).is_err() {
        summary.terminal = AgentTerminal::OutcomeUnknown;
        summary.reason = AgentReason::StorageFailure;
        b.events.clear();
        root.poison();
    }
    summary
}
pub(crate) fn reply(
    status: &str,
    reason: &str,
    request: &str,
    identity: Option<&AgentRunIdentity>,
    business: Option<&BusinessRead>,
    after: i64,
) -> String {
    let request = if request.len() <= 64 { request } else { "" };
    let mut events = Vec::new();
    let mut terminal = false;
    let mut next = after;
    let mut reason = reason.to_owned();
    let mut status = status;
    if let Some(b) = business {
        let disclosed = (|| {
            validate_events(b)?;
            if after > b.events.len() as i64 {
                return Err("BUSINESS_CURSOR_AHEAD".into());
            }
            let Some(dir) = &b.dir else {
                return Ok::<(), String>(());
            };
            if b.events.len() == 4 {
                let identity = identity.ok_or("BUSINESS_IDENTITY_MISSING")?;
                let run = AgentDurableRun {
                    intent: AgentIntentBinding {
                        request_id: request.into(),
                        variant: AgentReadVariant::Inquiry,
                        source_build_identity: String::new(),
                    },
                    identity: identity.clone(),
                };
                receipt_evidence(dir, &run, b)?;
            }
            if let Some(projection) = b
                .events
                .iter()
                .find(|e| field(e, "kind").ok() == Some(&string("supplier_projection")))
            {
                crate::supplier_lab_source::validate_lab_supplier_projection(
                    dir,
                    field(&b.payload, "key")?.string()?,
                    field(&b.payload, "revision")?.string()?,
                    field(projection, "payload")?,
                )?;
            }
            Ok(())
        })();
        if disclosed.is_err() {
            reason = "DISCLOSURE_UNAVAILABLE".into();
            status = "unknown";
        } else {
            terminal = b
                .events
                .last()
                .is_some_and(|e| field(e, "kind").ok() == Some(&string("terminal")));
            events = b
                .events
                .iter()
                .filter(|e| {
                    field(e, "cursor")
                        .and_then(Json::integer)
                        .map(|n| n > after as u64)
                        .unwrap_or(false)
                })
                .cloned()
                .collect();
            next = b.events.len() as i64;
        }
    }
    object([
        ("protocol", Json::Number("1".into())),
        ("status", string(status)),
        ("reason", string(reason)),
        ("request_id", string(request)),
        (
            "run_id",
            identity.map(|i| string(&i.run_id)).unwrap_or(Json::Null),
        ),
        (
            "admitted_service_epoch",
            identity
                .map(|i| string(&i.admitted_service_epoch))
                .unwrap_or(Json::Null),
        ),
        ("events", Json::Array(events)),
        ("next_cursor", Json::Number(next.to_string())),
        ("terminal", Json::Bool(terminal)),
        ("synthetic", Json::Bool(true)),
    ])
    .encode()
}
