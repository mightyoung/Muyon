//! Durable, bounded host activity. These events are not model reasoning.
use super::{
    owner::{AgentPlan, Observation},
    read_business, ReadScope,
};
use crate::{business::BusinessStore, contract::decode_json, sqlite::Db};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs::{File, OpenOptions},
    io::Read,
    os::fd::AsRawFd,
    path::Path,
};

pub type Result<T> = std::result::Result<T, &'static str>;
unsafe extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
}
fn sql<T>(r: crate::sqlite::Result<T>) -> Result<T> {
    r.map_err(|_| "workflow_storage_unavailable")
}
fn ident(s: &str) -> Result<()> {
    if s.is_empty()
        || s.len() > 128
        || !s
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
    {
        Err("workflow_identity_invalid")
    } else {
        Ok(())
    }
}
fn opaque() -> Result<String> {
    let mut bytes = [0u8; 16];
    File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut bytes))
        .map_err(|_| "workflow_identity_unavailable")?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}
fn sha(s: &str) -> String {
    Sha256::digest(s.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
fn text(s: &str, max: usize) -> Result<()> {
    if s.trim().is_empty() || s.len() > max || s.contains('\0') {
        Err("workflow_text_invalid")
    } else {
        Ok(())
    }
}
fn encoded<T: Serialize>(v: &T) -> Result<String> {
    serde_json::to_string(v).map_err(|_| "workflow_storage_invalid")
}
fn cell(row: &[Option<String>], n: usize) -> Result<&str> {
    row.get(n)
        .and_then(Option::as_deref)
        .ok_or("workflow_storage_invalid")
}

/// Authority is constructed by the host from the current store, never decoded.
pub struct RunScope {
    workspace: String,
    epoch: String,
    session: String,
    conversation: String,
    project: Option<String>,
}
impl RunScope {
    pub fn current(
        store: &BusinessStore,
        session: &str,
        conversation: &str,
        project: Option<&str>,
    ) -> Result<Self> {
        ident(session)?;
        ident(conversation)?;
        ReadScope::current(store, project).map_err(|_| "workflow_scope_mismatch")?;
        Ok(Self {
            workspace: store.workspace_id().into(),
            epoch: store.owner_epoch().into(),
            session: session.into(),
            conversation: conversation.into(),
            project: project.map(str::to_owned),
        })
    }
    fn key(&self) -> String {
        json!([self.workspace, self.conversation, self.project]).to_string()
    }
}
struct Skill {
    id: &'static str,
    title: &'static str,
    description: &'static str,
    tool: &'static str,
    body: &'static str,
}
const SKILLS: &[Skill] = &[
    Skill {
        id: "supplier-overview",
        title: "供应商概览",
        description: "读取当前工作区供应商列表",
        tool: "supplier_list",
        body: include_str!("skills/supplier-overview/SKILL.md"),
    },
    Skill {
        id: "paper-overview",
        title: "论文概览",
        description: "读取当前科研项目论文列表",
        tool: "paper_list",
        body: include_str!("skills/paper-overview/SKILL.md"),
    },
];
fn skill(id: &str) -> Result<&'static Skill> {
    SKILLS
        .iter()
        .find(|s| s.id == id)
        .ok_or("workflow_skill_not_found")
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Arguments {
    limit: u32,
    offset: u32,
}
#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
enum Action {
    CreateRoot {
        title: String,
        task: String,
    },
    CreateChild {
        root_id: String,
        skill_id: String,
        task: String,
        executor: String,
        arguments: Arguments,
    },
    ExecuteLocal {
        run_id: String,
    },
    Snapshot {
        root_id: String,
        #[serde(default)]
        after_seq: u64,
    },
    List {
        limit: u32,
    },
    Cancel {
        run_id: String,
    },
    Skills,
    LoadSkill {
        skill_id: String,
    },
    SetSkill {
        skill_id: String,
        enabled: bool,
    },
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Run {
    id: String,
    root_id: String,
    parent_id: Option<String>,
    conversation_id: String,
    project_id: Option<String>,
    kind: String,
    skill_id: Option<String>,
    skill_digest: Option<String>,
    title: String,
    task: String,
    depth: u32,
    status: String,
    cancel_requested: bool,
    remote_request_id: Option<String>,
    #[serde(default)]
    current_request_id: Option<String>,
    #[serde(default)]
    remote_request_ids: Vec<String>,
    blocked_reason: Option<String>,
    result: Option<Value>,
    error: Option<String>,
    created_seq: u64,
    updated_seq: u64,
    session: String,
    epoch: String,
    arguments: Value,
}
impl Run {
    fn view(&self, scope: &RunScope) -> Value {
        let mut v = serde_json::to_value(self).expect("serializable run");
        for k in ["session", "epoch", "arguments"] {
            v.as_object_mut().unwrap().remove(k);
        }
        v["can_control"] = json!(self.session == scope.session && self.epoch == scope.epoch);
        if let Some(result) = &self.result {
            if serde_json::to_vec(result)
                .expect("serializable result")
                .len()
                > 16_384
            {
                v["result"] = json!({
                    "source":result.get("source").and_then(Value::as_str).unwrap_or(if self.kind=="remote_chat" {"remote_observation"} else {"local_tool_result"}),
                    "preview_truncated":true,
                    "record_count":result.get("records").and_then(Value::as_array).map(Vec::len),
                    "summary":if self.kind=="remote_chat" {"远程请求已完成；结果超过界面预览上限，请查看原请求结果"} else {"工具已执行；结果超过界面预览上限，请在业务页查看完整记录"}
                });
            }
        }
        v
    }
}
pub struct RunLedger {
    db: Db,
    workspace: String,
    epoch: String,
    _lock: File,
}
impl RunLedger {
    pub fn open(path: &Path, workspace: &str, epoch: &str) -> Result<Self> {
        ident(workspace)?;
        ident(epoch)?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(format!("{}.owner.lock", path.display()))
            .map_err(|_| "workflow_owner_unavailable")?;
        if unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 {
            return Err("workflow_owner_busy");
        }
        let fresh = !path.exists();
        let db = sql(Db::open(
            path.to_str().ok_or("workflow_path_invalid")?,
            false,
            true,
        ))?;
        sql(db.query("PRAGMA journal_mode=WAL", &[]))?;
        sql(db.exec("PRAGMA synchronous=FULL", &[]))?;
        if fresh {
            let tx = sql(db.transaction())?;
            sql(db.exec(
                "CREATE TABLE meta(workspace TEXT NOT NULL,version TEXT NOT NULL)",
                &[],
            ))?;
            sql(db.exec("INSERT INTO meta VALUES(?,'1')", &[workspace]))?;
            sql(db.exec("CREATE TABLE runs(id TEXT PRIMARY KEY,scope TEXT NOT NULL,root TEXT NOT NULL,record TEXT NOT NULL)",&[]))?;
            sql(db.exec("CREATE TABLE events(seq INTEGER PRIMARY KEY AUTOINCREMENT,scope TEXT NOT NULL,root TEXT NOT NULL,event TEXT NOT NULL)",&[]))?;
            sql(db.exec("CREATE TABLE skills(scope TEXT NOT NULL,id TEXT NOT NULL,enabled INTEGER NOT NULL CHECK(enabled IN(0,1)),PRIMARY KEY(scope,id))",&[]))?;
            sql(tx.commit())?;
        }
        let meta = sql(db.query("SELECT workspace,version FROM meta", &[]))?;
        if meta.len() != 1 || cell(&meta[0], 0)? != workspace || cell(&meta[0], 1)? != "1" {
            return Err("workflow_database_invalid");
        }
        let ledger = Self {
            db,
            workspace: workspace.into(),
            epoch: epoch.into(),
            _lock: lock,
        };
        let tx = sql(ledger.db.transaction())?;
        for row in sql(ledger.db.query("SELECT scope,record FROM runs", &[]))? {
            let key = cell(&row, 0)?;
            let mut run: Run =
                serde_json::from_str(cell(&row, 1)?).map_err(|_| "workflow_storage_invalid")?;
            if matches!(
                run.status.as_str(),
                "running" | "waiting_confirmation" | "queued"
            ) {
                run.status = "unknown".into();
                run.blocked_reason = Some("query_original_no_replay".into());
                // Recovery must remain possible even if the event window is full.
                ledger.event(
                    key,
                    &mut run,
                    "unknown",
                    "运行中断，请查询原请求",
                    "host_activity",
                )?;
                ledger.save(key, &run)?;
            }
        }
        sql(tx.commit())?;
        Ok(ledger)
    }
    fn scope(&self, scope: &RunScope) -> Result<()> {
        if self.workspace != scope.workspace || self.epoch != scope.epoch {
            Err("workflow_scope_mismatch")
        } else {
            Ok(())
        }
    }
    fn get(&self, scope: &RunScope, id: &str, mutate: bool) -> Result<Run> {
        self.scope(scope)?;
        ident(id)?;
        let rows = sql(self.db.query(
            "SELECT record FROM runs WHERE id=? AND scope=?",
            &[id, &scope.key()],
        ))?;
        let row = rows.first().ok_or("workflow_run_not_found")?;
        let run: Run =
            serde_json::from_str(cell(row, 0)?).map_err(|_| "workflow_storage_invalid")?;
        if mutate && (run.session != scope.session || run.epoch != scope.epoch) {
            return Err("workflow_previous_session_read_only");
        }
        Ok(run)
    }
    fn save(&self, key: &str, run: &Run) -> Result<()> {
        sql(self.db.exec(
            "INSERT INTO runs VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET record=excluded.record",
            &[&run.id, key, &run.root_id, &encoded(run)?],
        ))?;
        Ok(())
    }
    fn event(&self, key: &str, run: &mut Run, kind: &str, label: &str, origin: &str) -> Result<()> {
        let event = json!({"run_id":run.id,"kind":kind,"label":label,"summary":label,"status":run.status,"origin":origin,"remote_request_id":run.current_request_id.as_ref().or(run.remote_request_id.as_ref()),"original_request_id":run.remote_request_id});
        sql(self.db.exec(
            "INSERT INTO events(scope,root,event) VALUES(?,?,?)",
            &[key, &run.root_id, &event.to_string()],
        ))?;
        let rows = sql(self.db.query("SELECT last_insert_rowid()", &[]))?;
        run.updated_seq = cell(&rows[0], 0)?
            .parse()
            .map_err(|_| "workflow_storage_invalid")?;
        if run.created_seq == 0 {
            run.created_seq = run.updated_seq;
        }
        sql(self.db.exec("DELETE FROM events WHERE scope=? AND root=? AND seq NOT IN (SELECT seq FROM events WHERE scope=? AND root=? ORDER BY seq DESC LIMIT 256)",&[key,&run.root_id,key,&run.root_id]))?;
        Ok(())
    }
    fn enabled(&self, scope: &RunScope, id: &str) -> Result<bool> {
        let rows = sql(self.db.query(
            "SELECT enabled FROM skills WHERE scope=? AND id=?",
            &[&scope.key(), id],
        ))?;
        Ok(rows
            .first()
            .map(|r| cell(r, 0).map(|s| s == "1"))
            .transpose()?
            .unwrap_or(true))
    }
    fn children(&self, scope: &RunScope, root: &str) -> Result<Vec<Run>> {
        sql(self.db.query(
            "SELECT record FROM runs WHERE scope=? AND root=? ORDER BY rowid",
            &[&scope.key(), root],
        ))?
        .iter()
        .map(|r| serde_json::from_str(cell(r, 0)?).map_err(|_| "workflow_storage_invalid"))
        .collect()
    }
    fn aggregate(&self, scope: &RunScope, root_id: &str) -> Result<()> {
        let mut root = self.get(scope, root_id, false)?;
        let all = self.children(scope, root_id)?;
        let children: Vec<_> = all.iter().filter(|r| r.parent_id.is_some()).collect();
        if children.is_empty() {
            return Ok(());
        }
        let status = if children.iter().any(|r| r.status == "unknown") {
            "unknown"
        } else if children.iter().any(|r| r.status == "running") {
            "running"
        } else if children.iter().any(|r| r.status == "waiting_confirmation") {
            "waiting_confirmation"
        } else if children.iter().any(|r| r.status == "queued") {
            "queued"
        } else if children.iter().any(|r| r.status == "blocked") {
            "blocked"
        } else if root.cancel_requested || children.iter().any(|r| r.status == "cancelled") {
            "cancelled"
        } else if children.iter().any(|r| r.status == "failed") {
            "failed"
        } else {
            "completed"
        };
        root.status = status.into();
        root.updated_seq = all
            .iter()
            .map(|r| r.updated_seq)
            .max()
            .unwrap_or(root.updated_seq);
        self.save(&scope.key(), &root)
    }
    fn snapshot(&self, scope: &RunScope, root_id: &str, after: u64) -> Result<Value> {
        let root = self.get(scope, root_id, false)?;
        if root.parent_id.is_some() {
            return Err("workflow_root_required");
        }
        let runs = self.children(scope, root_id)?;
        let mut events = Vec::new();
        let mut next = after;
        for row in sql(self.db.query(
            "SELECT seq,event FROM events WHERE scope=? AND root=? AND seq>? ORDER BY seq",
            &[&scope.key(), root_id, &after.to_string()],
        ))? {
            let seq: u64 = cell(&row, 0)?
                .parse()
                .map_err(|_| "workflow_storage_invalid")?;
            let mut v: Value =
                serde_json::from_str(cell(&row, 1)?).map_err(|_| "workflow_storage_invalid")?;
            v["seq"] = json!(seq);
            next = seq;
            events.push(v);
        }
        let reply = json!({"root":root.view(scope),"runs":runs.iter().map(|r|r.view(scope)).collect::<Vec<_>>(),"events":events,"next_seq":next});
        if encoded(&reply)?.len() > 524_288 {
            return Err("workflow_preview_limit");
        }
        Ok(reply)
    }
    pub fn execute(
        &mut self,
        action_json: &str,
        store: &BusinessStore,
        scope: &RunScope,
    ) -> Result<Value> {
        self.scope(scope)?;
        if store.workspace_id() != scope.workspace || store.owner_epoch() != scope.epoch {
            return Err("workflow_scope_mismatch");
        }
        ReadScope::current(store, scope.project.as_deref())
            .map_err(|_| "workflow_scope_mismatch")?;
        if action_json.len() > 16384 {
            return Err("workflow_input_limit");
        }
        let action: Action = serde_json::from_value(
            decode_json(action_json).map_err(|_| "workflow_action_invalid")?,
        )
        .map_err(|_| "workflow_action_invalid")?;
        let key = scope.key();
        match action {
            Action::Skills => Ok(
                json!({"skills":SKILLS.iter().map(|s|Ok(json!({"id":s.id,"title":s.title,"description":s.description,"tool":s.tool,"digest":sha(s.body),"enabled":self.enabled(scope,s.id)?}))).collect::<Result<Vec<_>>>()?}),
            ),
            Action::LoadSkill { skill_id } => {
                let s = skill(&skill_id)?;
                Ok(
                    json!({"id":s.id,"body":s.body,"digest":sha(s.body),"enabled":self.enabled(scope,s.id)?}),
                )
            }
            Action::SetSkill { skill_id, enabled } => {
                skill(&skill_id)?;
                sql(self.db.exec("INSERT INTO skills VALUES(?,?,?) ON CONFLICT(scope,id) DO UPDATE SET enabled=excluded.enabled",&[&key,&skill_id,if enabled {"1"} else {"0"}]))?;
                Ok(json!({"id":skill_id,"enabled":enabled}))
            }
            Action::Snapshot { root_id, after_seq } => self.snapshot(scope, &root_id, after_seq),
            Action::List { limit } => {
                if !(1..=50).contains(&limit) {
                    return Err("workflow_limit");
                }
                let mut roots = Vec::new();
                for row in sql(self.db.query(
                    "SELECT record FROM runs WHERE scope=? AND id=root ORDER BY rowid DESC LIMIT ?",
                    &[&key, &limit.to_string()],
                ))? {
                    let run: Run = serde_json::from_str(cell(&row, 0)?)
                        .map_err(|_| "workflow_storage_invalid")?;
                    roots.push(run.view(scope));
                }
                let reply = json!({"roots":roots});
                if encoded(&reply)?.len() > 524_288 {
                    return Err("workflow_preview_limit");
                }
                Ok(reply)
            }
            Action::CreateRoot { title, task } => {
                text(&title, 160)?;
                text(&task, 4096)?;
                let id = opaque()?;
                let mut run = Run {
                    id: id.clone(),
                    root_id: id,
                    parent_id: None,
                    conversation_id: scope.conversation.clone(),
                    project_id: scope.project.clone(),
                    kind: "workflow".into(),
                    skill_id: None,
                    skill_digest: None,
                    title,
                    task,
                    depth: 0,
                    status: "queued".into(),
                    cancel_requested: false,
                    remote_request_id: None,
                    current_request_id: None,
                    remote_request_ids: Vec::new(),
                    blocked_reason: None,
                    result: None,
                    error: None,
                    created_seq: 0,
                    updated_seq: 0,
                    session: scope.session.clone(),
                    epoch: scope.epoch.clone(),
                    arguments: json!({}),
                };
                let tx = sql(self.db.transaction())?;
                self.event(&key, &mut run, "run_created", "已创建任务", "host_activity")?;
                self.save(&key, &run)?;
                sql(tx.commit())?;
                Ok(run.view(scope))
            }
            Action::CreateChild {
                root_id,
                skill_id,
                task,
                executor,
                arguments,
            } => {
                let root = self.get(scope, &root_id, true)?;
                if root.depth != 0 || root.cancel_requested {
                    return Err("workflow_parent_invalid");
                }
                text(&task, 4096)?;
                let s = skill(&skill_id)?;
                if !self.enabled(scope, s.id)? {
                    return Err("workflow_skill_disabled");
                }
                if !matches!(executor.as_str(), "local_read" | "remote_chat")
                    || !(1..=50).contains(&arguments.limit)
                    || arguments.offset > 10000
                {
                    return Err("workflow_arguments_invalid");
                }
                let children = self.children(scope, &root_id)?;
                if children.len() > 8
                    || children
                        .iter()
                        .filter(|r| {
                            r.parent_id.is_some()
                                && matches!(
                                    r.status.as_str(),
                                    "queued" | "running" | "waiting_confirmation" | "unknown"
                                )
                        })
                        .count()
                        >= 2
                {
                    return Err("workflow_child_limit");
                }
                let mut run = Run {
                    id: opaque()?,
                    root_id: root_id.clone(),
                    parent_id: Some(root_id.clone()),
                    conversation_id: if executor == "remote_chat" {
                        format!("child-{}", opaque()?)
                    } else {
                        scope.conversation.clone()
                    },
                    project_id: scope.project.clone(),
                    kind: executor,
                    skill_id: Some(skill_id),
                    skill_digest: Some(sha(s.body)),
                    title: s.title.into(),
                    task,
                    depth: 1,
                    status: "queued".into(),
                    cancel_requested: false,
                    remote_request_id: None,
                    current_request_id: None,
                    remote_request_ids: Vec::new(),
                    blocked_reason: None,
                    result: None,
                    error: None,
                    created_seq: 0,
                    updated_seq: 0,
                    session: scope.session.clone(),
                    epoch: scope.epoch.clone(),
                    arguments: json!({"limit":arguments.limit,"offset":arguments.offset}),
                };
                let tx = sql(self.db.transaction())?;
                self.event(
                    &key,
                    &mut run,
                    "child_spawned",
                    "已派生子任务",
                    "host_activity",
                )?;
                self.event(
                    &key,
                    &mut run,
                    "skill_loaded",
                    "已加载选定技能",
                    "host_activity",
                )?;
                self.save(&key, &run)?;
                self.aggregate(scope, &root_id)?;
                sql(tx.commit())?;
                Ok(run.view(scope))
            }
            Action::ExecuteLocal { run_id } => {
                let mut run = self.get(scope, &run_id, true)?;
                if run.kind != "local_read" || run.status != "queued" || run.cancel_requested {
                    return Err("workflow_execution_denied");
                }
                let s = skill(run.skill_id.as_deref().ok_or("workflow_skill_not_found")?)?;
                if !self.enabled(scope, s.id)? {
                    return Err("workflow_skill_disabled");
                }
                let tx = sql(self.db.transaction())?;
                run.status = "running".into();
                self.event(
                    &key,
                    &mut run,
                    "tool_started",
                    "正在读取本地记录",
                    "host_activity",
                )?;
                let rs = ReadScope::current(store, scope.project.as_deref())
                    .map_err(|_| "workflow_scope_mismatch")?;
                let request = json!({"tool":s.tool,"limit":run.arguments["limit"],"offset":run.arguments["offset"]});
                match read_business(store, &rs, &request.to_string()) {
                    Ok(value) => {
                        if encoded(&value)?.len() > 262144 {
                            return Err("workflow_result_limit");
                        }
                        run.result = Some(value);
                        run.status = "completed".into();
                        self.event(
                            &key,
                            &mut run,
                            "tool_completed",
                            "本地读取完成",
                            "tool_result",
                        )?;
                        self.event(&key, &mut run, "completed", "子任务完成", "host_activity")?;
                    }
                    Err(_) => {
                        run.status = "failed".into();
                        run.error = Some("local_read_failed".into());
                        self.event(&key, &mut run, "failed", "本地读取失败", "host_activity")?;
                    }
                }
                self.save(&key, &run)?;
                self.aggregate(scope, &run.root_id)?;
                sql(tx.commit())?;
                Ok(run.view(scope))
            }
            Action::Cancel { run_id } => {
                let run = self.get(scope, &run_id, true)?;
                let mut selected = if run.parent_id.is_none() {
                    self.children(scope, &run.root_id)?
                } else {
                    vec![run.clone()]
                };
                let tx = sql(self.db.transaction())?;
                let mut requests = Vec::new();
                for r in &mut selected {
                    if matches!(r.status.as_str(), "completed" | "failed" | "cancelled") {
                        continue;
                    }
                    r.cancel_requested = true;
                    if let Some(request) = &r.remote_request_id {
                        if r.remote_request_ids.is_empty() {
                            requests.push(request.clone());
                        } else {
                            requests.extend(r.remote_request_ids.iter().cloned());
                        }
                    } else {
                        r.status = "cancelled".into();
                    }
                    self.event(&key, r, "cancel_requested", "已请求取消", "host_activity")?;
                    self.save(&key, r)?;
                }
                self.aggregate(scope, &run.root_id)?;
                sql(tx.commit())?;
                Ok(
                    json!({"run_id":run_id,"remote_request_ids":requests,"snapshot":self.snapshot(scope,&run.root_id,0)?}),
                )
            }
        }
    }
    /// Host-only composition. This contains no implicit private business records.
    pub fn remote_context(&self, scope: &RunScope, run_id: &str) -> Result<Value> {
        let run = self.get(scope, run_id, true)?;
        if run.kind != "remote_chat" || run.status != "queued" || run.cancel_requested {
            return Err("workflow_execution_denied");
        }
        let s = skill(run.skill_id.as_deref().ok_or("workflow_skill_not_found")?)?;
        if !self.enabled(scope, s.id)? {
            return Err("workflow_skill_disabled");
        }
        let related = self.children(scope, &run.root_id)?;
        Ok(
            json!({"root_id":run.root_id,"root_conversation":scope.conversation,"conversation_id":run.conversation_id,"task":run.task,"skill_body":s.body,"skill_digest":sha(s.body),"tool_names":[s.tool],"project_id":run.project_id,"remote_request_ids":related.iter().filter_map(|r|r.remote_request_id.as_ref()).collect::<Vec<_>>()}),
        )
    }
    pub fn bind_remote_plan(
        &mut self,
        scope: &RunScope,
        run_id: &str,
        plan: &AgentPlan,
    ) -> Result<Value> {
        self.remote_context(scope, run_id)?;
        let mut run = self.get(scope, run_id, true)?;
        if run.remote_request_id.is_some()
            || plan.conversation_id != run.conversation_id
            || plan.purpose != "chat"
        {
            return Err("workflow_remote_binding_invalid");
        }
        ident(&plan.request_id)?;
        for row in sql(self.db.query("SELECT record FROM runs", &[]))? {
            let other: Run =
                serde_json::from_str(cell(&row, 0)?).map_err(|_| "workflow_storage_invalid")?;
            if other.remote_request_id.as_deref() == Some(&plan.request_id) {
                return Err("workflow_remote_binding_invalid");
            }
        }
        run.remote_request_id = Some(plan.request_id.clone());
        run.current_request_id = Some(plan.request_id.clone());
        run.remote_request_ids = vec![plan.request_id.clone()];
        run.blocked_reason = plan.blocked_reason.clone();
        run.status = if plan.send_allowed {
            "waiting_confirmation"
        } else {
            "blocked"
        }
        .into();
        let tx = sql(self.db.transaction())?;
        self.event(
            &scope.key(),
            &mut run,
            if plan.send_allowed {
                "waiting_review"
            } else {
                "blocked"
            },
            if plan.send_allowed {
                "等待发送确认"
            } else {
                "远程请求受阻"
            },
            "remote_observation",
        )?;
        self.save(&scope.key(), &run)?;
        self.aggregate(scope, &run.root_id)?;
        sql(tx.commit())?;
        Ok(run.view(scope))
    }
    pub fn observe_remote(
        &mut self,
        scope: &RunScope,
        run_id: &str,
        observation: &Observation,
    ) -> Result<Value> {
        self.observe_remote_chain(scope, run_id, std::slice::from_ref(observation))
    }
    /// Only the trusted host supplies observations traversed through Owner's
    /// persisted followup edges. Public actions cannot submit this chain.
    pub fn observe_remote_chain(
        &mut self,
        scope: &RunScope,
        run_id: &str,
        observations: &[Observation],
    ) -> Result<Value> {
        let mut run = self.get(scope, run_id, true)?;
        if observations.is_empty() || observations.len() > 32 {
            return Err("workflow_remote_chain_invalid");
        }
        let first = &observations[0];
        if run.kind != "remote_chat" || run.remote_request_id.as_deref() != Some(&first.request_id)
        {
            return Err("workflow_remote_binding_invalid");
        }
        let ids: Vec<String> = observations.iter().map(|o| o.request_id.clone()).collect();
        let mut seen = std::collections::BTreeSet::new();
        for (index, observation) in observations.iter().enumerate() {
            ident(&observation.request_id)?;
            if !seen.insert(&observation.request_id)
                || (index + 1 < observations.len() && observation.status != "tool_consumed")
            {
                return Err("workflow_remote_chain_invalid");
            }
        }
        if !ids.starts_with(&run.remote_request_ids) {
            return Err("workflow_remote_chain_invalid");
        }
        if matches!(run.status.as_str(), "completed" | "failed" | "cancelled") {
            return Ok(run.view(scope));
        }
        let observation = observations.last().ok_or("workflow_remote_chain_invalid")?;
        let previous_status = run.status.clone();
        let previous_result = run.result.clone();
        let previous_cancel = run.cancel_requested;
        let previous_ids = run.remote_request_ids.clone();
        let previous_reason = run.blocked_reason.clone();
        let (status, kind, label) = if run.cancel_requested && observation.status != "cancelled" {
            ("unknown", "unknown", "已请求取消，请查询原请求状态")
        } else if observation.cancelled && observation.status == "cancelled" {
            ("cancelled", "cancel_requested", "原请求已取消")
        } else if observation.blocked_reason.is_some() {
            ("blocked", "blocked", "远程请求受阻")
        } else {
            match observation.status.as_str() {
                "completed" if observation.answer.is_some() && observation.attempted => {
                    ("completed", "completed", "远程任务完成")
                }
                "tool_pending" => ("waiting_confirmation", "waiting_review", "等待工具调用审核"),
                "blocked" => ("blocked", "blocked", "远程请求受阻"),
                "prepared" | "reserved" => {
                    ("waiting_confirmation", "waiting_review", "等待发送确认")
                }
                "cancelled" => ("cancelled", "cancel_requested", "原请求已取消"),
                _ => ("unknown", "unknown", "请查询原请求状态"),
            }
        };
        run.status = status.into();
        run.current_request_id = Some(observation.request_id.clone());
        run.remote_request_ids = ids;
        run.cancel_requested |= observation.cancelled;
        run.blocked_reason = if status == "blocked" {
            observation
                .blocked_reason
                .clone()
                .or(previous_reason.clone())
        } else {
            None
        };
        if status == "completed" {
            let answer = observation.answer.clone().unwrap();
            if encoded(&answer)?.len() > 262144 {
                return Err("workflow_result_limit");
            }
            run.result = Some(answer);
        }
        if run.status == previous_status
            && run.result == previous_result
            && run.cancel_requested == previous_cancel
            && run.remote_request_ids == previous_ids
            && run.blocked_reason == previous_reason
        {
            return Ok(run.view(scope));
        }
        let tx = sql(self.db.transaction())?;
        self.event(&scope.key(), &mut run, kind, label, "remote_observation")?;
        self.save(&scope.key(), &run)?;
        self.aggregate(scope, &run.root_id)?;
        sql(tx.commit())?;
        Ok(run.view(scope))
    }
    /// Original request identities across every root in this visible scope.
    /// This also supports read-only reconnections without granting execution.
    pub fn remote_requests(&self, scope: &RunScope) -> Result<Vec<String>> {
        self.scope(scope)?;
        let mut ids = Vec::new();
        for row in sql(self.db.query(
            "SELECT record FROM runs WHERE scope=? ORDER BY rowid",
            &[&scope.key()],
        ))? {
            let run: Run =
                serde_json::from_str(cell(&row, 0)?).map_err(|_| "workflow_storage_invalid")?;
            if let Some(id) = run.remote_request_id {
                ids.push(id);
            }
        }
        Ok(ids)
    }
}
impl Drop for RunLedger {
    fn drop(&mut self) {
        unsafe {
            flock(self._lock.as_raw_fd(), 8);
        }
    }
}
