use muyon_core::domains::development::{github_repository::*, repository_evidence::*};
use serde_json::{json, Value};

fn context() -> GitHubSnapshotContext {
    GitHubSnapshotContext {
        repository: RepositoryKey {
            provider: Provider::GitHub,
            instance: "github.com".into(),
            repository_id: "12".into(),
        },
        authorization_generation: 3,
        revision: 7,
        pull_request_number: 108,
        expected_workflow_ids: vec![42],
        verified_run_subjects: vec![VerifiedGitHubRunSubject {
            workflow_id: 42,
            run_id: 1001,
            run_attempt: 2,
            observed_head_sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
            observed_base_sha: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".into(),
            subject: CiSubject::Head {
                sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
            },
        }],
    }
}

fn pr() -> Value {
    json!({
        "number":108,"state":"open","merged":false,
        "merge_commit_sha":"cccccccccccccccccccccccccccccccccccccccc",
        "head":{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","repo":{"id":99}},
        "base":{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","repo":{"id":12}}
    })
}

fn run() -> Value {
    let pr = pr();
    json!({
        "id":1001,"workflow_id":42,"run_number":20,"run_attempt":2,
        "head_sha":pr["head"]["sha"],"repository":{"id":12},
        "pull_requests":[{"number":108,"head":pr["head"],"base":pr["base"]}],
        "status":"completed","conclusion":"success",
        "extra_provider_field":"accepted"
    })
}

fn snapshot(
    ctx: GitHubSnapshotContext,
    before: Value,
    runs: Vec<Value>,
    after: Value,
) -> Result<RepositorySnapshot, GitHubAdapterError> {
    let body = json!({"total_count":runs.len(),"workflow_runs":runs}).to_string();
    snapshot_from_github_actions(
        ctx,
        &before.to_string(),
        &[GitHubActionsPage {
            requested_url: "https://api.github.com/repos/owner/repo/actions/runs?head_sha=aaa",
            body: &body,
            link_header: None,
        }],
        &after.to_string(),
    )
}

fn assess(snapshot: RepositorySnapshot) -> CiAssessment {
    let key = snapshot.key.clone();
    let mut store = RepositoryEvidenceStore::default();
    store.set_access(key.repository.clone(), 3, true).unwrap();
    store.consume(snapshot).unwrap();
    store.project(&key).unwrap().unwrap().head_ci
}

#[test]
fn fork_head_and_raw_actions_fields_round_trip_through_existing_reducer() {
    let result = snapshot(context(), pr(), vec![run()], pr()).unwrap();
    assert_eq!(result.authorization_generation, 3);
    assert_eq!(result.revision, 7);
    assert_eq!(result.key.object_id, "108");
    assert_eq!(
        result.checks[0].run_id,
        "github:workflow:42:run:1001:attempt:2"
    );
    assert_eq!(result.state, PullRequestState::Open);
    assert_eq!(assess(result), CiAssessment::Success);
}

#[test]
fn only_merged_true_can_turn_merge_commit_sha_into_a_merge_fact() {
    let mut merged = pr();
    merged["state"] = json!("closed");
    merged["merged"] = json!(true);
    let result = snapshot(context(), merged.clone(), vec![run()], merged.clone()).unwrap();
    assert!(matches!(result.state, PullRequestState::Merged { .. }));
    merged["merge_commit_sha"] = Value::Null;
    assert_eq!(
        snapshot(context(), merged.clone(), vec![run()], merged),
        Err(GitHubAdapterError::InvalidResponse)
    );
    let mut closed = pr();
    closed["state"] = json!("closed");
    assert_eq!(
        snapshot(context(), closed.clone(), vec![run()], closed)
            .unwrap()
            .state,
        PullRequestState::Closed
    );
}

#[test]
fn changed_pr_reads_cannot_be_combined() {
    for path in ["head", "base"] {
        let mut after = pr();
        after[path]["sha"] = json!("dddddddddddddddddddddddddddddddddddddddd");
        assert_eq!(
            snapshot(context(), pr(), vec![run()], after),
            Err(GitHubAdapterError::PullRequestChanged)
        );
    }
    let mut after = pr();
    after["state"] = json!("closed");
    assert_eq!(
        snapshot(context(), pr(), vec![run()], after),
        Err(GitHubAdapterError::PullRequestChanged)
    );
}

#[test]
fn repository_number_sha_and_pr_association_are_required() {
    let mut ctx = context();
    ctx.repository.repository_id = "99".into();
    assert_eq!(
        snapshot(ctx, pr(), vec![run()], pr()),
        Err(GitHubAdapterError::IdentityMismatch)
    );
    let mut ctx = context();
    ctx.pull_request_number = 109;
    assert_eq!(
        snapshot(ctx, pr(), vec![run()], pr()),
        Err(GitHubAdapterError::IdentityMismatch)
    );
    for field in ["head_sha", "repository", "pull_requests"] {
        let mut wrong = run();
        wrong[field] = match field {
            "head_sha" => json!("dddddddddddddddddddddddddddddddddddddddd"),
            "repository" => json!({"id":99}),
            _ => json!([]),
        };
        assert_eq!(
            snapshot(context(), pr(), vec![wrong], pr()),
            Err(GitHubAdapterError::IdentityMismatch)
        );
    }
    let mut wrong = run();
    wrong["pull_requests"][0]["base"]["sha"] = json!("dddddddddddddddddddddddddddddddddddddddd");
    assert_eq!(
        snapshot(context(), pr(), vec![wrong], pr()),
        Err(GitHubAdapterError::IdentityMismatch)
    );
}

#[test]
fn only_completed_success_is_green() {
    for (status, conclusion, expected) in [
        ("completed", Some("failure"), CiAssessment::Failure),
        ("completed", Some("timed_out"), CiAssessment::Failure),
        ("completed", Some("skipped"), CiAssessment::Inconclusive),
        ("completed", Some("neutral"), CiAssessment::Inconclusive),
        ("completed", Some("cancelled"), CiAssessment::Inconclusive),
        ("completed", None, CiAssessment::Inconclusive),
        ("future_status", Some("success"), CiAssessment::Inconclusive),
        ("in_progress", Some("success"), CiAssessment::Inconclusive),
        ("queued", None, CiAssessment::Pending),
    ] {
        let mut value = run();
        value["status"] = json!(status);
        value["conclusion"] = json!(conclusion);
        assert_eq!(
            assess(snapshot(context(), pr(), vec![value], pr()).unwrap()),
            expected
        );
    }
}

#[test]
fn latest_workflow_run_replaces_old_green_and_retains_real_attempt() {
    let old = run();
    let mut latest = run();
    latest["id"] = json!(1002);
    latest["run_number"] = json!(21);
    latest["run_attempt"] = json!(1);
    latest["status"] = json!("in_progress");
    latest["conclusion"] = Value::Null;
    for runs in [vec![old.clone(), latest.clone()], vec![latest, old]] {
        let mut ctx = context();
        ctx.verified_run_subjects[0].run_id = 1002;
        ctx.verified_run_subjects[0].run_attempt = 1;
        let result = snapshot(ctx, pr(), runs, pr()).unwrap();
        assert_eq!(result.checks.len(), 1);
        assert!(result.checks[0].run_id.ends_with("1002:attempt:1"));
        assert_eq!(assess(result), CiAssessment::Pending);
    }
}

#[test]
fn successful_workflow_metadata_without_verified_checkout_never_proves_head_green() {
    let mut ctx = context();
    ctx.verified_run_subjects.clear();
    let result = snapshot(ctx, pr(), vec![run()], pr()).unwrap();
    assert!(result.checks.is_empty());
    assert_eq!(assess(result), CiAssessment::CapabilityUnknown);
}

#[test]
fn verified_test_merge_is_projected_separately_despite_identical_run_head_metadata() {
    let mut ctx = context();
    let subject = CiSubject::TestMerge {
        sha: "cccccccccccccccccccccccccccccccccccccccc".into(),
        head_sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".into(),
        base_sha: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".into(),
    };
    ctx.verified_run_subjects[0].subject = subject.clone();
    let snapshot = snapshot(ctx, pr(), vec![run()], pr()).unwrap();
    let key = snapshot.key.clone();
    let mut store = RepositoryEvidenceStore::default();
    store.set_access(key.repository.clone(), 3, true).unwrap();
    store.consume(snapshot).unwrap();
    let view = store.project(&key).unwrap().unwrap();
    assert_eq!(view.head_ci, CiAssessment::NoEvidence);
    assert_eq!(view.test_merge_checks.len(), 1);
    assert_eq!(view.test_merge_checks[0].subject, subject);
    assert_eq!(view.test_merge_checks[0].conclusion, CiConclusion::Success);
    assert_eq!(view.state, PullRequestState::Open);
}

#[test]
fn old_attempt_or_old_base_proof_cannot_bind_current_execution() {
    let mut newer_attempt = run();
    newer_attempt["run_attempt"] = json!(3);
    let result = snapshot(context(), pr(), vec![newer_attempt], pr()).unwrap();
    assert!(result.checks.is_empty());
    assert_eq!(assess(result), CiAssessment::CapabilityUnknown);

    let mut ctx = context();
    ctx.verified_run_subjects[0].observed_base_sha =
        "dddddddddddddddddddddddddddddddddddddddd".into();
    let result = snapshot(ctx, pr(), vec![run()], pr()).unwrap();
    assert!(result.checks.is_empty());
    assert_eq!(assess(result), CiAssessment::CapabilityUnknown);
}

#[test]
fn absent_or_unconfigured_workflows_never_prove_green() {
    assert_eq!(
        assess(snapshot(context(), pr(), vec![], pr()).unwrap()),
        CiAssessment::CapabilityUnknown
    );
    let mut ctx = context();
    ctx.expected_workflow_ids.push(43);
    assert_eq!(
        assess(snapshot(ctx, pr(), vec![run()], pr()).unwrap()),
        CiAssessment::CapabilityUnknown
    );
    let mut ctx = context();
    ctx.expected_workflow_ids.clear();
    let result = snapshot(ctx, pr(), vec![run()], pr()).unwrap();
    assert!(result.checks.is_empty());
    assert_eq!(assess(result), CiAssessment::CapabilityUnknown);
}

#[test]
fn pagination_follows_next_even_when_first_page_has_one_record() {
    let first = json!({"total_count":2,"workflow_runs":[run()]}).to_string();
    let mut second_run = run();
    second_run["id"] = json!(1002);
    second_run["workflow_id"] = json!(43);
    let second = json!({"total_count":2,"workflow_runs":[second_run]}).to_string();
    let before = pr().to_string();
    let pages = [
        GitHubActionsPage { requested_url:"https://api.github.com/page1",body:&first,link_header:Some("<https://api.github.com/page2>; rel=\"next\", <https://api.github.com/page2>; rel=\"last\"") },
        GitHubActionsPage { requested_url:"https://api.github.com/page2",body:&second,link_header:Some("<https://api.github.com/page1>; rel=\"prev\"") },
    ];
    assert!(snapshot_from_github_actions(context(), &before, &pages, &before).is_ok());
    assert_eq!(
        snapshot_from_github_actions(context(), &before, &pages[..1], &before),
        Err(GitHubAdapterError::IncompletePagination)
    );
}

#[test]
fn absent_next_does_not_hide_truncated_results_or_bad_chains() {
    let before = pr().to_string();
    let body = json!({"total_count":2,"workflow_runs":[run()]}).to_string();
    for link in [
        None,
        Some("broken"),
        Some("<https://api.github.com/missing>; rel=\"next\""),
    ] {
        assert_eq!(
            snapshot_from_github_actions(
                context(),
                &before,
                &[GitHubActionsPage {
                    requested_url: "https://api.github.com/page1",
                    body: &body,
                    link_header: link,
                }],
                &before
            ),
            Err(GitHubAdapterError::IncompletePagination)
        );
    }
    assert_eq!(
        snapshot_from_github_actions(context(), &before, &[], &before),
        Err(GitHubAdapterError::IncompletePagination)
    );
}

#[test]
fn malformed_ids_shas_and_conflicting_run_records_are_rejected() {
    for field in ["id", "workflow_id", "run_number", "run_attempt"] {
        let mut invalid = run();
        invalid[field] = json!(0);
        assert_eq!(
            snapshot(context(), pr(), vec![invalid], pr()),
            Err(GitHubAdapterError::InvalidResponse)
        );
    }
    assert_eq!(
        snapshot(context(), pr(), vec![run(), run()], pr()),
        Err(GitHubAdapterError::ConflictingRun)
    );
    let mut conflict = run();
    conflict["id"] = json!(1002);
    assert_eq!(
        snapshot(context(), pr(), vec![run(), conflict], pr()),
        Err(GitHubAdapterError::ConflictingRun)
    );
    let mut ctx = context();
    ctx.authorization_generation = 0;
    assert_eq!(
        snapshot(ctx, pr(), vec![run()], pr()),
        Err(GitHubAdapterError::InvalidResponse)
    );
    let mut invalid = pr();
    invalid["head"]["sha"] = json!("invalid");
    assert_eq!(
        snapshot(context(), invalid.clone(), vec![], invalid),
        Err(GitHubAdapterError::InvalidResponse)
    );
}
