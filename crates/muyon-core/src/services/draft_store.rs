//! Host-owned draft persistence. Saving a draft never authorizes a business command.
//! Use a dedicated file, separate from Bot definitions and the business intent ledger.
use super::{
    drafts::{DraftEnvelope, DraftRef, SaveAck},
    types::{decode_strict, Digest, IntentId, ResultId, ScopeRef},
};
use crate::{
    contract::{stable_digest, ContractError, Revision, MAX_COMMAND_BYTES},
    sqlite::Db,
};
use serde::Serialize;
use std::{fs::OpenOptions, path::Path};

type Result<T> = std::result::Result<T, ContractError>;
const SCHEMA: &[(&str, &str)] = &[
    ("draft_meta", "CREATE TABLE draft_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)"),
    ("plugin_drafts", "CREATE TABLE plugin_drafts(owner TEXT NOT NULL,draft_id TEXT NOT NULL,revision TEXT NOT NULL,envelope TEXT NOT NULL,PRIMARY KEY(owner,draft_id))"),
    ("draft_save_intents", "CREATE TABLE draft_save_intents(intent_id TEXT PRIMARY KEY,request_digest TEXT NOT NULL,ack TEXT NOT NULL)"),
];

fn io<T>(value: crate::sqlite::Result<T>) -> Result<T> {
    value.map_err(|_| ContractError::Storage)
}
fn encode<T: Serialize>(value: &T) -> Result<String> {
    serde_json::to_string(value).map_err(|_| ContractError::InvalidPayload)
}
fn cell(row: &[Option<String>], index: usize) -> Result<&str> {
    row.get(index)
        .and_then(Option::as_deref)
        .ok_or(ContractError::StorageCorrupt)
}
fn validate_scope(scope: &ScopeRef) -> Result<()> {
    for id in std::iter::once(&scope.scope.workspace_id)
        .chain(scope.scope.project_id.iter())
        .chain(scope.account_id.iter())
    {
        ResultId::parse(id).map_err(|_| ContractError::InvalidIdentity)?;
    }
    Ok(())
}

/// The host supplies the current scope; decoded plugin input cannot choose it.
pub struct DraftStore {
    db: Db,
    scope: ScopeRef,
}
/// Replaying a successful save acknowledges storage only; it must not issue a
/// second business dispatch permission to a stale editor.
pub enum SaveOutcome {
    Committed(SaveAck),
    Existing(SaveAck),
}
impl DraftStore {
    /// Explicitly creates a new namespace. Existing or partial files are never replaced.
    pub fn initialize(path: &Path, scope: &ScopeRef) -> Result<()> {
        validate_scope(scope)?;
        let _reservation = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .map_err(|_| ContractError::Storage)?;
        let db = Self::connect(path)?;
        io(db.query("PRAGMA journal_mode=WAL", &[]))?;
        let tx = io(db.transaction())?;
        for (_, sql) in SCHEMA {
            io(db.exec(sql, &[]))?;
        }
        io(db.exec("INSERT INTO draft_meta VALUES('version','1')", &[]))?;
        io(db.exec(
            "INSERT INTO draft_meta VALUES('scope',?)",
            &[&encode(scope)?],
        ))?;
        io(tx.commit())
    }

    fn connect(path: &Path) -> Result<Db> {
        let db = io(Db::open(
            path.to_str().ok_or(ContractError::InvalidIdentity)?,
            false,
            false,
        ))?;
        io(db.exec("PRAGMA synchronous=FULL", &[]))?;
        Ok(db)
    }

    /// Exact schema/scope match only; schema upgrades and scope changes are explicit.
    pub fn open_existing(path: &Path, scope: &ScopeRef) -> Result<Self> {
        validate_scope(scope)?;
        let db = Self::connect(path)?;
        let objects = io(db.query(
            "SELECT type,name FROM sqlite_master WHERE name NOT GLOB 'sqlite_*' ORDER BY name",
            &[],
        ))?;
        if objects.len() != SCHEMA.len()
            || objects.iter().any(|row| {
                cell(row, 0).ok() != Some("table")
                    || !SCHEMA
                        .iter()
                        .any(|(name, _)| cell(row, 1).ok() == Some(*name))
            })
        {
            return Err(ContractError::InvalidVersion);
        }
        for (name, sql) in SCHEMA {
            let rows = io(db.query(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                &[name],
            ))?;
            if rows.len() != 1 || cell(&rows[0], 0)? != *sql {
                return Err(ContractError::InvalidVersion);
            }
        }
        let rows = io(db.query("SELECT key,value FROM draft_meta ORDER BY key", &[]))?;
        if rows.len() != 2
            || cell(&rows[0], 0)? != "scope"
            || cell(&rows[1], 0)? != "version"
            || cell(&rows[1], 1)? != "1"
        {
            return Err(ContractError::InvalidVersion);
        }
        let stored: ScopeRef =
            decode_strict(cell(&rows[0], 1)?).map_err(|_| ContractError::StorageCorrupt)?;
        if &stored != scope {
            return Err(ContractError::ScopeMismatch);
        }
        Ok(Self { db, scope: stored })
    }

    fn validate_ref(&self, reference: &DraftRef) -> Result<()> {
        if reference.scope != self.scope {
            return Err(ContractError::ScopeMismatch);
        }
        ResultId::parse(&reference.owner_plugin_id)
            .and_then(|_| ResultId::parse(&reference.draft_id))
            .map_err(|_| ContractError::InvalidIdentity)?;
        Ok(())
    }

    fn validate_envelope(&self, envelope: &DraftEnvelope) -> Result<()> {
        self.validate_ref(&envelope.draft_ref)?;
        if envelope.schema_version != 1 {
            return Err(ContractError::InvalidVersion);
        }
        let raw = encode(envelope)?;
        if raw.len() > MAX_COMMAND_BYTES {
            return Err(ContractError::RawLimit);
        }
        let _: DraftEnvelope = decode_strict(&raw).map_err(|_| ContractError::InvalidPayload)?;
        Ok(())
    }

    pub fn load(&self, owner: &str, draft_id: &str) -> Result<Option<DraftEnvelope>> {
        let reference = DraftRef {
            owner_plugin_id: owner.into(),
            draft_id: draft_id.into(),
            scope: self.scope.clone(),
            revision: Revision::new(0),
        };
        self.validate_ref(&reference)?;
        let rows = io(self.db.query(
            "SELECT revision,envelope FROM plugin_drafts WHERE owner=? AND draft_id=?",
            &[owner, draft_id],
        ))?;
        let Some(row) = rows.first() else {
            return Ok(None);
        };
        let envelope: DraftEnvelope =
            decode_strict(cell(row, 1)?).map_err(|_| ContractError::StorageCorrupt)?;
        self.validate_envelope(&envelope)
            .map_err(|_| ContractError::StorageCorrupt)?;
        if envelope.draft_ref.owner_plugin_id != owner
            || envelope.draft_ref.draft_id != draft_id
            || envelope.draft_ref.revision.as_str() != cell(row, 0)?
        {
            return Err(ContractError::StorageCorrupt);
        }
        Ok(Some(envelope))
    }

    /// The same save intent and exact request return the original acknowledgement,
    /// even after later edits. Reusing an intent for another request is rejected.
    pub fn save(&self, envelope: &DraftEnvelope, intent: &IntentId) -> Result<SaveAck> {
        match self.save_with_outcome(envelope, intent)? {
            SaveOutcome::Committed(ack) | SaveOutcome::Existing(ack) => Ok(ack),
        }
    }

    pub fn save_with_outcome(
        &self,
        envelope: &DraftEnvelope,
        intent: &IntentId,
    ) -> Result<SaveOutcome> {
        self.validate_envelope(envelope)?;
        let request_digest = stable_digest(
            &serde_json::to_value(envelope).map_err(|_| ContractError::InvalidPayload)?,
        )?;
        let tx = io(self.db.transaction())?;
        let rows = io(self.db.query(
            "SELECT request_digest,ack FROM draft_save_intents WHERE intent_id=?",
            &[intent.as_str()],
        ))?;
        if let Some(row) = rows.first() {
            if cell(row, 0)? != request_digest {
                return Err(ContractError::IntentConflict);
            }
            let ack = self.decode_ack(cell(row, 1)?, &envelope.draft_ref, intent)?;
            super::drafts::validate_save_ack(envelope, &envelope.draft_ref.revision, intent, &ack)
                .map_err(|_| ContractError::StorageCorrupt)?;
            io(tx.commit())?;
            return Ok(SaveOutcome::Existing(ack));
        }
        let reference = &envelope.draft_ref;
        let current = self.load(&reference.owner_plugin_id, &reference.draft_id)?;
        let revision = current
            .as_ref()
            .map(|draft| &draft.draft_ref.revision)
            .cloned()
            .unwrap_or_else(|| Revision::new(0));
        if reference.revision != revision {
            return Err(ContractError::RevisionConflict);
        }
        let mut saved = envelope.clone();
        saved.draft_ref.revision = revision.next()?;
        // Advancing the decimal revision can increase encoded size.
        self.validate_envelope(&saved)?;
        let ack = SaveAck {
            draft_ref: saved.draft_ref.clone(),
            original_intent_id: intent.clone(),
            content_digest: Digest::parse(&stable_digest(&envelope.content)?)
                .map_err(|_| ContractError::InvalidDigest)?,
        };
        io(self.db.exec(
            "INSERT INTO plugin_drafts VALUES(?,?,?,?) ON CONFLICT(owner,draft_id) DO UPDATE SET revision=excluded.revision,envelope=excluded.envelope",
            &[&reference.owner_plugin_id, &reference.draft_id, saved.draft_ref.revision.as_str(), &encode(&saved)?],
        ))?;
        io(self.db.exec(
            "INSERT INTO draft_save_intents VALUES(?,?,?)",
            &[intent.as_str(), &request_digest, &encode(&ack)?],
        ))?;
        io(tx.commit())?;
        Ok(SaveOutcome::Committed(ack))
    }

    fn decode_ack(&self, raw: &str, original: &DraftRef, intent: &IntentId) -> Result<SaveAck> {
        let ack: SaveAck = decode_strict(raw).map_err(|_| ContractError::StorageCorrupt)?;
        let mut expected = original.clone();
        expected.revision = expected.revision.next()?;
        if ack.draft_ref != expected || ack.original_intent_id != *intent {
            return Err(ContractError::StorageCorrupt);
        }
        Ok(ack)
    }

    /// Query-only recovery, using the original reference and intent. No save or replay.
    pub fn lookup_save(&self, original: &DraftRef, intent: &IntentId) -> Result<Option<SaveAck>> {
        self.validate_ref(original)?;
        let rows = io(self.db.query(
            "SELECT ack FROM draft_save_intents WHERE intent_id=?",
            &[intent.as_str()],
        ))?;
        rows.first()
            .map(|row| self.decode_ack(cell(row, 0)?, original, intent))
            .transpose()
    }
}
