//! Trusted-owner private uploads. File durability and SQLite commit are separate.
//! No API accepts an arbitrary path. Lookup never reconciles or collects files.
use crate::{business::BusinessStore, contract::*, sqlite::Transaction};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, DirBuilder, File, OpenOptions},
    io::{Read, Seek, SeekFrom, Write},
    os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt},
    path::{Path, PathBuf},
};

pub const MAX_CHUNK: usize = 64 * 1024;
pub const MAX_DOCUMENT_BYTES: u64 = 30 * 1024 * 1024;
pub const MAX_UPLOAD_BYTES: u64 = 150 * 1024 * 1024;
type Result<T> = std::result::Result<T, ContractError>;
#[cfg(test)]
thread_local! { static DOCUMENT_HASH_BYTES: std::cell::Cell<u64> = const { std::cell::Cell::new(0) }; }
#[cfg(test)]
pub(crate) fn record_document_hash_bytes(bytes: usize) {
    DOCUMENT_HASH_BYTES.with(|count| count.set(count.get() + bytes as u64));
}
#[cfg(test)]
pub(crate) fn take_document_hash_bytes() -> u64 {
    DOCUMENT_HASH_BYTES.with(|count| count.replace(0))
}
#[cfg(target_os = "macos")]
const NOFOLLOW: i32 = 0x100;
#[cfg(any(target_os = "linux", target_os = "android"))]
const NOFOLLOW: i32 = 0x20000;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BlobKind {
    Pdf,
    Document,
    Archive,
}
impl BlobKind {
    fn name(self) -> &'static str {
        match self {
            Self::Pdf => "pdf",
            Self::Document => "document",
            Self::Archive => "archive",
        }
    }
    fn limit(self) -> u64 {
        if self == Self::Archive {
            MAX_UPLOAD_BYTES
        } else {
            MAX_DOCUMENT_BYTES
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct UploadHandle {
    pub upload_id: String,
    pub snapshot_id: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FinishedBlob {
    pub upload_id: String,
    pub snapshot_id: String,
    pub blob: BlobRef,
    pub kind: BlobKind,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct UploadStatus {
    pub upload_id: String,
    pub snapshot_id: String,
    pub project_id: String,
    pub state: String,
    pub byte_length: Revision,
    pub digest: Option<String>,
    pub kind: Option<BlobKind>,
}
/// The File and lease cannot be constructed from untrusted JSON. Dropping this
/// object closes the OS file but conservatively retains its DB pin; explicitly
/// close through the current owner to release it, or reconcile after owner death.
pub struct ControlledReader {
    file: File,
    source: FileSource,
    position: u64,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DocumentReaderStamp {
    device: u64,
    inode: u64,
    length: u64,
    links: u64,
    modified: (i64, i64),
    changed: (i64, i64),
}
impl ControlledReader {
    pub fn source(&self) -> &FileSource {
        &self.source
    }
}
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct BlobRecovery {
    pub aborted_uploads: usize,
    pub released_reader_pins: usize,
    pub removed_staging: usize,
}
struct Upload {
    id: String,
    snapshot: String,
    project: String,
    project_revision: String,
    owner: String,
    state: String,
    length: u64,
    digest: Option<String>,
    kind: Option<BlobKind>,
}
fn sql<T>(r: crate::sqlite::Result<T>) -> Result<T> {
    r.map_err(|_| ContractError::Storage)
}
fn io<T>(r: std::io::Result<T>) -> Result<T> {
    r.map_err(|_| ContractError::StorageIo)
}
fn cell(row: &[Option<String>], at: usize) -> Result<&str> {
    row.get(at)
        .and_then(Option::as_deref)
        .ok_or(ContractError::StorageCorrupt)
}
fn identity(v: &str) -> Result<()> {
    if v.is_empty()
        || v.len() > 128
        || !v
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
    {
        Err(ContractError::InvalidIdentity)
    } else {
        Ok(())
    }
}
fn valid_digest(v: &str) -> bool {
    v.len() == 64
        && v.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn random_id(prefix: &str) -> Result<String> {
    let mut bytes = [0u8; 16];
    io(File::open("/dev/urandom"))?
        .read_exact(&mut bytes)
        .map_err(|_| ContractError::StorageIo)?;
    Ok(format!(
        "{prefix}{}",
        bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
    ))
}
fn private_directory(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(m) if m.is_dir() && !m.file_type().is_symlink() && m.mode() & 0o077 == 0 => Ok(()),
        Ok(_) => Err(ContractError::InvalidAuthority),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            io(DirBuilder::new().mode(0o700).create(path))?;
            sync_dir(path.parent().ok_or(ContractError::StorageIo)?)
        }
        Err(_) => Err(ContractError::StorageIo),
    }
}
fn sync_dir(path: &Path) -> Result<()> {
    io(io(File::open(path))?.sync_all())
}
fn open_regular(path: &Path, append: bool) -> Result<File> {
    let file = io(OpenOptions::new()
        .read(!append)
        .append(append)
        .custom_flags(NOFOLLOW)
        .open(path))?;
    if !io(file.metadata())?.is_file() {
        return Err(ContractError::InvalidPayload);
    }
    Ok(file)
}
fn verify_file(path: &Path, expected_length: u64, expected_digest: &str) -> Result<File> {
    if !valid_digest(expected_digest) || expected_length == 0 || expected_length > MAX_UPLOAD_BYTES
    {
        return Err(ContractError::InvalidPayload);
    }
    let mut file = open_regular(path, false)?;
    if io(file.metadata())?.len() != expected_length {
        return Err(ContractError::BindingMismatch);
    }
    let actual = hash_file(&mut file, expected_length)?;
    if actual != expected_digest {
        return Err(ContractError::BindingMismatch);
    }
    io(file.seek(SeekFrom::Start(0)))?;
    Ok(file)
}
fn hash_file(file: &mut File, expected_length: u64) -> Result<String> {
    io(file.seek(SeekFrom::Start(0)))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; MAX_CHUNK];
    let mut length = 0u64;
    loop {
        let n = io(file.read(&mut buffer))?;
        if n == 0 {
            break;
        }
        length += n as u64;
        if length > expected_length || length > MAX_UPLOAD_BYTES {
            return Err(ContractError::TextLimit);
        }
        hasher.update(&buffer[..n]);
        #[cfg(test)]
        record_document_hash_bytes(n);
    }
    if length != expected_length {
        return Err(ContractError::BindingMismatch);
    }
    Ok(hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}
fn check_kind(file: &mut File, length: u64, kind: BlobKind) -> Result<()> {
    if length == 0 || length > kind.limit() {
        return Err(ContractError::TextLimit);
    }
    io(file.seek(SeekFrom::Start(0)))?;
    match kind {
        BlobKind::Pdf => {
            if length < 11 {
                return Err(ContractError::InvalidPayload);
            }
            let mut header = [0; 5];
            io(file.read_exact(&mut header))?;
            if &header != b"%PDF-" {
                return Err(ContractError::InvalidPayload);
            }
            io(file.seek(SeekFrom::End(-(length.min(1024) as i64))))?;
            let mut tail = Vec::new();
            io(file.take(1024).read_to_end(&mut tail))?;
            if !tail.windows(5).any(|w| w == b"%%EOF") {
                return Err(ContractError::InvalidPayload);
            }
        }
        BlobKind::Archive => {
            let mut bytes = Vec::new();
            io(file.take(MAX_UPLOAD_BYTES + 1).read_to_end(&mut bytes))?;
            if bytes.len() as u64 != length {
                return Err(ContractError::BindingMismatch);
            }
            crate::archive::parse_archive(&bytes)?;
        }
        BlobKind::Document => {}
    }
    Ok(())
}
fn remove_if_exists(path: &Path) -> Result<bool> {
    match fs::remove_file(path) {
        Ok(()) => Ok(true),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(_) => Err(ContractError::StorageIo),
    }
}

/// A filename being present is not authority to replace it. In particular,
/// symlink_metadata distinguishes a dangling symlink from a missing target.
fn regular_target_exists(path: &Path) -> Result<bool> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_file() && !metadata.file_type().is_symlink() => Ok(true),
        Ok(_) => Err(ContractError::BindingMismatch),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(_) => Err(ContractError::StorageIo),
    }
}

fn copy_for_publication(
    source: &mut File,
    temporary: &Path,
    length: u64,
    digest: &str,
) -> Result<()> {
    let mut output = match OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(NOFOLLOW)
        .open(temporary)
    {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            // Retry may reuse a complete private copy, never overwrite a partial,
            // corrupt or redirected one. Explicit abort/recovery cleans those.
            let file = verify_file(temporary, length, digest)?;
            io(file.sync_all())?;
            return Ok(());
        }
        Err(_) => return Err(ContractError::StorageIo),
    };
    #[cfg(test)]
    checkpoint("temp-copy-created");
    io(source.seek(SeekFrom::Start(0)))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0; MAX_CHUNK];
    let mut copied = 0u64;
    loop {
        let read = io(source.read(&mut buffer))?;
        if read == 0 {
            break;
        }
        copied = copied
            .checked_add(read as u64)
            .ok_or(ContractError::TextLimit)?;
        if copied > length || copied > MAX_UPLOAD_BYTES {
            return Err(ContractError::TextLimit);
        }
        io(output.write_all(&buffer[..read]))?;
        hasher.update(&buffer[..read]);
        #[cfg(test)]
        {
            io(output.sync_all())?;
            checkpoint("temp-copy-chunk-synced");
        }
    }
    let actual: String = hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    if copied != length || actual != digest {
        return Err(ContractError::BindingMismatch);
    }
    io(output.sync_all())
}

impl BusinessStore {
    fn blob_directories(&self) -> Result<()> {
        private_directory(self.root_dir())?;
        private_directory(&self.root_dir().join("staging"))?;
        private_directory(&self.root_dir().join("objects"))
    }
    fn staging_path(&self, id: &str) -> Result<PathBuf> {
        if !id.starts_with("up_")
            || id.len() != 35
            || !id[3..].bytes().all(|b| b.is_ascii_hexdigit())
        {
            return Err(ContractError::InvalidIdentity);
        }
        Ok(self.root_dir().join("staging").join(id))
    }
    fn object_path(&self, digest: &str) -> Result<PathBuf> {
        if !valid_digest(digest) {
            return Err(ContractError::InvalidDigest);
        }
        Ok(self.root_dir().join("objects").join(digest))
    }
    fn publication_staging_path(&self, upload_id: &str) -> Result<PathBuf> {
        self.staging_path(upload_id)?;
        Ok(self
            .root_dir()
            .join("staging")
            .join(format!("pub_{upload_id}")))
    }
    fn cleanup_upload_staging(&self, upload_id: &str) -> Result<usize> {
        let mut removed = 0;
        for path in [
            self.staging_path(upload_id)?,
            self.publication_staging_path(upload_id)?,
        ] {
            removed += usize::from(remove_if_exists(&path)?);
        }
        if removed != 0 {
            sync_dir(&self.root_dir().join("staging"))?;
        }
        Ok(removed)
    }
    fn project_revision_for_blob(&self, project: &str) -> Result<String> {
        identity(project)?;
        let rows = sql(self.database().query(
            "SELECT revision FROM projects WHERE id=? AND workspace=? AND deleted=0",
            &[project, self.workspace_id()],
        ))?;
        if rows.is_empty() {
            return Err(ContractError::NotFound);
        }
        Ok(cell(&rows[0], 0)?.into())
    }
    fn load_upload(&self, id: &str) -> Result<Upload> {
        self.staging_path(id)?;
        let rows=sql(self.database().query("SELECT snapshot_id,project_id,project_revision,owner_epoch,state,byte_length,digest,kind FROM blob_uploads WHERE upload_id=? AND workspace=?",&[id,self.workspace_id()]))?;
        let r = rows.first().ok_or(ContractError::NotFound)?;
        let kind = match r[7].as_deref() {
            None => None,
            Some("pdf") => Some(BlobKind::Pdf),
            Some("document") => Some(BlobKind::Document),
            Some("archive") => Some(BlobKind::Archive),
            _ => return Err(ContractError::StorageCorrupt),
        };
        Ok(Upload {
            id: id.into(),
            snapshot: cell(r, 0)?.into(),
            project: cell(r, 1)?.into(),
            project_revision: cell(r, 2)?.into(),
            owner: cell(r, 3)?.into(),
            state: cell(r, 4)?.into(),
            length: Revision::parse(cell(r, 5)?)?.value(),
            digest: r[6].clone(),
            kind,
        })
    }
    fn check_live_upload(&self, u: &Upload) -> Result<()> {
        if u.owner != self.owner_epoch() {
            return Err(ContractError::InvalidAuthority);
        }
        if self.project_revision_for_blob(&u.project)? != u.project_revision {
            return Err(ContractError::RevisionConflict);
        }
        Ok(())
    }
    fn checked_pinned_blob(&self, u: &Upload) -> Result<BlobRef> {
        if u.state != "pinned" {
            return Err(ContractError::IntentConflict);
        }
        let digest = u.digest.as_deref().ok_or(ContractError::StorageCorrupt)?;
        let rows = sql(self.database().query("SELECT b.byte_length FROM blobs b WHERE b.digest=? AND b.state='ready' AND EXISTS(SELECT 1 FROM blob_pins p WHERE p.digest=b.digest AND p.kind='upload' AND p.upload_id=? AND p.owner_epoch=? AND p.snapshot_id=?)", &[digest,&u.id,self.owner_epoch(),&u.snapshot]))?;
        if rows.is_empty() || Revision::parse(cell(&rows[0], 0)?)?.value() != u.length {
            return Err(ContractError::BindingMismatch);
        }
        Ok(BlobRef {
            digest: digest.into(),
            byte_length: Revision::new(u.length),
        })
    }
    /// Trusted picker owner only; never expose to model-generated commands.
    /// Candidate reservation is linked to its journal in the caller's same SQL
    /// transaction BEFORE file creation. It never commits or writes output bytes.
    pub(crate) fn reserve_candidate_upload_in_transaction(
        &self,
        tx: &Transaction<'_>,
        project_id: &str,
    ) -> Result<UploadHandle> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::InvalidAuthority);
        }
        self.blob_directories()?;
        let revision = self.project_revision_for_blob(project_id)?;
        let id = random_id("up_")?;
        let snapshot = random_id("snap_")?;
        sql(self.database().exec("INSERT INTO blob_uploads(upload_id,snapshot_id,workspace,project_id,project_revision,owner_epoch,state,byte_length,digest,kind) VALUES(?,?,?,?,?,?,'copying','0',NULL,NULL)", &[&id, &snapshot, self.workspace_id(), project_id, &revision, self.owner_epoch()]))?;
        Ok(UploadHandle {
            upload_id: id,
            snapshot_id: snapshot,
        })
    }
    /// First materialization only. Never reuse/overwrite a path after an uncertain
    /// prior call. File creation/fsync are NOT reverted by a later SQL rollback.
    pub(crate) fn materialize_candidate_upload_trusted(&self, upload_id: &str) -> Result<()> {
        let upload = self.load_upload(upload_id)?;
        self.check_live_upload(&upload)?;
        if upload.state != "copying" || upload.length != 0 {
            return Err(ContractError::IntentConflict);
        }
        let file = io(OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .custom_flags(NOFOLLOW)
            .open(self.staging_path(upload_id)?))?;
        io(file.sync_all())?;
        sync_dir(&self.root_dir().join("staging"))
    }
    /// Read-only preparation inspection, including old-owner pins after restart.
    /// True means pinned exact bytes exist, NEVER engine validation/publication.
    pub(crate) fn candidate_upload_is_pinned(
        &self,
        upload_id: &str,
        project_id: &str,
        expected: &BlobRef,
    ) -> Result<bool> {
        expected.validate()?;
        let upload = self.load_upload(upload_id)?;
        self.project_revision_for_blob(project_id)?;
        if upload.project != project_id
            || upload.state != "pinned"
            || upload.kind != Some(BlobKind::Document)
            || upload.length != expected.byte_length.value()
            || upload.digest.as_deref() != Some(expected.digest.as_str())
        {
            return Ok(false);
        }
        let rows = sql(self.database().query("SELECT CASE WHEN length(CAST(b.byte_length AS BLOB))<=20 THEN b.byte_length ELSE NULL END FROM blobs b WHERE b.digest=? AND b.state='ready' AND EXISTS(SELECT 1 FROM blob_pins p WHERE p.digest=b.digest AND p.kind='upload' AND p.upload_id=? AND p.owner_epoch=? AND p.snapshot_id=?)", &[&expected.digest, upload_id, &upload.owner, &upload.snapshot]))?;
        if rows.len() != 1 || cell(&rows[0], 0)? != expected.byte_length.as_str() {
            return Ok(false);
        }
        verify_file(
            &self.object_path(&expected.digest)?,
            upload.length,
            &expected.digest,
        )?;
        Ok(true)
    }
    /// Trusted picker owner only; never expose to model-generated commands.
    pub fn begin_upload(&self, project_id: &str) -> Result<UploadHandle> {
        self.blob_directories()?;
        let tx = sql(self.database().transaction())?;
        let revision = self.project_revision_for_blob(project_id)?;
        let id = random_id("up_")?;
        let snapshot = random_id("snap_")?;
        sql(self.database().exec("INSERT INTO blob_uploads(upload_id,snapshot_id,workspace,project_id,project_revision,owner_epoch,state,byte_length,digest,kind) VALUES(?,?,?,?,?,?,'copying','0',NULL,NULL)",&[&id,&snapshot,self.workspace_id(),project_id,&revision,self.owner_epoch()]))?;
        sql(tx.commit())?;
        #[cfg(test)]
        checkpoint("upload-intent");
        let file = io(OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .custom_flags(NOFOLLOW)
            .open(self.staging_path(&id)?))?;
        io(file.sync_all())?;
        sync_dir(&self.root_dir().join("staging"))?;
        Ok(UploadHandle {
            upload_id: id,
            snapshot_id: snapshot,
        })
    }
    pub fn append_chunk(&self, upload_id: &str, bytes: &[u8]) -> Result<u64> {
        if bytes.is_empty() || bytes.len() > MAX_CHUNK {
            return Err(ContractError::TextLimit);
        }
        let tx = sql(self.database().transaction())?;
        let u = self.load_upload(upload_id)?;
        self.check_live_upload(&u)?;
        if u.state != "copying" {
            return Err(ContractError::IntentConflict);
        }
        let next = u
            .length
            .checked_add(bytes.len() as u64)
            .ok_or(ContractError::TextLimit)?;
        if next > MAX_UPLOAD_BYTES {
            return Err(ContractError::TextLimit);
        }
        let mut file = open_regular(&self.staging_path(upload_id)?, true)?;
        let metadata = io(file.metadata())?;
        // Never append through an unexpected alias, including an old staging
        // inode created before the copy-and-rename publication protocol.
        if metadata.len() != u.length || metadata.nlink() != 1 {
            return Err(ContractError::BindingMismatch);
        }
        io(file.write_all(bytes))?;
        io(file.sync_all())?;
        #[cfg(test)]
        checkpoint("chunk-synced");
        sql(self.database().exec(
            "UPDATE blob_uploads SET byte_length=? WHERE upload_id=? AND state='copying'",
            &[&next.to_string(), upload_id],
        ))?;
        sql(tx.commit())?;
        Ok(next)
    }
    pub fn lookup_upload(&self, upload_id: &str) -> Result<UploadStatus> {
        let u = self.load_upload(upload_id)?;
        Ok(UploadStatus {
            upload_id: u.id,
            snapshot_id: u.snapshot,
            project_id: u.project,
            state: u.state,
            byte_length: Revision::new(u.length),
            digest: u.digest,
            kind: u.kind,
        })
    }
    pub fn finish_blob(&self, upload_id: &str, kind: BlobKind) -> Result<FinishedBlob> {
        let tx = sql(self.database().transaction())?;
        let u = self.load_upload(upload_id)?;
        self.check_live_upload(&u)?;
        if u.state == "pinned" && u.kind == Some(kind) {
            let blob = self.checked_pinned_blob(&u)?;
            verify_file(&self.object_path(&blob.digest)?, u.length, &blob.digest)?;
            sql(tx.commit())?;
            self.cleanup_upload_staging(upload_id)?;
            return Ok(FinishedBlob {
                upload_id: u.id,
                snapshot_id: u.snapshot,
                blob,
                kind,
            });
        }
        if u.state != "copying" {
            return Err(ContractError::IntentConflict);
        }
        let mut file = open_regular(&self.staging_path(upload_id)?, false)?;
        if io(file.metadata())?.len() != u.length {
            return Err(ContractError::BindingMismatch);
        }
        check_kind(&mut file, u.length, kind)?;
        let digest = hash_file(&mut file, u.length)?;
        let existing = sql(self.database().query(
            "SELECT byte_length,state FROM blobs WHERE digest=?",
            &[&digest],
        ))?;
        if let Some(row) = existing.first() {
            if cell(row, 1)? != "ready" {
                return Err(ContractError::Unknown);
            }
            if Revision::parse(cell(row, 0)?)?.value() != u.length {
                return Err(ContractError::BindingMismatch);
            }
        }
        let object = self.object_path(&digest)?;
        if !regular_target_exists(&object)? {
            let temporary = self.publication_staging_path(upload_id)?;
            copy_for_publication(&mut file, &temporary, u.length, &digest)?;
            sync_dir(&self.root_dir().join("staging"))?;
            #[cfg(test)]
            checkpoint("temp-copy-durable");
            // The private 0700 root, OS owner lock and this exact DB write
            // transaction exclude every other managed writer between this check
            // and rename. POSIX rename itself is not a no-replace syscall.
            if !regular_target_exists(&object)? {
                io(fs::rename(&temporary, &object))?;
                #[cfg(test)]
                checkpoint("renamed-before-dir-sync");
            }
        }
        let target = verify_file(&object, u.length, &digest)?;
        io(target.sync_all())?;
        sync_dir(&self.root_dir().join("objects"))?;
        sync_dir(&self.root_dir().join("staging"))?;
        #[cfg(test)]
        checkpoint("blob-solidified");
        sql(self.database().exec("INSERT INTO blobs(digest,byte_length,state) VALUES(?,?,'ready') ON CONFLICT(digest) DO NOTHING",&[&digest,&u.length.to_string()]))?;
        sql(self.database().exec("INSERT INTO blob_pins(pin_id,digest,kind,upload_id,owner_epoch,snapshot_id) VALUES(?,?,'upload',?,?,?)",&[&random_id("pin_")?,&digest,upload_id,self.owner_epoch(),&u.snapshot]))?;
        sql(self.database().exec(
            "UPDATE blob_uploads SET state='pinned',digest=?,kind=? WHERE upload_id=?",
            &[&digest, kind.name(), upload_id],
        ))?;
        sql(tx.commit())?;
        #[cfg(test)]
        checkpoint("blob-pinned");
        // Cleanup errors are surfaced; lookup/idempotent finish can observe the
        // already-pinned fact and retry cleanup without another publication.
        self.cleanup_upload_staging(upload_id)?;
        Ok(FinishedBlob {
            upload_id: u.id,
            snapshot_id: u.snapshot,
            blob: BlobRef {
                digest,
                byte_length: Revision::new(u.length),
            },
            kind,
        })
    }
    pub fn abort_upload(&self, upload_id: &str) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        let u = self.load_upload(upload_id)?;
        if u.owner != self.owner_epoch() {
            return Err(ContractError::InvalidAuthority);
        }
        if u.state == "committed" || u.state == "unknown" {
            return Err(ContractError::IntentConflict);
        }
        if u.state == "pinned"
            && !sql(self.database().query(
                "SELECT intent_id FROM intents WHERE status IN('pending','unknown') LIMIT 1",
                &[],
            ))?
            .is_empty()
        {
            return Err(ContractError::Unknown);
        }
        sql(self.database().exec(
            "UPDATE blob_uploads SET state='aborted' WHERE upload_id=?",
            &[upload_id],
        ))?;
        sql(self.database().exec(
            "DELETE FROM blob_pins WHERE kind='upload' AND upload_id=?",
            &[upload_id],
        ))?;
        sql(tx.commit())?;
        self.cleanup_upload_staging(upload_id)?;
        Ok(())
    }
    /// Called only while the business effect/history/receipt transaction is open.
    /// Never commits independently. No filesystem mutation occurs here.
    pub(crate) fn publish_blob_in_transaction(
        &self,
        tx: &Transaction<'_>,
        upload_id: &str,
        reference_id: &str,
        project_id: &str,
        target_id: &str,
        expected: &BlobRef,
    ) -> Result<BlobRef> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::InvalidAuthority);
        }
        identity(reference_id)?;
        identity(target_id)?;
        let u = self.load_upload(upload_id)?;
        self.check_live_upload(&u)?;
        if u.project != project_id {
            return Err(ContractError::ScopeMismatch);
        }
        if u.state != "pinned" {
            return Err(ContractError::IntentConflict);
        }
        let digest = u.digest.as_deref().ok_or(ContractError::StorageCorrupt)?;
        expected.validate()?;
        if digest != expected.digest || u.length != expected.byte_length.value() {
            return Err(ContractError::BindingMismatch);
        }
        self.checked_pinned_blob(&u)?;
        verify_file(&self.object_path(digest)?, u.length, digest)?;
        sql(self.database().exec(
            "INSERT INTO blob_references(reference_id,project_id,target_id,digest) VALUES(?,?,?,?)",
            &[reference_id, project_id, target_id, digest],
        ))?;
        sql(self.database().exec(
            "UPDATE blob_uploads SET state='committed' WHERE upload_id=? AND state='pinned'",
            &[upload_id],
        ))?;
        sql(self.database().exec(
            "DELETE FROM blob_pins WHERE kind='upload' AND upload_id=?",
            &[upload_id],
        ))?;
        #[cfg(test)]
        checkpoint("publication-applied");
        Ok(BlobRef {
            digest: digest.into(),
            byte_length: Revision::new(u.length),
        })
    }
    /// COPY-only: add a reference to an already-published immutable source blob.
    /// The caller owns authorization/intent and the same SQL transaction. This
    /// performs no upload, staging, file write, pin change or independent commit.
    pub(crate) fn clone_blob_reference_in_transaction(
        &self,
        tx: &Transaction<'_>,
        project_id: &str,
        target_id: &str,
        expected_blob: &BlobRef,
        new_reference_id: &str,
    ) -> Result<BlobRef> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::InvalidAuthority);
        }
        identity(target_id)?;
        identity(new_reference_id)?;
        expected_blob.validate()?;
        self.project_revision_for_blob(project_id)?;
        let rows = sql(self.database().query(
            "SELECT CASE WHEN length(CAST(b.byte_length AS BLOB))<=20 THEN b.byte_length ELSE NULL END FROM blob_references r JOIN blobs b ON b.digest=r.digest WHERE r.project_id=? AND r.digest=? AND b.state='ready' LIMIT 1",
            &[project_id, &expected_blob.digest],
        ))?;
        let row = rows.first().ok_or(ContractError::NotFound)?;
        if cell(row, 0)? != expected_blob.byte_length.as_str() {
            return Err(ContractError::BindingMismatch);
        }
        verify_file(
            &self.object_path(&expected_blob.digest)?,
            expected_blob.byte_length.value(),
            &expected_blob.digest,
        )?;
        sql(self.database().exec(
            "INSERT INTO blob_references(reference_id,project_id,target_id,digest) VALUES(?,?,?,?)",
            &[
                new_reference_id,
                project_id,
                target_id,
                &expected_blob.digest,
            ],
        ))?;
        Ok(expected_blob.clone())
    }
    fn open_reader_for(
        &self,
        project: &str,
        snapshot: &str,
        blob: &BlobRef,
    ) -> Result<ControlledReader> {
        blob.validate()?;
        let rows = sql(self.database().query(
            "SELECT CASE WHEN length(CAST(byte_length AS BLOB))<=20 THEN byte_length ELSE NULL END FROM blobs WHERE digest=? AND state='ready'",
            &[&blob.digest],
        ))?;
        if rows.is_empty() || cell(&rows[0], 0)? != blob.byte_length.as_str() {
            return Err(ContractError::NotFound);
        }
        self.project_revision_for_blob(project)?;
        let file = verify_file(
            &self.object_path(&blob.digest)?,
            blob.byte_length.value(),
            &blob.digest,
        )?;
        let pin = random_id("pin_")?;
        sql(self.database().exec("INSERT INTO blob_pins(pin_id,digest,kind,upload_id,owner_epoch,snapshot_id) VALUES(?,?,'reader',NULL,?,?)",&[&pin,&blob.digest,self.owner_epoch(),snapshot]))?;
        Ok(ControlledReader {
            file,
            source: FileSource {
                snapshot_id: snapshot.into(),
                blob: blob.clone(),
                lease: ReadLease {
                    lease_id: pin,
                    owner_epoch: self.owner_epoch().into(),
                    generation: Revision::new(1),
                },
            },
            position: 0,
        })
    }
    pub fn open_upload_reader(&self, upload_id: &str) -> Result<ControlledReader> {
        let tx = sql(self.database().transaction())?;
        let u = self.load_upload(upload_id)?;
        self.check_live_upload(&u)?;
        if u.state != "pinned" {
            return Err(ContractError::IntentConflict);
        }
        let blob = self.checked_pinned_blob(&u)?;
        let reader = self.open_reader_for(&u.project, &u.snapshot, &blob)?;
        sql(tx.commit())?;
        Ok(reader)
    }
    pub fn open_blob_reader(&self, project_id: &str, blob: &BlobRef) -> Result<ControlledReader> {
        let tx = sql(self.database().transaction())?;
        let refs = sql(self.database().query(
            "SELECT reference_id FROM blob_references WHERE project_id=? AND digest=?",
            &[project_id, &blob.digest],
        ))?;
        if refs.is_empty() {
            return Err(ContractError::NotFound);
        }
        let reader = self.open_reader_for(project_id, &random_id("snap_")?, blob)?;
        sql(tx.commit())?;
        Ok(reader)
    }
    fn check_reader(&self, reader: &ControlledReader) -> Result<()> {
        let source = &reader.source;
        source.validate()?;
        if source.lease.owner_epoch != self.owner_epoch() || source.lease.generation.value() != 1 {
            return Err(ContractError::InvalidAuthority);
        }
        let rows=sql(self.database().query("SELECT p.pin_id FROM blob_pins p JOIN blobs b ON b.digest=p.digest WHERE p.pin_id=? AND p.owner_epoch=? AND p.snapshot_id=? AND p.digest=? AND p.kind='reader' AND b.state='ready'",&[&source.lease.lease_id,self.owner_epoch(),&source.snapshot_id,&source.blob.digest]))?;
        if rows.is_empty() {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(())
    }
    pub fn read_blob_chunk(
        &self,
        reader: &mut ControlledReader,
        max_bytes: usize,
    ) -> Result<Vec<u8>> {
        if max_bytes == 0 || max_bytes > MAX_CHUNK {
            return Err(ContractError::TextLimit);
        }
        self.check_reader(reader)?;
        let remaining = reader
            .source
            .blob
            .byte_length
            .value()
            .checked_sub(reader.position)
            .ok_or(ContractError::BindingMismatch)?;
        let mut bytes = vec![0; max_bytes.min(remaining as usize)];
        io(reader.file.read_exact(&mut bytes))?;
        reader.position += bytes.len() as u64;
        if reader.position == reader.source.blob.byte_length.value() {
            let mut extra = [0];
            if io(reader.file.read(&mut extra))? != 0 {
                return Err(ContractError::BindingMismatch);
            }
        }
        Ok(bytes)
    }
    pub fn close_blob_reader(&self, reader: ControlledReader) -> Result<()> {
        self.check_reader(&reader)?;
        let pin = reader.source.lease.lease_id.clone();
        drop(reader);
        sql(self.database().exec(
            "DELETE FROM blob_pins WHERE pin_id=? AND owner_epoch=? AND kind='reader'",
            &[&pin, self.owner_epoch()],
        ))?;
        Ok(())
    }
    /// Document facade only: keep reader acquisition in the caller's real
    /// authorization transaction, with no nested transaction or path input.
    pub(crate) fn open_document_reader_in_transaction(
        &self,
        tx: &Transaction<'_>,
        project: &str,
        blob: &BlobRef,
    ) -> Result<ControlledReader> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::InvalidAuthority);
        }
        let refs = sql(self.database().query(
            "SELECT 1 FROM blob_references WHERE project_id=? AND digest=? LIMIT 1",
            &[project, &blob.digest],
        ))?;
        if refs.is_empty() {
            return Err(ContractError::NotFound);
        }
        self.open_reader_for(project, &random_id("snap_")?, blob)
    }
    pub(crate) fn verify_document_reader_in_transaction(
        &self,
        tx: &Transaction<'_>,
        reader: &mut ControlledReader,
    ) -> Result<()> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::InvalidAuthority);
        }
        self.check_reader(reader)?;
        let digest = hash_file(&mut reader.file, reader.source.blob.byte_length.value())?;
        io(reader.file.seek(SeekFrom::Start(reader.position)))?;
        if digest != reader.source.blob.digest {
            return Err(ContractError::BindingMismatch);
        }
        Ok(())
    }
    pub(crate) fn document_reader_stamp_in_transaction(
        &self,
        tx: &Transaction<'_>,
        reader: &ControlledReader,
    ) -> Result<DocumentReaderStamp> {
        if !tx.belongs_to(self.database()) {
            return Err(ContractError::InvalidAuthority);
        }
        self.check_reader(reader)?;
        let metadata = io(reader.file.metadata())?;
        if !metadata.is_file() || metadata.len() != reader.source.blob.byte_length.value() {
            return Err(ContractError::BindingMismatch);
        }
        Ok(DocumentReaderStamp {
            device: metadata.dev(),
            inode: metadata.ino(),
            length: metadata.len(),
            links: metadata.nlink(),
            modified: (metadata.mtime(), metadata.mtime_nsec()),
            changed: (metadata.ctime(), metadata.ctime_nsec()),
        })
    }
    /// Cleanup requires an actual nonconstructible reader, not document rights.
    /// It still works after revocation, deleted pins or corrupt/missing objects.
    pub(crate) fn release_document_reader(&self, reader: &ControlledReader) -> Result<()> {
        let source = reader.source();
        if source.lease.owner_epoch != self.owner_epoch() {
            return Err(ContractError::InvalidAuthority);
        }
        sql(self.database().exec(
            "DELETE FROM blob_pins WHERE pin_id=? AND owner_epoch=? AND snapshot_id=? AND digest=? AND kind='reader'",
            &[&source.lease.lease_id, self.owner_epoch(), &source.snapshot_id, &source.blob.digest],
        ))?;
        Ok(())
    }
    /// Explicit maintenance after the OS owner lock proves the old owner is gone.
    /// pending/unknown business intents conservatively retain old upload pins.
    pub fn reconcile_blobs_after_restart(&self) -> Result<BlobRecovery> {
        self.blob_directories()?;
        let tx = sql(self.database().transaction())?;
        let unknown = sql(self.database().query(
            "SELECT intent_id FROM intents WHERE status IN('pending','unknown') LIMIT 1",
            &[],
        ))?;
        let stale=sql(self.database().query("SELECT upload_id,state FROM blob_uploads WHERE workspace=? AND owner_epoch<>? AND state IN('copying','pinned')",&[self.workspace_id(),self.owner_epoch()]))?;
        let mut recovery = BlobRecovery::default();
        for row in &stale {
            if self.document_candidate_upload_retained(cell(row, 0)?)? {
                continue;
            }
            if cell(row, 1)? == "copying" || unknown.is_empty() {
                let id = cell(row, 0)?;
                sql(self.database().exec(
                    "UPDATE blob_uploads SET state='aborted' WHERE upload_id=?",
                    &[id],
                ))?;
                sql(self.database().exec(
                    "DELETE FROM blob_pins WHERE kind='upload' AND upload_id=?",
                    &[id],
                ))?;
                recovery.aborted_uploads += 1;
            }
        }
        recovery.released_reader_pins = sql(self.database().exec(
            "DELETE FROM blob_pins WHERE kind='reader' AND owner_epoch<>?",
            &[self.owner_epoch()],
        ))?;
        sql(tx.commit())?;
        let terminal=sql(self.database().query("SELECT upload_id FROM blob_uploads WHERE workspace=? AND state IN('aborted','committed','pinned')",&[self.workspace_id()]))?;
        for row in terminal {
            recovery.removed_staging += self.cleanup_upload_staging(cell(&row, 0)?)?;
        }
        Ok(recovery)
    }
    fn can_delete_blob(&self, digest: &str) -> Result<bool> {
        let blocked=sql(self.database().query("SELECT 1 WHERE EXISTS(SELECT 1 FROM blob_references WHERE digest=?) OR EXISTS(SELECT 1 FROM blob_pins WHERE digest=?) OR EXISTS(SELECT 1 FROM blob_uploads WHERE state NOT IN('committed','aborted') AND digest=?) OR EXISTS(SELECT 1 FROM intents WHERE status IN('pending','unknown'))",&[digest,digest,digest]))?;
        if !blocked.is_empty() {
            return Ok(false);
        }
        let mut cursor = String::new();
        loop {
            let unresolved = sql(self.database().query("SELECT CASE WHEN length(CAST(upload_id AS BLOB))<=128 THEN upload_id ELSE NULL END FROM blob_uploads WHERE state NOT IN('committed','aborted') AND digest IS NULL AND (?='' OR upload_id>?) ORDER BY upload_id LIMIT 128", &[&cursor, &cursor]))?;
            if unresolved.is_empty() {
                return Ok(true);
            }
            for row in &unresolved {
                let upload = cell(row, 0)?;
                match self.document_candidate_reserves_digest(upload, digest)? {
                    Some(false) => {}
                    // Legacy unresolved uploads keep their original conservative
                    // behavior; journal-backed candidates reserve exact digests.
                    Some(true) | None => return Ok(false),
                }
                cursor = upload.into();
            }
            if unresolved.len() < 128 {
                return Ok(true);
            }
        }
    }
    /// Explicit, serialized maintenance. Marking deleting commits before unlink;
    /// publication/read acquisition both require ready in the same database.
    pub fn collect_blobs(&self) -> Result<usize> {
        self.blob_directories()?;
        let mut removed = 0;
        // Recover complete content-addressed files renamed before their ledger
        // transaction. Partial publication copies remain in staging only.
        for entry in io(fs::read_dir(self.root_dir().join("objects")))? {
            let entry = io(entry)?;
            let name = entry
                .file_name()
                .into_string()
                .map_err(|_| ContractError::StorageCorrupt)?;
            if !valid_digest(&name) {
                return Err(ContractError::StorageCorrupt);
            }
            let tx = sql(self.database().transaction())?;
            let rows = sql(self
                .database()
                .query("SELECT digest FROM blobs WHERE digest=?", &[&name]))?;
            if rows.is_empty() && self.can_delete_blob(&name)? {
                let length = io(entry.metadata())?.len();
                verify_file(&entry.path(), length, &name)?;
                sql(self.database().exec(
                    "INSERT INTO blobs(digest,byte_length,state) VALUES(?,?,'deleting')",
                    &[&name, &length.to_string()],
                ))?;
            }
            sql(tx.commit())?;
        }
        let candidates = sql(self
            .database()
            .query("SELECT digest FROM blobs ORDER BY digest", &[]))?;
        for row in candidates {
            let digest = cell(&row, 0)?;
            let tx = sql(self.database().transaction())?;
            if !self.can_delete_blob(digest)? {
                continue;
            }
            sql(self.database().exec(
                "UPDATE blobs SET state='deleting' WHERE digest=?",
                &[digest],
            ))?;
            sql(tx.commit())?;
            #[cfg(test)]
            checkpoint("gc-marked");
            if remove_if_exists(&self.object_path(digest)?)? {
                sync_dir(&self.root_dir().join("objects"))?;
            }
            #[cfg(test)]
            checkpoint("gc-unlinked");
            let tx = sql(self.database().transaction())?;
            if !self.can_delete_blob(digest)? {
                return Err(ContractError::Unknown);
            }
            sql(self.database().exec(
                "DELETE FROM blobs WHERE digest=? AND state='deleting'",
                &[digest],
            ))?;
            sql(tx.commit())?;
            removed += 1;
        }
        Ok(removed)
    }
}

#[cfg(test)]
fn checkpoint(name: &str) {
    if std::env::var("MUYON_BLOB_KILL_POINT").ok().as_deref() == Some(name) {
        if let Ok(marker) = std::env::var("MUYON_BLOB_KILL_MARKER") {
            let marker = PathBuf::from(marker);
            let temporary = marker.with_extension("tmp");
            std::fs::write(&temporary, name).unwrap();
            std::fs::rename(temporary, marker).unwrap();
            loop {
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        process::{Child, Command, Stdio},
        sync::{Arc, Barrier, Mutex},
        time::{Duration, Instant},
    };
    const PDF: &[u8] = b"%PDF-1.7\nprivate sample\n%%EOF\n";
    struct Temp(PathBuf);
    impl Temp {
        fn new() -> Self {
            let p = std::env::temp_dir().join(random_id("muyon-blob-unit-").unwrap());
            fs::create_dir(&p).unwrap();
            Self(p)
        }
        fn path(&self) -> PathBuf {
            self.0.join("business.sqlite")
        }
        fn store(&self) -> BusinessStore {
            BusinessStore::initialize(&self.path(), "workspace-a").unwrap();
            let s = self.reopen("epoch-a");
            s.database().exec("INSERT INTO projects(id,workspace,name,revision,deleted) VALUES('project-a','workspace-a','Research','1',0)",&[]).unwrap();
            s
        }
        fn reopen(&self, epoch: &str) -> BusinessStore {
            BusinessStore::open_existing(&self.path(), "workspace-a", epoch).unwrap()
        }
        fn inspect(&self) -> crate::sqlite::Db {
            crate::sqlite::Db::open(self.path().to_str().unwrap(), true, false).unwrap()
        }
    }
    impl Drop for Temp {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    fn finish(s: &BusinessStore) -> FinishedBlob {
        let up = s.begin_upload("project-a").unwrap();
        s.append_chunk(&up.upload_id, PDF).unwrap();
        s.finish_blob(&up.upload_id, BlobKind::Pdf).unwrap()
    }
    fn count(s: &BusinessStore, table: &str) -> usize {
        s.database()
            .query(&format!("SELECT COUNT(*) FROM {table}"), &[])
            .unwrap()[0][0]
            .as_ref()
            .unwrap()
            .parse()
            .unwrap()
    }
    fn pending(s: &BusinessStore, status: &str) {
        s.database().exec("INSERT INTO intents(intent_id,binding_digest,command_json,status,owner_epoch) VALUES('uncertain','digest','{}',?,'epoch-a')",&[status]).unwrap();
    }

    #[test]
    fn publication_binds_expected_bytes_project_revision_and_real_transaction() {
        let temp = Temp::new();
        let store = temp.store();
        let blob = finish(&store);
        let other = crate::sqlite::Db::open(":memory:", false, true).unwrap();
        let wrong = other.transaction().unwrap();
        assert_eq!(
            store.publish_blob_in_transaction(
                &wrong,
                &blob.upload_id,
                "ref-a",
                "project-a",
                "paper-a",
                &blob.blob
            ),
            Err(ContractError::InvalidAuthority)
        );
        drop(wrong);
        {
            let tx = store.database().transaction().unwrap();
            assert_eq!(
                store.publish_blob_in_transaction(
                    &tx,
                    &blob.upload_id,
                    "ref-a",
                    "project-other",
                    "paper-a",
                    &blob.blob
                ),
                Err(ContractError::ScopeMismatch)
            );
            let mut changed = blob.blob.clone();
            changed.digest = "0".repeat(64);
            assert_eq!(
                store.publish_blob_in_transaction(
                    &tx,
                    &blob.upload_id,
                    "ref-a",
                    "project-a",
                    "paper-a",
                    &changed
                ),
                Err(ContractError::BindingMismatch)
            );
            assert_eq!(count(&store, "blob_references"), 0);
            store
                .publish_blob_in_transaction(
                    &tx,
                    &blob.upload_id,
                    "ref-a",
                    "project-a",
                    "paper-a",
                    &blob.blob,
                )
                .unwrap();
            // Drop rolls back reference publication and pin release together.
        }
        assert_eq!(count(&store, "blob_references"), 0);
        assert_eq!(
            store.lookup_upload(&blob.upload_id).unwrap().state,
            "pinned"
        );
        assert_eq!(count(&store, "blob_pins"), 1);
        store
            .database()
            .exec("UPDATE projects SET revision='2' WHERE id='project-a'", &[])
            .unwrap();
        let tx = store.database().transaction().unwrap();
        assert_eq!(
            store.publish_blob_in_transaction(
                &tx,
                &blob.upload_id,
                "ref-a",
                "project-a",
                "paper-a",
                &blob.blob
            ),
            Err(ContractError::RevisionConflict)
        );
        drop(tx);
        store
            .database()
            .exec("UPDATE projects SET revision='1' WHERE id='project-a'", &[])
            .unwrap();
        let tx = store.database().transaction().unwrap();
        store
            .publish_blob_in_transaction(
                &tx,
                &blob.upload_id,
                "ref-a",
                "project-a",
                "paper-a",
                &blob.blob,
            )
            .unwrap();
        tx.commit().unwrap();
        assert_eq!(
            store.lookup_upload(&blob.upload_id).unwrap().state,
            "committed"
        );
        assert_eq!(count(&store, "blob_pins"), 0);
        assert_eq!(count(&store, "blob_references"), 1);
        assert_eq!(store.collect_blobs().unwrap(), 0);
        let mut reader = store.open_blob_reader("project-a", &blob.blob).unwrap();
        assert_eq!(store.read_blob_chunk(&mut reader, MAX_CHUNK).unwrap(), PDF);
        store.close_blob_reader(reader).unwrap();
        assert!(store.open_blob_reader("other-project", &blob.blob).is_err());
    }
    #[test]
    fn pending_unknown_never_expire_and_lookup_does_not_recover() {
        for state in ["pending", "unknown"] {
            let temp = Temp::new();
            let store = temp.store();
            let blob = finish(&store);
            pending(&store, state);
            assert_eq!(
                store.abort_upload(&blob.upload_id),
                Err(ContractError::Unknown)
            );
            drop(store);
            let store = temp.reopen("epoch-b");
            assert_eq!(
                store.lookup_upload(&blob.upload_id).unwrap().state,
                "pinned"
            );
            assert_eq!(
                store
                    .reconcile_blobs_after_restart()
                    .unwrap()
                    .aborted_uploads,
                0
            );
            assert_eq!(store.collect_blobs().unwrap(), 0);
            assert_eq!(count(&store, "blob_pins"), 1);
            store
                .database()
                .exec(
                    "UPDATE intents SET status='rejected' WHERE intent_id='uncertain'",
                    &[],
                )
                .unwrap();
            assert_eq!(
                store
                    .reconcile_blobs_after_restart()
                    .unwrap()
                    .aborted_uploads,
                1
            );
            assert_eq!(store.collect_blobs().unwrap(), 1);
        }
        let temp = Temp::new();
        let store = temp.store();
        let blob = finish(&store);
        store
            .database()
            .exec("UPDATE blob_uploads SET state='unknown'", &[])
            .unwrap();
        drop(store);
        let store = temp.reopen("epoch-b");
        assert_eq!(
            store
                .reconcile_blobs_after_restart()
                .unwrap()
                .aborted_uploads,
            0
        );
        assert_eq!(store.collect_blobs().unwrap(), 0);
        assert_eq!(count(&store, "blob_pins"), 1);
        assert_eq!(
            store.lookup_upload(&blob.upload_id).unwrap().state,
            "unknown"
        );
    }
    #[test]
    fn failed_ledger_after_solidification_keeps_staging_and_object_independent() {
        let temp = Temp::new();
        let store = temp.store();
        let up = store.begin_upload("project-a").unwrap();
        store.append_chunk(&up.upload_id, PDF).unwrap();
        store.database().exec("CREATE TRIGGER refuse_pin BEFORE UPDATE ON blob_uploads WHEN NEW.state='pinned' BEGIN SELECT RAISE(ABORT,'controlled'); END",&[]).unwrap();
        assert!(store.finish_blob(&up.upload_id, BlobKind::Pdf).is_err());
        assert_eq!(store.lookup_upload(&up.upload_id).unwrap().state, "copying");
        let objects = fs::read_dir(store.root_dir().join("objects"))
            .unwrap()
            .map(|e| e.unwrap().path())
            .collect::<Vec<_>>();
        assert_eq!(objects.len(), 1);
        assert_eq!(fs::read(&objects[0]).unwrap(), PDF);
        assert_eq!(
            store.append_chunk(&up.upload_id, b"extra").unwrap(),
            PDF.len() as u64 + 5
        );
        assert_eq!(fs::read(&objects[0]).unwrap(), PDF);
        assert_eq!(store.collect_blobs().unwrap(), 0);
        store.abort_upload(&up.upload_id).unwrap();
        assert_eq!(store.collect_blobs().unwrap(), 1);
    }
    #[test]
    fn rename_then_failed_pin_commit_can_retry_existing_target_without_overwrite() {
        let temp = Temp::new();
        let store = temp.store();
        let up = store.begin_upload("project-a").unwrap();
        store.append_chunk(&up.upload_id, PDF).unwrap();
        store.database().exec("CREATE TRIGGER refuse_pin BEFORE UPDATE ON blob_uploads WHEN NEW.state='pinned' BEGIN SELECT RAISE(ABORT,'controlled'); END",&[]).unwrap();
        assert!(store.finish_blob(&up.upload_id, BlobKind::Pdf).is_err());
        let object = fs::read_dir(store.root_dir().join("objects"))
            .unwrap()
            .next()
            .unwrap()
            .unwrap()
            .path();
        let inode = fs::metadata(&object).unwrap().ino();
        assert_ne!(
            inode,
            fs::metadata(store.staging_path(&up.upload_id).unwrap())
                .unwrap()
                .ino()
        );
        assert_eq!(
            fs::read(store.staging_path(&up.upload_id).unwrap()).unwrap(),
            PDF
        );
        store
            .database()
            .exec("DROP TRIGGER refuse_pin", &[])
            .unwrap();
        let finished = store.finish_blob(&up.upload_id, BlobKind::Pdf).unwrap();
        assert_eq!(fs::metadata(&object).unwrap().ino(), inode);
        assert_eq!(finished.blob.byte_length.value(), PDF.len() as u64);
        assert_eq!(count(&store, "blob_pins"), 1);
        assert!(!store.staging_path(&up.upload_id).unwrap().exists());
    }
    #[test]
    fn corrupt_existing_object_and_dangling_symlink_are_never_replaced() {
        use std::os::unix::fs::symlink;
        for dangling in [false, true] {
            let temp = Temp::new();
            let store = temp.store();
            let up = store.begin_upload("project-a").unwrap();
            store.append_chunk(&up.upload_id, PDF).unwrap();
            let digest: String = Sha256::digest(PDF)
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect();
            let object = store.object_path(&digest).unwrap();
            let missing = temp.0.join("absent-target");
            let mut corrupt = PDF.to_vec();
            corrupt[10] ^= 1;
            if dangling {
                symlink(&missing, &object).unwrap();
            } else {
                fs::write(&object, &corrupt).unwrap();
            }
            let inode = fs::symlink_metadata(&object).unwrap().ino();
            assert_eq!(
                store.finish_blob(&up.upload_id, BlobKind::Pdf),
                Err(ContractError::BindingMismatch)
            );
            assert_eq!(fs::symlink_metadata(&object).unwrap().ino(), inode);
            if dangling {
                assert_eq!(fs::read_link(&object).unwrap(), missing);
            } else {
                assert_eq!(fs::read(&object).unwrap(), corrupt);
            }
            assert_eq!(
                fs::read(store.staging_path(&up.upload_id).unwrap()).unwrap(),
                PDF
            );
            assert_eq!(count(&store, "blob_pins"), 0);
        }
    }
    #[test]
    fn partial_publication_copy_is_not_reused_and_unknown_uploads_are_not_cleaned() {
        for state in ["copying", "unknown"] {
            let temp = Temp::new();
            let store = temp.store();
            let up = store.begin_upload("project-a").unwrap();
            store.append_chunk(&up.upload_id, PDF).unwrap();
            let publication = store.publication_staging_path(&up.upload_id).unwrap();
            fs::write(&publication, b"%PDF").unwrap();
            assert_eq!(
                store.finish_blob(&up.upload_id, BlobKind::Pdf),
                Err(ContractError::BindingMismatch)
            );
            assert_eq!(fs::read(&publication).unwrap(), b"%PDF");
            assert_eq!(
                store
                    .reconcile_blobs_after_restart()
                    .unwrap()
                    .removed_staging,
                0
            );
            store
                .database()
                .exec(
                    "UPDATE blob_uploads SET state=? WHERE upload_id=?",
                    &[state, &up.upload_id],
                )
                .unwrap();
            drop(store);
            let store = temp.reopen("epoch-b");
            let recovery = store.reconcile_blobs_after_restart().unwrap();
            if state == "copying" {
                assert_eq!(recovery.aborted_uploads, 1);
                assert_eq!(recovery.removed_staging, 2);
                assert!(!publication.exists());
                assert!(!store.staging_path(&up.upload_id).unwrap().exists());
            } else {
                assert_eq!(recovery.aborted_uploads, 0);
                assert_eq!(recovery.removed_staging, 0);
                assert_eq!(fs::read(&publication).unwrap(), b"%PDF");
                assert_eq!(store.lookup_upload(&up.upload_id).unwrap().state, "unknown");
            }
            assert_eq!(store.collect_blobs().unwrap(), 0);
        }
    }
    #[test]
    fn file_and_upload_logical_length_quotas_precede_hashing_and_writing() {
        let temp = Temp::new();
        let store = temp.store();
        let up = store.begin_upload("project-a").unwrap();
        let path = store.staging_path(&up.upload_id).unwrap();
        OpenOptions::new()
            .write(true)
            .open(&path)
            .unwrap()
            .set_len(MAX_DOCUMENT_BYTES + 1)
            .unwrap();
        store
            .database()
            .exec(
                "UPDATE blob_uploads SET byte_length=? WHERE upload_id=?",
                &[&(MAX_DOCUMENT_BYTES + 1).to_string(), &up.upload_id],
            )
            .unwrap();
        assert_eq!(
            store.finish_blob(&up.upload_id, BlobKind::Pdf),
            Err(ContractError::TextLimit)
        );
        OpenOptions::new()
            .write(true)
            .open(&path)
            .unwrap()
            .set_len(MAX_UPLOAD_BYTES)
            .unwrap();
        store
            .database()
            .exec(
                "UPDATE blob_uploads SET byte_length=? WHERE upload_id=?",
                &[&MAX_UPLOAD_BYTES.to_string(), &up.upload_id],
            )
            .unwrap();
        assert_eq!(
            store.append_chunk(&up.upload_id, b"x"),
            Err(ContractError::TextLimit)
        );
        assert_eq!(fs::metadata(path).unwrap().len(), MAX_UPLOAD_BYTES);
    }
    #[test]
    fn gc_and_publish_barrier_preserves_either_upload_pin_or_reference() {
        let temp = Temp::new();
        let store = temp.store();
        let blob = finish(&store);
        let shared = Arc::new(Mutex::new(store));
        let barrier = Arc::new(Barrier::new(3));
        let s = shared.clone();
        let b = barrier.clone();
        let publisher = std::thread::spawn(move || {
            b.wait();
            let s = s.lock().unwrap();
            let tx = s.database().transaction().unwrap();
            s.publish_blob_in_transaction(
                &tx,
                &blob.upload_id,
                "ref",
                "project-a",
                "paper",
                &blob.blob,
            )
            .unwrap();
            tx.commit().unwrap();
        });
        let s = shared.clone();
        let b = barrier.clone();
        let gc = std::thread::spawn(move || {
            b.wait();
            s.lock().unwrap().collect_blobs().unwrap()
        });
        barrier.wait();
        publisher.join().unwrap();
        assert_eq!(gc.join().unwrap(), 0);
        let store = shared.lock().unwrap();
        assert_eq!(count(&store, "blob_references"), 1);
        assert_eq!(count(&store, "blobs"), 1);
    }
    #[test]
    fn gc_and_reader_barrier_covers_reader_after_upload_pin_release() {
        let temp = Temp::new();
        let store = temp.store();
        let blob = finish(&store);
        let shared = Arc::new(Mutex::new(store));
        let opened = Arc::new(Barrier::new(2));
        let collected = Arc::new(Barrier::new(2));
        let s = shared.clone();
        let first = opened.clone();
        let second = collected.clone();
        let id = blob.upload_id.clone();
        let reader = std::thread::spawn(move || {
            let mut reader = s.lock().unwrap().open_upload_reader(&id).unwrap();
            first.wait();
            second.wait();
            let s = s.lock().unwrap();
            assert_eq!(s.read_blob_chunk(&mut reader, MAX_CHUNK).unwrap(), PDF);
            s.close_blob_reader(reader).unwrap();
        });
        opened.wait();
        {
            let s = shared.lock().unwrap();
            s.abort_upload(&blob.upload_id).unwrap();
            assert_eq!(s.collect_blobs().unwrap(), 0);
        }
        collected.wait();
        reader.join().unwrap();
        assert_eq!(shared.lock().unwrap().collect_blobs().unwrap(), 1);
    }
    #[test]
    fn deleting_rejects_new_read_or_same_digest_upload() {
        let temp = Temp::new();
        let store = temp.store();
        let blob = finish(&store);
        store.abort_upload(&blob.upload_id).unwrap();
        let tx = store.database().transaction().unwrap();
        assert!(store.can_delete_blob(&blob.blob.digest).unwrap());
        store
            .database()
            .exec("UPDATE blobs SET state='deleting'", &[])
            .unwrap();
        tx.commit().unwrap();
        assert!(store
            .open_reader_for("project-a", "snapshot", &blob.blob)
            .is_err());
        let next = store.begin_upload("project-a").unwrap();
        store.append_chunk(&next.upload_id, PDF).unwrap();
        assert_eq!(
            store.finish_blob(&next.upload_id, BlobKind::Pdf),
            Err(ContractError::Unknown)
        );
        store.abort_upload(&next.upload_id).unwrap();
        assert_eq!(store.collect_blobs().unwrap(), 1);
    }
    #[test]
    fn pinned_state_alone_does_not_replace_a_durable_upload_pin() {
        let temp = Temp::new();
        let store = temp.store();
        let blob = finish(&store);
        store.database().exec("DELETE FROM blob_pins", &[]).unwrap();
        assert_eq!(
            store.finish_blob(&blob.upload_id, BlobKind::Pdf),
            Err(ContractError::BindingMismatch)
        );
        assert!(store.open_upload_reader(&blob.upload_id).is_err());
        let tx = store.database().transaction().unwrap();
        assert_eq!(
            store.publish_blob_in_transaction(
                &tx,
                &blob.upload_id,
                "ref",
                "project-a",
                "paper",
                &blob.blob
            ),
            Err(ContractError::BindingMismatch)
        );
        assert_eq!(count(&store, "blob_references"), 0);
    }
    struct Worker(Child);
    impl Drop for Worker {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
    #[test]
    fn kill_fixture() {
        let Ok(path) = std::env::var("MUYON_BLOB_CHILD_DB") else {
            return;
        };
        let store =
            BusinessStore::open_existing(Path::new(&path), "workspace-a", "epoch-child").unwrap();
        let up = store.begin_upload("project-a").unwrap();
        let point = std::env::var("MUYON_BLOB_KILL_POINT").unwrap();
        let mut content = PDF.to_vec();
        if point == "temp-copy-chunk-synced" {
            content = b"%PDF-1.7\n".to_vec();
            content.resize(MAX_CHUNK + 4096, b'x');
            content.extend_from_slice(b"\n%%EOF\n");
        }
        for chunk in content.chunks(MAX_CHUNK) {
            store.append_chunk(&up.upload_id, chunk).unwrap();
        }
        let blob = store.finish_blob(&up.upload_id, BlobKind::Pdf).unwrap();
        if std::env::var_os("MUYON_BLOB_PAPER_CHILD").is_some() {
            let mut command = CommandEnvelope {
                protocol_version: 1,
                business_version: 1,
                intent_id: "paper-intent".into(),
                scope: Scope {
                    workspace_id: "workspace-a".into(),
                    project_id: Some("project-a".into()),
                },
                expected_revision: Revision::new(0),
                authority: AuthorityBinding {
                    grant_id: "paper-grant".into(),
                    generation: Revision::new(1),
                    owner_epoch: "epoch-child".into(),
                },
                plan_id: "paper-plan".into(),
                plan_digest: "0".repeat(64),
                command: Operation::PaperCreate {
                    paper_id: "paper-a".into(),
                    payload: PaperPayload {
                        title: "Persisted research paper".into(),
                        authors: vec![],
                        year: None,
                        doi: None,
                        url: None,
                        notes: None,
                        attachment: blob.blob,
                        attachment_upload_id: Some(up.upload_id),
                    },
                },
            };
            command.plan_digest = command.expected_plan_digest().unwrap();
            store.issue_grant_trusted(&command, None).unwrap();
            assert_eq!(
                store.execute(&command).unwrap().status,
                ExecutionStatus::Committed
            );
            checkpoint("publication-committed");
        } else if point.starts_with("gc-") {
            store.abort_upload(&up.upload_id).unwrap();
            store.collect_blobs().unwrap();
        } else {
            let tx = store.database().transaction().unwrap();
            store
                .publish_blob_in_transaction(
                    &tx,
                    &up.upload_id,
                    "ref",
                    "project-a",
                    "paper",
                    &blob.blob,
                )
                .unwrap();
            tx.commit().unwrap();
            checkpoint("publication-committed");
        }
        panic!("requested checkpoint was not reached");
    }
    #[test]
    fn real_sigkill_and_reopen_at_twelve_cross_media_windows() {
        use std::os::unix::process::ExitStatusExt;
        for point in [
            "upload-intent",
            "chunk-synced",
            "temp-copy-created",
            "temp-copy-chunk-synced",
            "temp-copy-durable",
            "renamed-before-dir-sync",
            "blob-solidified",
            "blob-pinned",
            "publication-applied",
            "publication-committed",
            "gc-marked",
            "gc-unlinked",
        ] {
            let temp = Temp::new();
            drop(temp.store());
            let marker = temp.0.join("checkpoint");
            let mut child = Worker(
                Command::new(std::env::current_exe().unwrap())
                    .args(["--exact", "blobs::tests::kill_fixture", "--nocapture"])
                    .env("MUYON_BLOB_CHILD_DB", temp.path())
                    .env("MUYON_BLOB_KILL_POINT", point)
                    .env("MUYON_BLOB_KILL_MARKER", &marker)
                    .stdout(Stdio::null())
                    .stderr(Stdio::inherit())
                    .spawn()
                    .unwrap(),
            );
            let deadline = Instant::now() + Duration::from_secs(8);
            while !marker.exists() {
                assert!(Instant::now() < deadline, "checkpoint timeout: {point}");
                assert!(
                    child.0.try_wait().unwrap().is_none(),
                    "child exited before {point}"
                );
                std::thread::sleep(Duration::from_millis(10));
            }
            assert_eq!(fs::read_to_string(marker).unwrap(), point);
            child.0.kill().unwrap();
            let status = child.0.wait().unwrap();
            assert_eq!(status.signal(), Some(9), "not SIGKILL {point}");
            let store = temp.reopen("epoch-recovery");
            let db = temp.inspect();
            let refs = db
                .query("SELECT reference_id FROM blob_references", &[])
                .unwrap();
            assert_eq!(
                refs.len(),
                usize::from(point == "publication-committed"),
                "{point}"
            );
            let state = db.query("SELECT state FROM blob_uploads", &[]).unwrap();
            let expected = match point {
                "publication-committed" => "committed",
                "blob-pinned" | "publication-applied" => "pinned",
                "gc-marked" | "gc-unlinked" => "aborted",
                _ => "copying",
            };
            assert_eq!(state[0][0].as_deref(), Some(expected), "{point}");
            if point.starts_with("temp-copy-") || point == "renamed-before-dir-sync" {
                let upload = db
                    .query("SELECT upload_id,byte_length FROM blob_uploads", &[])
                    .unwrap();
                let id = cell(&upload[0], 0).unwrap();
                let length = Revision::parse(cell(&upload[0], 1).unwrap())
                    .unwrap()
                    .value();
                let original = store.staging_path(id).unwrap();
                let publication = store.publication_staging_path(id).unwrap();
                assert_eq!(
                    fs::metadata(&original).unwrap().len(),
                    length,
                    "original staging missing {point}"
                );
                match point {
                    "temp-copy-created" => assert_eq!(fs::metadata(&publication).unwrap().len(), 0),
                    "temp-copy-chunk-synced" => {
                        assert_eq!(fs::metadata(&publication).unwrap().len(), MAX_CHUNK as u64);
                        assert!(length > MAX_CHUNK as u64);
                    }
                    "temp-copy-durable" => {
                        assert_eq!(fs::metadata(&publication).unwrap().len(), length)
                    }
                    "renamed-before-dir-sync" => {
                        assert!(!publication.exists());
                        let object = fs::read_dir(store.root_dir().join("objects"))
                            .unwrap()
                            .next()
                            .unwrap()
                            .unwrap()
                            .path();
                        assert_ne!(
                            fs::metadata(object).unwrap().ino(),
                            fs::metadata(&original).unwrap().ino()
                        );
                    }
                    _ => unreachable!(),
                }
            }
            store.reconcile_blobs_after_restart().unwrap();
            store.collect_blobs().unwrap();
            assert_eq!(
                fs::read_dir(store.root_dir().join("staging"))
                    .unwrap()
                    .count(),
                0,
                "{point}"
            );
            assert_eq!(
                count(&store, "blobs"),
                usize::from(point == "publication-committed"),
                "{point}"
            );
            assert_eq!(count(&store, "blob_pins"), 0, "{point}");
            if point == "publication-committed" {
                let rows = db
                    .query("SELECT digest,byte_length FROM blobs", &[])
                    .unwrap();
                let blob = BlobRef {
                    digest: cell(&rows[0], 0).unwrap().into(),
                    byte_length: Revision::parse(cell(&rows[0], 1).unwrap()).unwrap(),
                };
                let mut reader = store.open_blob_reader("project-a", &blob).unwrap();
                assert_eq!(store.read_blob_chunk(&mut reader, MAX_CHUNK).unwrap(), PDF);
                store.close_blob_reader(reader).unwrap();
            }
            println!("SIGKILL {point}: independent SQLite state {expected}, recovery preserved publication invariants");
        }
    }

    #[test]
    fn real_paper_effect_receipt_and_blob_reference_survive_or_roll_back_together() {
        use std::os::unix::process::ExitStatusExt;
        for point in ["publication-applied", "publication-committed"] {
            let temp = Temp::new();
            drop(temp.store());
            let marker = temp.0.join("checkpoint");
            let mut child = Worker(
                Command::new(std::env::current_exe().unwrap())
                    .args(["--exact", "blobs::tests::kill_fixture", "--nocapture"])
                    .env("MUYON_BLOB_CHILD_DB", temp.path())
                    .env("MUYON_BLOB_PAPER_CHILD", "1")
                    .env("MUYON_BLOB_KILL_POINT", point)
                    .env("MUYON_BLOB_KILL_MARKER", &marker)
                    .stdout(Stdio::null())
                    .stderr(Stdio::inherit())
                    .spawn()
                    .unwrap(),
            );
            let deadline = Instant::now() + Duration::from_secs(8);
            while !marker.exists() {
                assert!(
                    Instant::now() < deadline,
                    "paper checkpoint timeout {point}"
                );
                assert!(
                    child.0.try_wait().unwrap().is_none(),
                    "paper child exited before {point}"
                );
                std::thread::sleep(Duration::from_millis(10));
            }
            child.0.kill().unwrap();
            assert_eq!(child.0.wait().unwrap().signal(), Some(9));
            let store = temp.reopen("epoch-recovery");
            let db = temp.inspect();
            let committed = point == "publication-committed";
            for table in [
                "research_entries",
                "research_documents",
                "research_bindings",
                "blob_references",
                "business_history",
            ] {
                let count = db
                    .query(&format!("SELECT COUNT(*) FROM {table}"), &[])
                    .unwrap()[0][0]
                    .as_ref()
                    .unwrap()
                    .parse::<usize>()
                    .unwrap();
                assert_eq!(count, usize::from(committed), "{point}: {table}");
            }
            let intent = db
                .query(
                    "SELECT status,receipt_json FROM intents WHERE intent_id='paper-intent'",
                    &[],
                )
                .unwrap();
            assert_eq!(
                intent[0][0].as_deref(),
                Some(if committed { "committed" } else { "pending" })
            );
            assert_eq!(intent[0][1].is_some(), committed);
            let pins = count(&store, "blob_pins");
            assert_eq!(pins, usize::from(!committed));
            let result = store.lookup("paper-intent").unwrap();
            assert_eq!(
                result.status,
                if committed {
                    ExecutionStatus::Committed
                } else {
                    ExecutionStatus::Unknown
                }
            );
            assert_eq!(result.receipt.is_some(), committed);
            store.reconcile_blobs_after_restart().unwrap();
            assert_eq!(store.collect_blobs().unwrap(), 0);
            assert_eq!(count(&store, "blobs"), 1);
            let before = db
                .query(
                    "SELECT status,receipt_json FROM intents WHERE intent_id='paper-intent'",
                    &[],
                )
                .unwrap();
            store.lookup("paper-intent").unwrap();
            assert_eq!(
                before,
                db.query(
                    "SELECT status,receipt_json FROM intents WHERE intent_id='paper-intent'",
                    &[]
                )
                .unwrap()
            );
            println!("SIGKILL actual PaperCreate {point}: effect/history/receipt/reference={} and protected blob retained",usize::from(committed));
        }
    }
}
