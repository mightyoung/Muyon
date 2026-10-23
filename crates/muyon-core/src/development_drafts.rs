//! DM01 pure conversation drafts. No model, storage, authorization or host implementation.
use crate::{
    contract::{
        normalize_text, CommandEnvelope, ContractError, ExecutionResult, ExecutionStatus,
        Operation, Revision, MAX_COMMAND_BYTES,
    },
    services::{
        drafts::{validate_save_ack, DraftEnvelope, DraftRef, SaveAck},
        types::{decode_strict, IntentId, ResultId, ScopeRef},
    },
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

pub const OWNER_PLUGIN_ID: &str = "development";

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SourceBinding {
    pub conversation_id: String,
    pub message_id: String,
    pub message_revision: Revision,
    /// UTF-8 byte offsets into the preserved original message; not a trusted locator.
    pub start: usize,
    pub end: usize,
    pub original_message: String,
}
impl SourceBinding {
    fn validate(&self, conversation: &str) -> Result<(), ContractError> {
        id(&self.message_id)?;
        if self.conversation_id != conversation
            || self.start >= self.end
            || self.original_message.get(self.start..self.end).is_none()
            || self.original_message.len() > 65_536
        {
            return Err(ContractError::InvalidPayload);
        }
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ItemKind {
    Requirement,
    Bug,
    Question,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DraftText {
    pub text: String,
    pub manually_edited: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DraftItem {
    pub item_id: String,
    pub kind: ItemKind,
    pub text: DraftText,
    pub sources: Vec<SourceBinding>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case", deny_unknown_fields)]
pub enum ProjectChoice {
    Unassigned,
    Ambiguous { project_ids: Vec<String> },
    Existing { project_id: String },
    New { project_id: String },
}

/// A structured extraction proposal, not a parser or executable command.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DraftPatch {
    pub project_name: Option<String>,
    pub items: Vec<DraftItem>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TextDifference {
    /// "project_name" or the stable item ID.
    pub field: String,
    pub before: Option<String>,
    pub after: String,
    pub conflicts_with_manual_edit: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Submission {
    command: CommandEnvelope,
    /// Set before entering the host. A restored dispatched request is query-only.
    dispatched: bool,
    result: Option<ExecutionResult>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Content {
    /// Local editor CAS token, separate from DraftRef's confirmed storage baseline.
    edit_revision: Revision,
    conversation_id: String,
    project_name: Option<DraftText>,
    project: ProjectChoice,
    items: Vec<DraftItem>,
    submission: Option<Submission>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ConversationDraft {
    reference: DraftRef,
    content: Content,
}

/// Implemented by a host adapter that still owns authorization and the original ledger.
pub trait ProjectHost {
    fn query_original(&mut self, command: &CommandEnvelope) -> ExecutionResult;
}

impl ConversationDraft {
    pub fn new(reference: DraftRef, conversation_id: String) -> Result<Self, ContractError> {
        let draft = Self {
            reference,
            content: Content {
                edit_revision: Revision::new(0),
                conversation_id,
                project_name: None,
                project: ProjectChoice::Unassigned,
                items: vec![],
                submission: None,
            },
        };
        draft.validate()?;
        Ok(draft)
    }
    /// Local editing token used by preview/apply/project choice, never storage CAS.
    pub fn revision(&self) -> &Revision {
        &self.content.edit_revision
    }
    /// Last confirmed storage CAS baseline, advanced only by a matching SaveAck.
    pub fn stored_revision(&self) -> &Revision {
        &self.reference.revision
    }
    pub fn project(&self) -> &ProjectChoice {
        &self.content.project
    }
    pub fn project_name(&self) -> Option<&DraftText> {
        self.content.project_name.as_ref()
    }
    pub fn items(&self) -> &[DraftItem] {
        &self.content.items
    }

    pub fn envelope(&self) -> Result<DraftEnvelope, ContractError> {
        Ok(DraftEnvelope {
            draft_ref: self.reference.clone(),
            schema_version: 1,
            content: serde_json::to_value(&self.content)
                .map_err(|_| ContractError::InvalidPayload)?,
        })
    }

    /// Restore validates shape and expected scope; it never confers authority.
    pub fn restore(raw: &str, expected_scope: &ScopeRef) -> Result<Self, ContractError> {
        let envelope: DraftEnvelope =
            decode_strict(raw).map_err(|_| ContractError::InvalidPayload)?;
        if envelope.schema_version != 1 {
            return Err(ContractError::InvalidVersion);
        }
        if &envelope.draft_ref.scope != expected_scope {
            return Err(ContractError::ScopeMismatch);
        }
        let draft = Self {
            reference: envelope.draft_ref,
            content: serde_json::from_value(envelope.content)
                .map_err(|_| ContractError::InvalidPayload)?,
        };
        draft.validate()?;
        Ok(draft)
    }

    pub fn acknowledge_save(
        &mut self,
        pending: &IntentId,
        ack: &SaveAck,
    ) -> Result<(), ContractError> {
        validate_save_ack(&self.envelope()?, self.stored_revision(), pending, ack)
            .map_err(|_| ContractError::BindingMismatch)?;
        let mut next = self.clone();
        next.reference = ack.draft_ref.clone();
        next.validate()?;
        *self = next;
        Ok(())
    }

    pub fn preview(
        &self,
        expected: &Revision,
        patch: &DraftPatch,
    ) -> Result<Vec<TextDifference>, ContractError> {
        self.check_revision(expected)?;
        validate_patch(patch, &self.content.conversation_id)?;
        let mut differences = vec![];
        if let Some(name) = &patch.project_name {
            difference(
                &mut differences,
                "project_name",
                self.content.project_name.as_ref(),
                name,
            );
        }
        for item in &patch.items {
            let previous = self
                .content
                .items
                .iter()
                .find(|old| old.item_id == item.item_id);
            // A stable ID cannot silently change the object's meaning or original source.
            if previous.is_some_and(|old| old.kind != item.kind || old.sources != item.sources) {
                return Err(ContractError::BindingMismatch);
            }
            difference(
                &mut differences,
                &item.item_id,
                previous.map(|old| &old.text),
                &item.text.text,
            );
        }
        Ok(differences)
    }

    /// Suggestions never overwrite manual edits. Manual changes require this explicit flag.
    pub fn apply(
        &mut self,
        expected: &Revision,
        patch: DraftPatch,
        manual: bool,
    ) -> Result<Vec<TextDifference>, ContractError> {
        let differences = self.preview(expected, &patch)?;
        if !manual
            && differences
                .iter()
                .any(|change| change.conflicts_with_manual_edit)
        {
            return Err(ContractError::RevisionConflict);
        }
        let mut next = self.clone();
        if let Some(text) = patch.project_name {
            let edited = manual
                || next
                    .content
                    .project_name
                    .as_ref()
                    .is_some_and(|v| v.manually_edited);
            next.content.project_name = Some(DraftText {
                text,
                manually_edited: edited,
            });
        }
        for mut item in patch.items {
            if let Some(old) = next
                .content
                .items
                .iter_mut()
                .find(|old| old.item_id == item.item_id)
            {
                item.text.manually_edited = manual || old.text.manually_edited;
                *old = item;
            } else {
                item.text.manually_edited = manual;
                next.content.items.push(item);
            }
        }
        next.changed()?;
        next.validate()?;
        *self = next;
        Ok(differences)
    }

    pub fn propose_projects(
        &mut self,
        expected: &Revision,
        project_ids: Vec<String>,
    ) -> Result<(), ContractError> {
        self.check_revision(expected)?;
        unique_ids(&project_ids)?;
        if project_ids.is_empty() {
            return Err(ContractError::Required);
        }
        let mut next = self.clone();
        next.content.project = ProjectChoice::Ambiguous { project_ids };
        next.changed()?;
        next.validate()?;
        *self = next;
        Ok(())
    }

    /// Existing choices must come from the displayed candidates; new project creation is explicit.
    pub fn choose_project(
        &mut self,
        expected: &Revision,
        project_id: String,
        create_new: bool,
    ) -> Result<(), ContractError> {
        self.check_revision(expected)?;
        id(&project_id)?;
        if !create_new
            && !matches!(&self.content.project,
            ProjectChoice::Ambiguous { project_ids } if project_ids.contains(&project_id))
        {
            return Err(ContractError::BindingMismatch);
        }
        let mut next = self.clone();
        next.content.project = if create_new {
            ProjectChoice::New { project_id }
        } else {
            ProjectChoice::Existing { project_id }
        };
        next.changed()?;
        next.validate()?;
        *self = next;
        Ok(())
    }

    /// Accept an already prepared original host command; does not mint grants or plans.
    pub fn prepare_project(
        &mut self,
        expected: &Revision,
        command: CommandEnvelope,
    ) -> Result<(), ContractError> {
        self.check_revision(expected)?;
        if self.content.submission.is_some() {
            return Err(ContractError::IntentConflict);
        }
        self.validate_command(&command)?;
        let mut next = self.clone();
        next.content.submission = Some(Submission {
            command,
            dispatched: false,
            result: None,
        });
        next.validate()?;
        *self = next;
        Ok(())
    }

    /// Marks the original request before returning it to the host. A real adapter must
    /// durably save the resulting envelope before executing this command. A crash after
    /// saving the marker but before execution is also recovered by querying, never resend.
    pub fn begin_project_dispatch(&mut self) -> Result<CommandEnvelope, ContractError> {
        let mut next = self.clone();
        let submission = next
            .content
            .submission
            .as_mut()
            .ok_or(ContractError::Required)?;
        if submission.dispatched {
            return Err(ContractError::IntentConflict);
        }
        submission.dispatched = true;
        let command = submission.command.clone();
        next.validate()?;
        *self = next;
        Ok(command)
    }

    pub fn observe_project_result(&mut self, result: ExecutionResult) -> Result<(), ContractError> {
        let mut next = self.clone();
        let submission = next
            .content
            .submission
            .as_mut()
            .ok_or(ContractError::Required)?;
        if !submission.dispatched {
            return Err(ContractError::BindingMismatch);
        }
        validate_result(&result, &submission.command)?;
        if let Some(previous) = &submission.result {
            if !matches!(
                previous.status,
                ExecutionStatus::Pending | ExecutionStatus::Unknown
            ) && previous != &result
            {
                return Err(ContractError::BindingMismatch);
            }
        }
        submission.result = Some(result);
        next.validate()?;
        *self = next;
        Ok(())
    }

    /// Repeat clicks and restored pending/unknown requests only query the original identity.
    pub fn recover_project(
        &mut self,
        host: &mut impl ProjectHost,
    ) -> Result<ExecutionResult, ContractError> {
        let submission = self
            .content
            .submission
            .as_mut()
            .ok_or(ContractError::Required)?;
        if !submission.dispatched {
            return Err(ContractError::Required);
        }
        if let Some(result) = &submission.result {
            if !matches!(
                result.status,
                ExecutionStatus::Pending | ExecutionStatus::Unknown
            ) {
                return Ok(result.clone());
            }
        }
        let result = host.query_original(&submission.command);
        // A malformed/mismatched response leaves the marker query-only.
        self.observe_project_result(result.clone())?;
        Ok(result)
    }

    fn check_revision(&self, expected: &Revision) -> Result<(), ContractError> {
        if self.revision() != expected {
            Err(ContractError::RevisionConflict)
        } else {
            Ok(())
        }
    }
    fn changed(&mut self) -> Result<(), ContractError> {
        if self
            .content
            .submission
            .as_ref()
            .is_some_and(|s| s.dispatched)
        {
            return Err(ContractError::IntentConflict);
        }
        self.content.edit_revision = self.content.edit_revision.next()?;
        self.content.submission = None; // Any edit invalidates preparation.
        Ok(())
    }
    fn validate_command(&self, command: &CommandEnvelope) -> Result<(), ContractError> {
        command.validate()?;
        if command.scope != self.reference.scope.scope {
            return Err(ContractError::ScopeMismatch);
        }
        match (
            &self.content.project,
            &command.command,
            &self.content.project_name,
        ) {
            (
                ProjectChoice::New {
                    project_id: expected_id,
                },
                Operation::ProjectCreate { project_id, name },
                Some(expected_name),
            ) if project_id == expected_id && name == &expected_name.text => Ok(()),
            _ => Err(ContractError::BindingMismatch),
        }
    }
    fn validate(&self) -> Result<(), ContractError> {
        if self.reference.owner_plugin_id != OWNER_PLUGIN_ID {
            return Err(ContractError::BindingMismatch);
        }
        id(&self.reference.draft_id)?;
        id(&self.reference.scope.scope.workspace_id)?;
        id(&self.content.conversation_id)?;
        if let Some(project) = &self.reference.scope.scope.project_id {
            id(project)?;
        }
        if let Some(name) = &self.content.project_name {
            normalize_text(&name.text, 200, true)?;
        }
        match &self.content.project {
            ProjectChoice::Ambiguous { project_ids } => {
                unique_ids(project_ids)?;
                if project_ids.is_empty() {
                    return Err(ContractError::Required);
                }
                for project_id in project_ids {
                    self.validate_project_scope(project_id)?;
                }
            }
            ProjectChoice::New { project_id } | ProjectChoice::Existing { project_id } => {
                id(project_id)?;
                self.validate_project_scope(project_id)?;
            }
            ProjectChoice::Unassigned => {}
        }
        validate_patch(
            &DraftPatch {
                project_name: None,
                items: self.content.items.clone(),
            },
            &self.content.conversation_id,
        )?;
        if let Some(submission) = &self.content.submission {
            self.validate_command(&submission.command)?;
            if let Some(result) = &submission.result {
                if !submission.dispatched {
                    return Err(ContractError::BindingMismatch);
                }
                validate_result(result, &submission.command)?;
            }
        }
        // The same complete envelope must fit the existing strict restore decoder,
        // including JSON escaping, editor metadata, command and receipt payloads.
        let encoded =
            serde_json::to_string(&self.envelope()?).map_err(|_| ContractError::InvalidPayload)?;
        if encoded.len() > MAX_COMMAND_BYTES {
            return Err(ContractError::RawLimit);
        }
        crate::contract::decode_json(&encoded).map_err(|_| ContractError::InvalidPayload)?;
        Ok(())
    }
    fn validate_project_scope(&self, project_id: &str) -> Result<(), ContractError> {
        if self
            .reference
            .scope
            .scope
            .project_id
            .as_deref()
            .is_some_and(|bound| bound != project_id)
        {
            Err(ContractError::ScopeMismatch)
        } else {
            Ok(())
        }
    }
}

fn id(value: &str) -> Result<(), ContractError> {
    ResultId::parse(value)
        .map(|_| ())
        .map_err(|_| ContractError::InvalidIdentity)
}
fn unique_ids(values: &[String]) -> Result<(), ContractError> {
    let mut seen = BTreeSet::new();
    for value in values {
        id(value)?;
        if !seen.insert(value) {
            return Err(ContractError::InvalidIdentity);
        }
    }
    Ok(())
}
fn validate_patch(patch: &DraftPatch, conversation: &str) -> Result<(), ContractError> {
    if let Some(name) = &patch.project_name {
        normalize_text(name, 200, true)?;
    }
    unique_ids(
        &patch
            .items
            .iter()
            .map(|i| i.item_id.clone())
            .collect::<Vec<_>>(),
    )?;
    if patch.items.len() > 256 {
        return Err(ContractError::RawLimit);
    }
    for item in &patch.items {
        normalize_text(&item.text.text, 2000, true)?;
        if item.sources.is_empty() || item.sources.len() > 32 {
            return Err(ContractError::Required);
        }
        for source in &item.sources {
            source.validate(conversation)?;
        }
    }
    Ok(())
}
fn difference(
    output: &mut Vec<TextDifference>,
    field: &str,
    previous: Option<&DraftText>,
    after: &str,
) {
    if previous.is_none_or(|p| p.text != after) {
        output.push(TextDifference {
            field: field.into(),
            before: previous.map(|p| p.text.clone()),
            after: after.into(),
            conflicts_with_manual_edit: previous.is_some_and(|p| p.manually_edited),
        });
    }
}
fn validate_result(
    result: &ExecutionResult,
    command: &CommandEnvelope,
) -> Result<(), ContractError> {
    result.validate()?;
    if let Some(receipt) = &result.receipt {
        receipt.validate_for(command)?;
    }
    Ok(())
}
