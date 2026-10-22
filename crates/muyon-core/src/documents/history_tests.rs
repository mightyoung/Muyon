//! Explicit historical policy, never an inference from the current grant.
use super::{storage_tests::Fixture, *};
use crate::{business::BusinessStore, contract::*, sqlite::Db};
use std::time::{SystemTime, UNIX_EPOCH};

fn expiry() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64 + 20_000
}
fn advance(store: &BusinessStore, old: &DocumentAccess) -> (DocumentAccess, DocumentMetadata) {
    let metadata = store.read_document(old).unwrap();
    let tx = store.database().transaction().unwrap();
    let next = store.document_clone_in_transaction(&tx, &old.document, "COPY-only new head", &metadata.blob).unwrap();
    tx.commit().unwrap();
    let current = DocumentAccess { document: next.document, authority: AuthorityBinding { generation: old.authority.generation.next().unwrap(), ..old.authority.clone() } };
    store.issue_document_grant_trusted(&current.document, &current.authority, &[DocumentOperation::Inspect, DocumentOperation::ReadText], expiry()).unwrap();
    (current, metadata)
}
#[test]
fn history_denies_without_explicit_target_policy_and_then_reads_exact_snapshot() {
    let f = Fixture::new(); let (store, old) = f.setup(); let (current, snapshot) = advance(&store, &old);
    let tx = store.database().transaction().unwrap();
    assert!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::ReadText]).is_err());
    drop(tx);
    store.initialize_document_history_trusted().unwrap();
    let tx = store.database().transaction().unwrap();
    assert!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::ReadText]).is_err());
    assert_eq!(store.document_history_access_in_transaction(&tx, &current, &current.document, &[DocumentOperation::ReadText]).unwrap().document, current.document);
    drop(tx);
    store.issue_document_history_grant_trusted(&current, &old.document, &[DocumentOperation::ReadText], expiry()).unwrap();
    let tx = store.database().transaction().unwrap();
    assert_eq!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::ReadText]).unwrap(), snapshot);
    assert!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::Inspect]).is_err());
    drop(tx);
}
#[test]
fn historical_and_parent_revocation_expiry_generation_and_project_are_current() {
    let f = Fixture::new(); let (store, old) = f.setup(); let (current, _) = advance(&store, &old);
    store.initialize_document_history_trusted().unwrap();
    store.issue_document_history_grant_trusted(&current, &old.document, &[DocumentOperation::ReadText], expiry()).unwrap();
    for mutation in [
        "UPDATE document_history_grants_v1 SET active=0",
        "UPDATE document_history_grants_v1 SET expires_at_ms='0'",
        "UPDATE document_history_grants_v1 SET owner_epoch='old'",
        "UPDATE document_grants SET active=0",
        "UPDATE document_grants SET expires_at_ms='0'",
        "UPDATE document_grants SET generation='999'",
        "UPDATE projects SET deleted=1 WHERE id='project'",
    ] {
        let tx = store.database().transaction().unwrap();
        store.database().exec(mutation, &[]).unwrap();
        assert!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::ReadText]).is_err(), "{mutation}");
        drop(tx);
    }
    store.revoke_document_history_grant_trusted(&current, &old.document).unwrap();
    let tx = store.database().transaction().unwrap();
    assert!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::ReadText]).is_err());
    drop(tx);
}
#[test]
fn old_policy_is_not_inherited_by_a_new_parent_grant_generation() {
    let f = Fixture::new(); let (store, old) = f.setup(); let (current, _) = advance(&store, &old);
    store.initialize_document_history_trusted().unwrap();
    store.issue_document_history_grant_trusted(&current, &old.document, &[DocumentOperation::ReadText], expiry()).unwrap();
    let next = DocumentAccess { authority: AuthorityBinding { generation: current.authority.generation.next().unwrap(), ..current.authority.clone() }, document: current.document.clone() };
    store.issue_document_grant_trusted(&next.document, &next.authority, &[DocumentOperation::ReadText], expiry()).unwrap();
    let tx = store.database().transaction().unwrap();
    assert!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::ReadText]).is_err());
    assert!(store.document_history_access_in_transaction(&tx, &next, &old.document, &[DocumentOperation::ReadText]).is_err());
    drop(tx);
}
#[test]
fn historical_identity_scope_schema_and_read_only_policy_fail_closed() {
    let f = Fixture::new(); let (store, old) = f.setup(); let (current, _) = advance(&store, &old);
    store.initialize_document_history_trusted().unwrap();
    assert!(store.issue_document_history_grant_trusted(&current, &old.document, &[DocumentOperation::StructuredEdit], expiry()).is_err());
    store.issue_document_history_grant_trusted(&current, &old.document, &[DocumentOperation::ReadText], expiry()).unwrap();
    let tx = store.database().transaction().unwrap();
    for historical in [
        DocumentRef::new(Scope { workspace_id: "workspace".into(), project_id: Some("other".into()) }, "document", Revision::new(1), DocumentFormat::Pdf).unwrap(),
        DocumentRef::new(current.document.scope().clone(), "other", Revision::new(1), DocumentFormat::Pdf).unwrap(),
        DocumentRef::new(current.document.scope().clone(), "document", Revision::new(3), DocumentFormat::Pdf).unwrap(),
    ] { assert!(store.document_history_access_in_transaction(&tx, &current, &historical, &[DocumentOperation::ReadText]).is_err()); }
    assert!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::StructuredEdit]).is_err());
    drop(tx);
    let foreign = Db::open(":memory:", false, true).unwrap(); let tx = foreign.transaction().unwrap();
    assert_eq!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::ReadText]), Err(ContractError::InvalidAuthority));
}
#[test]
fn canonical_history_corruption_and_missing_revision_are_not_substituted() {
    let f = Fixture::new(); let (store, old) = f.setup(); let (current, _) = advance(&store, &old);
    store.initialize_document_history_trusted().unwrap();
    store.issue_document_history_grant_trusted(&current, &old.document, &[DocumentOperation::ReadText], expiry()).unwrap();
    let current_payload = serde_json::to_string(&store.read_document(&current).unwrap()).unwrap();
    let tx = store.database().transaction().unwrap();
    store.database().exec("UPDATE document_revisions SET payload=? WHERE revision='1'", &[&current_payload]).unwrap();
    assert_eq!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::ReadText]), Err(ContractError::StorageCorrupt));
    drop(tx);
    let tx = store.database().transaction().unwrap();
    store.database().exec("DELETE FROM document_revisions WHERE revision='1'", &[]).unwrap();
    assert_eq!(store.document_history_access_in_transaction(&tx, &current, &old.document, &[DocumentOperation::ReadText]), Err(ContractError::NotFound));
    drop(tx);
}
#[test]
fn text_label_roundtrips_without_default_utf8_or_reader_capability() {
    let document = DocumentRef::new(Scope { workspace_id: "workspace".into(), project_id: Some("project".into()) }, "text-source", Revision::new(1), DocumentFormat::Text).unwrap();
    let json = serde_json::to_string(&document).unwrap();
    assert!(json.contains("\"format\":\"text\""));
    assert_eq!(serde_json::from_str::<DocumentRef>(&json).unwrap(), document);
    assert_eq!(CapabilityMatrix::default().status(DocumentFormat::Text, DocumentOperation::ReadText), CapabilityStatus::Unknown);
}
