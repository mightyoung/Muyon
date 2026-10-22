use super::*;
use super::tests::{Fixture, generated, grant, human, upload};
use crate::{contract::*, documents::*};
use std::time::{SystemTime, UNIX_EPOCH};
fn project_access(s: &BusinessStore, actor: &str, grant_id: &str, generation: u64, operations: &[ArtifactProjectOperation]) -> ArtifactProjectAccess {
    let access = ArtifactProjectAccess { scope: Scope { workspace_id: "workspace".into(), project_id: Some("project".into()) }, actor_id: actor.into(), project_revision: Revision::new(1), authority: AuthorityBinding { grant_id: grant_id.into(), generation: Revision::new(generation), owner_epoch: "epoch".into() } };
    let expiry = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64 + 29_000;
    s.issue_artifact_project_grant_trusted(&access, operations, expiry).unwrap(); access
}
fn all_access(s: &BusinessStore) -> ArtifactProjectAccess { project_access(s, "actor", "project-grant", 1, &[ArtifactProjectOperation::Save, ArtifactProjectOperation::Discover, ArtifactProjectOperation::LookupOwnSaves]) }
fn archive(id: &str) -> ArtifactSaveOperation { ArtifactSaveOperation::Archive { artifact_id: id.into(), origin: generated() } }
#[test]
fn save_journal_duplicates_return_original_receipt_and_parameter_change_conflicts() {
    let f = Fixture::new(); let (s, out, source) = f.setup(); s.initialize_artifact_workflows_trusted().unwrap(); let p = all_access(&s);
    let first = s.submit_artifact_save_trusted("save-intent", &p, &archive("artifact"), &out, &[source.clone()]).unwrap();
    assert_eq!(first.status, ArtifactSaveStatus::Committed);
    assert_eq!(first.recovery_action, RecoveryAction::None);
    let duplicate = s.submit_artifact_save_trusted("save-intent", &p, &archive("artifact"), &out, &[source.clone()]).unwrap();
    assert_eq!(duplicate, first);
    assert_eq!(s.submit_artifact_save_trusted("save-intent", &p, &archive("different"), &out, &[source.clone()]), Err(ContractError::IntentConflict));
    assert_eq!(s.artifact_history("artifact", None, 1, &out, &[source]).unwrap().len(), 1);
    drop(s); let s = f.open();
    assert_eq!(s.lookup_artifact_save("save-intent", &p).unwrap(), first);
}
#[test]
fn pending_storage_failure_never_reexecutes_and_lookup_never_writes() {
    let f = Fixture::new(); let (s, out, source) = f.setup(); s.initialize_artifact_workflows_trusted().unwrap(); let p = all_access(&s);
    s.database().exec("CREATE TRIGGER fail_artifact BEFORE INSERT ON artifact_revisions BEGIN SELECT RAISE(ABORT,'synthetic'); END", &[]).unwrap();
    let first = s.submit_artifact_save_trusted("save-intent", &p, &archive("artifact"), &out, &[source.clone()]).unwrap();
    assert_eq!(first.status, ArtifactSaveStatus::Unknown); assert_eq!(first.recovery_action, RecoveryAction::QueryOriginal); assert!(first.receipt.is_none());
    s.database().exec("DROP TRIGGER fail_artifact", &[]).unwrap();
    let before = s.database().query("SELECT * FROM artifact_save_intents_v1", &[]).unwrap();
    assert_eq!(s.lookup_artifact_save("save-intent", &p).unwrap().status, ArtifactSaveStatus::Unknown);
    assert_eq!(s.lookup_artifact_save("absent", &p).unwrap().status, ArtifactSaveStatus::Unknown);
    assert_eq!(s.database().query("SELECT * FROM artifact_save_intents_v1", &[]).unwrap(), before);
    drop(s); let s = f.open();
    assert_eq!(s.submit_artifact_save_trusted("save-intent", &p, &archive("artifact"), &out, &[source.clone()]).unwrap().status, ArtifactSaveStatus::Unknown);
    assert!(s.database().query("SELECT * FROM artifact_heads", &[]).unwrap().is_empty());
}
#[test]
fn revise_receipt_is_atomic_and_survives_later_head_change() {
    let f = Fixture::new(); let (s, out, source) = f.setup(); s.initialize_artifact_workflows_trusted().unwrap(); let p = all_access(&s);
    s.submit_artifact_save_trusted("archive", &p, &archive("artifact"), &out, &[source.clone()]).unwrap();
    let operation = ArtifactSaveOperation::Revise { artifact_id: "artifact".into(), expected_revision: Revision::new(1), finished: upload(&s, b"%PDF-1.4\nhuman revision\n%%EOF\n"), title: "Human".into(), origin: human() };
    let saved = s.submit_artifact_save_trusted("human-save", &p, &operation, &out, &[source.clone()]).unwrap();
    let receipt = saved.receipt.clone().unwrap(); assert_eq!(receipt.artifact_revision, Revision::new(2));
    let current = grant(&s, receipt.document.clone(), 2);
    assert_eq!(s.submit_artifact_save_trusted("human-save", &p, &operation, &out, &[source.clone()]).unwrap(), saved);
    let generated_op = ArtifactSaveOperation::Revise { artifact_id: "artifact".into(), expected_revision: Revision::new(2), finished: upload(&s, b"%PDF-1.4\ngenerated overwrite\n%%EOF\n"), title: "Generated".into(), origin: generated() };
    let denied = s.submit_artifact_save_trusted("generated", &p, &generated_op, &current, &[source.clone()]).unwrap();
    assert_eq!(denied.status, ArtifactSaveStatus::Rejected); assert_eq!(denied.error, Some(ContractError::IntentConflict));
    assert_eq!(s.lookup_artifact_save("human-save", &p).unwrap(), saved);
    assert_eq!(s.read_document(&current).unwrap().document, receipt.document);
}
#[test]
fn own_receipt_permission_never_implies_discovery_or_another_actors_journal() {
    let f = Fixture::new(); let (s, out, source) = f.setup(); s.initialize_artifact_workflows_trusted().unwrap(); let p = all_access(&s);
    s.submit_artifact_save_trusted("intent", &p, &archive("artifact"), &out, &[source]).unwrap();
    let own = project_access(&s, "actor", "own-grant", 1, &[ArtifactProjectOperation::LookupOwnSaves]);
    assert!(s.lookup_artifact_save("intent", &own).unwrap().receipt.is_some());
    assert_eq!(s.discover_project_artifacts(&own, None, 10), Err(ContractError::InvalidAuthority));
    let other = project_access(&s, "another-actor", "other-grant", 1, &[ArtifactProjectOperation::LookupOwnSaves]);
    let hidden = s.lookup_artifact_save("intent", &other).unwrap();
    assert_eq!(hidden, s.lookup_artifact_save("absent", &other).unwrap());
    assert_eq!(hidden.status, ArtifactSaveStatus::Unknown); assert!(hidden.receipt.is_none());
    s.revoke_artifact_project_grant_trusted(&own).unwrap();
    assert_eq!(s.lookup_artifact_save("intent", &own), Err(ContractError::InvalidAuthority));
}
#[test]
fn catalog_requires_independent_project_grant_and_returns_inventory_only() {
    let f = Fixture::new(); let (s, out, source) = f.setup(); s.initialize_artifact_workflows_trusted().unwrap(); let p = all_access(&s);
    s.submit_artifact_save_trusted("intent", &p, &archive("artifact"), &out, &[source]).unwrap();
    // Existing valid document grant is deliberately not a project-discovery grant.
    let forged = ArtifactProjectAccess { scope: out.document.scope().clone(), actor_id: "actor".into(), project_revision: Revision::new(1), authority: out.authority.clone() };
    assert_eq!(s.discover_project_artifacts(&forged, None, 10), Err(ContractError::InvalidAuthority));
    let page = s.discover_project_artifacts(&p, None, 1).unwrap(); assert_eq!(page.len(), 1); assert_eq!(page[0].artifact_id, "artifact"); assert_eq!(page[0].title, "Synthetic");
    assert!(s.discover_project_artifacts(&p, Some("artifact"), 10).unwrap().is_empty());
    let mut wrong = p.clone(); wrong.scope.project_id = Some("another-project".into());
    assert!(s.discover_project_artifacts(&wrong, None, 10).is_err());
    s.database().exec("UPDATE artifact_project_grants_v1 SET expires_at_ms='0'", &[]).unwrap();
    assert_eq!(s.discover_project_artifacts(&p, None, 10), Err(ContractError::InvalidAuthority));
}
#[test]
fn historical_output_and_source_require_explicit_core_history_policy() {
    let f = Fixture::new(); let (s, out, source) = f.setup();
    let original = s.archive_artifact_trusted("artifact", &out, &[source.clone()], &generated()).unwrap();
    let edited = s.revise_artifact_trusted("artifact", &Revision::new(1), &out, &upload(&s, b"%PDF-1.4\nhuman history\n%%EOF\n"), "Human", &[source.clone()], &human()).unwrap();
    let current_output = grant(&s, edited.document.document.clone(), 2);
    let next_source = s.publish_document_revision_trusted(&source.document, "New source", DocumentFormat::Pdf, &upload(&s, b"%PDF-1.4\nnew source\n%%EOF\n")).unwrap();
    let current_source = grant(&s, next_source.document, 2);
    assert!(s.read_artifact_revision("artifact", &Revision::new(1), &current_output, &[current_source.clone()]).is_err());
    s.initialize_document_history_trusted().unwrap();
    let expires = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64 + 20_000;
    s.issue_document_history_grant_trusted(&current_output, &out.document, &[DocumentOperation::ReadText], expires).unwrap();
    assert!(s.read_artifact_revision("artifact", &Revision::new(1), &current_output, &[current_source.clone()]).is_err());
    s.issue_document_history_grant_trusted(&current_source, &source.document, &[DocumentOperation::ReadText], expires).unwrap();
    assert_eq!(s.read_artifact_revision("artifact", &Revision::new(1), &current_output, &[current_source.clone()]).unwrap(), original);
    let page = s.artifact_history("artifact", None, 10, &current_output, &[current_source.clone()]).unwrap();
    assert_eq!(page, vec![edited, original.clone()]);
    s.revoke_document_history_grant_trusted(&current_source, &source.document).unwrap();
    assert_eq!(s.read_artifact_revision("artifact", &Revision::new(1), &current_output, &[current_source]), Err(ContractError::InvalidAuthority));
    // No latest-source substitution: original reference remains persisted.
    let raw = s.database().query("SELECT payload FROM artifact_revisions WHERE artifact_id='artifact' AND revision='1'", &[]).unwrap();
    let persisted: ArtifactRevision = serde_json::from_str(raw[0][0].as_deref().unwrap()).unwrap();
    assert_eq!(persisted, original);
}
#[test]
fn receipt_write_failure_rolls_back_publication_and_keeps_pending_without_retry() {
    let f = Fixture::new(); let (s, out, source) = f.setup(); s.initialize_artifact_workflows_trusted().unwrap(); let p = all_access(&s);
    s.submit_artifact_save_trusted("archive", &p, &archive("artifact"), &out, &[source.clone()]).unwrap();
    s.database().exec("CREATE TRIGGER fail_receipt BEFORE UPDATE ON artifact_save_intents_v1 WHEN NEW.status='committed' BEGIN SELECT RAISE(ABORT,'synthetic receipt failure'); END", &[]).unwrap();
    let operation = ArtifactSaveOperation::Revise { artifact_id: "artifact".into(), expected_revision: Revision::new(1), finished: upload(&s, b"%PDF-1.4\nreceipt rollback\n%%EOF\n"), title: "Uncommitted".into(), origin: human() };
    let result = s.submit_artifact_save_trusted("failed-receipt", &p, &operation, &out, &[source.clone()]).unwrap();
    assert_eq!(result.status, ArtifactSaveStatus::Unknown); assert_eq!(result.recovery_action, RecoveryAction::QueryOriginal);
    assert_eq!(s.read_document(&out).unwrap().title, "Synthetic");
    assert_eq!(s.artifact_history("artifact", None, 10, &out, &[source.clone()]).unwrap().len(), 1);
    assert_eq!(s.lookup_artifact_save("failed-receipt", &p).unwrap().status, ArtifactSaveStatus::Unknown);
    s.database().exec("DROP TRIGGER fail_receipt", &[]).unwrap();
    assert_eq!(s.submit_artifact_save_trusted("failed-receipt", &p, &operation, &out, &[source.clone()]).unwrap().status, ArtifactSaveStatus::Unknown);
    assert_eq!(s.read_document(&out).unwrap().document, out.document);
}
#[test]
fn rejected_projection_requires_a_durable_terminal_row() {
    let f = Fixture::new(); let (s, out, source) = f.setup(); s.initialize_artifact_workflows_trusted().unwrap(); let p = all_access(&s);
    s.submit_artifact_save_trusted("archive", &p, &archive("artifact"), &out, &[source.clone()]).unwrap();
    s.database().exec("CREATE TRIGGER ignore_rejection BEFORE UPDATE ON artifact_save_intents_v1 WHEN NEW.status='rejected' BEGIN SELECT RAISE(IGNORE); END", &[]).unwrap();
    // This duplicate artifact ID is a deterministic effect conflict, but the
    // synthetic fault prevents its rejection from becoming a durable terminal.
    let result = s.submit_artifact_save_trusted("cannot-reject", &p, &archive("artifact"), &out, &[source]).unwrap();
    assert_eq!(result.status, ArtifactSaveStatus::Unknown); assert!(result.receipt.is_none());
    assert_eq!(s.lookup_artifact_save("cannot-reject", &p).unwrap().status, ArtifactSaveStatus::Unknown);
}
#[test]
fn independent_project_grants_reject_expiry_generation_epoch_and_project_changes() {
    let f = Fixture::new(); let (s, out, source) = f.setup(); s.initialize_artifact_workflows_trusted().unwrap(); let p = all_access(&s);
    let discover = project_access(&s, "actor", "discover-grant", 1, &[ArtifactProjectOperation::Discover]);
    assert_eq!(s.submit_artifact_save_trusted("not-authorized", &discover, &archive("artifact"), &out, &[source]), Err(ContractError::InvalidAuthority));
    assert_eq!(s.lookup_artifact_save("not-authorized", &discover), Err(ContractError::InvalidAuthority));
    let mut wrong = p.clone(); wrong.authority.owner_epoch = "old-epoch".into();
    assert_eq!(s.discover_project_artifacts(&wrong, None, 10), Err(ContractError::InvalidAuthority));
    let next = project_access(&s, "actor", "project-grant", 2, &[ArtifactProjectOperation::Discover]);
    assert_eq!(s.discover_project_artifacts(&p, None, 10), Err(ContractError::InvalidAuthority));
    assert!(s.discover_project_artifacts(&next, None, 10).unwrap().is_empty());
    s.revoke_artifact_project_grant_trusted(&next).unwrap();
    assert_eq!(s.discover_project_artifacts(&next, None, 10), Err(ContractError::InvalidAuthority));
    s.database().exec("UPDATE projects SET revision='2' WHERE id='project'", &[]).unwrap();
    assert_eq!(s.discover_project_artifacts(&discover, None, 10), Err(ContractError::RevisionConflict));
}
#[test]
fn receipt_tail_invalidation_rolls_back_all_effects_and_preserves_original_pending() {
    for mutation in [
        "UPDATE document_grants SET active=0 WHERE grant_id='grant-report'",
        "UPDATE document_grants SET expires_at_ms='0' WHERE grant_id='grant-report'",
        "UPDATE document_grants SET generation='999' WHERE grant_id='grant-report'",
        "UPDATE document_grants SET active=0 WHERE grant_id='grant-source'",
        "UPDATE document_grants SET expires_at_ms='0' WHERE grant_id='grant-source'",
        "UPDATE document_grants SET generation='999' WHERE grant_id='grant-source'",
        "UPDATE document_history_grants_v1 SET active=0",
        "UPDATE document_history_grants_v1 SET expires_at_ms='0'",
        "UPDATE document_history_grants_v1 SET generation='999'",
        "UPDATE artifact_project_grants_v1 SET active=0",
    ] {
        let f = Fixture::new(); let (s, out, source) = f.setup(); s.initialize_artifact_workflows_trusted().unwrap(); let p = all_access(&s);
        s.submit_artifact_save_trusted("archive", &p, &archive("artifact"), &out, &[source.clone()]).unwrap();
        let next = s.publish_document_revision_trusted(&source.document, "Source advanced", DocumentFormat::Pdf, &upload(&s, b"%PDF-1.4\nsource advanced\n%%EOF\n")).unwrap();
        let current_source = grant(&s, next.document, 2);
        s.initialize_document_history_trusted().unwrap();
        let expiry = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64 + 20_000;
        s.issue_document_history_grant_trusted(&current_source, &source.document, &[DocumentOperation::ReadText], expiry).unwrap();
        let operation = ArtifactSaveOperation::Revise { artifact_id: "artifact".into(), expected_revision: Revision::new(1), finished: upload(&s, b"%PDF-1.4\nreceipt tail rollback\n%%EOF\n"), title: "Must not commit".into(), origin: human() };
        let finished = match &operation { ArtifactSaveOperation::Revise { finished, .. } => finished, _ => unreachable!() };
        let before_document = s.read_document(&out).unwrap();
        let before_artifact = s.artifact_history("artifact", None, 10, &out, &[current_source.clone()]).unwrap();
        let before_refs = s.database().query("SELECT * FROM blob_references ORDER BY reference_id", &[]).unwrap();
        let before_pins = s.database().query("SELECT * FROM blob_pins ORDER BY pin_id", &[]).unwrap();
        let before_upload = s.lookup_upload(&finished.upload_id).unwrap();
        let trigger = format!("CREATE TRIGGER invalidate_on_receipt AFTER UPDATE ON artifact_save_intents_v1 WHEN NEW.intent_id='tail-save' AND NEW.status='committed' BEGIN {mutation}; END");
        s.database().exec(&trigger, &[]).unwrap();
        let result = s.submit_artifact_save_trusted("tail-save", &p, &operation, &out, &[current_source.clone()]).unwrap();
        assert_eq!(result.status, ArtifactSaveStatus::Unknown, "{mutation}");
        assert_eq!(result.recovery_action, RecoveryAction::QueryOriginal); assert!(result.receipt.is_none());
        assert_eq!(s.read_document(&out).unwrap(), before_document, "{mutation}");
        assert_eq!(s.artifact_history("artifact", None, 10, &out, &[current_source.clone()]).unwrap(), before_artifact);
        assert_eq!(s.database().query("SELECT * FROM blob_references ORDER BY reference_id", &[]).unwrap(), before_refs);
        assert_eq!(s.database().query("SELECT * FROM blob_pins ORDER BY pin_id", &[]).unwrap(), before_pins);
        assert_eq!(s.lookup_upload(&finished.upload_id).unwrap(), before_upload);
        assert_eq!(s.database().query("SELECT status,receipt_json,error FROM artifact_save_intents_v1 WHERE intent_id='tail-save'", &[]).unwrap(), vec![vec![Some("pending".into()), None, None]]);
        assert_eq!(s.database().query("SELECT revision FROM document_revisions WHERE document_id='report' ORDER BY revision", &[]).unwrap(), vec![vec![Some("1".into())]]);
        s.database().exec("DROP TRIGGER invalidate_on_receipt", &[]).unwrap();
        assert_eq!(s.lookup_artifact_save("tail-save", &p).unwrap().status, ArtifactSaveStatus::Unknown);
        drop(s); let s = f.open();
        assert_eq!(s.submit_artifact_save_trusted("tail-save", &p, &operation, &out, &[current_source.clone()]).unwrap().status, ArtifactSaveStatus::Unknown);
        assert_eq!(s.read_document(&out).unwrap(), before_document);
    }
}
