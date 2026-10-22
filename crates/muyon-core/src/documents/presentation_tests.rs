//! Original synthetic bytes; no PDF parser, Android PFD or engine assertion.
use super::{reader::*, reader_tests::{setup, pins}, *};
use crate::contract::*;

#[test]
fn presentation_eof_retains_same_lease_and_snapshot_until_explicit_close() {
    let (_f, mut host, access) = setup();
    let opened = host.open_presentation(&access).unwrap();
    assert_eq!(opened.status.phase, PresentationPhase::Loading);
    assert!(opened.status.valid_for_ms > 0 && opened.status.valid_for_ms <= 30_000);
    let chunk = host.read_presentation_chunk(&opened.status.ticket, crate::blobs::MAX_CHUNK).unwrap();
    assert!(chunk.eof && !chunk.bytes.is_empty());
    assert_eq!(pins(host.store()), 1);
    crate::blobs::take_document_hash_bytes();
    let ready = host.check_presentation(&opened.status.ticket).unwrap();
    assert_eq!(ready.phase, PresentationPhase::Ready);
    assert_eq!(ready.ticket.session_id(), opened.session.session_id);
    let next = host.advance_presentation_frame(&ready.ticket).unwrap();
    assert_eq!(next.ticket.document(), &access.document);
    assert_eq!(next.ticket.generation().value(), ready.ticket.generation().value() + 1);
    assert_eq!(crate::blobs::take_document_hash_bytes(), 0, "display checks must not rehash the source");
    assert_eq!(pins(host.store()), 1);
    host.close_presentation(&next.ticket).unwrap();
    host.close_presentation(&next.ticket).unwrap();
    assert_eq!(pins(host.store()), 0);
    let events = host.take_presentation_invalidations();
    assert!(events.invalidated.iter().any(|event| event.session_id == opened.session.session_id));
}

#[test]
fn legacy_eof_still_closes_and_transport_cannot_bypass_presentation_ticket() {
    let (_f, mut host, access) = setup();
    let old = host.open(&access, DocumentReadPurpose::Render).unwrap();
    assert!(host.read_chunk(&old.session_id, crate::blobs::MAX_CHUNK).unwrap().eof);
    assert_eq!(pins(host.store()), 0);
    let opened = host.open_presentation(&access).unwrap();
    assert!(host.read_chunk(&opened.session.session_id, 7).is_err());
    assert_eq!(pins(host.store()), 1);
    assert!(host.read_presentation_chunk(&opened.status.ticket, 7).is_ok());
}

#[test]
fn stale_page_callback_cannot_show_or_close_new_frame() {
    let (_f, mut host, access) = setup();
    let opened = host.open_presentation(&access).unwrap();
    assert!(host.advance_presentation_frame(&opened.status.ticket).is_err(), "loading bytes are not ready for a page callback");
    host.read_presentation_chunk(&opened.status.ticket, crate::blobs::MAX_CHUNK).unwrap();
    let next = host.advance_presentation_frame(&opened.status.ticket).unwrap();
    assert!(host.check_presentation(&opened.status.ticket).is_err());
    assert!(host.close_presentation(&opened.status.ticket).is_err());
    assert!(host.close(opened.status.ticket.session_id()).is_err(), "legacy callback must not bypass presentation generation");
    assert!(host.is_current(opened.status.ticket.session_id()).is_err());
    assert_eq!(host.check_presentation(&next.ticket).unwrap().phase, PresentationPhase::Ready);
    assert_eq!(pins(host.store()), 1);
}

#[test]
fn display_after_eof_denies_revoked_generation_epoch_expiry_or_deleted_project() {
    for mutation in [
        "UPDATE document_grants SET active=0",
        "UPDATE document_grants SET generation='99'",
        "UPDATE document_grants SET owner_epoch='other-epoch'",
        "UPDATE document_grants SET expires_at_ms='0'",
        "UPDATE projects SET deleted=1",
    ] {
        let (_f, mut host, access) = setup();
        let opened = host.open_presentation(&access).unwrap();
        host.read_presentation_chunk(&opened.status.ticket, crate::blobs::MAX_CHUNK).unwrap();
        host.store().database().exec(mutation, &[]).unwrap();
        assert!(host.check_presentation(&opened.status.ticket).is_err(), "{mutation}");
        assert_eq!(pins(host.store()), 0);
        assert!(!host.take_presentation_invalidations().invalidated.is_empty());
    }
}

#[test]
fn selection_change_fences_old_scope_and_reopen_of_same_reference_fences_old_id() {
    let (_f, mut host, access) = setup();
    let old = host.open_presentation(&access).unwrap();
    host.read_presentation_chunk(&old.status.ticket, crate::blobs::MAX_CHUNK).unwrap();
    let fresh = host.open_presentation(&access).unwrap();
    assert_ne!(old.status.ticket.session_id(), fresh.status.ticket.session_id());
    assert!(host.check_presentation(&old.status.ticket).is_err());
    assert!(host.check_presentation(&fresh.status.ticket).is_ok());
    let foreign = DocumentAccess { document: DocumentRef::new(Scope { workspace_id: "workspace".into(), project_id: Some("other-project".into()) }, "document", Revision::new(1), DocumentFormat::Pdf).unwrap(), authority: access.authority };
    assert!(host.open_presentation(&foreign).is_err());
    assert!(host.check_presentation(&fresh.status.ticket).is_err());
    assert_eq!(pins(host.store()), 0);
}

#[test]
fn changed_head_after_eof_invalidates_without_reopening_latest_revision() {
    let (_f, mut host, access) = setup();
    let opened = host.open_presentation(&access).unwrap();
    host.read_presentation_chunk(&opened.status.ticket, crate::blobs::MAX_CHUNK).unwrap();
    let tx = host.store().database().transaction().unwrap();
    let next = host.store().document_clone_in_transaction(&tx, &access.document, "Explicit new revision", &opened.session.metadata.blob).unwrap();
    tx.commit().unwrap();
    assert!(host.check_presentation(&opened.status.ticket).is_err());
    assert_ne!(next.document.revision(), access.document.revision());
    assert_eq!(pins(host.store()), 0);
    assert!(host.open_presentation(&access).is_err());
}

#[test]
fn check_never_renews_absolute_or_idle_deadline_and_expiry_frees_resources() {
    for idle in [true, false] {
        let (_f, mut host, access) = setup();
        let opened = host.open_presentation(&access).unwrap();
        host.read_presentation_chunk(&opened.status.ticket, crate::blobs::MAX_CHUNK).unwrap();
        let first = host.check_presentation(&opened.status.ticket).unwrap();
        let second = host.check_presentation(&opened.status.ticket).unwrap();
        assert!(second.valid_for_ms <= first.valid_for_ms);
        host.expire_for_test(opened.status.ticket.session_id(), idle);
        assert!(host.check_presentation(&opened.status.ticket).is_err());
        assert_eq!(pins(host.store()), 0);
    }
}

#[test]
fn presentation_cleanup_failure_poison_withholds_lifecycle_and_retains_budget_until_retry() {
    let (_f, mut host, access) = setup();
    let opened = host.open_presentation(&access).unwrap();
    host.read_presentation_chunk(&opened.status.ticket, crate::blobs::MAX_CHUNK).unwrap();
    host.store().database().exec("CREATE TRIGGER fail_presentation_cleanup BEFORE DELETE ON blob_pins WHEN OLD.kind='reader' BEGIN SELECT RAISE(ABORT,'synthetic cleanup fault'); END", &[]).unwrap();
    assert!(host.close_presentation(&opened.status.ticket).is_err());
    assert!(host.check_presentation(&opened.status.ticket).is_err());
    assert!(host.open_presentation(&access).is_err());
    assert_eq!(pins(host.store()), 1);
    let events = host.take_presentation_invalidations();
    assert!(events.clear_all);
    assert!(events.invalidated.iter().any(|event| event.cleanup_pending));
    host.store().database().exec("DROP TRIGGER fail_presentation_cleanup", &[]).unwrap();
    host.close_all().unwrap();
    assert_eq!(pins(host.store()), 0);
}

#[test]
fn invalidation_queue_is_bounded_and_overflow_requests_host_clear_all() {
    let (_f, mut host, access) = setup();
    for _ in 0..20 {
        let opened = host.open_presentation(&access).unwrap();
        host.close_presentation(&opened.status.ticket).unwrap();
    }
    let events = host.take_presentation_invalidations();
    assert!(events.clear_all);
    assert!(events.invalidated.len() <= MAX_READ_SESSIONS);
    assert_eq!(pins(host.store()), 0);
}
