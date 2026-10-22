//! Real local coordination persistence on BusinessStore's owned connection.
//! Local group grants authorize only these local mutations, never Agent dispatch.
use crate::{
    agent::owner::AgentOwner,
    business::BusinessStore,
    contract::{stable_digest, AuthorityBinding, ContractError, Revision},
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
type Result<T> = std::result::Result<T, ContractError>;
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum GroupActor {
    Human(String),
    Member(String),
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Capabilities {
    pub scopes: BTreeSet<String>,
    pub permissions: BTreeSet<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupCommand {
    pub intent_id: String,
    pub workspace_id: String,
    pub project_id: String,
    pub group_id: String,
    pub expected_revision: Revision,
    pub expected_epoch: Option<u64>,
    pub actor: GroupActor,
    pub authority: AuthorityBinding,
    pub operation: GroupOperation,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum GroupOperation {
    Configure {
        mode: String,
        fixed_leader: Option<String>,
        members: BTreeMap<String, Capabilities>,
    },
    Register {
        owner: String,
        admins: BTreeSet<String>,
        conversation_id: String,
        mode: String,
        fixed_leader: Option<String>,
        members: BTreeMap<String, Capabilities>,
    },
    Start {
        run_id: String,
        root_task_id: String,
        leader: Option<String>,
        max_rounds: u64,
        max_handoffs: u64,
        deadline_ms: u64,
    },
    Plan {
        run_id: String,
        node_id: String,
        member_id: String,
        dependencies: BTreeSet<String>,
        capabilities: Capabilities,
        payload_digest: String,
    },
    BindOriginal {
        run_id: String,
        node_id: String,
        request_id: String,
    },
    Observe {
        run_id: String,
        node_id: String,
        evidence: Vec<StoredEvidence>,
    },
    Handoff {
        run_id: String,
        to: String,
    },
    Stop {
        run_id: String,
    },
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StoredEvidence {
    pub claim_id: String,
    pub source_id: String,
    pub source_revision: Revision,
    pub stance: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocalStatus {
    Committed,
    PendingOriginal,
    Rejected,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LocalReceipt {
    pub intent_id: String,
    pub status: LocalStatus,
    pub revision: Revision,
    pub result: serde_json::Value,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Registration {
    pub revision: Revision,
    pub owner: String,
    pub admins: BTreeSet<String>,
    pub conversation_id: String,
    pub mode: String,
    pub fixed_leader: Option<String>,
    pub members: BTreeMap<String, Capabilities>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StoredRun {
    #[serde(default)]
    pub coordination_mode: Option<String>,
    pub members: BTreeMap<String, Capabilities>,
    pub run_id: String,
    pub root_task_id: String,
    pub leader: Option<String>,
    pub epoch: u64,
    pub handoffs: u64,
    pub max_handoffs: u64,
    pub max_rounds: u64,
    pub deadline_ms: u64,
    pub stopped: bool,
    pub summary: serde_json::Value,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StoredNode {
    pub node_id: String,
    pub member_id: String,
    pub dependencies: BTreeSet<String>,
    pub capabilities: Capabilities,
    pub payload_digest: String,
    pub epoch: u64,
    pub state: String,
    pub request_id: Option<String>,
    pub evidence: Vec<StoredEvidence>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PendingAdvice {
    None,
    Stopped,
    LookupOriginal {
        request_id: String,
    },
    PendingHostAdmission {
        node_id: String,
        payload_digest: String,
        epoch: u64,
    },
}
/// Original identity plus the host-created request chain; no caller-supplied
/// followup IDs. Deref exposes the actual last receipt without renaming it.
#[derive(Clone, Debug, Serialize)]
pub struct OriginalRequestView {
    pub original_request_id: String,
    pub chain: Vec<crate::agent::owner::Observation>,
    pub current: crate::agent::owner::Observation,
}
impl std::ops::Deref for OriginalRequestView {
    type Target = crate::agent::owner::Observation;
    fn deref(&self) -> &Self::Target {
        &self.current
    }
}
/// Opaque current scope, checked against persisted group and project every use.
pub struct GroupScope {
    workspace: String,
    project: String,
    group: String,
    owner_epoch: String,
}

const SCHEMA:&[(&str,&str)] = &[
 ("group_runtime_schema","CREATE TABLE group_runtime_schema(workspace TEXT PRIMARY KEY,version TEXT NOT NULL)"),
 ("group_runtime_groups","CREATE TABLE group_runtime_groups(group_id TEXT PRIMARY KEY,workspace TEXT NOT NULL,project_id TEXT NOT NULL REFERENCES projects(id),revision TEXT NOT NULL,record TEXT NOT NULL)"),
 ("group_runtime_runs","CREATE TABLE group_runtime_runs(run_id TEXT PRIMARY KEY,group_id TEXT NOT NULL REFERENCES group_runtime_groups(group_id),record TEXT NOT NULL)"),
 ("group_runtime_nodes","CREATE TABLE group_runtime_nodes(node_id TEXT PRIMARY KEY,run_id TEXT NOT NULL REFERENCES group_runtime_runs(run_id),request_id TEXT UNIQUE,record TEXT NOT NULL)"),
 ("group_runtime_local_intents","CREATE TABLE group_runtime_local_intents(intent_id TEXT PRIMARY KEY,workspace TEXT NOT NULL,project_id TEXT NOT NULL,group_id TEXT NOT NULL,binding_digest TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN('pending','committed','rejected')),receipt TEXT)"),
 ("group_runtime_events","CREATE TABLE group_runtime_events(intent_id TEXT PRIMARY KEY,group_id TEXT NOT NULL,run_id TEXT,record TEXT NOT NULL)"),
];
const INTENT_BINDINGS_DDL: &str = "CREATE TABLE group_runtime_intent_bindings(intent_id TEXT PRIMARY KEY REFERENCES group_runtime_local_intents(intent_id),command TEXT NOT NULL)";
fn io<T>(v: crate::sqlite::Result<T>) -> Result<T> {
    v.map_err(|_| ContractError::Storage)
}
fn encode<T: Serialize>(v: &T) -> Result<String> {
    serde_json::to_string(v).map_err(|_| ContractError::InvalidPayload)
}
fn decode<T: serde::de::DeserializeOwned>(s: &str) -> Result<T> {
    serde_json::from_str(s).map_err(|_| ContractError::StorageCorrupt)
}
fn cell(row: &[Option<String>], n: usize) -> Result<&str> {
    row.get(n)
        .and_then(Option::as_deref)
        .ok_or(ContractError::StorageCorrupt)
}
fn now() -> Result<u64> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| ContractError::InvalidAuthority)?
        .as_millis()
        .try_into()
        .map_err(|_| ContractError::InvalidAuthority)
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
fn digest(c: &GroupCommand) -> Result<String> {
    let v = serde_json::to_value(c).map_err(|_| ContractError::InvalidPayload)?;
    if encode(&v)?.len() > 1_048_576 {
        return Err(ContractError::TextLimit);
    }
    stable_digest(&serde_json::json!({"domain":"muyon_group_local_v1","command":v}))
}
fn pending(c: &GroupCommand) -> LocalReceipt {
    LocalReceipt {
        intent_id: c.intent_id.clone(),
        status: LocalStatus::PendingOriginal,
        revision: c.expected_revision.clone(),
        result: serde_json::json!({"recovery_action":"query_original_local_intent","execution_authority":false}),
    }
}
impl GroupScope {
    pub fn current(s: &BusinessStore, project: &str, group: &str) -> Result<Self> {
        id(project)?;
        id(group)?;
        let scope = Self {
            workspace: s.workspace_id().into(),
            project: project.into(),
            group: group.into(),
            owner_epoch: s.owner_epoch().into(),
        };
        s.group_registration(&scope)?;
        Ok(scope)
    }
}
// Captured from the actual active grant in the effect transaction. This is not
// a reusable permission token; only the final exact UPDATE may consume it.
#[derive(PartialEq, Eq)]
struct GroupGrantWitness {
    expires_at_ms: String,
}
impl BusinessStore {
    /// Explicitly creates only the extension namespace, never a group/account.
    pub fn initialize_group_runtime(&self) -> Result<()> {
        let db = self.database();
        let tx = io(db.transaction())?;
        let mut found = 0;
        for (name, ddl) in SCHEMA {
            let rows = io(db.query(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                &[name],
            ))?;
            if !rows.is_empty() {
                found += 1;
                if rows.len() != 1 || cell(&rows[0], 0)? != *ddl {
                    return Err(ContractError::InvalidVersion);
                }
            }
        }
        if found == 0 {
            for (_, ddl) in SCHEMA {
                io(db.exec(ddl, &[]))?;
            }
            io(db.exec(
                "INSERT INTO group_runtime_schema VALUES(?,'1')",
                &[self.workspace_id()],
            ))?;
        } else if found != SCHEMA.len() {
            return Err(ContractError::InvalidVersion);
        }
        let rows = io(db.query("SELECT workspace,version FROM group_runtime_schema", &[]))?;
        if rows.len() != 1 || cell(&rows[0], 0)? != self.workspace_id() {
            return Err(ContractError::ScopeMismatch);
        }
        let bindings = io(db.query("SELECT sql FROM sqlite_master WHERE type='table' AND name='group_runtime_intent_bindings'", &[]))?;
        let mut legacy_journal = None;
        match cell(&rows[0], 1)? {
            "1" if bindings.is_empty() => {
                // Capture all original column bytes/NULLs BEFORE migration writes.
                // Version UPDATE triggers must not erase, rewrite or inject history.
                legacy_journal = Some(io(db.query("SELECT intent_id,workspace,project_id,group_id,binding_digest,status,receipt FROM group_runtime_local_intents ORDER BY intent_id", &[]))?);
                // Explicit, atomic extension migration; never invent principals
                // or reconstruct missing historical commands from group defaults.
                io(db.exec(INTENT_BINDINGS_DDL, &[]))?;
                if io(db.exec(
                    "UPDATE group_runtime_schema SET version='2' WHERE workspace=? AND version='1'",
                    &[self.workspace_id()],
                ))? != 1
                {
                    return Err(ContractError::Storage);
                }
            }
            "2" if bindings == vec![vec![Some(INTENT_BINDINGS_DDL.into())]] => {}
            _ => return Err(ContractError::InvalidVersion),
        }
        if io(db.query("SELECT workspace,version FROM group_runtime_schema", &[]))? != vec![vec![Some(self.workspace_id().into()), Some("2".into())]]
            || io(db.query("SELECT sql FROM sqlite_master WHERE type='table' AND name='group_runtime_intent_bindings'", &[]))? != vec![vec![Some(INTENT_BINDINGS_DDL.into())]] {
            return Err(ContractError::Storage);
        }
        if let Some(expected) = legacy_journal {
            let actual = io(db.query("SELECT intent_id,workspace,project_id,group_id,binding_digest,status,receipt FROM group_runtime_local_intents ORDER BY intent_id", &[]))?;
            if actual != expected
                || !io(db.query("SELECT 1 FROM group_runtime_intent_bindings LIMIT 1", &[]))?
                    .is_empty()
            {
                return Err(ContractError::Storage);
            }
        }
        // Only reads follow all migration writes; commit this verified transaction.
        io(tx.commit())
    }
    fn group_check(&self, c: &GroupCommand) -> Result<()> {
        for x in [
            &c.intent_id,
            &c.workspace_id,
            &c.project_id,
            &c.group_id,
            &c.authority.grant_id,
            &c.authority.owner_epoch,
        ] {
            id(x)?;
        }
        if c.workspace_id != self.workspace_id() || self.project(&c.project_id)?.deleted {
            return Err(ContractError::ScopeMismatch);
        }
        if c.authority.generation.value() == 0 {
            return Err(ContractError::InvalidAuthority);
        }
        let GroupActor::Human(actor) = &c.actor else {
            return Err(ContractError::InvalidAuthority);
        };
        id(actor)?;
        if let GroupOperation::Register { owner, .. } = &c.operation {
            if owner != actor {
                return Err(ContractError::InvalidAuthority);
            }
        } else {
            let scope = GroupScope::current(self, &c.project_id, &c.group_id)?;
            let group = self.group_registration(&scope)?;
            if actor != &group.owner && !group.admins.contains(actor) {
                return Err(ContractError::InvalidAuthority);
            }
        }
        Ok(())
    }
    fn group_authority(&self, c: &GroupCommand, binding: &str) -> Result<GroupGrantWitness> {
        if c.authority.owner_epoch != self.owner_epoch() {
            return Err(ContractError::InvalidAuthority);
        }
        let rows=io(self.database().query("SELECT expires_at_ms,admission_id FROM business_grants WHERE grant_id=? AND generation=? AND owner_epoch=? AND binding_digest=? AND active=1",&[&c.authority.grant_id,c.authority.generation.as_str(),self.owner_epoch(),binding]))?;
        if rows.len() != 1
            || rows[0][1].is_some()
            || now()? >= Revision::parse(cell(&rows[0], 0)?)?.value()
        {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(GroupGrantWitness {
            expires_at_ms: cell(&rows[0], 0)?.into(),
        })
    }
    fn group_verify_intent_tail(
        &self,
        c: &GroupCommand,
        binding: &str,
        status: &str,
        receipt: &LocalReceipt,
    ) -> Result<()> {
        let expected = vec![
            Some(c.workspace_id.clone()),
            Some(c.project_id.clone()),
            Some(c.group_id.clone()),
            Some(binding.into()),
            Some(status.into()),
            Some(encode(receipt)?),
        ];
        let rows=io(self.database().query("SELECT workspace,project_id,group_id,binding_digest,status,receipt FROM group_runtime_local_intents WHERE intent_id=?",&[&c.intent_id]))?;
        if rows != vec![expected] {
            return Err(ContractError::Storage);
        }
        self.group_verify_original_command(c)?;
        Ok(())
    }
    fn group_verify_pending_tail(&self, c: &GroupCommand, binding: &str) -> Result<()> {
        let expected = vec![
            Some(c.workspace_id.clone()),
            Some(c.project_id.clone()),
            Some(c.group_id.clone()),
            Some(binding.into()),
            Some("pending".into()),
            None,
        ];
        let rows=io(self.database().query("SELECT workspace,project_id,group_id,binding_digest,status,receipt FROM group_runtime_local_intents WHERE intent_id=?", &[&c.intent_id]))?;
        if rows != vec![expected] {
            return Err(ContractError::Storage);
        }
        self.group_verify_original_command(c)
    }
    fn group_verify_original_command(&self, c: &GroupCommand) -> Result<()> {
        let rows = io(self.database().query(
            "SELECT command FROM group_runtime_intent_bindings WHERE intent_id=?",
            &[&c.intent_id],
        ))?;
        if rows != vec![vec![Some(encode(c)?)]] {
            return Err(ContractError::Storage);
        }
        Ok(())
    }
    /// Historical identity lookup only: verifies the actual journal digest, not
    /// current grant expiry/epoch or a successfully created group. Never writes.
    pub(crate) fn group_original_command(
        &self,
        intent: &str,
        project: &str,
        group: &str,
    ) -> Result<GroupCommand> {
        let rows = io(self.database().query("SELECT j.binding_digest,b.command FROM group_runtime_local_intents j LEFT JOIN group_runtime_intent_bindings b ON b.intent_id=j.intent_id WHERE j.intent_id=? AND j.workspace=? AND j.project_id=? AND j.group_id=?", &[intent,self.workspace_id(),project,group]))?;
        let row = rows.first().ok_or(ContractError::NotFound)?;
        let raw = row
            .get(1)
            .and_then(Option::as_deref)
            .ok_or(ContractError::Unknown)?;
        let c: GroupCommand = decode(raw)?;
        if c.intent_id != intent
            || c.workspace_id != self.workspace_id()
            || c.project_id != project
            || c.group_id != group
            || digest(&c)? != cell(row, 0)?
        {
            return Err(ContractError::BindingMismatch);
        }
        let GroupActor::Human(actor) = &c.actor else {
            return Err(ContractError::InvalidAuthority);
        };
        id(actor)?;
        if let GroupOperation::Register { owner, .. } = &c.operation {
            if actor != owner {
                return Err(ContractError::InvalidAuthority);
            }
        }
        Ok(c)
    }
    fn group_consume_and_verify_tail(
        &self,
        tx: &crate::sqlite::Transaction<'_>,
        c: &GroupCommand,
        binding: &str,
        grant: &GroupGrantWitness,
        receipt: &LocalReceipt,
        expected_group: &[Vec<Option<String>>],
        configured_runs: &Option<Vec<Vec<Option<String>>>>,
    ) -> Result<()> {
        let db = self.database();
        if !tx.belongs_to(db) {
            return Err(ContractError::Storage);
        }
        // A consumed-looking row is insufficient: prove THIS transaction matched
        // the original active row, including its exact expiry and local-only
        // admission namespace. No CAST or lexical comparison of u64 TEXT.
        if self.group_authority(c, binding)? != *grant {
            return Err(ContractError::InvalidAuthority);
        }
        if io(db.exec("UPDATE business_grants SET active=0 WHERE grant_id=? AND generation=? AND owner_epoch=? AND binding_digest=? AND active=1 AND admission_id IS NULL AND expires_at_ms=?",&[&c.authority.grant_id,c.authority.generation.as_str(),self.owner_epoch(),binding,&grant.expires_at_ms]))? != 1 { return Err(ContractError::InvalidAuthority); }
        // All writes (including the consumption UPDATE) can run SQL triggers.
        // Only reads follow, then the caller commits this very transaction.
        self.group_check(c)?;
        let scope = GroupScope::current(self, &c.project_id, &c.group_id)?;
        let group = self.group_registration(&scope)?;
        if group.revision != receipt.revision {
            return Err(ContractError::RevisionConflict);
        }
        let actual_group=io(db.query("SELECT workspace,project_id,revision,record FROM group_runtime_groups WHERE group_id=?",&[&c.group_id]))?;
        if actual_group != expected_group {
            return Err(ContractError::Storage);
        }
        // Configure must preserve every existing run's captured coordination
        // facts, including legacy rows frozen before changing future defaults.
        // Compare the intended complete set after ALL trigger-capable writes.
        if let Some(expected) = configured_runs {
            let actual = io(db.query("SELECT run_id,group_id,record FROM group_runtime_runs WHERE group_id=? ORDER BY run_id", &[&c.group_id]))?;
            if &actual != expected {
                return Err(ContractError::Storage);
            }
        }
        self.group_verify_intent_tail(c, binding, "committed", receipt)?;
        let events = io(db.query(
            "SELECT group_id,run_id,record FROM group_runtime_events WHERE intent_id=?",
            &[&c.intent_id],
        ))?;
        if events
            != vec![vec![
                Some(c.group_id.clone()),
                Some(run_id(&c.operation).unwrap_or("").into()),
                Some(encode(&c.operation)?),
            ]]
        {
            return Err(ContractError::Storage);
        }
        let consumed=io(db.query("SELECT generation,owner_epoch,binding_digest,active,admission_id,expires_at_ms FROM business_grants WHERE grant_id=?",&[&c.authority.grant_id]))?;
        if consumed
            != vec![vec![
                Some(c.authority.generation.as_str().into()),
                Some(self.owner_epoch().into()),
                Some(binding.into()),
                Some("0".into()),
                None,
                Some(grant.expires_at_ms.clone()),
            ]]
            || now()? >= Revision::parse(&grant.expires_at_ms)?.value()
        {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(())
    }
    /// HOST ONLY after authentic confirmation/current policy. Persists an exact
    /// local-only binding in the existing grant owner; never calls AgentOwner.
    /// The human ID here records a host assertion, not a newly created account.
    pub fn issue_group_local_grant_trusted(&self, c: &GroupCommand) -> Result<()> {
        let db = self.database();
        let tx = io(db.transaction())?;
        self.group_check(c)?;
        if c.authority.owner_epoch != self.owner_epoch() {
            return Err(ContractError::InvalidAuthority);
        }
        let previous = io(db.query(
            "SELECT generation FROM business_grants WHERE grant_id=?",
            &[&c.authority.grant_id],
        ))?;
        let generation = if previous.is_empty() {
            Revision::new(1)
        } else {
            Revision::parse(cell(&previous[0], 0)?)?.next()?
        };
        if generation != c.authority.generation {
            return Err(ContractError::InvalidAuthority);
        }
        let binding = digest(c)?;
        let expiry = now()?
            .checked_add(30_000)
            .ok_or(ContractError::InvalidAuthority)?
            .to_string();
        io(db.exec("INSERT INTO business_grants(grant_id,generation,owner_epoch,binding_digest,active,admission_id,expires_at_ms) VALUES(?,?,?,?,1,NULL,?) ON CONFLICT(grant_id) DO UPDATE SET generation=excluded.generation,owner_epoch=excluded.owner_epoch,binding_digest=excluded.binding_digest,active=1,admission_id=NULL,expires_at_ms=excluded.expires_at_ms",&[&c.authority.grant_id,c.authority.generation.as_str(),self.owner_epoch(),&binding,&expiry]))?;
        io(tx.commit())
    }
    /// Durable pending precedes the effect transaction. Existing pending is lookup
    /// only, including after restart; there is no resume/replay callback or transport.
    pub fn execute_group_local(
        &self,
        c: &GroupCommand,
        owner: Option<&AgentOwner>,
    ) -> Result<LocalReceipt> {
        self.group_check(c)?;
        let binding = digest(c)?;
        let db = self.database();
        {
            let tx = io(db.transaction())?;
            let rows=io(db.query("SELECT workspace,project_id,group_id,binding_digest,status,receipt FROM group_runtime_local_intents WHERE intent_id=?",&[&c.intent_id]))?;
            if let Some(row) = rows.first() {
                if cell(row, 0)? != self.workspace_id()
                    || cell(row, 1)? != c.project_id
                    || cell(row, 2)? != c.group_id
                    || cell(row, 3)? != binding
                {
                    return Err(ContractError::IntentConflict);
                }
                return row[5]
                    .as_deref()
                    .map(decode)
                    .unwrap_or_else(|| Ok(pending(c)));
            }
            self.group_authority(c, &binding)?;
            io(db.exec(
                "INSERT INTO group_runtime_local_intents VALUES(?,?,?,?,?,'pending',NULL)",
                &[
                    &c.intent_id,
                    self.workspace_id(),
                    &c.project_id,
                    &c.group_id,
                    &binding,
                ],
            ))?;
            if io(db.exec(
                "INSERT INTO group_runtime_intent_bindings VALUES(?,?)",
                &[&c.intent_id, &encode(c)?],
            ))? != 1
            {
                return Err(ContractError::Storage);
            }
            self.group_verify_pending_tail(c, &binding)?;
            io(tx.commit())?;
        }
        let result = (|| {
            let tx = io(db.transaction())?;
            self.group_check(c)?;
            let original_grant = self.group_authority(c, &binding)?;
            let mut configured_runs = None;
            let mut expected_group = Vec::new();
            let result = self.group_effect(c, owner, &mut configured_runs, &mut expected_group)?;
            if self.group_authority(c, &binding)? != original_grant {
                return Err(ContractError::InvalidAuthority);
            }
            let receipt = LocalReceipt {
                intent_id: c.intent_id.clone(),
                status: LocalStatus::Committed,
                revision: c.expected_revision.next()?,
                result,
            };
            io(db.exec(
                "INSERT INTO group_runtime_events VALUES(?,?,?,?)",
                &[
                    &c.intent_id,
                    &c.group_id,
                    run_id(&c.operation).unwrap_or(""),
                    &encode(&c.operation)?,
                ],
            ))?;
            if io(db.exec("UPDATE group_runtime_local_intents SET status='committed',receipt=? WHERE intent_id=? AND binding_digest=? AND status='pending'",&[&encode(&receipt)?,&c.intent_id,&binding]))?!=1{return Err(ContractError::IntentConflict)}
            self.group_consume_and_verify_tail(
                &tx,
                c,
                &binding,
                &original_grant,
                &receipt,
                &expected_group,
                &configured_runs,
            )?;
            io(tx.commit())?;
            Ok(receipt)
        })();
        match result {
            Ok(r) => Ok(r),
            Err(
                ContractError::Storage
                | ContractError::StorageBusy
                | ContractError::StorageConstraint
                | ContractError::StorageIo
                | ContractError::StorageCorrupt,
            ) => Ok(pending(c)),
            Err(e) => {
                let r = LocalReceipt {
                    intent_id: c.intent_id.clone(),
                    status: LocalStatus::Rejected,
                    revision: c.expected_revision.clone(),
                    result: serde_json::json!({"error":e,"execution_authority":false}),
                };
                let rejected = (|| -> Result<()> {
                    let tx = io(db.transaction())?;
                    if io(db.exec("UPDATE group_runtime_local_intents SET status='rejected',receipt=? WHERE intent_id=? AND workspace=? AND project_id=? AND group_id=? AND binding_digest=? AND status='pending'",&[&encode(&r)?,&c.intent_id,self.workspace_id(),&c.project_id,&c.group_id,&binding]))?!=1 { return Err(ContractError::Storage); }
                    self.group_verify_intent_tail(c, &binding, "rejected", &r)?;
                    io(tx.commit())
                })();
                // A suppressed/changed/failed/uncertain rejection write does not
                // prove a terminal receipt. Drop rolls it back; query original.
                Ok(if rejected.is_ok() { r } else { pending(c) })
            }
        }
    }
    pub fn group_registration(&self, scope: &GroupScope) -> Result<Registration> {
        if scope.workspace != self.workspace_id()
            || scope.owner_epoch != self.owner_epoch()
            || self.project(&scope.project)?.deleted
        {
            return Err(ContractError::ScopeMismatch);
        }
        let rows=io(self.database().query("SELECT record,revision FROM group_runtime_groups WHERE group_id=? AND workspace=? AND project_id=?",&[&scope.group,self.workspace_id(),&scope.project]))?;
        let row = rows.first().ok_or(ContractError::NotFound)?;
        let r: Registration = decode(cell(row, 0)?)?;
        if r.revision.as_str() != cell(row, 1)? {
            return Err(ContractError::StorageCorrupt);
        }
        Ok(r)
    }
    pub fn group_run(&self, scope: &GroupScope, run: &str) -> Result<StoredRun> {
        let registration = self.group_registration(scope)?;
        id(run)?;
        let rows = io(self.database().query(
            "SELECT record FROM group_runtime_runs WHERE run_id=? AND group_id=?",
            &[run, &scope.group],
        ))?;
        let mut run: StoredRun = decode(cell(rows.first().ok_or(ContractError::NotFound)?, 0)?)?;
        if run.coordination_mode.is_none() {
            run.coordination_mode = Some(registration.mode);
        }
        if !matches!(
            run.coordination_mode.as_deref(),
            Some("host_only" | "fixed" | "per_task")
        ) {
            return Err(ContractError::StorageCorrupt);
        }
        Ok(run)
    }
    pub(crate) fn group_nodes(&self, scope: &GroupScope, run: &str) -> Result<Vec<StoredNode>> {
        self.group_run(scope, run)?;
        io(self.database().query(
            "SELECT record FROM group_runtime_nodes WHERE run_id=? ORDER BY node_id",
            &[run],
        ))?
        .iter()
        .map(|r| decode(cell(r, 0)?))
        .collect()
    }
    fn group_node(&self, scope: &GroupScope, run: &str, node: &str) -> Result<StoredNode> {
        self.group_nodes(scope, run)?
            .into_iter()
            .find(|n| n.node_id == node)
            .ok_or(ContractError::NotFound)
    }
    fn group_save_node(&self, run: &str, node: &StoredNode) -> Result<()> {
        let changed = if let Some(request) = &node.request_id {
            io(self.database().exec(
                "UPDATE group_runtime_nodes SET request_id=?,record=? WHERE node_id=? AND run_id=?",
                &[request, &encode(node)?, &node.node_id, run],
            ))?
        } else {
            io(self.database().exec("UPDATE group_runtime_nodes SET request_id=NULL,record=? WHERE node_id=? AND run_id=?", &[&encode(node)?,&node.node_id,run]))?
        };
        if changed != 1 {
            return Err(ContractError::RevisionConflict);
        }
        Ok(())
    }
    fn group_owner(&self, scope: &GroupScope, owner: &AgentOwner) -> Result<Registration> {
        let g = self.group_registration(scope)?;
        if owner.workspace() != self.workspace_id() {
            return Err(ContractError::ScopeMismatch);
        }
        Ok(g)
    }
    pub fn group_lookup_original(
        &self,
        scope: &GroupScope,
        run: &str,
        node: &str,
        owner: &AgentOwner,
    ) -> Result<OriginalRequestView> {
        let g = self.group_owner(scope, owner)?;
        let n = self.group_node(scope, run, node)?;
        let request = n.request_id.ok_or(ContractError::NotFound)?;
        if owner
            .request_conversation(&request)
            .map_err(original_identity_read_error)?
            != g.conversation_id
        {
            return Err(ContractError::ScopeMismatch);
        }
        let chain = owner
            .request_chain(&request)
            .map_err(|_| ContractError::Unknown)?;
        let current = chain.last().cloned().ok_or(ContractError::Unknown)?;
        Ok(OriginalRequestView {
            original_request_id: request,
            chain,
            current,
        })
    }
    pub fn group_next_pending(
        &self,
        scope: &GroupScope,
        run: &str,
        owner: &AgentOwner,
    ) -> Result<PendingAdvice> {
        let g = self.group_owner(scope, owner)?;
        let r = self.group_run(scope, run)?;
        if r.stopped {
            return Ok(PendingAdvice::Stopped);
        }
        if now()? >= r.deadline_ms {
            return Err(ContractError::Cancelled);
        }
        let nodes = self.group_nodes(scope, run)?;
        for n in &nodes {
            if n.request_id.is_some() {
                let o = self.group_lookup_original(scope, run, &n.node_id, owner)?;
                if !terminal(&o.status) {
                    return Ok(PendingAdvice::LookupOriginal {
                        request_id: o.request_id.clone(),
                    });
                }
            }
        }
        owner
            .ensure_conversation_resolved(&g.conversation_id)
            .map_err(|_| ContractError::Unknown)?;
        for n in &nodes {
            if n.state == "pending_host_admission"
                && n.epoch == r.epoch
                && n.dependencies.iter().all(|d| {
                    nodes
                        .iter()
                        .any(|x| &x.node_id == d && x.state == "completed")
                })
            {
                return Ok(PendingAdvice::PendingHostAdmission {
                    node_id: n.node_id.clone(),
                    payload_digest: n.payload_digest.clone(),
                    epoch: r.epoch,
                });
            }
        }
        Ok(PendingAdvice::None)
    }
    fn group_effect(
        &self,
        c: &GroupCommand,
        owner: Option<&AgentOwner>,
        configured_runs: &mut Option<Vec<Vec<Option<String>>>>,
        expected_group: &mut Vec<Vec<Option<String>>>,
    ) -> Result<serde_json::Value> {
        let db = self.database();
        let new_revision = c.expected_revision.next()?;
        if let GroupOperation::Register {
            owner,
            admins,
            conversation_id,
            mode,
            fixed_leader,
            members,
        } = &c.operation
        {
            if c.expected_revision.value() != 0 || c.expected_epoch.is_some() {
                return Err(ContractError::RevisionConflict);
            }
            id(owner)?;
            id(conversation_id)?;
            for a in admins {
                id(a)?;
            }
            if members.is_empty() || members.len() > 32 {
                return Err(ContractError::InvalidPayload);
            }
            for (member, grant) in members {
                id(member)?;
                if grant.scopes != BTreeSet::from([c.project_id.clone()])
                    || grant.permissions.is_empty()
                {
                    return Err(ContractError::ScopeMismatch);
                }
                for p in &grant.permissions {
                    id(p)?;
                }
            }
            if !matches!(mode.as_str(), "host_only" | "fixed" | "per_task")
                || (mode == "fixed"
                    && fixed_leader
                        .as_ref()
                        .is_none_or(|l| !members.contains_key(l)))
                || (mode != "fixed" && fixed_leader.is_some())
            {
                return Err(ContractError::InvalidPayload);
            }
            if !io(db.query(
                "SELECT group_id FROM group_runtime_groups WHERE group_id=?",
                &[&c.group_id],
            ))?
            .is_empty()
            {
                return Err(ContractError::RevisionConflict);
            }
            let r = Registration {
                revision: new_revision.clone(),
                owner: owner.clone(),
                admins: admins.clone(),
                conversation_id: conversation_id.clone(),
                mode: mode.clone(),
                fixed_leader: fixed_leader.clone(),
                members: members.clone(),
            };
            let record = encode(&r)?;
            *expected_group = vec![vec![
                Some(self.workspace_id().into()),
                Some(c.project_id.clone()),
                Some(new_revision.as_str().into()),
                Some(record.clone()),
            ]];
            io(db.exec(
                "INSERT INTO group_runtime_groups VALUES(?,?,?,?,?)",
                &[
                    &c.group_id,
                    self.workspace_id(),
                    &c.project_id,
                    new_revision.as_str(),
                    &record,
                ],
            ))?;
            return Ok(
                serde_json::json!({"group_id":c.group_id,"registered":true,"execution_authority":false}),
            );
        }
        let scope = GroupScope::current(self, &c.project_id, &c.group_id)?;
        let mut group = self.group_registration(&scope)?;
        if group.revision != c.expected_revision {
            return Err(ContractError::RevisionConflict);
        }
        if let GroupOperation::Configure {
            mode,
            fixed_leader,
            members,
        } = &c.operation
        {
            if c.expected_epoch.is_some() {
                return Err(ContractError::InvalidRevision);
            }
            validate_configuration(&c.project_id, mode, fixed_leader, members)?;
            // Legacy runs predate explicit mode capture. Before a default edit,
            // freeze each from the actual persisted old group in this same tx.
            let mut expected = io(db.query(
                "SELECT run_id,group_id,record FROM group_runtime_runs WHERE group_id=? ORDER BY run_id",
                &[&c.group_id],
            ))?;
            for row in &mut expected {
                let mut run: StoredRun = decode(cell(row, 2)?)?;
                if run.coordination_mode.is_none() {
                    run.coordination_mode = Some(group.mode.clone());
                    let record = encode(&run)?;
                    if io(db.exec(
                        "UPDATE group_runtime_runs SET record=? WHERE run_id=? AND group_id=?",
                        &[&record, cell(row, 0)?, &c.group_id],
                    ))? != 1
                    {
                        return Err(ContractError::RevisionConflict);
                    }
                    row[2] = Some(record);
                }
            }
            *configured_runs = Some(expected);
            group.mode = mode.clone();
            group.fixed_leader = fixed_leader.clone();
            group.members = members.clone();
        } else if let GroupOperation::Start {
            run_id,
            root_task_id,
            leader,
            max_rounds,
            max_handoffs,
            deadline_ms,
        } = &c.operation
        {
            id(run_id)?;
            id(root_task_id)?;
            if *max_rounds == 0 || *deadline_ms <= now()? || c.expected_epoch.is_some() {
                return Err(ContractError::InvalidPayload);
            }
            let selected = match group.mode.as_str() {
                "host_only" if leader.is_none() => None,
                "fixed" if leader.is_none() || leader == &group.fixed_leader => {
                    group.fixed_leader.clone()
                }
                "per_task" => Some(
                    leader
                        .as_ref()
                        .filter(|l| group.members.contains_key(*l))
                        .ok_or(ContractError::InvalidPayload)?
                        .clone(),
                ),
                _ => return Err(ContractError::InvalidPayload),
            };
            if !io(db.query(
                "SELECT run_id FROM group_runtime_runs WHERE run_id=?",
                &[run_id],
            ))?
            .is_empty()
            {
                return Err(ContractError::RevisionConflict);
            }
            // The registered root's lifetime cannot be reset by changing run ID.
            // This check shares BEGIN IMMEDIATE with insertion and its receipt.
            for row in io(db.query("SELECT record FROM group_runtime_runs", &[]))? {
                let previous: StoredRun = decode(cell(&row, 0)?)?;
                if previous.root_task_id == *root_task_id {
                    return Err(ContractError::RevisionConflict);
                }
            }
            let r = StoredRun {
                coordination_mode: Some(group.mode.clone()),
                members: group.members.clone(),
                run_id: run_id.clone(),
                root_task_id: root_task_id.clone(),
                leader: selected,
                epoch: 1,
                handoffs: 0,
                max_handoffs: *max_handoffs,
                max_rounds: *max_rounds,
                deadline_ms: *deadline_ms,
                stopped: false,
                summary: serde_json::json!({"nodes":[],"claims":{},"execution_authority":false}),
            };
            io(db.exec(
                "INSERT INTO group_runtime_runs VALUES(?,?,?)",
                &[run_id, &c.group_id, &encode(&r)?],
            ))?;
        } else {
            let rid = run_id(&c.operation).ok_or(ContractError::UnsupportedOperation)?;
            let mut run = self.group_run(&scope, rid)?;
            if c.expected_epoch != Some(run.epoch) {
                return Err(ContractError::RevisionConflict);
            }
            let closed = run.stopped || now()? >= run.deadline_ms;
            match &c.operation {
                GroupOperation::Plan {
                    node_id,
                    member_id,
                    dependencies,
                    capabilities,
                    payload_digest,
                    ..
                } => {
                    if closed {
                        return Err(ContractError::Cancelled);
                    }
                    id(node_id)?;
                    id(member_id)?;
                    let nodes = self.group_nodes(&scope, rid)?;
                    if nodes.len() >= 8 || nodes.len() as u64 >= run.max_rounds {
                        return Err(ContractError::TextLimit);
                    }
                    if payload_digest.len() != 64
                        || !payload_digest
                            .bytes()
                            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
                    {
                        return Err(ContractError::InvalidDigest);
                    }
                    let allowed = run
                        .members
                        .get(member_id)
                        .ok_or(ContractError::InvalidAuthority)?;
                    if capabilities.scopes.is_empty()
                        || capabilities.permissions.is_empty()
                        || !capabilities.scopes.is_subset(&allowed.scopes)
                        || !capabilities.permissions.is_subset(&allowed.permissions)
                    {
                        return Err(ContractError::InvalidAuthority);
                    }
                    if dependencies.contains(node_id)
                        || dependencies
                            .iter()
                            .any(|d| !nodes.iter().any(|n| &n.node_id == d))
                    {
                        return Err(ContractError::InvalidPayload);
                    }
                    let n = StoredNode {
                        node_id: node_id.clone(),
                        member_id: member_id.clone(),
                        dependencies: dependencies.clone(),
                        capabilities: capabilities.clone(),
                        payload_digest: payload_digest.clone(),
                        epoch: run.epoch,
                        state: "pending_host_admission".into(),
                        request_id: None,
                        evidence: vec![],
                    };
                    io(db.exec("INSERT INTO group_runtime_nodes(node_id,run_id,request_id,record) VALUES(?,?,NULL,?)",&[node_id,rid,&encode(&n)?]))?;
                }
                GroupOperation::BindOriginal {
                    node_id,
                    request_id,
                    ..
                } => {
                    // This only registers an already-existing original request
                    // for reconciliation, even after stop/deadline/handoff. It
                    // never creates/resends/claims/cancels the provider request.
                    let owner = owner.ok_or(ContractError::InvalidAuthority)?;
                    let g = self.group_owner(&scope, owner)?;
                    let mut n = self.group_node(&scope, rid, node_id)?;
                    if n.request_id.is_some() {
                        return Err(ContractError::RevisionConflict);
                    }
                    if owner
                        .request_conversation(request_id)
                        .map_err(original_identity_read_error)?
                        != g.conversation_id
                    {
                        return Err(ContractError::ScopeMismatch);
                    }
                    let chain = owner
                        .request_chain(request_id)
                        .map_err(|_| ContractError::Storage)?;
                    let receipt = chain.last().ok_or(ContractError::Storage)?;
                    n.request_id = Some(request_id.clone());
                    n.state = if terminal(&receipt.status) {
                        receipt.status.clone()
                    } else {
                        "unknown".into()
                    };
                    self.group_save_node(rid, &n)?;
                }
                GroupOperation::Observe {
                    node_id, evidence, ..
                } => {
                    let owner = owner.ok_or(ContractError::InvalidAuthority)?;
                    let receipt = self
                        .group_lookup_original(&scope, rid, node_id, owner)
                        .map_err(inconclusive_original_read)?;
                    let mut n = self.group_node(&scope, rid, node_id)?;
                    // Late original receipts may update historical evidence,
                    // never current-epoch advice or authority.
                    if receipt.status == "completed"
                        && receipt.answer.as_ref().is_none_or(|v| v.is_null())
                    {
                        return Err(ContractError::InvalidPayload);
                    }
                    n.state = if terminal(&receipt.status) {
                        receipt.status.clone()
                    } else {
                        "unknown".into()
                    };
                    for e in evidence {
                        id(&e.claim_id)?;
                        id(&e.source_id)?;
                        if !matches!(e.stance.as_str(), "supports" | "contradicts" | "unknown") {
                            return Err(ContractError::InvalidPayload);
                        }
                        let source = io(db.query(
                            "SELECT revision FROM research_entries WHERE id=? AND project_id=?",
                            &[&e.source_id, &c.project_id],
                        ))?;
                        if source.len() != 1 || cell(&source[0], 0)? != e.source_revision.as_str() {
                            return Err(ContractError::ScopeMismatch);
                        }
                        if !n.evidence.contains(e) {
                            n.evidence.push(e.clone());
                        }
                    }
                    self.group_save_node(rid, &n)?;
                }
                GroupOperation::Handoff { to, .. } => {
                    if closed {
                        return Err(ContractError::Cancelled);
                    }
                    if run.coordination_mode.as_deref() != Some("per_task")
                        || run.leader.as_deref() == Some(to)
                        || run.handoffs >= run.max_handoffs
                    {
                        return Err(ContractError::InvalidPayload);
                    }
                    let owner = owner.ok_or(ContractError::InvalidAuthority)?;
                    self.group_owner(&scope, owner)?;
                    owner
                        .ensure_conversation_resolved(&group.conversation_id)
                        .map_err(|error| {
                            if error == "conversation_original_outcome_required" {
                                // Actual owner positively proves an unresolved original:
                                // this local handoff is definitely refused.
                                ContractError::Unknown
                            } else {
                                ContractError::Storage
                            }
                        })?;
                    let mut nodes = self.group_nodes(&scope, rid)?;
                    for n in &mut nodes {
                        if n.request_id.is_some() {
                            let original = self
                                .group_lookup_original(&scope, rid, &n.node_id, owner)
                                .map_err(inconclusive_original_read)?;
                            if !terminal(&original.status) {
                                return Err(ContractError::Unknown);
                            }
                            // Original owner status, not a stale UI observation,
                            // releases local advisory slots at the checkpoint.
                            n.state = original.status.clone();
                            self.group_save_node(rid, n)?;
                        }
                    }
                    let old = run
                        .members
                        .get(run.leader.as_deref().ok_or(ContractError::InvalidPayload)?)
                        .ok_or(ContractError::InvalidAuthority)?
                        .clone();
                    let next = run
                        .members
                        .get_mut(to)
                        .ok_or(ContractError::InvalidAuthority)?;
                    next.scopes = next.scopes.intersection(&old.scopes).cloned().collect();
                    next.permissions = next
                        .permissions
                        .intersection(&old.permissions)
                        .cloned()
                        .collect();
                    if next.scopes.is_empty() || next.permissions.is_empty() {
                        return Err(ContractError::InvalidAuthority);
                    }
                    run.epoch = run
                        .epoch
                        .checked_add(1)
                        .ok_or(ContractError::InvalidRevision)?;
                    run.handoffs = run
                        .handoffs
                        .checked_add(1)
                        .ok_or(ContractError::InvalidRevision)?;
                    run.leader = Some(to.clone());
                    for mut n in nodes {
                        if n.request_id.is_none() {
                            n.state = "obsolete_epoch".into();
                            self.group_save_node(rid, &n)?;
                        }
                    }
                }
                GroupOperation::Stop { .. } => {
                    run.stopped = true;
                    for mut n in self.group_nodes(&scope, rid)? {
                        if n.request_id.is_none() {
                            n.state = "stopped_unbound".into();
                            self.group_save_node(rid, &n)?;
                        }
                    }
                }
                _ => return Err(ContractError::UnsupportedOperation),
            }
            run.summary = self.group_summary(&scope, rid, run.epoch)?;
            io(db.exec(
                "UPDATE group_runtime_runs SET record=? WHERE run_id=? AND group_id=?",
                &[&encode(&run)?, rid, &c.group_id],
            ))?;
        }
        group.revision = new_revision.clone();
        // Capture intended bytes before any trigger-capable group write. A
        // post-write database snapshot could already contain a reverted config.
        let record = encode(&group)?;
        *expected_group = vec![vec![
            Some(self.workspace_id().into()),
            Some(c.project_id.clone()),
            Some(new_revision.as_str().into()),
            Some(record.clone()),
        ]];
        if io(db.exec("UPDATE group_runtime_groups SET revision=?,record=? WHERE group_id=? AND workspace=? AND project_id=? AND revision=?",&[new_revision.as_str(),&record,&c.group_id,self.workspace_id(),&c.project_id,c.expected_revision.as_str()]))?!=1{return Err(ContractError::RevisionConflict)}
        Ok(
            serde_json::json!({"group_id":c.group_id,"run_id":run_id(&c.operation),"execution_authority":false}),
        )
    }
    fn group_summary(
        &self,
        scope: &GroupScope,
        run: &str,
        epoch: u64,
    ) -> Result<serde_json::Value> {
        let nodes = self.group_nodes(scope, run)?;
        let mut claims: BTreeMap<String, serde_json::Value> = BTreeMap::new();
        for n in nodes.iter().filter(|n| n.epoch == epoch) {
            for e in &n.evidence {
                let c=claims.entry(e.claim_id.clone()).or_insert_with(||serde_json::json!({"supports":[],"contradicts":[],"unknown":[],"disputed":false}));
                let item = serde_json::json!({"source_id":e.source_id,"source_revision":e.source_revision,"member_id":n.member_id,"node_id":n.node_id,"original_request_id":n.request_id});
                let a = c[&e.stance]
                    .as_array_mut()
                    .ok_or(ContractError::StorageCorrupt)?;
                if !a.contains(&item) {
                    a.push(item)
                }
                c["disputed"] = serde_json::json!(
                    !c["supports"].as_array().unwrap().is_empty()
                        && !c["contradicts"].as_array().unwrap().is_empty()
                );
            }
        }
        Ok(
            serde_json::json!({"nodes":nodes,"claims":claims,"execution_authority":false,"majority_is_truth":false}),
        )
    }
}
fn run_id(op: &GroupOperation) -> Option<&str> {
    match op {
        GroupOperation::Register { .. } | GroupOperation::Configure { .. } => None,
        GroupOperation::Start { run_id, .. }
        | GroupOperation::Plan { run_id, .. }
        | GroupOperation::BindOriginal { run_id, .. }
        | GroupOperation::Observe { run_id, .. }
        | GroupOperation::Handoff { run_id, .. }
        | GroupOperation::Stop { run_id } => Some(run_id),
    }
}
fn terminal(s: &str) -> bool {
    matches!(s, "completed" | "failed" | "cancelled")
}

// A failed original-owner read is inconclusive; unlike a positively observed
// unresolved original it must not fabricate a definitive local rejection.
fn inconclusive_original_read(error: ContractError) -> ContractError {
    if error == ContractError::Unknown {
        ContractError::Storage
    } else {
        error
    }
}

fn original_identity_read_error(error: &'static str) -> ContractError {
    match error {
        "agent_request_not_found" => ContractError::NotFound,
        "agent_identity_invalid" => ContractError::InvalidIdentity,
        _ => ContractError::Storage,
    }
}

pub(crate) fn validate_configuration(
    project: &str,
    mode: &str,
    fixed_leader: &Option<String>,
    members: &BTreeMap<String, Capabilities>,
) -> Result<()> {
    if members.is_empty()
        || members.len() > 32
        || !matches!(mode, "host_only" | "fixed" | "per_task")
    {
        return Err(ContractError::InvalidPayload);
    }
    for (member, grant) in members {
        id(member)?;
        if grant.scopes != BTreeSet::from([project.to_string()]) || grant.permissions.is_empty() {
            return Err(ContractError::ScopeMismatch);
        }
        for permission in &grant.permissions {
            id(permission)?;
        }
    }
    if (mode == "fixed"
        && fixed_leader
            .as_ref()
            .is_none_or(|l| !members.contains_key(l)))
        || (mode != "fixed" && fixed_leader.is_some())
    {
        return Err(ContractError::InvalidPayload);
    }
    Ok(())
}
