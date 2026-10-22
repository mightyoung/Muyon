//! Synthetic existing-grant paths only. No Activity, PFD, engine or no-grant issuer.
use super::{reader::*, reader_tests::{setup, pins}, reading_policy::*, *};
use crate::contract::*;
fn scope() -> PolicyScope { PolicyScope { service_session: "service".into(), generation: Revision::new(1), project: "project".into() } }
fn surface() -> ReadingSurfaceBinding { ReadingSurfaceBinding { surface_id: "surface".into(), lifecycle_epoch: "lifecycle".into(), selection_sequence: Revision::new(1) } }
fn begin_request(access: &DocumentAccess, opened: &DocumentPresentationInfo) -> PolicyBeginRequest {
    PolicyBeginRequest { scope: scope(), access: access.clone(), source_digest: opened.session.metadata.blob.digest.clone(), presentation_id: "initial".into(), frame_generation: opened.status.ticket.generation().clone(), surface_binding: surface(), original_attempt_id: "begin".into() }
}
fn prepare_request(root: &OriginalPolicyOutcome, attempt: &str) -> PolicyPrepareRequest {
    let access = root.access.as_ref().unwrap();
    PolicyPrepareRequest { scope: scope(), root_id: root.root_id.clone().unwrap(), expected_root_revision: root.root_revision.clone().unwrap(), expected_grant_id: access.authority.grant_id.clone(), expected_grant_generation: access.authority.generation.clone(), original_attempt_id: attempt.into(), surface_binding: surface(), expected_presentation_id: root.presentation_id.clone().unwrap(), expected_frame_generation: root.frame_generation.clone().unwrap() }
}
fn renew_request(root: &OriginalPolicyOutcome, prepared: &PreparedPolicyOutcome) -> PolicyRenewRequest {
    PolicyRenewRequest { scope: scope(), root_id: root.root_id.clone().unwrap(), expected_root_revision: root.root_revision.clone().unwrap(), original_attempt_id: prepared.original_attempt_id.clone(), challenge_id: prepared.challenge_id.clone().unwrap(), surface_binding: surface(), observation_id: format!("observation-{}", prepared.original_attempt_id) }
}
fn continuation(issued: &OriginalPolicyOutcome) -> PolicyContinueRequest {
    PolicyContinueRequest { scope: scope(), root_id: issued.root_id.clone().unwrap(), resulting_root_revision: issued.root_revision.clone().unwrap(), original_renew_attempt_id: issued.original_attempt_id.clone(), continuation_token: issued.continuation_token.clone().unwrap(), predecessor_presentation_id: issued.presentation_id.clone().unwrap(), predecessor_frame_generation: issued.frame_generation.clone().unwrap(), presentation_id: "continued".into() }
}
fn stop_request(root: &OriginalPolicyOutcome) -> PolicyStopRequest {
    PolicyStopRequest { scope: scope(), root_id: root.root_id.clone().unwrap(), expected_root_revision: root.root_revision.clone().unwrap(), original_attempt_id: "stop".into(), reason: PolicyStopReason::UserClose }
}
fn root_start(reader: &mut DocumentReaderHost, policy: &mut ReadingPolicyHost, access: &DocumentAccess) -> (DocumentPresentationInfo, OriginalPolicyOutcome) {
    policy.selection_changed(reader, &scope(), &Revision::new(1)).unwrap();
    let opened = reader.open_presentation(access).unwrap();
    let root = policy.begin(reader, &begin_request(access, &opened), &opened.status.ticket, &Revision::new(1)).unwrap();
    (opened, root)
}
#[test]
fn policy_observe_is_readonly_and_distinguishes_expiry_revocation_and_replacement() {
    let (_f, mut reader, access) = setup(); let mut policy = ReadingPolicyHost::open(&mut reader).unwrap();
    let request = PolicyObserveRequest { scope: scope(), access: access.clone() };
    assert_eq!(policy.observe(&mut reader, &request).unwrap().availability, PolicyAvailability::Valid);
    reader.store().database().exec("UPDATE document_grants SET expires_at_ms='0'", &[]).unwrap();
    assert_eq!(policy.observe(&mut reader, &request).unwrap().availability, PolicyAvailability::NaturallyExpired);
    reader.store().database().exec("UPDATE document_grants SET active=0", &[]).unwrap();
    assert_eq!(policy.observe(&mut reader, &request).unwrap().availability, PolicyAvailability::Revoked);
    reader.store().database().exec("UPDATE document_grants SET generation='99'", &[]).unwrap();
    assert_eq!(policy.observe(&mut reader, &request).unwrap().availability, PolicyAvailability::Replaced);
    assert_eq!(pins(reader.store()), 0);
}
#[test]
fn begin_requires_a_real_current_render_ticket_and_valid_existing_grant() {
    let (_f, mut reader, access) = setup(); let mut policy = ReadingPolicyHost::open(&mut reader).unwrap();
    policy.selection_changed(&mut reader, &scope(), &Revision::new(1)).unwrap();
    let opened = reader.open_presentation(&access).unwrap(); let request = begin_request(&access, &opened);
    reader.store().database().exec("UPDATE document_grants SET expires_at_ms='0'", &[]).unwrap();
    assert!(policy.begin(&mut reader, &request, &opened.status.ticket, &Revision::new(1)).is_err());
}
#[test]
fn first_renewal_creates_owned_child_without_modifying_shared_parent_and_handoff_is_real() {
    let (_f, mut reader, access) = setup(); let mut policy = ReadingPolicyHost::open(&mut reader).unwrap();
    let (opened, root) = root_start(&mut reader, &mut policy, &access);
    let parent = reader.store().database().query("SELECT * FROM document_grants WHERE grant_id=?", &[&access.authority.grant_id]).unwrap();
    let prepared = policy.prepare(&mut reader, &prepare_request(&root, "renew")).unwrap();
    let issued = policy.renew(&mut reader, &renew_request(&root, &prepared)).unwrap();
    assert_eq!(issued.status, PolicyOutcomeStatus::Issued);
    let child = issued.access.as_ref().unwrap(); assert_ne!(child.authority.grant_id, access.authority.grant_id); assert_eq!(child.authority.generation, Revision::new(1));
    assert_eq!(reader.store().database().query("SELECT * FROM document_grants WHERE grant_id=?", &[&access.authority.grant_id]).unwrap(), parent);
    assert!(reader.check_presentation(&opened.status.ticket).is_err());
    let next = policy.continue_presentation(&mut reader, &continuation(&issued)).unwrap(); let info = next.presentation.unwrap();
    assert_ne!(info.status.ticket.session_id(), opened.status.ticket.session_id());
    assert_eq!(info.status.ticket.document(), &access.document); assert_eq!(pins(reader.store()), 1);
    assert!(reader.check_presentation(&info.status.ticket).is_ok());
    let duplicate = policy.continue_presentation(&mut reader, &continuation(&issued)).unwrap(); assert!(duplicate.presentation.is_none()); assert!(duplicate.outcome.historical); assert_eq!(pins(reader.store()), 1);
}
#[test]
fn natural_expiry_after_begin_can_renew_but_stop_never_revives() {
    let (_f, mut reader, access) = setup(); let mut policy = ReadingPolicyHost::open(&mut reader).unwrap();
    let (_opened, root) = root_start(&mut reader, &mut policy, &access);
    reader.store().database().exec("UPDATE document_grants SET expires_at_ms='0'", &[]).unwrap();
    let prepared = policy.prepare(&mut reader, &prepare_request(&root, "renew")).unwrap();
    let issued = policy.renew(&mut reader, &renew_request(&root, &prepared)).unwrap(); assert_eq!(issued.status, PolicyOutcomeStatus::Issued);
    policy.stop(&mut reader, &stop_request(&root)).unwrap();
    assert!(policy.continue_presentation(&mut reader, &continuation(&issued)).is_err());
    assert!(policy.prepare(&mut reader, &prepare_request(&root, "late")).is_err());
    assert_eq!(reader.store().database().query("SELECT active FROM document_grants WHERE grant_id=?", &[&access.authority.grant_id]).unwrap()[0][0].as_deref(), Some("1"));
}
#[test]
fn parent_revoke_or_external_generation_change_fences_root_even_if_row_reactivated() {
    for action in ["UPDATE document_grants SET active=0", "UPDATE document_grants SET generation='99'"] {
        let (_f, mut reader, access) = setup(); let mut policy = ReadingPolicyHost::open(&mut reader).unwrap(); let (_o, root) = root_start(&mut reader, &mut policy, &access);
        let prepared = policy.prepare(&mut reader, &prepare_request(&root, "renew")).unwrap();
        reader.store().database().exec(action, &[]).unwrap();
        reader.store().database().exec("UPDATE document_grants SET active=1", &[]).unwrap();
        assert!(policy.renew(&mut reader, &renew_request(&root, &prepared)).is_err());
    }
}
#[test]
fn new_selection_b_rejects_late_a_before_any_destructive_open() {
    let (_f, mut reader, access) = setup(); let mut policy = ReadingPolicyHost::open(&mut reader).unwrap(); let (_o, root) = root_start(&mut reader, &mut policy, &access);
    let prepared = policy.prepare(&mut reader, &prepare_request(&root, "renew")).unwrap(); let issued = policy.renew(&mut reader, &renew_request(&root, &prepared)).unwrap();
    policy.selection_changed(&mut reader, &scope(), &Revision::new(2)).unwrap();
    let b = reader.open_presentation(&access).unwrap(); let count = pins(reader.store());
    assert!(policy.continue_presentation(&mut reader, &continuation(&issued)).is_err());
    assert_eq!(pins(reader.store()), count); assert!(reader.check_presentation(&b.status.ticket).is_ok());
}
#[test]
fn duplicate_original_renew_is_historical_and_altered_payload_cannot_reissue() {
    let (_f, mut reader, access) = setup(); let mut policy = ReadingPolicyHost::open(&mut reader).unwrap(); let (_o, root) = root_start(&mut reader, &mut policy, &access);
    let prepared = policy.prepare(&mut reader, &prepare_request(&root, "renew")).unwrap(); let request = renew_request(&root, &prepared);
    let first = policy.renew(&mut reader, &request).unwrap(); let again = policy.renew(&mut reader, &request).unwrap();
    assert_eq!(first.outcome_id, again.outcome_id); assert_eq!(first.expires_at_ms, again.expires_at_ms); assert!(again.historical);
    let mut altered = request; altered.observation_id = "another".into(); assert!(policy.renew(&mut reader, &altered).is_err());
}
#[test]
fn reconcile_fences_prepared_attempt_and_missing_original_before_late_renew() {
    let (_f, mut reader, access) = setup(); let mut policy = ReadingPolicyHost::open(&mut reader).unwrap(); let (_o, root) = root_start(&mut reader, &mut policy, &access);
    let prepared = policy.prepare(&mut reader, &prepare_request(&root, "renew")).unwrap();
    let reconciled = policy.reconcile(&mut reader, &PolicyReconcileRequest { scope: scope(), original_attempt_id: "renew".into(), kind: PolicyKind::Renew }).unwrap();
    assert_eq!(reconciled.status, PolicyOutcomeStatus::FencedNotCommitted);
    assert!(policy.renew(&mut reader, &renew_request(&root, &prepared)).is_err());
}
#[test]
fn frame_advance_invalidates_original_prepared_frame_instead_of_adopting_latest() {
    let (_f, mut reader, access) = setup(); let mut policy = ReadingPolicyHost::open(&mut reader).unwrap(); let (opened, root) = root_start(&mut reader, &mut policy, &access);
    let prepared = policy.prepare(&mut reader, &prepare_request(&root, "renew")).unwrap();
    reader.read_presentation_chunk(&opened.status.ticket, crate::blobs::MAX_CHUNK).unwrap();
    let next = reader.advance_presentation_frame(&opened.status.ticket).unwrap(); policy.frame_advanced(&mut reader, &opened.status.ticket, &next.ticket).unwrap();
    assert!(policy.renew(&mut reader, &renew_request(&root, &prepared)).is_err()); assert!(reader.check_presentation(&next.ticket).is_ok());
}
#[test]
fn project_or_head_change_cannot_be_recovered_by_clock_or_active_flag() {
    for action in ["UPDATE projects SET deleted=1 WHERE id='project'", "UPDATE document_heads SET revision='99'"] {
        let (_f, mut reader, access) = setup(); let mut policy = ReadingPolicyHost::open(&mut reader).unwrap(); let (_o, root) = root_start(&mut reader, &mut policy, &access);
        let prepared = policy.prepare(&mut reader, &prepare_request(&root, "renew")).unwrap(); reader.store().database().exec(action, &[]).unwrap();
        assert!(policy.renew(&mut reader, &renew_request(&root, &prepared)).is_err());
    }
}
