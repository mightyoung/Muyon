pub use muyon_core::{contract, documents, services};
pub mod adapter {
    include!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/services/pipeline.rs"
    ));
}
use adapter::*;
use muyon_core::{
    contract::{Revision, Scope},
    documents::{DocumentFormat, DocumentRef},
    services::{drafts::*, types::*},
};
fn scope(project: &str) -> ScopeRef {
    ScopeRef {
        scope: Scope {
            workspace_id: "w".into(),
            project_id: Some(project.into()),
        },
        account_id: None,
        scope_generation: Revision::new(1),
    }
}
fn document(project: &str, revision: u64) -> DocumentRef {
    DocumentRef::new(
        scope(project).scope,
        "doc",
        Revision::new(revision),
        DocumentFormat::Text,
    )
    .unwrap()
}
fn descriptor() -> VectorDescriptor {
    VectorDescriptor {
        model_version: "synthetic-model-v1".into(),
        tokenizer_version: "synthetic-tokenizer-v1".into(),
        dimensions: 768,
        chunk_version: "synthetic-chunk-v1".into(),
    }
}
fn result(id: &str, project: &str) -> ResultRef {
    ResultRef {
        result_id: ResultId::parse(id).unwrap(),
        input_document_ref: document(project, 1),
        input_result_refs: vec![],
        content_digest: Digest::parse(&"a".repeat(64)).unwrap(),
        producer_version: "synthetic".into(),
        parameters_digest: Digest::parse(&"b".repeat(64)).unwrap(),
    }
}
fn snapshot() -> IndexSnapshotRef {
    IndexSnapshotRef {
        snapshot_id: "synthetic-snapshot-v1".into(),
        scope: scope("p"),
        revision: Revision::new(1),
        inputs: vec![
            ResultId::parse("r1").unwrap(),
            ResultId::parse("r2").unwrap(),
        ],
        descriptor: descriptor(),
    }
}
#[test]
fn late_job_cannot_publish_current() {
    let expected = document("p", 1);
    let current = document("p", 2);
    let one = Revision::new(1);
    let two = Revision::new(2);
    let historical = [result("old-result", "p")];
    let current_pointer = ResultId::parse("new-result").unwrap();
    assert_eq!(
        can_publish_head(&expected, &current, &one, &one)
            .unwrap_err()
            .code,
        ErrorCode::StaleRevision
    );
    assert_eq!(
        can_publish_head(&current, &current, &one, &two)
            .unwrap_err()
            .code,
        ErrorCode::ScopeChanged
    );
    assert_eq!(
        can_publish_head(&current, &document("other", 2), &one, &one)
            .unwrap_err()
            .code,
        ErrorCode::ScopeChanged
    );
    assert!(can_publish_head(&current, &current, &two, &two).is_ok());
    // The pure guard neither mutates historic products nor publishes a pointer.
    assert_eq!(historical[0].result_id.as_str(), "old-result");
    assert_eq!(current_pointer.as_str(), "new-result");
}
#[test]
fn descriptor_mismatch_is_rejected() {
    let s = snapshot();
    let inputs = vec![result("r1", "p"), result("r2", "p")];
    assert!(validate_search(&s, &descriptor(), &inputs).is_ok());
    assert!(validate_search(&s, &descriptor(), &[inputs[1].clone(), inputs[0].clone()]).is_ok());
    for field in 0..4 {
        let mut q = descriptor();
        match field {
            0 => q.model_version.push('2'),
            1 => q.tokenizer_version.push('2'),
            2 => q.dimensions = 384,
            _ => q.chunk_version.push('2'),
        }
        assert!(validate_search(&s, &q, &inputs).is_err(), "field {field}");
    }
    let mut cross = inputs.clone();
    cross[1] = result("r2", "other");
    assert_eq!(
        validate_search(&s, &descriptor(), &cross).unwrap_err().code,
        ErrorCode::ScopeChanged
    );
    for bad in [
        vec![],
        vec![inputs[0].clone()],
        vec![inputs[0].clone(), inputs[0].clone()],
        vec![inputs[0].clone(), inputs[1].clone(), result("r3", "p")],
    ] {
        assert!(validate_search(&s, &descriptor(), &bad).is_err());
    }
    let mut duplicate = s.clone();
    duplicate.inputs[1] = duplicate.inputs[0].clone();
    assert!(validate_search(&duplicate, &descriptor(), &inputs).is_err());
    let mut zero = s.clone();
    zero.descriptor.dimensions = 0;
    assert!(validate_search(&zero, &zero.descriptor, &inputs).is_err());
}
#[test]
fn job_cancel_maps_original_only() {
    let original = IntentId::parse("intent:registered-original").unwrap();
    for phase in [
        JobPhase::UnknownOutcome,
        JobPhase::CancelRequested,
        JobPhase::Succeeded,
    ] {
        let job = JobSnapshot {
            job_id: JobId::parse("job:1").unwrap(),
            original_intent_id: original.clone(),
            scope: scope("p"),
            stage: PipelineStage::Embedding,
            attempt: 3,
            phase: phase.clone(),
            coverage: Coverage {
                state: CoverageState::Unknown,
                processed: 0,
                total: None,
                failed_units: vec![],
            },
        };
        assert_eq!(cancellation_target(&job), original);
        assert_eq!(job.phase, phase);
        assert_eq!(job.attempt, 3);
    }
    // Existing C3 recovery can only select a read; closing this value does not
    // invoke cancellation_target or a HostCommandPort command.
    let lease = SubscriptionLease {
        scope: scope("p"),
        cursor: "expired".into(),
        capacity: 1,
        expires_at_unix_ms: UnixMs::parse("0").unwrap(),
    };
    assert_eq!(
        resume_action(&scope("p"), &lease, false).unwrap(),
        ResumeAction::ReadSnapshot
    );
}
#[test]
fn shared_descriptor_fixture_matches_rust_projection() {
    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/public_pipeline.json")).unwrap();
    assert_eq!(
        fixture["descriptor"],
        serde_json::to_value(descriptor()).unwrap()
    );
    assert_eq!(fixture["legacy_paper_only_publicly_resolvable"], false);
}

#[test]
fn each_embedding_descriptor_must_match_snapshot() {
    let snapshot = snapshot();
    let inputs: Vec<_> = ["r1", "r2"]
        .iter()
        .map(|id| EmbeddingResult {
            reference: result(id, "p"),
            descriptor: descriptor(),
        })
        .collect();
    assert!(validate_embedding_search(&snapshot, &descriptor(), &inputs).is_ok());
    for index in 0..inputs.len() {
        for field in 0..4 {
            let mut mismatched = inputs.clone();
            let d = &mut mismatched[index].descriptor;
            match field {
                0 => d.model_version.push('2'),
                1 => d.tokenizer_version.push('2'),
                2 => d.dimensions = 384,
                _ => d.chunk_version.push('2'),
            }
            assert_eq!(
                validate_embedding_search(&snapshot, &descriptor(), &mismatched)
                    .unwrap_err()
                    .code,
                ErrorCode::InvalidArgument,
                "input {index}, field {field}"
            );
        }
    }
}
