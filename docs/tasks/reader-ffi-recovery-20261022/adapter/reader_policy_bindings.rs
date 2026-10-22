//! Staged correlation validation, not grant policy, visibility or a native ticket.
//! No issuer/SQLite/current-root lookup. Concrete Core remains authoritative.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum InputError {
    Identifier,
    Counter,
    Scope,
    Attempt,
    Kind,
    Selection,
    Frame,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ScopeCorrelation {
    pub service_session: String,
    pub generation: String,
    pub project: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OriginalKind {
    Admission,
    Begin,
    Renew,
    Handoff,
    Stop,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OriginalKey {
    pub scope: ScopeCorrelation,
    pub kind: OriginalKind,
    pub attempt_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FrameCorrelation {
    pub scope: ScopeCorrelation,
    /// Internal captured native selection epoch; never a caller claim of current.
    pub selection_epoch: String,
    pub presentation_id: String,
    pub frame_generation: String,
}

pub fn identifier(value: &str) -> Result<(), InputError> {
    if value.is_empty()
        || value.len() > 128
        || !value
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"-_.:".contains(&c))
    {
        return Err(InputError::Identifier);
    }
    Ok(())
}

/// Canonical unsigned decimal validation only, never an authorization check.
pub fn counter(value: &str) -> Result<u64, InputError> {
    if value.is_empty()
        || value.len() > 20
        || !value.bytes().all(|c| c.is_ascii_digit())
        || (value.len() > 1 && value.starts_with('0'))
    {
        return Err(InputError::Counter);
    }
    value.parse::<u64>().map_err(|_| InputError::Counter)
}

impl ScopeCorrelation {
    pub fn validate(&self) -> Result<(), InputError> {
        identifier(&self.service_session)?;
        identifier(&self.generation)?;
        identifier(&self.project)
    }
}
impl OriginalKey {
    pub fn validate(&self) -> Result<(), InputError> {
        self.scope.validate()?;
        identifier(&self.attempt_id)
    }
    /// Exact original identity only, not evidence of a committed outcome.
    pub fn check_same_original(&self, incoming: &Self) -> Result<(), InputError> {
        self.validate()?;
        incoming.validate()?;
        if self.scope != incoming.scope {
            return Err(InputError::Scope);
        }
        if self.kind != incoming.kind {
            return Err(InputError::Kind);
        }
        if self.attempt_id != incoming.attempt_id {
            return Err(InputError::Attempt);
        }
        Ok(())
    }
}
impl FrameCorrelation {
    pub fn validate(&self) -> Result<(), InputError> {
        self.scope.validate()?;
        identifier(&self.presentation_id)?;
        if counter(&self.selection_epoch)? == 0 || counter(&self.frame_generation)? == 0 {
            return Err(InputError::Counter);
        }
        Ok(())
    }
    /// Pure comparison: rejection never updates/adopts/closes a newer frame.
    /// Both values must be validated; success still needs the genuine Core ticket.
    pub fn check_original_callback(&self, incoming: &Self) -> Result<(), InputError> {
        self.validate()?;
        incoming.validate()?;
        if self.scope != incoming.scope {
            return Err(InputError::Scope);
        }
        if self.selection_epoch != incoming.selection_epoch {
            return Err(InputError::Selection);
        }
        if self.presentation_id != incoming.presentation_id
            || self.frame_generation != incoming.frame_generation
        {
            return Err(InputError::Frame);
        }
        Ok(())
    }
}
