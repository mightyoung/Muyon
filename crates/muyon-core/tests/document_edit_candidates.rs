//! Original synthetic bytes only; no Office engine, model, network or user files.
use muyon_core::{
    blobs::BlobKind,
    business::BusinessStore,
    contract::*,
    document_edit::{
        edited_candidates::*,
        engine_protocol::{prepare_request_trusted, NumericCellEdit, PreparedEngineRequest},
        gateway::DocumentEditGateway,
        Binding, Confirmation,
    },
    documents::{DocumentAccess, DocumentFormat, DocumentOperation, DocumentRef},
};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
const SYNTHETIC: &[u8] = b"original synthetic copy bytes; no Office engine acceptance";
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "muyon-edited-candidate-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn path(&self) -> PathBuf {
        self.0.join("store.sqlite")
    }
    fn reopen(&self, epoch: &str) -> BusinessStore {
        BusinessStore::open_existing(&self.path(), "workspace", epoch).unwrap()
    }
    fn store(&self) -> BusinessStore {
        self.store_with_format(DocumentFormat::Xlsx)
    }
    fn store_with_format(&self, format: DocumentFormat) -> BusinessStore {
        BusinessStore::initialize(&self.path(), "workspace").unwrap();
        let s = self.reopen("epoch-1");
        let mut c = CommandEnvelope {
            protocol_version: 1,
            business_version: 1,
            intent_id: "create-project".into(),
            scope: Scope {
                workspace_id: "workspace".into(),
                project_id: Some("project".into()),
            },
            expected_revision: Revision::new(0),
            authority: AuthorityBinding {
                grant_id: "business-project".into(),
                generation: Revision::new(1),
                owner_epoch: "epoch-1".into(),
            },
            plan_id: "plan-project".into(),
            plan_digest: "0".repeat(64),
            command: Operation::ProjectCreate {
                project_id: "project".into(),
                name: "Synthetic local test".into(),
            },
        };
        c.plan_digest = c.expected_plan_digest().unwrap();
        s.issue_grant_trusted(&c, None).unwrap();
        assert_eq!(s.execute(&c).unwrap().status, ExecutionStatus::Committed);
        s.initialize_documents_trusted().unwrap();
        let upload = s.begin_upload("project").unwrap();
        s.append_chunk(&upload.upload_id, SYNTHETIC).unwrap();
        let blob = s
            .finish_blob(&upload.upload_id, BlobKind::Document)
            .unwrap();
        s.register_document_trusted("project", "document", "Synthetic", format, &blob)
            .unwrap();
        s
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn reference(revision: u64) -> DocumentRef {
    DocumentRef::new(
        Scope {
            workspace_id: "workspace".into(),
            project_id: Some("project".into()),
        },
        "document",
        Revision::new(revision),
        DocumentFormat::Xlsx,
    )
    .unwrap()
}
fn access(
    s: &BusinessStore,
    revision: u64,
    id: &str,
    generation: u64,
    epoch: &str,
) -> DocumentAccess {
    let a = DocumentAccess {
        document: reference(revision),
        authority: AuthorityBinding {
            grant_id: id.into(),
            generation: Revision::new(generation),
            owner_epoch: epoch.into(),
        },
    };
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64;
    s.issue_document_grant_trusted(
        &a.document,
        &a.authority,
        &[
            DocumentOperation::Inspect,
            DocumentOperation::ReadText,
            DocumentOperation::StructuredEdit,
            DocumentOperation::Validate,
            DocumentOperation::Export,
        ],
        now + 20_000,
    )
    .unwrap();
    a
}

fn request(s: &BusinessStore, a: &DocumentAccess, intent: &str) -> PreparedEngineRequest {
    prepare_request_trusted(
        &s.read_document(a).unwrap(),
        intent,
        NumericCellEdit {
            sheet: "Synthetic".into(),
            cell: "A1".into(),
            expected: "2".into(),
            replacement: "5".into(),
        },
    )
    .unwrap()
}
fn confirmed(
    g: &EditedCandidateJournal<'_>,
    p: &PreparedEngineRequest,
    a: &DocumentAccess,
) -> Binding {
    let b = g.prepare(p, a).unwrap().binding;
    g.confirm_trusted(
        p,
        a,
        &Confirmation {
            binding: b.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    b
}
const DIFFERENT: &[u8] = b"original synthetic changed bytes, not an Office engine output";
#[test]
fn prepared_candidate_restart_never_implies_confirmation_validation_or_document_success() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let p = request(&s, &a, "edited");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let b = g.prepare(&p, &a).unwrap().binding;
    assert_eq!(
        g.stage_candidate_trusted(&b, &a, DIFFERENT).unwrap_err(),
        ContractError::InvalidAuthority
    );
    drop(s);
    let s = f.reopen("epoch-2");
    let a = access(&s, 1, "after", 1, "epoch-2");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    assert_eq!(
        g.lookup_original(&b, &a).unwrap().state,
        EditedCandidateState::Planned
    );
    let p = request(&s, &a, "edited");
    confirmed(&g, &p, &a);
    let staged = g.stage_candidate_trusted(&b, &a, DIFFERENT).unwrap();
    assert_eq!(staged.state, EditedCandidateState::CandidateUnvalidated);
    assert_eq!(
        staged.candidate.unwrap().byte_length,
        Revision::new(DIFFERENT.len() as u64)
    );
    assert_eq!(
        g.commit_edited(&b, &a).unwrap_err(),
        ContractError::UnsupportedOperation
    );
    assert_eq!(
        s.read_document(&a).unwrap().document.revision(),
        &Revision::new(1)
    );
    drop(s);
    let s = f.reopen("epoch-3");
    let a = access(&s, 1, "inspect", 1, "epoch-3");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    assert_eq!(
        g.lookup_original(&b, &a).unwrap().state,
        EditedCandidateState::CandidateUnvalidated
    );
    assert_eq!(
        g.candidate_bytes(&b, &a).unwrap_err(),
        ContractError::InvalidAuthority
    );
    confirmed(&g, &request(&s, &a, "edited"), &a);
    assert_eq!(g.candidate_bytes(&b, &a).unwrap(), DIFFERENT);
    assert_eq!(
        g.stage_candidate_trusted(&b, &a, b"must never replace existing candidate")
            .unwrap()
            .candidate
            .unwrap(),
        g.lookup_original(&b, &a).unwrap().candidate.unwrap()
    );
    assert_eq!(g.candidate_bytes(&b, &a).unwrap(), DIFFERENT);
}
#[test]
fn unknown_ingestion_queries_original_intent_and_never_replays_after_restart() {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let p = request(&s, &a, "unknown");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let b = confirmed(&g, &p, &a);
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    db.exec("CREATE TRIGGER fail_candidate BEFORE UPDATE OF candidate_hex ON edit_candidate_intents WHEN NEW.candidate_hex IS NOT NULL BEGIN SELECT RAISE(ABORT,'synthetic candidate failure'); END",&[]).unwrap();
    assert_eq!(
        g.stage_candidate_trusted(&b, &a, DIFFERENT).unwrap_err(),
        ContractError::Unknown
    );
    db.exec("DROP TRIGGER fail_candidate", &[]).unwrap();
    drop(s);
    let s = f.reopen("epoch-2");
    let a = access(&s, 1, "after", 1, "epoch-2");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    assert_eq!(
        g.lookup_original(&b, &a).unwrap().state,
        EditedCandidateState::Unknown
    );
    assert_eq!(
        g.stage_candidate_trusted(&b, &a, DIFFERENT).unwrap_err(),
        ContractError::Unknown
    );
    assert_eq!(
        g.confirm_trusted(
            &request(&s, &a, "unknown"),
            &a,
            &Confirmation {
                binding: b.clone(),
                authority: a.authority.clone()
            }
        )
        .unwrap_err(),
        ContractError::Unknown
    );
    assert!(g.lookup_original(&b, &a).unwrap().candidate.is_none());
    assert_eq!(g.cancel_trusted(&b).unwrap(), EditedCandidateState::Unknown);
}
fn candidate_tail_failure(change: &str) {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let p = request(&s, &a, "tail");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let b = confirmed(&g, &p, &a);
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    db.exec(&format!("CREATE TRIGGER revoke_candidate AFTER UPDATE OF candidate_hex ON edit_candidate_intents WHEN NEW.candidate_hex IS NOT NULL BEGIN UPDATE document_grants SET {change} WHERE grant_id='original'; END"),&[]).unwrap();
    assert_eq!(
        g.stage_candidate_trusted(&b, &a, DIFFERENT).unwrap_err(),
        ContractError::Unknown
    );
    assert_eq!(
        g.lookup_original(&b, &a).unwrap().state,
        EditedCandidateState::Unknown
    );
    assert!(g.lookup_original(&b, &a).unwrap().candidate.is_none());
    assert_eq!(
        s.read_document(&a).unwrap().document.revision(),
        &Revision::new(1)
    );
}
#[test]
fn last_candidate_write_revocation_rolls_back_to_query_only_unknown() {
    candidate_tail_failure("active=0");
}
#[test]
fn last_candidate_write_expiry_rolls_back_to_query_only_unknown() {
    candidate_tail_failure("expires_at_ms='0'");
}
#[test]
fn last_candidate_write_generation_rolls_back_to_query_only_unknown() {
    candidate_tail_failure("generation='2'");
}
#[test]
fn last_candidate_write_epoch_rolls_back_to_query_only_unknown() {
    candidate_tail_failure("owner_epoch='other'");
}

#[test]
fn exact_confirm_same_intent_scope_and_copy_routes_are_separate() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let p = request(&s, &a, "edited");
    let b = g.prepare(&p, &a).unwrap().binding;
    let mut stale = b.clone();
    stale.patch_digest = [0; 32];
    assert_eq!(
        g.confirm_trusted(
            &p,
            &a,
            &Confirmation {
                binding: stale,
                authority: a.authority.clone()
            }
        )
        .unwrap_err(),
        ContractError::BindingMismatch
    );
    let changed = prepare_request_trusted(
        &s.read_document(&a).unwrap(),
        "edited",
        NumericCellEdit {
            sheet: "Synthetic".into(),
            cell: "A1".into(),
            expected: "2".into(),
            replacement: "9".into(),
        },
    )
    .unwrap();
    assert_eq!(
        g.prepare(&changed, &a).unwrap_err(),
        ContractError::IntentConflict
    );
    let copy = DocumentEditGateway::initialize_trusted(&s).unwrap();
    assert_eq!(
        copy.prepare_copy(&a, "edited").unwrap_err(),
        ContractError::IntentConflict
    );
    copy.prepare_copy(&a, "copy").unwrap();
    assert_eq!(
        g.prepare(&request(&s, &a, "copy"), &a).unwrap_err(),
        ContractError::IntentConflict
    );
    let mut cross = a.clone();
    cross.document = DocumentRef::new(
        Scope {
            workspace_id: "workspace".into(),
            project_id: Some("elsewhere".into()),
        },
        "document",
        Revision::new(1),
        DocumentFormat::Xlsx,
    )
    .unwrap();
    assert!(g.prepare(&p, &cross).is_err());
}
#[test]
fn cancellation_and_source_change_prevent_new_staging_without_rollback() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let p = request(&s, &a, "cancel");
    let b = confirmed(&g, &p, &a);
    assert_eq!(
        g.cancel_trusted(&b).unwrap(),
        EditedCandidateState::Cancelled
    );
    assert_eq!(
        g.stage_candidate_trusted(&b, &a, DIFFERENT).unwrap_err(),
        ContractError::Cancelled
    );
    let p = request(&s, &a, "stale");
    let b = confirmed(&g, &p, &a);
    let copy = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let cb = copy.prepare_copy(&a, "advance").unwrap().binding;
    copy.confirm_trusted(
        &cb,
        &a,
        &Confirmation {
            binding: cb.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    copy.copy_candidate(&cb, &a).unwrap();
    copy.validate_copy(&cb, &a).unwrap();
    copy.commit_copy(&cb, &a).unwrap();
    assert_eq!(
        g.stage_candidate_trusted(&b, &a, DIFFERENT).unwrap_err(),
        ContractError::RevisionConflict
    );
    let current = access(&s, 2, "current", 1, "epoch-1");
    assert_eq!(
        s.read_document(&current).unwrap().document.revision(),
        &Revision::new(2)
    );
    assert!(g.lookup_original(&b, &current).unwrap().candidate.is_none());
}
#[test]
fn candidate_corruption_and_equal_source_bytes_are_not_edited_success() {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let p = request(&s, &a, "tamper");
    let b = confirmed(&g, &p, &a);
    assert_eq!(
        g.stage_candidate_trusted(&b, &a, SYNTHETIC).unwrap_err(),
        ContractError::InvalidPayload
    );
    g.stage_candidate_trusted(&b, &a, DIFFERENT).unwrap();
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    db.exec(
        "UPDATE edit_candidate_intents SET candidate_hex='ff' WHERE intent_id='tamper'",
        &[],
    )
    .unwrap();
    assert!(g.candidate_bytes(&b, &a).is_err());
    assert!(g.lookup_original(&b, &a).is_err());
}

#[test]
fn copy_and_edited_candidates_share_the_same_total_byte_budget() {
    use muyon_core::sqlite::Db;
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let p = request(&s, &a, "quota-template");
    g.prepare(&p, &a).unwrap();
    let db = Db::open(f.path().to_str().unwrap(), false, false).unwrap();
    // Synthetic journal rows exercise the real aggregate admission SQL. They are
    // never loaded as plans, authority, engine output or validation receipts.
    db.exec("WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<18) INSERT INTO edit_candidate_intents SELECT 'quota-'||i,binding_json,source_json,request_json,state,authority_json,expires_ms,cancel_requested,hex(zeroblob(8388608)),NULL,NULL FROM edit_candidate_intents,n WHERE intent_id='quota-template'",&[]).unwrap();
    db.exec("INSERT INTO edit_candidate_intents SELECT 'quota-final',binding_json,source_json,request_json,state,authority_json,expires_ms,cancel_requested,hex(zeroblob(6291456)),NULL,NULL FROM edit_candidate_intents WHERE intent_id='quota-template'",&[]).unwrap();
    let copy = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let b = copy.prepare_copy(&a, "copy-over-budget").unwrap().binding;
    copy.confirm_trusted(
        &b,
        &a,
        &Confirmation {
            binding: b.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    assert_eq!(
        copy.copy_candidate(&b, &a).unwrap_err(),
        ContractError::RawLimit
    );
    assert_eq!(
        s.read_document(&a).unwrap().document.revision(),
        &Revision::new(1)
    );
}

#[test]
fn unpublished_candidate_bytes_require_fresh_explicit_edit_confirmation_not_source_read() {
    let f = Fixture::new();
    let s = f.store();
    let a = access(&s, 1, "original", 1, "epoch-1");
    let g = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let p = request(&s, &a, "private-candidate");
    let b = confirmed(&g, &p, &a);
    g.stage_candidate_trusted(&b, &a, DIFFERENT).unwrap();
    let mut read = access(&s, 1, "source-read-only", 1, "epoch-1");
    read.authority.generation = Revision::new(2);
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64;
    s.issue_document_grant_trusted(
        &read.document,
        &read.authority,
        &[DocumentOperation::ReadText, DocumentOperation::Inspect],
        now + 20_000,
    )
    .unwrap();
    assert_eq!(
        g.candidate_bytes(&b, &read).unwrap_err(),
        ContractError::InvalidAuthority
    );
    let fresh = access(&s, 1, "new-full-grant", 1, "epoch-1");
    let p = request(&s, &fresh, "private-candidate");
    g.prepare(&p, &fresh).unwrap();
    assert_eq!(
        g.candidate_bytes(&b, &fresh).unwrap_err(),
        ContractError::InvalidAuthority
    );
    confirmed(&g, &p, &fresh);
    assert_eq!(g.candidate_bytes(&b, &fresh).unwrap(), DIFFERENT);
    g.cancel_trusted(&b).unwrap();
    assert_eq!(
        g.candidate_bytes(&b, &fresh).unwrap_err(),
        ContractError::Cancelled
    );
    assert!(g.lookup_original(&b, &fresh).unwrap().candidate.is_some());
}

#[test]
fn schema2_host_mapping_prepares_only_unvalidated_candidate_and_obeys_revocation() {
    use muyon_core::document_edit::{
        fingerprint::ExpandedNode,
        text_protocol::{TextEdit, TextLocation},
    };
    let f = Fixture::new();
    let s = f.store_with_format(DocumentFormat::Docx);
    let a = DocumentAccess {
        document: DocumentRef::new(
            Scope {
                workspace_id: "workspace".into(),
                project_id: Some("project".into()),
            },
            "document",
            Revision::new(1),
            DocumentFormat::Docx,
        )
        .unwrap(),
        authority: AuthorityBinding {
            grant_id: "docx-source".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch-1".into(),
        },
    };
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64;
    s.issue_document_grant_trusted(
        &a.document,
        &a.authority,
        &[
            DocumentOperation::Inspect,
            DocumentOperation::ReadText,
            DocumentOperation::StructuredEdit,
        ],
        now + 20_000,
    )
    .unwrap();
    let op = TextEdit {
        location: TextLocation::DocxRun {
            paragraph_index: 0,
            run_index: 0,
        },
        observed_run: ExpandedNode {
            tag: "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}r".into(),
            attributes: vec![],
            text: None,
            tail: None,
            children: vec![ExpandedNode {
                tag: "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}t".into(),
                attributes: vec![],
                text: Some("target".into()),
                tail: None,
                children: vec![],
            }],
        },
        expected: "target".into(),
        replacement: "edited".into(),
    };
    let gateway = DocumentEditGateway::initialize_trusted(&s).unwrap();
    let p = gateway
        .prepare_text_request(&a, "docx-held", op.clone())
        .unwrap();
    let raw: serde_json::Value = serde_json::from_str(p.request_json()).unwrap();
    assert_eq!(
        raw["source_sha256"],
        s.read_document(&a).unwrap().blob.digest
    );
    assert_eq!(raw["schema_version"], 2);
    let journal = EditedCandidateJournal::initialize_trusted(&s).unwrap();
    let b = confirmed(&journal, &p, &a);
    assert_eq!(
        journal
            .stage_candidate_trusted(&b, &a, DIFFERENT)
            .unwrap()
            .state,
        EditedCandidateState::CandidateUnvalidated
    );
    assert_eq!(
        journal.commit_edited(&b, &a).unwrap_err(),
        ContractError::UnsupportedOperation
    );
    // Neither these source bytes nor the observation were Office-parsed. This is
    // protocol/storage coverage only; there is no eligibility or fidelity verdict.
    s.revoke_document_grant_trusted(&a.authority).unwrap();
    assert!(gateway.prepare_text_request(&a, "blocked", op).is_err());
    assert!(journal.candidate_bytes(&b, &a).is_err());
}
