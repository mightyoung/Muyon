use super::*;
use crate::{blobs::BlobKind, contract::*, documents::*};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
pub(super) struct Fixture(PathBuf);
impl Fixture {
    pub(super) fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "muyon-artifacts-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&p).unwrap();
        Self(p)
    }
    fn path(&self) -> PathBuf {
        self.0.join("business.sqlite")
    }
    pub(super) fn open(&self) -> BusinessStore {
        BusinessStore::open_existing(&self.path(), "workspace", "epoch").unwrap()
    }
    pub(super) fn setup(&self) -> (BusinessStore, DocumentAccess, DocumentAccess) {
        BusinessStore::initialize(&self.path(), "workspace").unwrap();
        let s = self.open();
        s.database()
            .exec(
                "INSERT INTO projects VALUES('project','workspace','Synthetic','1',0)",
                &[],
            )
            .unwrap();
        s.initialize_documents_trusted().unwrap();
        s.initialize_artifacts_trusted().unwrap();
        let output = document(&s, "report", b"%PDF-1.4\nsynthetic report v1\n%%EOF\n");
        let source = document(&s, "source", b"%PDF-1.4\nsynthetic source v1\n%%EOF\n");
        (s, output, source)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
pub(super) fn upload(s: &BusinessStore, bytes: &[u8]) -> FinishedBlob {
    let u = s.begin_upload("project").unwrap();
    s.append_chunk(&u.upload_id, bytes).unwrap();
    s.finish_blob(&u.upload_id, BlobKind::Pdf).unwrap()
}
pub(super) fn grant(s: &BusinessStore, document: DocumentRef, generation: u64) -> DocumentAccess {
    let authority = AuthorityBinding {
        grant_id: format!("grant-{}", document.document_id()),
        generation: Revision::new(generation),
        owner_epoch: "epoch".into(),
    };
    let expires = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
        + 29_000;
    s.issue_document_grant_trusted(
        &document,
        &authority,
        &[
            DocumentOperation::Inspect,
            DocumentOperation::ReadText,
            DocumentOperation::StructuredEdit,
        ],
        expires,
    )
    .unwrap();
    DocumentAccess {
        document,
        authority,
    }
}
fn document(s: &BusinessStore, id: &str, bytes: &[u8]) -> DocumentAccess {
    let d = s
        .register_document_trusted(
            "project",
            id,
            "Synthetic",
            DocumentFormat::Pdf,
            &upload(s, bytes),
        )
        .unwrap();
    grant(s, d.document, 1)
}
pub(super) fn generated() -> ArtifactOrigin {
    ArtifactOrigin {
        author: AnnotationAuthor::Ai {
            agent_id: "agent".into(),
            run_id: "run".into(),
        },
        context: Some(ArtifactContext {
            message_id: "message".into(),
            attempt_id: "attempt".into(),
        }),
    }
}
pub(super) fn human() -> ArtifactOrigin {
    ArtifactOrigin {
        author: AnnotationAuthor::Human {
            actor_id: "actor".into(),
        },
        context: None,
    }
}
#[test]
fn restart_restores_exact_snapshot_and_source_advance_fails_closed() {
    let f = Fixture::new();
    let (s, out, source) = f.setup();
    let saved = s
        .archive_artifact_trusted(
            "artifact",
            &out,
            std::slice::from_ref(&source),
            &generated(),
        )
        .unwrap();
    assert_eq!(saved.revision, Revision::new(1));
    assert_eq!(
        s.archive_artifact_trusted(
            "artifact",
            &out,
            std::slice::from_ref(&source),
            &generated()
        ),
        Err(ContractError::RevisionConflict)
    );
    drop(s);
    let s = f.open();
    s.initialize_artifacts_trusted().unwrap();
    let restored = s
        .read_artifact_revision(
            "artifact",
            &Revision::new(1),
            &out,
            std::slice::from_ref(&source),
        )
        .unwrap();
    assert_eq!(restored, saved);
    let mut reader = s
        .open_blob_reader("project", &restored.document.blob)
        .unwrap();
    assert_eq!(
        s.read_blob_chunk(&mut reader, 65536).unwrap(),
        b"%PDF-1.4\nsynthetic report v1\n%%EOF\n"
    );
    s.close_blob_reader(reader).unwrap();
    let newer = s
        .publish_document_revision_trusted(
            &source.document,
            "New source",
            DocumentFormat::Pdf,
            &upload(&s, b"%PDF-1.4\nsource v2\n%%EOF\n"),
        )
        .unwrap();
    let current_source = grant(&s, newer.document, 2);
    assert_eq!(
        s.read_artifact_revision(
            "artifact",
            &Revision::new(1),
            &out,
            std::slice::from_ref(&source)
        ),
        Err(ContractError::RevisionConflict)
    );
    assert_eq!(
        s.read_artifact_revision("artifact", &Revision::new(1), &out, &[current_source]),
        Err(ContractError::InvalidAuthority)
    );
    // Immutable original snapshot remains on disk; failure never retargets it.
    let raw = s
        .database()
        .query(
            "SELECT payload FROM artifact_revisions WHERE artifact_id='artifact'",
            &[],
        )
        .unwrap();
    let stored: ArtifactRevision = serde_json::from_str(raw[0][0].as_deref().unwrap()).unwrap();
    assert_eq!(stored, saved);
    assert_eq!(stored.sources[0].document, source.document);
}
#[test]
fn human_revision_is_atomic_and_generated_cannot_overwrite_it() {
    let f = Fixture::new();
    let (s, out, source) = f.setup();
    let old = s
        .archive_artifact_trusted(
            "artifact",
            &out,
            std::slice::from_ref(&source),
            &generated(),
        )
        .unwrap();
    let edited = s
        .revise_artifact_trusted(
            "artifact",
            &old.revision,
            &out,
            &upload(&s, b"%PDF-1.4\nhuman edit\n%%EOF\n"),
            "Human",
            std::slice::from_ref(&source),
            &human(),
        )
        .unwrap();
    assert_eq!(edited.sources, old.sources);
    assert_eq!(edited.created_by, old.created_by);
    assert!(edited.human_edited);
    assert_eq!(edited.modified_by, human());
    let current = grant(&s, edited.document.document.clone(), 2);
    let pending = upload(&s, b"%PDF-1.4\nnew generation\n%%EOF\n");
    assert_eq!(
        s.revise_artifact_trusted(
            "artifact",
            &edited.revision,
            &current,
            &pending,
            "Generated",
            std::slice::from_ref(&source),
            &generated()
        ),
        Err(ContractError::IntentConflict)
    );
    assert_eq!(
        s.revise_artifact_trusted(
            "artifact",
            &old.revision,
            &current,
            &pending,
            "Stale",
            std::slice::from_ref(&source),
            &human()
        ),
        Err(ContractError::RevisionConflict)
    );
    assert_eq!(s.read_document(&current).unwrap(), edited.document);
    let history = s
        .artifact_history("artifact", None, 1, &current, std::slice::from_ref(&source))
        .unwrap();
    assert_eq!(history, vec![edited.clone()]);
    assert_eq!(
        s.artifact_history(
            "artifact",
            None,
            10,
            &current,
            std::slice::from_ref(&source)
        ),
        Err(ContractError::InvalidAuthority)
    );
    assert_eq!(
        s.artifact_history(
            "artifact",
            Some(&edited.revision),
            1,
            &current,
            std::slice::from_ref(&source)
        ),
        Err(ContractError::InvalidAuthority)
    );
    assert_eq!(
        s.read_artifact_revision("artifact", &old.revision, &current, &[source]),
        Err(ContractError::InvalidAuthority)
    );
}
#[test]
fn revocation_deletion_wrong_project_and_missing_source_deny_history() {
    let f = Fixture::new();
    let (s, out, source) = f.setup();
    s.archive_artifact_trusted(
        "artifact",
        &out,
        std::slice::from_ref(&source),
        &generated(),
    )
    .unwrap();
    assert_eq!(
        s.read_artifact_revision("artifact", &Revision::new(1), &out, &[]),
        Err(ContractError::InvalidAuthority)
    );
    s.revoke_document_grant_trusted(&source.authority).unwrap();
    assert_eq!(
        s.read_artifact_revision(
            "artifact",
            &Revision::new(1),
            &out,
            std::slice::from_ref(&source)
        ),
        Err(ContractError::InvalidAuthority)
    );
    let source = grant(&s, source.document, 2);
    let other = document(&s, "other", b"%PDF-1.4\nother\n%%EOF\n");
    assert_eq!(
        s.artifact_history("artifact", None, 10, &other, std::slice::from_ref(&source)),
        Err(ContractError::BindingMismatch)
    );
    s.revoke_document_grant_trusted(&out.authority).unwrap();
    assert_eq!(
        s.artifact_history("artifact", None, 10, &out, std::slice::from_ref(&source)),
        Err(ContractError::InvalidAuthority)
    );
    let out = grant(&s, out.document, 2);
    s.database()
        .exec("UPDATE projects SET deleted=1 WHERE id='project'", &[])
        .unwrap();
    assert_eq!(
        s.artifact_history("artifact", None, 10, &out, &[source]),
        Err(ContractError::NotFound)
    );
}
#[test]
fn invalid_sources_schema_and_oversized_rows_fail_closed() {
    let f = Fixture::new();
    let (s, out, source) = f.setup();
    assert_eq!(
        s.archive_artifact_trusted(
            "artifact",
            &out,
            &[source.clone(), source.clone()],
            &human()
        ),
        Err(ContractError::InvalidPayload)
    );
    assert_eq!(
        s.artifact_history("artifact", None, 0, &out, &[]),
        Err(ContractError::InvalidPayload)
    );
    s.archive_artifact_trusted("artifact", &out, std::slice::from_ref(&source), &human())
        .unwrap();
    s.database()
        .exec(
            "UPDATE artifact_revisions SET payload=?",
            &[&"x".repeat(MAX_RECORD_BYTES + 1)],
        )
        .unwrap();
    assert_eq!(
        s.read_artifact_revision("artifact", &Revision::new(1), &out, &[source]),
        Err(ContractError::StorageCorrupt)
    );
    s.database()
        .exec(
            "UPDATE artifact_store_meta SET value='99' WHERE key='version'",
            &[],
        )
        .unwrap();
    assert_eq!(
        s.initialize_artifacts_trusted(),
        Err(ContractError::InvalidVersion)
    );
}
#[test]
fn failed_publication_rolls_back_artifact_and_document_heads() {
    let f = Fixture::new();
    let (s, out, source) = f.setup();
    let saved = s
        .archive_artifact_trusted(
            "artifact",
            &out,
            std::slice::from_ref(&source),
            &generated(),
        )
        .unwrap();
    // Force a real SQLite failure after publication, before the transaction commit.
    s.database().exec("CREATE TRIGGER fail_artifact BEFORE INSERT ON artifact_revisions BEGIN SELECT RAISE(ABORT,'synthetic'); END", &[]).unwrap();
    let blob = upload(&s, b"%PDF-1.4\nfailed revision\n%%EOF\n");
    assert!(s
        .revise_artifact_trusted(
            "artifact",
            &saved.revision,
            &out,
            &blob,
            "Failed",
            std::slice::from_ref(&source),
            &human()
        )
        .is_err());
    assert_eq!(s.read_document(&out).unwrap(), saved.document);
    assert_eq!(
        s.artifact_history("artifact", None, 10, &out, &[source])
            .unwrap(),
        vec![saved]
    );
}
#[test]
fn exact_scope_and_write_permission_are_required() {
    let f = Fixture::new();
    let (s, out, source) = f.setup();
    s.database()
        .exec(
            "INSERT INTO projects VALUES('other-project','workspace','Other synthetic','1',0)",
            &[],
        )
        .unwrap();
    let u = s.begin_upload("other-project").unwrap();
    s.append_chunk(&u.upload_id, b"%PDF-1.4\nother project\n%%EOF\n")
        .unwrap();
    let blob = s.finish_blob(&u.upload_id, BlobKind::Pdf).unwrap();
    let d = s
        .register_document_trusted(
            "other-project",
            "foreign",
            "Foreign",
            DocumentFormat::Pdf,
            &blob,
        )
        .unwrap();
    let foreign = grant(&s, d.document, 1);
    assert_eq!(
        s.archive_artifact_trusted("artifact", &out, &[foreign], &human()),
        Err(ContractError::ScopeMismatch)
    );
    // Modify only the synthetic persisted grant, never construct a fake token.
    s.database().exec("UPDATE document_grants SET permissions='[\"read_text\"]' WHERE grant_id='grant-report'", &[]).unwrap();
    assert_eq!(
        s.archive_artifact_trusted("artifact", &out, std::slice::from_ref(&source), &human()),
        Err(ContractError::InvalidAuthority)
    );
    let out = grant(&s, out.document, 2);
    s.archive_artifact_trusted(
        "artifact",
        &out,
        std::slice::from_ref(&source),
        &generated(),
    )
    .unwrap();
    let mut wrong_epoch = out.clone();
    wrong_epoch.authority.owner_epoch = "other-epoch".into();
    assert_eq!(
        s.read_artifact_revision(
            "artifact",
            &Revision::new(1),
            &wrong_epoch,
            std::slice::from_ref(&source)
        ),
        Err(ContractError::InvalidAuthority)
    );
    let mut old_generation = out.clone();
    old_generation.authority.generation = Revision::new(1);
    assert_eq!(
        s.read_artifact_revision(
            "artifact",
            &Revision::new(1),
            &old_generation,
            std::slice::from_ref(&source)
        ),
        Err(ContractError::InvalidAuthority)
    );
    s.database()
        .exec(
            "UPDATE document_grants SET expires_at_ms='0' WHERE grant_id='grant-source'",
            &[],
        )
        .unwrap();
    assert_eq!(
        s.read_artifact_revision("artifact", &Revision::new(1), &out, &[source]),
        Err(ContractError::InvalidAuthority)
    );
}
