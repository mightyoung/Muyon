//! Durable unvalidated edited-candidate journal and held core preparation bridge.
//! Core owns private object/pin preparation; no engine or publication is enabled.
//! Bytes here are local preparation data, never a document result or validation.
use super::{
    engine_protocol::{now, verify_stored_request, PreparedEngineRequest},
    gateway::{
        binding_json, document_decode, document_json, journal_candidate_bytes, DocumentEditGateway,
    },
    Binding, Confirmation,
};
use crate::{
    business::BusinessStore,
    contract::{AuthorityBinding, BlobRef, ContractError, Revision},
    documents::{DocumentAccess, DocumentMetadata, DocumentOperation},
    sqlite::Transaction,
};
use sha2::{Digest, Sha256};
type Result<T> = std::result::Result<T, ContractError>;
const TABLE:&str="CREATE TABLE edit_candidate_intents(intent_id TEXT PRIMARY KEY,binding_json TEXT NOT NULL,source_json TEXT NOT NULL,request_json TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN('planned','confirmed','ingesting','candidate_unvalidated','cancelled')),authority_json TEXT,expires_ms TEXT NOT NULL,cancel_requested INTEGER NOT NULL CHECK(cancel_requested IN(0,1)),candidate_hex TEXT CHECK(length(candidate_hex)<=16777216),candidate_digest TEXT,candidate_length TEXT)";
mod core_bridge;
pub use core_bridge::CoreCandidatePreparation;

const MAX_CANDIDATE: usize = 8 * 1024 * 1024;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EditedCandidateState {
    Planned,
    Confirmed,
    CandidateUnvalidated,
    Cancelled,
    Unknown,
}
/// Receipt of local journal preparation only. There is deliberately no document
/// result, engine validation, publication status or durable blob-pin handle.
#[derive(Clone, Debug)]
pub struct EditedCandidatePreparation {
    pub binding: Binding,
    pub state: EditedCandidateState,
    pub candidate: Option<BlobRef>,
}
pub struct EditedCandidateJournal<'a> {
    store: &'a BusinessStore,
}
struct Record {
    source: DocumentMetadata,
    state: String,
    authority: Option<AuthorityBinding>,
    expires: u64,
    cancel: bool,
    bytes: Option<String>,
    digest: Option<String>,
    length: Option<String>,
}
fn sql<T>(v: crate::sqlite::Result<T>) -> Result<T> {
    v.map_err(|_| ContractError::Storage)
}
fn cell(r: &[Option<String>], n: usize) -> Result<&str> {
    r.get(n)
        .and_then(Option::as_deref)
        .ok_or(ContractError::StorageCorrupt)
}
fn sha(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
fn bytes(r: &Record) -> Result<Vec<u8>> {
    let text = r.bytes.as_deref().ok_or(ContractError::NotFound)?;
    if text.len() > MAX_CANDIDATE * 2
        || !text.len().is_multiple_of(2)
        || !text
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err(ContractError::StorageCorrupt);
    }
    let bytes: Vec<u8> = text
        .as_bytes()
        .chunks_exact(2)
        .map(|p| {
            let n = |b: u8| if b <= b'9' { b - b'0' } else { b - b'a' + 10 };
            n(p[0]) * 16 + n(p[1])
        })
        .collect();
    if bytes.is_empty()
        || Some(sha(&bytes).as_str()) != r.digest.as_deref()
        || Some(bytes.len().to_string().as_str()) != r.length.as_deref()
        || sha(&bytes) == r.source.blob.digest
    {
        return Err(ContractError::StorageCorrupt);
    }
    Ok(bytes)
}
impl<'a> EditedCandidateJournal<'a> {
    pub fn initialize_trusted(store: &'a BusinessStore) -> Result<Self> {
        DocumentEditGateway::initialize_trusted(store)?;
        let db = store.database();
        let tx = sql(db.transaction())?;
        let rows = sql(db.query(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='edit_candidate_intents'",
            &[],
        ))?;
        if rows.is_empty() {
            sql(db.exec(TABLE, &[]))?;
        } else if rows.len() != 1 || cell(&rows[0], 0)? != TABLE {
            return Err(ContractError::InvalidVersion);
        }
        sql(tx.commit())?;
        core_bridge::initialize_core_bridge(store)?;
        Ok(Self { store })
    }
    fn load(&self, b: &Binding) -> Result<Record> {
        if b.document.scope().workspace_id != self.store.workspace_id() {
            return Err(ContractError::ScopeMismatch);
        }
        let rows=sql(self.store.database().query("SELECT CASE WHEN length(CAST(binding_json AS BLOB))<=8192 THEN binding_json END,CASE WHEN length(CAST(source_json AS BLOB))<=8192 THEN source_json END,CASE WHEN length(CAST(request_json AS BLOB))<=32768 THEN request_json END,state,CASE WHEN length(CAST(authority_json AS BLOB))<=4096 THEN authority_json END,CASE WHEN length(expires_ms)<=20 THEN expires_ms END,cancel_requested,CASE WHEN length(candidate_hex)<=16777216 THEN candidate_hex END,CASE WHEN length(candidate_digest)=64 THEN candidate_digest END,CASE WHEN length(candidate_length)<=20 THEN candidate_length END FROM edit_candidate_intents WHERE intent_id=?",&[&b.intent_id]))?;
        let r = rows.first().ok_or(ContractError::NotFound)?;
        if cell(r, 0)? != binding_json(b)? {
            return Err(ContractError::IntentConflict);
        }
        let source = document_decode(cell(r, 1)?)?;
        verify_stored_request(&source, cell(r, 2)?, b)
            .map_err(|_| ContractError::StorageCorrupt)?;
        Ok(Record {
            source,
            state: cell(r, 3)?.into(),
            authority: r[4]
                .as_deref()
                .map(serde_json::from_str)
                .transpose()
                .map_err(|_| ContractError::StorageCorrupt)?,
            expires: cell(r, 5)?
                .parse()
                .map_err(|_| ContractError::StorageCorrupt)?,
            cancel: cell(r, 6)? == "1",
            bytes: r[7].clone(),
            digest: r[8].clone(),
            length: r[9].clone(),
        })
    }
    fn view(&self, b: &Binding, r: &Record) -> Result<EditedCandidatePreparation> {
        let state = match r.state.as_str() {
            "planned" => EditedCandidateState::Planned,
            "confirmed" => EditedCandidateState::Confirmed,
            "ingesting" => EditedCandidateState::Unknown,
            "candidate_unvalidated" => EditedCandidateState::CandidateUnvalidated,
            "cancelled" => EditedCandidateState::Cancelled,
            _ => return Err(ContractError::StorageCorrupt),
        };
        let candidate = if r.bytes.is_some() {
            let b = bytes(r)?;
            Some(BlobRef {
                digest: sha(&b),
                byte_length: Revision::new(b.len() as u64),
            })
        } else {
            if r.digest.is_some()
                || r.length.is_some()
                || state == EditedCandidateState::CandidateUnvalidated
            {
                return Err(ContractError::StorageCorrupt);
            }
            None
        };
        Ok(EditedCandidatePreparation {
            binding: b.clone(),
            state,
            candidate,
        })
    }
    fn authorize(
        &self,
        tx: &Transaction<'_>,
        b: &Binding,
        a: &DocumentAccess,
        ops: &[DocumentOperation],
        query: bool,
    ) -> Result<DocumentMetadata> {
        if a.document.scope() != b.document.scope()
            || a.document.document_id() != b.document.document_id()
            || a.document.format() != b.document.format()
        {
            return Err(ContractError::ScopeMismatch);
        }
        if !query && a.document != b.document {
            return Err(ContractError::BindingMismatch);
        }
        self.store.document_access_in_transaction(tx, a, ops)
    }
    fn effect(
        &self,
        tx: &Transaction<'_>,
        b: &Binding,
        a: &DocumentAccess,
        r: &Record,
    ) -> Result<()> {
        let source = self.authorize(
            tx,
            b,
            a,
            &[
                DocumentOperation::ReadText,
                DocumentOperation::StructuredEdit,
            ],
            false,
        )?;
        if source.document != b.document
            || source.blob != r.source.blob
            || source.title != r.source.title
        {
            return Err(ContractError::RevisionConflict);
        }
        if r.cancel {
            return Err(ContractError::Cancelled);
        }
        if r.authority.as_ref() != Some(&a.authority)
            || now().map_err(|_| ContractError::InvalidAuthority)? >= r.expires
        {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(())
    }
    pub fn prepare(
        &self,
        p: &PreparedEngineRequest,
        a: &DocumentAccess,
    ) -> Result<EditedCandidatePreparation> {
        let deadline = p
            .fresh_deadline()
            .map_err(|_| ContractError::InvalidAuthority)?;
        let b = p.binding();
        let db = self.store.database();
        let tx = sql(db.transaction())?;
        let source = self.authorize(&tx, b, a, &[DocumentOperation::ReadText], false)?;
        verify_stored_request(&source, p.request_json(), b)
            .map_err(|_| ContractError::BindingMismatch)?;
        if !sql(db.query(
            "SELECT intent_id FROM edit_journal_intents WHERE intent_id=?",
            &[&b.intent_id],
        ))?
        .is_empty()
        {
            return Err(ContractError::IntentConflict);
        }
        if sql(db.query(
            "SELECT intent_id FROM edit_candidate_intents WHERE intent_id=?",
            &[&b.intent_id],
        ))?
        .is_empty()
        {
            sql(db.exec("INSERT INTO edit_candidate_intents(intent_id,binding_json,source_json,request_json,state,expires_ms,cancel_requested) VALUES(?,?,?,?,'planned',?,0)",&[&b.intent_id,&binding_json(b)?,&document_json(&source)?,p.request_json(),&deadline.to_string()]))?;
        }
        let v = self.view(b, &self.load(b)?)?;
        self.authorize(&tx, b, a, &[DocumentOperation::ReadText], false)?;
        sql(tx.commit())?;
        Ok(v)
    }
    pub fn confirm_trusted(
        &self,
        p: &PreparedEngineRequest,
        a: &DocumentAccess,
        c: &Confirmation,
    ) -> Result<EditedCandidatePreparation> {
        let deadline = p
            .fresh_deadline()
            .map_err(|_| ContractError::InvalidAuthority)?;
        let b = p.binding();
        if &c.binding != b || c.authority != a.authority {
            return Err(ContractError::BindingMismatch);
        }
        let db = self.store.database();
        let tx = sql(db.transaction())?;
        let r = self.load(b)?;
        let source = self.authorize(
            &tx,
            b,
            a,
            &[
                DocumentOperation::ReadText,
                DocumentOperation::StructuredEdit,
            ],
            false,
        )?;
        verify_stored_request(&source, p.request_json(), b)
            .map_err(|_| ContractError::RevisionConflict)?;
        if r.cancel {
            return Err(ContractError::Cancelled);
        }
        if r.state == "ingesting" {
            return Err(ContractError::Unknown);
        }
        if !matches!(
            r.state.as_str(),
            "planned" | "confirmed" | "candidate_unvalidated"
        ) {
            return Err(ContractError::IntentConflict);
        }
        let authority =
            serde_json::to_string(&a.authority).map_err(|_| ContractError::InvalidPayload)?;
        sql(db.exec("UPDATE edit_candidate_intents SET state=CASE WHEN state='planned' THEN 'confirmed' ELSE state END,authority_json=?,expires_ms=? WHERE intent_id=?",&[&authority,&deadline.to_string(),&b.intent_id]))?;
        let v = self.view(b, &self.load(b)?)?;
        self.effect(&tx, b, a, &self.load(b)?)?;
        sql(tx.commit())?;
        Ok(v)
    }
    pub fn lookup_original(
        &self,
        b: &Binding,
        a: &DocumentAccess,
    ) -> Result<EditedCandidatePreparation> {
        let tx = sql(self.store.database().transaction())?;
        self.authorize(&tx, b, a, &[DocumentOperation::Inspect], true)?;
        let v = self.view(b, &self.load(b)?)?;
        self.authorize(&tx, b, a, &[DocumentOperation::Inspect], true)?;
        sql(tx.commit())?;
        Ok(v)
    }
    pub fn candidate_bytes(&self, b: &Binding, a: &DocumentAccess) -> Result<Vec<u8>> {
        let tx = sql(self.store.database().transaction())?;
        // Unpublished edited content needs the exact fresh edit confirmation,
        // not merely a grant to read the original document bytes.
        let r = self.load(b)?;
        self.effect(&tx, b, a, &r)?;
        let data = bytes(&r)?;
        self.effect(&tx, b, a, &self.load(b)?)?;
        sql(tx.commit())?;
        Ok(data)
    }
    pub fn cancel_trusted(&self, b: &Binding) -> Result<EditedCandidateState> {
        let db = self.store.database();
        let tx = sql(db.transaction())?;
        let r = self.load(b)?;
        sql(db.exec("UPDATE edit_candidate_intents SET cancel_requested=1,state=CASE WHEN state='ingesting' THEN state ELSE 'cancelled' END WHERE intent_id=?",&[&b.intent_id]))?;
        let state = if r.state == "ingesting" {
            EditedCandidateState::Unknown
        } else {
            EditedCandidateState::Cancelled
        };
        sql(tx.commit())?;
        Ok(state)
    }
    pub fn stage_candidate_trusted(
        &self,
        b: &Binding,
        a: &DocumentAccess,
        data: &[u8],
    ) -> Result<EditedCandidatePreparation> {
        if data.is_empty() || data.len() > MAX_CANDIDATE {
            return Err(ContractError::RawLimit);
        }
        let digest = sha(data);
        {
            let db = self.store.database();
            let tx = sql(db.transaction())?;
            let r = self.load(b)?;
            if r.cancel {
                return Err(ContractError::Cancelled);
            }
            if matches!(r.state.as_str(), "ingesting" | "candidate_unvalidated") {
                self.authorize(&tx, b, a, &[DocumentOperation::Inspect], true)?;
                if r.state == "ingesting" {
                    return Err(ContractError::Unknown);
                }
                let v = self.view(b, &r)?;
                self.authorize(&tx, b, a, &[DocumentOperation::Inspect], true)?;
                sql(tx.commit())?;
                return Ok(v);
            }
            self.effect(&tx, b, a, &r)?;
            if r.state != "confirmed" {
                return Err(ContractError::InvalidAuthority);
            }
            if digest == r.source.blob.digest {
                return Err(ContractError::InvalidPayload);
            }
            sql(db.exec("UPDATE edit_candidate_intents SET state='ingesting' WHERE intent_id=? AND state='confirmed'",&[&b.intent_id]))?;
            self.effect(&tx, b, a, &self.load(b)?)?;
            sql(tx.commit())?;
        }
        let result = (|| {
            let db = self.store.database();
            let tx = sql(db.transaction())?;
            let r = self.load(b)?;
            self.effect(&tx, b, a, &r)?;
            if r.state != "ingesting" {
                return Err(ContractError::Unknown);
            }
            let total = journal_candidate_bytes(self.store)?;
            if total
                .checked_add(data.len())
                .ok_or(ContractError::RawLimit)?
                > 150 * 1024 * 1024
            {
                return Err(ContractError::RawLimit);
            }
            sql(db.exec("UPDATE edit_candidate_intents SET state='candidate_unvalidated',candidate_hex=?,candidate_digest=?,candidate_length=? WHERE intent_id=? AND state='ingesting' AND cancel_requested=0",&[&hex(data),&digest,&data.len().to_string(),&b.intent_id]))?;
            let v = self.view(b, &self.load(b)?)?;
            self.effect(&tx, b, a, &self.load(b)?)?;
            sql(tx.commit())?;
            Ok(v)
        })();
        // Claim survives every failed/uncertain ingestion. Never reuse the engine or
        // caller payload on retry; original-intent query is the only recovery action.
        result.map_err(|_| ContractError::Unknown)
    }
    pub fn commit_edited(
        &self,
        _b: &Binding,
        _a: &DocumentAccess,
    ) -> Result<EditedCandidatePreparation> {
        Err(ContractError::UnsupportedOperation)
    }
}
