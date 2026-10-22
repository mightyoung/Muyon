//! Offline governance validation only. No persistence, transport, authority token,
//! model scheduler or gateway. An Eligible decision is advice, never permission
//! to execute. All inputs must come from the current trusted host stores.
use std::collections::{BTreeMap, BTreeSet};

pub type Result<T, E = Error> = std::result::Result<T, E>;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    InvalidConfig,
    UnsupportedMode,
    ManagementDenied,
    ScopeDenied,
    StaleIdentity,
    InvalidLedger,
    InvalidPlan,
    ChildLimit,
    ActiveLimit,
    CommandConflict,
    ReconcileOriginal,
    BudgetLimit,
    RoundLimit,
    Stopped,
    NotNextReady,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    HostOnly,
    Fixed,
    PerTask,
}
impl Mode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::HostOnly => "host_only",
            Self::Fixed => "fixed",
            Self::PerTask => "per_task",
        }
    }
}
impl TryFrom<&str> for Mode {
    type Error = Error;
    fn try_from(s: &str) -> Result<Self> {
        match s {
            "host_only" => Ok(Self::HostOnly),
            "fixed" => Ok(Self::Fixed),
            "per_task" => Ok(Self::PerTask),
            _ => Err(Error::UnsupportedMode),
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GroupConfig {
    pub schema_version: u32,
    pub revision: u64,
    pub owner_user_id: String,
    pub admin_user_ids: BTreeSet<String>,
    pub mode: Mode,
    pub coordinator_id: Option<String>,
}
impl GroupConfig {
    pub fn validate(&self) -> Result<()> {
        if self.schema_version != 1
            || self.revision == 0
            || !valid_id(&self.owner_user_id)
            || self.admin_user_ids.iter().any(|id| !valid_id(id))
            || self.coordinator_id.as_ref().is_some_and(|id| !valid_id(id))
            || (self.mode == Mode::HostOnly && self.coordinator_id.is_some())
            || (self.mode == Mode::Fixed && self.coordinator_id.is_none())
        {
            return Err(Error::InvalidConfig);
        }
        Ok(())
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Principal {
    Human(String),
    Member(String),
}
/// Scope IDs are exact, host-resolved identities, never path prefixes or wildcards.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Grant {
    pub scopes: BTreeSet<String>,
    pub permissions: BTreeSet<String>,
}
pub fn validate_narrowing(
    config: &GroupConfig,
    actor: &Principal,
    previous: &Grant,
    next: &Grant,
) -> Result<()> {
    let Principal::Human(id) = actor else {
        return Err(Error::ManagementDenied);
    };
    config.validate()?;
    if id != &config.owner_user_id && !config.admin_user_ids.contains(id) {
        return Err(Error::ManagementDenied);
    }
    if !valid_grant(previous) || !valid_grant(next) || !subset(next, previous) {
        return Err(Error::ScopeDenied);
    }
    Ok(())
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Member {
    pub id: String,
    pub grant: Grant,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Identity {
    pub workspace_id: String,
    pub owner_epoch: String,
    pub run_id: String,
    pub config_revision: u64,
    pub policy_revision: u64,
    pub plan_revision: u64,
    pub coordinator_epoch: u64,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChildState {
    Queued,
    Running,
    WaitingConfirmation,
    Unknown,
    Completed,
    Failed,
    Cancelled,
    Blocked,
}
impl TryFrom<&str> for ChildState {
    type Error = Error;
    fn try_from(s: &str) -> Result<Self> {
        match s {
            "queued" => Ok(Self::Queued),
            "running" => Ok(Self::Running),
            "waiting_confirmation" => Ok(Self::WaitingConfirmation),
            "unknown" => Ok(Self::Unknown),
            "completed" => Ok(Self::Completed),
            "failed" => Ok(Self::Failed),
            "cancelled" => Ok(Self::Cancelled),
            "blocked" => Ok(Self::Blocked),
            _ => Err(Error::InvalidLedger),
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LedgerChild {
    pub id: String,
    pub parent_id: String,
    pub depth: u32,
    pub state: ChildState,
}
/// Proposed, unadmitted root children. Not a second persistent queue.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PlannedChild {
    pub id: String,
    pub parent_id: String,
    pub depth: u32,
    pub member_id: String,
    pub grant: Grant,
    pub dependencies: BTreeSet<String>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Command {
    pub id: String,
    pub identity: Identity,
    pub child_id: String,
    /// Bound by the host to canonical payload, recipient, scope and grant revisions.
    pub payload_digest: String,
    pub reservation: u64,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CommandState {
    Prepared,
    Submitted,
    Unknown,
    Completed,
    Failed,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommandRecord {
    pub command: Command,
    pub request_id: String,
    pub state: CommandState,
}
/// Original root accounting, in one host-defined integer currency unit.
/// Never synthesize known_actual=0 when usage is missing: retain an unknown ID.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Budget {
    pub ceiling: u64,
    pub known_actual: u64,
    pub reserved: u64,
    pub unknown_request_ids: BTreeSet<String>,
}
/// Read-only projections of the existing root/child and original request owners.
/// Children include ALL historical children (even failed/cancelled); commands
/// include ALL attempts. Truncated event feeds are not valid lifetime sources.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HostSnapshot {
    pub identity: Identity,
    pub root_task_id: String,
    pub stopped: bool,
    pub children: Vec<LedgerChild>,
    pub commands: Vec<CommandRecord>,
    pub budget: Budget,
}
pub struct Limits {
    pub max_rounds: usize,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Decision {
    Eligible {
        child_id: String,
    },
    LookupOriginal {
        request_id: String,
        state: CommandState,
    },
}
/// authority_layers must be exactly user authorization, group policy, task policy,
/// and current tool policy; the fifth intersection is the member's capability.
/// Side effects still require the sole host gateway to recheck and atomically
/// persist intent/reserve/claim. This function offers no exactly-once guarantee.
pub fn validate_host_only(
    config: &GroupConfig,
    host: &HostSnapshot,
    plan: &[PlannedChild],
    members: &[Member],
    authority_layers: &[Grant],
    limits: &Limits,
    command: &Command,
) -> Result<Decision> {
    config.validate()?;
    if config.mode != Mode::HostOnly {
        return Err(Error::UnsupportedMode);
    }
    if !valid_identity(&host.identity)
        || command.identity != host.identity
        || config.revision != host.identity.config_revision
    {
        return Err(Error::StaleIdentity);
    }
    if !valid_id(&host.root_task_id)
        || !valid_id(&command.id)
        || !valid_id(&command.child_id)
        || command.payload_digest.trim().is_empty()
    {
        return Err(Error::InvalidLedger);
    }

    // Deduplicate against the original host request owner, never a local cache.
    let mut command_ids = BTreeSet::new();
    let mut request_ids = BTreeSet::new();
    for record in &host.commands {
        if !valid_id(&record.command.id)
            || !valid_id(&record.request_id)
            || !valid_identity(&record.command.identity)
            || record.command.identity.workspace_id != host.identity.workspace_id
            || record.command.identity.run_id != host.identity.run_id
            || !command_ids.insert(&record.command.id)
            || !request_ids.insert(&record.request_id)
        {
            return Err(Error::InvalidLedger);
        }
    }
    if let Some(original) = host.commands.iter().find(|r| r.command.id == command.id) {
        if original.command != *command {
            return Err(Error::CommandConflict);
        }
        return Ok(Decision::LookupOriginal {
            request_id: original.request_id.clone(),
            state: original.state,
        });
    }
    if host.stopped {
        return Err(Error::Stopped);
    }
    // Submitted is unresolved too: absence of an unknown marker is not a receipt.
    if !host.budget.unknown_request_ids.is_empty()
        || host
            .commands
            .iter()
            .any(|r| matches!(r.state, CommandState::Submitted | CommandState::Unknown))
    {
        return Err(Error::ReconcileOriginal);
    }
    if limits.max_rounds == 0 || host.commands.len() >= limits.max_rounds {
        return Err(Error::RoundLimit);
    }
    host.budget
        .known_actual
        .checked_add(host.budget.reserved)
        .and_then(|total| total.checked_add(command.reservation))
        .filter(|total| *total <= host.budget.ceiling)
        .ok_or(Error::BudgetLimit)?;

    let mut ledger = BTreeMap::new();
    for child in &host.children {
        if !valid_id(&child.id)
            || child.id == host.root_task_id
            || child.parent_id != host.root_task_id
            || child.depth != 1
            || ledger.insert(child.id.as_str(), child.state).is_some()
        {
            return Err(Error::InvalidLedger);
        }
    }
    // Existing RunLedger::children includes the root row; adapters must remove
    // that row, not subtract a separately supplied/resettable numeric count.
    if host
        .children
        .len()
        .checked_add(plan.len())
        .is_none_or(|n| n > 8)
    {
        return Err(Error::ChildLimit);
    }
    let active = host
        .children
        .iter()
        .filter(|c| {
            matches!(
                c.state,
                ChildState::Queued
                    | ChildState::Running
                    | ChildState::WaitingConfirmation
                    | ChildState::Unknown
            )
        })
        .count();
    if active >= 2 {
        return Err(Error::ActiveLimit);
    }
    // An incomplete accounting projection cannot clear an unresolved child.
    if host.children.iter().any(|c| c.state == ChildState::Unknown) {
        return Err(Error::ReconcileOriginal);
    }
    if authority_layers.len() != 4 || authority_layers.iter().any(|g| !valid_grant(g)) {
        return Err(Error::ScopeDenied);
    }
    let mut member_map = BTreeMap::new();
    for member in members {
        if !valid_id(&member.id)
            || !valid_grant(&member.grant)
            || member_map
                .insert(member.id.as_str(), &member.grant)
                .is_some()
        {
            return Err(Error::ScopeDenied);
        }
    }
    let mut pending = BTreeMap::new();
    for node in plan {
        if !valid_id(&node.id)
            || node.id == host.root_task_id
            || node.parent_id != host.root_task_id
            || node.depth != 1
            || ledger.contains_key(node.id.as_str())
            || pending.insert(node.id.as_str(), node).is_some()
        {
            return Err(Error::InvalidPlan);
        }
        let member_grant = member_map
            .get(node.member_id.as_str())
            .ok_or(Error::ScopeDenied)?;
        if !valid_grant(&node.grant)
            || node.grant.scopes.is_empty()
            || node.grant.permissions.is_empty()
            || !subset(&node.grant, member_grant)
            || authority_layers.iter().any(|g| !subset(&node.grant, g))
        {
            return Err(Error::ScopeDenied);
        }
    }
    if pending.is_empty() {
        return Err(Error::InvalidPlan);
    }
    for node in plan {
        if node
            .dependencies
            .iter()
            .any(|dep| !ledger.contains_key(dep.as_str()) && !pending.contains_key(dep.as_str()))
        {
            return Err(Error::InvalidPlan);
        }
    }
    // Validate the entire DAG, including blocked components, before selecting.
    let mut visited = BTreeSet::new();
    loop {
        let next = pending
            .iter()
            .find(|(id, n)| {
                !visited.contains(*id)
                    && n.dependencies
                        .iter()
                        .all(|d| ledger.contains_key(d.as_str()) || visited.contains(d.as_str()))
            })
            .map(|(id, _)| *id);
        match next {
            Some(id) => {
                visited.insert(id);
            }
            None => break,
        }
    }
    if visited.len() != pending.len() {
        return Err(Error::InvalidPlan);
    }
    let next = pending
        .values()
        .find(|n| {
            n.dependencies
                .iter()
                .all(|d| ledger.get(d.as_str()) == Some(&ChildState::Completed))
        })
        .ok_or(Error::NotNextReady)?;
    if next.id != command.child_id {
        return Err(Error::NotNextReady);
    }
    Ok(Decision::Eligible {
        child_id: next.id.clone(),
    })
}

fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
}
fn valid_grant(grant: &Grant) -> bool {
    grant
        .scopes
        .iter()
        .chain(&grant.permissions)
        .all(|id| valid_id(id))
}
fn subset(next: &Grant, previous: &Grant) -> bool {
    next.scopes.is_subset(&previous.scopes) && next.permissions.is_subset(&previous.permissions)
}
fn valid_identity(i: &Identity) -> bool {
    valid_id(&i.workspace_id)
        && valid_id(&i.owner_epoch)
        && valid_id(&i.run_id)
        && i.config_revision > 0
        && i.policy_revision > 0
        && i.plan_revision > 0
        && i.coordinator_epoch > 0
}
