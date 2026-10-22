//! MIG16: bounded offline extraction and evidence projection, not a document store.
//! Text offsets are UTF-8 bytes. PDF pages are never inferred from text offsets.
//! No durable import/save/index completion is implied by a processing receipt.
use crate::{
    contract::{AuthorityBinding, BlobRef},
    documents::*,
};
use serde::Serialize;
use sha2::{Digest, Sha256};

const MAX_BYTES: usize = 2_000_000;
const MAX_HITS: usize = 100;
const PROCESSOR: &str = "muyon.local-utf8-literal.v1";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum InputKind {
    Utf8Text,
    Pdf,
    Ocr,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ProcessingState {
    Available,
    Unsupported,
    Failed,
    NotRun,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LocalEvent {
    ExtractionStarted,
    Extracted,
    ExtractionFailed,
    Unsupported,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Failure {
    InvalidUtf8,
    EmptyText,
    NulText,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum EvidenceError {
    Denied,
    SourceMismatch,
    InvalidRequest,
    InvalidAnchor,
    NotAvailable,
    LimitExceeded,
}

/// Same immutable document identity and blob digest as core, no alternate store.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SourceVersion {
    pub document: DocumentRef,
    pub blob: BlobRef,
}
#[derive(Clone, Debug, Serialize)]
pub struct ProcessingReceipt {
    /// Deterministic processing identity, not a business intent/commit receipt.
    pub receipt_id: String,
    pub schema: &'static str,
    pub processor: &'static str,
    pub source_id: String,
    pub source: SourceVersion,
    pub input_kind: InputKind,
    pub extraction: ProcessingState,
    /// Existing Android ResearchIndex remains the sole vector index owner.
    pub index: ProcessingState,
    pub failure: Option<Failure>,
    pub events: Vec<LocalEvent>,
}
/// A literal passage reference, not a claim verification or an approval token.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct EvidenceRef {
    pub evidence_id: String,
    pub source_id: String,
    pub source: SourceVersion,
    pub start_byte: usize,
    pub end_byte: usize,
    pub quote_digest: String,
    pub page_index_zero_based: Option<u32>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ClaimSupport {
    Unassessed,
}
#[derive(Clone, Debug, Serialize)]
pub struct Citation {
    pub number: usize,
    pub evidence: EvidenceRef,
    pub support: ClaimSupport,
}
#[derive(Clone, Debug, Serialize)]
pub struct AnswerEvidence {
    pub schema: &'static str,
    pub body: String,
    pub citations: Vec<Citation>,
    pub candidates: Vec<EvidenceRef>,
    /// Distinct cited source identities only, never number of passages.
    /// This local projection has one original source and makes no claim about
    /// independence of external copies or reprints.
    pub distinct_cited_source_count: usize,
    /// Unknown: a local passage cannot establish independent corroboration.
    pub independent_support_count: Option<usize>,
}

/// Ephemeral derived text. Private fields, no deserialization or unguarded text getter.
pub struct LocalEvidence {
    receipt: ProcessingReceipt,
    authority: AuthorityBinding,
    text: Option<String>,
}
impl std::fmt::Debug for LocalEvidence {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("LocalEvidence")
            .field("receipt", &self.receipt)
            .finish_non_exhaustive()
    }
}
fn hash(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}
fn source_id(source: &SourceVersion) -> Result<String, EvidenceError> {
    let bytes = serde_json::to_vec(source).map_err(|_| EvidenceError::InvalidRequest)?;
    Ok(format!("source-{}", hash(&bytes)))
}
fn evidence_id(source_id: &str, start: usize, end: usize, digest: &str) -> String {
    // All fields have bounded alphabets; separators cannot collide.
    format!(
        "evidence-{}",
        hash(format!("{source_id}:{start}:{end}:{digest}").as_bytes())
    )
}

/// Synchronous authorization at every derived data use. Host must resolve current
/// actor membership, exact resource/grant and lease in its owner transaction.
/// No client-provided capability matrix can turn Unknown into permission.
fn authorize(
    host: &dyn DocumentHost,
    request: &ReadRequest,
) -> Result<SourceVersion, EvidenceError> {
    // Anchored requests must not expand to read the whole document.
    if request.operation != DocumentOperation::ReadText || request.anchor.is_some() {
        return Err(EvidenceError::InvalidRequest);
    }
    let current = host
        .resolve_current(request)
        .map_err(|_| EvidenceError::Denied)?;
    if current.document != request.document {
        return Err(EvidenceError::SourceMismatch);
    }
    let id_ok = |id: &str| {
        !id.is_empty()
            && id.len() <= 128
            && id
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
    };
    if current.document.revision().value() == 0
        || current.access != AccessState::Active
        || current.authority != request.authority
        || !id_ok(&current.authority.grant_id)
        || !id_ok(&current.authority.owner_epoch)
        || current.authority.generation.value() == 0
        || !current.permissions.contains(&DocumentOperation::ReadText)
        || current.source.validate().is_err()
        || current.source.lease.owner_epoch != current.authority.owner_epoch
    {
        return Err(EvidenceError::Denied);
    }
    Ok(SourceVersion {
        document: current.document,
        blob: current.source.blob,
    })
}

/// Caller supplies bytes obtained through existing controlled blob reads. Digest
/// and exact byte length bind the bytes to the freshly authorized core resource.
/// The host must serialize this call against revocation (no await/cached grants).
/// UTF8 mode is explicit and requires Unknown core format until core adds Text.
/// This function never opens a path, writes a file or marks an import saved.
pub fn process_local(
    host: &dyn DocumentHost,
    request: &ReadRequest,
    kind: InputKind,
    bytes: &[u8],
) -> Result<LocalEvidence, EvidenceError> {
    let source = authorize(host, request)?;
    if bytes.len() > MAX_BYTES {
        return Err(EvidenceError::LimitExceeded);
    }
    if bytes.len() as u64 != source.blob.byte_length.value() || hash(bytes) != source.blob.digest {
        return Err(EvidenceError::SourceMismatch);
    }
    let id = source_id(&source)?;
    let processing_key =
        serde_json::to_vec(&(PROCESSOR, &id, kind)).map_err(|_| EvidenceError::InvalidRequest)?;
    let receipt_id = format!("processing-{}", hash(&processing_key));
    let mut receipt = ProcessingReceipt {
        receipt_id,
        schema: "muyon.processing-receipt.v1",
        processor: PROCESSOR,
        source_id: id,
        source,
        input_kind: kind,
        extraction: ProcessingState::Unsupported,
        index: ProcessingState::NotRun,
        failure: None,
        events: vec![],
    };
    let mut text = None;
    if kind != InputKind::Utf8Text {
        receipt.events.push(LocalEvent::Unsupported);
    } else {
        if request.document.format() != DocumentFormat::Unknown {
            return Err(EvidenceError::InvalidRequest);
        }
        receipt.events.push(LocalEvent::ExtractionStarted);
        let parsed = std::str::from_utf8(bytes)
            .map_err(|_| Failure::InvalidUtf8)
            .and_then(|value| {
                if value.contains('\0') {
                    Err(Failure::NulText)
                } else if value.trim().is_empty() {
                    Err(Failure::EmptyText)
                } else {
                    Ok(value)
                }
            });
        match parsed {
            Ok(value) => {
                receipt.extraction = ProcessingState::Available;
                receipt.events.push(LocalEvent::Extracted);
                text = Some(value.to_owned());
            }
            Err(error) => {
                receipt.extraction = ProcessingState::Failed;
                receipt.failure = Some(error);
                receipt.events.push(LocalEvent::ExtractionFailed);
            }
        }
    }
    // A host changing identity while supplying bytes must not publish a result.
    if authorize(host, request)? != receipt.source {
        return Err(EvidenceError::SourceMismatch);
    }
    Ok(LocalEvidence {
        receipt,
        authority: request.authority.clone(),
        text,
    })
}
impl LocalEvidence {
    /// Historical processing metadata only, never proof of current access/save.
    pub fn receipt(&self) -> &ProcessingReceipt {
        &self.receipt
    }
    fn check(&self, host: &dyn DocumentHost, request: &ReadRequest) -> Result<(), EvidenceError> {
        if self.authority != request.authority {
            return Err(EvidenceError::Denied);
        }
        if authorize(host, request)? != self.receipt.source {
            return Err(EvidenceError::SourceMismatch);
        }
        Ok(())
    }
    fn passage<'a>(&'a self, reference: &EvidenceRef) -> Result<&'a str, EvidenceError> {
        let text = self.text.as_deref().ok_or(EvidenceError::NotAvailable)?;
        if reference.source != self.receipt.source
            || reference.source_id != self.receipt.source_id
            || reference.page_index_zero_based.is_some()
            || reference.start_byte >= reference.end_byte
        {
            return Err(EvidenceError::InvalidAnchor);
        }
        let quote = text
            .get(reference.start_byte..reference.end_byte)
            .ok_or(EvidenceError::InvalidAnchor)?;
        if hash(quote.as_bytes()) != reference.quote_digest
            || reference.evidence_id
                != evidence_id(
                    &reference.source_id,
                    reference.start_byte,
                    reference.end_byte,
                    &reference.quote_digest,
                )
        {
            return Err(EvidenceError::InvalidAnchor);
        }
        Ok(quote)
    }
    /// Bounded direct literal scan, not semantic retrieval or a second index.
    pub fn find_literal(
        &self,
        host: &dyn DocumentHost,
        request: &ReadRequest,
        query: &str,
        limit: usize,
    ) -> Result<Vec<EvidenceRef>, EvidenceError> {
        self.check(host, request)?;
        if query.trim().is_empty()
            || query.len() > 4096
            || query.contains('\0')
            || limit == 0
            || limit > MAX_HITS
        {
            return Err(EvidenceError::InvalidRequest);
        }
        let text = self.text.as_deref().ok_or(EvidenceError::NotAvailable)?;
        let result = text
            .match_indices(query)
            .take(limit)
            .map(|(start, quote)| {
                let end = start + quote.len();
                let digest = hash(quote.as_bytes());
                EvidenceRef {
                    evidence_id: evidence_id(&self.receipt.source_id, start, end, &digest),
                    source_id: self.receipt.source_id.clone(),
                    source: self.receipt.source.clone(),
                    start_byte: start,
                    end_byte: end,
                    quote_digest: digest,
                    page_index_zero_based: None,
                }
            })
            .collect();
        self.check(host, request)?;
        Ok(result)
    }
    /// Returns an owned excerpt, with permission checked again before delivery.
    pub fn open(
        &self,
        host: &dyn DocumentHost,
        request: &ReadRequest,
        reference: &EvidenceRef,
    ) -> Result<String, EvidenceError> {
        self.check(host, request)?;
        let quote = self.passage(reference)?.to_owned();
        self.check(host, request)?;
        Ok(quote)
    }
    /// Explicit citation selection. Never derives citations from body markup or
    /// automatically promotes all retrieval candidates to supporting evidence.
    /// Citation numbers follow supplied selection order. Rebuilds produce a new
    /// immutable projection; streaming callers must retain this projection.
    pub fn answer(
        &self,
        host: &dyn DocumentHost,
        request: &ReadRequest,
        body: &str,
        hits: &[EvidenceRef],
        cited_indices: &[usize],
    ) -> Result<AnswerEvidence, EvidenceError> {
        self.check(host, request)?;
        if body.len() > MAX_BYTES || hits.len() > MAX_HITS || cited_indices.len() > MAX_HITS {
            return Err(EvidenceError::LimitExceeded);
        }
        for (index, hit) in hits.iter().enumerate() {
            self.passage(hit)?;
            if hits[..index]
                .iter()
                .any(|old| old.evidence_id == hit.evidence_id)
            {
                return Err(EvidenceError::InvalidRequest);
            }
        }
        let mut citations = Vec::new();
        for (number, &index) in cited_indices.iter().enumerate() {
            if cited_indices[..number].contains(&index) {
                return Err(EvidenceError::InvalidRequest);
            }
            let hit = hits.get(index).ok_or(EvidenceError::InvalidRequest)?;
            citations.push(Citation {
                number: number + 1,
                evidence: hit.clone(),
                support: ClaimSupport::Unassessed,
            });
        }
        let candidates = hits
            .iter()
            .enumerate()
            .filter(|(index, _)| !cited_indices.contains(index))
            .map(|(_, hit)| hit.clone())
            .collect();
        self.check(host, request)?;
        Ok(AnswerEvidence {
            schema: "muyon.answer-evidence.v1",
            body: body.into(),
            distinct_cited_source_count: usize::from(!citations.is_empty()),
            independent_support_count: None,
            citations,
            candidates,
        })
    }
}
