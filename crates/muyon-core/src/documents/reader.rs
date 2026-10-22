//! Trusted host facade. Raw bytes are not evidence of parsing/rendering support.
use super::*;
use crate::{
    blobs::{ControlledReader, DocumentReaderStamp, MAX_CHUNK, MAX_DOCUMENT_BYTES},
    business::BusinessStore,
    contract::*,
    sqlite::Transaction,
};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{
    cell::RefCell,
    collections::BTreeMap,
    time::{Duration, Instant},
};

pub const MAX_READ_SESSIONS: usize = 8;
pub const MAX_SOURCE_BUFFER: usize = 2_000_000;
pub const MAX_SESSION_SNAPSHOT_BYTES: usize = 64 * 1024 * 1024;
const IDLE: Duration = Duration::from_secs(15);
const LIFETIME: Duration = Duration::from_secs(30);
type Result<T> = std::result::Result<T, DocumentReadError>;
type CoreResult<T> = std::result::Result<T, ContractError>;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DocumentReadPurpose {
    ReadText,
    Render,
}
impl DocumentReadPurpose {
    fn operation(self) -> DocumentOperation {
        match self {
            Self::ReadText => DocumentOperation::ReadText,
            Self::Render => DocumentOperation::Render,
        }
    }
}
#[derive(Debug, PartialEq, Eq)]
pub enum DocumentReadError {
    Core(ContractError),
    Cleanup {
        primary: Option<ContractError>,
        cleanup: ContractError,
    },
}
impl From<ContractError> for DocumentReadError {
    fn from(error: ContractError) -> Self {
        Self::Core(error)
    }
}
fn sql<T>(value: crate::sqlite::Result<T>) -> CoreResult<T> {
    value.map_err(|_| ContractError::Storage)
}

#[derive(Clone, Debug, Serialize)]
pub struct DocumentReadSessionInfo {
    pub session_id: String,
    pub metadata: DocumentMetadata,
    pub source: FileSource,
    pub purpose: DocumentReadPurpose,
}
#[derive(Debug, Serialize)]
pub struct DocumentReadChunk {
    pub offset: Revision,
    pub bytes: Vec<u8>,
    pub eof: bool,
}
/// A callback fence, not self-authenticating wire authority. Only a live native
/// registry can issue it; every use checks its original document/grant again.
#[derive(Clone, Debug, Serialize)]
pub struct PresentationTicket {
    session_id: String,
    document: DocumentRef,
    authority: AuthorityBinding,
    generation: Revision,
}
impl PresentationTicket {
    pub fn session_id(&self) -> &str { &self.session_id }
    pub fn document(&self) -> &DocumentRef { &self.document }
    pub fn generation(&self) -> &Revision { &self.generation }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PresentationPhase { Loading, Ready }
#[derive(Clone, Debug, Serialize)]
pub struct PresentationStatus {
    pub ticket: PresentationTicket,
    pub phase: PresentationPhase,
    pub valid_for_ms: u64,
    pub check_after_ms: u64,
}
#[derive(Clone, Debug, Serialize)]
pub struct DocumentPresentationInfo {
    pub session: DocumentReadSessionInfo,
    pub status: PresentationStatus,
}
#[derive(Debug, Serialize)]
pub struct PresentationInvalidation {
    pub session_id: String,
    pub generation: Revision,
    pub cleanup_pending: bool,
}
#[derive(Debug, Default, Serialize)]
pub struct PresentationInvalidations {
    pub clear_all: bool,
    pub invalidated: Vec<PresentationInvalidation>,
}
struct PresentationState {
    generation: Revision,
    active: bool,
}
struct Session {
    access: DocumentAccess,
    metadata: DocumentMetadata,
    purpose: DocumentReadPurpose,
    reader: ControlledReader,
    snapshot: Box<[u8]>,
    stamp: DocumentReaderStamp,
    opened: Instant,
    touched: Instant,
    delivered: u64,
    presentation: Option<PresentationState>,
}
impl Session {
    fn expired(&self) -> bool {
        self.opened.elapsed() >= LIFETIME || self.touched.elapsed() >= IDLE
    }
}
fn validate(
    store: &BusinessStore,
    tx: &Transaction<'_>,
    access: &DocumentAccess,
    purpose: DocumentReadPurpose,
    metadata: &DocumentMetadata,
    reader: &mut ControlledReader,
) -> CoreResult<()> {
    let current = store.document_access_in_transaction(tx, access, &[purpose.operation()])?;
    if &current != metadata || reader.source().blob != current.blob {
        return Err(ContractError::BindingMismatch);
    }
    store.verify_document_reader_in_transaction(tx, reader)?;
    // Hashing may take wall time; do not let its initial grant check authorize
    // delivery after expiry. The owner transaction still binds the same head.
    let tail = store.document_access_in_transaction(tx, access, &[purpose.operation()])?;
    if &tail != metadata {
        return Err(ContractError::BindingMismatch);
    }
    Ok(())
}
fn validate_snapshot(
    store: &BusinessStore,
    tx: &Transaction<'_>,
    session: &Session,
) -> CoreResult<()> {
    let current = store.document_access_in_transaction(
        tx,
        &session.access,
        &[session.purpose.operation()],
    )?;
    if current != session.metadata || session.reader.source().blob != current.blob {
        return Err(ContractError::BindingMismatch);
    }
    // The delivered memory is private, immutable and authenticated at open.
    // Stamps detect observed backing-file mutation; cryptographic byte integrity
    // comes from that snapshot, never from assuming timestamps are unforgeable.
    if store.document_reader_stamp_in_transaction(tx, &session.reader)? != session.stamp {
        return Err(ContractError::BindingMismatch);
    }
    let tail = store.document_access_in_transaction(
        tx,
        &session.access,
        &[session.purpose.operation()],
    )?;
    if tail != session.metadata {
        return Err(ContractError::BindingMismatch);
    }
    Ok(())
}

/// Own the existing store in the Service guard. No self-referential borrowed
/// handles, new database connection, path input or cached grant authority.
pub struct DocumentReaderHost {
    store: BusinessStore,
    sessions: BTreeMap<String, Session>,
    poisoned: bool,
    presentation_invalidations: PresentationInvalidations,
}
impl DocumentReaderHost {
    pub fn new(store: BusinessStore) -> Self {
        Self {
            store,
            sessions: BTreeMap::new(),
            poisoned: false,
            presentation_invalidations: PresentationInvalidations::default(),
        }
    }
    /// Trusted Service/evidence adapter borrow; database/transactions remain private.
    pub fn store(&self) -> &BusinessStore {
        &self.store
    }
    pub fn inspect(&self, access: &DocumentAccess) -> Result<DocumentMetadata> {
        Ok(self.store.read_document(access)?)
    }
    fn release<T>(&mut self, mut session: Session, result: CoreResult<T>) -> Result<T> {
        let cleanup = self.store.release_document_reader(&session.reader);
        if cleanup.is_err() { self.presentation_invalidations.clear_all = true; }
        if let Some(state) = session.presentation.as_mut() {
            state.active = false;
            if self.presentation_invalidations.invalidated.len() == MAX_READ_SESSIONS {
                self.presentation_invalidations.clear_all = true;
                self.presentation_invalidations.invalidated.clear();
            }
            self.presentation_invalidations.invalidated.push(PresentationInvalidation {
                session_id: session.reader.source().lease.lease_id.clone(),
                generation: state.generation.clone(),
                cleanup_pending: cleanup.is_err(),
            });
        }
        match (result, cleanup) {
            (Ok(value), Ok(())) => Ok(value),
            (Err(error), Ok(())) => Err(error.into()),
            (result, Err(cleanup)) => {
                self.poisoned = true;
                // Keep the actual owned reader solely for a later explicit
                // cleanup retry; no read/open can proceed on a poisoned host.
                self.sessions
                    .insert(session.reader.source().lease.lease_id.clone(), session);
                Err(DocumentReadError::Cleanup {
                    primary: result.err(),
                    cleanup,
                })
            }
        }
    }
    fn deliver_eof(
        &mut self,
        session: Session,
        chunk: DocumentReadChunk,
    ) -> Result<DocumentReadChunk> {
        let access = session.access.clone();
        let metadata = session.metadata.clone();
        let purpose = session.purpose;
        let opened = session.opened;
        let touched = session.touched;
        let chunk = self.release(session, Ok(chunk))?;
        // Cleanup can wait or change persistent authority. The removed pin is
        // no longer a delivery prerequisite, but exact document/grant truth is.
        let tx = sql(self.store.database().transaction())?;
        let current =
            self.store
                .document_access_in_transaction(&tx, &access, &[purpose.operation()])?;
        if current != metadata {
            return Err(ContractError::BindingMismatch.into());
        }
        if opened.elapsed() >= LIFETIME || touched.elapsed() >= IDLE {
            return Err(ContractError::InvalidAuthority.into());
        }
        tx.commit().map_err(|_| ContractError::Unknown)?;
        Ok(chunk)
    }
    fn sweep(&mut self) -> Result<()> {
        let expired: Vec<_> = self
            .sessions
            .iter()
            .filter(|(_, value)| value.expired())
            .map(|(key, _)| key.clone())
            .collect();
        for key in expired {
            self.close(&key)?;
        }
        Ok(())
    }
    pub fn open(
        &mut self,
        access: &DocumentAccess,
        purpose: DocumentReadPurpose,
    ) -> Result<DocumentReadSessionInfo> {
        self.sweep()?;
        if self.poisoned {
            return Err(ContractError::Unknown.into());
        }
        if self.sessions.len() >= MAX_READ_SESSIONS {
            return Err(ContractError::TextLimit.into());
        }
        let tx = sql(self.store.database().transaction())?;
        let metadata =
            self.store
                .document_access_in_transaction(&tx, access, &[purpose.operation()])?;
        if metadata.blob.byte_length.value() > MAX_DOCUMENT_BYTES {
            return Err(ContractError::TextLimit.into());
        }
        let reserved: usize = self
            .sessions
            .values()
            .map(|session| session.snapshot.len())
            .sum();
        let length = metadata.blob.byte_length.value() as usize;
        if reserved
            .checked_add(length)
            .ok_or(ContractError::TextLimit)?
            > MAX_SESSION_SNAPSHOT_BYTES
        {
            return Err(ContractError::TextLimit.into());
        }
        let project = access
            .document
            .scope()
            .project_id
            .as_deref()
            .ok_or(ContractError::ScopeMismatch)?;
        let mut reader =
            self.store
                .open_document_reader_in_transaction(&tx, project, &metadata.blob)?;
        validate(&self.store, &tx, access, purpose, &metadata, &mut reader)?;
        let stamp = self
            .store
            .document_reader_stamp_in_transaction(&tx, &reader)?;
        let mut snapshot = Vec::with_capacity(length);
        while snapshot.len() < length {
            let chunk = self
                .store
                .read_blob_chunk(&mut reader, MAX_CHUNK.min(length - snapshot.len()))?;
            if chunk.is_empty() {
                return Err(ContractError::StorageCorrupt.into());
            }
            snapshot.extend_from_slice(&chunk);
        }
        let digest: String = Sha256::digest(&snapshot)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect();
        #[cfg(test)]
        crate::blobs::record_document_hash_bytes(snapshot.len());
        if digest != metadata.blob.digest {
            return Err(ContractError::BindingMismatch.into());
        }
        let now = Instant::now();
        let session = Session {
            access: access.clone(),
            metadata: metadata.clone(),
            purpose,
            reader,
            snapshot: snapshot.into_boxed_slice(),
            stamp,
            opened: now,
            touched: now,
            delivered: 0,
            presentation: None,
        };
        validate_snapshot(&self.store, &tx, &session)?;
        let info = DocumentReadSessionInfo {
            session_id: session.reader.source().lease.lease_id.clone(),
            metadata,
            source: session.reader.source().clone(),
            purpose,
        };
        if tx.commit().is_err() {
            return self.release(session, Err(ContractError::Unknown));
        }
        self.sessions.insert(info.session_id.clone(), session);
        Ok(info)
    }
    pub fn read_chunk(&mut self, id: &str, max_bytes: usize) -> Result<DocumentReadChunk> {
        self.read_chunk_mode(id, max_bytes, None)
    }
    fn read_chunk_mode(&mut self, id: &str, max_bytes: usize, ticket: Option<&PresentationTicket>) -> Result<DocumentReadChunk> {
        self.sweep()?;
        match ticket {
            Some(ticket) => self.require_presentation_ticket(ticket, true)?,
            None => {
                if self.sessions.get(id).is_some_and(|session| session.presentation.is_some()) {
                    return Err(ContractError::UnsupportedOperation.into());
                }
            }
        }
        let mut session = self.sessions.remove(id).ok_or(ContractError::NotFound)?;
        if self.poisoned {
            return self.release(session, Err(ContractError::Unknown));
        }
        let result = (|| -> CoreResult<DocumentReadChunk> {
            if max_bytes == 0 || max_bytes > MAX_CHUNK {
                return Err(ContractError::TextLimit);
            }
            let tx = sql(self.store.database().transaction())?;
            validate_snapshot(&self.store, &tx, &session)?;
            let offset = session.delivered;
            let end = (offset as usize + max_bytes).min(session.snapshot.len());
            let bytes = session.snapshot[offset as usize..end].to_vec();
            session.delivered = session
                .delivered
                .checked_add(bytes.len() as u64)
                .ok_or(ContractError::TextLimit)?;
            let length = session.metadata.blob.byte_length.value();
            if session.delivered > length || session.delivered > MAX_DOCUMENT_BYTES {
                return Err(ContractError::TextLimit);
            }
            validate_snapshot(&self.store, &tx, &session)?;
            if session.expired() {
                return Err(ContractError::InvalidAuthority);
            }
            tx.commit().map_err(|_| ContractError::Unknown)?;
            Ok(DocumentReadChunk {
                offset: Revision::new(offset),
                bytes,
                eof: session.delivered == length,
            })
        })();
        match result {
            Ok(chunk) if !chunk.eof || session.presentation.is_some() => {
                if !chunk.bytes.is_empty() { session.touched = Instant::now(); }
                self.sessions.insert(id.into(), session);
                Ok(chunk)
            }
            Ok(chunk) => self.deliver_eof(session, chunk),
            Err(error) => self.release(session, Err(error)),
        }
    }
    fn require_presentation_ticket(&self, ticket: &PresentationTicket, require_active: bool) -> CoreResult<()> {
        let session = self.sessions.get(&ticket.session_id).ok_or(ContractError::NotFound)?;
        let state = session.presentation.as_ref().ok_or(ContractError::InvalidAuthority)?;
        if session.access.document != ticket.document || session.access.authority != ticket.authority
            || state.generation != ticket.generation || (require_active && !state.active) {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(())
    }
    fn presentation_status_in_transaction(&self, tx: &Transaction<'_>, session: &Session) -> CoreResult<PresentationStatus> {
        validate_snapshot(&self.store, tx, session)?;
        let state = session.presentation.as_ref().ok_or(ContractError::InvalidAuthority)?;
        if !state.active || session.expired() { return Err(ContractError::InvalidAuthority); }
        let grant_deadline = self.store.document_read_deadline_in_transaction(tx, &session.access, &[DocumentOperation::Render])?;
        let grant_remaining = grant_deadline.saturating_sub(storage::now_ms()?);
        let remaining = LIFETIME.saturating_sub(session.opened.elapsed()).min(IDLE.saturating_sub(session.touched.elapsed())).as_millis() as u64;
        let valid_for_ms = remaining.min(grant_remaining);
        if valid_for_ms == 0 { return Err(ContractError::InvalidAuthority); }
        Ok(PresentationStatus {
            ticket: PresentationTicket { session_id: session.reader.source().lease.lease_id.clone(), document: session.access.document.clone(), authority: session.access.authority.clone(), generation: state.generation.clone() },
            phase: if session.delivered == session.metadata.blob.byte_length.value() { PresentationPhase::Ready } else { PresentationPhase::Loading },
            valid_for_ms,
            check_after_ms: valid_for_ms.min(1000),
        })
    }
    /// Explicit new selection; never a renewal of an old ticket or grant.
    pub fn open_presentation(&mut self, access: &DocumentAccess) -> Result<DocumentPresentationInfo> {
        if self.poisoned { return Err(ContractError::Unknown.into()); }
        let previous: Vec<_> = self.sessions.iter().filter(|(_, session)| session.presentation.is_some()).map(|(id, _)| id.clone()).collect();
        for id in previous { self.close(&id)?; }
        let session = self.open(access, DocumentReadPurpose::Render)?;
        self.sessions.get_mut(&session.session_id).ok_or(ContractError::NotFound)?.presentation = Some(PresentationState { generation: Revision::new(1), active: true });
        let ticket = PresentationTicket { session_id: session.session_id.clone(), document: access.document.clone(), authority: access.authority.clone(), generation: Revision::new(1) };
        let status = self.check_presentation(&ticket)?;
        Ok(DocumentPresentationInfo { session, status })
    }
    pub fn read_presentation_chunk(&mut self, ticket: &PresentationTicket, max_bytes: usize) -> Result<DocumentReadChunk> {
        self.read_chunk_mode(&ticket.session_id, max_bytes, Some(ticket))
    }
    /// Status refresh never extends idle, absolute or grant expiry. Host must
    /// clear cached output on any error and may display only phase Ready.
    pub fn check_presentation(&mut self, ticket: &PresentationTicket) -> Result<PresentationStatus> {
        if self.poisoned { return Err(ContractError::Unknown.into()); }
        self.sweep()?;
        self.require_presentation_ticket(ticket, true)?;
        let session = self.sessions.remove(&ticket.session_id).ok_or(ContractError::NotFound)?;
        let result = (|| -> CoreResult<PresentationStatus> {
            let tx = sql(self.store.database().transaction())?;
            let status = self.presentation_status_in_transaction(&tx, &session)?;
            tx.commit().map_err(|_| ContractError::Unknown)?;
            Ok(status)
        })();
        match result {
            Ok(status) => { self.sessions.insert(ticket.session_id.clone(), session); Ok(status) }
            Err(error) => self.release(session, Err(error)),
        }
    }
    pub fn advance_presentation_frame(&mut self, ticket: &PresentationTicket) -> Result<PresentationStatus> {
        let checked = self.check_presentation(ticket)?;
        if checked.phase != PresentationPhase::Ready { return Err(ContractError::InvalidPayload.into()); }
        let next = {
            let session = self.sessions.get_mut(&ticket.session_id).ok_or(ContractError::NotFound)?;
            let state = session.presentation.as_mut().ok_or(ContractError::InvalidAuthority)?;
            state.generation = state.generation.next()?;
            session.touched = Instant::now();
            PresentationTicket { generation: state.generation.clone(), ..ticket.clone() }
        };
        self.check_presentation(&next)
    }
    pub fn close_presentation(&mut self, ticket: &PresentationTicket) -> Result<()> {
        if !self.sessions.contains_key(&ticket.session_id) { return Ok(()); }
        self.require_presentation_ticket(ticket, false)?;
        self.close(&ticket.session_id)
    }
    pub fn take_presentation_invalidations(&mut self) -> PresentationInvalidations {
        std::mem::take(&mut self.presentation_invalidations)
    }
    pub fn is_current(&mut self, id: &str) -> Result<bool> {
        self.sweep()?;
        let Some(mut session) = self.sessions.remove(id) else {
            return Ok(false);
        };
        if self.poisoned {
            return self.release(session, Err(ContractError::Unknown));
        }
        let result = (|| -> CoreResult<()> {
            let tx = sql(self.store.database().transaction())?;
            validate(
                &self.store,
                &tx,
                &session.access,
                session.purpose,
                &session.metadata,
                &mut session.reader,
            )?;
            if session.expired() {
                return Err(ContractError::InvalidAuthority);
            }
            tx.commit().map_err(|_| ContractError::Unknown)
        })();
        if result.is_ok() {
            self.sessions.insert(id.into(), session);
            Ok(true)
        } else {
            self.release(session, Ok(false))
        }
    }
    pub fn close(&mut self, id: &str) -> Result<()> {
        match self.sessions.remove(id) {
            Some(session) => self.release(session, Ok(())),
            None => Ok(()),
        }
    }
    pub fn close_all(&mut self) -> Result<()> {
        let sessions = std::mem::take(&mut self.sessions);
        let mut first = None;
        for (_, session) in sessions {
            if let Err(error) = self.release(session, Ok(())) {
                if first.is_none() {
                    first = Some(error);
                }
            }
        }
        match first {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }
    #[cfg(test)]
    pub(super) fn expire_for_test(&mut self, id: &str, idle: bool) {
        let session = self.sessions.get_mut(id).unwrap();
        if idle {
            session.touched = Instant::now() - IDLE;
        } else {
            session.opened = Instant::now() - LIFETIME;
        }
    }
    #[cfg(test)]
    pub(super) fn resample_stamp_for_test(&mut self, id: &str) {
        let session = self.sessions.get_mut(id).unwrap();
        let tx = self.store.database().transaction().unwrap();
        session.stamp = self
            .store
            .document_reader_stamp_in_transaction(&tx, &session.reader)
            .unwrap();
        tx.commit().unwrap();
    }
}
impl Drop for DocumentReaderHost {
    fn drop(&mut self) {
        let _ = self.close_all();
    }
}

/// Nonconstructible, transaction-borrowed local processing view, never a cached
/// authorization token. Return data only after with_document_source returns Ok.
pub struct DocumentReadView<'a, 'tx> {
    store: &'a BusinessStore,
    tx: &'a Transaction<'tx>,
    access: &'a DocumentAccess,
    metadata: &'a DocumentMetadata,
    reader: &'a RefCell<ControlledReader>,
    bytes: &'a [u8],
    purpose: DocumentReadPurpose,
}
impl DocumentReadView<'_, '_> {
    pub fn metadata(&self) -> &DocumentMetadata {
        self.metadata
    }
    pub fn bytes(&self) -> &[u8] {
        self.bytes
    }
    pub fn request(&self) -> ReadRequest {
        ReadRequest {
            document: self.access.document.clone(),
            authority: self.access.authority.clone(),
            operation: self.purpose.operation(),
            anchor: None,
        }
    }
}
impl DocumentHost for DocumentReadView<'_, '_> {
    fn resolve_current(
        &self,
        request: &ReadRequest,
    ) -> std::result::Result<CurrentDocument, ReadInvalidation> {
        if request.document != self.access.document
            || request.authority != self.access.authority
            || request.operation != self.purpose.operation()
            || request.anchor.is_some()
        {
            return Err(ReadInvalidation::PermissionDenied);
        }
        validate(
            self.store,
            self.tx,
            self.access,
            self.purpose,
            self.metadata,
            &mut self.reader.borrow_mut(),
        )
        .map_err(|_| ReadInvalidation::AuthorityUnavailable)?;
        Ok(CurrentDocument {
            document: self.metadata.document.clone(),
            authority: self.access.authority.clone(),
            access: AccessState::Active,
            source: self.reader.borrow().source().clone(),
            permissions: vec![self.purpose.operation()],
        })
    }
}
impl BusinessStore {
    /// Trusted local callback only: no nested store transaction, file/network
    /// side effect or external delivery before this method successfully returns.
    pub fn with_document_source<T>(
        &self,
        access: &DocumentAccess,
        purpose: DocumentReadPurpose,
        max_bytes: usize,
        callback: impl FnOnce(&DocumentReadView<'_, '_>) -> CoreResult<T>,
    ) -> Result<T> {
        if max_bytes == 0 || max_bytes > MAX_SOURCE_BUFFER {
            return Err(ContractError::TextLimit.into());
        }
        let tx = sql(self.database().transaction())?;
        let metadata = self.document_access_in_transaction(&tx, access, &[purpose.operation()])?;
        if metadata.blob.byte_length.value() > max_bytes as u64 {
            return Err(ContractError::TextLimit.into());
        }
        let project = access
            .document
            .scope()
            .project_id
            .as_deref()
            .ok_or(ContractError::ScopeMismatch)?;
        let mut reader = self.open_document_reader_in_transaction(&tx, project, &metadata.blob)?;
        let mut bytes = Vec::with_capacity(metadata.blob.byte_length.value() as usize);
        while bytes.len() < metadata.blob.byte_length.value() as usize {
            let chunk =
                self.read_blob_chunk(&mut reader, MAX_CHUNK.min(max_bytes - bytes.len()))?;
            if chunk.is_empty() {
                return Err(ContractError::StorageCorrupt.into());
            }
            bytes.extend_from_slice(&chunk);
        }
        let digest: String = Sha256::digest(&bytes)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect();
        if digest != metadata.blob.digest {
            return Err(ContractError::BindingMismatch.into());
        }
        let reader = RefCell::new(reader);
        let view = DocumentReadView {
            store: self,
            tx: &tx,
            access,
            metadata: &metadata,
            reader: &reader,
            bytes: &bytes,
            purpose,
        };
        view.resolve_current(&view.request())
            .map_err(|_| ContractError::InvalidAuthority)?;
        let value = callback(&view)?;
        view.resolve_current(&view.request())
            .map_err(|_| ContractError::InvalidAuthority)?;
        self.release_document_reader(&reader.borrow())?;
        drop(reader.into_inner());
        // Finish cleanup before its delivery check, retaining any durable
        // authority changes made during cleanup instead of undoing them.
        tx.commit().map_err(|_| ContractError::Unknown)?;
        // The write COMMIT itself may wait. Do not let pre-COMMIT authority
        // authorize output after that wait; this final transaction is read-only.
        let delivery = sql(self.database().transaction())?;
        let current =
            self.document_access_in_transaction(&delivery, access, &[purpose.operation()])?;
        if current != metadata {
            return Err(ContractError::BindingMismatch.into());
        }
        delivery.commit().map_err(|_| ContractError::Unknown)?;
        Ok(value)
    }
}
