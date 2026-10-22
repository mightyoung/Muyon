//! Original synthetic bytes only; no Office engine, model, network or user files.
use muyon_core::{
    blobs::BlobKind,
    business::BusinessStore,
    contract::*,
    document_edit::{gateway::*, Binding, Confirmation},
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
            "muyon-edit-gateway-{}-{}",
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
        self.store_with_format(DocumentFormat::Unknown)
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
        DocumentFormat::Unknown,
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
fn ready(g: &DocumentEditGateway<'_>, a: &DocumentAccess, intent: &str) -> Binding {
    let b = g.prepare_copy(a, intent).unwrap().binding;
    g.confirm_trusted(
        &b,
        a,
        &Confirmation {
            binding: b.clone(),
            authority: a.authority.clone(),
        },
    )
    .unwrap();
    assert_eq!(
        g.copy_candidate(&b, a).unwrap().state,
        DurableState::Candidate
    );
    assert_eq!(
        g.validate_copy(&b, a).unwrap().state,
        DurableState::Validated
    );
    b
}

use muyon_core::sqlite::Db;
use std::os::unix::fs::MetadataExt;
fn physical(f:&Fixture)->Vec<(String,Vec<u8>,u64,u64,u64,i64,i64)> {
 let root=PathBuf::from(format!("{}.blobs",f.path().display()));let mut result=Vec::new();
 for dir in ["objects","staging"] {for e in fs::read_dir(root.join(dir)).unwrap(){let e=e.unwrap();let m=e.metadata().unwrap();result.push((format!("{dir}/{:?}",e.file_name()),fs::read(e.path()).unwrap(),m.ino(),m.len(),m.nlink(),m.mtime(),m.mtime_nsec()));}}
 result.sort();result
}
fn counts(db:&Db)->Vec<Vec<Option<String>>> {db.query("SELECT (SELECT COUNT(*) FROM blob_uploads),(SELECT COUNT(*) FROM blobs),(SELECT COUNT(*) FROM blob_references),(SELECT COUNT(*) FROM document_revisions)",&[]).unwrap()}
fn inspect_only(s:&BusinessStore,revision:u64)->DocumentAccess {
 let a=DocumentAccess{document:reference(revision),authority:AuthorityBinding{grant_id:"inspect-only".into(),generation:Revision::new(1),owner_epoch:"epoch-1".into()}};
 let now=SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64;s.issue_document_grant_trusted(&a.document,&a.authority,&[DocumentOperation::Inspect],now+20000).unwrap();a
}
#[test] fn real_clone_and_duplicates_do_not_write_source_or_create_upload() {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let g=DocumentEditGateway::initialize_trusted(&s).unwrap();let b=ready(&g,&a,"clone");let db=Db::open(f.path().to_str().unwrap(),true,false).unwrap();let before=counts(&db);let disk=physical(&f);
 let receipt=g.commit_copy(&b,&a).unwrap().receipt.unwrap();assert_eq!(receipt.operation,CopyOperation::ByteIdenticalCopy);let q=inspect_only(&s,2);
 assert_eq!(g.commit_copy(&b,&q).unwrap().receipt,Some(receipt.clone()));assert_eq!(g.copy_candidate(&b,&q).unwrap().receipt,Some(receipt));assert_eq!(g.candidate_bytes(&b,&q).unwrap_err(),ContractError::InvalidAuthority);
 let after=counts(&db);assert_eq!(before[0][0],after[0][0]);assert_eq!(before[0][1],after[0][1]);for n in [2,3]{assert_eq!(after[0][n].as_ref().unwrap().parse::<usize>().unwrap(),before[0][n].as_ref().unwrap().parse::<usize>().unwrap()+1);}assert_eq!(physical(&f),disk);println!("clone+duplicate: unchanged object/staging bytes,inode,length,nlink,mtime; no extra blob/upload; one reference/revision");
}
#[test] fn receipt_tail_authority_mutations_roll_back_all_references_and_files() {
 for change in ["active=0","expires_at_ms='0'","generation='2'","owner_epoch='other'"] {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let g=DocumentEditGateway::initialize_trusted(&s).unwrap();let b=ready(&g,&a,"tail");let db=Db::open(f.path().to_str().unwrap(),false,false).unwrap();let before=counts(&db);let disk=physical(&f);
 db.exec(&format!("CREATE TRIGGER mutate_tail AFTER UPDATE OF receipt_json ON edit_journal_intents WHEN NEW.receipt_json IS NOT NULL BEGIN UPDATE document_grants SET {change} WHERE grant_id='original'; END"),&[]).unwrap();assert_eq!(g.commit_copy(&b,&a).unwrap_err(),ContractError::InvalidAuthority);assert_eq!(counts(&db),before);assert_eq!(physical(&f),disk);assert_eq!(s.read_document(&a).unwrap().document.revision(),&Revision::new(1));assert!(g.lookup_original(&b,&a).unwrap().receipt.is_none());println!("tail {change}: full metadata/reference/file rollback");
 }
}
#[test] fn current_inspect_unknown_query_cannot_reconfirm_or_replay() {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let g=DocumentEditGateway::initialize_trusted(&s).unwrap();let b=ready(&g,&a,"pending");let db=Db::open(f.path().to_str().unwrap(),false,false).unwrap();let before=counts(&db);let disk=physical(&f);
 db.exec("CREATE TRIGGER fail_receipt BEFORE UPDATE OF receipt_json ON edit_journal_intents WHEN NEW.receipt_json IS NOT NULL BEGIN SELECT RAISE(ABORT,'independent receipt fault'); END",&[]).unwrap();assert_eq!(g.commit_copy(&b,&a).unwrap_err(),ContractError::Unknown);
 let q=inspect_only(&s,1);assert_eq!(g.lookup_original(&b,&q).unwrap().state,DurableState::Unknown);assert_eq!(g.copy_candidate(&b,&q).unwrap_err(),ContractError::Unknown);assert_eq!(g.commit_copy(&b,&q).unwrap_err(),ContractError::Unknown);assert_eq!(g.confirm_trusted(&b,&q,&Confirmation{binding:b.clone(),authority:q.authority.clone()}).unwrap_err(),ContractError::InvalidAuthority);assert_eq!(g.candidate_bytes(&b,&q).unwrap_err(),ContractError::InvalidAuthority);assert_eq!(counts(&db),before);assert_eq!(physical(&f),disk);
}

#[test] fn persisted_receipt_title_mismatch_is_rejected_by_every_receipt_delivery() {
 let f=Fixture::new();let s=f.store();let a=access(&s,1,"original",1,"epoch-1");let g=DocumentEditGateway::initialize_trusted(&s).unwrap();let b=ready(&g,&a,"receipt-title");g.commit_copy(&b,&a).unwrap();let q=access(&s,2,"query",1,"epoch-1");let db=Db::open(f.path().to_str().unwrap(),false,false).unwrap();
 let rows=db.query("SELECT receipt_json FROM edit_journal_intents WHERE intent_id='receipt-title'",&[]).unwrap();let original=rows[0][0].as_ref().unwrap();let changed=original.replace("\"title\":\"Synthetic\"","\"title\":\"unreviewed-forged-title\"");assert_ne!(&changed,original);db.exec("UPDATE edit_journal_intents SET receipt_json=? WHERE intent_id='receipt-title'",&[&changed]).unwrap();
 assert_eq!(g.lookup_original(&b,&q).unwrap_err(),ContractError::StorageCorrupt);assert_eq!(g.copy_candidate(&b,&q).unwrap_err(),ContractError::StorageCorrupt);assert_eq!(g.commit_copy(&b,&q).unwrap_err(),ContractError::StorageCorrupt);assert_eq!(s.read_document(&q).unwrap().title,"Synthetic");println!("tampered receipt title rejected by lookup, late copy duplicate and committed duplicate; real source title intact");
}
