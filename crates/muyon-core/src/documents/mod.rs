//! Offline public document contracts only. No engine, file IO, DB or model calls.
//!
//! A valid reference/anchor/capability declaration never proves actual file
//! reading, rendering, target resolution, editing or native format fidelity.
pub mod anchor;
pub mod capability;
pub mod identity;
pub mod annotation;
pub mod storage;
use crate::contract::{AuthorityBinding, FileSource};
pub use anchor::*;
pub use capability::*;
pub use identity::DocumentRef;
pub use annotation::*;
pub use storage::{DocumentAccess, DocumentMetadata};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReadInvalidation {
    InvalidIdentity,
    ScopeMismatch,
    DocumentMismatch,
    StaleRevision,
    FormatMismatch,
    AuthorityUnavailable,
    PermissionDenied,
    CapabilityUnavailable,
    HostUnavailable,
    InvalidAnchor,
    AnchorUnresolved,
    NotAReadOperation,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AccessState {
    Active,
    Revoked,
    Unknown,
}

/// Not deserializable. Created by the trusted host from current session/grant
/// and handle resolution, never from model-produced metadata. Permissions are
/// the host-computed intersection of current actor, scope and resource grants.
#[derive(Clone, Debug)]
pub struct CurrentDocument {
    pub document: DocumentRef,
    pub authority: AuthorityBinding,
    pub access: AccessState,
    pub source: FileSource,
    pub permissions: Vec<DocumentOperation>,
}
#[derive(Clone, Debug)]
pub struct ReadRequest {
    pub document: DocumentRef,
    pub authority: AuthorityBinding,
    pub operation: DocumentOperation,
    pub anchor: Option<DocumentAnchor>,
}

/// Required trusted boundary; no default resolver. Resolve opaque IDs through
/// a host table, with exact current revision, scope, grant generation/epoch and
/// source lease. Re-check membership/revocation for every derived/cache access.
/// No arbitrary path/URL, SDK, credential, macro or outbound permission is implied.
pub trait DocumentHost {
    fn resolve_current(&self, request: &ReadRequest) -> Result<CurrentDocument, ReadInvalidation>;
}

/// Pure preflight, not a capability token. Each call consults the host afresh.
/// A future byte-delivery API MUST enforce the same checks atomically at use;
/// calling this once and later serving cached bytes is explicitly insufficient.
pub fn validate_read(
    host: &dyn DocumentHost,
    request: &ReadRequest,
    capabilities: &CapabilityMatrix,
) -> Result<(), ReadInvalidation> {
    if !request.operation.is_read() {
        return Err(ReadInvalidation::NotAReadOperation);
    }
    let current = host.resolve_current(request)?;
    request.document.matches(&current.document)?;
    let binding = &current.authority;
    if current.access != AccessState::Active
        || binding != &request.authority
        || !identity::valid_id(&binding.grant_id)
        || !identity::valid_id(&binding.owner_epoch)
        || binding.generation.value() == 0
        || current.source.validate().is_err()
        || current.source.lease.owner_epoch != binding.owner_epoch
    {
        return Err(ReadInvalidation::AuthorityUnavailable);
    }
    if !current.permissions.contains(&request.operation) {
        return Err(ReadInvalidation::PermissionDenied);
    }
    if !matches!(
        capabilities.status(current.document.format(), request.operation),
        CapabilityStatus::Supported | CapabilityStatus::ReadOnly
    ) {
        return Err(ReadInvalidation::CapabilityUnavailable);
    }
    if let Some(anchor) = &request.anchor {
        if anchor.validate_for(&current.document)? == AnchorStatus::UnresolvedGeometry {
            return Err(ReadInvalidation::AnchorUnresolved);
        }
    }
    Ok(())
}

/// DOC-02 interface only. Unknown is not acceptance; no detector is installed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SafetyStatus {
    Unknown,
    Rejected,
    Accepted,
}
pub trait DocumentSafety {
    fn check(&self, document: &DocumentRef, source: &FileSource) -> SafetyStatus;
}

/// DOC-06 expected base only. Future transaction owner must authenticate the
/// current binding and perform CAS against document revision before publication.
/// This is neither a write grant nor a transaction, success receipt or rollback.
#[derive(Clone, Debug)]
pub struct RevisionPrecondition {
    pub document: DocumentRef,
    pub authority: AuthorityBinding,
}
