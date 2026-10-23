use muyon_core::domains::development::repository_evidence::*;

fn fixtures() -> Vec<RepositorySnapshot> {
    serde_json::from_str(include_str!(
        "../../../docs/contracts/development/fixtures/repository-evidence.json"
    ))
    .unwrap()
}

fn store(snapshot: &RepositorySnapshot) -> RepositoryEvidenceStore {
    let mut store = RepositoryEvidenceStore::default();
    store
        .set_access(snapshot.key.repository.clone(), 1, true)
        .unwrap();
    store
}

#[test]
fn all_provider_fixtures_are_consumed_as_repository_facts() {
    for snapshot in fixtures() {
        let mut store = store(&snapshot);
        assert_eq!(store.consume(snapshot.clone()), Ok(ConsumeResult::Applied));
        let view = store.project(&snapshot.key).unwrap().unwrap();
        assert_eq!(view.head_sha, snapshot.head_sha);
        assert_eq!(view.state, snapshot.state);
        assert_eq!(
            view.head_ci,
            match snapshot.ci_capability {
                CiCapability::Available => CiAssessment::Success,
                CiCapability::Missing => CiAssessment::CapabilityMissing,
                CiCapability::Unknown => CiAssessment::CapabilityUnknown,
            }
        );
    }
}

#[test]
fn head_change_invalidates_old_green_and_test_merge_is_separate() {
    let mut snapshot = fixtures().remove(0);
    let mut store = store(&snapshot);
    store.consume(snapshot.clone()).unwrap();
    snapshot.revision += 1;
    snapshot.head_sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".into();
    store.consume(snapshot.clone()).unwrap();
    assert_eq!(
        store.project(&snapshot.key).unwrap().unwrap().head_ci,
        CiAssessment::Stale
    );
    snapshot.revision += 1;
    snapshot.checks.push(CiCheck {
        run_id: "merge-check".into(),
        subject: CiSubject::TestMerge {
            sha: "cccccccccccccccccccccccccccccccccccccccc".into(),
            head_sha: snapshot.head_sha.clone(),
            base_sha: "dddddddddddddddddddddddddddddddddddddddd".into(),
        },
        conclusion: CiConclusion::Success,
    });
    store.consume(snapshot.clone()).unwrap();
    let view = store.project(&snapshot.key).unwrap().unwrap();
    assert_eq!(view.head_ci, CiAssessment::Stale);
    assert_eq!(view.test_merge_checks.len(), 1);
    assert_eq!(view.test_merge_checks[0].conclusion, CiConclusion::Success);
    assert_eq!(view.state, PullRequestState::Open);
    snapshot.revision += 1;
    snapshot.head_sha = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".into();
    store.consume(snapshot.clone()).unwrap();
    assert!(store
        .project(&snapshot.key)
        .unwrap()
        .unwrap()
        .test_merge_checks
        .is_empty());
}

#[test]
fn only_explicit_success_is_success_and_failure_dominates() {
    for (conclusion, expected) in [
        (CiConclusion::Success, CiAssessment::Success),
        (CiConclusion::Failure, CiAssessment::Failure),
        (CiConclusion::Pending, CiAssessment::Pending),
        (CiConclusion::Skipped, CiAssessment::Inconclusive),
        (CiConclusion::Cancelled, CiAssessment::Inconclusive),
        (CiConclusion::Unknown, CiAssessment::Inconclusive),
    ] {
        let mut snapshot = fixtures().remove(0);
        snapshot.checks[0].conclusion = conclusion;
        let mut store = store(&snapshot);
        store.consume(snapshot.clone()).unwrap();
        assert_eq!(
            store.project(&snapshot.key).unwrap().unwrap().head_ci,
            expected
        );
        snapshot.revision += 1;
        snapshot.checks.push(CiCheck {
            run_id: "failing".into(),
            subject: CiSubject::Head {
                sha: snapshot.head_sha.clone(),
            },
            conclusion: CiConclusion::Failure,
        });
        store.consume(snapshot.clone()).unwrap();
        assert_eq!(
            store.project(&snapshot.key).unwrap().unwrap().head_ci,
            CiAssessment::Failure
        );
    }
}

#[test]
fn closed_is_not_merged_and_real_merge_has_its_own_sha() {
    let mut snapshot = fixtures().remove(0);
    snapshot.state = PullRequestState::Closed;
    let mut store = store(&snapshot);
    store.consume(snapshot.clone()).unwrap();
    assert_eq!(
        store.project(&snapshot.key).unwrap().unwrap().state,
        PullRequestState::Closed
    );
    snapshot.revision += 1;
    snapshot.state = PullRequestState::Merged {
        merge_sha: "ffffffffffffffffffffffffffffffffffffffff".into(),
    };
    store.consume(snapshot.clone()).unwrap();
    let view = store.project(&snapshot.key).unwrap().unwrap();
    assert_eq!(view.state, snapshot.state);
    assert_ne!(view.head_sha, "ffffffffffffffffffffffffffffffffffffffff");
}

#[test]
fn duplicates_and_reordered_snapshots_cannot_restore_old_green() {
    let older = fixtures().remove(0);
    let mut store = store(&older);
    store.consume(older.clone()).unwrap();
    assert_eq!(store.consume(older.clone()), Ok(ConsumeResult::Duplicate));
    let mut conflict = older.clone();
    conflict.state = PullRequestState::Closed;
    assert_eq!(
        store.consume(conflict),
        Err(EvidenceError::RevisionConflict)
    );
    let mut newer = older.clone();
    newer.revision += 1;
    newer.head_sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".into();
    store.consume(newer.clone()).unwrap();
    assert_eq!(store.consume(older), Ok(ConsumeResult::Outdated));
    assert_eq!(
        store.project(&newer.key).unwrap().unwrap().head_ci,
        CiAssessment::Stale
    );
}

#[test]
fn provider_instance_repository_and_object_are_independent() {
    let initial = fixtures().remove(0);
    let mut variants = vec![initial.clone(); 5];
    variants[1].key.repository.provider = Provider::GitLab;
    variants[2].key.repository.instance = "https://second.example".into();
    variants[3].key.repository.repository_id = "second/repo".into();
    variants[4].key.object_id = "2".into();
    let mut store = RepositoryEvidenceStore::default();
    for snapshot in &variants {
        if store.project(&snapshot.key) == Err(EvidenceError::AccessDenied) {
            store
                .set_access(snapshot.key.repository.clone(), 1, true)
                .unwrap();
        }
        store.consume(snapshot.clone()).unwrap();
    }
    let mut changed = variants[0].clone();
    changed.revision += 1;
    changed.head_sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".into();
    store.consume(changed).unwrap();
    assert_eq!(
        store.project(&variants[0].key).unwrap().unwrap().head_ci,
        CiAssessment::Stale
    );
    for snapshot in &variants[1..] {
        assert_eq!(
            store.project(&snapshot.key).unwrap().unwrap().head_ci,
            CiAssessment::Success
        );
    }
}

#[test]
fn permission_loss_hides_all_objects_and_old_generation_cannot_reappear() {
    let first = fixtures().remove(0);
    let mut second = first.clone();
    second.key.object_id = "2".into();
    let mut store = store(&first);
    store.consume(first.clone()).unwrap();
    store.consume(second.clone()).unwrap();
    store
        .set_access(first.key.repository.clone(), 2, false)
        .unwrap();
    for snapshot in [&first, &second] {
        assert_eq!(
            store.project(&snapshot.key),
            Err(EvidenceError::AccessDenied)
        );
        assert_eq!(
            store.consume(snapshot.clone()),
            Err(EvidenceError::AccessDenied)
        );
    }
    assert_eq!(
        store.set_access(first.key.repository.clone(), 1, true),
        Err(EvidenceError::AccessGeneration)
    );
    store
        .set_access(first.key.repository.clone(), 3, true)
        .unwrap();
    assert_eq!(store.project(&first.key), Ok(None));
    assert_eq!(
        store.consume(first.clone()),
        Err(EvidenceError::AccessGeneration)
    );
    let mut fresh = first.clone();
    fresh.authorization_generation = 3;
    fresh.revision = 1;
    store.consume(fresh.clone()).unwrap();
    assert!(store.project(&fresh.key).unwrap().is_some());
    assert_eq!(store.project(&second.key), Ok(None));
}

#[test]
fn malformed_and_ambiguous_checks_are_rejected_atomically() {
    let original = fixtures().remove(0);
    let mut bad = Vec::new();
    let mut snapshot = original.clone();
    snapshot.head_sha = "short".into();
    bad.push(snapshot);
    let mut snapshot = original.clone();
    snapshot.key.object_id.clear();
    bad.push(snapshot);
    let mut snapshot = original.clone();
    snapshot.checks.push(snapshot.checks[0].clone());
    bad.push(snapshot);
    let mut snapshot = original.clone();
    snapshot.state = PullRequestState::Merged {
        merge_sha: String::new(),
    };
    bad.push(snapshot);
    let mut snapshot = original.clone();
    snapshot.checks[0].subject = CiSubject::TestMerge {
        sha: snapshot.head_sha.clone(),
        head_sha: snapshot.head_sha.clone(),
        base_sha: "dddddddddddddddddddddddddddddddddddddddd".into(),
    };
    bad.push(snapshot);
    for snapshot in bad {
        let mut store = store(&original);
        store.consume(original.clone()).unwrap();
        assert_eq!(store.consume(snapshot), Err(EvidenceError::InvalidInput));
        assert_eq!(
            store.project(&original.key).unwrap().unwrap().head_ci,
            CiAssessment::Success
        );
    }
}

#[test]
fn missing_and_unknown_ci_capability_never_turn_green() {
    for capability in [CiCapability::Missing, CiCapability::Unknown] {
        let mut snapshot = fixtures().remove(0);
        snapshot.ci_capability = capability;
        let mut store = store(&snapshot);
        store.consume(snapshot.clone()).unwrap();
        assert_ne!(
            store.project(&snapshot.key).unwrap().unwrap().head_ci,
            CiAssessment::Success
        );
    }
    let mut snapshot = fixtures().remove(0);
    snapshot.checks.clear();
    let mut store = store(&snapshot);
    store.consume(snapshot.clone()).unwrap();
    assert_eq!(
        store.project(&snapshot.key).unwrap().unwrap().head_ci,
        CiAssessment::NoEvidence
    );
}

#[test]
fn serialized_snapshot_roundtrip_preserves_identity_and_sha() {
    for snapshot in fixtures() {
        let restored: RepositorySnapshot =
            serde_json::from_str(&serde_json::to_string(&snapshot).unwrap()).unwrap();
        assert_eq!(restored, snapshot);
    }
}

#[test]
fn test_merge_from_old_base_does_not_cover_current_base() {
    let mut snapshot = fixtures().remove(0);
    snapshot.checks = vec![CiCheck {
        run_id: "test-merge".into(),
        subject: CiSubject::TestMerge {
            sha: "cccccccccccccccccccccccccccccccccccccccc".into(),
            head_sha: snapshot.head_sha.clone(),
            base_sha: snapshot.base_sha.clone(),
        },
        conclusion: CiConclusion::Success,
    }];
    let mut store = store(&snapshot);
    store.consume(snapshot.clone()).unwrap();
    assert_eq!(
        store
            .project(&snapshot.key)
            .unwrap()
            .unwrap()
            .test_merge_checks
            .len(),
        1
    );
    snapshot.base_sha = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".into();
    snapshot.revision += 1;
    store.consume(snapshot.clone()).unwrap();
    let view = store.project(&snapshot.key).unwrap().unwrap();
    assert!(view.test_merge_checks.is_empty());
    assert_eq!(view.head_ci, CiAssessment::NoEvidence);
}

#[test]
fn reordered_check_list_is_duplicate_and_non_success_prevents_green() {
    for conclusion in [
        CiConclusion::Pending,
        CiConclusion::Skipped,
        CiConclusion::Cancelled,
        CiConclusion::Unknown,
    ] {
        let mut snapshot = fixtures().remove(0);
        snapshot.checks.push(CiCheck {
            run_id: "second".into(),
            subject: CiSubject::Head {
                sha: snapshot.head_sha.clone(),
            },
            conclusion,
        });
        let mut store = store(&snapshot);
        store.consume(snapshot.clone()).unwrap();
        assert_ne!(
            store.project(&snapshot.key).unwrap().unwrap().head_ci,
            CiAssessment::Success
        );
        snapshot.checks.reverse();
        assert_eq!(store.consume(snapshot), Ok(ConsumeResult::Duplicate));
    }
}

#[test]
fn serialized_unknown_status_and_extra_authority_fields_are_rejected() {
    let snapshot = fixtures().remove(0);
    let mut value = serde_json::to_value(&snapshot).unwrap();
    value["state"] = "closed_means_merged".into();
    assert!(serde_json::from_value::<RepositorySnapshot>(value).is_err());
    let mut value = serde_json::to_value(&snapshot).unwrap();
    value["authorized"] = true.into();
    assert!(serde_json::from_value::<RepositorySnapshot>(value).is_err());
    let mut store = RepositoryEvidenceStore::default();
    assert_eq!(store.consume(snapshot), Err(EvidenceError::AccessDenied));
}
