//! Versioned local UI/FFI bridge. Read schemas cannot nominate native scope,
//! authorization, SQL or workflow actions. Configuration preparation creates no
//! grant. All persistence uses the existing reviewed local mutation tail.
use crate::{
    agent::{
        owner::AgentOwner,
        workflow::{RunLedger, RunScope},
    },
    business::BusinessStore,
    contract::{decode_json, AuthorityBinding, ContractError, Revision},
    group_runtime_store::{
        validate_configuration, Capabilities, GroupActor, GroupCommand, GroupOperation, GroupScope,
        LocalReceipt, LocalStatus,
    },
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
type Result<T> = std::result::Result<T, ContractError>;
/// Only authenticated host context supplies actor/project; these are not wire
/// authorization or a fabricated account. The original grant owner still decides.
pub struct GroupUiScope {
    workspace: String,
    project: String,
    owner_epoch: String,
    actor: String,
}
impl GroupUiScope {
    pub fn current(store: &BusinessStore, project: &str, actor: &str) -> Result<Self> {
        id(project)?;
        id(actor)?;
        if store.project(project)?.deleted {
            return Err(ContractError::NotFound);
        }
        Ok(Self {
            workspace: store.workspace_id().into(),
            project: project.into(),
            owner_epoch: store.owner_epoch().into(),
            actor: actor.into(),
        })
    }
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ReadEnvelope {
    schema_version: u32,
    request: ReadRequest,
}
#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum ReadRequest {
    Catalog,
    Groups {
        limit: u32,
        after_group_id: Option<String>,
    },
    Group {
        group_id: String,
    },
    Runs {
        group_id: String,
        limit: u32,
        after_run_id: Option<String>,
    },
    Run {
        group_id: String,
        run_id: String,
    },
    LocalIntent {
        group_id: String,
        intent_id: String,
    },
    Workflow {
        group_id: String,
        run_id: String,
    },
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ChangeEnvelope {
    schema_version: u32,
    change: ConfigurationChange,
}
#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum ConfigurationChange {
    Register {
        intent_id: String,
        group_id: String,
        expected_revision: Revision,
        mode: Option<String>,
        fixed_leader: Option<String>,
        members: BTreeMap<String, Capabilities>,
    },
    Configure {
        intent_id: String,
        group_id: String,
        expected_revision: Revision,
        mode: String,
        fixed_leader: Option<String>,
        members: BTreeMap<String, Capabilities>,
    },
}
fn id(s: &str) -> Result<()> {
    if s.is_empty()
        || s.len() > 128
        || !s
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
    {
        Err(ContractError::InvalidIdentity)
    } else {
        Ok(())
    }
}
fn io<T>(v: crate::sqlite::Result<T>) -> Result<T> {
    v.map_err(|_| ContractError::Storage)
}
fn cell(r: &[Option<String>], n: usize) -> Result<&str> {
    r.get(n)
        .and_then(Option::as_deref)
        .ok_or(ContractError::StorageCorrupt)
}
fn page(limit: u32, after: &Option<String>) -> Result<()> {
    if !(1..=50).contains(&limit) {
        return Err(ContractError::RawLimit);
    }
    if let Some(after) = after {
        id(after)?;
    }
    Ok(())
}
fn parsed<T: serde::de::DeserializeOwned>(raw: &str, limit: usize) -> Result<T> {
    if raw.len() > limit {
        return Err(ContractError::RawLimit);
    }
    serde_json::from_value(decode_json(raw)?).map_err(|_| ContractError::InvalidPayload)
}
fn original_json(owner: &AgentOwner, first: &str, conversation: &str) -> Result<Value> {
    if owner
        .request_conversation(first)
        .map_err(|_| ContractError::Unknown)?
        != conversation
    {
        return Err(ContractError::ScopeMismatch);
    }
    let chain = owner
        .request_chain(first)
        .map_err(|_| ContractError::Unknown)?;
    let tail = chain.last().ok_or(ContractError::Unknown)?;
    let resolved = matches!(tail.status.as_str(), "completed" | "cancelled" | "failed");
    let settled = resolved || matches!(tail.status.as_str(), "tool_pending" | "tool_consumed");
    Ok(
        json!({"lookup_status":"available","original_request_id":first,"current_request_id":tail.request_id,"status":tail.status,"cancel_requested":tail.cancelled,"attempted":tail.attempted,"recovery_action":tail.recovery_action,"chain":chain.iter().map(|o|json!({"request_id":o.request_id,"status":o.status,"reserved_micro_cny_original":o.reserved_micro_cny,"actual_micro_cny":if matches!(o.status.as_str(),"completed"|"cancelled"|"failed"|"tool_pending"|"tool_consumed"){Some(o.charged_micro_cny.clone())}else{None},"attempted":o.attempted})).collect::<Vec<_>>(),"actual_usage_known":settled,"original_chain_resolved":resolved,"actual_cost_scope":"current_request","actual_micro_cny":if settled{Some(tail.charged_micro_cny.clone())}else{None}}),
    )
}
fn unavailable_original(first: &str) -> Value {
    json!({"lookup_status":"unavailable","original_request_id":first,"status":"unknown","actual_usage_known":false,"original_chain_resolved":false,"actual_micro_cny":null,"recovery_action":"query_original"})
}
impl BusinessStore {
    fn check_group_ui_scope(&self, s: &GroupUiScope) -> Result<()> {
        if s.workspace != self.workspace_id()
            || s.owner_epoch != self.owner_epoch()
            || self.project(&s.project)?.deleted
        {
            return Err(ContractError::ScopeMismatch);
        }
        Ok(())
    }
    fn group_ui_configuration(&self, s: &GroupUiScope, group_id: &str) -> Result<Value> {
        let scope = GroupScope::current(self, &s.project, group_id)?;
        let g = self.group_registration(&scope)?;
        let role = if s.actor == g.owner {
            "owner"
        } else if g.admins.contains(&s.actor) {
            "admin"
        } else {
            "none"
        };
        Ok(
            json!({"group_id":group_id,"revision":g.revision,"owner_user_id":g.owner,"admin_user_ids":g.admins,"management_role":role,"default_mode":g.mode,"fixed_coordinator_id":g.fixed_leader,"members":g.members,"configuration_scope":"future_runs_only","execution_authority":false}),
        )
    }
    /// Strict stable read protocol. The optional ledger/session are native objects
    /// supplied by the actual host, never model JSON or file paths in the request.
    pub fn group_ui_read(
        &self,
        s: &GroupUiScope,
        raw: &str,
        owner: Option<&AgentOwner>,
        workflow: Option<(&mut RunLedger, &str)>,
    ) -> Result<Value> {
        self.check_group_ui_scope(s)?;
        let e: ReadEnvelope = parsed(raw, 8192)?;
        if e.schema_version != 1 {
            return Err(ContractError::InvalidVersion);
        }
        if owner.is_some_and(|o| o.workspace() != self.workspace_id()) {
            return Err(ContractError::ScopeMismatch);
        }
        let operation = match &e.request {
            ReadRequest::Catalog => "catalog",
            ReadRequest::Groups { .. } => "groups",
            ReadRequest::Group { .. } => "group",
            ReadRequest::Runs { .. } => "runs",
            ReadRequest::Run { .. } => "run",
            ReadRequest::LocalIntent { .. } => "local_intent",
            ReadRequest::Workflow { .. } => "workflow",
        };
        let mut out = match e.request {
            ReadRequest::Catalog => {
                json!({"default_mode":"host_only","modes":[{"id":"host_only","selection":"initial_default"},{"id":"fixed","selection":"explicit"},{"id":"per_task","selection":"explicit"}],"coordination_is_management":false,"configuration_changes_apply_to":"future_runs_only"})
            }
            ReadRequest::Groups {
                limit,
                after_group_id,
            } => {
                page(limit, &after_group_id)?;
                let rows=io(self.database().query("SELECT group_id FROM group_runtime_groups WHERE workspace=? AND project_id=? AND group_id>? ORDER BY group_id LIMIT ?",&[self.workspace_id(),&s.project,after_group_id.as_deref().unwrap_or(""),&(limit+1).to_string()]))?;
                let groups: Vec<Value> = rows
                    .iter()
                    .take(limit as usize)
                    .map(|r| self.group_ui_configuration(s, cell(r, 0)?))
                    .collect::<Result<_>>()?;
                let cursor = if rows.len() > limit as usize {
                    groups.last().and_then(|g| g["group_id"].as_str())
                } else {
                    None
                };
                json!({"groups":groups,"next_after_group_id":cursor})
            }
            ReadRequest::Group { group_id } => {
                json!({"group":self.group_ui_configuration(s,&group_id)?})
            }
            ReadRequest::Runs {
                group_id,
                limit,
                after_run_id,
            } => {
                let scope = GroupScope::current(self, &s.project, &group_id)?;
                page(limit, &after_run_id)?;
                let rows=io(self.database().query("SELECT run_id FROM group_runtime_runs WHERE group_id=? AND run_id>? ORDER BY run_id LIMIT ?",&[&group_id,after_run_id.as_deref().unwrap_or(""),&(limit+1).to_string()]))?;
                let runs: Vec<Value> = rows
                    .iter()
                    .take(limit as usize)
                    .map(|r| self.group_ui_run(s, &scope, cell(r, 0)?, owner))
                    .collect::<Result<_>>()?;
                let cursor = if rows.len() > limit as usize {
                    runs.last().and_then(|r| r["run_id"].as_str())
                } else {
                    None
                };
                json!({"runs":runs,"next_after_run_id":cursor})
            }
            ReadRequest::Run { group_id, run_id } => {
                let scope = GroupScope::current(self, &s.project, &group_id)?;
                json!({"run":self.group_ui_run(s,&scope,&run_id,owner)?})
            }
            ReadRequest::LocalIntent {
                group_id,
                intent_id,
            } => {
                GroupScope::current(self, &s.project, &group_id)?;
                id(&intent_id)?;
                let rows=io(self.database().query("SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id=? AND workspace=? AND project_id=? AND group_id=?",&[&intent_id,self.workspace_id(),&s.project,&group_id]))?;
                let row = rows.first().ok_or(ContractError::NotFound)?;
                let status = cell(row, 0)?;
                let receipt: Option<LocalReceipt> = row[1]
                    .as_deref()
                    .map(|x| serde_json::from_str(x).map_err(|_| ContractError::StorageCorrupt))
                    .transpose()?;
                if let Some(r) = &receipt {
                    let expected = match r.status {
                        LocalStatus::Committed => "committed",
                        LocalStatus::Rejected => "rejected",
                        LocalStatus::PendingOriginal => "pending",
                    };
                    if r.intent_id != intent_id || expected != status {
                        return Err(ContractError::StorageCorrupt);
                    }
                }
                let status = if receipt.is_none() {
                    "pending_original"
                } else {
                    status
                };
                json!({"local_intent":{"intent_id":intent_id,"status":status,"receipt":receipt,"recovery_action":if status=="pending_original"{"query_original_local_intent"}else{"none"}}})
            }
            ReadRequest::Workflow { group_id, run_id } => {
                let scope = GroupScope::current(self, &s.project, &group_id)?;
                match workflow {
                    Some((ledger, session)) => {
                        json!({"workflow":self.group_ui_workflow(s,&scope,&group_id,&run_id,ledger,session,owner)?})
                    }
                    None => {
                        json!({"workflow":{"availability":"not_bound","reason":"workflow_owner_not_bound","complete_lifetime_children":false}})
                    }
                }
            }
        };
        out["schema_version"] = json!(1);
        out["operation"] = json!(operation);
        out["execution_authority"] = json!(false);
        if serde_json::to_vec(&out)
            .map_err(|_| ContractError::InvalidPayload)?
            .len()
            > 1_048_576
        {
            return Err(ContractError::TextLimit);
        }
        Ok(out)
    }
    fn group_ui_run(
        &self,
        _s: &GroupUiScope,
        scope: &GroupScope,
        run_id: &str,
        owner: Option<&AgentOwner>,
    ) -> Result<Value> {
        let run = self.group_run(scope, run_id)?;
        let group = self.group_registration(scope)?;
        let nodes = self.group_nodes(scope, run_id)?;
        let mut lookup_failed = false;
        let mut unresolved = false;
        let mut view_nodes = Vec::new();
        for n in &nodes {
            let original = match (&n.request_id, owner) {
                (Some(first), Some(owner)) => {
                    match original_json(owner, first, &group.conversation_id) {
                        Ok(v) => {
                            unresolved |= !v["original_chain_resolved"].as_bool().unwrap_or(false);
                            v
                        }
                        Err(ContractError::ScopeMismatch) => {
                            return Err(ContractError::ScopeMismatch)
                        }
                        Err(_) => {
                            lookup_failed = true;
                            unavailable_original(first)
                        }
                    }
                }
                (Some(first), None) => {
                    lookup_failed = true;
                    json!({"lookup_status":"not_bound","original_request_id":first,"actual_usage_known":false,"original_chain_resolved":false,"actual_micro_cny":null})
                }
                _ => Value::Null,
            };
            view_nodes.push(json!({"node_id":n.node_id,"member_id":n.member_id,"coordinator_epoch":n.epoch.to_string(),"persisted_state":n.state,"dependencies":n.dependencies,"payload_digest":n.payload_digest,"original":original}));
        }
        let now_ms: u64 = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|_| ContractError::Unknown)?
            .as_millis()
            .try_into()
            .map_err(|_| ContractError::Unknown)?;
        let deadline_reached = now_ms >= run.deadline_ms;
        let live_state = if run.stopped {
            "stopped"
        } else if deadline_reached && !lookup_failed && !unresolved {
            "deadline_reached"
        } else if owner.is_none() {
            "owner_not_bound"
        } else if lookup_failed || unresolved {
            "reconciling"
        } else if nodes
            .iter()
            .any(|n| n.state == "pending_host_admission" && n.epoch == run.epoch)
        {
            "pending_host_admission"
        } else if nodes.is_empty() {
            "configured"
        } else if nodes.iter().any(|n| n.request_id.is_some()) {
            "originals_resolved"
        } else {
            "local_proposals_inactive"
        };
        let (budget, budget_status) = match owner {
            None => (None, "not_bound"),
            Some(o) => match o.budget() {
                Ok(b) => (
                    Some(
                        json!({"scope":"workspace_owner","cap_micro_cny":b.cap_micro_cny,"held_micro_cny":b.held_micro_cny,"charged_micro_cny":b.charged_micro_cny,"used_calls":b.used_calls,"max_calls":b.max_calls}),
                    ),
                    "available",
                ),
                Err(_) => (None, "unavailable"),
            },
        };
        let mut summary = run.summary.clone();
        if let Some(nodes) = summary["nodes"].as_array_mut() {
            for node in nodes {
                if let Some(epoch) = node["epoch"].as_u64() {
                    node["epoch"] = json!(epoch.to_string());
                }
            }
        }
        Ok(
            json!({"run_id":run.run_id,"root_task_id":run.root_task_id,"coordination_mode":run.coordination_mode,"coordinator_id":run.leader,"coordinator_epoch":run.epoch.to_string(),"handoffs":run.handoffs.to_string(),"max_handoffs":run.max_handoffs.to_string(),"max_rounds":run.max_rounds.to_string(),"deadline_ms":run.deadline_ms.to_string(),"stopped":run.stopped,"deadline_reached":deadline_reached,"members":run.members,"live_state":live_state,"original_owner_status":if owner.is_none(){"not_bound"}else if lookup_failed{"unavailable"}else{"available"},"nodes":view_nodes,"persisted_summary":summary,"owner_budget":budget,"owner_budget_status":budget_status,"canonical_payload_binding":"not_available_from_current_owner_api","execution_authority":false}),
        )
    }
    /// Only the actual owner's scoped snapshot supplies rows. Display events are
    /// deliberately not used to infer lifetime counts, attempts, identity or cost.
    fn group_ui_workflow(
        &self,
        s: &GroupUiScope,
        scope: &GroupScope,
        group_id: &str,
        run_id: &str,
        ledger: &mut RunLedger,
        session: &str,
        owner: Option<&AgentOwner>,
    ) -> Result<Value> {
        let run = self.group_run(scope, run_id)?;
        let group = self.group_registration(scope)?;
        let native_scope =
            RunScope::current(self, session, &group.conversation_id, Some(&s.project))
                .map_err(|_| ContractError::ScopeMismatch)?;
        let raw = ledger
            .execute(
                &json!({"action":"snapshot","root_id":run.root_task_id,"after_seq":0}).to_string(),
                self,
                &native_scope,
            )
            .map_err(|e| match e {
                "workflow_run_not_found" => ContractError::NotFound,
                "workflow_preview_limit" => ContractError::TextLimit,
                "workflow_scope_mismatch" => ContractError::ScopeMismatch,
                "workflow_root_required" => ContractError::InvalidPayload,
                _ => ContractError::Storage,
            })?;
        let root = &raw["root"];
        let rows = raw["runs"]
            .as_array()
            .ok_or(ContractError::StorageCorrupt)?;
        if root["id"] != run.root_task_id
            || root["root_id"] != run.root_task_id
            || root["parent_id"] != Value::Null
            || root["project_id"] != s.project
            || root["conversation_id"] != group.conversation_id
        {
            return Err(ContractError::ScopeMismatch);
        }
        let mut seen = BTreeSet::new();
        let mut root_count = 0;
        let mut children = Vec::new();
        let mut active = 0;
        let mut request_ids = BTreeSet::new();
        for row in rows {
            let child = row["id"].as_str().ok_or(ContractError::StorageCorrupt)?;
            if !seen.insert(child) {
                return Err(ContractError::StorageCorrupt);
            }
            if row["root_id"] != run.root_task_id || row["project_id"] != s.project {
                return Err(ContractError::ScopeMismatch);
            }
            if child == run.root_task_id {
                root_count += 1;
                continue;
            }
            if row["parent_id"] != run.root_task_id || row["depth"] != 1 {
                return Err(ContractError::StorageCorrupt);
            }
            active += usize::from(matches!(
                row["status"].as_str(),
                Some("queued" | "running" | "waiting_confirmation" | "unknown")
            ));
            let mut child_view = row.clone();
            child_view
                .as_object_mut()
                .ok_or(ContractError::StorageCorrupt)?
                .remove("can_control");
            let original = match row["remote_request_id"].as_str() {
                Some(first) => {
                    request_ids.insert(first.to_string());
                    match owner {
                        Some(o) => match original_json(
                            o,
                            first,
                            row["conversation_id"]
                                .as_str()
                                .ok_or(ContractError::StorageCorrupt)?,
                        ) {
                            Ok(v) => v,
                            Err(ContractError::ScopeMismatch) => {
                                return Err(ContractError::ScopeMismatch)
                            }
                            Err(_) => unavailable_original(first),
                        },
                        None => {
                            json!({"lookup_status":"not_bound","original_request_id":first,"actual_usage_known":false,"original_chain_resolved":false,"actual_micro_cny":null})
                        }
                    }
                }
                None => Value::Null,
            };
            child_view["original"] = original;
            for field in ["created_seq", "updated_seq"] {
                if let Some(v) = child_view[field].as_u64() {
                    child_view[field] = json!(v.to_string());
                }
            }
            children.push(child_view);
        }
        if root_count != 1 || children.len() > 8 || active > 2 {
            return Err(ContractError::StorageCorrupt);
        }
        let mut root = root.clone();
        root.as_object_mut()
            .ok_or(ContractError::StorageCorrupt)?
            .remove("can_control");
        for field in ["created_seq", "updated_seq"] {
            if let Some(v) = root[field].as_u64() {
                root[field] = json!(v.to_string());
            }
        }
        Ok(
            json!({"availability":"available","group_id":group_id,"run_id":run_id,"root":root,"children":children,"lifetime_child_count":rows.len()-1,"active_child_count":active,"original_request_ids":request_ids,"complete_lifetime_children":true,"source":"actual_run_ledger_snapshot","events_are_display_only":true,"display_event_count":raw["events"].as_array().map(Vec::len),"canonical_payload_binding":"not_available_from_current_owner_api","host_dispatch_permission":false,"execution_authority":false}),
        )
    }
    /// Builds an exact local command only. Host auth context and native authority
    /// are absent from the wire schema. The trusted grant/execute steps stay separate.
    pub fn group_ui_prepare_configuration(
        &self,
        s: &GroupUiScope,
        raw: &str,
        authority: AuthorityBinding,
        conversation: Option<&str>,
    ) -> Result<GroupCommand> {
        self.check_group_ui_scope(s)?;
        if authority.owner_epoch != self.owner_epoch() {
            return Err(ContractError::InvalidAuthority);
        }
        let e: ChangeEnvelope = parsed(raw, 65536)?;
        if e.schema_version != 1 {
            return Err(ContractError::InvalidVersion);
        }
        let (intent_id, group_id, expected_revision, operation) = match e.change {
            ConfigurationChange::Register {
                intent_id,
                group_id,
                expected_revision,
                mode,
                fixed_leader,
                members,
            } => {
                let conversation = conversation.ok_or(ContractError::Required)?;
                id(conversation)?;
                if expected_revision.value() != 0 {
                    return Err(ContractError::InvalidRevision);
                }
                (
                    intent_id,
                    group_id,
                    expected_revision,
                    GroupOperation::Register {
                        owner: s.actor.clone(),
                        admins: BTreeSet::new(),
                        conversation_id: conversation.into(),
                        mode: mode.unwrap_or_else(|| "host_only".into()),
                        fixed_leader,
                        members,
                    },
                )
            }
            ConfigurationChange::Configure {
                intent_id,
                group_id,
                expected_revision,
                mode,
                fixed_leader,
                members,
            } => {
                GroupScope::current(self, &s.project, &group_id)?;
                (
                    intent_id,
                    group_id,
                    expected_revision,
                    GroupOperation::Configure {
                        mode,
                        fixed_leader,
                        members,
                    },
                )
            }
        };
        id(&intent_id)?;
        id(&group_id)?;
        match &operation {
            GroupOperation::Register {
                mode,
                fixed_leader,
                members,
                ..
            }
            | GroupOperation::Configure {
                mode,
                fixed_leader,
                members,
            } => validate_configuration(&s.project, mode, fixed_leader, members)?,
            _ => return Err(ContractError::UnsupportedOperation),
        }
        Ok(GroupCommand {
            intent_id,
            workspace_id: self.workspace_id().into(),
            project_id: s.project.clone(),
            group_id,
            expected_revision,
            expected_epoch: None,
            actor: GroupActor::Human(s.actor.clone()),
            authority,
            operation,
        })
    }
}
