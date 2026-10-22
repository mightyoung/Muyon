//! Request-only routing facts for the ONE existing host gateway. Never a permit.
use super::*;
use crate::agent::{
    owner::{origin::GroupOriginSeed, AgentPlan, HostedCostVerifier},
    workflow::{RunLedger, RunScope},
};
#[derive(Serialize)]
pub struct GroupRequestGate {
    request_id: String,
    group_hold: bool,
    reason: String,
    origin: Option<crate::agent::owner::origin::RequestOrigin>,
    workflow: Option<crate::agent::workflow::WorkflowRequestAttribution>,
    canonical: Option<binding::RegisteredGroupRequest>,
    source_error: Option<String>,
    cross_owner_atomic: bool,
    execution_authority: bool,
}
impl GroupRequestGate {
    pub fn group_hold(&self) -> bool {
        self.group_hold
    }
}
/// Selectors only: all recorded identity/context is reread from actual owners.
pub struct GroupChatPreparation<'a> {
    pub run_id: &'a str,
    pub workflow_run_id: &'a str,
    pub member_id: &'a str,
    pub text: &'a str,
}
impl BusinessStore {
    pub fn group_prepare_chat(
        &self,
        scope: &GroupScope,
        owner: &AgentOwner,
        ledger: &RunLedger,
        workflow_scope: &RunScope,
        request: GroupChatPreparation<'_>,
        verifier: Option<&dyn HostedCostVerifier>,
    ) -> Result<AgentPlan> {
        let group = self.group_owner(scope, owner)?;
        let run = self.group_run(scope, request.run_id)?;
        if run.stopped || now()? >= run.deadline_ms || !run.members.contains_key(request.member_id)
        {
            return Err(ContractError::InvalidAuthority);
        }
        let facts = ledger
            .admission_facts(workflow_scope, &run.root_task_id, owner)
            .map_err(|_| ContractError::Storage)?;
        let child = facts
            .children()
            .iter()
            .find(|c| c.id() == request.workflow_run_id)
            .ok_or(ContractError::ScopeMismatch)?;
        if facts.root().conversation_id() != group.conversation_id
            || facts.root().project_id() != Some(scope.project.as_str())
            || !facts.root().native_context_current()
            || child.project_id() != Some(scope.project.as_str())
            || child.kind() != "remote_chat"
            || !child.native_context_current()
            || !child.skill_current()
            || child.cancel_requested()
            || !child.originals().is_empty()
        {
            return Err(ContractError::InvalidAuthority);
        }
        let context = ledger
            .remote_context(workflow_scope, child.id())
            .map_err(|_| ContractError::InvalidAuthority)?;
        let allowed: Vec<&str> = context["tool_names"]
            .as_array()
            .ok_or(ContractError::Storage)?
            .iter()
            .map(|v| v.as_str().ok_or(ContractError::Storage))
            .collect::<Result<_>>()?;
        let seed = GroupOriginSeed {
            workspace_id: self.workspace_id().into(),
            project_id: scope.project.clone(),
            group_id: scope.group.clone(),
            run_id: run.run_id.clone(),
            root_task_id: run.root_task_id.clone(),
            workflow_run_id: child.id().into(),
            member_id: request.member_id.into(),
            conversation_id: child.conversation_id().into(),
            coordinator_epoch: Revision::new(run.epoch),
            group_revision: group.revision,
            owner_epoch: self.owner_epoch().into(),
            host_session: child.host_session().into(),
        };
        owner
            .prepare_group_chat_trusted(seed, request.text, verifier, &allowed)
            .map_err(original_identity_read_error)
    }
    fn request_local_group_evidence(
        &self,
        request: &str,
        root: &str,
        conversation: &str,
    ) -> Result<bool> {
        let tables=io(self.database().query("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('group_runtime_schema','group_runtime_groups','group_runtime_runs','group_runtime_local_intents','group_runtime_intent_bindings','group_request_bindings','group_runtime_nodes','group_runtime_events','group_request_binding_schema')",&[]))?;
        let names: std::collections::BTreeSet<_> =
            tables.iter().map(|r| cell(r, 0)).collect::<Result<_>>()?;
        if names.is_empty() {
            return Ok(false);
        }
        if !names.contains("group_runtime_schema") {
            return Err(ContractError::Storage);
        }
        if io(self
            .database()
            .query("SELECT workspace,version FROM group_runtime_schema", &[]))?
            != vec![vec![Some(self.workspace_id().into()), Some("2".into())]]
        {
            return Err(ContractError::Storage);
        }
        for row in io(self
            .database()
            .query("SELECT workspace,record FROM group_runtime_groups", &[]))?
        {
            let group: Registration = decode(cell(&row, 1)?)?;
            if cell(&row, 0)? != self.workspace_id() {
                return Err(ContractError::Storage);
            }
            if group.conversation_id == conversation {
                return Ok(true);
            }
        }
        if !io(self.database().query(
            "SELECT node_id FROM group_runtime_nodes WHERE request_id=? OR request_id=?",
            &[request, root],
        ))?
        .is_empty()
        {
            return Ok(true);
        }
        if names.contains("group_request_bindings") {
            for row in io(self
                .database()
                .query("SELECT request_id,record FROM group_request_bindings", &[]))?
            {
                if matches!(cell(&row,0)?,v if v==request || v==root) {
                    return Ok(true);
                }
                let record: serde_json::Value = decode(cell(&row, 1)?)?;
                let original = record["request_id"]
                    .as_str()
                    .ok_or(ContractError::Storage)?;
                if original == request || original == root {
                    return Ok(true);
                }
            }
        }
        for row in io(self.database().query("SELECT i.intent_id,i.project_id,i.group_id,i.status,b.command FROM group_runtime_local_intents i LEFT JOIN group_runtime_intent_bindings b ON b.intent_id=i.intent_id",&[]))? {
            if row[4].is_none(){if cell(&row,3)?=="pending"{return Err(ContractError::Storage)}else{continue}}
            let c=self.group_original_command(cell(&row,0)?,cell(&row,1)?,cell(&row,2)?).map_err(|_|ContractError::Storage)?;
            if let GroupOperation::BindCanonical{request_id,..} | GroupOperation::BindOriginal{request_id,..} =&c.operation {
                if request_id==request || request_id==root{return Ok(true)}
            }
        }
        Ok(false)
    }
    /// A routing observation only. Errors are captured as strict HOLD facts;
    /// this method cannot authorize confirm, claim, budget or provider I/O.
    pub fn group_request_gate(
        &self,
        request: &str,
        owner: &AgentOwner,
        ledger: &RunLedger,
    ) -> GroupRequestGate {
        let mut out = GroupRequestGate {
            request_id: request.into(),
            group_hold: true,
            reason: "source_unavailable".into(),
            origin: None,
            workflow: None,
            canonical: None,
            source_error: None,
            cross_owner_atomic: false,
            execution_authority: false,
        };
        let result = (|| -> Result<()> {
            if owner.workspace() != self.workspace_id() || owner.owner_epoch() != self.owner_epoch()
            {
                return Err(ContractError::ScopeMismatch);
            }
            let origin = owner.request_origin(request).map_err(|e| {
                out.source_error = Some(e.into());
                ContractError::Storage
            })?;
            let direct = origin.is_direct();
            let conversation = origin.conversation_id().to_string();
            let group = origin.group_seed().cloned();
            let root = origin.root_request_id().map(str::to_owned);
            out.origin = Some(origin);
            if !direct && group.is_none() {
                out.reason = "legacy_origin_unknown".into();
                return Ok(());
            }
            let local_evidence = self.request_local_group_evidence(
                request,
                root.as_deref().ok_or(ContractError::Unknown)?,
                &conversation,
            )?;
            let attribution = ledger.request_attribution(request, owner).map_err(|e| {
                out.source_error = Some(e.into());
                ContractError::Storage
            })?;
            // Positive Direct classification still inspects actual ledger/group
            // facts: generic child prepare cannot bypass group provenance.
            let mut actual_groups = Vec::new();
            let mut group_evidence = false;
            if let Some(a) = &attribution {
                let schema=io(self.database().query("SELECT name FROM sqlite_master WHERE type='table' AND name='group_runtime_schema'",&[]))?;
                if !schema.is_empty() {
                    if io(self.database().query("SELECT workspace,version FROM group_runtime_schema",&[]))?!=vec![vec![Some(self.workspace_id().into()),Some("2".into())]]{return Err(ContractError::Storage)}
                    // Registration and original Start command survive loss of a
                    // run index. They remain group evidence, never nongroup proof.
                    for row in io(self.database().query("SELECT workspace,project_id,record FROM group_runtime_groups",&[]))? {
                        let registration:Registration=decode(cell(&row,2)?)?;
                        if cell(&row,0)?!=self.workspace_id(){return Err(ContractError::Storage)}
                        if registration.conversation_id==a.facts().root().conversation_id() && Some(cell(&row,1)?)==a.facts().root().project_id(){group_evidence=true;}
                    }
                    for row in io(self.database().query("SELECT command FROM group_runtime_intent_bindings",&[]))? {
                        let command:GroupCommand=decode(cell(&row,0)?)?;
                        if command.workspace_id!=self.workspace_id(){return Err(ContractError::Storage)}
                        if matches!(&command.operation,GroupOperation::Start{root_task_id,..} if root_task_id==a.facts().root().id()){group_evidence=true;}
                    }
                    let rows=io(self.database().query("SELECT run_id,group_id,record FROM group_runtime_runs",&[]))?;
                    for row in rows {
                        let run:StoredRun=decode(cell(&row,2)?)?;
                        if cell(&row,0)?!=run.run_id {return Err(ContractError::Storage)}
                        if run.root_task_id==a.facts().root().id(){actual_groups.push((cell(&row,1)?.to_string(),run));}
                    }
                } else if !io(self.database().query("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('group_runtime_groups','group_runtime_runs','group_runtime_local_intents','group_runtime_intent_bindings','group_request_bindings','group_runtime_nodes','group_runtime_events','group_request_binding_schema')",&[]))?.is_empty(){return Err(ContractError::Storage)}
            }
            if let Some(g) = group {
                out.reason = "group_origin_requires_hold".into();
                let a = attribution.as_ref().ok_or(ContractError::ScopeMismatch)?;
                if a.child().id() != g.workflow_run_id
                    || a.facts().root().id() != g.root_task_id
                    || a.child().conversation_id() != g.conversation_id
                    || a.child().project_id() != Some(g.project_id.as_str())
                    || actual_groups
                        .iter()
                        .filter(|(id, r)| id == &g.group_id && r.run_id == g.run_id)
                        .count()
                        != 1
                {
                    return Err(ContractError::BindingMismatch);
                }
                let scope = GroupScope::current(self, &g.project_id, &g.group_id)?;
                let mapping = io(self.database().query(
                    "SELECT node_id FROM group_request_bindings WHERE request_id=?",
                    &[root.as_deref().ok_or(ContractError::Unknown)?],
                ));
                match mapping {
                    Ok(rows) if rows.len() == 1 => {
                        let binding =
                            self.group_request_binding(&scope, &g.run_id, cell(&rows[0], 0)?)?;
                        let value =
                            serde_json::to_value(&binding).map_err(|_| ContractError::Storage)?;
                        if value["workflow_run_id"] != g.workflow_run_id
                            || value["member_id"] != g.member_id
                            || value["root_task_id"] != g.root_task_id
                            || value["coordinator_epoch"] != json_revision(&g.coordinator_epoch)
                        {
                            return Err(ContractError::BindingMismatch);
                        }
                        out.canonical = Some(binding);
                        out.reason = "cross_owner_consumption_unclosed".into();
                    }
                    _ => {
                        out.reason = "canonical_mapping_unavailable".into();
                    }
                }
            } else if local_evidence || group_evidence || !actual_groups.is_empty() {
                out.reason = "actual_group_child_missing_group_origin".into();
            } else {
                out.group_hold = false;
                out.reason = "direct_non_group_observed".into();
            }
            out.workflow = attribution;
            Ok(())
        })();
        if let Err(e) = result {
            out.group_hold = true;
            out.reason = "source_inconclusive".into();
            if out.source_error.is_none() {
                out.source_error = Some(format!("{e:?}"));
            }
        }
        out
    }
}
fn json_revision(r: &Revision) -> serde_json::Value {
    serde_json::Value::String(r.as_str().into())
}
