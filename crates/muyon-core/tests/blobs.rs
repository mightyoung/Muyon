use muyon_core::{
    blobs::{BlobKind, MAX_CHUNK},
    business::BusinessStore,
    contract::*,
    sqlite::Db,
};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};
static COUNT: AtomicU64 = AtomicU64::new(0);
const PDF: &[u8] = b"%PDF-1.7\nprivate sample\n%%EOF\n";
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "muyon-blobs-{}-{}",
            std::process::id(),
            COUNT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&p).unwrap();
        Self(p)
    }
    fn dbpath(&self) -> PathBuf {
        self.0.join("business.sqlite")
    }
    fn store(&self) -> BusinessStore {
        BusinessStore::initialize(&self.dbpath(), "workspace-a").unwrap();
        let store = self.reopen("epoch-a");
        let mut c = CommandEnvelope {
            protocol_version: 1,
            business_version: 1,
            intent_id: "project-create".into(),
            scope: Scope {
                workspace_id: "workspace-a".into(),
                project_id: Some("project-a".into()),
            },
            expected_revision: Revision::new(0),
            authority: AuthorityBinding {
                grant_id: "grant-project".into(),
                generation: Revision::new(1),
                owner_epoch: "epoch-a".into(),
            },
            plan_id: "plan-project".into(),
            plan_digest: "0".repeat(64),
            command: Operation::ProjectCreate {
                project_id: "project-a".into(),
                name: "Research".into(),
            },
        };
        c.plan_digest = c.expected_plan_digest().unwrap();
        store.issue_grant_trusted(&c, None).unwrap();
        assert_eq!(
            store.execute(&c).unwrap().status,
            ExecutionStatus::Committed
        );
        store
    }
    fn reopen(&self, epoch: &str) -> BusinessStore {
        BusinessStore::open_existing(&self.dbpath(), "workspace-a", epoch).unwrap()
    }
    fn inspect(&self) -> Db {
        Db::open(self.dbpath().to_str().unwrap(), true, false).unwrap()
    }
    fn root(&self) -> PathBuf {
        PathBuf::from(format!("{}.blobs", self.dbpath().display()))
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn durable_upload_and_repeatable_lease_reads() {
    let temp = Temp::new();
    let store = temp.store();
    let handle = store.begin_upload("project-a").unwrap();
    assert_eq!(
        store.lookup_upload(&handle.upload_id).unwrap().state,
        "copying"
    );
    store.append_chunk(&handle.upload_id, PDF).unwrap();
    let finished = store.finish_blob(&handle.upload_id, BlobKind::Pdf).unwrap();
    assert_eq!(finished.blob.byte_length.value(), PDF.len() as u64);
    assert_eq!(
        store.finish_blob(&handle.upload_id, BlobKind::Pdf).unwrap(),
        finished
    );
    for _ in 0..2 {
        let mut reader = store.open_upload_reader(&handle.upload_id).unwrap();
        assert_eq!(reader.source().snapshot_id, handle.snapshot_id);
        let mut actual = Vec::new();
        loop {
            let bytes = store.read_blob_chunk(&mut reader, 7).unwrap();
            if bytes.is_empty() {
                break;
            }
            actual.extend(bytes);
        }
        assert_eq!(actual, PDF);
        store.close_blob_reader(reader).unwrap();
    }
    assert_eq!(store.collect_blobs().unwrap(), 0);
    store.abort_upload(&handle.upload_id).unwrap();
    assert_eq!(store.collect_blobs().unwrap(), 1);
    assert!(!temp
        .root()
        .join("objects")
        .join(finished.blob.digest)
        .exists());
}
#[test]
fn input_is_opaque_and_chunks_and_kinds_are_bounded() {
    let temp = Temp::new();
    let store = temp.store();
    assert!(store.begin_upload("missing").is_err());
    assert!(store.append_chunk("../../outside", PDF).is_err());
    let handle = store.begin_upload("project-a").unwrap();
    assert_eq!(
        store.append_chunk(&handle.upload_id, &vec![0; MAX_CHUNK + 1]),
        Err(ContractError::TextLimit)
    );
    assert_eq!(
        store.append_chunk(&handle.upload_id, &[]),
        Err(ContractError::TextLimit)
    );
    store.append_chunk(&handle.upload_id, b"not pdf").unwrap();
    assert!(store.finish_blob(&handle.upload_id, BlobKind::Pdf).is_err());
    assert!(store
        .finish_blob(&handle.upload_id, BlobKind::Archive)
        .is_err());
    assert_eq!(
        store.lookup_upload(&handle.upload_id).unwrap().state,
        "copying"
    );
    assert!(store
        .finish_blob(&handle.upload_id, BlobKind::Document)
        .is_ok());
}
#[test]
fn private_snapshot_survives_source_removal_and_does_not_overwrite_corruption() {
    let temp = Temp::new();
    let store = temp.store();
    let source = temp.0.join("source.pdf");
    fs::write(&source, PDF).unwrap();
    let up = store.begin_upload("project-a").unwrap();
    store
        .append_chunk(&up.upload_id, &fs::read(&source).unwrap())
        .unwrap();
    let blob = store.finish_blob(&up.upload_id, BlobKind::Pdf).unwrap();
    fs::remove_file(&source).unwrap();
    let mut r = store.open_upload_reader(&up.upload_id).unwrap();
    assert_eq!(store.read_blob_chunk(&mut r, MAX_CHUNK).unwrap(), PDF);
    store.close_blob_reader(r).unwrap();
    let object = temp.root().join("objects").join(&blob.blob.digest);
    fs::write(&object, b"corrupt").unwrap();
    let second = store.begin_upload("project-a").unwrap();
    store.append_chunk(&second.upload_id, PDF).unwrap();
    assert_eq!(
        store.finish_blob(&second.upload_id, BlobKind::Pdf),
        Err(ContractError::BindingMismatch)
    );
    assert_eq!(fs::read(object).unwrap(), b"corrupt");
}
#[test]
fn persistent_reader_pin_outlives_upload_pin_until_explicit_close() {
    let temp = Temp::new();
    let store = temp.store();
    let up = store.begin_upload("project-a").unwrap();
    store.append_chunk(&up.upload_id, PDF).unwrap();
    store.finish_blob(&up.upload_id, BlobKind::Pdf).unwrap();
    let mut reader = store.open_upload_reader(&up.upload_id).unwrap();
    store.abort_upload(&up.upload_id).unwrap();
    assert_eq!(store.collect_blobs().unwrap(), 0);
    assert_eq!(store.read_blob_chunk(&mut reader, MAX_CHUNK).unwrap(), PDF);
    store.close_blob_reader(reader).unwrap();
    assert_eq!(store.collect_blobs().unwrap(), 1);
}
#[test]
fn lookup_is_read_only_and_restart_reconciliation_is_explicit() {
    let temp = Temp::new();
    let store = temp.store();
    let up = store.begin_upload("project-a").unwrap();
    store.append_chunk(&up.upload_id, PDF).unwrap();
    store.finish_blob(&up.upload_id, BlobKind::Pdf).unwrap();
    let reader = store.open_upload_reader(&up.upload_id).unwrap();
    drop(reader);
    drop(store);
    let store = temp.reopen("epoch-b");
    let before = temp
        .inspect()
        .query("SELECT state FROM blob_uploads", &[])
        .unwrap();
    assert_eq!(store.lookup_upload(&up.upload_id).unwrap().state, "pinned");
    assert_eq!(
        before,
        temp.inspect()
            .query("SELECT state FROM blob_uploads", &[])
            .unwrap()
    );
    assert_eq!(store.collect_blobs().unwrap(), 0);
    assert!(store.open_upload_reader(&up.upload_id).is_err());
    let result = store.reconcile_blobs_after_restart().unwrap();
    assert_eq!(result.aborted_uploads, 1);
    assert_eq!(result.released_reader_pins, 1);
    assert_eq!(store.collect_blobs().unwrap(), 1);
}
#[test]
fn archive_upload_uses_actual_archive409_metadata_reader() {
    let temp = Temp::new();
    let store = temp.store();
    let up = store.begin_upload("project-a").unwrap();
    store
        .append_chunk(
            &up.upload_id,
            include_bytes!("fixtures/archive/archive409.zip"),
        )
        .unwrap();
    assert!(store.finish_blob(&up.upload_id, BlobKind::Archive).is_ok());
}

#[test]
fn controlled_paths_refuse_symlinks_and_preserve_outside_files() {
    use std::os::unix::fs::symlink;
    let temp = Temp::new();
    let store = temp.store();
    let outside = temp.0.join("outside.pdf");
    fs::write(&outside, PDF).unwrap();
    let up = store.begin_upload("project-a").unwrap();
    let staging = temp.root().join("staging").join(&up.upload_id);
    fs::remove_file(&staging).unwrap();
    symlink(&outside, &staging).unwrap();
    assert!(store.append_chunk(&up.upload_id, b"injected").is_err());
    assert!(store.finish_blob(&up.upload_id, BlobKind::Pdf).is_err());
    assert_eq!(fs::read(&outside).unwrap(), PDF);
    store.abort_upload(&up.upload_id).unwrap();
    assert!(outside.exists());
    let up = store.begin_upload("project-a").unwrap();
    store.append_chunk(&up.upload_id, PDF).unwrap();
    let blob = store.finish_blob(&up.upload_id, BlobKind::Pdf).unwrap();
    let object = temp.root().join("objects").join(&blob.blob.digest);
    fs::remove_file(&object).unwrap();
    symlink(&outside, &object).unwrap();
    assert!(store.open_upload_reader(&up.upload_id).is_err());
    assert_eq!(fs::read(&outside).unwrap(), PDF);

    let second = Temp::new();
    let store = second.store();
    let outside_dir = second.0.join("outside-directory");
    fs::create_dir(&outside_dir).unwrap();
    symlink(&outside_dir, second.root()).unwrap();
    assert!(store.begin_upload("project-a").is_err());
    assert_eq!(fs::read_dir(outside_dir).unwrap().count(), 0);
}

#[test]
fn equal_content_reuses_verified_object_but_retains_independent_upload_pins() {
    let temp = Temp::new();
    let store = temp.store();
    let first = store.begin_upload("project-a").unwrap();
    store.append_chunk(&first.upload_id, PDF).unwrap();
    let a = store.finish_blob(&first.upload_id, BlobKind::Pdf).unwrap();
    let second = store.begin_upload("project-a").unwrap();
    store.append_chunk(&second.upload_id, PDF).unwrap();
    let b = store.finish_blob(&second.upload_id, BlobKind::Pdf).unwrap();
    assert_eq!(a.blob, b.blob);
    assert_ne!(a.snapshot_id, b.snapshot_id);
    assert_eq!(
        fs::read_dir(temp.root().join("objects")).unwrap().count(),
        1
    );
    assert_eq!(
        temp.inspect()
            .query("SELECT COUNT(*) FROM blob_pins", &[])
            .unwrap()[0][0]
            .as_deref(),
        Some("2")
    );
    store.abort_upload(&first.upload_id).unwrap();
    assert_eq!(store.collect_blobs().unwrap(), 0);
    let mut reader = store.open_upload_reader(&second.upload_id).unwrap();
    assert_eq!(store.read_blob_chunk(&mut reader, MAX_CHUNK).unwrap(), PDF);
    store.close_blob_reader(reader).unwrap();
    store.abort_upload(&second.upload_id).unwrap();
    assert_eq!(store.collect_blobs().unwrap(), 1);
}
