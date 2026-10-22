//! Real canonical association, never an outbound permit or second gateway.
use super::*;
use crate::agent::{
    owner::{Observation, OriginalRequestBinding},
    workflow::{RunLedger, RunScope},
};

const TABLES: &[(&str,&str)] = &[
    ("group_request_binding_schema","CREATE TABLE group_request_binding_schema(workspace TEXT PRIMARY KEY,version TEXT NOT NULL)"),
    ("group_request_bindings","CREATE TABLE group_request_bindings(request_id TEXT PRIMARY KEY,node_id TEXT NOT NULL UNIQUE REFERENCES group_runtime_nodes(node_id),workflow_run_id TEXT NOT NULL UNIQUE,record TEXT NOT NULL)"),
];
#[derive(Clone, Copy)]
pub(super) struct CanonicalContext<'a> {
    pub ledger: &'a RunLedger,
    pub scope: &'a RunScope,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct StoredBinding {
    workspace_id: String,
    project_id: String,
    group_id: String,
    run_id: String,
    root_task_id: String,
    node_id: String,
    member_id: String,
    request_id: String,
    configuration_id: String,
    payload_digest: String,
    conversation_id: String,
    request_epoch: String,
    purpose: String,
    coordinator_epoch: Revision,
    authorized_group_revision: Revision,
    registered_revision: Revision,
    binding_owner_epoch: String,
    workflow_run_id: String,
    workflow_owner_epoch: String,
    host_session: String,
    workflow_revision: Revision,
    workflow_arguments_digest: String,
    workflow_skill_digest: Option<String>,
    local_intent_id: String,
    local_authority: AuthorityBinding,
    capabilities: Capabilities,
}
/// Persisted association only. No Deserialize/public constructor and no permission.
#[derive(Clone, Serialize)]
pub struct RegisteredGroupRequest {
    #[serde(flatten)]
    record: StoredBinding,
    execution_authority: bool,
}
#[derive(Serialize)]
pub struct GroupBindingCheck {
    binding: RegisteredGroupRequest,
    canonical_verified_now: bool,
    workflow_verified_now: bool,
    configuration_current: bool,
    context_current: bool,
    group_stopped: bool,
    original_chain_resolved: bool,
    observations: Vec<Observation>,
    recovery_state: String,
    source_error: Option<String>,
    cross_owner_atomic: bool,
    execution_authority: bool,
}
pub(super) struct BindingWitness {
    mapping: Vec<Vec<Option<String>>>,
    node: Vec<Vec<Option<String>>>,
    pub expected_run: Vec<Vec<Option<String>>>,
    source_plan_intent: String,
    source_plan_rows: Vec<Vec<Option<String>>>,
}
fn same_original(m: &StoredBinding, b: &OriginalRequestBinding) -> bool {
    m.workspace_id == b.workspace_id()
        && m.request_id == b.request_id()
        && m.conversation_id == b.conversation_id()
        && m.purpose == b.purpose()
        && m.configuration_id == b.configuration_id()
        && m.request_epoch == b.request_epoch()
        && m.payload_digest == b.payload_digest()
}
fn committed_command(
    store: &BusinessStore,
    intent: &str,
    project: &str,
    group: &str,
) -> Result<GroupCommand> {
    let c = store.group_original_command(intent, project, group)?;
    let rows = io(store.database().query(
        "SELECT status,receipt FROM group_runtime_local_intents WHERE intent_id=?",
        &[intent],
    ))?;
    let row = rows.first().ok_or(ContractError::Unknown)?;
    if cell(row, 0)? != "committed" || row[1].is_none() {
        return Err(ContractError::Unknown);
    }
    let receipt: LocalReceipt = decode(cell(row, 1)?)?;
    if receipt.intent_id != intent
        || receipt.status != LocalStatus::Committed
        || receipt.revision != c.expected_revision.next()?
        || receipt.result
            != serde_json::json!({"group_id":group,"run_id":run_id(&c.operation),"execution_authority":false})
    {
        return Err(ContractError::BindingMismatch);
    }
    let event = io(store.database().query(
        "SELECT group_id,run_id,record FROM group_runtime_events WHERE intent_id=?",
        &[intent],
    ))?;
    if event.is_empty() {
        return Err(ContractError::Unknown);
    }
    if event
        != vec![vec![
            Some(group.into()),
            Some(run_id(&c.operation).unwrap_or("").into()),
            Some(encode(&c.operation)?),
        ]]
    {
        return Err(ContractError::BindingMismatch);
    }
    Ok(c)
}
fn verify_node_plan(
    store: &BusinessStore,
    scope: &GroupScope,
    run: &str,
    node: &StoredNode,
) -> Result<GroupCommand> {
    let events = io(store.database().query(
        "SELECT intent_id,record FROM group_runtime_events WHERE group_id=? AND run_id=?",
        &[&scope.group, run],
    ))?;
    for event in events {
        if let GroupOperation::Plan {
            run_id,
            node_id,
            member_id,
            dependencies,
            capabilities,
            payload_digest,
        } = decode(cell(&event, 1)?)?
        {
            if node_id != node.node_id {
                continue;
            }
            let original =
                committed_command(store, cell(&event, 0)?, &scope.project, &scope.group)?;
            if encode(&original.operation)? != cell(&event, 1)?
                || original.expected_epoch != Some(node.epoch)
                || run_id != run
                || member_id != node.member_id
                || dependencies != node.dependencies
                || capabilities != node.capabilities
                || payload_digest != node.payload_digest
            {
                return Err(ContractError::BindingMismatch);
            }
            return Ok(original);
        }
    }
    Err(ContractError::Unknown)
}
impl BusinessStore {
    /// Explicit separate owned namespace; never registers a group or an account.
    pub fn initialize_group_request_bindings(&self) -> Result<()> {
        let db = self.database();
        let tx = io(db.transaction())?;
        if io(db.query("SELECT workspace,version FROM group_runtime_schema", &[]))?
            != vec![vec![Some(self.workspace_id().into()), Some("2".into())]]
        {
            return Err(ContractError::InvalidVersion);
        }
        let mut found = 0;
        for (name, ddl) in TABLES {
            let actual = io(db.query(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                &[name],
            ))?;
            if !actual.is_empty() {
                found += 1;
                if actual != vec![vec![Some((*ddl).into())]] {
                    return Err(ContractError::InvalidVersion);
                }
            }
        }
        if found == 0 {
            for (_, ddl) in TABLES {
                io(db.exec(ddl, &[]))?;
            }
            io(db.exec(
                "INSERT INTO group_request_binding_schema VALUES(?,'1')",
                &[self.workspace_id()],
            ))?;
        } else if found != TABLES.len() {
            return Err(ContractError::InvalidVersion);
        }
        if io(db.query(
            "SELECT workspace,version FROM group_request_binding_schema",
            &[],
        ))? != vec![vec![Some(self.workspace_id().into()), Some("1".into())]]
        {
            return Err(ContractError::ScopeMismatch);
        }
        io(tx.commit())
    }
    pub(super) fn group_bind_canonical_effect(
        &self,
        c: &GroupCommand,
        scope: &GroupScope,
        owner: &AgentOwner,
        context: CanonicalContext<'_>,
    ) -> Result<BindingWitness> {
        let GroupOperation::BindCanonical {
            run_id,
            node_id,
            workflow_run_id,
            request_id,
        } = &c.operation
        else {
            return Err(ContractError::InvalidPayload);
        };
        for id_value in [node_id, workflow_run_id, request_id] {
            id(id_value)?;
        }
        let group = self.group_owner(scope, owner)?;
        let run = self.group_run(scope, run_id)?;
        let mut node = self.group_node(scope, run_id, node_id)?;
        if node.node_id != *node_id
            || node.request_id.is_some()
            || !run.members.contains_key(&node.member_id)
        {
            return Err(ContractError::BindingMismatch);
        }
        let source_plan = verify_node_plan(self, scope, run_id, &node).map_err(|error| {
            if error == ContractError::Unknown {
                ContractError::InvalidAuthority
            } else {
                error
            }
        })?;
        let original = owner
            .request_binding(request_id)
            .map_err(original_identity_read_error)?;
        let facts = context
            .ledger
            .admission_facts(context.scope, &run.root_task_id, owner)
            .map_err(|_| ContractError::Storage)?;
        let child = facts
            .children()
            .iter()
            .find(|r| r.id() == workflow_run_id)
            .ok_or(ContractError::BindingMismatch)?;
        if facts.workspace_id() != self.workspace_id()
            || facts.root().project_id() != Some(c.project_id.as_str())
            || facts.root().conversation_id() != group.conversation_id
            || child.project_id() != Some(c.project_id.as_str())
            || child.kind() != "remote_chat"
            || child.originals().first() != Some(&original)
            || node.payload_digest != original.payload_digest()
            || child.conversation_id() != original.conversation_id()
        {
            return Err(ContractError::BindingMismatch);
        }
        let m = StoredBinding {
            workspace_id: self.workspace_id().into(),
            project_id: c.project_id.clone(),
            group_id: c.group_id.clone(),
            run_id: run_id.clone(),
            root_task_id: run.root_task_id,
            node_id: node_id.clone(),
            member_id: node.member_id.clone(),
            request_id: request_id.clone(),
            configuration_id: original.configuration_id().into(),
            payload_digest: original.payload_digest().into(),
            conversation_id: original.conversation_id().into(),
            request_epoch: original.request_epoch().into(),
            purpose: original.purpose().into(),
            coordinator_epoch: Revision::new(node.epoch),
            authorized_group_revision: c.expected_revision.clone(),
            registered_revision: c.expected_revision.next()?,
            binding_owner_epoch: self.owner_epoch().into(),
            workflow_run_id: workflow_run_id.clone(),
            workflow_owner_epoch: child.owner_epoch().into(),
            host_session: child.host_session().into(),
            workflow_revision: child.updated_seq().clone(),
            workflow_arguments_digest: child.arguments_digest().into(),
            workflow_skill_digest: child.skill_digest().map(str::to_owned),
            local_intent_id: c.intent_id.clone(),
            local_authority: c.authority.clone(),
            capabilities: node.capabilities.clone(),
        };
        if !io(self.database().query("SELECT request_id FROM group_request_bindings WHERE request_id=? OR node_id=? OR workflow_run_id=?", &[request_id,node_id,workflow_run_id]))?.is_empty() {return Err(ContractError::IntentConflict)}
        let raw = encode(&m)?;
        // An association consumes a local grant only. Original prepared/reserved/
        // Unknown state remains owned by AgentOwner and is never advanced here.
        node.request_id = Some(request_id.clone());
        let last = child.observations().last().ok_or(ContractError::Storage)?;
        node.state = if terminal(&last.status) {
            last.status.clone()
        } else {
            "unknown".into()
        };
        let witness = BindingWitness {
            mapping: vec![vec![
                Some(request_id.clone()),
                Some(node_id.clone()),
                Some(workflow_run_id.clone()),
                Some(raw.clone()),
            ]],
            node: vec![vec![
                Some(node_id.clone()),
                Some(run_id.clone()),
                Some(request_id.clone()),
                Some(encode(&node)?),
            ]],
            expected_run: Vec::new(),
            source_plan_intent: source_plan.intent_id.clone(),
            source_plan_rows: source_plan_rows(self, &source_plan.intent_id)?,
        };
        if io(self.database().exec(
            "INSERT INTO group_request_bindings VALUES(?,?,?,?)",
            &[request_id, node_id, workflow_run_id, &raw],
        ))? != 1
        {
            return Err(ContractError::Storage);
        }
        self.group_save_node(run_id, &node)?;
        Ok(witness)
    }
    /// Exact local association, validated against actual group/run/node facts.
    /// Canonical verification requires the separate actual-owner recheck below.
    pub fn group_request_binding(
        &self,
        scope: &GroupScope,
        run_id: &str,
        node_id: &str,
    ) -> Result<RegisteredGroupRequest> {
        let group = self.group_registration(scope)?;
        if io(self.database().query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='group_request_bindings'",
            &[],
        ))?
        .is_empty()
        {
            return Err(ContractError::NotFound);
        }
        let run = self.group_run(scope, run_id)?;
        let node = self.group_node(scope, run_id, node_id)?;
        let rows=io(self.database().query("SELECT request_id,node_id,workflow_run_id,record FROM group_request_bindings WHERE node_id=?",&[node_id]))?;
        let row = rows.first().ok_or(ContractError::NotFound)?;
        let m: StoredBinding = decode(cell(row, 3)?)?;
        if m.workspace_id != self.workspace_id()
            || m.project_id != scope.project
            || m.group_id != scope.group
            || m.run_id != run_id
            || m.node_id != node_id
            || m.root_task_id != run.root_task_id
            || m.member_id != node.member_id
            || m.coordinator_epoch.value() != node.epoch
            || m.capabilities != node.capabilities
            || m.payload_digest != node.payload_digest
            || node.request_id.as_deref() != Some(m.request_id.as_str())
            || cell(row, 0)? != m.request_id
            || cell(row, 1)? != m.node_id
            || cell(row, 2)? != m.workflow_run_id
            || m.registered_revision != m.authorized_group_revision.next()?
            || group.revision < m.registered_revision
        {
            return Err(ContractError::BindingMismatch);
        }
        verify_node_plan(self, scope, run_id, &node)?;
        let original = committed_command(self, &m.local_intent_id, &scope.project, &scope.group)?;
        if original.expected_revision != m.authorized_group_revision
            || encode(&original.authority)? != encode(&m.local_authority)?
            || !matches!(&original.operation,GroupOperation::BindCanonical{run_id:r,node_id:n,workflow_run_id:w,request_id:q} if r==&m.run_id && n==&m.node_id && w==&m.workflow_run_id && q==&m.request_id)
        {
            return Err(ContractError::BindingMismatch);
        }
        Ok(RegisteredGroupRequest {
            record: m,
            execution_authority: false,
        })
    }
    /// Read/reconcile only. Failures preserve the durable original identity and
    /// Unknown; this never claims, cancels, refunds, resends or issues permission.
    pub fn group_recheck_request_binding(
        &self,
        scope: &GroupScope,
        run_id: &str,
        node_id: &str,
        owner: &AgentOwner,
        ledger: &RunLedger,
        workflow_scope: &RunScope,
    ) -> Result<GroupBindingCheck> {
        let binding = self.group_request_binding(scope, run_id, node_id)?;
        let run = self.group_run(scope, run_id)?;
        let group = self.group_registration(scope)?;
        if owner.workspace() != self.workspace_id() {
            return Err(ContractError::ScopeMismatch);
        }
        let mut check = GroupBindingCheck {
            binding,
            canonical_verified_now: false,
            workflow_verified_now: false,
            configuration_current: false,
            context_current: false,
            group_stopped: run.stopped,
            original_chain_resolved: false,
            observations: vec![],
            recovery_state: "query_original".into(),
            source_error: None,
            cross_owner_atomic: false,
            execution_authority: false,
        };
        let m = &check.binding.record;
        let original = match owner.request_binding(&m.request_id) {
            Ok(v) => v,
            Err(e) => {
                check.source_error = Some(e.into());
                return Ok(check);
            }
        };
        if !same_original(m, &original) {
            check.recovery_state = "binding_mismatch".into();
            return Ok(check);
        }
        check.canonical_verified_now = true;
        check.observations = match owner.request_chain(&m.request_id) {
            Ok(v) => v,
            Err(e) => {
                check.source_error = Some(e.into());
                return Ok(check);
            }
        };
        check.original_chain_resolved = check
            .observations
            .last()
            .is_some_and(|o| terminal(&o.status));
        let facts = match ledger.admission_facts(workflow_scope, &m.root_task_id, owner) {
            Ok(v) => v,
            Err(e) => {
                check.source_error = Some(e.into());
                return Ok(check);
            }
        };
        let Some(child) = facts
            .children()
            .iter()
            .find(|r| r.id() == m.workflow_run_id)
        else {
            check.recovery_state = "binding_mismatch".into();
            return Ok(check);
        };
        if facts.root().conversation_id() != group.conversation_id
            || child.project_id() != Some(m.project_id.as_str())
            || child.originals().first() != Some(&original)
            || child.arguments_digest() != m.workflow_arguments_digest
            || child.skill_digest() != m.workflow_skill_digest.as_deref()
        {
            check.recovery_state = "binding_mismatch".into();
            return Ok(check);
        }
        check.workflow_verified_now = true;
        check.configuration_current = match owner.configuration() {
            Ok(configuration) => configuration.id == m.configuration_id,
            Err(error) => {
                check.source_error = Some(error.into());
                false
            }
        };
        check.context_current = check.configuration_current
            && !run.stopped
            && !facts.root().cancel_requested()
            && facts.root().native_context_current()
            && owner.owner_epoch() == self.owner_epoch()
            && m.binding_owner_epoch == self.owner_epoch()
            && m.request_epoch == self.owner_epoch()
            && child.native_context_current()
            && child.owner_epoch() == m.workflow_owner_epoch
            && child.host_session() == m.host_session
            && child.updated_seq() == &m.workflow_revision
            && child.skill_current()
            && !child.cancel_requested()
            && group.revision == m.registered_revision
            && run.epoch == m.coordinator_epoch.value()
            && now()? < run.deadline_ms;
        check.recovery_state = if !check.original_chain_resolved {
            "query_original"
        } else if run.stopped {
            "stopped"
        } else if !check.context_current {
            "stale_context"
        } else {
            "await_existing_host_gateway"
        }
        .into();
        Ok(check)
    }
    pub(super) fn group_pending_canonical_originals(
        &self,
        scope: &GroupScope,
        run: &str,
        owner: &AgentOwner,
    ) -> Result<Vec<String>> {
        let rows=io(self.database().query("SELECT intent_id FROM group_runtime_local_intents WHERE workspace=? AND project_id=? AND group_id=? AND status='pending' ORDER BY intent_id", &[self.workspace_id(),&scope.project,&scope.group]))?;
        let mut originals = std::collections::BTreeSet::new();
        for row in rows {
            let c = match self.group_original_command(cell(&row, 0)?, &scope.project, &scope.group)
            {
                Ok(value) => value,
                // Missing persisted command identity is inconclusive, including
                // legacy pending intents. It cannot prove absence of an original.
                Err(ContractError::Unknown) => return Err(ContractError::Storage),
                Err(error) => return Err(error),
            };
            if let GroupOperation::BindCanonical {
                run_id,
                node_id,
                request_id,
                ..
            } = &c.operation
            {
                if run_id != run {
                    continue;
                }
                let node = self.group_node(scope, run, node_id)?;
                if node.request_id.as_deref() == Some(request_id.as_str()) {
                    continue;
                }
                let original = owner
                    .request_binding(request_id)
                    .map_err(|_| ContractError::Storage)?;
                if original.workspace_id() != self.workspace_id() {
                    return Err(ContractError::ScopeMismatch);
                }
                // Pending local association is NOT permission to prepare a new
                // external original. Preserve the actual existing owner identity.
                originals.insert(original.request_id().to_string());
            }
        }
        Ok(originals.into_iter().collect())
    }
    pub(super) fn group_canonical_conversation(
        &self,
        scope: &GroupScope,
        run: &str,
        node: &str,
        owner: &AgentOwner,
    ) -> Result<Option<String>> {
        if io(self.database().query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='group_request_bindings'",
            &[],
        ))?
        .is_empty()
        {
            return Ok(None);
        }
        let binding = match self.group_request_binding(scope, run, node) {
            Ok(v) => v,
            Err(ContractError::NotFound) => return Ok(None),
            Err(e) => return Err(e),
        };
        let original = owner
            .request_binding(&binding.record.request_id)
            .map_err(original_identity_read_error)?;
        if !same_original(&binding.record, &original) {
            return Err(ContractError::BindingMismatch);
        }
        Ok(Some(original.conversation_id().into()))
    }
}
// Freeze all checked same-database authorization provenance before any effect write.
fn source_plan_rows(store: &BusinessStore, intent: &str) -> Result<Vec<Vec<Option<String>>>> {
    io(store.database().query("SELECT i.*,b.*,e.* FROM group_runtime_local_intents i JOIN group_runtime_intent_bindings b ON b.intent_id=i.intent_id JOIN group_runtime_events e ON e.intent_id=i.intent_id WHERE i.intent_id=?", &[intent]))
}
pub(super) fn verify_tail(store: &BusinessStore, w: &BindingWitness) -> Result<()> {
    if source_plan_rows(store, &w.source_plan_intent)? != w.source_plan_rows {
        return Err(ContractError::Storage);
    }
    let request = cell(&w.mapping[0], 0)?;
    let node = cell(&w.node[0], 0)?;
    let run = cell(&w.node[0], 1)?;
    if io(store.database().query("SELECT request_id,node_id,workflow_run_id,record FROM group_request_bindings WHERE request_id=?",&[request]))?!=w.mapping
        || io(store.database().query("SELECT node_id,run_id,request_id,record FROM group_runtime_nodes WHERE node_id=?",&[node]))?!=w.node
        || io(store.database().query("SELECT run_id,group_id,record FROM group_runtime_runs WHERE run_id=?",&[run]))?!=w.expected_run {return Err(ContractError::Storage)}
    Ok(())
}
