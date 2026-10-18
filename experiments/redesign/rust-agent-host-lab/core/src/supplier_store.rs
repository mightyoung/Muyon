//! Private domain12 supplier-name dependency slice. No model or external source configuration.
//! Trusted host owns installation and MUST supply its current ScopeResolver authority.
#[path = "supplier_sqlite.rs"]
mod sqlite;
use crate::{
    field, service_runtime::RunControl, AuthoritySnapshot, AuthoritySource, Enrollment, Json,
    NativeSession, PurposeReview, RawRead, ReadHandler,
};
use muyon_core_agent_lab::{
    agent::{Agent, Limits, State},
    Result,
};
use muyon_plugin_contract_lab::{object, parse, string};
use std::{
    cell::RefCell,
    os::unix::fs::MetadataExt,
    path::{Component, Path, PathBuf},
    rc::Rc,
    sync::Arc,
};
const BINDING: &str = "host-supplier-name-read";
const OPERATION: &str = "inquiry/supplier_name@1";
const TOOL: &str = "inquiry.supplier_name";
#[derive(Clone, PartialEq, Eq)]
struct FileIdentity {
    dev: u64,
    ino: u64,
    uid: u32,
    mode: u32,
}
impl FileIdentity {
    fn at(path: &Path, directory: bool) -> Result<Self> {
        let m = std::fs::symlink_metadata(path).map_err(|_| "supplier_source_unavailable")?;
        if m.file_type().is_symlink() || if directory { !m.is_dir() } else { !m.is_file() } {
            return Err("supplier_path_type".into());
        }
        Ok(Self {
            dev: m.dev(),
            ino: m.ino(),
            uid: m.uid(),
            mode: m.mode(),
        })
    }
}
struct SupplierStore {
    path: PathBuf,
    identities: Vec<(PathBuf, FileIdentity)>,
    db: sqlite::Db,
    id: String,
}
struct Record {
    reference: Json,
    name: String,
    source_version: String,
}
impl SupplierStore {
    fn open(path: &Path, id: &str) -> Result<Self> {
        if !path.is_absolute() || id.is_empty() || id.len() > 128 || id.contains('\0') {
            return Err("supplier_install_identity".into());
        }
        let components: Vec<_> = path.components().collect();
        if components
            .iter()
            .any(|c| !matches!(c, Component::RootDir | Component::Normal(_)))
        {
            return Err("supplier_install_path".into());
        }
        let mut current = PathBuf::new();
        let mut identities = Vec::new();
        for (i, c) in components.iter().enumerate() {
            current.push(c.as_os_str());
            identities.push((
                current.clone(),
                FileIdentity::at(&current, i + 1 != components.len())?,
            ));
        }
        let db = sqlite::Db::open_readonly(path.to_str().ok_or("supplier_path_utf8")?)?;
        let store = Self {
            path: path.into(),
            identities,
            db,
            id: id.into(),
        };
        store.verify_identity()?;
        store.record()?;
        Ok(store)
    }
    fn verify_identity(&self) -> Result<()> {
        for (path, identity) in &self.identities {
            if FileIdentity::at(path, path != &self.path)? != *identity {
                return Err("supplier_source_replaced".into());
            }
        }
        Ok(())
    }
    fn scalar(&self, sql: &str, args: &[&str]) -> Result<String> {
        let rows = self.db.query(sql, args)?;
        if rows.len() != 1 || rows[0].len() != 1 {
            return Err("supplier_scalar_shape".into());
        }
        rows[0][0].clone().ok_or("supplier_null".into())
    }
    fn schema(&self) -> Result<()> {
        for table in ["meta", "supplier"] {
            if self.scalar("SELECT type FROM sqlite_master WHERE name=?", &[table])? != "table" {
                return Err("supplier_table_shape".into());
            }
        }
        let meta = self.db.query("PRAGMA table_info(meta)", &[])?;
        let expected_meta = [("key", "TEXT", "0", "1"), ("value", "TEXT", "1", "0")];
        if meta.len() != expected_meta.len() {
            return Err("supplier_meta_columns".into());
        }
        for (row, (name, typ, notnull, pk)) in meta.iter().zip(expected_meta) {
            for (i, v) in [(1, name), (2, typ), (3, notnull), (5, pk)] {
                if row.get(i).and_then(|x| x.as_deref()) != Some(v) {
                    return Err("supplier_meta_columns".into());
                }
            }
        }
        for key in ["format", "schema_version"] {
            if self.scalar(
                "SELECT typeof(key)||':'||typeof(value) FROM meta WHERE key=?",
                &[key],
            )? != "text:text"
            {
                return Err("supplier_meta_type".into());
            }
        }
        if self.scalar("SELECT value FROM meta WHERE key='format'", &[])? != "supplier-inquiry"
            || self.scalar("SELECT value FROM meta WHERE key='schema_version'", &[])? != "12"
        {
            return Err("supplier_domain_schema".into());
        }
        let expected = [
            ("id", "TEXT", "0", "1"),
            ("version", "INTEGER", "1", "0"),
            ("updated_at", "TEXT", "1", "0"),
            ("updated_by", "TEXT", "1", "0"),
            ("deleted", "INTEGER", "1", "0"),
            ("data", "TEXT", "1", "0"),
        ];
        let columns = self.db.query("PRAGMA table_info(supplier)", &[])?;
        if columns.len() != expected.len() {
            return Err("supplier_columns".into());
        }
        for (row, (name, typ, notnull, pk)) in columns.iter().zip(expected) {
            for (i, v) in [(1, name), (2, typ), (3, notnull), (5, pk)] {
                if row.get(i).and_then(|x| x.as_deref()) != Some(v) {
                    return Err("supplier_columns".into());
                }
            }
        }
        Ok(())
    }
    fn record(&self) -> Result<Record> {
        self.verify_identity()?;
        let before = self.scalar("PRAGMA data_version", &[])?;
        self.db.query("BEGIN", &[])?;
        struct Rollback<'a>(&'a sqlite::Db);
        impl Drop for Rollback<'_> {
            fn drop(&mut self) {
                let _ = self.0.query("ROLLBACK", &[]);
            }
        }
        let transaction = Rollback(&self.db);
        self.schema()?;
        // Bound payload bytes before SQLite returns the text to native code.
        let rows=self.db.query("SELECT version,deleted,CASE WHEN length(CAST(data AS BLOB))<=65536 THEN data ELSE NULL END,typeof(version),typeof(deleted),typeof(data) FROM supplier WHERE id=? LIMIT 2",&[&self.id])?;
        if rows.len() != 1 || rows[0].len() != 6 {
            return Err("supplier_missing".into());
        }
        let row = &rows[0];
        if row[1].as_deref() != Some("0")
            || row[3].as_deref() != Some("integer")
            || row[4].as_deref() != Some("integer")
            || row[5].as_deref() != Some("text")
        {
            return Err("supplier_row_type_or_deleted".into());
        }
        let version = row[0].as_deref().ok_or("supplier_revision")?;
        if !version.parse::<i64>().is_ok_and(|v| v > 0) {
            return Err("supplier_revision".into());
        }
        let data = row[2].as_deref().ok_or("supplier_payload_budget")?;
        let value = parse(data.as_bytes())?;
        let dense = value.object()?;
        let fields = [
            "name",
            "aliases",
            "address",
            "categories",
            "notes",
            "merged_into",
            "rating",
            "rating_note",
        ];
        if dense.len() != fields.len() || fields.iter().any(|k| !dense.contains_key(*k)) {
            return Err("supplier_dense_payload".into());
        }
        let name = field(&value, "name")?.string()?.to_owned();
        if name.is_empty() || name.len() > 4096 || name.chars().count() > 2000 {
            return Err("supplier_name_budget".into());
        }
        let reference = object([
            ("module_id", string("inquiry")),
            ("type", string("supplier")),
            ("key", string(&self.id)),
            ("revision", string(version)),
            ("schema_version", Json::Number("1".into())),
        ]);
        drop(transaction);
        if before != self.scalar("PRAGMA data_version", &[])? {
            return Err("supplier_source_changed".into());
        }
        self.verify_identity()?;
        Ok(Record {
            reference,
            name,
            source_version: before,
        })
    }
}
/// Installed bridge to existing host authority; no JSON request can replace it.
/// Implementations must include ScopeResolver/host scope owner and current policy
/// stamps. This wrapper cannot reconstruct ephemeral production authority from DB.
pub struct CurrentSupplierAuthority {
    store: Rc<SupplierStore>,
    host: Rc<dyn AuthoritySource>,
    source_stamp: RefCell<Option<(String, Json)>>,
}
impl CurrentSupplierAuthority {
    fn current(&self) -> Result<(AuthoritySnapshot, Record)> {
        let mut snapshot = self.host.snapshot()?;
        let read = snapshot.read.object()?;
        let fields = [
            "allowed",
            "available",
            "scope_allowed",
            "bindings",
            "revision",
            "binding_revision",
            "source_revision",
            "rule_revision",
            "scope",
            "refs",
        ];
        if read.len() != fields.len() || fields.iter().any(|k| !read.contains_key(*k)) {
            return Err("supplier_authority_shape".into());
        }
        for key in ["allowed", "available", "scope_allowed"] {
            if field(&snapshot.read, key)? != &Json::Bool(true) {
                return Err("supplier_authority_denied".into());
            }
        }
        for key in [
            "revision",
            "binding_revision",
            "source_revision",
            "rule_revision",
            "scope",
        ] {
            let s = field(&snapshot.read, key)?.string()?;
            if s.is_empty() || s.len() > 4096 {
                return Err("supplier_authority_unknown".into());
            }
        }
        if !field(&snapshot.read, "bindings")?
            .array()?
            .contains(&string(BINDING))
        {
            return Err("supplier_binding_denied".into());
        }
        let record = self.store.record()?;
        let refs = field(&snapshot.read, "refs")?.array()?;
        if refs.len() != 1 || refs[0] != record.reference {
            return Err("supplier_current_ref_changed".into());
        }
        if self.host.snapshot()? != snapshot {
            return Err("supplier_host_authority_changed".into());
        }
        // Host callbacks can yield or trigger a source change: validate again
        // after the final host sample, including the final publication sample.
        if self.store.scalar("PRAGMA data_version", &[])? != record.source_version {
            return Err("supplier_source_changed".into());
        }
        self.store.verify_identity()?;
        let source = field(&snapshot.read, "source_revision")?.clone();
        if let Some((previous_db, previous_host)) = &*self.source_stamp.borrow() {
            if previous_db != &record.source_version && previous_host == &source {
                return Err("supplier_source_stamp_changed".into());
            }
        }
        *self.source_stamp.borrow_mut() = Some((record.source_version.clone(), source.clone()));
        if let Json::Object(m) = &mut snapshot.read {
            m.insert(
                "source_revision".into(),
                string(Json::Array(vec![source, string(&record.source_version)]).encode()),
            );
        }
        snapshot.model_allowed = false;
        snapshot.profile = "local-read-only".into();
        Ok((snapshot, record))
    }
}
impl AuthoritySource for CurrentSupplierAuthority {
    fn snapshot(&self) -> Result<AuthoritySnapshot> {
        Ok(self.current()?.0)
    }
}
struct SupplierHandler {
    authority: Rc<CurrentSupplierAuthority>,
    pinned: AuthoritySnapshot,
    reference: Json,
}
impl ReadHandler for SupplierHandler {
    fn admit_read(&self, args: &Json, refs: &[Json]) -> Result<()> {
        let m = args.object()?;
        if m.len() != 1
            || field(args, "id")? != field(&self.reference, "key")?
            || refs != [self.reference.clone()]
        {
            return Err("supplier_request_scope".into());
        }
        Ok(())
    }
    fn read(&mut self, args: &Json) -> Result<RawRead> {
        self.admit_read(args, &[self.reference.clone()])?;
        let (authority, record) = self.authority.current()?;
        if authority != self.pinned || record.reference != self.reference {
            return Err("supplier_read_changed".into());
        }
        let projection = object([
            ("supplier", record.reference),
            ("name", string(record.name)),
        ]);
        // Raw receipt intentionally records only the selected business slice.
        Ok(RawRead {
            raw: projection.clone(),
            projection,
        })
    }
}
struct LocalReadReview;
impl PurposeReview for LocalReadReview {
    fn review(&self, _: &Json, _: &Json, purpose: &str) -> Result<()> {
        if purpose == "model_context" {
            Ok(())
        } else {
            Err("supplier_model_disabled".into())
        }
    }
    fn mask_answer(&self, _: &str) -> Result<String> {
        Err("supplier_model_disabled".into())
    }
}
/// Local Rust consumer facade. Installation is a host-only operation.
/// Each call rereads current values and creates its own original durable receipt.
/// Production Dart authority is separate; the Service synthetic lab uses a
/// dedicated host-owned source and does not claim production authority.
pub struct SupplierReader {
    authority: Rc<CurrentSupplierAuthority>,
    receipts: PathBuf,
}
pub struct SupplierReadResult {
    pub projection: Json,
    pub receipt_ref: Json,
    pub task_id: String,
    pub attempt_id: String,
}
impl SupplierReader {
    pub fn install_host_scope(
        _receipts: &Path,
        _id: &str,
        _bridge: Rc<crate::supplier_scope_bridge::HostSupplierScopeBridge>,
    ) -> Result<Self> {
        Err("supplier_scope_bridge_unavailable".into())
    }
    pub(crate) fn install_host_scope_in_run(
        _dir: &Path,
        _id: &str,
        _bridge: Rc<crate::supplier_scope_bridge::HostSupplierScopeBridge>,
    ) -> Result<Self> {
        Err("supplier_scope_bridge_unavailable".into())
    }
    pub fn validate_current_projection(&self, _projection: &Json) -> Result<()> {
        Err("supplier_scope_bridge_unavailable".into())
    }
    pub fn install(
        db: &Path,
        receipts: &Path,
        id: &str,
        host: Rc<dyn AuthoritySource>,
    ) -> Result<Self> {
        let store = Rc::new(SupplierStore::open(db, id)?);
        let authority = Rc::new(CurrentSupplierAuthority {
            store,
            host,
            source_stamp: RefCell::new(None),
        });
        authority.snapshot()?;
        // Existing protected native store checks each generated child directory.
        if receipts.exists() {
            return Err("supplier_receipt_root_exists".into());
        }
        muyon_core_agent_lab::store::create_dir(receipts)?;
        Ok(Self {
            authority,
            receipts: receipts.into(),
        })
    }
    /// Host-only installation for a Service run. The caller owns and validates
    /// the existing run directory; NativeStore keeps its original durable path.
    pub(crate) fn install_in_run(
        db: &Path,
        dir: &Path,
        id: &str,
        host: Rc<dyn AuthoritySource>,
    ) -> Result<Self> {
        let store = Rc::new(SupplierStore::open(db, id)?);
        let authority = Rc::new(CurrentSupplierAuthority {
            store,
            host,
            source_stamp: RefCell::new(None),
        });
        authority.snapshot()?;
        Ok(Self {
            authority,
            receipts: dir.into(),
        })
    }
    /// Fresh source/authority validation for disclosure; creates no receipt.
    pub(crate) fn validate_projection(&self, projection: &Json) -> Result<()> {
        let (_, record) = self.authority.current()?;
        let current = object([
            ("supplier", record.reference),
            ("name", string(record.name)),
        ]);
        if &current != projection {
            return Err("supplier_projection_changed".into());
        }
        Ok(())
    }
    pub fn read_current(&self, id: &str) -> Result<SupplierReadResult> {
        if id != self.authority.store.id {
            return Err("supplier_request_scope".into());
        }
        let dir = self.receipts.join(format!("read-{}", crate::nonce()?));
        muyon_core_agent_lab::store::create_dir(&dir)?;
        self.read_in_run(
            &dir,
            "read selected supplier name",
            id,
            Arc::new(RunControl::new()),
        )
    }
    pub(crate) fn read_in_run(
        &self,
        dir: &Path,
        text: &str,
        id: &str,
        control: Arc<RunControl>,
    ) -> Result<SupplierReadResult> {
        self.read_in_run_admitted(dir, text, id, control, |_| Ok(()))
    }
    pub(crate) fn read_in_run_admitted(
        &self,
        dir: &Path,
        text: &str,
        id: &str,
        control: Arc<RunControl>,
        admitted: impl FnOnce(&State) -> Result<()>,
    ) -> Result<SupplierReadResult> {
        control.poll()?;
        if id != self.authority.store.id {
            return Err("supplier_request_scope".into());
        }
        let (pinned, record) = self.authority.current()?;
        let session = NativeSession::service_in_process(
            dir,
            self.authority.clone(),
            Rc::new(LocalReadReview),
            text,
            control.clone(),
        )?;
        let mut session = session.borrow_mut();
        session.register(Enrollment {
            bundle: bundle()?,
            operation: OPERATION.into(),
            tool_id: TOOL.into(),
            binding_id: BINDING.into(),
            scope_refs: vec![record.reference.clone()],
            handler: Box::new(SupplierHandler {
                authority: self.authority.clone(),
                pinned: pinned.clone(),
                reference: record.reference,
            }),
        })?;
        let discovered = session.discover()?;
        if field(&discovered, "operations")?.array()?.len() != 1 {
            return Err("supplier_not_discoverable".into());
        }
        session.advertised = vec![TOOL.into()];
        session.catalog_sealed = true;
        let mut agent = Agent {
            dir: dir.into(),
            state: State::runtime(
                text.into(),
                field(&pinned.read, "scope")?.string()?.into(),
                Limits::default(),
            )?,
        };
        agent.state.counters.steps = 1;
        // Persist the actual task/attempt before the first receipt can exist.
        admitted(&agent.state)?;
        control.poll()?;
        session.dispatch(
            &mut agent,
            "supplier-read".into(),
            TOOL.into(),
            object([("id", string(id))]),
        )?;
        control.poll()?;
        if self.authority.snapshot()? != pinned {
            return Err("supplier_publication_changed".into());
        }
        let accepted = session
            .projections
            .last()
            .ok_or("supplier_projection_missing")?;
        Ok(SupplierReadResult {
            projection: accepted.value.clone(),
            receipt_ref: accepted.receipt.clone(),
            task_id: agent.state.task.clone(),
            attempt_id: agent.state.attempt.clone(),
        })
    }
}
fn bundle() -> Result<Json> {
    parse(include_bytes!("supplier_name_contract.json"))
}
