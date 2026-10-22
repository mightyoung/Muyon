//! Sole Service root lease and durable admission index. No handler or Agent loop.
use crate::{field, service_types::*, Result};
use muyon_core_agent_lab::store::{self, DirectoryLock};
use muyon_plugin_contract_lab::{object, parse, string, Json};
use std::{
    fs,
    io::Read,
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::{Path, PathBuf},
};
const ROOT_BYTES: u64 = 8 * 1024 * 1024;
const PEAK_BYTES: u64 = 2 * 1024 * 1024;
const INDEX_BYTES: usize = 65536;
const NAMESPACE: &str = "native-agent-service-v1";
pub struct ServiceRoot {
    dir: PathBuf,
    _lock: DirectoryLock,
    runs: Vec<AgentDurableRun>,
    poisoned: bool,
}
fn hex_id(s: &str, n: usize) -> bool {
    s.len() == n
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn request_id(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 64
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}
fn variant(v: &AgentReadVariant) -> &'static str {
    match v {
        AgentReadVariant::Equipment => "equipment",
        AgentReadVariant::Research => "research",
        AgentReadVariant::Inquiry => "inquiry",
        AgentReadVariant::SeededEquipment => "seeded_equipment",
    }
}
fn closed(j: &Json, names: &[&str]) -> Result<()> {
    let m = j.object()?;
    if m.len() != names.len() || names.iter().any(|n| !m.contains_key(*n)) {
        Err("service_index_fields".into())
    } else {
        Ok(())
    }
}
pub(crate) fn encode_run(run: &AgentDurableRun) -> Json {
    let task = run
        .identity
        .actual_task
        .as_ref()
        .map(|t| {
            object([
                ("task_id", string(&t.task_id)),
                ("attempt_id", string(&t.attempt_id)),
            ])
        })
        .unwrap_or(Json::Null);
    object([
        ("request_id", string(&run.intent.request_id)),
        ("variant", string(variant(&run.intent.variant))),
        (
            "source_build_identity",
            string(&run.intent.source_build_identity),
        ),
        ("run_id", string(&run.identity.run_id)),
        (
            "admitted_service_epoch",
            string(&run.identity.admitted_service_epoch),
        ),
        ("actual_task", task),
    ])
}
pub(crate) fn decode_run(j: &Json) -> Result<AgentDurableRun> {
    closed(
        j,
        &[
            "request_id",
            "variant",
            "source_build_identity",
            "run_id",
            "admitted_service_epoch",
            "actual_task",
        ],
    )?;
    let text = |k| -> Result<String> { Ok(field(j, k)?.string()?.into()) };
    let request = text("request_id")?;
    let source = text("source_build_identity")?;
    let run = text("run_id")?;
    let epoch = text("admitted_service_epoch")?;
    if !request_id(&request) || !hex_id(&source, 40) || !hex_id(&run, 32) || !hex_id(&epoch, 32) {
        return Err("service_index_identity".into());
    }
    let v = match text("variant")?.as_str() {
        "equipment" => AgentReadVariant::Equipment,
        "research" => AgentReadVariant::Research,
        "inquiry" => AgentReadVariant::Inquiry,
        "seeded_equipment" => AgentReadVariant::SeededEquipment,
        _ => return Err("service_index_variant".into()),
    };
    let task = field(j, "actual_task")?;
    let task = if *task == Json::Null {
        None
    } else {
        closed(task, &["task_id", "attempt_id"])?;
        let t = field(task, "task_id")?.string()?;
        let a = field(task, "attempt_id")?.string()?;
        if !muyon_core_agent_lab::identifier(t) || !muyon_core_agent_lab::identifier(a) {
            return Err("service_index_task".into());
        }
        Some(AgentTaskIdentity {
            task_id: t.into(),
            attempt_id: a.into(),
        })
    };
    Ok(AgentDurableRun {
        intent: AgentIntentBinding {
            request_id: request,
            variant: v,
            source_build_identity: source,
        },
        identity: AgentRunIdentity {
            run_id: run,
            admitted_service_epoch: epoch,
            actual_task: task,
        },
    })
}
// Enforce the narrower Service index limit on the actual read, independently
// of the existing Core reader's 1 MiB file bound. Keep the extra byte for growth.
fn read_index(path: &Path) -> Result<String> {
    let metadata = fs::symlink_metadata(path).map_err(|e| e.to_string())?;
    if !metadata.is_file() || metadata.file_type().is_symlink() {
        return Err("service_index_file".into());
    }
    if metadata.len() > INDEX_BYTES as u64 {
        return Err("service_index_bound".into());
    }
    let mut bytes = Vec::new();
    fs::File::open(path)
        .map_err(|e| e.to_string())?
        .take(INDEX_BYTES as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() > INDEX_BYTES {
        return Err("service_index_bound".into());
    }
    String::from_utf8(bytes).map_err(|_| "service_index_utf8".into())
}
impl ServiceRoot {
    pub fn open(private_root: &Path) -> Result<Self> {
        store::validate_dir(private_root)?;
        let dir = private_root.join(NAMESPACE);
        if !dir.exists() {
            match store::create_dir(&dir) {
                Ok(()) => {}
                Err(e) => {
                    if !dir.exists() {
                        return Err(e);
                    }
                }
            }
        }
        store::validate_dir(&dir)?;
        let lock = store::lock(&dir)?;
        let mut result = Self {
            dir,
            _lock: lock,
            runs: Vec::new(),
            poisoned: false,
        };
        if result.dir.join("index.db").exists() {
            let data = read_index(&result.dir.join("index.db"))?;
            if data.len() > INDEX_BYTES {
                return Err("service_index_bound".into());
            }
            let value = parse(data.as_bytes())?;
            closed(&value, &["version", "runs"])?;
            if field(&value, "version")? != &string("agent-service-index-1") {
                return Err("service_index_version".into());
            }
            for value in field(&value, "runs")?.array()? {
                let run = decode_run(value)?;
                if result.runs.len() >= 8
                    || result.runs.iter().any(|r| {
                        r.intent.request_id == run.intent.request_id
                            || r.identity.run_id == run.identity.run_id
                    })
                {
                    return Err("service_index_duplicate_or_bound".into());
                }
                result.runs.push(run);
            }
        } else {
            for item in fs::read_dir(&result.dir).map_err(|e| e.to_string())? {
                let item = item.map_err(|e| e.to_string())?;
                if item.file_name() != ".lock" {
                    return Err("service_root_inventory".into());
                }
            }
            result.write_index(Vec::new())?;
        }
        result.census()?;
        Ok(result)
    }
    fn census(&mut self) -> Result<u64> {
        let mut bytes = 0u64;
        let mut entries = 0usize;
        let uid = fs::symlink_metadata(&self.dir)
            .map_err(|e| e.to_string())?
            .uid();
        for item in fs::read_dir(&self.dir).map_err(|e| e.to_string())? {
            let item = item.map_err(|e| e.to_string())?;
            entries += 1;
            let name = item
                .file_name()
                .into_string()
                .map_err(|_| "service_root_inventory")?;
            let m = fs::symlink_metadata(item.path()).map_err(|e| e.to_string())?;
            if m.file_type().is_symlink() || m.uid() != uid {
                return Err("service_root_inventory".into());
            }
            if m.is_dir() {
                if m.permissions().mode() & 0o777 != 0o700
                    || !self.runs.iter().any(|r| r.identity.run_id == name)
                {
                    return Err("service_root_inventory".into());
                }
                for file in fs::read_dir(item.path()).map_err(|e| e.to_string())? {
                    let file = file.map_err(|e| e.to_string())?;
                    entries += 1;
                    if entries > 256 {
                        return Err("service_root_quota".into());
                    }
                    let n = file
                        .file_name()
                        .into_string()
                        .map_err(|_| "service_root_inventory")?;
                    let known = [
                        "source.db",
                        "ordinary-agent-v1.db",
                        "ordinary-send-v1.db",
                        "registered-result.db",
                        "search-outbound.db",
                        "lab-supplier.siq",
                        "native.db",
                        "task.db",
                        "outbound.db",
                        "summary.db",
                        ".lock",
                        "cancel.request",
                    ];
                    let temp = known.iter().any(|base| {
                        n.starts_with(&format!(".{base}."))
                            && n[base.len() + 2..]
                                .bytes()
                                .all(|b| b.is_ascii_digit() || b == b'.')
                    });
                    if !known.contains(&n.as_str()) && !temp {
                        return Err("service_root_inventory".into());
                    }
                    if temp {
                        // Recognized atomic candidates are evidence of interruption,
                        // never garbage to remove or permission to admit another run.
                        self.poisoned = true;
                    }
                    let f = fs::symlink_metadata(file.path()).map_err(|e| e.to_string())?;
                    if !f.is_file()
                        || f.file_type().is_symlink()
                        || f.uid() != uid
                        || f.permissions().mode() & 0o777 != 0o600
                    {
                        return Err("service_root_inventory".into());
                    }
                    bytes = bytes.checked_add(f.len()).ok_or("service_root_quota")?;
                }
            } else if m.is_file()
                && m.permissions().mode() & 0o777 == 0o600
                && (name == "index.db"
                    || name == ".lock"
                    || (name.starts_with(".index.db.")
                        && name[10..].bytes().all(|b| b.is_ascii_digit() || b == b'.')))
            {
                if name.starts_with(".index.db.") {
                    self.poisoned = true;
                }
                bytes = bytes.checked_add(m.len()).ok_or("service_root_quota")?
            } else {
                return Err("service_root_inventory".into());
            }
            if entries > 256 || bytes > ROOT_BYTES {
                return Err("service_root_quota".into());
            }
        }
        for run in &self.runs {
            store::validate_dir(&self.dir.join(&run.identity.run_id))?;
        }
        Ok(bytes)
    }
    fn write_index(&mut self, candidate: Vec<AgentDurableRun>) -> Result<()> {
        if self.poisoned {
            return Err("service_root_poisoned".into());
        }
        let encoded = object([
            ("version", string("agent-service-index-1")),
            (
                "runs",
                Json::Array(candidate.iter().map(encode_run).collect()),
            ),
        ])
        .encode();
        if encoded.len() > INDEX_BYTES {
            return Err("service_index_bound".into());
        }
        parse(encoded.as_bytes())?;
        // An error may follow rename/fsync; preserve uncertainty, never reuse this lease to execute.
        if let Err(e) = store::atomic(&self.dir, "index.db", &encoded) {
            self.poisoned = true;
            return Err(e);
        }
        self.runs = candidate;
        Ok(())
    }
    pub fn admit(&mut self, intent: AgentIntentBinding, epoch: &str) -> Result<AgentDurableRun> {
        if self.poisoned {
            return Err("service_root_poisoned".into());
        }
        if !request_id(&intent.request_id)
            || !hex_id(&intent.source_build_identity, 40)
            || !hex_id(epoch, 32)
        {
            return Err("service_index_identity".into());
        }
        if self
            .runs
            .iter()
            .any(|r| r.intent.request_id == intent.request_id)
        {
            return Err("service_request_exists".into());
        }
        if self.runs.len() >= 8
            || self
                .census()?
                .checked_add(PEAK_BYTES)
                .ok_or("service_root_quota")?
                > ROOT_BYTES
        {
            return Err("service_root_quota".into());
        }
        if self.poisoned {
            return Err("service_root_poisoned".into());
        }
        let run = AgentDurableRun {
            intent,
            identity: AgentRunIdentity {
                run_id: crate::nonce()?,
                admitted_service_epoch: epoch.into(),
                actual_task: None,
            },
        };
        store::create_dir(&self.dir.join(&run.identity.run_id))?;
        let mut candidate = self.runs.clone();
        candidate.push(run.clone());
        self.write_index(candidate)?;
        Ok(run)
    }
    pub fn attach_task(&mut self, run: &str, task: AgentTaskIdentity) -> Result<()> {
        if !muyon_core_agent_lab::identifier(&task.task_id)
            || !muyon_core_agent_lab::identifier(&task.attempt_id)
        {
            return Err("service_index_task".into());
        }
        let mut candidate = self.runs.clone();
        let row = candidate
            .iter_mut()
            .find(|r| r.identity.run_id == run)
            .ok_or("service_run_unknown")?;
        if let Some(existing) = &row.identity.actual_task {
            if existing == &task {
                return Ok(());
            }
            return Err("service_task_conflict".into());
        }
        row.identity.actual_task = Some(task);
        self.write_index(candidate)
    }
    pub fn run_dir(&self, run: &str) -> Result<PathBuf> {
        if self.runs.iter().any(|r| r.identity.run_id == run) {
            Ok(self.dir.join(run))
        } else {
            Err("service_run_unknown".into())
        }
    }
    pub(crate) fn is_poisoned(&self) -> bool {
        self.poisoned
    }
    pub(crate) fn poison(&mut self) {
        self.poisoned = true;
    }
    pub fn runs(&self) -> &[AgentDurableRun] {
        &self.runs
    }
    // Terminal validation is deliberately not inferred from index presence.
    pub fn recovery_required(&self) -> bool {
        self.poisoned || !self.runs.is_empty()
    }
}
