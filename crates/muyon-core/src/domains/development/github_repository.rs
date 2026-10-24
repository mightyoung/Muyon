//! Offline GitHub REST response adapter. The host owns transport, OAuth, access and revisions.
//!
//! This deliberately supports Actions workflow runs only. A workflow result is not proof of
//! required checks, individual jobs, external Checks/Statuses, or permission to execute a merge.
//! Fetch all pages for the current head between the two PR reads. Pagination headers must be
//! retained, including an absent Link header on the terminal response.

use super::repository_evidence::*;
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};

pub struct GitHubSnapshotContext {
    pub repository: RepositoryKey,
    pub authorization_generation: u64,
    pub revision: u64,
    pub pull_request_number: u64,
    /// Host-selected workflow IDs to observe. This is not GitHub branch-protection policy.
    /// An empty set or a missing workflow keeps CI capability unknown.
    pub expected_workflow_ids: Vec<u64>,
    /// Host-verified checkout evidence, obtained independently of workflow-run metadata.
    /// Never populate this from model output, caller assertions or `run.head_sha` alone.
    pub verified_run_subjects: Vec<VerifiedGitHubRunSubject>,
}

/// Trusted host input, intentionally not deserializable from provider/model response JSON.
/// The host must verify what the specific execution actually tested, including its PR
/// inputs, before constructing this value. The adapter cannot perform that verification.
pub struct VerifiedGitHubRunSubject {
    pub workflow_id: u64,
    pub run_id: u64,
    pub run_attempt: u64,
    pub observed_head_sha: String,
    pub observed_base_sha: String,
    pub subject: CiSubject,
}

/// Raw response body and pagination metadata from one successful REST request.
pub struct GitHubActionsPage<'a> {
    pub requested_url: &'a str,
    pub body: &'a str,
    pub link_header: Option<&'a str>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitHubAdapterError {
    InvalidResponse,
    IdentityMismatch,
    PullRequestChanged,
    IncompletePagination,
    ConflictingRun,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
struct Repo {
    id: u64,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
struct Branch {
    sha: String,
    repo: Repo,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
struct PullRequest {
    number: u64,
    state: String,
    merged: bool,
    merge_commit_sha: Option<String>,
    head: Branch,
    base: Branch,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
struct RunPullRequest {
    number: u64,
    head: Branch,
    base: Branch,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
struct WorkflowRun {
    id: u64,
    workflow_id: u64,
    run_number: u64,
    run_attempt: u64,
    head_sha: String,
    repository: Repo,
    pull_requests: Vec<RunPullRequest>,
    status: String,
    conclusion: Option<String>,
}

#[derive(Deserialize)]
struct RunsPage {
    total_count: usize,
    workflow_runs: Vec<WorkflowRun>,
}

/// Builds a snapshot without network requests or authorization side effects.
/// `pages` must cover a complete head-filtered Actions workflow-runs query. GitHub's
/// query result cap cannot prove completeness: a reported total larger than the supplied
/// distinct runs is rejected even if the final response has no next link.
pub fn snapshot_from_github_actions(
    context: GitHubSnapshotContext,
    pr_before: &str,
    pages: &[GitHubActionsPage<'_>],
    pr_after: &str,
) -> Result<RepositorySnapshot, GitHubAdapterError> {
    let before: PullRequest = parse(pr_before)?;
    let after: PullRequest = parse(pr_after)?;
    let repo_id = context.repository.repository_id.parse::<u64>().ok();
    if context.repository.provider != Provider::GitHub
        || context.pull_request_number == 0
        || repo_id != Some(before.base.repo.id)
        || before.base.repo.id == 0
        || before.number != context.pull_request_number
        || after.number != context.pull_request_number
        || repo_id != Some(after.base.repo.id)
    {
        return Err(GitHubAdapterError::IdentityMismatch);
    }
    if before != after {
        return Err(GitHubAdapterError::PullRequestChanged);
    }
    let state = match (before.state.as_str(), before.merged) {
        ("open", false) => PullRequestState::Open,
        ("closed", false) => PullRequestState::Closed,
        ("closed", true) => PullRequestState::Merged {
            merge_sha: before
                .merge_commit_sha
                .clone()
                .ok_or(GitHubAdapterError::InvalidResponse)?,
        },
        _ => return Err(GitHubAdapterError::InvalidResponse),
    };
    if pages.is_empty() {
        return Err(GitHubAdapterError::IncompletePagination);
    }
    let mut total_count = None;
    let mut requested_urls = BTreeSet::new();
    let mut runs = BTreeMap::<u64, WorkflowRun>::new();
    for (index, page) in pages.iter().enumerate() {
        if page.requested_url.trim().is_empty() || !requested_urls.insert(page.requested_url) {
            return Err(GitHubAdapterError::IncompletePagination);
        }
        let next = next_link(page.link_header)?;
        if next != pages.get(index + 1).map(|next| next.requested_url) {
            return Err(GitHubAdapterError::IncompletePagination);
        }
        let parsed: RunsPage = parse(page.body)?;
        if total_count.is_some_and(|total| total != parsed.total_count) {
            return Err(GitHubAdapterError::IncompletePagination);
        }
        total_count = Some(parsed.total_count);
        for run in parsed.workflow_runs {
            if run.id == 0 || run.workflow_id == 0 || run.run_number == 0 || run.run_attempt == 0 {
                return Err(GitHubAdapterError::InvalidResponse);
            }
            if run.repository.id != before.base.repo.id || run.head_sha != before.head.sha {
                return Err(GitHubAdapterError::IdentityMismatch);
            }
            // A head SHA alone is insufficient: the same commit can belong to another PR.
            // Empty PR references cannot establish this association and are rejected.
            if !run.pull_requests.iter().any(|pr| {
                pr.number == before.number && pr.head == before.head && pr.base == before.base
            }) {
                return Err(GitHubAdapterError::IdentityMismatch);
            }
            if runs.insert(run.id, run).is_some() {
                return Err(GitHubAdapterError::ConflictingRun);
            }
        }
    }
    if total_count != Some(runs.len()) {
        return Err(GitHubAdapterError::IncompletePagination);
    }
    let mut latest = BTreeMap::<u64, WorkflowRun>::new();
    for run in runs.into_values() {
        if let Some(previous) = latest.get(&run.workflow_id) {
            if previous.run_number == run.run_number {
                // A workflow run keeps its ID across attempts; conflicting IDs with the
                // same workflow/number are not an ordering signal.
                return Err(GitHubAdapterError::ConflictingRun);
            }
            if previous.run_number > run.run_number {
                continue;
            }
        }
        latest.insert(run.workflow_id, run);
    }
    let expected: BTreeSet<_> = context.expected_workflow_ids.iter().copied().collect();
    if expected.contains(&0) || expected.len() != context.expected_workflow_ids.len() {
        return Err(GitHubAdapterError::InvalidResponse);
    }
    let mut subjects = BTreeMap::new();
    for proof in &context.verified_run_subjects {
        let identity = (proof.workflow_id, proof.run_id, proof.run_attempt);
        if identity.0 == 0 || identity.1 == 0 || identity.2 == 0 {
            return Err(GitHubAdapterError::InvalidResponse);
        }
        if subjects.insert(identity, proof).is_some() {
            return Err(GitHubAdapterError::ConflictingRun);
        }
    }
    let verified_subject = |run: &WorkflowRun| {
        let proof = subjects.get(&(run.workflow_id, run.id, run.run_attempt))?;
        if proof.observed_head_sha != before.head.sha || proof.observed_base_sha != before.base.sha
        {
            return None;
        }
        match &proof.subject {
            CiSubject::Head { sha } if *sha == before.head.sha => Some(proof.subject.clone()),
            CiSubject::TestMerge {
                head_sha, base_sha, ..
            } if *head_sha == before.head.sha && *base_sha == before.base.sha => {
                Some(proof.subject.clone())
            }
            _ => None,
        }
    };
    let ci_capability = if !expected.is_empty()
        && expected
            .iter()
            .all(|id| latest.get(id).and_then(&verified_subject).is_some())
    {
        CiCapability::Available
    } else {
        CiCapability::Unknown
    };
    let checks = latest
        .into_values()
        .filter(|run| expected.contains(&run.workflow_id))
        .filter_map(|run| {
            Some(CiCheck {
                run_id: format!(
                    "github:workflow:{}:run:{}:attempt:{}",
                    run.workflow_id, run.id, run.run_attempt
                ),
                subject: verified_subject(&run)?,
                conclusion: conclusion(&run.status, run.conclusion.as_deref()),
            })
        })
        .collect();
    let snapshot = RepositorySnapshot {
        key: ObjectKey {
            repository: context.repository,
            object_id: context.pull_request_number.to_string(),
        },
        authorization_generation: context.authorization_generation,
        revision: context.revision,
        head_sha: before.head.sha,
        base_sha: before.base.sha,
        state,
        ci_capability,
        checks,
    };
    // Reuse the reducer's canonical validation; this does not grant access in the host store.
    let mut validation = RepositoryEvidenceStore::default();
    validation
        .set_access(
            snapshot.key.repository.clone(),
            snapshot.authorization_generation,
            true,
        )
        .and_then(|()| validation.consume(snapshot.clone()))
        .map_err(|_| GitHubAdapterError::InvalidResponse)?;
    Ok(snapshot)
}

fn parse<T: serde::de::DeserializeOwned>(body: &str) -> Result<T, GitHubAdapterError> {
    serde_json::from_str(body).map_err(|_| GitHubAdapterError::InvalidResponse)
}

fn conclusion(status: &str, result: Option<&str>) -> CiConclusion {
    match (status, result) {
        ("completed", Some("success")) => CiConclusion::Success,
        ("completed", Some("failure" | "timed_out" | "action_required" | "startup_failure")) => {
            CiConclusion::Failure
        }
        ("completed", Some("skipped")) => CiConclusion::Skipped,
        ("completed", Some("cancelled")) => CiConclusion::Cancelled,
        ("queued" | "in_progress" | "waiting" | "requested" | "pending", None) => {
            CiConclusion::Pending
        }
        _ => CiConclusion::Unknown,
    }
}

fn next_link(header: Option<&str>) -> Result<Option<&str>, GitHubAdapterError> {
    let mut next = None;
    for link in header.into_iter().flat_map(|value| value.split(',')) {
        let mut parts = link.trim().split(';');
        let target = parts.next().unwrap_or_default().trim();
        let url = target
            .strip_prefix('<')
            .and_then(|value| value.strip_suffix('>'))
            .filter(|value| !value.is_empty())
            .ok_or(GitHubAdapterError::IncompletePagination)?;
        for parameter in parts {
            if parameter.trim().strip_prefix("rel=").is_some_and(|rels| {
                rels.trim_matches('"')
                    .split_whitespace()
                    .any(|rel| rel == "next")
            }) && next.replace(url).is_some()
            {
                return Err(GitHubAdapterError::IncompletePagination);
            }
        }
    }
    Ok(next)
}
