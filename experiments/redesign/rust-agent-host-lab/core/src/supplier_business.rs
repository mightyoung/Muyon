//! Bounded business protocol owned by the existing Service worker.
//! Host ports are trusted constructor injection, never request payload fields.
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
    pub(crate) mode: Option<crate::service_host::ServiceHostMode>,
    pub(crate) source_binding: Option<Json>,
    pub(crate) host: Option<Arc<crate::service_host::ServiceHostPorts>>,
    pub(crate) events: Vec<Json>,
    pub(crate) dir: Option<PathBuf>,
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
            mode: None,
            source_binding: None,
            host: None,
            events: Vec::new(),
            dir: None,
        })
    }
    pub(crate) fn attach_host(&mut self, host: Option<Arc<crate::service_host::ServiceHostPorts>>) {
        if let Some(host) = &host { self.mode = Some(host.mode); }
        self.host = host;
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
    pub(crate) fn ordinary(conversation:String,text:String)->Result<Self> {
        Ok(Self { payload:crate::ordinary_chat::payload(conversation,text)?,mode:Some(crate::service_host::ServiceHostMode::ConfiguredChat),source_binding:None,host:None,events:Vec::new(),dir:None })
    }
    pub(crate) fn save(&self, dir: &Path) -> Result<()> {
        if crate::ordinary_chat::is_chat(self) {
            return store::atomic(dir,"source.db",&object([("version",string("ordinary-chat-1")),("payload",self.payload.clone()),("binding",self.source_binding.clone().unwrap_or(Json::Null)),("events",Json::Array(self.events.clone()))]).encode());
        }
        let mut data = object([
            ("version", string("supplier-business-1")),
            ("payload", self.payload.clone()),
            ("events", Json::Array(self.events.clone())),
        ]);
        if let Some(mode) = self.mode {
            if let Json::Object(fields) = &mut data {
                fields.insert("version".into(), string("supplier-business-2"));
                fields.insert("host".into(), object([
                    ("mode", string(mode.label())),
                    ("source_binding", self.source_binding.clone().unwrap_or(Json::Null)),
                ]));
            }
        }
        let data = data.encode();
        if data.len() > 16384 {
            return Err("BUSINESS_LEDGER_BOUND".into());
        }
        store::atomic(dir, "source.db", &data)
    }
    pub(crate) fn push(&mut self, kind: &str, payload: Json) {
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
    let version=field(&j,"version")?.string()?;
    if version=="ordinary-chat-1" {
        closed(&j,&["version","payload","binding","events"])?;
        let p=field(&j,"payload")?;closed(p,&["intent","conversation","text"])?;
        let mut b=BusinessRead::ordinary(field(p,"conversation")?.string()?.into(),field(p,"text")?.string()?.into())?;
        if &b.payload!=p {return Err("CHAT_PAYLOAD".into())}
        let binding=field(&j,"binding")?;if binding!=&Json::Null{b.source_binding=Some(binding.clone())}
        b.events=field(&j,"events")?.array()?.to_vec();b.dir=Some(dir.into());validate_events(&b)?;return Ok(b);
    }
    match version {
        "supplier-business-1" => closed(&j, &["version", "payload", "events"])?,
        "supplier-business-2" => closed(&j, &["version", "payload", "events", "host"])?,
        _ => return Err("BUSINESS_VERSION".into()),
    }
    let payload = field(&j, "payload")?;
    closed(payload, &["text", "key", "revision"])?;
    let mut b = BusinessRead::new(
        field(payload, "text")?.string()?.into(),
        field(payload, "key")?.string()?.into(),
        field(payload, "revision")?.string()?.into(),
    )?;
    if version == "supplier-business-2" {
        let host=field(&j,"host")?; closed(host,&["mode","source_binding"])?;
        b.mode=Some(crate::service_host::ServiceHostMode::parse(field(host,"mode")?.string()?)?);
        let binding=field(host,"source_binding")?;
        if binding != &Json::Null {
            closed(binding,&["source_identity","namespace","managed_root","database","source_revision","lineage"])?;
            for key in ["source_identity","namespace","managed_root","database","source_revision"] {
                let value=field(binding,key)?.string()?;
                if value.is_empty() || value.len()>4096 { return Err("BUSINESS_HOST_BINDING".into()); }
            }
            // v2 records without physical lineage are unavailable, never rebound
            // to whichever source currently happens to occupy the same pathname.
            let database=Path::new(field(binding,"database")?.string()?);
            let managed_root=Path::new(field(binding,"managed_root")?.string()?);
            crate::supplier_scope_bridge::HostSupplierSource::new(
                field(binding,"source_identity")?.string()?,field(binding,"namespace")?.string()?,managed_root,database,
            )?;
            let lineage=field(binding,"lineage")?.array()?;
            let components: Vec<_>=database.components().collect();
            if lineage.is_empty() || lineage.len()>128 || lineage.len()!=components.len() {
                return Err("BUSINESS_HOST_LINEAGE".into());
            }
            let mut current=PathBuf::new();
            for (index,(component,identity)) in components.iter().zip(lineage).enumerate() {
                current.push(component.as_os_str());
                closed(identity,&["path","dev","ino","uid","mode"])?;
                if field(identity,"path")?.string()?!=current.to_str().ok_or("BUSINESS_HOST_LINEAGE")? {
                    return Err("BUSINESS_HOST_LINEAGE".into());
                }
                field(identity,"dev")?.integer()?;
                if field(identity,"ino")?.integer()?==0 || field(identity,"uid")?.integer()?>u32::MAX as u64 {
                    return Err("BUSINESS_HOST_LINEAGE".into());
                }
                let mode=field(identity,"mode")?.integer()?;
                let expected_type=if index+1==lineage.len() {0o100000} else {0o040000};
                if mode>u32::MAX as u64 || mode & 0o170000 != expected_type {
                    return Err("BUSINESS_HOST_LINEAGE".into());
                }
            }
            b.source_binding=Some(binding.clone());
        }
    }
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
    if crate::ordinary_chat::is_chat(b) {
        if b.events.is_empty(){return Ok(())}
        let last=b.events.last().ok_or("CHAT_EVENTS")?;
        closed(last,&["cursor","kind","payload"])?;
        if field(last,"kind")?!=&string("terminal"){return Err("CHAT_TERMINAL".into())}
        let terminal=field(last,"payload")?;closed(terminal,&["state","reason"])?;
        match field(terminal,"state")?.string()? {
            "completed" if b.events.len()==3 => {
                if field(&b.events[0],"kind")?!=&string("answer_delta") || field(&b.events[1],"kind")?!=&string("provider_receipt") || field(terminal,"reason")?!=&string("none"){return Err("CHAT_ORDER".into())}
                let answer=field(&b.events[0],"payload")?;closed(answer,&["text"])?;crate::ordinary_chat::check_text(field(answer,"text")?.string()?)?;
                closed(field(&b.events[1],"payload")?,&["owner","identity","task","attempt","synthetic"])?;
            },
            "failed"|"cancelled"|"outcome_unknown" if b.events.len()==1 => (),
            _=>return Err("CHAT_EVENTS".into())
        }
        for (i,e) in b.events.iter().enumerate(){closed(e,&["cursor","kind","payload"])?;if field(e,"cursor")?.integer()?!=i as u64+1{return Err("CHAT_CURSOR".into())}}
        return Ok(())
    }
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
            if name.len() > 512 || field(delta, "text")? != &string(format!("{}{name}", if b.mode.is_some() { "供应商：" } else { "合成供应商：" }))
            {
                return Err("BUSINESS_ANSWER_BINDING".into());
            }
        }
        "failed" if b.mode.is_some() && b.events.len() == 1 => (),
        "cancelled" | "outcome_unknown" if b.events.len() == 1 => (),
        "outcome_unknown"
            if b.events.len() == 2 && field(&b.events[0], "kind")? == &string("receipt") =>
        {
            ()
        }
        _ => return Err("BUSINESS_TERMINAL".into()),
    }
    Ok(())
}
pub(crate) fn restore_all(root: &ServiceRoot, host: Option<Arc<crate::service_host::ServiceHostPorts>>) -> BTreeMap<String, BusinessRead> {
    root.runs()
        .iter()
        .filter_map(|run| {
            let mut business=load(&root.run_dir(&run.identity.run_id).ok()?).ok()?;
            // Never relabel history from a different execution mode.
            if host.as_ref().is_some_and(|h|Some(h.mode)!=business.mode) { return None; }
            business.host=host.as_ref().filter(|h|Some(h.mode)==business.mode).cloned();
            Some((run.intent.request_id.clone(), business))
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
        || !matches!(field(row, "status")?.string()?, "succeeded" | "failed")
    {
        return Err("BUSINESS_RECEIPT_BINDING".into());
    }
    let projection = b
        .events
        .iter()
        .find(|e| field(e, "kind").ok() == Some(&string("supplier_projection")));
    let receipt = b
        .events
        .iter()
        .find(|e| field(e, "kind").ok() == Some(&string("receipt")))
        .ok_or("BUSINESS_RECEIPT_MISSING")?;
    if field(receipt, "payload")? != field(row, "identity")?
        || projection
            .map(|e| field(e, "payload"))
            .transpose()?
            .is_some_and(|p| Some(p) != field(row, "raw").ok())
    {
        return Err("BUSINESS_ORIGINAL_MISMATCH".into());
    }
    Ok(AgentReceiptSummary {
        opaque_id: Some(field(field(row, "identity")?, "identity")?.string()?.into()),
        outcome: if field(row, "status")? == &string("succeeded") {
            AgentReceiptOutcome::RecordedSuccess
        } else {
            AgentReceiptOutcome::RecordedFailure
        },
    })
}
pub(crate) fn restore_snapshot(dir: &Path, run: &AgentDurableRun) -> Result<AgentRunSnapshot> {
    let b = load(dir)?;
    if crate::ordinary_chat::is_chat(&b){return crate::ordinary_chat::restore(dir,run,&b)}
    // The payload-only ledger is the real crash window after native execution.
    // It must reconcile the original receipt using the pre-dispatch task binding.
    let state = match b.events.last() {
        Some(last) => {
            if field(last, "kind")? != &string("terminal") {
                return Err("BUSINESS_INTERRUPTED".into());
            }
            field(field(last, "payload")?, "state")?.string()?
        }
        None => "outcome_unknown",
    };
    let (terminal, reason, receipt) = if state == "completed" {
        let receipt = receipt_evidence(dir, run, &b)?;
        if receipt.outcome != AgentReceiptOutcome::RecordedSuccess {
            return Err("BUSINESS_COMPLETION_RECEIPT".into());
        }
        (AgentTerminal::Completed, AgentReason::None, receipt)
    } else if state == "failed" && b.mode.is_some() {
        if dir.join("native.db").exists() { return Err("BUSINESS_FAILED_RECEIPT".into()); }
        (AgentTerminal::Failed, AgentReason::InternalFailure, AgentReceiptSummary { opaque_id: None, outcome: AgentReceiptOutcome::NotStarted })
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
    if crate::ordinary_chat::is_chat(b){return crate::ordinary_chat::execute(root,run,dir,b,control)}
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
        if b.mode == Some(crate::service_host::ServiceHostMode::LocalRead) {
            b.source_binding=Some(b.host.as_ref().ok_or("host_owner_unavailable")?.source_binding()?);
        }
        b.save(dir)?;
        control.poll()?;
        if b.mode == Some(crate::service_host::ServiceHostMode::ConfiguredChat) {
            let error = b.host.as_ref().ok_or("host_owner_unavailable")?.configured_readiness().err().ok_or("configured_transport_unavailable")?;
            summary.terminal=AgentTerminal::Failed;
            summary.reason=AgentReason::InternalFailure;
            summary.receipt=AgentReceiptSummary { opaque_id: None, outcome: AgentReceiptOutcome::NotStarted };
            // Readiness performs no reservation, outbound commit, or model exchange.
            b.push("terminal",object([("state",string("failed")),("reason",string(error))]));
            return Ok(());
        }
        let mut admitted = |state: &muyon_core_agent_lab::agent::State| {
            let actual=AgentTaskIdentity {task_id:state.task.clone(),attempt_id:state.attempt.clone()};
            root.attach_task(&run.identity.run_id,actual.clone())?;
            run.identity.actual_task=Some(actual); summary.identity=run.identity.clone(); Ok(())
        };
        let result = if b.mode.is_some() {
            b.host.as_ref().ok_or("host_owner_unavailable")?.read_admitted(dir,&b.payload,b.source_binding.as_ref().ok_or("host_source_binding_unavailable")?,control.clone(),&mut admitted)?
        } else {
            crate::supplier_lab_source::run_lab_supplier_read_admitted(dir,field(&b.payload,"text")?.string()?,field(&b.payload,"key")?.string()?,field(&b.payload,"revision")?.string()?,control.clone(),&mut admitted)?
        };
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
            object([("text", string(format!("{}{name}", if b.mode.is_some() { "供应商：" } else { "合成供应商：" })))]),
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
    if summary.terminal == AgentTerminal::OutcomeUnknown {
        if let Ok(history) = unknown_business(b, run, &summary.receipt) {
            *b = history;
        }
    }
    let state = match summary.terminal {
        AgentTerminal::Completed => "completed",
        AgentTerminal::Cancelled => "cancelled",
        AgentTerminal::Failed => "failed",
        _ => "outcome_unknown",
    };
    let failure_reason = if state == "failed" { b.events.last().and_then(|e|field(e,"payload").ok()).and_then(|p|field(p,"reason").ok()).and_then(|r|r.string().ok()).unwrap_or("configured_provider_unavailable").to_owned() } else { String::new() };
    if b.events
        .last()
        .is_some_and(|e| field(e, "kind").ok() == Some(&string("terminal")))
    {
        b.events.pop();
    }
    b.push(
        "terminal",
        object([
            ("state", string(state)),
            (
                "reason",
                string(if state == "failed" {
                    &failure_reason
                } else if state == "completed" {
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
        *b = unknown_business(b, run, &summary.receipt).unwrap_or_else(|_| {
            let mut fallback = b.clone();
            fallback.events.clear();
            fallback.push(
                "terminal",
                object([
                    ("state", string("outcome_unknown")),
                    ("reason", string("storage_failure")),
                ]),
            );
            fallback
        });
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
    let mut terminal = status == "unknown";
    let mut next = after;
    let mut reason = reason.to_owned();
    let mut status = status;
    if let Some(b) = business {
        let disclosed = (|| {
            validate_events(b)?;
            if crate::ordinary_chat::is_chat(b){crate::ordinary_chat::disclose(b)?;return Ok(())}
            if let Some(mode)=b.mode.filter(|_|!b.events.is_empty()) {
                let host=b.host.as_ref().filter(|h|h.mode==mode).ok_or("host_owner_unavailable")?;
                if mode==crate::service_host::ServiceHostMode::LocalRead && b.source_binding.is_some() {
                    host.validate(b.dir.as_ref().ok_or("host_run_unavailable")?,&b.payload,b.source_binding.as_ref().ok_or("host_source_binding_unavailable")?,None)?;
                }
            }
            if after > b.events.len() as i64 {
                return Err("BUSINESS_CURSOR_AHEAD".into());
            }
            let Some(dir) = &b.dir else {
                return Ok::<(), String>(());
            };
            if b.events
                .iter()
                .any(|e| field(e, "kind").ok() == Some(&string("receipt")))
            {
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
                if b.mode.is_some() {
                    b.host.as_ref().ok_or("host_owner_unavailable")?.validate(dir,&b.payload,b.source_binding.as_ref().ok_or("host_source_binding_unavailable")?,Some(field(projection,"payload")?))?;
                } else {
                    crate::supplier_lab_source::validate_lab_supplier_projection(dir,field(&b.payload,"key")?.string()?,field(&b.payload,"revision")?.string()?,field(projection,"payload")?)?;
                }
            }
            Ok(())
        })();
        if disclosed.is_err() {
            reason = "DISCLOSURE_UNAVAILABLE".into();
            status = "unknown";
            terminal = true;
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
        ("synthetic", Json::Bool(business.map(|b|crate::ordinary_chat::is_chat(b)||b.mode.is_none()).unwrap_or(true))),
    ])
    .encode()
}

/// Reconcile terminal controller state before exposing a stream. This also covers
/// final-ledger persistence failure, where volatile successful events are unsafe.
pub(crate) fn snapshot_reply(
    snapshot: &AgentRunSnapshot,
    business: Option<&BusinessRead>,
    after: i64,
) -> String {
    let (request, identity, receipt, unknown) = match snapshot {
        AgentRunSnapshot::Terminal { summary } => (
            &summary.request_id,
            Some(&summary.identity),
            &summary.receipt,
            summary.terminal == AgentTerminal::OutcomeUnknown,
        ),
        AgentRunSnapshot::Unresolved { observation } => (
            &observation.intent.request_id,
            observation.identity.as_ref(),
            &observation.receipt,
            true,
        ),
        _ => unreachable!(),
    };
    if !unknown {
        return reply("events", "none", request, identity, business, after);
    }
    let history = (|| {
        let b = business.ok_or("BUSINESS_HISTORY_UNAVAILABLE")?;
        let identity = identity.ok_or("BUSINESS_IDENTITY_MISSING")?;
        let run = AgentDurableRun {
            intent: AgentIntentBinding {
                request_id: request.clone(),
                variant: AgentReadVariant::Inquiry,
                source_build_identity: String::new(),
            },
            identity: identity.clone(),
        };
        unknown_business(b, &run, receipt)
    })();
    match history {
        Ok(b) => reply(
            "events",
            "OUTCOME_UNKNOWN",
            request,
            identity,
            Some(&b),
            after,
        ),
        Err(_) => reply("unknown", "OUTCOME_UNKNOWN", request, identity, None, after),
    }
}
/// Historical metadata has its own fixed lab lookup scope. It does not authorize
/// source values or a projection, and requires the original native receipt.
fn unknown_business(
    b: &BusinessRead,
    run: &AgentDurableRun,
    expected: &AgentReceiptSummary,
) -> Result<BusinessRead> {
    if crate::ordinary_chat::is_chat(b){let mut history=b.clone();history.events.clear();history.push("terminal",object([("state",string("outcome_unknown")),("reason",string("chat_outcome_unknown"))]));return Ok(history)}
    if b.mode.is_none() && (field(&b.payload, "key")? != &string(crate::supplier_lab_source::LAB_SUPPLIER_KEY)
        || field(&b.payload, "revision")?
            != &string(crate::supplier_lab_source::LAB_SUPPLIER_REVISION))
    {
        return Err("BUSINESS_HISTORY_SCOPE".into());
    }
    let mut history = b.clone();
    history.events.clear();
    if expected.opaque_id.is_some() {
        let dir = b.dir.as_ref().ok_or("BUSINESS_HISTORY_UNAVAILABLE")?;
        let (rows, _) = NativeStore::read_service_evidence(dir)?;
        if rows.len() != 1 {
            return Err("BUSINESS_RECEIPT_COUNT".into());
        }
        let original = field(&rows[0], "identity")?;
        if let Some(recorded) = b
            .events
            .iter()
            .find(|e| field(e, "kind").ok() == Some(&string("receipt")))
        {
            if field(recorded, "payload")? != original {
                return Err("BUSINESS_ORIGINAL_MISMATCH".into());
            }
        }
        history.push("receipt", original.clone());
        if &receipt_evidence(dir, run, &history)? != expected {
            return Err("BUSINESS_ORIGINAL_MISMATCH".into());
        }
    }
    history.push(
        "terminal",
        object([
            ("state", string("outcome_unknown")),
            ("reason", string("storage_or_authority_failure")),
        ]),
    );
    Ok(history)
}

#[cfg(test)]
mod terminal_regressions {
    use super::*;
    use crate::supplier_lab_source::{LAB_SUPPLIER_KEY, LAB_SUPPLIER_REVISION};
    fn fixture() -> (PathBuf, ServiceRoot, AgentDurableRun, BusinessRead, Json) {
        let path =
            std::env::temp_dir().join(format!("business-terminal-{}", crate::nonce().unwrap()));
        store::create_dir(&path).unwrap();
        let mut root = ServiceRoot::open(&path).unwrap();
        let mut run = root
            .admit(
                AgentIntentBinding {
                    request_id: "terminal_read".into(),
                    variant: AgentReadVariant::Inquiry,
                    source_build_identity: "a".repeat(40),
                },
                &"b".repeat(32),
            )
            .unwrap();
        let dir = root.run_dir(&run.identity.run_id).unwrap();
        let result = crate::supplier_lab_source::run_lab_supplier_read(
            &dir,
            "read",
            LAB_SUPPLIER_KEY,
            LAB_SUPPLIER_REVISION,
            Arc::new(RunControl::new()),
        )
        .unwrap();
        let task = AgentTaskIdentity {
            task_id: result.task_id,
            attempt_id: result.attempt_id,
        };
        root.attach_task(&run.identity.run_id, task.clone())
            .unwrap();
        run.identity.actual_task = Some(task);
        let mut b = BusinessRead::new(
            "read".into(),
            LAB_SUPPLIER_KEY.into(),
            LAB_SUPPLIER_REVISION.into(),
        )
        .unwrap();
        b.dir = Some(dir);
        (path, root, run, b, result.receipt_ref)
    }
    fn unknown_summary(run: &AgentDurableRun, receipt: &Json) -> AgentRunSnapshot {
        AgentRunSnapshot::Terminal {
            summary: AgentRunSummary {
                request_id: run.intent.request_id.clone(),
                variant: run.intent.variant.clone(),
                source_build_identity: run.intent.source_build_identity.clone(),
                identity: run.identity.clone(),
                terminal: AgentTerminal::OutcomeUnknown,
                reason: AgentReason::StorageFailure,
                receipt: AgentReceiptSummary {
                    opaque_id: Some(field(receipt, "identity").unwrap().string().unwrap().into()),
                    outcome: AgentReceiptOutcome::RecordedSuccess,
                },
            },
        }
    }
    #[test]
    fn task_identity_is_durable_before_dispatch_creates_a_receipt() {
        let path =
            std::env::temp_dir().join(format!("business-admitted-{}", crate::nonce().unwrap()));
        store::create_dir(&path).unwrap();
        let mut root = ServiceRoot::open(&path).unwrap();
        let run = root
            .admit(
                AgentIntentBinding {
                    request_id: "before_dispatch".into(),
                    variant: AgentReadVariant::Inquiry,
                    source_build_identity: "a".repeat(40),
                },
                &"b".repeat(32),
            )
            .unwrap();
        let dir = root.run_dir(&run.identity.run_id).unwrap();
        let mut seen = false;
        let mut payload = BusinessRead::new(
            "original chat text".into(),
            LAB_SUPPLIER_KEY.into(),
            LAB_SUPPLIER_REVISION.into(),
        )
        .unwrap();
        payload.dir = Some(dir.clone());
        payload.save(&dir).unwrap();
        let result = crate::supplier_lab_source::run_lab_supplier_read_admitted(
            &dir,
            "original chat text",
            LAB_SUPPLIER_KEY,
            LAB_SUPPLIER_REVISION,
            Arc::new(RunControl::new()),
            |state| {
                let native = parse(&std::fs::read(dir.join("native.db")).unwrap())?;
                assert!(field(&native, "receipts")?.array()?.is_empty());
                root.attach_task(
                    &run.identity.run_id,
                    AgentTaskIdentity {
                        task_id: state.task.clone(),
                        attempt_id: state.attempt.clone(),
                    },
                )?;
                assert!(root.runs()[0].identity.actual_task.is_some());
                // Check the actual durable index, not only the in-memory root.
                assert!(
                    std::fs::read_to_string(dir.parent().unwrap().join("index.db"))
                        .unwrap()
                        .contains(&state.task)
                );
                seen = true;
                Ok(())
            },
        )
        .unwrap();
        assert!(seen);
        let task = root.runs()[0].identity.actual_task.as_ref().unwrap();
        assert_eq!(task.task_id, result.task_id);
        assert_eq!(task.attempt_id, result.attempt_id);
        // Simulate process death immediately after receipt commit, before events.
        let restored = restore_snapshot(&dir, &root.runs()[0]).unwrap();
        let replay =
            parse(snapshot_reply(&restored, Some(&load(&dir).unwrap()), 0).as_bytes()).unwrap();
        assert_eq!(field(&replay, "terminal").unwrap(), &Json::Bool(true));
        let events = field(&replay, "events").unwrap().array().unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(field(&events[0], "payload").unwrap(), &result.receipt_ref);
        drop(root);
        std::fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn failed_final_ledger_is_unknown_terminal_not_pending_or_completed() {
        let (path, root, run, b, receipt) = fixture();
        // This is exactly the post-final-save-failure state: terminal summary,
        // empty volatile events, and an original durable successful receipt.
        let snapshot = unknown_summary(&run, &receipt);
        let reply = parse(snapshot_reply(&snapshot, Some(&b), 0).as_bytes()).unwrap();
        assert_eq!(field(&reply, "terminal").unwrap(), &Json::Bool(true));
        assert_eq!(field(&reply, "status").unwrap(), &string("events"));
        let events = field(&reply, "events").unwrap().array().unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(field(&events[0], "payload").unwrap(), &receipt);
        assert_eq!(
            field(field(&events[1], "payload").unwrap(), "state").unwrap(),
            &string("outcome_unknown")
        );
        assert!(!reply.encode().contains("合成供应商甲"));
        drop(root);
        std::fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn interrupted_receipt_survives_restart_without_projection_or_new_receipt() {
        let (path, root, run, mut b, receipt) = fixture();
        let dir = b.dir.clone().unwrap();
        let original = std::fs::read(dir.join("native.db")).unwrap();
        b.push("receipt", receipt.clone());
        b.push(
            "terminal",
            object([
                ("state", string("outcome_unknown")),
                ("reason", string("interrupted")),
            ]),
        );
        b.save(&dir).unwrap();
        let restored = restore_snapshot(&dir, &run).unwrap();
        let loaded = load(&dir).unwrap();
        let reply = parse(snapshot_reply(&restored, Some(&loaded), 0).as_bytes()).unwrap();
        assert_eq!(field(&reply, "terminal").unwrap(), &Json::Bool(true));
        let events = field(&reply, "events").unwrap().array().unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(field(&events[0], "payload").unwrap(), &receipt);
        assert!(!reply.encode().contains("合成供应商甲"));
        assert_eq!(std::fs::read(dir.join("native.db")).unwrap(), original);
        // Forged metadata fails the exact original identity check.
        let mut forged = loaded.clone();
        forged.events[0] = object([
            ("cursor", Json::Number("1".into())),
            ("kind", string("receipt")),
            ("payload", object([("identity", string("fake"))])),
        ]);
        let denied = parse(snapshot_reply(&restored, Some(&forged), 0).as_bytes()).unwrap();
        assert_eq!(field(&denied, "status").unwrap(), &string("unknown"));
        assert!(field(&denied, "events")
            .unwrap()
            .array()
            .unwrap()
            .is_empty());
        drop(root);
        std::fs::remove_dir_all(path).unwrap();
    }
}
