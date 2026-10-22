//! Persisted preparation provenance. These facts never confer execution authority.
use super::*;
const DDL: &str = "CREATE TABLE request_origins(request_id TEXT PRIMARY KEY,record TEXT NOT NULL)";
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct GroupOriginSeed {
    pub workspace_id: String,
    pub project_id: String,
    pub group_id: String,
    pub run_id: String,
    pub root_task_id: String,
    pub workflow_run_id: String,
    pub member_id: String,
    pub conversation_id: String,
    pub coordinator_epoch: Revision,
    pub group_revision: Revision,
    pub owner_epoch: String,
    pub host_session: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum Classification {
    Direct,
    Group,
    LegacyUnknown,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct OriginRecord {
    request_id: String,
    workspace_id: String,
    conversation_id: String,
    configuration_id: String,
    request_epoch: String,
    payload_digest: String,
    classification: Classification,
    root_request_id: Option<String>,
    parent_request_id: Option<String>,
    group: Option<GroupOriginSeed>,
}
/// No Deserialize/public constructor. Absence or corruption is never Direct.
#[derive(Clone, Debug, Serialize)]
pub struct RequestOrigin {
    #[serde(flatten)]
    record: OriginRecord,
}
impl RequestOrigin {
    pub fn conversation_id(&self) -> &str {
        &self.record.conversation_id
    }
    pub fn is_direct(&self) -> bool {
        self.record.classification == Classification::Direct
    }
    pub fn is_group(&self) -> bool {
        self.record.classification == Classification::Group
    }
    pub fn root_request_id(&self) -> Option<&str> {
        self.record.root_request_id.as_deref()
    }
    pub(crate) fn group_seed(&self) -> Option<&GroupOriginSeed> {
        self.record.group.as_ref()
    }
}
pub(super) enum OriginDraft {
    Direct,
    Group(GroupOriginSeed),
    Followup(RequestOrigin),
}
type ParentWitness = (Vec<Option<String>>, Vec<Vec<Option<String>>>, String);
pub(in crate::agent) struct PrepareWitness {
    request: Vec<Option<String>>,
    origin: String,
    parent: Option<ParentWitness>,
}
fn encode<T: Serialize>(value: &T) -> Result<String> {
    serde_json::to_string(value).map_err(|_| "agent_origin_invalid")
}
pub(super) fn initialize(db: &Db) -> Result<()> {
    storage(db.exec(DDL, &[]))?;
    Ok(())
}
pub(super) fn validate(db: &Db) -> Result<()> {
    if storage(db.query(
        "SELECT sql FROM sqlite_master WHERE name='request_origins' AND type='table'",
        &[],
    ))? != vec![vec![Some(DDL.into())]]
    {
        return Err("agent_origin_schema_invalid");
    }
    Ok(())
}
pub(super) fn migrate(db: &Db, workspace: &str) -> Result<()> {
    let tx = storage(db.transaction())?;
    let requests = storage(db.query("SELECT rowid,* FROM requests ORDER BY id", &[]))?;
    let config = storage(db.query("SELECT * FROM configuration ORDER BY slot", &[]))?;
    let tools = storage(db.query("SELECT * FROM tool_steps ORDER BY request_id", &[]))?;
    initialize(db)?;
    let rows = storage(db.query(
        "SELECT id,conversation,config,epoch,digest FROM requests ORDER BY id",
        &[],
    ))?;
    let mut expected = Vec::new();
    for r in rows {
        let record = OriginRecord {
            request_id: cell(&r, 0)?.into(),
            workspace_id: workspace.into(),
            conversation_id: cell(&r, 1)?.into(),
            configuration_id: cell(&r, 2)?.into(),
            request_epoch: cell(&r, 3)?.into(),
            payload_digest: cell(&r, 4)?.into(),
            classification: Classification::LegacyUnknown,
            root_request_id: None,
            parent_request_id: None,
            group: None,
        };
        let raw = encode(&record)?;
        storage(db.exec(
            "INSERT INTO request_origins VALUES(?,?)",
            &[&record.request_id, &raw],
        ))?;
        expected.push(vec![Some(record.request_id), Some(raw)]);
    }
    if storage(db.exec(
        "UPDATE meta SET version='4' WHERE workspace=? AND version='3'",
        &[workspace],
    ))? != 1
    {
        return Err("agent_origin_migration_invalid");
    }
    validate(db)?;
    if storage(db.query("SELECT workspace,version FROM meta", &[]))?
        != vec![vec![Some(workspace.into()), Some("4".into())]]
        || storage(db.query("SELECT rowid,* FROM requests ORDER BY id", &[]))? != requests
        || storage(db.query("SELECT * FROM configuration ORDER BY slot", &[]))? != config
        || storage(db.query("SELECT * FROM tool_steps ORDER BY request_id", &[]))? != tools
        || storage(db.query("SELECT * FROM request_origins ORDER BY request_id", &[]))? != expected
    {
        return Err("agent_origin_migration_invalid");
    }
    storage(tx.commit())
}
impl AgentOwner {
    fn origin_record(&self, request: &str) -> Result<OriginRecord> {
        let binding = self.request_binding(request)?;
        let rows = storage(self.db.query(
            "SELECT request_id,record FROM request_origins WHERE request_id=?",
            &[request],
        ))?;
        let r = rows.first().ok_or("agent_origin_unknown")?;
        let record: OriginRecord =
            serde_json::from_str(cell(r, 1)?).map_err(|_| "agent_origin_invalid")?;
        if cell(r, 0)? != request
            || record.request_id != request
            || record.workspace_id != self.workspace
            || record.conversation_id != binding.conversation_id()
            || record.configuration_id != binding.configuration_id()
            || record.request_epoch != binding.request_epoch()
            || record.payload_digest != binding.payload_digest()
            || (record.classification == Classification::Group) != record.group.is_some()
            || (record.classification == Classification::LegacyUnknown
                && (record.root_request_id.is_some() || record.parent_request_id.is_some()))
        {
            return Err("agent_origin_invalid");
        }
        Ok(record)
    }
    pub fn request_origin(&self, request: &str) -> Result<RequestOrigin> {
        let record = self.origin_record(request)?;
        if record.classification == Classification::LegacyUnknown {
            return Ok(RequestOrigin { record });
        }
        let mut next = record.clone();
        let mut seen = std::collections::BTreeSet::new();
        loop {
            if seen.len() >= 32 || !seen.insert(next.request_id.clone()) {
                return Err("agent_origin_chain_invalid");
            }
            if next.classification != record.classification
                || next.group != record.group
                || next.root_request_id != record.root_request_id
                || next.conversation_id != record.conversation_id
                || next.configuration_id != record.configuration_id
            {
                return Err("agent_origin_chain_invalid");
            }
            let reverse = storage(self.db.query(
                "SELECT request_id FROM tool_steps WHERE followup=?",
                &[&next.request_id],
            ))?;
            match &next.parent_request_id {
                Some(parent) => {
                    if reverse != vec![vec![Some(parent.clone())]] {
                        return Err("agent_origin_chain_invalid");
                    }
                    next = self.origin_record(parent)?;
                }
                None => {
                    if !reverse.is_empty()
                        || next.root_request_id.as_deref() != Some(next.request_id.as_str())
                    {
                        return Err("agent_origin_chain_invalid");
                    }
                    break;
                }
            }
        }
        if let Some(g) = &record.group {
            if g.workspace_id != self.workspace || g.conversation_id != record.conversation_id {
                return Err("agent_origin_invalid");
            }
        }
        Ok(RequestOrigin { record })
    }
    pub(crate) fn prepare_group_chat_trusted(
        &self,
        origin: GroupOriginSeed,
        text: &str,
        verifier: Option<&dyn HostedCostVerifier>,
        allowed: &[&str],
    ) -> Result<AgentPlan> {
        if origin.workspace_id != self.workspace || origin.owner_epoch != self.epoch {
            return Err("agent_origin_scope_mismatch");
        }
        let conversation = origin.conversation_id.clone();
        self.prepare_chat_inner(
            &conversation,
            text,
            verifier,
            Some(allowed),
            OriginDraft::Group(origin),
        )
    }
    pub(super) fn origin_source_before_prepare(
        &self,
        draft: &OriginDraft,
        conversation: &str,
    ) -> Result<Option<ParentWitness>> {
        match draft {
            OriginDraft::Direct => {
                let previous = storage(self.db.query(
                    "SELECT id FROM requests WHERE conversation=?",
                    &[conversation],
                ))?;
                for r in previous {
                    let old = self.origin_record(cell(&r, 0)?)?;
                    if old.classification == Classification::Group {
                        return Err("agent_group_origin_required");
                    }
                }
                Ok(None)
            }
            OriginDraft::Followup(p) => {
                if p.record.classification == Classification::LegacyUnknown {
                    return Err("agent_origin_unknown");
                }
                if self.request_origin(&p.record.request_id)?.record != p.record {
                    return Err("agent_origin_chain_invalid");
                }
                let source = self.request(&p.record.request_id)?;
                let steps = storage(self.db.query(
                    "SELECT * FROM tool_steps WHERE request_id=?",
                    &[&p.record.request_id],
                ))?;
                Ok(Some((source, steps, encode(&p.record)?)))
            }
            OriginDraft::Group(_) => Ok(None),
        }
    }
    pub(super) fn write_origin(
        &self,
        plan: &AgentPlan,
        row: Vec<Option<String>>,
        draft: OriginDraft,
        parent_witness: Option<ParentWitness>,
    ) -> Result<PrepareWitness> {
        let (classification, root, parent, group) = match draft {
            OriginDraft::Direct => (
                Classification::Direct,
                Some(plan.request_id.clone()),
                None,
                None,
            ),
            OriginDraft::Group(g) => (
                Classification::Group,
                Some(plan.request_id.clone()),
                None,
                Some(g),
            ),
            OriginDraft::Followup(p) => (
                p.record.classification,
                p.record.root_request_id,
                Some(p.record.request_id),
                p.record.group,
            ),
        };
        let record = OriginRecord {
            request_id: plan.request_id.clone(),
            workspace_id: self.workspace.clone(),
            conversation_id: plan.conversation_id.clone(),
            configuration_id: plan.configuration_id.clone(),
            request_epoch: self.epoch.clone(),
            payload_digest: plan.payload_digest.clone(),
            classification,
            root_request_id: root,
            parent_request_id: parent,
            group,
        };
        let raw = encode(&record)?;
        if storage(self.db.exec(
            "INSERT INTO request_origins VALUES(?,?)",
            &[&plan.request_id, &raw],
        ))? != 1
        {
            return Err("agent_origin_write_failed");
        }
        Ok(PrepareWitness {
            request: row,
            origin: raw,
            parent: parent_witness,
        })
    }
    pub(in crate::agent) fn verify_prepare_origin_tail(
        &self,
        w: &PrepareWitness,
        binding: Option<&str>,
    ) -> Result<()> {
        let mut expected = w.request.clone();
        expected[16] = binding.map(str::to_owned);
        let request = cell(&expected, 0)?;
        if self.request(request)? != expected
            || storage(self.db.query(
                "SELECT record FROM request_origins WHERE request_id=?",
                &[request],
            ))? != vec![vec![Some(w.origin.clone())]]
        {
            return Err("agent_origin_write_failed");
        }
        if let Some((parent, steps, origin)) = &w.parent {
            let mut parent = parent.clone();
            parent[9] = Some("tool_consumed".into());
            let mut steps = steps.clone();
            if steps.len() != 1 || steps[0][5].is_some() {
                return Err("agent_origin_chain_invalid");
            };
            steps[0][5] = Some(request.into());
            let parent_id = cell(&parent, 0)?;
            if self.request(parent_id)? != parent
                || storage(
                    self.db
                        .query("SELECT * FROM tool_steps WHERE request_id=?", &[parent_id]),
                )? != steps
                || storage(self.db.query(
                    "SELECT record FROM request_origins WHERE request_id=?",
                    &[parent_id],
                ))? != vec![vec![Some(origin.clone())]]
            {
                return Err("agent_origin_chain_invalid");
            }
        }
        self.request_origin(request)?;
        Ok(())
    }
}
