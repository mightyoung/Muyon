//! DOC-06/08 transaction contracts and trusted host integration.
//!
//! The fact/state types below remain pure in-memory validation: no I/O, permission
//! issuance or real CAS. They are NOT wire grants or engine execution receipts.
//! Never populate them from model output, document content or untrusted JSON.
//! `gateway` separately implements durable, live-authorized byte-identical COPY
//! through the existing core store. `engine_protocol` maps held requests only;
//! no real Office editing engine or edited-candidate publication is enabled.

pub mod edited_candidates;
pub mod engine_protocol;
pub mod fingerprint;
pub mod gateway;
pub mod text_protocol;

pub use crate::contract::AuthorityBinding as Authority;
use crate::contract::Revision;
use crate::documents::{CapabilityMatrix, CapabilityStatus, DocumentOperation, DocumentRef};

// Same restricted opaque-ID syntax as documents::identity (its helper is
// crate-private to the owning library). This checks metadata syntax only.
fn opaque_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Binding {
    pub document: DocumentRef,
    /// Host-computed digest of the canonical typed patch, including targets and
    /// expected values. This module does not hash/interpret an engine payload.
    pub patch_digest: [u8; 32],
    pub intent_id: String,
    pub rollback_target: Option<Revision>,
}
impl Binding {
    fn check(&self) -> Result<(), Error> {
        // DocumentRef already enforces the shared document/scope identity contract.
        // Intent identity follows that same opaque-ID alphabet; it is metadata only.
        if !opaque_id(&self.intent_id) || self.patch_digest == [0; 32] {
            return Err(Error::MissingFact);
        }
        Ok(())
    }
}
#[derive(Clone, Debug)]
pub struct HostFacts {
    pub permissions: Vec<DocumentOperation>,
    pub capabilities: CapabilityMatrix,
    pub binding: Binding,
    /// Current source revision observed by the host, not a model-supplied value.
    pub current_revision: Revision,
    pub authority: Option<Authority>,
    /// Host must resolve live operation-specific permission at EVERY boundary.
    pub active: bool,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Confirmation {
    pub binding: Binding,
    pub authority: Authority,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Candidate {
    pub binding: Binding,
    /// Opaque scope-local immutable output identity; never an arbitrary path/URL.
    pub id: String,
    pub digest: [u8; 32],
    pub immutable_copy: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FormulaStatus {
    NotApplicable,
    Recalculated,
    Unknown,
    Failed,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Validation {
    pub candidate: Candidate,
    pub reopened: bool,
    pub structure: bool,
    pub semantics: bool,
    pub render_comparison: bool,
    pub unsupported_preserved: bool,
    pub formula: FormulaStatus,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommitReceipt {
    pub binding: Binding,
    pub candidate: Candidate,
    pub previous_revision: Revision,
    pub committed_revision: Revision,
    pub cas_succeeded: bool,
    pub durable: bool,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExportReceipt {
    pub binding: Binding,
    pub candidate: Candidate,
    pub revision: Revision,
    pub export_id: String,
    pub durable: bool,
}
/// Commands validate supplied observations; none dispatch an effect. In
/// particular, ApplyCopy and Commit must not be interpreted as executor permits.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Command {
    Inspect,
    Read,
    Propose,
    Preview,
    /// Record the exact original in-flight apply; this never dispatches it.
    AwaitApply(Confirmation),
    RecoverApply(Option<Candidate>),
    ApplyCopy {
        confirmation: Confirmation,
        candidate: Option<Candidate>,
    },
    Validate(Option<Validation>),
    Commit(Option<CommitReceipt>),
    Export(Option<ExportReceipt>),
    /// Uncertain commit result: block replay, query the original durable intent.
    OutcomeUnknown,
    RecoverCommit(Option<CommitReceipt>),
    Cancel,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    New,
    Inspected,
    Read,
    Proposed,
    Previewed,
    Applying,
    Candidate,
    Validated,
    Committed,
    Exported,
    Unknown,
    Failed,
    Conflict,
    Cancelled,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    Permission,
    Capability,
    MissingFact,
    Binding,
    Authority,
    State,
    Validation,
    Conflict,
    Unknown,
}
#[derive(Debug)]
pub struct Transaction {
    binding: Binding,
    state: State,
    confirmed_authority: Option<Authority>,
    candidate: Option<Candidate>,
    receipt: Option<CommitReceipt>,
    cancel_requested: bool,
    cancelled_from: Option<State>,
    unknown_from: Option<State>,
}
impl Transaction {
    pub fn new(binding: Binding) -> Result<Self, Error> {
        binding.check()?;
        Ok(Self {
            binding,
            state: State::New,
            confirmed_authority: None,
            candidate: None,
            receipt: None,
            cancel_requested: false,
            cancelled_from: None,
            unknown_from: None,
        })
    }
    pub fn binding(&self) -> &Binding {
        &self.binding
    }
    pub fn state(&self) -> State {
        self.state
    }
    pub fn candidate(&self) -> Option<&Candidate> {
        self.candidate.as_ref()
    }
    pub fn cancel_requested(&self) -> bool {
        self.cancel_requested
    }

    fn host<'a>(
        &self,
        facts: Option<&'a HostFacts>,
        command: &Command,
    ) -> Result<&'a HostFacts, Error> {
        let f = facts.ok_or(Error::MissingFact)?;
        if f.binding != self.binding {
            return Err(Error::Binding);
        }
        // Local stopping/uncertainty recording needs no write grant. Neither
        // discloses candidate data, grants authority nor clears an outcome.
        if matches!(command, Command::Cancel | Command::OutcomeUnknown) {
            return Ok(f);
        }
        let a = f.authority.as_ref().ok_or(Error::Authority)?;
        if !f.active
            || !opaque_id(&a.grant_id)
            || !opaque_id(&a.owner_epoch)
            || a.generation.value() == 0
        {
            return Err(Error::Authority);
        }
        if !matches!(
            command,
            Command::RecoverCommit(_) | Command::RecoverApply(_) | Command::OutcomeUnknown
        ) && self
            .confirmed_authority
            .as_ref()
            .is_some_and(|old| old != a)
        {
            return Err(Error::Authority);
        }
        // Existing DocumentHost read preflight is not a publish gateway. Require
        // an explicit host-computed operation intersection AND engine evidence.
        let operation = match command {
            Command::Inspect | Command::RecoverCommit(_) | Command::RecoverApply(_) => {
                DocumentOperation::Inspect
            }
            Command::Read | Command::Propose => DocumentOperation::ReadText,
            Command::Preview => DocumentOperation::Render,
            Command::AwaitApply(_) | Command::ApplyCopy { .. } | Command::Commit(_) => {
                DocumentOperation::StructuredEdit
            }
            Command::Validate(_) => DocumentOperation::Validate,
            Command::Export(_) => DocumentOperation::Export,
            Command::Cancel | Command::OutcomeUnknown => {
                unreachable!("local observations returned above")
            }
        };
        if !f.permissions.contains(&operation) {
            return Err(Error::Permission);
        }
        let read = matches!(
            operation,
            DocumentOperation::Inspect | DocumentOperation::ReadText | DocumentOperation::Render
        );
        match f
            .capabilities
            .status(self.binding.document.format(), operation)
        {
            CapabilityStatus::Supported => {}
            CapabilityStatus::ReadOnly if read => {}
            _ => return Err(Error::Capability),
        }
        Ok(f)
    }
    fn require(&self, state: State) -> Result<(), Error> {
        if self.state == state {
            Ok(())
        } else {
            Err(Error::State)
        }
    }
    fn check_candidate(&self, c: &Candidate) -> Result<(), Error> {
        if !opaque_id(&c.id) || c.digest == [0; 32] {
            return Err(Error::MissingFact);
        }
        if c.binding != self.binding {
            return Err(Error::Binding);
        }
        if !c.immutable_copy || c.id == self.binding.document.document_id() {
            return Err(Error::Binding);
        }
        Ok(())
    }
    fn same_candidate(&self, c: &Candidate) -> Result<(), Error> {
        if self.candidate.as_ref() != Some(c) {
            Err(Error::Binding)
        } else {
            Ok(())
        }
    }
    fn accept_commit(&mut self, receipt: Option<CommitReceipt>) -> Result<(), Error> {
        let r = receipt.ok_or(Error::MissingFact)?;
        if r.binding != self.binding {
            return Err(Error::Binding);
        }
        self.same_candidate(&r.candidate)?;
        if &r.previous_revision != self.binding.document.revision() || !r.cas_succeeded {
            self.state = State::Conflict;
            return Err(Error::Conflict);
        }
        if !r.durable {
            return Err(Error::MissingFact);
        }
        // Match the shared Revision/business contract: every publication is
        // exactly one checked increment, including rollback as a NEW revision.
        let next = r.previous_revision.next().map_err(|_| Error::Binding)?;
        if r.committed_revision != next {
            return Err(Error::Binding);
        }
        self.receipt = Some(r);
        self.state = State::Committed;
        Ok(())
    }
    pub fn execute(&mut self, command: Command, facts: Option<&HostFacts>) -> Result<(), Error> {
        let f = self.host(facts, &command)?;
        if self.state == State::Unknown
            && !matches!(
                &command,
                Command::RecoverCommit(_) | Command::RecoverApply(_) | Command::Cancel
            )
        {
            return Err(Error::Unknown);
        }
        match command {
            Command::Inspect => {
                self.require(State::New)?;
                self.state = State::Inspected;
            }
            Command::Read => {
                self.require(State::Inspected)?;
                self.state = State::Read;
            }
            Command::Propose => {
                self.require(State::Read)?;
                self.state = State::Proposed;
            }
            Command::Preview => {
                self.require(State::Proposed)?;
                self.state = State::Previewed;
            }
            Command::AwaitApply(confirmation) => {
                self.require(State::Previewed)?;
                if confirmation.binding != self.binding {
                    return Err(Error::Binding);
                }
                if Some(&confirmation.authority) != f.authority.as_ref() {
                    return Err(Error::Authority);
                }
                if &f.current_revision != self.binding.document.revision() {
                    self.state = State::Conflict;
                    return Err(Error::Conflict);
                }
                self.confirmed_authority = Some(confirmation.authority);
                self.state = State::Applying;
            }
            Command::RecoverApply(candidate) => {
                if self.state != State::Unknown || self.unknown_from != Some(State::Applying) {
                    return Err(Error::State);
                }
                let c = candidate.ok_or(Error::MissingFact)?;
                self.check_candidate(&c)?;
                self.candidate = Some(c);
                // Cancellation preserves the observed candidate without resuming work.
                self.state = if self.cancel_requested {
                    State::Cancelled
                } else {
                    State::Candidate
                };
            }
            Command::ApplyCopy {
                confirmation,
                candidate,
            } => {
                if !matches!(self.state, State::Previewed | State::Applying) {
                    return Err(Error::State);
                }
                if confirmation.binding != self.binding {
                    return Err(Error::Binding);
                }
                if Some(&confirmation.authority) != f.authority.as_ref() {
                    return Err(Error::Authority);
                }
                if &f.current_revision != self.binding.document.revision() {
                    self.state = State::Conflict;
                    return Err(Error::Conflict);
                }
                let c = candidate.ok_or(Error::MissingFact)?;
                self.check_candidate(&c)?;
                self.confirmed_authority = Some(confirmation.authority);
                self.candidate = Some(c);
                self.state = if self.cancel_requested {
                    State::Cancelled
                } else {
                    State::Candidate
                };
            }
            Command::Validate(v) => {
                self.require(State::Candidate)?;
                let v = v.ok_or(Error::MissingFact)?;
                self.same_candidate(&v.candidate)?;
                if !v.reopened
                    || !v.structure
                    || !v.semantics
                    || !v.render_comparison
                    || !v.unsupported_preserved
                    || !matches!(
                        v.formula,
                        FormulaStatus::NotApplicable | FormulaStatus::Recalculated
                    )
                {
                    self.state = State::Failed;
                    return Err(Error::Validation);
                }
                self.state = State::Validated;
            }
            Command::Commit(r) => {
                self.require(State::Validated)?;
                if &f.current_revision != self.binding.document.revision() {
                    self.state = State::Conflict;
                    return Err(Error::Conflict);
                }
                self.accept_commit(r)?;
            }
            Command::OutcomeUnknown => {
                let from = if self.state == State::Cancelled {
                    self.cancelled_from
                } else {
                    Some(self.state)
                };
                if !matches!(from, Some(State::Applying | State::Validated)) {
                    return Err(Error::State);
                }
                self.unknown_from = from;
                self.state = State::Unknown;
            }
            Command::RecoverCommit(r) => {
                if !((self.state == State::Unknown && self.unknown_from == Some(State::Validated))
                    || (self.state == State::Cancelled
                        && self.cancelled_from == Some(State::Validated)))
                {
                    return Err(Error::State);
                }
                self.accept_commit(r)?;
            }
            Command::Export(r) => {
                self.require(State::Committed)?;
                let r = r.ok_or(Error::MissingFact)?;
                if r.binding != self.binding {
                    return Err(Error::Binding);
                }
                self.same_candidate(&r.candidate)?;
                if Some(r.revision.as_str())
                    != self.receipt.as_ref().map(|x| x.committed_revision.as_str())
                {
                    return Err(Error::Binding);
                }
                if !r.durable || !opaque_id(&r.export_id) {
                    return Err(Error::MissingFact);
                }
                self.state = State::Exported;
            }
            Command::Cancel => {
                self.cancel_requested = true;
                if !matches!(
                    self.state,
                    State::Committed
                        | State::Exported
                        | State::Unknown
                        | State::Applying
                        | State::Failed
                        | State::Conflict
                        | State::Cancelled
                ) {
                    self.cancelled_from = Some(self.state);
                    self.state = State::Cancelled;
                }
            }
        }
        Ok(())
    }
    /// Build a distinct, unconfirmed transaction against the observed committed
    /// revision and explicit restore target. This never restores any bytes.
    pub fn rollback(&self, next: Binding) -> Result<Self, Error> {
        if !matches!(self.state, State::Committed | State::Exported) {
            return Err(Error::State);
        }
        next.check()?;
        if next.document.document_id() != self.binding.document.document_id()
            || next.document.scope() != self.binding.document.scope()
            || next.document.format() != self.binding.document.format()
            || next.intent_id == self.binding.intent_id
            || next.rollback_target.is_none()
            || next.rollback_target.as_ref() == Some(next.document.revision())
            || Some(next.document.revision().as_str())
                != self.receipt.as_ref().map(|r| r.committed_revision.as_str())
        {
            return Err(Error::Binding);
        }
        Self::new(next)
    }
}
