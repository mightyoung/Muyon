use super::tests::{expiry, fixture, patch};
use super::*;
use crate::{
    blobs::BlobKind,
    documents::*,
    evidence::{store::StoreEvidence, InputKind},
};

pub(super) fn source(_s: &BusinessStore) -> DocumentAccess {
    let doc = DocumentRef::new(
        Scope {
            workspace_id: "workspace".into(),
            project_id: Some("project".into()),
        },
        "local-evidence",
        Revision::new(1),
        DocumentFormat::Text,
    )
    .unwrap();
    DocumentAccess {
        document: doc,
        authority: AuthorityBinding {
            grant_id: "grant-local-evidence".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch".into(),
        },
    }
}
pub(super) fn create_source(s: &BusinessStore) {
    let upload = s.begin_upload("project").unwrap();
    s.append_chunk(&upload.upload_id, b"Synthetic original evidence passage.")
        .unwrap();
    let blob = s
        .finish_blob(&upload.upload_id, BlobKind::Document)
        .unwrap();
    s.register_document_trusted(
        "project",
        "local-evidence",
        "Synthetic",
        DocumentFormat::Text,
        &blob,
    )
    .unwrap();
    let a = source(s);
    s.issue_document_grant_trusted(
        &a.document,
        &a.authority,
        &[DocumentOperation::ReadText],
        expiry(),
    )
    .unwrap();
}
pub(super) fn resolved<'a>(
    s: &'a BusinessStore,
    project: &ArtifactProjectAccess,
    purpose: ArtifactProjectOperation,
) -> crate::artifacts::local_sources::ResolvedLocalEvidence<'a> {
    let a = source(s);
    let e = StoreEvidence::new(s);
    let p = e.process(&a, InputKind::Utf8Text).unwrap();
    let hits = e.find_literal(&a, &p, "evidence", 1).unwrap();
    s.resolve_local_evidence_trusted(project, purpose, &a, &p, &hits[0])
        .unwrap()
}
pub(super) fn issue(
    s: &BusinessStore,
    a: &LocalAccess,
    kind: &LocalKind,
    expires: u64,
) -> Result<()> {
    let purpose = match kind {
        LocalKind::Form(_) => ArtifactProjectOperation::LocalDraft,
        LocalKind::Feedback => ArtifactProjectOperation::LocalFeedback,
    };
    s.issue_local_evidence_binding_trusted(a, kind, expires, &resolved(s, &a.project, purpose))
}
#[test]
fn source_head_change_invalidates_frozen_preview_without_waiting_for_lease() {
    let (_f, s, a) = fixture();
    s.mutate_local_trusted("edit", &a, &patch("manual", 0))
        .unwrap();
    let p = s
        .prepare_local_form_submit_trusted("submit", &a, &Revision::new(1))
        .unwrap();
    let u = s.begin_upload("project").unwrap();
    s.append_chunk(&u.upload_id, b"Replacement source.")
        .unwrap();
    let b = s.finish_blob(&u.upload_id, BlobKind::Document).unwrap();
    s.publish_document_revision_trusted(&source(&s).document, "New", DocumentFormat::Text, &b)
        .unwrap();
    assert!(s.lookup_local_form_preview("submit", &a).is_err());
    assert!(s
        .confirm_local_form_submit_trusted("submit", &a, &p.digest)
        .is_err());
    assert!(s.read_local_form(&a).is_err());
    assert_eq!(
        s.database()
            .query("SELECT revision FROM artifact_local_forms_v1", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
}
#[test]
fn receipt_tail_source_revocation_rolls_back_state_and_receipt_preserving_pending() {
    for change in ["active=0", "expires_at_ms='0'", "generation='2'"] {
        let (_f, s, a) = fixture();
        let trigger=format!("CREATE TRIGGER revoke_source AFTER UPDATE ON artifact_local_intents_v1 WHEN NEW.status='committed' BEGIN UPDATE document_grants SET {change} WHERE grant_id='grant-local-evidence'; END");
        s.database().exec(&trigger, &[]).unwrap();
        let out = s
            .mutate_local_trusted("tail", &a, &patch("secret", 0))
            .unwrap();
        assert_eq!(out.status, ArtifactSaveStatus::Unknown);
        assert_eq!(out.recovery_action, RecoveryAction::QueryOriginal);
        assert!(s
            .database()
            .query("SELECT * FROM artifact_local_forms_v1", &[])
            .unwrap()
            .is_empty());
        let rows = s
            .database()
            .query(
                "SELECT status,receipt_json FROM artifact_local_intents_v1 WHERE intent_id='tail'",
                &[],
            )
            .unwrap();
        assert_eq!(rows[0], vec![Some("pending".into()), None]);
        assert_eq!(s.read_local_form(&a).unwrap().revision, Revision::new(0));
        assert_eq!(
            s.lookup_local_intent("tail", &a.project).unwrap().status,
            ArtifactSaveStatus::Unknown
        );
    }
}
#[test]
fn unsupported_message_or_unresolved_evidence_cannot_issue_binding() {
    let (_f, s, a) = fixture();
    let mut unresolved = a.clone();
    unresolved.object.object_id = "unresolved".into();
    assert!(s
        .issue_local_binding_trusted(&unresolved, &LocalKind::Feedback, expiry())
        .is_err());
    unresolved.object.target = LocalTarget::Message {
        conversation_id: "conversation".into(),
        message_id: "message".into(),
        revision: Revision::new(1),
    };
    assert_eq!(
        s.issue_local_evidence_binding_trusted(
            &unresolved,
            &LocalKind::Feedback,
            expiry(),
            &resolved(&s, &a.project, ArtifactProjectOperation::LocalDraft)
        ),
        Err(ContractError::UnsupportedOperation)
    );
}
#[test]
fn actual_evidence_identity_quote_and_source_scope_are_required() {
    let (_f, s, a) = fixture();
    let da = source(&s);
    let e = StoreEvidence::new(&s);
    let p = e.process(&da, InputKind::Utf8Text).unwrap();
    let mut hit = e.find_literal(&da, &p, "evidence", 1).unwrap().remove(0);
    hit.evidence_id = "model-supplied-evidence-id".into();
    assert!(s
        .resolve_local_evidence_trusted(
            &a.project,
            ArtifactProjectOperation::LocalDraft,
            &da,
            &p,
            &hit
        )
        .is_err());
    let mut wrong = a.clone();
    if let LocalTarget::Evidence { revision, .. } = &mut wrong.object.target {
        *revision = Revision::new(2);
    }
    assert!(s
        .issue_local_evidence_binding_trusted(
            &wrong,
            &LocalKind::Feedback,
            expiry(),
            &resolved(&s, &a.project, ArtifactProjectOperation::LocalDraft)
        )
        .is_err());
}
#[test]
fn revocation_hook_is_atomic_and_never_replays_original_intents() {
    let (_f, s, a) = fixture();
    s.mutate_local_trusted("edit", &a, &patch("retained", 0))
        .unwrap();
    s.prepare_local_form_submit_trusted("submit", &a, &Revision::new(1))
        .unwrap();
    let before = s
        .database()
        .query("SELECT * FROM artifact_local_intents_v1", &[])
        .unwrap();
    let tx = s.database().transaction().unwrap();
    s.database()
        .exec(
            "UPDATE document_grants SET active=0 WHERE grant_id='grant-local-evidence'",
            &[],
        )
        .unwrap();
    let events = s
        .invalidate_local_evidence_sources_in_transaction(&tx, &source(&s).document)
        .unwrap();
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].object_id, a.object.object_id);
    drop(tx);
    assert!(s.lookup_local_form_preview("submit", &a).is_ok());
    let tx = s.database().transaction().unwrap();
    s.database()
        .exec(
            "UPDATE document_grants SET active=0 WHERE grant_id='grant-local-evidence'",
            &[],
        )
        .unwrap();
    assert_eq!(
        s.invalidate_local_evidence_sources_in_transaction(&tx, &source(&s).document)
            .unwrap()
            .len(),
        1
    );
    tx.commit().unwrap();
    assert!(s.lookup_local_form_preview("submit", &a).is_err());
    assert_eq!(
        s.database()
            .query("SELECT * FROM artifact_local_intents_v1", &[])
            .unwrap(),
        before
    );
    assert_eq!(
        s.database()
            .query("SELECT revision FROM artifact_local_forms_v1", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
}

#[test]
fn revocation_hook_processes_more_than_one_batch_without_blocking_revocation() {
    let (_f, s, a) = fixture();
    let proof = resolved(&s, &a.project, ArtifactProjectOperation::LocalDraft);
    for n in 0..257 {
        let mut b = a.clone();
        b.object.object_id = format!("batch-{n:03}");
        s.issue_local_evidence_binding_trusted(&b, &LocalKind::Feedback, expiry(), &proof)
            .unwrap();
    }
    let tx = s.database().transaction().unwrap();
    s.database()
        .exec(
            "UPDATE document_grants SET active=0 WHERE grant_id='grant-local-evidence'",
            &[],
        )
        .unwrap();
    let events = s
        .invalidate_local_evidence_sources_in_transaction(&tx, &source(&s).document)
        .unwrap();
    assert_eq!(events.len(), 258);
    tx.commit().unwrap();
    assert!(s
        .database()
        .query(
            "SELECT 1 FROM artifact_local_evidence_sources_v1 WHERE active=1",
            &[]
        )
        .unwrap()
        .is_empty());
    assert!(s.read_local_form(&a).is_err());
}

#[test]
fn resolved_proof_is_bound_to_same_store_and_resolving_actor() {
    let (_f, s, a) = fixture();
    let proof = resolved(&s, &a.project, ArtifactProjectOperation::LocalDraft);
    let mut other = a.clone();
    other.object.object_id = "another-actor".into();
    other.project.actor_id = "other".into();
    other.project.authority.grant_id = "other-local-project".into();
    s.issue_artifact_project_grant_trusted(
        &other.project,
        &[ArtifactProjectOperation::LocalFeedback],
        expiry(),
    )
    .unwrap();
    assert_eq!(
        s.issue_local_evidence_binding_trusted(&other, &LocalKind::Feedback, expiry(), &proof),
        Err(ContractError::BindingMismatch)
    );
    let (_f2, s2, a2) = fixture();
    assert_eq!(
        s2.issue_local_evidence_binding_trusted(&a2, &LocalKind::Feedback, expiry(), &proof),
        Err(ContractError::BindingMismatch)
    );
}

#[test]
fn fresh_source_authority_restores_same_draft_and_invalidates_old_preview() {
    let (_f, s, a) = fixture();
    s.mutate_local_trusted("edit", &a, &patch("retained manual", 0))
        .unwrap();
    let preview = s
        .prepare_local_form_submit_trusted("submit", &a, &Revision::new(1))
        .unwrap();
    let tx = s.database().transaction().unwrap();
    s.database()
        .exec(
            "UPDATE document_grants SET active=0 WHERE grant_id='grant-local-evidence'",
            &[],
        )
        .unwrap();
    s.invalidate_local_evidence_sources_in_transaction(&tx, &source(&s).document)
        .unwrap();
    tx.commit().unwrap();
    assert!(s.read_local_form(&a).is_err());
    let mut da = source(&s);
    da.authority.generation = Revision::new(2);
    s.issue_document_grant_trusted(
        &da.document,
        &da.authority,
        &[DocumentOperation::ReadText],
        expiry(),
    )
    .unwrap();
    let e = StoreEvidence::new(&s);
    let p = e.process(&da, InputKind::Utf8Text).unwrap();
    let hits = e.find_literal(&da, &p, "evidence", 1).unwrap();
    let proof = s
        .resolve_local_evidence_trusted(
            &a.project,
            ArtifactProjectOperation::LocalDraft,
            &da,
            &p,
            &hits[0],
        )
        .unwrap();
    let kind = LocalKind::Form(FormSpec {
        fields: vec![LocalField::Text, LocalField::Choice, LocalField::Selections],
        single_options: vec!["one".into(), "two".into()],
        multiple_options: vec!["a".into(), "b".into()],
    });
    let mut renewed = a.clone();
    renewed.binding_generation = Revision::new(2);
    s.issue_local_evidence_binding_trusted(&renewed, &kind, expiry(), &proof)
        .unwrap();
    let state = s.read_local_form(&renewed).unwrap();
    assert_eq!(state.values.text, "retained manual");
    assert_eq!(state.revision, Revision::new(1));
    assert_eq!(state.manual_fields, vec![LocalField::Text]);
    assert_eq!(
        s.confirm_local_form_submit_trusted("submit", &renewed, &preview.digest),
        Err(ContractError::BindingMismatch)
    );
    assert!(s.read_local_form(&a).is_err());
}

#[test]
fn persisted_source_cannot_pair_an_evidence_id_with_another_real_document() {
    let (_f, s, a) = fixture();
    let u = s.begin_upload("project").unwrap();
    s.append_chunk(&u.upload_id, b"Other synthetic evidence.")
        .unwrap();
    let blob = s.finish_blob(&u.upload_id, BlobKind::Document).unwrap();
    let metadata = s
        .register_document_trusted(
            "project",
            "other-evidence",
            "Other",
            DocumentFormat::Text,
            &blob,
        )
        .unwrap();
    let other = crate::artifacts::tests::grant(&s, metadata.document.clone(), 1);
    let rows = s
        .database()
        .query(
            "SELECT payload FROM artifact_local_evidence_sources_v1",
            &[],
        )
        .unwrap();
    let mut snapshot: serde_json::Value =
        serde_json::from_str(rows[0][0].as_deref().unwrap()).unwrap();
    snapshot["metadata"] = serde_json::to_value(metadata).unwrap();
    snapshot["authority"] = serde_json::to_value(other.authority).unwrap();
    s.database()
        .exec(
            "UPDATE artifact_local_evidence_sources_v1 SET payload=?",
            &[&snapshot.to_string()],
        )
        .unwrap();
    assert!(s.read_local_form(&a).is_err());
}
