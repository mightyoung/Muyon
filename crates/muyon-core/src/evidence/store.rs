//! Real owner adapter over BusinessStore. All delivered text and projections are
//! computed inside the same BEGIN IMMEDIATE transaction as persisted ReadText,
//! exact document-head, scope, epoch/generation/expiry and live reader checks.
use super::{
    local::{hash, MAX_BYTES},
    *,
};
use crate::{
    blobs::{ControlledReader, MAX_CHUNK},
    business::BusinessStore,
    contract::ContractError,
    documents::{
        AccessState, CurrentDocument, DocumentAccess, DocumentHost, DocumentMetadata,
        DocumentOperation, ReadInvalidation, ReadRequest,
    },
    sqlite::Transaction,
};
use serde::Serialize;
use std::cell::RefCell;

type Result<T> = std::result::Result<T, StoreEvidenceError>;
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum StoreEvidenceError {
    Core(ContractError),
    Processing(EvidenceError),
    /// Never publish a successful value if explicit reader cleanup failed.
    Cleanup {
        primary: Option<Box<StoreEvidenceError>>,
        cleanup: ContractError,
    },
}
fn sql<T>(value: crate::sqlite::Result<T>) -> Result<T> {
    value.map_err(|_| StoreEvidenceError::Core(ContractError::Storage))
}
fn core<T>(value: std::result::Result<T, ContractError>) -> Result<T> {
    value.map_err(StoreEvidenceError::Core)
}

/// Historical metadata from the real registered document row plus its actual
/// parser result. No import intent, saved-success flag or index confirmation is
/// synthesized. Repeated processing neither creates nor retries a business intent.
#[derive(Debug)]
pub struct StoredProcessing {
    metadata: DocumentMetadata,
    local: LocalEvidence,
}
#[derive(Serialize)]
pub struct StoredProcessingProjection<'a> {
    pub schema: &'static str,
    pub registered_source_snapshot: &'a DocumentMetadata,
    pub processing: &'a ProcessingReceipt,
}
impl StoredProcessing {
    pub fn source_metadata(&self) -> &DocumentMetadata {
        &self.metadata
    }
    pub fn receipt(&self) -> &ProcessingReceipt {
        self.local.receipt()
    }
    pub fn projection(&self) -> StoredProcessingProjection<'_> {
        StoredProcessingProjection {
            schema: "muyon.stored-processing.v1",
            registered_source_snapshot: &self.metadata,
            processing: self.receipt(),
        }
    }
}

/// Borrow from the trusted Service's existing BusinessStore guard. The store is
/// !Sync and its owner flock excludes a second managed writer; no new connection,
/// database, credential, permission policy or fake CurrentDocument is installed.
pub struct StoreEvidence<'a> {
    store: &'a BusinessStore,
}
impl<'a> StoreEvidence<'a> {
    pub fn new(store: &'a BusinessStore) -> Self {
        Self { store }
    }
    pub fn process(&self, access: &DocumentAccess, kind: InputKind) -> Result<StoredProcessing> {
        self.with_source(access, |host, request, bytes, metadata| {
            let local = process_local(host, request, kind, bytes)?;
            Ok(StoredProcessing {
                metadata: metadata.clone(),
                local,
            })
        })
    }
    pub fn find_literal(
        &self,
        access: &DocumentAccess,
        result: &StoredProcessing,
        query: &str,
        limit: usize,
    ) -> Result<Vec<EvidenceRef>> {
        self.with_source(access, |host, request, _, _| {
            result.local.find_literal(host, request, query, limit)
        })
    }
    pub fn open(
        &self,
        access: &DocumentAccess,
        result: &StoredProcessing,
        reference: &EvidenceRef,
    ) -> Result<String> {
        self.with_source(access, |host, request, _, _| {
            result.local.open(host, request, reference)
        })
    }
    pub fn answer(
        &self,
        access: &DocumentAccess,
        result: &StoredProcessing,
        body: &str,
        hits: &[EvidenceRef],
        cited_indices: &[usize],
    ) -> Result<AnswerEvidence> {
        self.with_source(access, |host, request, _, _| {
            result
                .local
                .answer(host, request, body, hits, cited_indices)
        })
    }

    fn with_source<T>(
        &self,
        access: &DocumentAccess,
        operation: impl FnOnce(
            &dyn DocumentHost,
            &ReadRequest,
            &[u8],
            &DocumentMetadata,
        ) -> std::result::Result<T, EvidenceError>,
    ) -> Result<T> {
        // The existing open_blob_reader owns its own transaction. Resolve the
        // registered blob under a short preliminary ReadText transaction, acquire
        // its controlled reader, then reauthorize everything in the final owner
        // transaction before any byte is delivered to the parser/caller. The
        // preliminary check is not the delivery authority or an atomicity claim.
        let initial = {
            let tx = sql(self.store.database().transaction())?;
            let metadata = core(self.store.document_access_in_transaction(
                &tx,
                access,
                &[DocumentOperation::ReadText],
            ))?;
            if metadata.blob.byte_length.value() > MAX_BYTES as u64 {
                return Err(StoreEvidenceError::Processing(EvidenceError::LimitExceeded));
            }
            sql(tx.commit())?;
            metadata
        };
        let project = access
            .document
            .scope()
            .project_id
            .as_deref()
            .ok_or(StoreEvidenceError::Core(ContractError::ScopeMismatch))?;
        let reader = RefCell::new(core(self.store.open_blob_reader(project, &initial.blob))?);
        let result = (|| {
            let tx = sql(self.store.database().transaction())?;
            let metadata = core(self.store.document_access_in_transaction(
                &tx,
                access,
                &[DocumentOperation::ReadText],
            ))?;
            if metadata != initial || reader.borrow().source().blob != metadata.blob {
                return Err(StoreEvidenceError::Core(ContractError::BindingMismatch));
            }
            let length = usize::try_from(metadata.blob.byte_length.value())
                .map_err(|_| StoreEvidenceError::Processing(EvidenceError::LimitExceeded))?;
            let mut bytes = Vec::with_capacity(length);
            while bytes.len() < length {
                let chunk = core(self.store.read_blob_chunk(
                    &mut reader.borrow_mut(),
                    MAX_CHUNK.min(length - bytes.len()),
                ))?;
                if chunk.is_empty() {
                    return Err(StoreEvidenceError::Core(ContractError::StorageCorrupt));
                }
                bytes.extend_from_slice(&chunk);
            }
            if hash(&bytes) != metadata.blob.digest {
                return Err(StoreEvidenceError::Core(ContractError::BindingMismatch));
            }
            let host = TransactionDocumentHost {
                store: self.store,
                tx: &tx,
                access,
                reader: &reader,
            };
            let request = ReadRequest {
                document: access.document.clone(),
                authority: access.authority.clone(),
                operation: DocumentOperation::ReadText,
                anchor: None,
            };
            let value = operation(&host, &request, &bytes, &metadata)
                .map_err(StoreEvidenceError::Processing)?;
            // Expiry can change with wall time even though concurrent owner
            // writes are excluded. Validate grant/head/lease at publication tail.
            host.resolve_current(&request)
                .map_err(|_| StoreEvidenceError::Processing(EvidenceError::Denied))?;
            sql(tx.commit())?;
            Ok(value)
        })();
        // This occurs only after final transaction commit/rollback. Core reader
        // cleanup cannot nest a transaction and it has no document side effects.
        match (result, self.store.close_blob_reader(reader.into_inner())) {
            (Ok(value), Ok(())) => Ok(value),
            (Err(error), Ok(())) => Err(error),
            (result, Err(cleanup)) => Err(StoreEvidenceError::Cleanup {
                primary: result.err().map(Box::new),
                cleanup,
            }),
        }
    }
}

/// Cannot escape the owner's live transaction or be constructed from wire data.
/// Its only permission is the operation actually checked in persistent SQL.
struct TransactionDocumentHost<'a, 'tx> {
    store: &'a BusinessStore,
    tx: &'a Transaction<'tx>,
    access: &'a DocumentAccess,
    reader: &'a RefCell<ControlledReader>,
}
impl DocumentHost for TransactionDocumentHost<'_, '_> {
    fn resolve_current(
        &self,
        request: &ReadRequest,
    ) -> std::result::Result<CurrentDocument, ReadInvalidation> {
        if request.document != self.access.document
            || request.authority != self.access.authority
            || request.operation != DocumentOperation::ReadText
            || request.anchor.is_some()
        {
            return Err(ReadInvalidation::PermissionDenied);
        }
        let metadata = self
            .store
            .document_access_in_transaction(self.tx, self.access, &[DocumentOperation::ReadText])
            .map_err(|_| ReadInvalidation::AuthorityUnavailable)?;
        // with_source fully consumes the controlled reader before constructing
        // this host. An EOF read reuses core's actual check_reader lease checks
        // (epoch, pin, generation, ready blob), without a duplicated SQL authority
        // implementation or new blob hook. A non-EOF result is never accepted.
        let mut reader = self.reader.borrow_mut();
        let source = reader.source().clone();
        if source.blob != metadata.blob {
            return Err(ReadInvalidation::DocumentMismatch);
        }
        let eof = self
            .store
            .read_blob_chunk(&mut reader, 1)
            .map_err(|_| ReadInvalidation::AuthorityUnavailable)?;
        if !eof.is_empty() {
            return Err(ReadInvalidation::HostUnavailable);
        }
        Ok(CurrentDocument {
            document: metadata.document,
            authority: self.access.authority.clone(),
            access: AccessState::Active,
            source,
            permissions: vec![DocumentOperation::ReadText],
        })
    }
}
#[cfg(test)]
#[path = "store_tests.rs"]
mod tests;
