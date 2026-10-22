//! Provisional in-memory domain seam, not a DTO, authorization or persistence API.
use unicode_normalization::UnicodeNormalization;

#[derive(Debug, PartialEq, Eq)]
pub enum DomainError {
    RawLimit,
    InvalidXml,
    Required,
    NameLimit,
    Scope,
    Missing,
    Revision,
    RevisionOverflow,
}

/// A caller-supplied synthetic snapshot. Fields are not validated product IDs.
/// Scope equality here is a pure precondition, not proof of read/write authority.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProvisionalSnapshot {
    pub scope: String,
    pub supplier_id: String,
    pub name: String,
    pub revision: u64,
    pub deleted: bool,
}

/// Preview only: candidate_revision is hypothetical, never evidence of a commit.
#[derive(Debug, PartialEq, Eq)]
pub struct ProvisionalEditCandidate {
    pub supplier_id: String,
    pub scope: String,
    pub normalized_name: String,
    pub expected_revision: u64,
    pub candidate_revision: u64,
}

/// Receives the complete raw UTF-16 input, including invalid surrogate sequences.
pub fn normalize_raw(raw: &[u16]) -> Result<String, DomainError> {
    if raw.len() > 2000 {
        return Err(DomainError::RawLimit);
    }
    let decoded = String::from_utf16(raw).map_err(|_| DomainError::InvalidXml)?;
    if !decoded.chars().all(|c| matches!(c as u32,
        0x9 | 0xa | 0xd | 0x20..=0xd7ff | 0xe000..=0xfffd | 0x10000..=0x10ffff
    )) {
        return Err(DomainError::InvalidXml);
    }
    let normalized: String = decoded
        .trim_matches(|c: char| c.is_whitespace() || c == '\u{feff}')
        .nfc()
        .collect();
    if normalized.is_empty() {
        return Err(DomainError::Required);
    }
    if normalized.chars().count() > 200 {
        return Err(DomainError::NameLimit);
    }
    Ok(normalized)
}

pub fn read_name<'a>(
    snapshot: &'a ProvisionalSnapshot,
    scope: &str,
    id: &str,
) -> Result<&'a str, DomainError> {
    if snapshot.scope != scope || snapshot.supplier_id != id {
        return Err(DomainError::Scope);
    }
    if snapshot.deleted {
        return Err(DomainError::Missing);
    }
    Ok(&snapshot.name)
}

/// Pure candidate validation. The stored snapshot remains untouched on all paths.
/// Same-name candidates suggest +1; intent/replay, CAS and receipts need a real
/// transactional adapter and are deliberately not simulated as committed here.
pub fn edit_candidate(
    snapshot: &ProvisionalSnapshot,
    scope: &str,
    id: &str,
    expected_revision: u64,
    raw: &[u16],
) -> Result<ProvisionalEditCandidate, DomainError> {
    read_name(snapshot, scope, id)?;
    if expected_revision == 0 || snapshot.revision != expected_revision {
        return Err(DomainError::Revision);
    }
    let normalized_name = normalize_raw(raw)?;
    let candidate_revision = expected_revision
        .checked_add(1)
        .ok_or(DomainError::RevisionOverflow)?;
    Ok(ProvisionalEditCandidate {
        supplier_id: snapshot.supplier_id.clone(),
        scope: snapshot.scope.clone(),
        normalized_name,
        expected_revision,
        candidate_revision,
    })
}
