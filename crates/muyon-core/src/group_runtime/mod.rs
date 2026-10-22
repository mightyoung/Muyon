//! Offline coordination state. All snapshots and policy inputs must be trusted host
//! projections. Advice is never an execution permit; the host must recheck and
//! persist intent/reservation/claim atomically through its existing sole gateway.
//! No network, accounting writes or second child queue live here. Restore from the
//! host's durable epoch/handoff count; never reset those values on restart.
use crate::group_governance as g;
use std::collections::{BTreeMap, BTreeSet};
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RuntimeError {
    Governance(g::Error),
    InvalidConfig,
    StaleIdentity,
    InvalidActor,
    ReconcileOriginal,
    Stopped,
    Deadline,
    UnsafeCheckpoint,
    HandoffLimit,
    EpochExhausted,
    InvalidResult,
    EventConflict,
}
impl From<g::Error> for RuntimeError {
    fn from(e: g::Error) -> Self {
        Self::Governance(e)
    }
}
type Result<T> = std::result::Result<T, RuntimeError>;
#[derive(Clone, Debug)]
pub struct RuntimeLimits {
    pub max_rounds: usize,
    pub max_handoffs: usize,
    pub deadline_tick: u64,
}
/// Named host policies, not anonymous model-supplied grants. Host still owns
/// provenance, current policy revisions, provider/data approval and cost proof.
#[derive(Clone, Debug)]
pub struct Policies {
    pub user: g::Grant,
    pub group: g::Grant,
    pub task: g::Grant,
    pub tool: g::Grant,
}
impl Policies {
    fn layers(&self) -> [g::Grant; 4] {
        [
            self.user.clone(),
            self.group.clone(),
            self.task.clone(),
            self.tool.clone(),
        ]
    }
}
#[derive(Clone, Debug)]
pub enum Origin {
    Host,
    Coordinator { id: String, epoch: u64 },
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MaterialRef {
    pub scope_id: String,
    pub source_id: String,
    pub version: String,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Handoff {
    pub identity: g::Identity,
    pub from: String,
    pub to: String,
    pub grant: g::Grant,
    pub materials: Vec<MaterialRef>,
    pub completed_child_ids: BTreeSet<String>,
    pub budget: g::Budget,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Outcome {
    Completed,
    Failed,
    Unknown,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Stance {
    Supports,
    Contradicts,
    Unknown,
}
/// primary_origin is a host-resolved provenance ID, shared by copies/retellings.
/// Evidence supports a claim; neither counts nor model agreement certify truth.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Evidence {
    pub claim_id: String,
    pub source_ref: String,
    pub source_version: String,
    pub primary_origin: String,
    pub observed_at: u64,
    pub stance: Stance,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Observation {
    pub event_id: String,
    pub sequence: u64,
    pub identity: g::Identity,
    pub child_id: String,
    pub member_id: String,
    pub request_id: String,
    pub outcome: Outcome,
    pub artifact_refs: BTreeSet<String>,
    pub evidence: Vec<Evidence>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Collection {
    Collected,
    Duplicate,
    LateEvidence,
}
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ClaimSummary {
    pub evidence: BTreeSet<Evidence>,
    pub independent_origins: BTreeSet<String>,
    pub disputed: bool,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SchedulingState {
    Ready { available_slots: usize },
    Stopped,
    Deadline,
    Reconciling { request_ids: BTreeSet<String> },
    RoundLimit,
    BudgetLimit,
}
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Summary {
    pub results: BTreeMap<String, Observation>,
    pub completed: BTreeSet<String>,
    pub failed: BTreeSet<String>,
    pub unknown: BTreeSet<String>,
    pub claims: BTreeMap<String, ClaimSummary>,
}
#[derive(Clone, Debug)]
pub struct Runtime {
    config: g::GroupConfig,
    identity: g::Identity,
    root: String,
    members: Vec<g::Member>,
    leader: Option<String>,
    limits: RuntimeLimits,
    handoffs: usize,
    stopped: bool,
    observations: BTreeMap<String, Observation>,
    events: BTreeMap<String, Observation>,
    late: Vec<Observation>,
}
impl Runtime {
    /// `handoffs` is the durable lifetime count, never a session-local reset.
    /// Restored members must reflect current host grants (including narrowing).
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        config: g::GroupConfig,
        host: &g::HostSnapshot,
        members: Vec<g::Member>,
        task_leader: Option<&str>,
        limits: RuntimeLimits,
        now: u64,
        handoffs: usize,
    ) -> Result<Self> {
        config.validate()?;
        if !valid_identity(&host.identity)
            || host.identity.config_revision != config.revision
            || !id(&host.root_task_id)
            || limits.max_rounds == 0
            || limits.deadline_tick <= now
            || handoffs > limits.max_handoffs
        {
            return Err(RuntimeError::InvalidConfig);
        }
        let mut ids = BTreeSet::new();
        for member in &members {
            if !id(&member.id) || !valid_grant(&member.grant) || !ids.insert(&member.id) {
                return Err(RuntimeError::InvalidConfig);
            }
        }
        let leader = match config.mode {
            g::Mode::HostOnly if task_leader.is_none() => None,
            g::Mode::Fixed
                if task_leader.is_none() || task_leader == config.coordinator_id.as_deref() =>
            {
                config.coordinator_id.clone()
            }
            g::Mode::PerTask if config.coordinator_id.is_none() => task_leader.map(str::to_owned),
            _ => return Err(RuntimeError::InvalidConfig),
        };
        if (config.mode != g::Mode::HostOnly && leader.is_none())
            || leader.as_ref().is_some_and(|x| !ids.contains(x))
        {
            return Err(RuntimeError::InvalidConfig);
        }
        let runtime = Self {
            config,
            identity: host.identity.clone(),
            root: host.root_task_id.clone(),
            members,
            leader,
            limits,
            handoffs,
            stopped: host.stopped,
            observations: BTreeMap::new(),
            events: BTreeMap::new(),
            late: Vec::new(),
        };
        runtime.fence(host)?;
        Ok(runtime)
    }
    /// Deterministic UI/host projection, never an authorization or cost receipt.
    pub fn status(&self, host: &g::HostSnapshot, now: u64) -> Result<SchedulingState> {
        self.fence(host)?;
        if self.stopped || host.stopped {
            return Ok(SchedulingState::Stopped);
        }
        if now >= self.limits.deadline_tick {
            return Ok(SchedulingState::Deadline);
        }
        let mut requests = host.budget.unknown_request_ids.clone();
        for record in &host.commands {
            if matches!(
                record.state,
                g::CommandState::Prepared | g::CommandState::Submitted | g::CommandState::Unknown
            ) {
                requests.insert(record.request_id.clone());
            }
        }
        if !requests.is_empty()
            || host
                .children
                .iter()
                .any(|c| c.state == g::ChildState::Unknown)
        {
            return Ok(SchedulingState::Reconciling {
                request_ids: requests,
            });
        }
        if host.commands.len() >= self.limits.max_rounds {
            return Ok(SchedulingState::RoundLimit);
        }
        if host
            .budget
            .known_actual
            .checked_add(host.budget.reserved)
            .is_none_or(|total| total > host.budget.ceiling)
        {
            return Ok(SchedulingState::BudgetLimit);
        }
        let active = host
            .children
            .iter()
            .filter(|c| {
                matches!(
                    c.state,
                    g::ChildState::Queued
                        | g::ChildState::Running
                        | g::ChildState::WaitingConfirmation
                        | g::ChildState::Unknown
                )
            })
            .count();
        Ok(SchedulingState::Ready {
            available_slots: 2usize.saturating_sub(active),
        })
    }
    pub fn leader(&self) -> Option<&str> {
        self.leader.as_deref()
    }
    pub fn epoch(&self) -> u64 {
        self.identity.coordinator_epoch
    }
    /// Monotonic for this projection. Host must persist stop before acknowledging.
    pub fn stop(&mut self) {
        self.stopped = true;
    }
    fn fence(&self, host: &g::HostSnapshot) -> Result<()> {
        if host.identity != self.identity || host.root_task_id != self.root {
            return Err(RuntimeError::StaleIdentity);
        }
        let mut children = BTreeSet::new();
        for child in &host.children {
            if !id(&child.id)
                || child.id == self.root
                || child.parent_id != self.root
                || child.depth != 1
                || !children.insert(&child.id)
            {
                return Err(g::Error::InvalidLedger.into());
            }
        }
        let mut commands = BTreeSet::new();
        let mut requests = BTreeSet::new();
        for r in &host.commands {
            if !id(&r.command.id)
                || !id(&r.request_id)
                || !id(&r.command.child_id)
                || r.command.payload_digest.trim().is_empty()
                || !valid_identity(&r.command.identity)
                || r.command.identity.workspace_id != self.identity.workspace_id
                || r.command.identity.run_id != self.identity.run_id
                || r.command.identity.coordinator_epoch > self.epoch()
                || !commands.insert(&r.command.id)
                || !requests.insert(&r.request_id)
            {
                return Err(g::Error::InvalidLedger.into());
            }
        }
        if host.children.len() > 8 || host.budget.unknown_request_ids.iter().any(|x| !id(x)) {
            return Err(g::Error::InvalidLedger.into());
        }
        Ok(())
    }
    /// Query-only across coordination epochs. Never routes back to dispatch.
    pub fn lookup_original(
        &self,
        host: &g::HostSnapshot,
        command: &g::Command,
    ) -> Result<Option<g::Decision>> {
        self.fence(host)?;
        if command.identity.workspace_id != self.identity.workspace_id
            || command.identity.run_id != self.identity.run_id
        {
            return Err(RuntimeError::StaleIdentity);
        }
        match host.commands.iter().find(|r| r.command.id == command.id) {
            Some(r) if r.command == *command => Ok(Some(g::Decision::LookupOriginal {
                request_id: r.request_id.clone(),
                state: r.state,
            })),
            Some(_) => Err(g::Error::CommandConflict.into()),
            None => Ok(None),
        }
    }
    fn open(&self, host: &g::HostSnapshot, now: u64) -> Result<()> {
        self.fence(host)?;
        if self.stopped || host.stopped {
            return Err(RuntimeError::Stopped);
        }
        if now >= self.limits.deadline_tick {
            return Err(RuntimeError::Deadline);
        }
        if !host.budget.unknown_request_ids.is_empty()
            || host.commands.iter().any(|r| {
                matches!(
                    r.state,
                    g::CommandState::Prepared
                        | g::CommandState::Submitted
                        | g::CommandState::Unknown
                )
            })
            || host
                .children
                .iter()
                .any(|c| c.state == g::ChildState::Unknown)
        {
            return Err(RuntimeError::ReconcileOriginal);
        }
        Ok(())
    }
    /// One next intent, not a dispatched child. To fill the second parallel slot,
    /// host first commits its first intent to its own ledger and supplies a new
    /// consistent snapshot. This module never invents a running/completed child.
    pub fn advise(
        &self,
        host: &g::HostSnapshot,
        plan: &[g::PlannedChild],
        policies: &Policies,
        command: &g::Command,
        origin: Origin,
        now: u64,
    ) -> Result<g::Decision> {
        if let Some(original) = self.lookup_original(host, command)? {
            return Ok(original);
        }
        self.open(host, now)?;
        if command.identity != self.identity {
            return Err(RuntimeError::StaleIdentity);
        }
        match origin {
            Origin::Host => {}
            Origin::Coordinator { id, epoch }
                if self.leader.as_ref() == Some(&id) && epoch == self.epoch() => {}
            _ => return Err(RuntimeError::InvalidActor),
        }
        // Reuse hard host gates after checking the actual captured coordination
        // mode above; the old public validator remains host_only and unchanged.
        let mut validation = self.config.clone();
        validation.mode = g::Mode::HostOnly;
        validation.coordinator_id = None;
        Ok(g::validate_host_only(
            &validation,
            host,
            plan,
            &self.members,
            &policies.layers(),
            &g::Limits {
                max_rounds: self.limits.max_rounds,
            },
            command,
        )?)
    }
    /// Produces a candidate epoch and minimum reference package. The host must
    /// CAS-persist epoch + lifetime count + narrowed member grants in its existing
    /// transaction before publishing the candidate or accepting another intent.
    /// Calling this method alone does not acquire a live host lease.
    pub fn handoff(
        &mut self,
        host: &g::HostSnapshot,
        actor: &g::Principal,
        to: &str,
        policies: &Policies,
        materials: &[MaterialRef],
        now: u64,
    ) -> Result<Handoff> {
        self.open(host, now)?;
        if self.config.mode != g::Mode::PerTask {
            return Err(RuntimeError::InvalidConfig);
        }
        let g::Principal::Human(actor) = actor else {
            return Err(RuntimeError::InvalidActor);
        };
        if actor != &self.config.owner_user_id && !self.config.admin_user_ids.contains(actor) {
            return Err(RuntimeError::InvalidActor);
        }
        if self.handoffs >= self.limits.max_handoffs {
            return Err(RuntimeError::HandoffLimit);
        }
        if host.children.iter().any(|c| {
            matches!(
                c.state,
                g::ChildState::Queued
                    | g::ChildState::Running
                    | g::ChildState::WaitingConfirmation
                    | g::ChildState::Unknown
            )
        }) {
            return Err(RuntimeError::UnsafeCheckpoint);
        }
        let from = self.leader.as_ref().ok_or(RuntimeError::InvalidConfig)?;
        if from == to {
            return Err(RuntimeError::InvalidConfig);
        }
        let old = self
            .members
            .iter()
            .find(|m| &m.id == from)
            .ok_or(RuntimeError::InvalidConfig)?;
        let next = self
            .members
            .iter()
            .find(|m| m.id == to)
            .ok_or(RuntimeError::InvalidConfig)?;
        let mut grant = next.grant.clone();
        for layer in policies.layers().iter().chain(std::iter::once(&old.grant)) {
            if !valid_grant(layer) {
                return Err(g::Error::ScopeDenied.into());
            }
            grant.scopes = grant.scopes.intersection(&layer.scopes).cloned().collect();
            grant.permissions = grant
                .permissions
                .intersection(&layer.permissions)
                .cloned()
                .collect();
        }
        if grant.scopes.is_empty() || grant.permissions.is_empty() {
            return Err(g::Error::ScopeDenied.into());
        }
        let mut seen = BTreeSet::new();
        for material in materials {
            if !grant.scopes.contains(&material.scope_id)
                || !id(&material.source_id)
                || !id(&material.version)
                || !seen.insert((&material.scope_id, &material.source_id, &material.version))
            {
                return Err(g::Error::ScopeDenied.into());
            }
        }
        let epoch = self
            .epoch()
            .checked_add(1)
            .ok_or(RuntimeError::EpochExhausted)?;
        let mut identity = self.identity.clone();
        identity.coordinator_epoch = epoch;
        let package = Handoff {
            identity: identity.clone(),
            from: from.clone(),
            to: to.into(),
            grant: grant.clone(),
            materials: materials.to_vec(),
            completed_child_ids: host
                .children
                .iter()
                .filter(|c| c.state == g::ChildState::Completed)
                .map(|c| c.id.clone())
                .collect(),
            budget: host.budget.clone(),
        };
        self.identity = identity;
        self.leader = Some(to.into());
        self.handoffs += 1;
        self.members
            .iter_mut()
            .find(|m| m.id == to)
            .expect("validated member")
            .grant = grant;
        // Older records remain available as late evidence, not current results.
        self.late
            .extend(std::mem::take(&mut self.observations).into_values());
        Ok(package)
    }
    /// Host-attributed observations only. Text saying "complete" is insufficient:
    /// both the original request receipt and host child state must agree, and a
    /// completed result must reference an actual host-resolved artifact.
    pub fn collect(
        &mut self,
        host: &g::HostSnapshot,
        plan: &[g::PlannedChild],
        observation: Observation,
    ) -> Result<Collection> {
        self.fence(host)?;
        let o = &observation;
        if !id(&o.event_id)
            || o.sequence == 0
            || !id(&o.member_id)
            || !valid_identity(&o.identity)
            || o.identity.coordinator_epoch > self.epoch()
            || o.artifact_refs.iter().any(|x| !id(x))
            || o.evidence.iter().any(|e| {
                !id(&e.claim_id)
                    || !id(&e.source_ref)
                    || !id(&e.source_version)
                    || !id(&e.primary_origin)
            })
        {
            return Err(RuntimeError::InvalidResult);
        }
        let nodes: Vec<_> = plan.iter().filter(|n| n.id == o.child_id).collect();
        if nodes.len() != 1 {
            return Err(RuntimeError::InvalidResult);
        }
        let n = nodes[0];
        if n.parent_id != self.root
            || n.depth != 1
            || n.member_id != o.member_id
            || !self.members.iter().any(|m| m.id == o.member_id)
        {
            return Err(RuntimeError::InvalidResult);
        }
        let record = host
            .commands
            .iter()
            .find(|r| r.request_id == o.request_id)
            .ok_or(RuntimeError::InvalidResult)?;
        if record.command.child_id != o.child_id || record.command.identity != o.identity {
            return Err(RuntimeError::InvalidResult);
        }
        let child = host
            .children
            .iter()
            .find(|c| c.id == o.child_id)
            .ok_or(RuntimeError::InvalidResult)?;
        let states = match o.outcome {
            Outcome::Completed => (g::ChildState::Completed, g::CommandState::Completed),
            Outcome::Failed => (g::ChildState::Failed, g::CommandState::Failed),
            Outcome::Unknown => (g::ChildState::Unknown, g::CommandState::Unknown),
        };
        if (child.state, record.state) != states
            || (o.outcome == Outcome::Completed && o.artifact_refs.is_empty())
        {
            return Err(RuntimeError::InvalidResult);
        }
        if let Some(original) = self.events.get(&o.event_id) {
            return if original == o {
                Ok(Collection::Duplicate)
            } else {
                Err(RuntimeError::EventConflict)
            };
        }
        if o.identity.coordinator_epoch < self.epoch() {
            self.events.insert(o.event_id.clone(), observation.clone());
            self.late.push(observation);
            return Ok(Collection::LateEvidence);
        }
        // Equal epoch still requires all config/policy/host/plan identity fields.
        if o.identity != self.identity {
            return Err(RuntimeError::StaleIdentity);
        }
        if let Some(previous) = self.observations.get(&o.child_id) {
            if o.sequence <= previous.sequence
                || previous.outcome != Outcome::Unknown
                || o.request_id != previous.request_id
                || o.member_id != previous.member_id
            {
                return Err(RuntimeError::EventConflict);
            }
        }
        self.events.insert(o.event_id.clone(), observation.clone());
        self.observations.insert(o.child_id.clone(), observation);
        Ok(Collection::Collected)
    }
    pub fn late_evidence(&self) -> &[Observation] {
        &self.late
    }
    pub fn summary(&self) -> Summary {
        let mut summary = Summary::default();
        for o in self.observations.values() {
            summary.results.insert(o.child_id.clone(), o.clone());
            match o.outcome {
                Outcome::Completed => {
                    summary.completed.insert(o.child_id.clone());
                }
                Outcome::Failed => {
                    summary.failed.insert(o.child_id.clone());
                }
                Outcome::Unknown => {
                    summary.unknown.insert(o.child_id.clone());
                }
            }
        }
        // A later original receipt changes state, not previously observed facts.
        for o in self
            .events
            .values()
            .filter(|o| o.identity.coordinator_epoch == self.epoch())
        {
            for e in &o.evidence {
                let claim = summary.claims.entry(e.claim_id.clone()).or_default();
                claim.evidence.insert(e.clone());
                claim.independent_origins.insert(e.primary_origin.clone());
            }
        }
        for claim in summary.claims.values_mut() {
            claim.disputed = claim.evidence.iter().any(|e| e.stance == Stance::Supports)
                && claim
                    .evidence
                    .iter()
                    .any(|e| e.stance == Stance::Contradicts);
        }
        summary
    }
}
fn id(x: &str) -> bool {
    !x.is_empty()
        && x.len() <= 128
        && x.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
}
fn valid_grant(g: &g::Grant) -> bool {
    g.scopes.iter().chain(&g.permissions).all(|x| id(x))
}
fn valid_identity(i: &g::Identity) -> bool {
    id(&i.workspace_id)
        && id(&i.owner_epoch)
        && id(&i.run_id)
        && i.config_revision > 0
        && i.policy_revision > 0
        && i.plan_revision > 0
        && i.coordinator_epoch > 0
}
