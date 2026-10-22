//! Narrow persisted project permissions; a document grant is never accepted here.
//! Trusted issuer must derive actor/membership permissions from real host policy.
use super::*;
use crate::contract::AuthorityBinding;
use std::time::{SystemTime, UNIX_EPOCH};

pub(super) const WORKFLOW_SCHEMA: &[(&str, &str)] = &[
    ("artifact_workflow_meta_v1", "CREATE TABLE artifact_workflow_meta_v1(key TEXT PRIMARY KEY,value TEXT NOT NULL)"),
    ("artifact_project_grants_v1", "CREATE TABLE artifact_project_grants_v1(grant_id TEXT PRIMARY KEY,generation TEXT NOT NULL,owner_epoch TEXT NOT NULL,project_id TEXT NOT NULL REFERENCES projects(id),project_revision TEXT NOT NULL,actor_id TEXT NOT NULL,permissions TEXT NOT NULL,expires_at_ms TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN(0,1)))"),
    ("artifact_save_intents_v1", "CREATE TABLE artifact_save_intents_v1(intent_id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),actor_id TEXT NOT NULL,binding_digest TEXT NOT NULL,request_json TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN('pending','committed','rejected')),receipt_json TEXT,error TEXT)"),
];
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactProjectOperation {
    Discover,
    Save,
    LookupOwnSaves,
    LocalDraft,
    LocalSubmit,
    LocalFeedback,
    ReadOwnLocal,
}
/// Not deserializable. The host resolves authenticated actor/project identity.
/// This is a request binding; only the persisted live grant supplies permission.
#[derive(Clone, Debug)]
pub struct ArtifactProjectAccess {
    pub scope: Scope,
    pub actor_id: String,
    pub project_revision: Revision,
    pub authority: AuthorityBinding,
}
impl ArtifactProjectAccess {
    pub(super) fn project_id(&self) -> Result<&str> {
        self.scope
            .project_id
            .as_deref()
            .ok_or(ContractError::ScopeMismatch)
    }
    fn validate(&self) -> Result<()> {
        identifier(&self.scope.workspace_id)?;
        identifier(self.project_id()?)?;
        identifier(&self.actor_id)?;
        identifier(&self.authority.grant_id)?;
        identifier(&self.authority.owner_epoch)?;
        if self.project_revision.value() == 0 || self.authority.generation.value() == 0 {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(())
    }
}
fn now_ms() -> Result<u64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| ContractError::InvalidAuthority)?
        .as_millis()
        .try_into()
        .map_err(|_| ContractError::InvalidAuthority)
}
impl BusinessStore {
    /// Explicit additive workflow namespace. Existing artifact/document schemas
    /// stay unchanged. Partial/unknown workflow schemas are rejected, not migrated.
    pub fn initialize_artifact_workflows_trusted(&self) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        self.artifact_schema()?;
        let mut present = 0;
        for (name, _) in WORKFLOW_SCHEMA {
            present += sql(self.database().query(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                &[name],
            ))?
            .len();
        }
        if present == 0 {
            for (_, ddl) in WORKFLOW_SCHEMA {
                sql(self.database().exec(ddl, &[]))?;
            }
            sql(self.database().exec(
                "INSERT INTO artifact_workflow_meta_v1 VALUES('version','1')",
                &[],
            ))?;
            sql(self.database().exec(
                "INSERT INTO artifact_workflow_meta_v1 VALUES('workspace',?)",
                &[self.workspace_id()],
            ))?;
        } else if present != WORKFLOW_SCHEMA.len() {
            return Err(ContractError::InvalidVersion);
        }
        self.artifact_workflow_schema()?;
        sql(tx.commit())
    }
    pub(super) fn artifact_workflow_schema(&self) -> Result<()> {
        self.artifact_schema()?;
        for (name, ddl) in WORKFLOW_SCHEMA {
            let rows = sql(self.database().query(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                &[name],
            ))?;
            if rows.len() != 1 || cell(&rows[0], 0)? != *ddl {
                return Err(ContractError::InvalidVersion);
            }
        }
        let rows = sql(self.database().query(
            "SELECT key,value FROM artifact_workflow_meta_v1 ORDER BY key",
            &[],
        ))?;
        if rows
            != vec![
                vec![Some("version".into()), Some("1".into())],
                vec![Some("workspace".into()), Some(self.workspace_id().into())],
            ]
        {
            return Err(ContractError::InvalidVersion);
        }
        Ok(())
    }
    fn artifact_project_live(&self, access: &ArtifactProjectAccess) -> Result<()> {
        access.validate()?;
        if access.scope.workspace_id != self.workspace_id() {
            return Err(ContractError::ScopeMismatch);
        }
        if access.authority.owner_epoch != self.owner_epoch() {
            return Err(ContractError::InvalidAuthority);
        }
        let project = self.project(access.project_id()?)?;
        if project.deleted {
            return Err(ContractError::NotFound);
        }
        if project.revision != access.project_revision {
            return Err(ContractError::RevisionConflict);
        }
        Ok(())
    }
    /// HOST ONLY after authentic current actor/project-membership authorization.
    /// Never call from a model-supplied role/permission list. Discover authorizes
    /// inventory metadata only, not document/source contents or other save logs.
    pub fn issue_artifact_project_grant_trusted(
        &self,
        access: &ArtifactProjectAccess,
        operations: &[ArtifactProjectOperation],
        expires_at_ms: u64,
    ) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        self.artifact_workflow_schema()?;
        self.artifact_project_live(access)?;
        let now = now_ms()?;
        if operations.is_empty()
            || operations.len() > 7
            || expires_at_ms <= now
            || expires_at_ms
                > now
                    .checked_add(30_000)
                    .ok_or(ContractError::InvalidAuthority)?
        {
            return Err(ContractError::InvalidAuthority);
        }
        let mut distinct = Vec::new();
        for operation in operations {
            if distinct.contains(operation) {
                return Err(ContractError::InvalidPayload);
            }
            distinct.push(*operation);
        }
        let old = sql(self.database().query("SELECT CASE WHEN length(CAST(generation AS BLOB))<=20 THEN generation ELSE NULL END FROM artifact_project_grants_v1 WHERE grant_id=?", &[&access.authority.grant_id]))?;
        let expected = if old.is_empty() {
            Revision::new(1)
        } else {
            Revision::parse(cell(&old[0], 0)?)?.next()?
        };
        if access.authority.generation != expected {
            return Err(ContractError::InvalidAuthority);
        }
        sql(self.database().exec("INSERT INTO artifact_project_grants_v1 VALUES(?,?,?,?,?,?,?,?,1) ON CONFLICT(grant_id) DO UPDATE SET generation=excluded.generation,owner_epoch=excluded.owner_epoch,project_id=excluded.project_id,project_revision=excluded.project_revision,actor_id=excluded.actor_id,permissions=excluded.permissions,expires_at_ms=excluded.expires_at_ms,active=1", &[&access.authority.grant_id, access.authority.generation.as_str(), self.owner_epoch(), access.project_id()?, access.project_revision.as_str(), &access.actor_id, &encode(&operations)?, &expires_at_ms.to_string()]))?;
        sql(tx.commit())
    }
    pub fn revoke_artifact_project_grant_trusted(
        &self,
        access: &ArtifactProjectAccess,
    ) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        self.artifact_workflow_schema()?;
        self.artifact_project_live(access)?;
        let changed = sql(self.database().exec("UPDATE artifact_project_grants_v1 SET active=0 WHERE grant_id=? AND generation=? AND owner_epoch=? AND project_id=? AND actor_id=?", &[&access.authority.grant_id, access.authority.generation.as_str(), self.owner_epoch(), access.project_id()?, &access.actor_id]))?;
        if changed != 1 {
            return Err(ContractError::InvalidAuthority);
        }
        sql(tx.commit())
    }
    pub(super) fn artifact_project_authorize(
        &self,
        tx: &Transaction<'_>,
        access: &ArtifactProjectAccess,
        operation: ArtifactProjectOperation,
    ) -> Result<()> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::InvalidAuthority);
        }
        self.artifact_workflow_schema()?;
        self.artifact_project_live(access)?;
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(permissions AS BLOB))<=256 THEN permissions ELSE NULL END,CASE WHEN length(CAST(expires_at_ms AS BLOB))<=20 THEN expires_at_ms ELSE NULL END FROM artifact_project_grants_v1 WHERE grant_id=? AND generation=? AND owner_epoch=? AND project_id=? AND project_revision=? AND actor_id=? AND active=1", &[&access.authority.grant_id, access.authority.generation.as_str(), self.owner_epoch(), access.project_id()?, access.project_revision.as_str(), &access.actor_id]))?;
        if rows.len() != 1 {
            return Err(ContractError::InvalidAuthority);
        }
        let permissions: Vec<ArtifactProjectOperation> = decode(cell(&rows[0], 0)?)?;
        let expires: u64 = cell(&rows[0], 1)?
            .parse()
            .map_err(|_| ContractError::StorageCorrupt)?;
        if permissions.len() > 7 || !permissions.contains(&operation) || expires <= now_ms()? {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(())
    }
}
