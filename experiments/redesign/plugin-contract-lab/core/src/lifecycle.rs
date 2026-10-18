//! Optional trusted Rust lifecycle for the existing Catalog. Leases are not
//! serializable plugin authority. The host owns actual handler cancellation,
//! quiescence, durable receipts and resources; no Drop path claims to drain.
use crate::schema::{array, get, references, text};
use crate::{object, string, Catalog, Json, Result};
use std::collections::BTreeSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

/// Host-issued bundle identity. Fields are private; clones refer to one epoch.
#[derive(Clone, Debug)]
pub struct OwnerLease {
    identity: Arc<()>,
    module: String,
    epoch: u64,
    generation: u64,
}
impl OwnerLease {
    pub fn epoch(&self) -> u64 {
        self.epoch
    }
    /// Publication generation, not a schema or database version.
    pub fn generation(&self) -> u64 {
        self.generation
    }
}

/// One dispatched host work item. Dropping it deliberately leaves drain blocked.
#[derive(Clone, Debug)]
pub struct WorkLease {
    identity: Arc<()>,
    id: u64,
    ticket: String,
    cancel: Arc<AtomicBool>,
}
impl WorkLease {
    pub fn ticket(&self) -> &str {
        &self.ticket
    }
    /// Cooperative request only; true never means the handler has stopped.
    pub fn cancel_requested(&self) -> bool {
        self.cancel.load(Ordering::Acquire)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DrainState {
    Active,
    /// Admission fenced. Zero work still requires explicit resource release.
    Draining {
        in_flight: usize,
    },
    Released,
}

pub(super) struct OwnerRecord {
    pub epoch: u64,
    pub managed: bool,
    pub stopping: bool,
    dependencies: BTreeSet<String>,
    data: BTreeSet<String>,
    operations: BTreeSet<String>,
    bindings: BTreeSet<String>,
    relations: usize,
    views: usize,
}
pub(super) struct WorkRecord {
    module: String,
    epoch: u64,
    ticket: String,
    cancel: Arc<AtomicBool>,
}

impl OwnerRecord {
    /// Build removal/dependency metadata before the existing publication point.
    pub(super) fn new(
        epoch: u64,
        bundle: &Json,
        data: BTreeSet<String>,
        operations: BTreeSet<String>,
        bindings: BTreeSet<String>,
    ) -> Result<Self> {
        let module = text(bundle, "module_id")?;
        let mut targets = Vec::new();
        for d in array(bundle, "data")? {
            targets.extend(references(get(d, "schema")?)?);
        }
        for r in array(bundle, "relations")? {
            targets.push(text(r, "from")?);
            targets.push(text(r, "to")?);
        }
        for key in ["operations", "views"] {
            for row in array(bundle, key)? {
                for target in array(row, "data_refs")? {
                    targets.push(target.string()?.to_owned());
                }
            }
        }
        let dependencies = targets
            .into_iter()
            .filter_map(|t| t.split_once('/').map(|(m, _)| m.to_owned()))
            .filter(|m| m != &module)
            .collect();
        Ok(Self {
            epoch,
            managed: false,
            stopping: false,
            dependencies,
            data,
            operations,
            bindings,
            relations: array(bundle, "relations")?.len(),
            views: array(bundle, "views")?.len(),
        })
    }
}

impl Catalog {
    pub(super) fn request_work_cancel(&self, ticket: Option<&str>) {
        for work in self
            .work
            .values()
            .filter(|w| ticket.is_none_or(|t| w.ticket == t))
        {
            work.cancel.store(true, Ordering::Release);
        }
    }
    pub(super) fn module_active(&self, module: &str) -> bool {
        self.owners.get(module).is_some_and(|owner| !owner.stopping)
    }
    fn lease_record(&self, lease: &OwnerLease) -> Result<Option<&OwnerRecord>> {
        if !Arc::ptr_eq(&self.identity, &lease.identity) {
            return Err("foreign_owner".into());
        }
        Ok(self
            .owners
            .get(&lease.module)
            .filter(|owner| owner.epoch == lease.epoch))
    }
    fn in_flight(&self, lease: &OwnerLease) -> usize {
        self.work
            .values()
            .filter(|w| w.module == lease.module && w.epoch == lease.epoch)
            .count()
    }
    fn has_dependents(&self, module: &str) -> bool {
        self.owners
            .values()
            .any(|owner| owner.dependencies.contains(module))
    }

    /// Same closed validation and atomic publication as wire register, with a
    /// host-only lease. Legacy wire enrollments retain their existing API.
    pub fn register_owned(
        &mut self,
        bundle: Json,
        host_bindings: Vec<String>,
        host_data_admissions: Vec<String>,
    ) -> Result<OwnerLease> {
        crate::schema::bounded(&bundle)?;
        let module = text(&bundle, "module_id")?;
        self.run(&object([
            ("protocol_version", crate::number(1)),
            ("command", string("register")),
            ("bundle", bundle),
            (
                "host_bindings",
                Json::Array(host_bindings.into_iter().map(string).collect()),
            ),
            (
                "host_data_admissions",
                Json::Array(host_data_admissions.into_iter().map(string).collect()),
            ),
        ]))?;
        let owner = self.owners.get_mut(&module).ok_or("owner_missing")?;
        owner.managed = true;
        Ok(OwnerLease {
            identity: self.identity.clone(),
            module,
            epoch: owner.epoch,
            generation: self.generation,
        })
    }

    pub fn owner_state(&self, lease: &OwnerLease) -> Result<DrainState> {
        Ok(match self.lease_record(lease)? {
            None => DrainState::Released,
            Some(owner) if owner.stopping => DrainState::Draining {
                in_flight: self.in_flight(lease),
            },
            Some(_) => DrainState::Active,
        })
    }

    /// Fence first; host then requests cancellation and polls state without
    /// blocking a Catalog lock. Release consumers before their dependencies.
    pub fn stop_owner(&mut self, lease: &OwnerLease) -> Result<DrainState> {
        if self.owner_state(lease)? != DrainState::Active {
            return self.owner_state(lease);
        }
        if self.has_dependents(&lease.module) {
            return Err("owner_has_dependents".into());
        }
        let next = self
            .generation
            .checked_add(1)
            .ok_or("generation_exhausted")?;
        self.owners
            .get_mut(&lease.module)
            .ok_or("owner_missing")?
            .stopping = true;
        for work in self
            .work
            .values()
            .filter(|w| w.module == lease.module && w.epoch == lease.epoch)
        {
            work.cancel.store(true, Ordering::Release);
        }
        self.tickets
            .retain(|_, t| t.operation.module != lease.module);
        self.generation = next;
        self.owner_state(lease)
    }

    /// Call after stop and durable settlement. `close` is synchronous host code;
    /// failure/panic retains metadata and fencing. No automatic retry is made.
    /// An old disposer is a no-op even after a same-name replacement enrolls.
    pub fn release_owner(
        &mut self,
        lease: &OwnerLease,
        close: impl FnOnce() -> Result<()>,
    ) -> Result<DrainState> {
        match self.owner_state(lease)? {
            DrainState::Released => return Ok(DrainState::Released),
            DrainState::Active => return Err("owner_active".into()),
            DrainState::Draining { in_flight } if in_flight != 0 => {
                return Err("owner_draining".into())
            }
            _ => {}
        }
        if self.has_dependents(&lease.module) {
            return Err("owner_has_dependents".into());
        }
        let next = self
            .generation
            .checked_add(1)
            .ok_or("generation_exhausted")?;
        close()?;
        let owner = self.owners.remove(&lease.module).ok_or("owner_missing")?;
        self.data.retain(|id, _| !owner.data.contains(id));
        self.operations
            .retain(|id, _| !owner.operations.contains(id));
        self.bindings.retain(|id| !owner.bindings.contains(id));
        self.relation_count -= owner.relations;
        self.view_count -= owner.views;
        self.modules.remove(&lease.module);
        self.generation = next;
        Ok(DrainState::Released)
    }

    /// Atomically dispatch through existing authority/generation checks and
    /// retain a work lease before handing the dispatch back to the host.
    pub fn dispatch_owned(
        &mut self,
        lease: &OwnerLease,
        ticket: &str,
        authority: Json,
    ) -> Result<(Json, WorkLease)> {
        if self.owner_state(lease)? != DrainState::Active {
            return Err("owner_stopping".into());
        }
        if self.closed {
            return Err("closed".into());
        }
        let t = self.tickets.get(ticket).ok_or("unknown_ticket")?;
        if t.operation.module != lease.module {
            return Err("work_owner".into());
        }
        if self.work.len() >= 128 {
            return Err("owner_work_limit".into());
        }
        let next = self
            .work_serial
            .checked_add(1)
            .ok_or("work_epoch_exhausted")?;
        let request = object([
            ("command", string("invoke")),
            ("ticket", string(ticket)),
            ("authority", authority),
        ]);
        crate::schema::bounded(&request)?;
        let reply = self.invoke_inner(&request, true)?;
        self.work_serial = next;
        let cancel = Arc::new(AtomicBool::new(false));
        self.work.insert(
            next,
            WorkRecord {
                module: lease.module.clone(),
                epoch: lease.epoch,
                ticket: ticket.into(),
                cancel: cancel.clone(),
            },
        );
        Ok((
            reply,
            WorkLease {
                identity: self.identity.clone(),
                id: next,
                ticket: ticket.into(),
                cancel,
            },
        ))
    }

    /// Trusted host calls ONLY once its handler is quiescent. The callback must
    /// persist final/unknown evidence under the original receipt identity.
    /// Failure retains the work lease. This API neither creates nor rewrites a
    /// receipt and cannot observe host quiescence or fsync itself. Settle after
    /// optional accept_result; settlement consumes any remaining transient ticket.
    pub fn settle_work(
        &mut self,
        lease: &WorkLease,
        persist: impl FnOnce() -> Result<()>,
    ) -> Result<()> {
        if !Arc::ptr_eq(&self.identity, &lease.identity) {
            return Err("foreign_work".into());
        }
        if !self.work.contains_key(&lease.id) {
            return Ok(());
        }
        persist()?;
        self.work.remove(&lease.id);
        self.tickets.remove(&lease.ticket);
        Ok(())
    }
}
