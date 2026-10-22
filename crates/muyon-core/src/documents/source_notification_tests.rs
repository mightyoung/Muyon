//! Integration regressions against real fixed Artifacts/Evidence, synthetic data.
use super::{storage_tests::Fixture, *};
use crate::{
    artifacts::{local_interactions::*, *},
    blobs::BlobKind,
    business::BusinessStore,
    contract::*,
    evidence::{store::StoreEvidence, InputKind},
    sqlite::Db,
};
use std::collections::BTreeSet;

fn expiry() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
        + 25_000
}
fn upload(store: &BusinessStore, project: &str, bytes: &[u8]) -> crate::blobs::FinishedBlob {
    let upload = store.begin_upload(project).unwrap();
    store.append_chunk(&upload.upload_id, bytes).unwrap();
    store
        .finish_blob(&upload.upload_id, BlobKind::Document)
        .unwrap()
}
fn bind(store: &BusinessStore, source: &DocumentAccess, local: &LocalAccess, kind: &LocalKind) {
    let evidence = StoreEvidence::new(store);
    let processing = evidence.process(source, InputKind::Utf8Text).unwrap();
    let hits = evidence
        .find_literal(source, &processing, "synthetic", 1)
        .unwrap();
    let proof = store
        .resolve_local_evidence_trusted(
            &local.project,
            ArtifactProjectOperation::LocalDraft,
            source,
            &processing,
            &hits[0],
        )
        .unwrap();
    assert_eq!(local.object.target, proof.target());
    store
        .issue_local_evidence_binding_trusted(local, kind, expiry(), &proof)
        .unwrap();
}
fn fixture() -> (
    Fixture,
    BusinessStore,
    DocumentAccess,
    LocalAccess,
    LocalKind,
) {
    let f = Fixture::new();
    let (store, _) = f.setup();
    store.initialize_artifacts_trusted().unwrap();
    store.initialize_artifact_workflows_trusted().unwrap();
    store.initialize_local_interactions_trusted().unwrap();
    let blob = upload(&store, "project", b"Original synthetic evidence passage.");
    let metadata = store
        .register_document_trusted(
            "project",
            "text-source",
            "Synthetic",
            DocumentFormat::Text,
            &blob,
        )
        .unwrap();
    let source = DocumentAccess {
        document: metadata.document,
        authority: AuthorityBinding {
            grant_id: "source-grant".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch".into(),
        },
    };
    store
        .issue_document_grant_trusted(
            &source.document,
            &source.authority,
            &[
                DocumentOperation::Inspect,
                DocumentOperation::ReadText,
                DocumentOperation::StructuredEdit,
            ],
            expiry(),
        )
        .unwrap();
    let project = ArtifactProjectAccess {
        scope: source.document.scope().clone(),
        actor_id: "actor".into(),
        project_revision: Revision::new(1),
        authority: AuthorityBinding {
            grant_id: "project-grant".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch".into(),
        },
    };
    store
        .issue_artifact_project_grant_trusted(
            &project,
            &[
                ArtifactProjectOperation::LocalDraft,
                ArtifactProjectOperation::ReadOwnLocal,
            ],
            expiry(),
        )
        .unwrap();
    let evidence = StoreEvidence::new(&store);
    let processing = evidence.process(&source, InputKind::Utf8Text).unwrap();
    let hits = evidence
        .find_literal(&source, &processing, "synthetic", 1)
        .unwrap();
    let proof = store
        .resolve_local_evidence_trusted(
            &project,
            ArtifactProjectOperation::LocalDraft,
            &source,
            &processing,
            &hits[0],
        )
        .unwrap();
    let local = LocalAccess {
        project,
        object: LocalObjectRef {
            object_id: "object".into(),
            target: proof.target(),
            component_id: "component".into(),
            component_revision: Revision::new(1),
            attempt_id: "attempt".into(),
        },
        binding_generation: Revision::new(1),
    };
    let kind = LocalKind::Form(FormSpec {
        fields: vec![LocalField::Text],
        single_options: Vec::new(),
        multiple_options: Vec::new(),
    });
    store
        .issue_local_evidence_binding_trusted(&local, &kind, expiry(), &proof)
        .unwrap();
    drop(proof);
    let change = LocalMutation::Patch {
        expected: Revision::new(0),
        changes: vec![FieldChange::Text {
            value: "original manual draft".into(),
        }],
        author: AnnotationAuthor::Human {
            actor_id: "actor".into(),
        },
    };
    assert_eq!(
        store
            .mutate_local_trusted("manual", &local, &change)
            .unwrap()
            .status,
        ArtifactSaveStatus::Committed
    );
    (f, store, source, local, kind)
}
fn active(store: &BusinessStore) -> String {
    store
        .database()
        .query(
            "SELECT active FROM artifact_local_evidence_sources_v1 WHERE object_id='object'",
            &[],
        )
        .unwrap()[0][0]
        .clone()
        .unwrap()
}
fn head(store: &BusinessStore) -> String {
    store
        .database()
        .query(
            "SELECT revision FROM document_heads WHERE document_id='text-source'",
            &[],
        )
        .unwrap()[0][0]
        .clone()
        .unwrap()
}
fn raw_forms(store: &BusinessStore) -> Vec<Vec<Option<String>>> {
    store
        .database()
        .query(
            "SELECT * FROM artifact_local_forms_v1 ORDER BY object_id",
            &[],
        )
        .unwrap()
}

#[test]
fn uninitialized_source_feature_does_not_block_docs_or_create_tables_on_read() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    assert!(store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap()
        .is_empty());
    store
        .revoke_document_grant_trusted(&access.authority)
        .unwrap();
    assert!(store
        .database()
        .query(
            "SELECT name FROM sqlite_master WHERE name='document_source_notifications_v1'",
            &[]
        )
        .unwrap()
        .is_empty());
}

#[test]
fn legacy_local_tables_without_source_namespace_remain_compatible() {
    let f = Fixture::new();
    let (store, access) = f.setup();
    store.initialize_artifacts_trusted().unwrap();
    store.initialize_artifact_workflows_trusted().unwrap();
    store.initialize_local_interactions_trusted().unwrap();
    // Reproduce the previous six-table feature shape before a tracked source or
    // core notification marker exists. This is not the damaged-installed case.
    store
        .database()
        .exec("DROP TABLE artifact_local_evidence_sources_v1", &[])
        .unwrap();
    store
        .revoke_document_grant_trusted(&access.authority)
        .unwrap();
    assert!(store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap()
        .is_empty());
    assert!(store
        .database()
        .query(
            "SELECT name FROM sqlite_master WHERE name='document_source_notifications_v1'",
            &[]
        )
        .unwrap()
        .is_empty());
}

#[test]
fn reissuing_same_document_grant_invalidates_active_original_generation() {
    let (_f, store, source, _, _) = fixture();
    let forms = raw_forms(&store);
    let next = AuthorityBinding {
        generation: source.authority.generation.next().unwrap(),
        ..source.authority
    };
    store
        .issue_document_grant_trusted(
            &source.document,
            &next,
            &[DocumentOperation::ReadText],
            expiry(),
        )
        .unwrap();
    assert_eq!(active(&store), "0");
    assert_eq!(raw_forms(&store), forms);
    assert_eq!(
        store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn publish_and_copy_call_real_hook_preserving_manual_values() {
    for copy in [false, true] {
        let (_f, store, source, _, _) = fixture();
        let forms = raw_forms(&store);
        if copy {
            let metadata = store.read_document(&source).unwrap();
            let tx = store.database().transaction().unwrap();
            store
                .document_clone_in_transaction(&tx, &source.document, "Copy", &metadata.blob)
                .unwrap();
            tx.commit().unwrap();
        } else {
            let blob = upload(&store, "project", b"Replacement synthetic source.");
            store
                .publish_document_revision_trusted(
                    &source.document,
                    "Next",
                    DocumentFormat::Text,
                    &blob,
                )
                .unwrap();
        }
        assert_eq!(head(&store), "2");
        assert_eq!(active(&store), "0");
        assert_eq!(raw_forms(&store), forms);
        let pending = store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(
            (
                pending[0].project_id.as_str(),
                pending[0].actor_id.as_str(),
                pending[0].object_id.as_str()
            ),
            ("project", "actor", "object")
        );
    }
}

#[test]
fn source_and_notifications_are_not_visible_until_commit_and_rollback_keeps_both() {
    let (f, store, source, _, _) = fixture();
    let observer = Db::open(f.path().to_str().unwrap(), true, false).unwrap();
    let metadata = store.read_document(&source).unwrap();
    let tx = store.database().transaction().unwrap();
    store
        .document_clone_in_transaction(&tx, &source.document, "Uncommitted", &metadata.blob)
        .unwrap();
    assert!(
        store
            .pending_document_source_notifications_trusted(None, 256)
            .is_err(),
        "nested transaction cannot publish pending IDs"
    );
    assert_eq!(
        observer
            .query("SELECT active FROM artifact_local_evidence_sources_v1", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("1")
    );
    assert!(observer
        .query(
            "SELECT 1 FROM document_source_notifications_v1 WHERE pending=1",
            &[]
        )
        .unwrap()
        .is_empty());
    drop(tx);
    assert_eq!(active(&store), "1");
    assert_eq!(head(&store), "1");
    assert!(store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap()
        .is_empty());
    let tx = store.database().transaction().unwrap();
    store
        .document_clone_in_transaction(&tx, &source.document, "Committed", &metadata.blob)
        .unwrap();
    tx.commit().unwrap();
    assert_eq!(
        store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn notification_failure_rolls_back_original_head_and_grant_mutations() {
    for mutation in [0, 1, 2] {
        let (_f, store, source, _, _) = fixture();
        store.database().exec("CREATE TRIGGER fail_source_notification BEFORE INSERT ON document_source_notifications_v1 BEGIN SELECT RAISE(ABORT,'synthetic notification failure'); END", &[]).unwrap();
        if mutation == 0 {
            let blob = upload(&store, "project", b"Replacement synthetic source.");
            assert!(store
                .publish_document_revision_trusted(
                    &source.document,
                    "Next",
                    DocumentFormat::Text,
                    &blob
                )
                .is_err());
        } else if mutation == 1 {
            assert!(store
                .revoke_document_grant_trusted(&source.authority)
                .is_err());
        } else {
            let next = AuthorityBinding {
                generation: source.authority.generation.next().unwrap(),
                ..source.authority.clone()
            };
            assert!(store
                .issue_document_grant_trusted(
                    &source.document,
                    &next,
                    &[DocumentOperation::ReadText],
                    expiry()
                )
                .is_err());
        }
        assert_eq!(head(&store), "1");
        assert_eq!(active(&store), "1");
        assert!(store.read_document(&source).is_ok());
        assert!(store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap()
            .is_empty());
    }
}

#[test]
fn grant_replacement_invalidates_old_document_even_when_new_scope_differs() {
    let (_f, store, source, _, _) = fixture();
    let forms = raw_forms(&store);
    store
        .database()
        .exec(
            "INSERT INTO projects VALUES('other-project','workspace','Other','1',0)",
            &[],
        )
        .unwrap();
    let blob = upload(&store, "other-project", b"Other original synthetic source.");
    let other = store
        .register_document_trusted(
            "other-project",
            "other-document",
            "Other",
            DocumentFormat::Text,
            &blob,
        )
        .unwrap();
    let authority = AuthorityBinding {
        generation: source.authority.generation.next().unwrap(),
        ..source.authority
    };
    store
        .issue_document_grant_trusted(
            &other.document,
            &authority,
            &[DocumentOperation::ReadText],
            expiry(),
        )
        .unwrap();
    assert_eq!(active(&store), "0");
    assert_eq!(raw_forms(&store), forms);
    let pending = store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].project_id, "project");
}

#[test]
fn malformed_feature_or_notification_schema_rejects_without_committing_revocation() {
    for damage in [
        "DROP TABLE artifact_local_evidence_sources_v1",
        "DROP TABLE artifact_local_evidence_sources_v1; CREATE TABLE artifact_local_evidence_sources_v1(wrong TEXT)",
        "DROP TABLE document_source_notifications_v1; CREATE TABLE document_source_notifications_v1(wrong TEXT)",
    ] {
        let (_f, store, source, _, _) = fixture();
        for statement in damage.split(';') { store.database().exec(statement.trim(), &[]).unwrap(); }
        assert!(store.revoke_document_grant_trusted(&source.authority).is_err(), "{damage}");
        assert_eq!(store.database().query("SELECT active FROM document_grants WHERE grant_id='source-grant'", &[]).unwrap()[0][0].as_deref(), Some("1"));
    }
}

#[test]
fn malformed_original_grant_target_is_not_discarded_during_reissue_or_revoke() {
    let (_f, store, mut source, _, _) = fixture();
    store
        .database()
        .exec(
            "UPDATE document_grants SET document_json='{' WHERE grant_id='source-grant'",
            &[],
        )
        .unwrap();
    assert!(store
        .revoke_document_grant_trusted(&source.authority)
        .is_err());
    source.authority.generation = source.authority.generation.next().unwrap();
    assert!(store
        .issue_document_grant_trusted(
            &source.document,
            &source.authority,
            &[DocumentOperation::ReadText],
            expiry()
        )
        .is_err());
    assert_eq!(
        store
            .database()
            .query(
                "SELECT generation,active FROM document_grants WHERE grant_id='source-grant'",
                &[]
            )
            .unwrap()[0],
        vec![Some("1".into()), Some("1".into())]
    );
}

#[test]
fn pending_notifications_repeat_until_ack_and_stale_ack_cannot_erase_new_generation() {
    let (_f, store, mut source, mut local, kind) = fixture();
    let forms = raw_forms(&store);
    store
        .revoke_document_grant_trusted(&source.authority)
        .unwrap();
    let first = store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap();
    assert_eq!(
        store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap(),
        first
    );
    assert_eq!(
        store
            .ack_document_source_notifications_trusted(&first)
            .unwrap(),
        1
    );
    source.authority.generation = source.authority.generation.next().unwrap();
    store
        .issue_document_grant_trusted(
            &source.document,
            &source.authority,
            &[DocumentOperation::Inspect, DocumentOperation::ReadText],
            expiry(),
        )
        .unwrap();
    local.binding_generation = local.binding_generation.next().unwrap();
    bind(&store, &source, &local, &kind);
    store
        .revoke_document_grant_trusted(&source.authority)
        .unwrap();
    let second = store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap();
    assert!(second[0].generation.value() > first[0].generation.value());
    assert_eq!(
        store
            .ack_document_source_notifications_trusted(&first)
            .unwrap(),
        0
    );
    assert_eq!(
        store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap(),
        second
    );
    assert_eq!(
        store
            .ack_document_source_notifications_trusted(&second)
            .unwrap(),
        1
    );
    assert_eq!(raw_forms(&store), forms);
}

#[test]
fn more_than_256_real_bindings_revoke_and_queue_without_a_global_limit() {
    let (_f, store, source, local, kind) = fixture();
    let evidence = StoreEvidence::new(&store);
    let processing = evidence.process(&source, InputKind::Utf8Text).unwrap();
    let hits = evidence
        .find_literal(&source, &processing, "synthetic", 1)
        .unwrap();
    let proof = store
        .resolve_local_evidence_trusted(
            &local.project,
            ArtifactProjectOperation::LocalDraft,
            &source,
            &processing,
            &hits[0],
        )
        .unwrap();
    for n in 0..257 {
        let mut extra = local.clone();
        extra.object.object_id = format!("object-{n:03}");
        store
            .issue_local_evidence_binding_trusted(&extra, &kind, expiry(), &proof)
            .unwrap();
    }
    drop(proof);
    store
        .revoke_document_grant_trusted(&source.authority)
        .unwrap();
    assert!(store
        .database()
        .query(
            "SELECT 1 FROM artifact_local_evidence_sources_v1 WHERE active=1",
            &[]
        )
        .unwrap()
        .is_empty());
    let first = store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap();
    let second = store
        .pending_document_source_notifications_trusted(first.last(), 256)
        .unwrap();
    assert_eq!(first.len(), 256);
    assert_eq!(second.len(), 2);
    let unique: BTreeSet<_> = first
        .iter()
        .chain(&second)
        .map(|event| (&event.project_id, &event.actor_id, &event.object_id))
        .collect();
    assert_eq!(unique.len(), 258);
}

#[test]
fn foreign_transaction_and_oversized_pages_are_rejected() {
    let (_f, store, source, _, _) = fixture();
    let other = Db::open(":memory:", false, true).unwrap();
    let tx = other.transaction().unwrap();
    assert!(store
        .prepare_document_source_mutation_in_transaction(&tx, &[&source.document])
        .is_err());
    assert!(store
        .pending_document_source_notifications_trusted(None, 0)
        .is_err());
    assert!(store
        .pending_document_source_notifications_trusted(None, 257)
        .is_err());
}

// Successful AFTER triggers must not turn a successful SQL statement into an
// unchecked mutation receipt. Each case must fail at the read-only tail and
// roll back the grant/head, source/binding and notification together.
#[test]
fn successful_outbox_trigger_tampering_rolls_back_revoke() {
    for action in [
        "UPDATE document_grants SET active=1 WHERE grant_id='source-grant'",
        "DELETE FROM document_source_notifications_v1 WHERE object_id=NEW.object_id",
        "UPDATE document_source_notifications_v1 SET pending=0 WHERE object_id=NEW.object_id",
        "UPDATE document_source_notifications_v1 SET generation='99' WHERE object_id=NEW.object_id",
        "UPDATE artifact_local_evidence_sources_v1 SET active=1 WHERE object_id=NEW.object_id",
        "UPDATE artifact_local_bindings_v1 SET active=1 WHERE object_id=NEW.object_id",
    ] {
        let (_f, store, source, _, _) = fixture();
        store.database().exec(&format!("CREATE TRIGGER tamper AFTER INSERT ON document_source_notifications_v1 BEGIN {action}; END"), &[]).unwrap();
        assert!(
            store
                .revoke_document_grant_trusted(&source.authority)
                .is_err(),
            "successful trigger escaped the tail: {action}"
        );
        assert!(store.read_document(&source).is_ok());
        assert_eq!(active(&store), "1");
        assert!(store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap()
            .is_empty());
    }
}

#[test]
fn successful_outbox_trigger_tampering_rolls_back_issue_publish_and_copy() {
    for mutation in [0, 1, 2] {
        let (_f, store, source, _, _) = fixture();
        let action = if mutation == 0 {
            "UPDATE document_grants SET generation='1' WHERE grant_id='source-grant'"
        } else {
            "UPDATE document_heads SET revision='1' WHERE document_id='text-source'"
        };
        store.database().exec(&format!("CREATE TRIGGER tamper AFTER INSERT ON document_source_notifications_v1 BEGIN {action}; END"), &[]).unwrap();
        if mutation == 0 {
            let next = AuthorityBinding {
                generation: source.authority.generation.next().unwrap(),
                ..source.authority.clone()
            };
            assert!(store
                .issue_document_grant_trusted(
                    &source.document,
                    &next,
                    &[DocumentOperation::ReadText],
                    expiry()
                )
                .is_err());
        } else if mutation == 1 {
            let blob = upload(&store, "project", b"Replacement synthetic source.");
            assert!(store
                .publish_document_revision_trusted(
                    &source.document,
                    "Next",
                    DocumentFormat::Text,
                    &blob
                )
                .is_err());
        } else {
            let metadata = store.read_document(&source).unwrap();
            let tx = store.database().transaction().unwrap();
            assert!(store
                .document_clone_in_transaction(&tx, &source.document, "Copy", &metadata.blob)
                .is_err());
            drop(tx);
        }
        assert_eq!(head(&store), "1");
        assert_eq!(active(&store), "1");
        assert!(store.read_document(&source).is_ok());
        assert!(store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap()
            .is_empty());
    }
}

#[test]
fn later_outbox_write_cannot_erase_an_earlier_event() {
    let (_f, store, source, local, kind) = fixture();
    let mut second = local.clone();
    second.object.object_id = "object-z".into();
    bind(&store, &source, &second, &kind);
    store.database().exec("CREATE TRIGGER tamper AFTER INSERT ON document_source_notifications_v1 WHEN NEW.object_id='object-z' BEGIN DELETE FROM document_source_notifications_v1 WHERE object_id='object'; END", &[]).unwrap();
    assert!(store
        .revoke_document_grant_trusted(&source.authority)
        .is_err());
    assert!(store.read_document(&source).is_ok());
    assert_eq!(active(&store), "1");
    assert!(store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap()
        .is_empty());
}

#[test]
fn successful_outbox_update_and_ack_tampering_cannot_report_success() {
    for acknowledge in [false, true] {
        let (_f, store, mut source, mut local, kind) = fixture();
        store
            .revoke_document_grant_trusted(&source.authority)
            .unwrap();
        let first = store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap();
        if acknowledge {
            store.database().exec("CREATE TRIGGER tamper AFTER UPDATE ON document_source_notifications_v1 WHEN NEW.pending=0 BEGIN UPDATE document_source_notifications_v1 SET pending=1 WHERE object_id=NEW.object_id; END", &[]).unwrap();
            assert!(store
                .ack_document_source_notifications_trusted(&first)
                .is_err());
            assert_eq!(
                store
                    .pending_document_source_notifications_trusted(None, 256)
                    .unwrap(),
                first
            );
        } else {
            store
                .ack_document_source_notifications_trusted(&first)
                .unwrap();
            source.authority.generation = source.authority.generation.next().unwrap();
            store
                .issue_document_grant_trusted(
                    &source.document,
                    &source.authority,
                    &[DocumentOperation::Inspect, DocumentOperation::ReadText],
                    expiry(),
                )
                .unwrap();
            local.binding_generation = local.binding_generation.next().unwrap();
            bind(&store, &source, &local, &kind);
            store.database().exec("CREATE TRIGGER tamper AFTER UPDATE ON document_source_notifications_v1 WHEN NEW.pending=1 BEGIN UPDATE document_grants SET active=1 WHERE grant_id='source-grant'; END", &[]).unwrap();
            assert!(store
                .revoke_document_grant_trusted(&source.authority)
                .is_err());
            assert!(store.read_document(&source).is_ok());
            assert_eq!(active(&store), "1");
            assert!(store
                .pending_document_source_notifications_trusted(None, 256)
                .unwrap()
                .is_empty());
        }
    }
}

#[test]
fn successful_outbox_trigger_cannot_delete_blob_publication_receipt() {
    for copy in [false, true] {
        let (_f, store, source, _, _) = fixture();
        let before = store
            .database()
            .query("SELECT * FROM blob_references ORDER BY reference_id", &[])
            .unwrap();
        store.database().exec("CREATE TRIGGER tamper AFTER INSERT ON document_source_notifications_v1 BEGIN DELETE FROM blob_references WHERE target_id='text-source'; END", &[]).unwrap();
        if copy {
            let metadata = store.read_document(&source).unwrap();
            let tx = store.database().transaction().unwrap();
            assert!(store
                .document_clone_in_transaction(&tx, &source.document, "Copy", &metadata.blob)
                .is_err());
            drop(tx);
        } else {
            let blob = upload(&store, "project", b"Replacement synthetic source.");
            assert!(store
                .publish_document_revision_trusted(
                    &source.document,
                    "Next",
                    DocumentFormat::Text,
                    &blob
                )
                .is_err());
        }
        assert_eq!(
            store
                .database()
                .query("SELECT * FROM blob_references ORDER BY reference_id", &[])
                .unwrap(),
            before
        );
        assert_eq!(head(&store), "1");
        assert_eq!(active(&store), "1");
        assert!(store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap()
            .is_empty());
    }
}

#[test]
fn successful_outbox_trigger_cannot_restore_upload_to_pinned_or_leave_an_upload_pin() {
    for pin in [false, true] {
        let (_f, store, source, _, _) = fixture();
        let blob = upload(&store, "project", b"Replacement synthetic source.");
        let action = if pin {
            format!("INSERT INTO blob_pins SELECT 'synthetic-pin',digest,'upload',upload_id,snapshot_id,owner_epoch FROM blob_uploads WHERE upload_id='{}'", blob.upload_id)
        } else {
            format!(
                "UPDATE blob_uploads SET state='pinned' WHERE upload_id='{}'",
                blob.upload_id
            )
        };
        store.database().exec(&format!("CREATE TRIGGER tamper AFTER INSERT ON document_source_notifications_v1 BEGIN {action}; END"), &[]).unwrap();
        assert!(store
            .publish_document_revision_trusted(
                &source.document,
                "Next",
                DocumentFormat::Text,
                &blob
            )
            .is_err());
        assert_eq!(head(&store), "1");
        assert_eq!(active(&store), "1");
        assert_eq!(
            store
                .database()
                .query(
                    "SELECT state FROM blob_uploads WHERE upload_id=?",
                    &[&blob.upload_id]
                )
                .unwrap()[0][0]
                .as_deref(),
            Some("pinned")
        );
        assert!(store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap()
            .is_empty());
    }
}

#[test]
fn ignored_ack_write_cannot_delete_the_generation_tombstone() {
    let (_f, store, source, _, _) = fixture();
    store
        .revoke_document_grant_trusted(&source.authority)
        .unwrap();
    let first = store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap();
    store.database().exec("CREATE TRIGGER tamper BEFORE UPDATE ON document_source_notifications_v1 WHEN NEW.pending=0 BEGIN DELETE FROM document_source_notifications_v1 WHERE object_id=OLD.object_id; SELECT RAISE(IGNORE); END", &[]).unwrap();
    assert!(store
        .ack_document_source_notifications_trusted(&first)
        .is_err());
    assert_eq!(
        store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap(),
        first
    );
}

#[test]
fn later_ack_trigger_cannot_mutate_an_earlier_stale_or_missing_target() {
    for missing in [false, true] {
        let (_f, store, source, local, kind) = fixture();
        let mut second = local.clone();
        second.object.object_id = "object-z".into();
        bind(&store, &source, &second, &kind);
        store
            .revoke_document_grant_trusted(&source.authority)
            .unwrap();
        let pending = store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap();
        assert_eq!(pending.len(), 2);
        let mut first_input = pending[0].clone();
        let action = if missing {
            first_input.object_id = "missing".into();
            "INSERT INTO document_source_notifications_v1 VALUES('project','actor','missing','1',1)"
        } else {
            first_input.generation = Revision::new(99);
            "DELETE FROM document_source_notifications_v1 WHERE object_id='object'"
        };
        store.database().exec(&format!("CREATE TRIGGER tamper AFTER UPDATE ON document_source_notifications_v1 WHEN NEW.object_id='object-z' BEGIN {action}; END"), &[]).unwrap();
        assert!(store
            .ack_document_source_notifications_trusted(&[first_input, pending[1].clone()])
            .is_err());
        assert_eq!(
            store
                .pending_document_source_notifications_trusted(None, 256)
                .unwrap(),
            pending
        );
    }
}

#[test]
fn first_outbox_update_cannot_reset_a_later_tombstone_generation() {
    let (_f, store, mut source, mut local, kind) = fixture();
    let mut second = local.clone();
    second.object.object_id = "object-z".into();
    bind(&store, &source, &second, &kind);
    store
        .revoke_document_grant_trusted(&source.authority)
        .unwrap();
    let first = store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap();
    assert_eq!(first.len(), 2);
    assert!(first
        .iter()
        .all(|event| event.generation == Revision::new(1)));
    store
        .ack_document_source_notifications_trusted(&first)
        .unwrap();
    source.authority.generation = source.authority.generation.next().unwrap();
    store
        .issue_document_grant_trusted(
            &source.document,
            &source.authority,
            &[DocumentOperation::Inspect, DocumentOperation::ReadText],
            expiry(),
        )
        .unwrap();
    local.binding_generation = local.binding_generation.next().unwrap();
    second.binding_generation = second.binding_generation.next().unwrap();
    bind(&store, &source, &local, &kind);
    bind(&store, &source, &second, &kind);
    store.database().exec("CREATE TRIGGER tamper AFTER UPDATE ON document_source_notifications_v1 WHEN NEW.object_id='object' AND NEW.pending=1 BEGIN DELETE FROM document_source_notifications_v1 WHERE object_id='object-z'; END", &[]).unwrap();
    assert!(
        store
            .revoke_document_grant_trusted(&source.authority)
            .is_err(),
        "cross-row tombstone deletion must roll back, not reuse generation1"
    );
    assert!(store.read_document(&source).is_ok());
    assert_eq!(active(&store), "1");
    let tombstones = store
        .database()
        .query(
            "SELECT generation,pending FROM document_source_notifications_v1 ORDER BY object_id",
            &[],
        )
        .unwrap();
    assert_eq!(
        tombstones,
        vec![vec![Some("1".into()), Some("0".into())]; 2]
    );
    store.database().exec("DROP TRIGGER tamper", &[]).unwrap();
    store
        .revoke_document_grant_trusted(&source.authority)
        .unwrap();
    let renewed = store
        .pending_document_source_notifications_trusted(None, 256)
        .unwrap();
    assert!(renewed
        .iter()
        .all(|event| event.generation == Revision::new(2)));
    assert_eq!(
        store
            .ack_document_source_notifications_trusted(&first)
            .unwrap(),
        0
    );
    assert_eq!(
        store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap(),
        renewed
    );
}

#[test]
fn publication_token_rejects_later_write_tampering_and_rolls_back() {
    // Core seam test only: this does NOT claim the real gateway receipt path ran.
    for action in [
        "DELETE FROM document_source_notifications_v1",
        "UPDATE document_source_notifications_v1 SET pending=0",
        "UPDATE artifact_local_evidence_sources_v1 SET active=1",
        "DELETE FROM blob_references WHERE target_id='text-source'",
        "UPDATE document_heads SET revision='1' WHERE document_id='text-source'",
    ] {
        let (_f, store, source, _, _) = fixture();
        let metadata = store.read_document(&source).unwrap();
        let tx = store.database().transaction().unwrap();
        let (_, token) = store
            .document_clone_with_postcondition_in_transaction(
                &tx,
                &source.document,
                "Copy",
                &metadata.blob,
            )
            .unwrap();
        store.database().exec(action, &[]).unwrap();
        assert!(
            store
                .document_publication_postcondition_in_transaction(&tx, token)
                .is_err(),
            "{action}"
        );
        drop(tx);
        assert_eq!(head(&store), "1");
        assert_eq!(active(&store), "1");
        assert!(store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap()
            .is_empty());
    }
}

#[test]
fn publication_token_rejects_another_transaction_and_accepts_exact_original() {
    let (_f, store, source, _, _) = fixture();
    let metadata = store.read_document(&source).unwrap();
    let tx = store.database().transaction().unwrap();
    let (_, token) = store
        .document_clone_with_postcondition_in_transaction(
            &tx,
            &source.document,
            "Copy",
            &metadata.blob,
        )
        .unwrap();
    let other = Db::open(":memory:", false, true).unwrap();
    let foreign = other.transaction().unwrap();
    assert!(store
        .document_publication_postcondition_in_transaction(&foreign, token)
        .is_err());
    drop(tx);
    drop(foreign);
    assert_eq!(head(&store), "1");
    let tx = store.database().transaction().unwrap();
    let (result, token) = store
        .document_clone_with_postcondition_in_transaction(
            &tx,
            &source.document,
            "Copy",
            &metadata.blob,
        )
        .unwrap();
    store
        .document_grant_in_transaction(&tx, &source, &[DocumentOperation::StructuredEdit])
        .unwrap();
    store
        .document_publication_postcondition_in_transaction(&tx, token)
        .unwrap();
    tx.commit().unwrap();
    assert_eq!(result.document.revision(), &Revision::new(2));
    assert_eq!(
        store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn earlier_grant_source_or_binding_write_cannot_reset_a_tombstone() {
    for table in [
        "document_grants",
        "artifact_local_evidence_sources_v1",
        "artifact_local_bindings_v1",
    ] {
        let (_f, store, mut source, mut local, kind) = fixture();
        let mut second = local.clone();
        second.object.object_id = "object-z".into();
        bind(&store, &source, &second, &kind);
        store
            .revoke_document_grant_trusted(&source.authority)
            .unwrap();
        let first = store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap();
        store
            .ack_document_source_notifications_trusted(&first)
            .unwrap();
        source.authority.generation = source.authority.generation.next().unwrap();
        store
            .issue_document_grant_trusted(
                &source.document,
                &source.authority,
                &[DocumentOperation::Inspect, DocumentOperation::ReadText],
                expiry(),
            )
            .unwrap();
        local.binding_generation = local.binding_generation.next().unwrap();
        second.binding_generation = second.binding_generation.next().unwrap();
        bind(&store, &source, &local, &kind);
        bind(&store, &source, &second, &kind);
        store.database().exec(&format!("CREATE TRIGGER tamper AFTER UPDATE ON {table} WHEN NEW.active=0 BEGIN DELETE FROM document_source_notifications_v1 WHERE object_id='object-z'; END"), &[]).unwrap();
        assert!(
            store
                .revoke_document_grant_trusted(&source.authority)
                .is_err(),
            "{table} write preceded frozen generation boundary"
        );
        assert!(store.read_document(&source).is_ok());
        assert_eq!(active(&store), "1");
        store.database().exec("DROP TRIGGER tamper", &[]).unwrap();
        store
            .revoke_document_grant_trusted(&source.authority)
            .unwrap();
        let renewed = store
            .pending_document_source_notifications_trusted(None, 256)
            .unwrap();
        assert!(renewed
            .iter()
            .all(|event| event.generation == Revision::new(2)));
        assert_eq!(
            store
                .ack_document_source_notifications_trusted(&first)
                .unwrap(),
            0
        );
        assert_eq!(
            store
                .pending_document_source_notifications_trusted(None, 256)
                .unwrap(),
            renewed
        );
    }
}
