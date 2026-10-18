//! Trusted host-only scope owner adapter. Never decoded from a UI/model request.
use crate::{AuthoritySnapshot, AuthoritySource};
use muyon_core_agent_lab::Result;
use std::{path::{Path, PathBuf}, rc::Rc};

pub struct HostSupplierSource {
    pub(crate) identity: String,
    pub(crate) namespace: String,
    pub(crate) root: PathBuf,
    pub(crate) db: PathBuf,
}
impl HostSupplierSource {
    pub fn new(identity: &str, namespace: &str, root: &Path, db: &Path) -> Result<Self> {
        Ok(Self { identity: identity.into(), namespace: namespace.into(), root: root.into(), db: db.into() })
    }
}
#[derive(Clone)]
pub struct SupplierSelection { pub key: String, pub revision: String }
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
    pub fn new(source: HostSupplierSource, current: Rc<dyn Fn() -> Result<SupplierScopeDecision>>) -> Result<Self> {
        Ok(Self { source, current })
    }
}
impl AuthoritySource for HostSupplierScopeBridge {
    fn snapshot(&self) -> Result<AuthoritySnapshot> { Err("supplier_scope_bridge_unavailable".into()) }
}
