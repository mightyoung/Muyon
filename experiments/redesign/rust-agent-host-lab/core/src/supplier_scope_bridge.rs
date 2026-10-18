//! Trusted host-only scope owner adapter. Never decoded from a UI/model request.
use crate::{AuthoritySnapshot, AuthoritySource};
use muyon_core_agent_lab::Result;
use muyon_plugin_contract_lab::{object, string, Json};
use std::{path::{Component, Path, PathBuf}, rc::Rc};

/// Stable identity and exact schema12 readonly location supplied by the actual
/// host store owner. This is an installation capability, never a request DTO.
#[derive(Clone)]
pub struct HostSupplierSource {
    pub(crate) identity: String,
    pub(crate) namespace: String,
    pub(crate) root: PathBuf,
    pub(crate) db: PathBuf,
}
fn bounded(value: &str, limit: usize) -> bool {
    !value.trim().is_empty() && value.len() <= limit && !value.chars().any(char::is_control)
}
fn absolute_normal(path: &Path) -> bool {
    path.is_absolute() && path.components().all(|part| matches!(part, Component::RootDir | Component::Normal(_)))
}
impl HostSupplierSource {
    pub fn new(identity: &str, namespace: &str, root: &Path, db: &Path) -> Result<Self> {
        if !bounded(identity, 128) || !bounded(namespace, 512) {
            return Err("supplier_scope_source_identity".into());
        }
        if !absolute_normal(root) || !absolute_normal(db) || root.parent().is_none()
            || db == root || !db.starts_with(root)
        {
            return Err("supplier_scope_source_namespace".into());
        }
        Ok(Self { identity: identity.into(), namespace: namespace.into(), root: root.into(), db: db.into() })
    }
}
#[derive(Clone)]
pub struct SupplierSelection { pub key: String, pub revision: String }
/// Current proof from the host ScopeResolver and read policy owner. Boolean
/// permission results are explicit read proofs; model, module, write and outbound
/// grants are not accepted as substitutes. The callback must resolve current
/// canonical selections and stamp the binding, source and rule owners each time.
#[derive(Clone)]
pub struct SupplierScopeDecision {
    pub source_identity: String,
    pub namespace: String,
    pub allowed: bool,
    pub available: bool,
    pub scope_allowed: bool,
    pub bindings: Vec<String>,
    pub revision: String,
    pub binding_revision: String,
    pub source_revision: String,
    pub rule_revision: String,
    pub scope: String,
    pub selected: Vec<SupplierSelection>,
}
pub struct HostSupplierScopeBridge {
    pub(crate) source: HostSupplierSource,
    current: Rc<dyn Fn() -> Result<SupplierScopeDecision>>,
}
impl HostSupplierScopeBridge {
    /// The callback must sample the live owner, not a cached authority snapshot.
    /// An Arc-backed Service owner may be captured here when each worker builds
    /// its own Rc adapter. Nothing in this adapter accesses credentials or models.
    pub fn new(source: HostSupplierSource, current: Rc<dyn Fn() -> Result<SupplierScopeDecision>>) -> Result<Self> {
        let bridge = Self { source, current };
        bridge.snapshot()?;
        Ok(bridge)
    }
}
impl AuthoritySource for HostSupplierScopeBridge {
    fn snapshot(&self) -> Result<AuthoritySnapshot> {
        if !self.source.db.starts_with(&self.source.root) {
            return Err("supplier_scope_source_namespace".into());
        }
        let decision = (self.current)()?;
        if decision.source_identity != self.source.identity || decision.namespace != self.source.namespace {
            return Err("supplier_scope_source_changed".into());
        }
        if !decision.allowed || !decision.available || !decision.scope_allowed {
            return Err("supplier_scope_denied".into());
        }
        if decision.bindings.len() > 64
            || !decision.bindings.iter().all(|binding| bounded(binding, 128))
            || !decision.bindings.iter().any(|binding| binding == "host-supplier-name-read")
        {
            return Err("supplier_scope_binding_denied".into());
        }
        for stamp in [&decision.revision, &decision.binding_revision, &decision.source_revision, &decision.rule_revision, &decision.scope] {
            if !bounded(stamp, 1024) { return Err("supplier_scope_proof_unknown".into()); }
        }
        if decision.selected.len() != 1 || decision.selected.iter().any(|selected| !bounded(&selected.key, 128) || !bounded(&selected.revision, 128)) {
            return Err("supplier_scope_selection_unknown".into());
        }
        // Stable namespace/owner evidence survives adapter reconstruction. The
        // SQLite wrapper adds its connection's data_version and physical lineage
        // checks, then repeats this callback before physical read and disclosure.
        let source_revision = Json::Array(vec![string(&self.source.identity), string(&self.source.namespace), string(&decision.source_revision)]).encode();
        let selected = &decision.selected[0];
        Ok(AuthoritySnapshot {
            read: object([
                ("allowed", Json::Bool(true)), ("available", Json::Bool(true)), ("scope_allowed", Json::Bool(true)),
                ("bindings", Json::Array(decision.bindings.iter().map(string).collect())),
                ("revision", string(&decision.revision)), ("binding_revision", string(&decision.binding_revision)),
                ("source_revision", string(source_revision)), ("rule_revision", string(&decision.rule_revision)),
                ("scope", string(&decision.scope)),
                ("refs", Json::Array(vec![object([
                    ("module_id", string("inquiry")), ("type", string("supplier")),
                    ("key", string(&selected.key)), ("revision", string(&selected.revision)),
                    ("schema_version", Json::Number("1".into())),
                ])])),
            ]),
            model_allowed: false,
            profile: "local-read-only".into(),
        })
    }
}
