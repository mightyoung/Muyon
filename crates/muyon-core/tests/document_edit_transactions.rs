use contract::{Revision, Scope};
use documents::{
    CapabilityMatrix, CapabilityStatus, DocumentFormat, DocumentOperation, DocumentRef,
};
use muyon_core::{contract, documents};
#[path = "../src/document_edit/mod.rs"]
mod document_edit;
use document_edit::*;

fn document(project: &str, revision: u64) -> DocumentRef {
    DocumentRef::new(
        Scope {
            workspace_id: "workspace".into(),
            project_id: Some(project.into()),
        },
        "doc",
        Revision::new(revision),
        DocumentFormat::Docx,
    )
    .unwrap()
}
fn binding() -> Binding {
    Binding {
        document: document("project-a", 1),
        patch_digest: [7; 32],
        intent_id: "intent-1".into(),
        rollback_target: None,
    }
}
fn facts(b: &Binding) -> HostFacts {
    // Synthetic capability facts for contract tests, never installed engine proof.
    let mut capabilities = CapabilityMatrix::default();
    for op in [
        DocumentOperation::Inspect,
        DocumentOperation::ReadText,
        DocumentOperation::Render,
        DocumentOperation::StructuredEdit,
        DocumentOperation::Validate,
        DocumentOperation::Export,
    ] {
        capabilities.set(b.document.format(), op, CapabilityStatus::Supported);
    }
    HostFacts {
        permissions: vec![
            DocumentOperation::Inspect,
            DocumentOperation::ReadText,
            DocumentOperation::Render,
            DocumentOperation::StructuredEdit,
            DocumentOperation::Validate,
            DocumentOperation::Export,
        ],
        capabilities,
        binding: b.clone(),
        current_revision: b.document.revision().clone(),
        authority: Some(Authority {
            grant_id: "grant".into(),
            generation: Revision::new(1),
            owner_epoch: "owner".into(),
        }),
        active: true,
    }
}
fn candidate() -> Candidate {
    Candidate {
        binding: binding(),
        id: "copy-1".into(),
        digest: [8; 32],
        immutable_copy: true,
    }
}
fn validation() -> Validation {
    Validation {
        candidate: candidate(),
        reopened: true,
        structure: true,
        semantics: true,
        render_comparison: true,
        unsupported_preserved: true,
        formula: FormulaStatus::NotApplicable,
    }
}
fn previewed() -> Transaction {
    let mut t = Transaction::new(binding()).unwrap();
    let f = facts(t.binding());
    t.execute(Command::Inspect, Some(&f)).unwrap();
    t.execute(Command::Read, Some(&f)).unwrap();
    t.execute(Command::Propose, Some(&f)).unwrap();
    t.execute(Command::Preview, Some(&f)).unwrap();
    t
}
fn applied() -> Transaction {
    let mut t = previewed();
    let f = facts(t.binding());
    t.execute(
        Command::ApplyCopy {
            confirmation: Confirmation {
                binding: t.binding().clone(),
                authority: f.authority.clone().unwrap(),
            },
            candidate: Some(candidate()),
        },
        Some(&f),
    )
    .unwrap();
    t
}
fn validated() -> Transaction {
    let mut t = applied();
    let f = facts(t.binding());
    t.execute(Command::Validate(Some(validation())), Some(&f))
        .unwrap();
    t
}
fn receipt(b: &Binding) -> CommitReceipt {
    CommitReceipt {
        binding: b.clone(),
        candidate: candidate(),
        previous_revision: b.document.revision().clone(),
        committed_revision: Revision::new(2),
        cas_succeeded: true,
        durable: true,
    }
}

#[test]
fn identity_requires_all_binding_fields() {
    let mut b = binding();
    b.intent_id.clear();
    assert_eq!(Transaction::new(b).unwrap_err(), Error::MissingFact);
    let mut b = binding();
    b.patch_digest = [0; 32];
    assert_eq!(Transaction::new(b).unwrap_err(), Error::MissingFact);
}
#[test]
fn preview_never_confirms_or_supplies_missing_authority() {
    let mut t = previewed();
    let mut f = facts(t.binding());
    f.authority = None;
    assert_eq!(
        t.execute(
            Command::ApplyCopy {
                confirmation: Confirmation {
                    binding: t.binding().clone(),
                    authority: facts(t.binding()).authority.unwrap()
                },
                candidate: Some(candidate())
            },
            Some(&f)
        ),
        Err(Error::Authority)
    );
    assert_eq!(t.state(), State::Previewed);
}
#[test]
fn stale_confirmation_is_rejected() {
    let mut t = previewed();
    let f = facts(t.binding());
    let mut b = t.binding().clone();
    b.document = document("project-a", 0);
    assert_eq!(
        t.execute(
            Command::ApplyCopy {
                confirmation: Confirmation {
                    binding: b,
                    authority: f.authority.clone().unwrap()
                },
                candidate: Some(candidate())
            },
            Some(&f)
        ),
        Err(Error::Binding)
    );
    assert_eq!(t.state(), State::Previewed);
}
#[test]
fn cross_scope_is_rejected_even_for_read() {
    let mut t = Transaction::new(binding()).unwrap();
    let mut f = facts(t.binding());
    f.binding.document = document("project-b", 1);
    assert_eq!(t.execute(Command::Inspect, Some(&f)), Err(Error::Binding));
}
#[test]
fn every_boundary_requires_facts_and_live_authority() {
    let mut t = previewed();
    assert_eq!(t.execute(Command::Preview, None), Err(Error::MissingFact));
    let mut t = validated();
    let mut f = facts(t.binding());
    f.active = false;
    assert_eq!(
        t.execute(Command::Commit(Some(receipt(t.binding()))), Some(&f)),
        Err(Error::Authority)
    );
    assert_eq!(t.state(), State::Validated);
}
#[test]
fn reissued_authority_does_not_reuse_confirmation() {
    let mut t = applied();
    let mut f = facts(t.binding());
    f.authority.as_mut().unwrap().generation = Revision::new(2);
    assert_eq!(
        t.execute(Command::Validate(Some(validation())), Some(&f)),
        Err(Error::Authority)
    );
}
#[test]
fn apply_requires_an_immutable_copy_with_a_distinct_identity() {
    for c in [
        None,
        Some(Candidate {
            id: "doc".into(),
            ..candidate()
        }),
        Some(Candidate {
            immutable_copy: false,
            ..candidate()
        }),
    ] {
        let mut t = previewed();
        let f = facts(t.binding());
        assert!(t
            .execute(
                Command::ApplyCopy {
                    confirmation: Confirmation {
                        binding: t.binding().clone(),
                        authority: f.authority.clone().unwrap()
                    },
                    candidate: c
                },
                Some(&f)
            )
            .is_err());
        assert_eq!(t.state(), State::Previewed);
    }
}
#[test]
fn double_click_does_not_reapply() {
    let mut t = applied();
    let f = facts(t.binding());
    assert_eq!(
        t.execute(
            Command::ApplyCopy {
                confirmation: Confirmation {
                    binding: t.binding().clone(),
                    authority: f.authority.clone().unwrap()
                },
                candidate: Some(candidate())
            },
            Some(&f)
        ),
        Err(Error::State)
    );
}
#[test]
fn unvalidated_commit_is_refused() {
    let mut t = applied();
    let f = facts(t.binding());
    assert_eq!(
        t.execute(Command::Commit(Some(receipt(t.binding()))), Some(&f)),
        Err(Error::State)
    );
}
#[test]
fn validation_failure_is_terminal_and_cannot_commit() {
    let mut t = applied();
    let f = facts(t.binding());
    let mut v = validation();
    v.semantics = false;
    assert_eq!(
        t.execute(Command::Validate(Some(v)), Some(&f)),
        Err(Error::Validation)
    );
    assert_eq!(t.state(), State::Failed);
    assert_eq!(
        t.execute(Command::Commit(Some(receipt(t.binding()))), Some(&f)),
        Err(Error::State)
    );
}
#[test]
fn candidate_mismatch_and_missing_validation_do_not_advance() {
    let mut t = applied();
    let f = facts(t.binding());
    assert_eq!(
        t.execute(Command::Validate(None), Some(&f)),
        Err(Error::MissingFact)
    );
    let mut v = validation();
    v.candidate.digest = [9; 32];
    assert_eq!(
        t.execute(Command::Validate(Some(v)), Some(&f)),
        Err(Error::Binding)
    );
    assert_eq!(t.state(), State::Candidate);
}
#[test]
fn stale_source_and_failed_cas_preserve_candidate_as_conflict() {
    let mut t = validated();
    let mut f = facts(t.binding());
    f.current_revision = Revision::new(3);
    assert_eq!(
        t.execute(Command::Commit(Some(receipt(t.binding()))), Some(&f)),
        Err(Error::Conflict)
    );
    assert_eq!(t.state(), State::Conflict);
    assert_eq!(t.candidate(), Some(&candidate()));
    let mut t = validated();
    let f = facts(t.binding());
    let mut r = receipt(t.binding());
    r.cas_succeeded = false;
    assert_eq!(
        t.execute(Command::Commit(Some(r)), Some(&f)),
        Err(Error::Conflict)
    );
}
#[test]
fn commit_needs_durable_matching_receipt_and_cannot_repeat() {
    let mut t = validated();
    let f = facts(t.binding());
    assert_eq!(
        t.execute(Command::Commit(None), Some(&f)),
        Err(Error::MissingFact)
    );
    let mut r = receipt(t.binding());
    r.durable = false;
    assert_eq!(
        t.execute(Command::Commit(Some(r)), Some(&f)),
        Err(Error::MissingFact)
    );
    t.execute(Command::Commit(Some(receipt(t.binding()))), Some(&f))
        .unwrap();
    assert_eq!(t.state(), State::Committed);
    assert_eq!(
        t.execute(Command::Commit(Some(receipt(t.binding()))), Some(&f)),
        Err(Error::State)
    );
}
#[test]
fn unknown_queries_original_intent_and_never_replays() {
    let mut t = validated();
    let f = facts(t.binding());
    t.execute(Command::OutcomeUnknown, Some(&f)).unwrap();
    assert_eq!(
        t.execute(Command::Commit(Some(receipt(t.binding()))), Some(&f)),
        Err(Error::Unknown)
    );
    let mut r = receipt(t.binding());
    r.binding.intent_id = "other".into();
    assert_eq!(
        t.execute(Command::RecoverCommit(Some(r)), Some(&f)),
        Err(Error::Binding)
    );
    assert_eq!(t.state(), State::Unknown);
    assert_eq!(
        t.execute(Command::RecoverCommit(None), Some(&f)),
        Err(Error::MissingFact)
    );
    t.execute(Command::RecoverCommit(Some(receipt(t.binding()))), Some(&f))
        .unwrap();
    assert_eq!(t.state(), State::Committed);
}
#[test]
fn cancellation_preserves_unknown_and_committed_outcomes() {
    let mut t = validated();
    let f = facts(t.binding());
    t.execute(Command::OutcomeUnknown, Some(&f)).unwrap();
    t.execute(Command::Cancel, Some(&f)).unwrap();
    assert!(t.cancel_requested());
    assert_eq!(t.state(), State::Unknown);
    t.execute(Command::RecoverCommit(Some(receipt(t.binding()))), Some(&f))
        .unwrap();
    t.execute(Command::Cancel, Some(&f)).unwrap();
    assert_eq!(t.state(), State::Committed);
    let mut t = applied();
    let f = facts(t.binding());
    t.execute(Command::Cancel, Some(&f)).unwrap();
    assert_eq!(t.state(), State::Cancelled);
    assert_eq!(t.candidate(), Some(&candidate()));
}
#[test]
fn rollback_is_a_new_bound_transaction_not_a_cancel_side_effect() {
    let mut t = validated();
    let f = facts(t.binding());
    t.execute(Command::Commit(Some(receipt(t.binding()))), Some(&f))
        .unwrap();
    let b = Binding {
        document: document("project-a", 2),
        intent_id: "rollback-2".into(),
        patch_digest: [10; 32],
        rollback_target: Some(Revision::new(1)),
        ..binding()
    };
    let next = t.rollback(b.clone()).unwrap();
    assert_eq!(next.state(), State::New);
    assert_eq!(next.binding(), &b);
    assert_eq!(t.state(), State::Committed);
    let mut bad = b.clone();
    bad.intent_id = t.binding().intent_id.clone();
    assert!(t.rollback(bad).is_err());
    let mut bad = b;
    bad.rollback_target = None;
    assert!(t.rollback(bad).is_err());
}
#[test]
fn export_requires_committed_revision_and_matching_copy() {
    let mut t = validated();
    let f = facts(t.binding());
    let e = ExportReceipt {
        binding: t.binding().clone(),
        candidate: candidate(),
        revision: Revision::new(2),
        export_id: "export-1".into(),
        durable: true,
    };
    assert_eq!(
        t.execute(Command::Export(Some(e.clone())), Some(&f)),
        Err(Error::State)
    );
    t.execute(Command::Commit(Some(receipt(t.binding()))), Some(&f))
        .unwrap();
    let mut wrong = e.clone();
    wrong.revision = Revision::new(1);
    assert_eq!(
        t.execute(Command::Export(Some(wrong)), Some(&f)),
        Err(Error::Binding)
    );
    t.execute(Command::Export(Some(e)), Some(&f)).unwrap();
    assert_eq!(t.state(), State::Exported);
}

#[test]
fn prior_candidate_cannot_be_attached_to_a_different_patch_or_intent() {
    for field in 0..2 {
        let mut b = binding();
        if field == 0 {
            b.patch_digest = [11; 32]
        } else {
            b.intent_id = "other-intent".into()
        }
        let mut t = Transaction::new(b).unwrap();
        let f = facts(t.binding());
        for command in [
            Command::Inspect,
            Command::Read,
            Command::Propose,
            Command::Preview,
        ] {
            t.execute(command, Some(&f)).unwrap();
        }
        assert_eq!(
            t.execute(
                Command::ApplyCopy {
                    confirmation: Confirmation {
                        binding: t.binding().clone(),
                        authority: f.authority.clone().unwrap()
                    },
                    candidate: Some(candidate())
                },
                Some(&f)
            ),
            Err(Error::Binding)
        );
        assert_eq!(t.state(), State::Previewed);
    }
}
#[test]
fn cancel_before_late_commit_receipt_or_unknown_keeps_recovery_open() {
    for unknown in [false, true] {
        let mut t = validated();
        let f = facts(t.binding());
        t.execute(Command::Cancel, Some(&f)).unwrap();
        assert!(t.cancel_requested());
        if unknown {
            t.execute(Command::OutcomeUnknown, Some(&f)).unwrap();
            assert_eq!(t.state(), State::Unknown);
        }
        t.execute(Command::RecoverCommit(Some(receipt(t.binding()))), Some(&f))
            .unwrap();
        assert_eq!(t.state(), State::Committed);
        assert!(t.cancel_requested());
    }
}
#[test]
fn original_intent_query_with_new_read_authority_does_not_replay_old_confirmation() {
    let mut t = validated();
    let f = facts(t.binding());
    t.execute(Command::OutcomeUnknown, Some(&f)).unwrap();
    let mut fresh = f.clone();
    fresh.authority.as_mut().unwrap().generation = Revision::new(2);
    fresh.authority.as_mut().unwrap().owner_epoch = "new-owner".into();
    fresh.current_revision = Revision::new(2);
    t.execute(
        Command::RecoverCommit(Some(receipt(t.binding()))),
        Some(&fresh),
    )
    .unwrap();
    assert_eq!(t.state(), State::Committed);
}
#[test]
fn revocation_does_not_prevent_local_cancel_request() {
    let mut t = validated();
    let mut f = facts(t.binding());
    t.execute(Command::OutcomeUnknown, Some(&f)).unwrap();
    f.active = false;
    f.authority = None;
    t.execute(Command::Cancel, Some(&f)).unwrap();
    assert!(t.cancel_requested());
    assert_eq!(t.state(), State::Unknown);
    assert_eq!(
        t.execute(Command::RecoverCommit(Some(receipt(t.binding()))), Some(&f)),
        Err(Error::Authority)
    );
}
#[test]
fn each_validation_dimension_and_formula_unknown_fails_closed() {
    for field in 0..7 {
        let mut t = applied();
        let f = facts(t.binding());
        let mut v = validation();
        match field {
            0 => v.reopened = false,
            1 => v.structure = false,
            2 => v.semantics = false,
            3 => v.render_comparison = false,
            4 => v.unsupported_preserved = false,
            5 => v.formula = FormulaStatus::Unknown,
            _ => v.formula = FormulaStatus::Failed,
        }
        assert_eq!(
            t.execute(Command::Validate(Some(v)), Some(&f)),
            Err(Error::Validation)
        );
        assert_eq!(t.state(), State::Failed);
    }
    let mut t = applied();
    let f = facts(t.binding());
    let mut v = validation();
    v.formula = FormulaStatus::Recalculated;
    t.execute(Command::Validate(Some(v)), Some(&f)).unwrap();
    assert_eq!(t.state(), State::Validated);
}
#[test]
fn unknown_apply_recovers_original_candidate_without_replay() {
    for cancelled in [false, true] {
        let mut t = previewed();
        let f = facts(t.binding());
        t.execute(
            Command::AwaitApply(Confirmation {
                binding: t.binding().clone(),
                authority: f.authority.clone().unwrap(),
            }),
            Some(&f),
        )
        .unwrap();
        if cancelled {
            t.execute(Command::Cancel, Some(&f)).unwrap();
        }
        t.execute(Command::OutcomeUnknown, Some(&f)).unwrap();
        assert_eq!(
            t.execute(
                Command::ApplyCopy {
                    confirmation: Confirmation {
                        binding: t.binding().clone(),
                        authority: f.authority.clone().unwrap()
                    },
                    candidate: Some(candidate())
                },
                Some(&f)
            ),
            Err(Error::Unknown)
        );
        assert_eq!(
            t.execute(Command::RecoverCommit(Some(receipt(t.binding()))), Some(&f)),
            Err(Error::State)
        );
        let mut fresh = f.clone();
        fresh.authority.as_mut().unwrap().generation = Revision::new(2);
        t.execute(Command::RecoverApply(Some(candidate())), Some(&fresh))
            .unwrap();
        assert_eq!(t.candidate(), Some(&candidate()));
        assert_eq!(
            t.state(),
            if cancelled {
                State::Cancelled
            } else {
                State::Candidate
            }
        );
    }
}

#[test]
fn revocation_cannot_hide_an_uncertain_original_outcome() {
    let mut t = validated();
    let mut f = facts(t.binding());
    f.active = false;
    f.authority = None;
    t.execute(Command::OutcomeUnknown, Some(&f)).unwrap();
    assert_eq!(t.state(), State::Unknown);
    let live = facts(t.binding());
    assert_eq!(
        t.execute(Command::Commit(Some(receipt(t.binding()))), Some(&live)),
        Err(Error::Unknown)
    );
}

#[test]
fn unknown_capability_or_missing_operation_permission_never_advances() {
    let mut t = previewed();
    let mut f = facts(t.binding());
    f.capabilities = CapabilityMatrix::default();
    assert_eq!(
        t.execute(
            Command::ApplyCopy {
                confirmation: Confirmation {
                    binding: t.binding().clone(),
                    authority: f.authority.clone().unwrap()
                },
                candidate: Some(candidate())
            },
            Some(&f)
        ),
        Err(Error::Capability)
    );
    assert_eq!(t.state(), State::Previewed);
    let mut f = facts(t.binding());
    f.permissions = vec![DocumentOperation::ReadText];
    assert_eq!(
        t.execute(
            Command::ApplyCopy {
                confirmation: Confirmation {
                    binding: t.binding().clone(),
                    authority: f.authority.clone().unwrap()
                },
                candidate: Some(candidate())
            },
            Some(&f)
        ),
        Err(Error::Permission)
    );
}
#[test]
fn readonly_capability_is_never_edit_permission() {
    let mut t = previewed();
    let mut f = facts(t.binding());
    f.capabilities.set(
        t.binding().document.format(),
        DocumentOperation::StructuredEdit,
        CapabilityStatus::ReadOnly,
    );
    assert_eq!(
        t.execute(
            Command::AwaitApply(Confirmation {
                binding: t.binding().clone(),
                authority: f.authority.clone().unwrap()
            }),
            Some(&f)
        ),
        Err(Error::Capability)
    );
}

#[test]
fn host_observations_reject_paths_in_opaque_candidate_and_authority_ids() {
    let mut t = previewed();
    let f = facts(t.binding());
    let mut c = candidate();
    c.id = "/tmp/copy".into();
    assert_eq!(
        t.execute(
            Command::ApplyCopy {
                confirmation: Confirmation {
                    binding: t.binding().clone(),
                    authority: f.authority.clone().unwrap()
                },
                candidate: Some(c)
            },
            Some(&f)
        ),
        Err(Error::MissingFact)
    );
    let mut f = facts(t.binding());
    f.authority.as_mut().unwrap().grant_id = "/tmp/grant".into();
    assert_eq!(
        t.execute(
            Command::AwaitApply(Confirmation {
                binding: t.binding().clone(),
                authority: f.authority.clone().unwrap()
            }),
            Some(&f)
        ),
        Err(Error::Authority)
    );
}
