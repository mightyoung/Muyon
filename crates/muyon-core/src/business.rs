//! Durable Android business writes. Only the trusted Service host owns this store.
//! The wire grant is a reference; persisted business_grants is the authority source.
use crate::{
    contract::*,
    sqlite::{Db, Transaction},
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::os::fd::AsRawFd;
use std::time::{SystemTime, UNIX_EPOCH};
use std::{
    fs::{File, OpenOptions},
    path::{Path, PathBuf},
};

pub const STORE_VERSION: &str = "2";
/// Exact initial DDL is the required schema identity. No inferred migration.
const REQUIRED_SCHEMA: &[&str] = &[
    "CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)",
    "CREATE TABLE business_grants(grant_id TEXT PRIMARY KEY,generation TEXT NOT NULL,owner_epoch TEXT NOT NULL,binding_digest TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN(0,1)),admission_id TEXT,expires_at_ms TEXT NOT NULL)",
    "CREATE TABLE intents(intent_id TEXT PRIMARY KEY,binding_digest TEXT NOT NULL,command_json TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN('pending','unknown','committed','rejected','cancelled')),receipt_json TEXT,error TEXT,owner_epoch TEXT NOT NULL)",
    "CREATE TABLE supplier(id TEXT PRIMARY KEY,workspace TEXT NOT NULL,payload TEXT NOT NULL,revision TEXT NOT NULL,deleted INTEGER NOT NULL CHECK(deleted IN(0,1)))",
    "CREATE TABLE supplier_history(intent_id TEXT PRIMARY KEY,target_id TEXT NOT NULL,old_revision TEXT NOT NULL,new_revision TEXT NOT NULL,old_payload TEXT,new_payload TEXT NOT NULL,operation TEXT NOT NULL)",
    "CREATE TABLE business_history(intent_id TEXT PRIMARY KEY,target_id TEXT NOT NULL,old_revision TEXT NOT NULL,new_revision TEXT NOT NULL,binding_digest TEXT NOT NULL,result TEXT NOT NULL)",
    "CREATE TABLE supplier_references(reference_id TEXT PRIMARY KEY,supplier_id TEXT NOT NULL REFERENCES supplier(id))",
    "CREATE TABLE projects(id TEXT PRIMARY KEY,workspace TEXT NOT NULL,name TEXT NOT NULL,revision TEXT NOT NULL,deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN(0,1)))",
    "CREATE TABLE blob_uploads(upload_id TEXT PRIMARY KEY,snapshot_id TEXT NOT NULL UNIQUE,workspace TEXT NOT NULL,project_id TEXT NOT NULL,project_revision TEXT NOT NULL,owner_epoch TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN('copying','pinned','committed','aborted','unknown')),byte_length TEXT NOT NULL,digest TEXT,kind TEXT)",
    "CREATE TABLE blobs(digest TEXT PRIMARY KEY,byte_length TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN('ready','deleting')))",
    "CREATE TABLE blob_pins(pin_id TEXT PRIMARY KEY,digest TEXT NOT NULL REFERENCES blobs(digest),kind TEXT NOT NULL CHECK(kind IN('upload','reader')),upload_id TEXT,snapshot_id TEXT NOT NULL,owner_epoch TEXT NOT NULL)",
    "CREATE TABLE blob_references(reference_id TEXT PRIMARY KEY,project_id TEXT NOT NULL,target_id TEXT NOT NULL,digest TEXT NOT NULL REFERENCES blobs(digest))",
    "CREATE TABLE research_snapshots(upload_id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),project_revision TEXT NOT NULL,owner_epoch TEXT NOT NULL,digest TEXT NOT NULL,byte_length TEXT NOT NULL,records_digest TEXT NOT NULL)",
    "CREATE TABLE research_sources(source_id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),revision TEXT NOT NULL,external_revision TEXT NOT NULL,snapshot_digest TEXT NOT NULL,snapshot_upload_id TEXT NOT NULL,records_digest TEXT NOT NULL,layout TEXT NOT NULL,skill_root TEXT NOT NULL)",
    "CREATE TABLE research_entries(id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),source_id TEXT,entry_key TEXT NOT NULL,kind TEXT NOT NULL,title TEXT NOT NULL,raw_json TEXT NOT NULL,content_digest TEXT NOT NULL,source_record_id TEXT,source_revision TEXT,revision TEXT NOT NULL,manual INTEGER NOT NULL CHECK(manual IN(0,1)))",
    "CREATE TABLE research_documents(id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),source_id TEXT,relative_path TEXT NOT NULL,digest TEXT NOT NULL,byte_length TEXT NOT NULL,retained INTEGER NOT NULL DEFAULT 0 CHECK(retained IN(0,1)))",
    "CREATE TABLE research_bindings(document_id TEXT NOT NULL REFERENCES research_documents(id),paper_id TEXT NOT NULL REFERENCES research_entries(id),paper_revision TEXT NOT NULL,method TEXT NOT NULL,hash_ok INTEGER NOT NULL CHECK(hash_ok IN(0,1)),ambiguous INTEGER NOT NULL CHECK(ambiguous IN(0,1)),manual INTEGER NOT NULL DEFAULT 0 CHECK(manual IN(0,1)),PRIMARY KEY(document_id,paper_id))",
    "CREATE TABLE research_citations(citation_id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),entry_id TEXT REFERENCES research_entries(id),document_id TEXT REFERENCES research_documents(id),CHECK(entry_id IS NOT NULL OR document_id IS NOT NULL))",
    "CREATE TABLE research_import_members(intent_id TEXT NOT NULL,entry_id TEXT NOT NULL,raw_digest TEXT NOT NULL,content_digest TEXT NOT NULL,source_revision TEXT NOT NULL,title TEXT NOT NULL,PRIMARY KEY(intent_id,entry_id))",
];
unsafe extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
}
struct OwnerLock(File);
impl OwnerLock {
    fn acquire(path: &Path) -> Result<Self, ContractError> {
        let mut lock_name = path.as_os_str().to_os_string();
        lock_name.push(".owner.lock");
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(PathBuf::from(lock_name))
            .map_err(|_| ContractError::Storage)?;
        // LOCK_EX | LOCK_NB; file ownership remains held for the connection lifetime.
        if unsafe { flock(file.as_raw_fd(), 2 | 4) } != 0 {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(Self(file))
    }
}
impl Drop for OwnerLock {
    fn drop(&mut self) {
        unsafe {
            flock(self.0.as_raw_fd(), 8);
        }
    }
}

pub struct BusinessStore {
    db: Db,
    workspace: String,
    owner_epoch: String,
    blob_root: PathBuf,
    _owner: OwnerLock,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SupplierRecord {
    pub id: String,
    pub payload: SupplierPayload,
    pub revision: Revision,
    pub deleted: bool,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectRecord {
    pub id: String,
    pub name: String,
    pub revision: Revision,
    pub deleted: bool,
}
fn identity(value: &str) -> Result<(), ContractError> {
    if value.is_empty()
        || value.len() > 128
        || !value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
    {
        Err(ContractError::InvalidIdentity)
    } else {
        Ok(())
    }
}
fn storage<T>(result: crate::sqlite::Result<T>) -> Result<T, ContractError> {
    result.map_err(|error| {
        let code = error
            .strip_prefix("SQLite ")
            .and_then(|rest| rest.split(':').next())
            .and_then(|code| code.parse::<i32>().ok())
            .map(|code| code & 0xff);
        match code {
            Some(5 | 6) => ContractError::StorageBusy,
            Some(19) => ContractError::StorageConstraint,
            Some(11 | 26) => ContractError::StorageCorrupt,
            Some(10 | 13 | 14) => ContractError::StorageIo,
            _ => ContractError::Storage,
        }
    })
}
fn clock_ms() -> Result<u64, ContractError> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| ContractError::InvalidAuthority)?
        .as_millis()
        .try_into()
        .map_err(|_| ContractError::InvalidAuthority)
}
fn storage_failure(error: &ContractError) -> bool {
    matches!(
        error,
        ContractError::Storage
            | ContractError::StorageBusy
            | ContractError::StorageConstraint
            | ContractError::StorageCorrupt
            | ContractError::StorageIo
    )
}
fn cell(row: &[Option<String>], index: usize) -> Result<&str, ContractError> {
    row.get(index)
        .and_then(Option::as_deref)
        .ok_or(ContractError::Storage)
}
fn path_text(path: &Path) -> Result<&str, ContractError> {
    path.to_str().ok_or(ContractError::InvalidIdentity)
}
fn json_text<T: Serialize>(value: &T) -> Result<String, ContractError> {
    serde_json::to_string(value).map_err(|_| ContractError::InvalidPayload)
}
fn unknown() -> ExecutionResult {
    ExecutionResult {
        status: ExecutionStatus::Unknown,
        receipt: None,
        error: Some(ContractError::Unknown),
        recovery_action: RecoveryAction::QueryOriginal,
    }
}

impl BusinessStore {
    /// Explicit new namespace only. Existing, partial and legacy files are never replaced.
    pub fn initialize(path: &Path, workspace: &str) -> Result<(), ContractError> {
        identity(workspace)?;
        let _owner = OwnerLock::acquire(path)?;
        let _reserved = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .map_err(|_| ContractError::Storage)?;
        let db = storage(Db::open(path_text(path)?, false, false))?;
        storage(db.query("PRAGMA journal_mode=WAL", &[]))?;
        storage(db.exec("PRAGMA synchronous=FULL", &[]))?;
        let tx = storage(db.transaction())?;
        for statement in REQUIRED_SCHEMA {
            storage(db.exec(statement, &[]))?;
        }
        storage(db.exec(
            "INSERT INTO meta VALUES('schema_version',?)",
            &[STORE_VERSION],
        ))?;
        storage(db.exec("INSERT INTO meta VALUES('workspace',?)", &[workspace]))?;
        storage(tx.commit())
    }

    /// Opens an already initialized store, with no schema creation or migration.
    pub fn open_existing(
        path: &Path,
        workspace: &str,
        owner_epoch: &str,
    ) -> Result<Self, ContractError> {
        identity(workspace)?;
        identity(owner_epoch)?;
        let owner = OwnerLock::acquire(path)?;
        let db = storage(Db::open(path_text(path)?, false, false))?;
        storage(db.exec("PRAGMA foreign_keys=ON", &[]))?;
        storage(db.exec("PRAGMA synchronous=FULL", &[]))?;
        let meta = storage(db.query("SELECT key,value FROM meta ORDER BY key", &[]))?;
        if meta.len() != 2
            || cell(&meta[0], 0)? != "schema_version"
            || cell(&meta[0], 1)? != STORE_VERSION
        {
            return Err(ContractError::InvalidVersion);
        }
        if cell(&meta[1], 0)? != "workspace" || cell(&meta[1], 1)? != workspace {
            return Err(ContractError::ScopeMismatch);
        }
        for expected in REQUIRED_SCHEMA {
            let name = expected
                .strip_prefix("CREATE TABLE ")
                .and_then(|sql| sql.split_once('('))
                .map(|parts| parts.0)
                .ok_or(ContractError::InvalidVersion)?;
            let actual = storage(db.query(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                &[name],
            ))?;
            if actual.len() != 1 || cell(&actual[0], 0)? != *expected {
                return Err(ContractError::InvalidVersion);
            }
        }
        let mut blob_root = path.as_os_str().to_os_string();
        blob_root.push(".blobs");
        Ok(Self {
            db,
            workspace: workspace.into(),
            owner_epoch: owner_epoch.into(),
            blob_root: PathBuf::from(blob_root),
            _owner: owner,
        })
    }

    pub(crate) fn database(&self) -> &Db {
        &self.db
    }
    pub(crate) fn workspace_id(&self) -> &str {
        &self.workspace
    }
    pub(crate) fn owner_epoch(&self) -> &str {
        &self.owner_epoch
    }
    /// The blob owner creates this namespace only at an explicit begin-upload.
    pub(crate) fn root_dir(&self) -> &Path {
        &self.blob_root
    }

    fn check_command(&self, command: &CommandEnvelope) -> Result<String, ContractError> {
        let digest = command.binding_digest()?;
        if command.scope.workspace_id != self.workspace {
            return Err(ContractError::ScopeMismatch);
        }
        if command.authority.owner_epoch != self.owner_epoch {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(digest)
    }

    /// HOST ONLY: call after authentic user confirmation/current policy authorization.
    /// Never expose this through an untrusted model/JSON command dispatcher.
    /// Reissuing a grant requires exactly the next persisted generation.
    pub fn issue_grant_trusted(
        &self,
        command: &CommandEnvelope,
        admission_id: Option<&str>,
    ) -> Result<(), ContractError> {
        let binding = self.check_command(command)?;
        if let Some(id) = admission_id {
            identity(id)?;
        }
        let tx = storage(self.db.transaction())?;
        let previous = storage(self.db.query(
            "SELECT generation FROM business_grants WHERE grant_id=?",
            &[&command.authority.grant_id],
        ))?;
        let expected = if previous.is_empty() {
            Revision::new(1)
        } else {
            Revision::parse(cell(&previous[0], 0)?)?.next()?
        };
        if command.authority.generation != expected {
            return Err(ContractError::InvalidAuthority);
        }
        let expires_at_ms = clock_ms()?
            .checked_add(30_000)
            .ok_or(ContractError::InvalidAuthority)?
            .to_string();
        storage(self.db.exec("INSERT INTO business_grants(grant_id,generation,owner_epoch,binding_digest,active,admission_id,expires_at_ms) VALUES(?,?,?,?,1,NULL,?) ON CONFLICT(grant_id) DO UPDATE SET generation=excluded.generation,owner_epoch=excluded.owner_epoch,binding_digest=excluded.binding_digest,active=1,admission_id=NULL,expires_at_ms=excluded.expires_at_ms", &[&command.authority.grant_id, command.authority.generation.as_str(), &self.owner_epoch, &binding,&expires_at_ms]))?;
        if let Some(admission) = admission_id {
            storage(self.db.exec(
                "UPDATE business_grants SET admission_id=? WHERE grant_id=?",
                &[admission, &command.authority.grant_id],
            ))?;
        }
        storage(tx.commit())
    }

    /// HOST ONLY: revocation linearizes at this same business-database COMMIT.
    pub fn revoke_grant_trusted(
        &self,
        grant_id: &str,
        generation: &Revision,
    ) -> Result<(), ContractError> {
        let tx = storage(self.db.transaction())?;
        let changed = storage(self.db.exec("UPDATE business_grants SET active=0 WHERE grant_id=? AND generation=? AND owner_epoch=?", &[grant_id,generation.as_str(),&self.owner_epoch]))?;
        if changed != 1 {
            return Err(ContractError::InvalidAuthority);
        }
        storage(tx.commit())
    }

    fn authority(
        &self,
        command: &CommandEnvelope,
        binding: &str,
    ) -> Result<Option<String>, ContractError> {
        let rows = storage(self.db.query("SELECT admission_id,expires_at_ms FROM business_grants WHERE grant_id=? AND generation=? AND owner_epoch=? AND binding_digest=? AND active=1", &[&command.authority.grant_id,command.authority.generation.as_str(),&self.owner_epoch,binding]))?;
        if rows.len() != 1 {
            return Err(ContractError::InvalidAuthority);
        }
        let expiry = Revision::parse(cell(&rows[0], 1)?)?.value();
        if clock_ms()? >= expiry {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(rows[0][0].clone())
    }

    /// Public write dispatcher has only implemented operations. Unsupported work
    /// never fabricates a business receipt or invokes the extension closure.
    pub fn execute(&self, command: &CommandEnvelope) -> Result<ExecutionResult, ContractError> {
        if matches!(
            command.command,
            Operation::PaperCreate { .. } | Operation::ResearchImport { .. }
        ) {
            return self.execute_research(command);
        }
        if !matches!(
            command.command,
            Operation::SupplierCreate { .. }
                | Operation::SupplierUpdate { .. }
                | Operation::SupplierDelete { .. }
                | Operation::SupplierRestore { .. }
                | Operation::ProjectCreate { .. }
        ) {
            return Err(ContractError::UnsupportedOperation);
        }
        self.execute_with(command, |db, _transaction, command| self.apply(db, command))
    }

    pub(crate) fn existing_execution(
        &self,
        command: &CommandEnvelope,
    ) -> Result<Option<ExecutionResult>, ContractError> {
        let binding = self.check_command(command)?;
        let rows=storage(self.db.query("SELECT binding_digest,status,receipt_json,error,command_json FROM intents WHERE intent_id=?",&[&command.intent_id]))?;
        if let Some(row) = rows.first() {
            if cell(row, 0)? != binding {
                return Err(ContractError::IntentConflict);
            }
            Ok(Some(self.project_intent(row, &command.intent_id)?))
        } else {
            Ok(None)
        }
    }

    /// Trusted Rust extension seam, never callable from arbitrary wire/FFI code.
    /// Caller performs only business effects using this transaction's connection.
    pub(crate) fn execute_with<F>(
        &self,
        command: &CommandEnvelope,
        effect: F,
    ) -> Result<ExecutionResult, ContractError>
    where
        F: FnOnce(&Db, &Transaction<'_>, &CommandEnvelope) -> Result<Value, ContractError>,
    {
        let binding = self.check_command(command)?;
        {
            let pending_tx = storage(self.db.transaction())?;
            let existing = storage(self.db.query(
                "SELECT binding_digest,status,receipt_json,error,command_json FROM intents WHERE intent_id=?",
                &[&command.intent_id],
            ))?;
            if let Some(row) = existing.first() {
                if cell(row, 0)? != binding {
                    return Err(ContractError::IntentConflict);
                }
                return self.project_intent(row, &command.intent_id);
            }
            self.authority(command, &binding)?;
            storage(self.db.exec("INSERT INTO intents(intent_id,binding_digest,command_json,status,owner_epoch) VALUES(?,?,?,'pending',?)", &[&command.intent_id,&binding,&json_text(command)?,&self.owner_epoch]))?;
            storage(pending_tx.commit())?; // PENDING_DURABLE: must precede business transaction.
        }
        let outcome = (|| {
            let tx = storage(self.db.transaction())?;
            // Cancellation/revocation and effects share this BEGIN IMMEDIATE queue.
            let current = storage(self.db.query(
                "SELECT status FROM intents WHERE intent_id=? AND binding_digest=?",
                &[&command.intent_id, &binding],
            ))?;
            if current.len() != 1 || cell(&current[0], 0)? != "pending" {
                return Err(ContractError::Cancelled);
            }
            let admission_id = self.authority(command, &binding)?;
            let result = effect(&self.db, &tx, command)?; // EFFECT_TRANSACTION: no side connection or COMMIT allowed.
            self.authority(command, &binding)?; // Recheck expiry after the effect, before commit.
            let receipt = Receipt {
                protocol_version: PROTOCOL_VERSION,
                intent_id: command.intent_id.clone(),
                binding_digest: binding.clone(),
                scope: command.scope.clone(),
                authority: command.authority.clone(),
                admission_id,
                target_id: command.command.target_id().into(),
                revision: command.expected_revision.next()?,
                status: ExecutionStatus::Committed,
                result,
            };
            receipt.validate_for(command)?;
            storage(self.db.exec("INSERT INTO business_history(intent_id,target_id,old_revision,new_revision,binding_digest,result) VALUES(?,?,?,?,?,?)", &[&command.intent_id,command.command.target_id(),command.expected_revision.as_str(),receipt.revision.as_str(),&binding,&json_text(&receipt.result)?]))?;
            let changed = storage(self.db.exec("UPDATE intents SET status='committed',receipt_json=?,error=NULL WHERE intent_id=? AND binding_digest=? AND status='pending'", &[&json_text(&receipt)?,&command.intent_id,&binding]))?;
            if changed != 1 {
                return Err(ContractError::IntentConflict);
            }
            let consumed = storage(self.db.exec("UPDATE business_grants SET active=0 WHERE grant_id=? AND generation=? AND owner_epoch=? AND binding_digest=? AND active=1", &[&command.authority.grant_id,command.authority.generation.as_str(),&self.owner_epoch,&binding]))?;
            if consumed != 1 {
                return Err(ContractError::InvalidAuthority);
            }
            self.verify_effect_tail(command, &receipt)?;
            storage(tx.commit())?; // BUSINESS_COMMIT: effect + history + intent + original receipt.
            Ok(ExecutionResult {
                status: ExecutionStatus::Committed,
                receipt: Some(receipt),
                error: None,
                recovery_action: RecoveryAction::None,
            })
        })();
        match outcome {
            Ok(result) => Ok(result),
            Err(ref error) if storage_failure(error) => Ok(unknown()), // Unprovable outcome never becomes a retry.
            Err(error) => {
                let tx = storage(self.db.transaction())?;
                let status = if error == ContractError::Cancelled {
                    "cancelled"
                } else {
                    "rejected"
                };
                storage(self.db.exec(
                    "UPDATE intents SET status=?,error=? WHERE intent_id=? AND status='pending'",
                    &[status, &json_text(&error)?, &command.intent_id],
                ))?;
                storage(tx.commit())?;
                self.lookup(&command.intent_id)
            }
        }
    }

    fn verify_effect_tail(
        &self,
        command: &CommandEnvelope,
        receipt: &Receipt,
    ) -> Result<(), ContractError> {
        let grants=storage(self.db.query("SELECT generation,owner_epoch,binding_digest,active,admission_id FROM business_grants WHERE grant_id=?",&[&command.authority.grant_id]))?;
        if grants.len() != 1
            || cell(&grants[0], 0)? != command.authority.generation.as_str()
            || cell(&grants[0], 1)? != self.owner_epoch
            || cell(&grants[0], 2)? != receipt.binding_digest
            || cell(&grants[0], 3)? != "0"
            || grants[0][4] != receipt.admission_id
        {
            return Err(ContractError::Storage);
        }
        let rows = storage(self.db.query(
            "SELECT binding_digest,status,receipt_json FROM intents WHERE intent_id=?",
            &[&command.intent_id],
        ))?;
        if rows.len() != 1
            || cell(&rows[0], 0)? != receipt.binding_digest
            || cell(&rows[0], 1)? != "committed"
            || cell(&rows[0], 2)? != json_text(receipt)?
        {
            return Err(ContractError::Storage);
        }
        let history = storage(self.db.query("SELECT new_revision,binding_digest,result FROM business_history WHERE intent_id=? AND target_id=?", &[&command.intent_id,command.command.target_id()]))?;
        if history.len() != 1
            || cell(&history[0], 0)? != receipt.revision.as_str()
            || cell(&history[0], 1)? != receipt.binding_digest
            || cell(&history[0], 2)? != json_text(&receipt.result)?
        {
            return Err(ContractError::Storage);
        }
        if matches!(
            command.command,
            Operation::SupplierCreate { .. }
                | Operation::SupplierUpdate { .. }
                | Operation::SupplierDelete { .. }
                | Operation::SupplierRestore { .. }
        ) {
            let actual = self.supplier(command.command.target_id())?;
            if actual.revision != receipt.revision
                || serde_json::to_value(actual).map_err(|_| ContractError::Storage)?
                    != receipt.result
            {
                return Err(ContractError::Storage);
            }
            let history = storage(self.db.query("SELECT new_revision,new_payload,old_revision FROM supplier_history WHERE intent_id=? AND target_id=?", &[&command.intent_id,command.command.target_id()]))?;
            if history.len() != 1
                || cell(&history[0], 0)? != receipt.revision.as_str()
                || cell(&history[0], 1)? != json_text(&receipt.result)?
                || cell(&history[0], 2)? != command.expected_revision.as_str()
            {
                return Err(ContractError::Storage);
            }
        }
        if matches!(command.command, Operation::ProjectCreate { .. }) {
            let actual = self.project(command.command.target_id())?;
            if serde_json::to_value(actual).map_err(|_| ContractError::Storage)? != receipt.result {
                return Err(ContractError::Storage);
            }
        }
        if matches!(
            command.command,
            Operation::PaperCreate { .. } | Operation::ResearchImport { .. }
        ) {
            self.verify_research_effect_tail(command, receipt)?;
        }
        Ok(())
    }

    fn apply(&self, db: &Db, command: &CommandEnvelope) -> Result<Value, ContractError> {
        if let Operation::ProjectCreate { project_id, name } = &command.command {
            let normalized = normalize_text(name, 200, true)?.unwrap();
            let exists = storage(db.query("SELECT id FROM projects WHERE id=?", &[project_id]))?;
            if !exists.is_empty() {
                return Err(ContractError::RevisionConflict);
            }
            storage(db.exec(
                "INSERT INTO projects(id,workspace,name,revision) VALUES(?,?,?,'1')",
                &[project_id, &self.workspace, &normalized],
            ))?;
            return Ok(json!({"id":project_id,"name":normalized,"revision":"1","deleted":false}));
        }
        let id = command.command.target_id();
        let old = self.supplier(id);
        let (payload, deleted, operation) = match &command.command {
            Operation::SupplierCreate { payload, .. } => {
                match &old {
                    Ok(_) => return Err(ContractError::RevisionConflict),
                    Err(ContractError::NotFound) => {}
                    Err(e) => return Err(e.clone()),
                }
                (payload.normalize()?, false, "create")
            }
            Operation::SupplierUpdate { payload, .. } => {
                let current = old.as_ref().map_err(Clone::clone)?;
                if current.deleted {
                    return Err(ContractError::NotFound);
                }
                (payload.normalize()?, false, "update")
            }
            Operation::SupplierDelete { .. } => {
                let current = old.as_ref().map_err(Clone::clone)?;
                if current.deleted {
                    return Err(ContractError::RevisionConflict);
                }
                (current.payload.clone(), true, "delete")
            }
            Operation::SupplierRestore { .. } => {
                let current = old.as_ref().map_err(Clone::clone)?;
                if !current.deleted {
                    return Err(ContractError::RevisionConflict);
                }
                (current.payload.clone(), false, "restore")
            }
            _ => return Err(ContractError::UnsupportedOperation),
        };
        if old
            .as_ref()
            .is_ok_and(|current| current.revision != command.expected_revision)
        {
            return Err(ContractError::RevisionConflict);
        }
        let record = SupplierRecord {
            id: id.into(),
            payload,
            revision: command.expected_revision.next()?,
            deleted,
        };
        let payload_json = json_text(&record.payload)?;
        if old.is_ok() {
            let changed = storage(db.exec("UPDATE supplier SET payload=?,revision=?,deleted=? WHERE id=? AND workspace=? AND revision=?", &[&payload_json,record.revision.as_str(),if deleted {"1"} else {"0"},id,&self.workspace,command.expected_revision.as_str()]))?; // SUPPLIER_CAS
            if changed != 1 {
                return Err(ContractError::RevisionConflict);
            }
        } else {
            storage(db.exec(
                "INSERT INTO supplier(id,workspace,payload,revision,deleted) VALUES(?,?,?,?,0)",
                &[id, &self.workspace, &payload_json, record.revision.as_str()],
            ))?;
        }
        let result = serde_json::to_value(&record).map_err(|_| ContractError::Storage)?;
        storage(db.exec("INSERT INTO supplier_history(intent_id,target_id,old_revision,new_revision,old_payload,new_payload,operation) VALUES(?,?,?,?,NULL,?,?)", &[&command.intent_id,id,command.expected_revision.as_str(),record.revision.as_str(),&json_text(&result)?,operation]))?;
        if let Ok(previous) = old {
            storage(db.exec(
                "UPDATE supplier_history SET old_payload=? WHERE intent_id=?",
                &[&json_text(&previous)?, &command.intent_id],
            ))?;
        }
        Ok(result)
    }

    /// Read projection under the trusted host's currently selected workspace.
    pub fn supplier(&self, id: &str) -> Result<SupplierRecord, ContractError> {
        let rows = storage(self.db.query(
            "SELECT id,payload,revision,deleted FROM supplier WHERE id=? AND workspace=?",
            &[id, &self.workspace],
        ))?;
        let row = rows.first().ok_or(ContractError::NotFound)?;
        Ok(SupplierRecord {
            id: cell(row, 0)?.into(),
            payload: serde_json::from_str(cell(row, 1)?).map_err(|_| ContractError::Storage)?,
            revision: Revision::parse(cell(row, 2)?)?,
            deleted: cell(row, 3)? == "1",
        })
    }
    pub fn suppliers(&self, limit: u32, offset: u32) -> Result<Vec<SupplierRecord>, ContractError> {
        if limit == 0 || limit > 200 {
            return Err(ContractError::TextLimit);
        }
        let rows = storage(self.db.query(
            "SELECT id FROM supplier WHERE workspace=? AND deleted=0 ORDER BY id LIMIT ? OFFSET ?",
            &[&self.workspace, &limit.to_string(), &offset.to_string()],
        ))?;
        rows.iter()
            .map(|row| self.supplier(cell(row, 0)?))
            .collect()
    }
    pub fn deleted_suppliers(
        &self,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<SupplierRecord>, ContractError> {
        if limit == 0 || limit > 200 {
            return Err(ContractError::TextLimit);
        }
        let rows = storage(self.db.query(
            "SELECT id FROM supplier WHERE workspace=? AND deleted=1 ORDER BY id LIMIT ? OFFSET ?",
            &[&self.workspace, &limit.to_string(), &offset.to_string()],
        ))?;
        rows.iter()
            .map(|row| self.supplier(cell(row, 0)?))
            .collect()
    }
    pub fn project(&self, id: &str) -> Result<ProjectRecord, ContractError> {
        let rows = storage(self.db.query(
            "SELECT id,name,revision,deleted FROM projects WHERE id=? AND workspace=?",
            &[id, &self.workspace],
        ))?;
        let row = rows.first().ok_or(ContractError::NotFound)?;
        Ok(ProjectRecord {
            id: cell(row, 0)?.into(),
            name: cell(row, 1)?.into(),
            revision: Revision::parse(cell(row, 2)?)?,
            deleted: cell(row, 3)? == "1",
        })
    }
    pub fn projects(&self, limit: u32, offset: u32) -> Result<Vec<ProjectRecord>, ContractError> {
        if limit == 0 || limit > 200 {
            return Err(ContractError::TextLimit);
        }
        let rows = storage(self.db.query(
            "SELECT id FROM projects WHERE workspace=? AND deleted=0 ORDER BY id LIMIT ? OFFSET ?",
            &[&self.workspace, &limit.to_string(), &offset.to_string()],
        ))?;
        rows.iter().map(|row| self.project(cell(row, 0)?)).collect()
    }
    /// HOST ONLY: establishes a new business reference; existing references are
    /// retained across soft deletion and resolve through supplier(id).
    pub fn add_reference_trusted(
        &self,
        reference_id: &str,
        supplier_id: &str,
    ) -> Result<(), ContractError> {
        identity(reference_id)?;
        let tx = storage(self.db.transaction())?;
        if self.supplier(supplier_id)?.deleted {
            return Err(ContractError::NotFound);
        }
        storage(self.db.exec(
            "INSERT INTO supplier_references(reference_id,supplier_id) VALUES(?,?)",
            &[reference_id, supplier_id],
        ))?;
        storage(tx.commit())
    }
    pub fn reference_supplier(&self, reference_id: &str) -> Result<SupplierRecord, ContractError> {
        let rows = storage(self.db.query(
            "SELECT supplier_id FROM supplier_references WHERE reference_id=?",
            &[reference_id],
        ))?;
        self.supplier(cell(rows.first().ok_or(ContractError::NotFound)?, 0)?)
    }

    /// Lookup is read-only, cannot schedule effects, create intents or clean pins.
    pub fn lookup(&self, intent_id: &str) -> Result<ExecutionResult, ContractError> {
        let rows = storage(self.db.query(
            "SELECT binding_digest,status,receipt_json,error,command_json FROM intents WHERE intent_id=?",
            &[intent_id],
        ))?;
        if let Some(row) = rows.first() {
            self.project_intent(row, intent_id)
        } else {
            Ok(ExecutionResult {
                status: ExecutionStatus::Unknown,
                receipt: None,
                error: Some(ContractError::NotFound),
                recovery_action: RecoveryAction::QueryOriginal,
            })
        }
    }
    fn project_intent(
        &self,
        row: &[Option<String>],
        intent_id: &str,
    ) -> Result<ExecutionResult, ContractError> {
        match cell(row, 1)? {
            "committed" => {
                let receipt: Receipt =
                    serde_json::from_str(cell(row, 2)?).map_err(|_| ContractError::Storage)?;
                if receipt.binding_digest != cell(row, 0)?
                    || receipt.scope.workspace_id != self.workspace
                    || receipt.status != ExecutionStatus::Committed
                {
                    return Err(ContractError::Storage);
                }
                let original =
                    CommandEnvelope::decode(cell(row, 4)?).map_err(|_| ContractError::Storage)?;
                if original.intent_id != intent_id {
                    return Err(ContractError::Storage);
                }
                receipt
                    .validate_for(&original)
                    .map_err(|_| ContractError::Storage)?;
                Ok(ExecutionResult {
                    status: ExecutionStatus::Committed,
                    receipt: Some(receipt),
                    error: None,
                    recovery_action: RecoveryAction::None,
                })
            }
            "pending" | "unknown" => Ok(unknown()),
            "cancelled" => Ok(ExecutionResult {
                status: ExecutionStatus::Cancelled,
                receipt: None,
                error: Some(ContractError::Cancelled),
                recovery_action: RecoveryAction::None,
            }),
            "rejected" => Ok(ExecutionResult {
                status: ExecutionStatus::Rejected,
                receipt: None,
                error: Some(
                    serde_json::from_str(cell(row, 3)?).map_err(|_| ContractError::Storage)?,
                ),
                recovery_action: RecoveryAction::None,
            }),
            _ => Err(ContractError::Storage),
        }
    }
    /// HOST ONLY: cancellation linearizes at COMMIT; committed effects stay committed.
    pub fn cancel_trusted(&self, intent_id: &str) -> Result<ExecutionResult, ContractError> {
        let tx: Transaction<'_> = storage(self.db.transaction())?;
        storage(self.db.exec("UPDATE intents SET status='cancelled',error=? WHERE intent_id=? AND status IN('pending','unknown')", &[&json_text(&ContractError::Cancelled)?,intent_id]))?;
        storage(tx.commit())?;
        self.lookup(intent_id)
    }
}
