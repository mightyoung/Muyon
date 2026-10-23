//! Pure consumption of reconciled repository snapshots; no transport or business mutations.
//!
//! The host supplies access generations. A connector must reconcile raw provider events into
//! complete snapshots with a monotonic revision per object and access generation. Provider
//! timestamps, webhook delivery order, CI success and merge facts do not grant authority.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Provider {
    GitHub,
    GitLab,
    Gitee,
}

/// Canonical identities supplied by the host; names are not fuzzy matched or URL guessed.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RepositoryKey {
    pub provider: Provider,
    pub instance: String,
    pub repository_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ObjectKey {
    pub repository: RepositoryKey,
    /// PR/MR number or stable provider ID within the repository, normalized by the adapter.
    pub object_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", deny_unknown_fields)]
pub enum PullRequestState {
    Open,
    Closed,
    Merged { merge_sha: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CiCapability {
    Available,
    Missing,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CiConclusion {
    Pending,
    Success,
    Failure,
    Skipped,
    Cancelled,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", deny_unknown_fields)]
pub enum CiSubject {
    Head {
        sha: String,
    },
    /// A synthetic test commit and its exact two inputs; never evidence of actual merge.
    TestMerge {
        sha: String,
        head_sha: String,
        base_sha: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CiCheck {
    pub run_id: String,
    pub subject: CiSubject,
    pub conclusion: CiConclusion,
}

/// Full replacement snapshot. `checks` is the reconciled current set, not incremental events.
/// Missing checks cannot prove that branch protection or a required-check policy is satisfied.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RepositorySnapshot {
    pub key: ObjectKey,
    pub authorization_generation: u64,
    pub revision: u64,
    pub head_sha: String,
    pub base_sha: String,
    pub state: PullRequestState,
    pub ci_capability: CiCapability,
    pub checks: Vec<CiCheck>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CiAssessment {
    /// Only the supplied head checks succeeded; no acceptance/mergeability claim is implied.
    Success,
    Failure,
    Pending,
    Inconclusive,
    Stale,
    NoEvidence,
    CapabilityMissing,
    CapabilityUnknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RepositoryEvidenceView {
    pub head_sha: String,
    pub state: PullRequestState,
    pub head_ci: CiAssessment,
    /// Current-head synthetic checks, retaining tested SHA and parents for separate display.
    pub test_merge_checks: Vec<CiCheck>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvidenceError {
    InvalidInput,
    AccessDenied,
    AccessGeneration,
    RevisionConflict,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConsumeResult {
    Applied,
    Duplicate,
    Outdated,
}

#[derive(Debug, Clone)]
struct Access {
    generation: u64,
    readable: bool,
}

#[derive(Debug, Default)]
pub struct RepositoryEvidenceStore {
    access: BTreeMap<RepositoryKey, Access>,
    snapshots: BTreeMap<ObjectKey, RepositorySnapshot>,
}

impl RepositoryEvidenceStore {
    /// Host-only access input, independent of any provider event. Any generation change
    /// invalidates all retained repository objects, including a revoke followed by regrant.
    pub fn set_access(
        &mut self,
        repository: RepositoryKey,
        generation: u64,
        readable: bool,
    ) -> Result<(), EvidenceError> {
        if !valid_repository(&repository) || generation == 0 {
            return Err(EvidenceError::InvalidInput);
        }
        if self
            .access
            .get(&repository)
            .is_some_and(|access| generation <= access.generation)
        {
            return Err(EvidenceError::AccessGeneration);
        }
        self.snapshots.retain(|key, _| key.repository != repository);
        self.access.insert(
            repository,
            Access {
                generation,
                readable,
            },
        );
        Ok(())
    }

    pub fn consume(
        &mut self,
        mut snapshot: RepositorySnapshot,
    ) -> Result<ConsumeResult, EvidenceError> {
        validate_snapshot(&snapshot)?;
        snapshot
            .checks
            .sort_by(|left, right| left.run_id.cmp(&right.run_id));
        let access = self.readable_access(&snapshot.key.repository)?;
        if access.generation != snapshot.authorization_generation {
            return Err(EvidenceError::AccessGeneration);
        }
        if let Some(previous) = self.snapshots.get(&snapshot.key) {
            if snapshot.revision < previous.revision {
                return Ok(ConsumeResult::Outdated);
            }
            if snapshot.revision == previous.revision {
                return if snapshot == *previous {
                    Ok(ConsumeResult::Duplicate)
                } else {
                    Err(EvidenceError::RevisionConflict)
                };
            }
        }
        self.snapshots.insert(snapshot.key.clone(), snapshot);
        Ok(ConsumeResult::Applied)
    }

    pub fn project(
        &self,
        key: &ObjectKey,
    ) -> Result<Option<RepositoryEvidenceView>, EvidenceError> {
        self.readable_access(&key.repository)?;
        Ok(self
            .snapshots
            .get(key)
            .map(|snapshot| RepositoryEvidenceView {
                head_sha: snapshot.head_sha.clone(),
                state: snapshot.state.clone(),
                head_ci: assess_head(snapshot),
                test_merge_checks: if snapshot.ci_capability == CiCapability::Available {
                    snapshot
                        .checks
                        .iter()
                        .filter(|check| {
                            matches!(&check.subject, CiSubject::TestMerge { head_sha, base_sha, .. }
                        if *head_sha == snapshot.head_sha && *base_sha == snapshot.base_sha)
                        })
                        .cloned()
                        .collect()
                } else {
                    Vec::new()
                },
            }))
    }

    fn readable_access(&self, repository: &RepositoryKey) -> Result<&Access, EvidenceError> {
        self.access
            .get(repository)
            .filter(|access| access.readable)
            .ok_or(EvidenceError::AccessDenied)
    }
}

fn valid_id(value: &str) -> bool {
    !value.trim().is_empty() && !value.chars().any(char::is_control)
}

fn valid_repository(repository: &RepositoryKey) -> bool {
    valid_id(&repository.instance) && valid_id(&repository.repository_id)
}

fn valid_sha(sha: &str) -> bool {
    matches!(sha.len(), 40 | 64)
        && sha
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn validate_snapshot(snapshot: &RepositorySnapshot) -> Result<(), EvidenceError> {
    if !valid_repository(&snapshot.key.repository)
        || !valid_id(&snapshot.key.object_id)
        || snapshot.authorization_generation == 0
        || snapshot.revision == 0
        || !valid_sha(&snapshot.head_sha)
        || !valid_sha(&snapshot.base_sha)
    {
        return Err(EvidenceError::InvalidInput);
    }
    if matches!(&snapshot.state, PullRequestState::Merged { merge_sha } if !valid_sha(merge_sha)) {
        return Err(EvidenceError::InvalidInput);
    }
    let mut runs = BTreeSet::new();
    for check in &snapshot.checks {
        if !valid_id(&check.run_id) || !runs.insert(&check.run_id) {
            return Err(EvidenceError::InvalidInput);
        }
        let valid_subject = match &check.subject {
            CiSubject::Head { sha } => valid_sha(sha),
            CiSubject::TestMerge {
                sha,
                head_sha,
                base_sha,
            } => {
                valid_sha(sha)
                    && valid_sha(head_sha)
                    && valid_sha(base_sha)
                    && sha != head_sha
                    && sha != base_sha
            }
        };
        if !valid_subject {
            return Err(EvidenceError::InvalidInput);
        }
    }
    Ok(())
}

fn assess_head(snapshot: &RepositorySnapshot) -> CiAssessment {
    match snapshot.ci_capability {
        CiCapability::Missing => return CiAssessment::CapabilityMissing,
        CiCapability::Unknown => return CiAssessment::CapabilityUnknown,
        CiCapability::Available => {}
    }
    let current: Vec<_> = snapshot
        .checks
        .iter()
        .filter(
            |check| matches!(&check.subject, CiSubject::Head { sha } if *sha == snapshot.head_sha),
        )
        .map(|check| check.conclusion)
        .collect();
    if current.is_empty() {
        return if snapshot
            .checks
            .iter()
            .any(|check| matches!(check.subject, CiSubject::Head { .. }))
        {
            CiAssessment::Stale
        } else {
            CiAssessment::NoEvidence
        };
    }
    if current.contains(&CiConclusion::Failure) {
        CiAssessment::Failure
    } else if current.contains(&CiConclusion::Pending) {
        CiAssessment::Pending
    } else if current
        .iter()
        .all(|conclusion| *conclusion == CiConclusion::Success)
    {
        CiAssessment::Success
    } else {
        CiAssessment::Inconclusive
    }
}
