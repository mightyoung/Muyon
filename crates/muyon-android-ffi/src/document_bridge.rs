//! Trusted private Service adapter; no grant issuer, arbitrary path, PFD or annotation write.
//! Current core closes at EOF. A completed byte copy is NOT a reusable display lease.
use super::{opaque_id, ProductError};
use muyon_core::{
    business::BusinessStore,
    contract::{AuthorityBinding, ContractError, Revision},
    documents::{
        reader::{DocumentReadError, DocumentReadPurpose, DocumentReaderHost},
        DocumentAccess, DocumentMetadata, DocumentRef,
    },
    evidence::{
        store::{StoreEvidence, StoreEvidenceError, StoredProcessing},
        EvidenceError, EvidenceRef, InputKind,
    },
};
use serde::Serialize;
use serde_json::json;
use std::{collections::BTreeMap, ops::Deref, time::{Duration, Instant}};

type Result<T> = std::result::Result<T, ProductError>;
const MAX_WIRE: usize = 262144;
const MAX_STREAM: u64 = 16 * 1024 * 1024;
const MAX_PROCESSING: usize = 4;
const MAX_HITS: usize = 32;
const IDLE: Duration = Duration::from_secs(15);
const LIFE: Duration = Duration::from_secs(30);

#[derive(Clone, PartialEq, Eq, uniffi::Record)]
pub struct DocumentReaderScope {
    pub service_session: String,
    pub generation: String,
    pub project: Option<String>,
}
#[derive(Clone, uniffi::Record)]
pub struct DocumentAccessRequest {
    pub scope: DocumentReaderScope,
    pub document_ref_json: String,
    pub grant_id: String,
    pub grant_generation: String,
}
#[derive(Clone, uniffi::Record)]
pub struct DocumentReadUseRequest {
    pub scope: DocumentReaderScope,
    pub read_session_id: String,
}
#[derive(Debug, uniffi::Record)]
pub struct DocumentReadChunkResult {
    pub offset: String,
    pub bytes: Vec<u8>,
    pub eof: bool,
    pub session_active: bool,
}
#[derive(Clone, Copy, uniffi::Enum)]
pub enum DocumentReadOperation { ReadText, Render }
impl From<DocumentReadOperation> for DocumentReadPurpose {
    fn from(value: DocumentReadOperation) -> Self {
        match value { DocumentReadOperation::ReadText => Self::ReadText, DocumentReadOperation::Render => Self::Render }
    }
}
#[derive(Clone, Copy, uniffi::Enum)]
pub enum DocumentEvidenceKind { Utf8Text, Pdf, Ocr }
impl From<DocumentEvidenceKind> for InputKind {
    fn from(value: DocumentEvidenceKind) -> Self {
        match value { DocumentEvidenceKind::Utf8Text => Self::Utf8Text, DocumentEvidenceKind::Pdf => Self::Pdf, DocumentEvidenceKind::Ocr => Self::Ocr }
    }
}
#[derive(Clone, uniffi::Record)]
pub struct DocumentEvidenceUseRequest {
    pub scope: DocumentReaderScope,
    pub processing_id: String,
}
#[derive(Clone, uniffi::Record)]
pub struct DocumentEvidenceAnswerRequest {
    pub context: DocumentEvidenceUseRequest,
    pub query_id: String,
    pub body: String,
    pub cited_indices: Vec<u32>,
}
fn failure(code: &'static str) -> ProductError { ProductError::Failure { code: code.into() } }
fn identifier(value: &str) -> Result<()> {
    if value.is_empty() || value.len() > 128 || !value.bytes().all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b)) {
        Err(failure("DOCUMENT_INVALID_REQUEST"))
    } else { Ok(()) }
}
fn scope(value: &DocumentReaderScope) -> Result<()> {
    identifier(&value.service_session)?;
    identifier(&value.generation)?;
    identifier(value.project.as_deref().ok_or_else(|| failure("DOCUMENT_SCOPE_MISMATCH"))?)
}
fn same_scope(expected: &DocumentReaderScope, actual: &DocumentReaderScope) -> Result<()> {
    scope(actual)?;
    if expected != actual { return Err(failure("DOCUMENT_SCOPE_MISMATCH")); }
    Ok(())
}
fn encode<T: Serialize>(value: &T) -> Result<String> {
    let raw = serde_json::to_string(value).map_err(|_| failure("DOCUMENT_UNAVAILABLE"))?;
    if raw.len() > MAX_WIRE { return Err(failure("DOCUMENT_LIMIT")); }
    Ok(raw)
}
fn core_error(error: ContractError) -> ProductError {
    let code = match error {
        ContractError::InvalidAuthority => "DOCUMENT_ACCESS_DENIED",
        ContractError::ScopeMismatch => "DOCUMENT_SCOPE_MISMATCH",
        ContractError::RevisionConflict | ContractError::BindingMismatch | ContractError::NotFound => "DOCUMENT_SOURCE_INVALIDATED",
        ContractError::TextLimit | ContractError::RawLimit => "DOCUMENT_LIMIT",
        ContractError::InvalidIdentity | ContractError::InvalidJson | ContractError::InvalidVersion
        | ContractError::InvalidRevision | ContractError::InvalidPayload | ContractError::Required => "DOCUMENT_INVALID_REQUEST",
        _ => "DOCUMENT_UNAVAILABLE",
    };
    failure(code)
}
struct ReadLease {
    scope: DocumentReaderScope,
    core_id: String,
    reference: DocumentRef,
}
struct QuerySnapshot { id: String, hits: Vec<EvidenceRef> }
struct ProcessingEntry {
    scope: DocumentReaderScope,
    access: DocumentAccess,
    processing: StoredProcessing,
    query: Option<QuerySnapshot>,
    opened: Instant,
    touched: Instant,
}
impl ProcessingEntry {
    fn expired(&self) -> bool { self.opened.elapsed() >= LIFE || self.touched.elapsed() >= IDLE }
}
/// Owns exactly the original BusinessStore through the canonical facade. Deref
/// keeps existing business/draft callsites on the SAME connection and owner lock.
pub(crate) struct DocumentBridge {
    host: DocumentReaderHost,
    workspace: String,
    epoch: String,
    reads: BTreeMap<String, ReadLease>,
    processing: BTreeMap<String, ProcessingEntry>,
    cleanup_blocked: bool,
    evidence_cleanup_failed: bool,
    stopped: bool,
}
impl Deref for DocumentBridge {
    type Target = BusinessStore;
    fn deref(&self) -> &BusinessStore { self.host.store() }
}
impl DocumentBridge {
    pub(crate) fn new(store: BusinessStore, workspace: String, epoch: String) -> Self {
        Self { host: DocumentReaderHost::new(store), workspace, epoch, reads: BTreeMap::new(),
            processing: BTreeMap::new(), cleanup_blocked: false, evidence_cleanup_failed: false, stopped: false }
    }
    fn ready(&self) -> Result<()> {
        if self.stopped { return Err(failure("DOCUMENT_READER_STOPPED")); }
        if self.cleanup_blocked { return Err(failure("DOCUMENT_CLEANUP_REQUIRED")); }
        Ok(())
    }
    fn access(&self, request: &DocumentAccessRequest) -> Result<DocumentAccess> {
        self.ready()?;
        scope(&request.scope)?;
        identifier(&request.grant_id)?;
        if request.document_ref_json.len() > 8192 { return Err(failure("DOCUMENT_LIMIT")); }
        let document: DocumentRef = serde_json::from_str(&request.document_ref_json)
            .map_err(|_| failure("DOCUMENT_INVALID_REQUEST"))?;
        if document.scope().workspace_id != self.workspace || document.scope().project_id != request.scope.project {
            return Err(failure("DOCUMENT_SCOPE_MISMATCH"));
        }
        let generation = Revision::parse(&request.grant_generation).map_err(core_error)?;
        if generation.value() == 0 { return Err(failure("DOCUMENT_ACCESS_DENIED")); }
        Ok(DocumentAccess { document, authority: AuthorityBinding {
            grant_id: request.grant_id.clone(), generation, owner_epoch: self.epoch.clone(),
        } })
    }
    fn reader_result<T>(&mut self, result: std::result::Result<T, DocumentReadError>) -> Result<T> {
        match result {
            Ok(value) => Ok(value),
            Err(DocumentReadError::Core(error)) => Err(core_error(error)),
            Err(DocumentReadError::Cleanup { .. }) => {
                self.cleanup_blocked = true;
                Err(failure("DOCUMENT_CLEANUP_REQUIRED"))
            }
        }
    }
    fn evidence_result<T>(&mut self, result: std::result::Result<T, StoreEvidenceError>) -> Result<T> {
        match result {
            Ok(value) => Ok(value),
            Err(StoreEvidenceError::Core(error)) => Err(core_error(error)),
            Err(StoreEvidenceError::Cleanup { .. }) => {
                self.cleanup_blocked = true;
                self.evidence_cleanup_failed = true;
                Err(failure("DOCUMENT_CLEANUP_REQUIRED"))
            }
            Err(StoreEvidenceError::Processing(error)) => Err(failure(match error {
                EvidenceError::Denied => "DOCUMENT_ACCESS_DENIED",
                EvidenceError::SourceMismatch => "DOCUMENT_SOURCE_INVALIDATED",
                EvidenceError::LimitExceeded => "DOCUMENT_LIMIT",
                EvidenceError::NotAvailable => "DOCUMENT_EVIDENCE_UNAVAILABLE",
                EvidenceError::InvalidRequest | EvidenceError::InvalidAnchor => "DOCUMENT_INVALID_REQUEST",
            })),
        }
    }
    pub(crate) fn metadata(&mut self, request: DocumentAccessRequest) -> Result<String> {
        let access = self.access(&request)?;
        let result = self.host.inspect(&access);
        let metadata = self.reader_result(result)?;
        encode(&json!({"schema":1,"status":"inspected","document":metadata,
            "annotation_editing":false,"safety_status":"not_assessed"}))
    }
    pub(crate) fn annotations(&mut self, request: DocumentAccessRequest) -> Result<String> {
        let access = self.access(&request)?;
        let annotations = self.host.store().list_annotations(&access).map_err(core_error)?;
        let out = encode(&json!({"schema":1,"status":"listed","annotations":annotations,"annotation_editing":false}))?;
        self.deliver(&access, None, out)
    }
    pub(crate) fn open(&mut self, request: DocumentAccessRequest, purpose: DocumentReadOperation) -> Result<String> {
        let access = self.access(&request)?;
        if self.reads.len() >= 8 {
            // Admission only: explicit checks hash the whole source. Never run
            // these for each chunk; core read_chunk already validates its lease.
            let known: Vec<_> = self.reads.iter().map(|(id, lease)| (id.clone(), lease.core_id.clone())).collect();
            for (id, core_id) in known {
                let result = self.host.is_current(&core_id);
                if !self.reader_result(result)? { self.reads.remove(&id); }
            }
            if self.reads.len() >= 8 { return Err(failure("DOCUMENT_LIMIT")); }
        }
        let id = opaque_id("document-reader")?;
        let result = self.host.open(&access, purpose.into());
        let info = self.reader_result(result)?;
        self.reads.insert(id.clone(), ReadLease { scope: request.scope, core_id: info.session_id,
            reference: info.metadata.document.clone() });
        if info.metadata.blob.byte_length.value() > MAX_STREAM {
            let lease = self.reads.get(&id).ok_or_else(|| failure("DOCUMENT_UNAVAILABLE"))?;
            let request = DocumentReadUseRequest { scope: lease.scope.clone(), read_session_id: id };
            self.close(request)?;
            return Err(failure("DOCUMENT_LIMIT"));
        }
        let result = encode(&json!({"schema":1,"status":"opened","read_session_id":id,
            "document":info.metadata,"purpose":info.purpose,"byte_length":info.source.blob.byte_length,
            "sha256":info.source.blob.digest,"expires_at_ms":null,
            "expiry_status":"enforced_by_core_not_exposed","annotation_editing":false,
            "safety_status":"not_assessed","display_lease":false}));
        if result.is_err() {
            let lease = self.reads.get(&id).ok_or_else(|| failure("DOCUMENT_UNAVAILABLE"))?;
            self.close(DocumentReadUseRequest { scope: lease.scope.clone(), read_session_id: id })?;
        }
        result
    }
    fn read_identity(&self, request: &DocumentReadUseRequest) -> Result<Option<(String, DocumentRef)>> {
        scope(&request.scope)?;
        identifier(&request.read_session_id)?;
        match self.reads.get(&request.read_session_id) {
            None => Ok(None),
            Some(lease) => { same_scope(&lease.scope, &request.scope)?; Ok(Some((lease.core_id.clone(), lease.reference.clone()))) }
        }
    }
    pub(crate) fn check(&mut self, request: DocumentReadUseRequest) -> Result<String> {
        self.ready()?;
        let Some((id, reference)) = self.read_identity(&request)? else {
            return encode(&json!({"schema":1,"status":"invalidated","read_session_id":request.read_session_id}));
        };
        let result = self.host.is_current(&id);
        let current = self.reader_result(result)?;
        if !current { self.reads.remove(&request.read_session_id); }
        encode(&json!({"schema":1,"status":if current {"current"} else {"invalidated"},
            "read_session_id":request.read_session_id,"document":reference,
            "expires_at_ms":null,"expiry_status":"enforced_by_core_not_exposed"}))
    }
    pub(crate) fn chunk(&mut self, request: DocumentReadUseRequest, max_bytes: u32) -> Result<DocumentReadChunkResult> {
        self.ready()?;
        let (id, _) = self.read_identity(&request)?.ok_or_else(|| failure("DOCUMENT_SOURCE_INVALIDATED"))?;
        let result = self.host.read_chunk(&id, max_bytes as usize);
        match result {
            Ok(chunk) => {
                if chunk.eof { self.reads.remove(&request.read_session_id); }
                Ok(DocumentReadChunkResult { offset: chunk.offset.as_str().into(), bytes: chunk.bytes,
                    eof: chunk.eof, session_active: !chunk.eof })
            }
            Err(error) => {
                if !matches!(error, DocumentReadError::Cleanup { .. }) { self.reads.remove(&request.read_session_id); }
                self.reader_result(Err(error))
            }
        }
    }
    pub(crate) fn close(&mut self, request: DocumentReadUseRequest) -> Result<()> {
        let Some((id, _)) = self.read_identity(&request)? else { return Ok(()); };
        let result = self.host.close(&id);
        self.reader_result(result)?;
        self.reads.remove(&request.read_session_id);
        Ok(())
    }
    pub(crate) fn release_owner(&mut self, owner: &str) -> Result<()> {
        identifier(owner)?;
        let closing: Vec<_> = self.reads.iter().filter(|(_, lease)| lease.scope.service_session == owner)
            .map(|(id, lease)| DocumentReadUseRequest { scope: lease.scope.clone(), read_session_id: id.clone() }).collect();
        let mut first = None;
        for request in closing {
            if let Err(error) = self.close(request) { if first.is_none() { first = Some(error); } }
        }
        self.processing.retain(|_, entry| entry.scope.service_session != owner);
        if let Some(error) = first { return Err(error); }
        if self.cleanup_blocked { return Err(failure("DOCUMENT_CLEANUP_REQUIRED")); }
        Ok(())
    }
    /// Explicit trusted Service shutdown: invalidates every document output, not
    /// a client route to inspect or close another live owner's ordinary session.
    pub(crate) fn shutdown(&mut self) -> Result<()> {
        self.stopped = true;
        self.processing.clear();
        let result = self.host.close_all();
        self.reader_result(result)?;
        self.reads.clear();
        if self.evidence_cleanup_failed { return Err(failure("DOCUMENT_CLEANUP_REQUIRED")); }
        Ok(())
    }
    fn take_processing(&mut self, request: &DocumentEvidenceUseRequest) -> Result<ProcessingEntry> {
        self.ready()?;
        scope(&request.scope)?;
        identifier(&request.processing_id)?;
        self.processing.retain(|_, entry| !entry.expired());
        let entry = self.processing.get(&request.processing_id).ok_or_else(|| failure("DOCUMENT_EVIDENCE_SESSION_INVALIDATED"))?;
        same_scope(&entry.scope, &request.scope)?;
        self.processing.remove(&request.processing_id).ok_or_else(|| failure("DOCUMENT_EVIDENCE_SESSION_INVALIDATED"))
    }
    fn validate_query(&self, context: &DocumentEvidenceUseRequest, query_id: &str) -> Result<()> {
        self.ready()?;
        scope(&context.scope)?;
        identifier(&context.processing_id)?;
        identifier(query_id)?;
        let entry = self.processing.get(&context.processing_id).ok_or_else(|| failure("DOCUMENT_EVIDENCE_SESSION_INVALIDATED"))?;
        same_scope(&entry.scope, &context.scope)?;
        if entry.expired() { return Err(failure("DOCUMENT_EVIDENCE_SESSION_INVALIDATED")); }
        if entry.query.as_ref().map(|query| query.id.as_str()) != Some(query_id) {
            return Err(failure("DOCUMENT_EVIDENCE_QUERY_STALE"));
        }
        Ok(())
    }
    /// StoreEvidence's older adapter validates before cleanup. Gate owned output
    /// through the corrected PUBLIC facade; no nested transaction or delivery in
    /// its callback. Exact historical metadata must still match, never latest.
    fn deliver(&mut self, access: &DocumentAccess, expected: Option<&DocumentMetadata>, out: String) -> Result<String> {
        let result = self.host.store().with_document_source(access, DocumentReadPurpose::ReadText, 2_000_000, |view| {
            if expected.is_some_and(|metadata| metadata != view.metadata()) {
                return Err(ContractError::BindingMismatch);
            }
            Ok(out)
        });
        self.reader_result(result)
    }
    fn deliver_processing(&mut self, entry: &ProcessingEntry, out: String) -> Result<String> {
        let out = self.deliver(&entry.access, Some(entry.processing.source_metadata()), out)?;
        // Work and cleanup can cross the idle/absolute deadline. Check before
        // resetting touched or publishing, including error paths that drop entry.
        if entry.expired() { return Err(failure("DOCUMENT_EVIDENCE_SESSION_INVALIDATED")); }
        Ok(out)
    }
    pub(crate) fn process(&mut self, request: DocumentAccessRequest, kind: DocumentEvidenceKind) -> Result<String> {
        let access = self.access(&request)?;
        self.processing.retain(|_, entry| !entry.expired());
        if self.processing.len() >= MAX_PROCESSING { return Err(failure("DOCUMENT_LIMIT")); }
        let id = opaque_id("document-evidence")?;
        let result = StoreEvidence::new(self.host.store()).process(&access, kind.into());
        let processing = self.evidence_result(result)?;
        let out = encode(&json!({"schema":1,"status":"processed","processing_id":id,"projection":processing.projection()}))?;
        let out = self.deliver(&access, Some(processing.source_metadata()), out)?;
        let now = Instant::now();
        self.processing.insert(id, ProcessingEntry { scope: request.scope, access, processing, query: None, opened: now, touched: now });
        Ok(out)
    }
    pub(crate) fn query(&mut self, context: DocumentEvidenceUseRequest, query: String, limit: u32) -> Result<String> {
        if query.trim().is_empty() || query.len() > 4096 || query.contains('\0') || limit == 0 || limit as usize > MAX_HITS {
            return Err(failure("DOCUMENT_INVALID_REQUEST"));
        }
        let query_id = opaque_id("document-query")?;
        let mut entry = self.take_processing(&context)?;
        let result = StoreEvidence::new(self.host.store()).find_literal(&entry.access, &entry.processing, &query, limit as usize);
        let hits = self.evidence_result(result)?;
        let out = encode(&json!({"schema":1,"status":"queried","processing_id":context.processing_id,"query_id":query_id,"hits":hits}))?;
        entry.query = Some(QuerySnapshot { id: query_id, hits });
        let out = self.deliver_processing(&entry, out)?;
        entry.touched = Instant::now();
        self.processing.insert(context.processing_id, entry);
        Ok(out)
    }
    pub(crate) fn quote(&mut self, context: DocumentEvidenceUseRequest, query_id: String, evidence_id: String) -> Result<String> {
        self.validate_query(&context, &query_id)?;
        identifier(&evidence_id)?;
        let mut entry = self.take_processing(&context)?;
        let hit = entry.query.as_ref().and_then(|query| query.hits.iter().find(|hit| hit.evidence_id == evidence_id))
            .cloned().ok_or_else(|| failure("DOCUMENT_INVALID_REQUEST"))?;
        let result = StoreEvidence::new(self.host.store()).open(&entry.access, &entry.processing, &hit);
        let quote = self.evidence_result(result)?;
        let out = encode(&json!({"schema":1,"status":"quoted","processing_id":context.processing_id,"query_id":query_id,"evidence":hit,"quote":quote}))?;
        let out = self.deliver_processing(&entry, out)?;
        entry.touched = Instant::now();
        self.processing.insert(context.processing_id, entry);
        Ok(out)
    }
    pub(crate) fn answer(&mut self, request: DocumentEvidenceAnswerRequest) -> Result<String> {
        self.validate_query(&request.context, &request.query_id)?;
        if request.body.len() > 65536 || request.cited_indices.len() > MAX_HITS { return Err(failure("DOCUMENT_LIMIT")); }
        let mut entry = self.take_processing(&request.context)?;
        let hits = &entry.query.as_ref().ok_or_else(|| failure("DOCUMENT_EVIDENCE_QUERY_STALE"))?.hits;
        let indices: Vec<_> = request.cited_indices.iter().map(|index| *index as usize).collect();
        let result = StoreEvidence::new(self.host.store()).answer(&entry.access, &entry.processing, &request.body, hits, &indices);
        let answer = self.evidence_result(result)?;
        let out = encode(&json!({"schema":1,"status":"projected","processing_id":request.context.processing_id,"query_id":request.query_id,"answer":answer}))?;
        let out = self.deliver_processing(&entry, out)?;
        entry.touched = Instant::now();
        self.processing.insert(request.context.processing_id, entry);
        Ok(out)
    }
    pub(crate) fn close_evidence(&mut self, request: DocumentEvidenceUseRequest) -> Result<()> {
        scope(&request.scope)?;
        identifier(&request.processing_id)?;
        if let Some(entry) = self.processing.get(&request.processing_id) { same_scope(&entry.scope, &request.scope)?; }
        self.processing.remove(&request.processing_id);
        Ok(())
    }
}
