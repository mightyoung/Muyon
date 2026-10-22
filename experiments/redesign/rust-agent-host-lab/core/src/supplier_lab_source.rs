//! Host-owned synthetic schema12 source for the private Android Service lab.
//! This is a real SQLite read through the registered trusted handler, not a
//! production ScopeResolver bridge or a model/provider implementation.
use crate::{
    field,
    service_runtime::RunControl,
    supplier_store::{SupplierReadResult, SupplierReader},
    AuthoritySnapshot, AuthoritySource,
};
use muyon_core_agent_lab::Result;
use muyon_plugin_contract_lab::{object, string, Json};
use std::{
    fs::{self, OpenOptions},
    io::{Read, Write},
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
    rc::Rc,
    sync::Arc,
};
pub const LAB_SUPPLIER_KEY: &str = "11111111-1111-4111-8111-111111111111";
pub const LAB_SUPPLIER_REVISION: &str = "7";
const NAME: &str = "合成供应商甲";
const FIXTURE: &[u8] = include_bytes!(
    "../../../android-compose-lab/app/src/main/assets/synthetic-supplier-schema12.siq"
);
const FILE: &str = "lab-supplier.siq";
fn selected(key: &str, revision: &str) -> Result<()> {
    if key != LAB_SUPPLIER_KEY || revision != LAB_SUPPLIER_REVISION {
        return Err("production_supplier_scope_unavailable".into());
    }
    Ok(())
}
fn reference() -> Json {
    object([
        ("module_id", string("inquiry")),
        ("type", string("supplier")),
        ("key", string(LAB_SUPPLIER_KEY)),
        ("revision", string(LAB_SUPPLIER_REVISION)),
        ("schema_version", Json::Number("1".into())),
    ])
}
/// The only owner of this lab authority. It cannot be configured by UI JSON,
/// selected object DTO, SQL, paths, environment variables or external plugins.
struct SyntheticServiceAuthority;
impl AuthoritySource for SyntheticServiceAuthority {
    fn snapshot(&self) -> Result<AuthoritySnapshot> {
        Ok(AuthoritySnapshot {
            read: object([
                ("allowed", Json::Bool(true)),
                ("available", Json::Bool(true)),
                ("scope_allowed", Json::Bool(true)),
                (
                    "bindings",
                    Json::Array(vec![string("host-supplier-name-read")]),
                ),
                ("revision", string("synthetic-service-owner:v1")),
                ("binding_revision", string("synthetic-binding:v1")),
                ("source_revision", string("synthetic-schema12-fixture:v1")),
                ("rule_revision", string("synthetic-read-only:v1")),
                ("scope", string("synthetic-only:selected-supplier")),
                ("refs", Json::Array(vec![reference()])),
            ]),
            model_allowed: false,
            profile: "synthetic-local-read-only".into(),
        })
    }
}
fn source_path(dir: &Path) -> Result<PathBuf> {
    // Android filesDir may contain platform-owned aliases; install the reader
    // against the resolved private run directory so its ancestry checks remain
    // strict. No caller supplies a database path.
    let root = dir.canonicalize().map_err(|_| "supplier_run_unavailable")?;
    if !root.is_dir() {
        return Err("supplier_run_unavailable".into());
    }
    Ok(root.join(FILE))
}
fn verify_fixture(path: &Path) -> Result<()> {
    let m = fs::symlink_metadata(path).map_err(|_| "synthetic_source_unavailable")?;
    if !m.is_file() || m.file_type().is_symlink() || m.len() != FIXTURE.len() as u64 {
        return Err("synthetic_source_identity".into());
    }
    // O_NOFOLLOW is the Linux/Android public open flag. Keep the read bounded
    // even if another writer races the earlier length check.
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(0x20000)
        .open(path)
        .map_err(|_| "synthetic_source_unavailable")?;
    let mut bytes = Vec::new();
    file.take(FIXTURE.len() as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "synthetic_source_unavailable")?;
    if bytes != FIXTURE {
        return Err("synthetic_source_changed".into());
    }
    Ok(())
}
fn prepare_source(dir: &Path) -> Result<PathBuf> {
    let path = source_path(dir)?;
    match OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&path)
    {
        Ok(mut file) => {
            file.write_all(FIXTURE)
                .map_err(|_| "synthetic_source_write")?;
            file.sync_all().map_err(|_| "synthetic_source_sync")?;
            fs::File::open(path.parent().ok_or("supplier_run_unavailable")?)
                .and_then(|f| f.sync_all())
                .map_err(|_| "synthetic_source_sync")?;
        }
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => (),
        Err(_) => return Err("synthetic_source_unavailable".into()),
    }
    verify_fixture(&path)?;
    Ok(path)
}
pub fn run_lab_supplier_read(
    dir: &Path,
    text: &str,
    key: &str,
    revision: &str,
    control: Arc<RunControl>,
) -> Result<SupplierReadResult> {
    run_lab_supplier_read_admitted(dir, text, key, revision, control, |_| Ok(()))
}
pub fn run_lab_supplier_read_admitted(
    dir: &Path,
    text: &str,
    key: &str,
    revision: &str,
    control: Arc<RunControl>,
    admitted: impl FnOnce(&muyon_core_agent_lab::agent::State) -> Result<()>,
) -> Result<SupplierReadResult> {
    selected(key, revision)?;
    if text.trim().is_empty() || text.len() > 4096 {
        return Err("supplier_text_limit".into());
    }
    control.poll()?;
    let source = prepare_source(dir)?;
    let reader = SupplierReader::install_in_run(
        &source,
        dir,
        LAB_SUPPLIER_KEY,
        Rc::new(SyntheticServiceAuthority),
    )?;
    let result =
        reader.read_in_run_admitted(dir, text, LAB_SUPPLIER_KEY, control.clone(), admitted)?;
    control.poll()?;
    verify_fixture(&source)?;
    if field(&result.projection, "name")? != &string(NAME) {
        return Err("synthetic_projection_changed".into());
    }
    Ok(result)
}
/// Reconnection cannot authorize a cached projection by itself. Reopen and
/// validate the exact host-owned source and its fixed synthetic scope, without
/// executing another tool or generating a replacement historical receipt.
pub fn validate_lab_supplier_projection(
    dir: &Path,
    key: &str,
    revision: &str,
    projection: &Json,
) -> Result<()> {
    selected(key, revision)?;
    let source = source_path(dir)?;
    verify_fixture(&source)?;
    let reader = SupplierReader::install_in_run(
        &source,
        dir,
        LAB_SUPPLIER_KEY,
        Rc::new(SyntheticServiceAuthority),
    )?;
    reader.validate_projection(projection)?;
    verify_fixture(&source)
}
