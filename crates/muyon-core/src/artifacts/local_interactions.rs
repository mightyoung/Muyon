//! Bounded local component state, not business execution or canonical source data.
//! Actual Evidence source authority is revalidated in each local transaction.
use super::save_journal::{requires_original_lookup, ArtifactSaveFailure, JournalDomain};
use super::*;
use crate::contract::{AuthorityBinding, RecoveryAction};
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};
const SCHEMA: &[(&str,&str)] = &[
    ("artifact_local_meta_v1","CREATE TABLE artifact_local_meta_v1(key TEXT PRIMARY KEY,value TEXT NOT NULL)"),
    ("artifact_local_bindings_v1","CREATE TABLE artifact_local_bindings_v1(project_id TEXT NOT NULL REFERENCES projects(id),actor_id TEXT NOT NULL,object_id TEXT NOT NULL,binding_json TEXT NOT NULL,kind_json TEXT NOT NULL,generation TEXT NOT NULL,grant_id TEXT NOT NULL,grant_generation TEXT NOT NULL,owner_epoch TEXT NOT NULL,expires_at_ms TEXT NOT NULL,active INTEGER NOT NULL CHECK(active IN(0,1)),PRIMARY KEY(project_id,actor_id,object_id))"),
    ("artifact_local_forms_v1","CREATE TABLE artifact_local_forms_v1(project_id TEXT NOT NULL,actor_id TEXT NOT NULL,object_id TEXT NOT NULL,revision TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(project_id,actor_id,object_id),FOREIGN KEY(project_id,actor_id,object_id) REFERENCES artifact_local_bindings_v1(project_id,actor_id,object_id))"),
    ("artifact_local_feedback_v1","CREATE TABLE artifact_local_feedback_v1(project_id TEXT NOT NULL,actor_id TEXT NOT NULL,object_id TEXT NOT NULL,revision TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(project_id,actor_id,object_id),FOREIGN KEY(project_id,actor_id,object_id) REFERENCES artifact_local_bindings_v1(project_id,actor_id,object_id))"),
    ("artifact_local_reviews_v1","CREATE TABLE artifact_local_reviews_v1(intent_id TEXT PRIMARY KEY,project_id TEXT NOT NULL,actor_id TEXT NOT NULL,request_json TEXT NOT NULL,digest TEXT NOT NULL)"),
    ("artifact_local_intents_v1","CREATE TABLE artifact_local_intents_v1(intent_id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id),actor_id TEXT NOT NULL,binding_digest TEXT NOT NULL,request_json TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN('pending','committed','rejected')),receipt_json TEXT,error TEXT,object_id TEXT NOT NULL)"),
];
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum LocalTarget {
    Message {
        conversation_id: String,
        message_id: String,
        revision: Revision,
    },
    Evidence {
        evidence_id: String,
        revision: Revision,
    },
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LocalObjectRef {
    pub object_id: String,
    pub target: LocalTarget,
    pub component_id: String,
    pub component_revision: Revision,
    pub attempt_id: String,
}
impl LocalObjectRef {
    pub(super) fn validate(&self) -> Result<()> {
        identifier(&self.object_id)?;
        identifier(&self.component_id)?;
        identifier(&self.attempt_id)?;
        let revision = match &self.target {
            LocalTarget::Message {
                conversation_id,
                message_id,
                revision,
            } => {
                identifier(conversation_id)?;
                identifier(message_id)?;
                revision
            }
            LocalTarget::Evidence {
                evidence_id,
                revision,
            } => {
                identifier(evidence_id)?;
                revision
            }
        };
        if revision.value() == 0 {
            return Err(ContractError::InvalidRevision);
        }
        Ok(())
    }
}
/// Not a token and not deserializable; authority is always read from persisted rows.
#[derive(Clone, Debug)]
pub struct LocalAccess {
    pub project: ArtifactProjectAccess,
    pub object: LocalObjectRef,
    pub binding_generation: Revision,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LocalField {
    Text,
    Choice,
    Selections,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FormSpec {
    pub fields: Vec<LocalField>,
    pub single_options: Vec<String>,
    pub multiple_options: Vec<String>,
}
impl FormSpec {
    fn validate(&self) -> Result<()> {
        if self.fields.is_empty() || self.fields.len() > 3 {
            return Err(ContractError::InvalidPayload);
        }
        let mut fields = self.fields.clone();
        fields.sort();
        fields.dedup();
        if fields.len() != self.fields.len() {
            return Err(ContractError::InvalidPayload);
        }
        for (field, options) in [
            (LocalField::Choice, &self.single_options),
            (LocalField::Selections, &self.multiple_options),
        ] {
            if options.len() > 16 || self.fields.contains(&field) == options.is_empty() {
                return Err(ContractError::InvalidPayload);
            }
            let mut unique = options.clone();
            unique.sort();
            unique.dedup();
            if unique.len() != options.len() {
                return Err(ContractError::InvalidPayload);
            }
            for option in options {
                identifier(option)?;
            }
        }
        Ok(())
    }
    fn values(&self, values: &FormValues) -> Result<()> {
        text(&values.text, 4096)?;
        if !self.fields.contains(&LocalField::Text) && !values.text.is_empty() {
            return Err(ContractError::InvalidPayload);
        }
        if let Some(choice) = &values.choice {
            if !self.single_options.contains(choice) {
                return Err(ContractError::InvalidPayload);
            }
        }
        let mut selected = values.selections.clone();
        selected.sort();
        selected.dedup();
        if selected.len() != values.selections.len()
            || selected
                .iter()
                .any(|id| !self.multiple_options.contains(id))
        {
            return Err(ContractError::InvalidPayload);
        }
        Ok(())
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "spec",
    rename_all = "snake_case",
    deny_unknown_fields
)]
pub enum LocalKind {
    Form(FormSpec),
    Feedback,
}
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FormValues {
    pub text: String,
    pub choice: Option<String>,
    pub selections: Vec<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "field", rename_all = "snake_case", deny_unknown_fields)]
pub enum FieldChange {
    Text { value: String },
    Choice { value: Option<String> },
    Selections { values: Vec<String> },
}
impl FieldChange {
    fn field(&self) -> LocalField {
        match self {
            Self::Text { .. } => LocalField::Text,
            Self::Choice { .. } => LocalField::Choice,
            Self::Selections { .. } => LocalField::Selections,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FeedbackValue {
    Helpful,
    NotHelpful,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum LocalMutation {
    Patch {
        expected: Revision,
        changes: Vec<FieldChange>,
        author: AnnotationAuthor,
    },
    React {
        expected: Revision,
        value: Option<FeedbackValue>,
    },
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FieldOrigin {
    pub field: LocalField,
    pub author: AnnotationAuthor,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FormState {
    pub revision: Revision,
    pub values: FormValues,
    pub manual_fields: Vec<LocalField>,
    pub field_origins: Vec<FieldOrigin>,
    pub modified_by: Option<AnnotationAuthor>,
    pub submitted_intent: Option<String>,
    pub pending_intent: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FeedbackState {
    pub revision: Revision,
    pub value: Option<FeedbackValue>,
    pub pending_intent: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LocalReceipt {
    pub intent_id: String,
    pub digest: String,
    pub object: LocalObjectRef,
    pub revision: Revision,
    pub result: LocalResult,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LocalResult {
    DraftSaved,
    FormSubmitted,
    FeedbackSaved,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct LocalOutcome {
    pub status: ArtifactSaveStatus,
    pub receipt: Option<LocalReceipt>,
    pub error: Option<ContractError>,
    pub recovery_action: RecoveryAction,
}
impl LocalOutcome {
    fn failure(error: ContractError) -> Self {
        Self {
            status: ArtifactSaveStatus::Unknown,
            receipt: None,
            error: Some(error),
            recovery_action: RecoveryAction::QueryOriginal,
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LocalPreview {
    pub intent_id: String,
    pub digest: String,
    pub object: LocalObjectRef,
    pub revision: Revision,
    pub values: FormValues,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum Command {
    Mutation {
        mutation: LocalMutation,
    },
    Confirm {
        expected: Revision,
        values: FormValues,
        spec: FormSpec,
    },
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    intent: String,
    scope: Scope,
    actor: String,
    object: LocalObjectRef,
    command: Command,
    confirmation: Option<ReviewAuthority>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ReviewAuthority {
    binding_generation: Revision,
    project_revision: Revision,
    authority: AuthorityBinding,
}
impl ReviewAuthority {
    fn current(a: &LocalAccess) -> Self {
        Self {
            binding_generation: a.binding_generation.clone(),
            project_revision: a.project.project_revision.clone(),
            authority: a.project.authority.clone(),
        }
    }
}
impl Request {
    fn binding(&self) -> Result<(String, String)> {
        if matches!(self.command, Command::Confirm { .. }) != self.confirmation.is_some() {
            return Err(ContractError::StorageCorrupt);
        }
        let json = encode(self)?;
        if json.len() > 16 * 1024 {
            return Err(ContractError::TextLimit);
        }
        let mut hash = Sha256::new();
        hash.update(b"muyon.local.v1\0");
        hash.update(json.as_bytes());
        let digest = hash.finalize().iter().map(|b| format!("{b:02x}")).collect();
        Ok((json, digest))
    }
    fn permission(&self) -> ArtifactProjectOperation {
        match &self.command {
            Command::Mutation {
                mutation: LocalMutation::Patch { .. },
            } => ArtifactProjectOperation::LocalDraft,
            Command::Mutation {
                mutation: LocalMutation::React { .. },
            } => ArtifactProjectOperation::LocalFeedback,
            Command::Confirm { .. } => ArtifactProjectOperation::LocalSubmit,
        }
    }
    fn expected(&self) -> &Revision {
        match &self.command {
            Command::Mutation {
                mutation:
                    LocalMutation::Patch { expected, .. } | LocalMutation::React { expected, .. },
            }
            | Command::Confirm { expected, .. } => expected,
        }
    }
    fn result(&self) -> LocalResult {
        match &self.command {
            Command::Mutation {
                mutation: LocalMutation::Patch { .. },
            } => LocalResult::DraftSaved,
            Command::Mutation {
                mutation: LocalMutation::React { .. },
            } => LocalResult::FeedbackSaved,
            Command::Confirm { .. } => LocalResult::FormSubmitted,
        }
    }
}
fn now() -> Result<u64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| ContractError::InvalidAuthority)?
        .as_millis()
        .try_into()
        .map_err(|_| ContractError::InvalidAuthority)
}
fn text(value: &str, max: usize) -> Result<()> {
    if value.len() > max || value.contains('\0') {
        Err(ContractError::InvalidPayload)
    } else {
        Ok(())
    }
}
impl BusinessStore {
    pub fn initialize_local_interactions_trusted(&self) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        self.artifact_workflow_schema()?;
        let mut present = 0;
        for (name, _) in SCHEMA {
            present += sql(self.database().query(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                &[name],
            ))?
            .len();
        }
        if present == 0 {
            for (_, ddl) in SCHEMA {
                sql(self.database().exec(ddl, &[]))?;
            }
            sql(self.database().exec(
                "INSERT INTO artifact_local_meta_v1 VALUES('version','1')",
                &[],
            ))?;
            sql(self.database().exec(
                "INSERT INTO artifact_local_meta_v1 VALUES('workspace',?)",
                &[self.workspace_id()],
            ))?;
        } else if present != SCHEMA.len() {
            return Err(ContractError::InvalidVersion);
        }
        self.initialize_local_sources_in_transaction(&tx)?;
        self.local_schema()?;
        sql(tx.commit())
    }
    fn local_schema(&self) -> Result<()> {
        self.artifact_workflow_schema()?;
        for (name, ddl) in SCHEMA {
            let rows = sql(self.database().query(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                &[name],
            ))?;
            if rows.len() != 1 || cell(&rows[0], 0)? != *ddl {
                return Err(ContractError::InvalidVersion);
            }
        }
        if sql(self.database().query(
            "SELECT key,value FROM artifact_local_meta_v1 ORDER BY key",
            &[],
        ))? != vec![
            vec![Some("version".into()), Some("1".into())],
            vec![Some("workspace".into()), Some(self.workspace_id().into())],
        ] {
            return Err(ContractError::InvalidVersion);
        }
        Ok(())
    }
    /// Renew an already resolved exact Evidence binding. Initial issuance requires
    /// issue_local_evidence_binding_trusted; unresolved Message is unsupported.
    pub fn issue_local_binding_trusted(
        &self,
        a: &LocalAccess,
        kind: &LocalKind,
        expires: u64,
    ) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        self.issue_local_binding_in_transaction(&tx, a, kind, expires)?;
        sql(tx.commit())
    }
    pub(super) fn issue_local_binding_in_transaction(
        &self,
        tx: &Transaction<'_>,
        a: &LocalAccess,
        kind: &LocalKind,
        expires: u64,
    ) -> Result<()> {
        a.object.validate()?;
        if let LocalKind::Form(spec) = kind {
            spec.validate()?;
        }
        self.local_schema()?;
        self.local_source_binding(tx, a)?;
        let permission = match kind {
            LocalKind::Form(_) => ArtifactProjectOperation::LocalDraft,
            LocalKind::Feedback => ArtifactProjectOperation::LocalFeedback,
        };
        self.artifact_project_authorize(tx, &a.project, permission)?;
        let clock = now()?;
        if expires <= clock
            || expires
                > clock
                    .checked_add(30_000)
                    .ok_or(ContractError::InvalidAuthority)?
        {
            return Err(ContractError::InvalidAuthority);
        }
        let reference = encode(&a.object)?;
        let spec = encode(kind)?;
        let rows=sql(self.database().query("SELECT CASE WHEN length(CAST(binding_json AS BLOB))<=8192 THEN binding_json ELSE NULL END,CASE WHEN length(CAST(kind_json AS BLOB))<=8192 THEN kind_json ELSE NULL END,CASE WHEN length(CAST(generation AS BLOB))<=20 THEN generation ELSE NULL END FROM artifact_local_bindings_v1 WHERE project_id=? AND actor_id=? AND object_id=?",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id]))?;
        let expected = if rows.is_empty() {
            Revision::new(1)
        } else {
            if cell(&rows[0], 0)? != reference || cell(&rows[0], 1)? != spec {
                return Err(ContractError::BindingMismatch);
            }
            Revision::parse(cell(&rows[0], 2)?)?.next()?
        };
        if a.binding_generation != expected {
            return Err(ContractError::InvalidAuthority);
        }
        sql(self.database().exec("INSERT INTO artifact_local_bindings_v1 VALUES(?,?,?,?,?,?,?,?,?,?,1) ON CONFLICT(project_id,actor_id,object_id) DO UPDATE SET generation=excluded.generation,grant_id=excluded.grant_id,grant_generation=excluded.grant_generation,owner_epoch=excluded.owner_epoch,expires_at_ms=excluded.expires_at_ms,active=1",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id,&reference,&spec,a.binding_generation.as_str(),&a.project.authority.grant_id,a.project.authority.generation.as_str(),&a.project.authority.owner_epoch,&expires.to_string()]))?;
        if self.local_binding(tx, a, permission)? != *kind {
            return Err(ContractError::BindingMismatch);
        }
        self.artifact_project_authorize(tx, &a.project, permission)?;
        Ok(())
    }
    pub fn revoke_local_binding_trusted(&self, a: &LocalAccess) -> Result<()> {
        let tx = sql(self.database().transaction())?;
        self.local_schema()?;
        // Resolve only the scoped binding kind internally; do not require a new
        // read permission merely to revoke an already issued mutation lease.
        let rows=sql(self.database().query("SELECT CASE WHEN length(CAST(kind_json AS BLOB))<=8192 THEN kind_json ELSE NULL END FROM artifact_local_bindings_v1 WHERE project_id=? AND actor_id=? AND object_id=?",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id]))?;
        let kind: LocalKind = decode(cell(rows.first().ok_or(ContractError::NotFound)?, 0)?)?;
        let permission = match kind {
            LocalKind::Form(_) => ArtifactProjectOperation::LocalDraft,
            LocalKind::Feedback => ArtifactProjectOperation::LocalFeedback,
        };
        self.local_binding(&tx, a, permission)?;
        if sql(self.database().exec("UPDATE artifact_local_bindings_v1 SET active=0 WHERE project_id=? AND actor_id=? AND object_id=? AND generation=?",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id,a.binding_generation.as_str()]))?!=1 {return Err(ContractError::InvalidAuthority);}
        self.artifact_project_authorize(&tx, &a.project, permission)?;
        sql(tx.commit())
    }
    fn local_binding(
        &self,
        tx: &Transaction<'_>,
        a: &LocalAccess,
        permission: ArtifactProjectOperation,
    ) -> Result<LocalKind> {
        self.local_schema()?;
        self.artifact_project_authorize(tx, &a.project, permission)?;
        a.object.validate()?;
        self.local_source_binding(tx, a)?;
        let rows=sql(self.database().query("SELECT CASE WHEN length(CAST(binding_json AS BLOB))<=8192 THEN binding_json ELSE NULL END,CASE WHEN length(CAST(kind_json AS BLOB))<=8192 THEN kind_json ELSE NULL END,CASE WHEN length(CAST(expires_at_ms AS BLOB))<=20 THEN expires_at_ms ELSE NULL END FROM artifact_local_bindings_v1 WHERE project_id=? AND actor_id=? AND object_id=? AND generation=? AND grant_id=? AND grant_generation=? AND owner_epoch=? AND active=1",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id,a.binding_generation.as_str(),&a.project.authority.grant_id,a.project.authority.generation.as_str(),&a.project.authority.owner_epoch]))?;
        let row = rows.first().ok_or(ContractError::InvalidAuthority)?;
        if decode::<LocalObjectRef>(cell(row, 0)?)? != a.object {
            return Err(ContractError::BindingMismatch);
        }
        if cell(row, 2)?
            .parse::<u64>()
            .map_err(|_| ContractError::StorageCorrupt)?
            <= now()?
        {
            return Err(ContractError::InvalidAuthority);
        }
        let kind: LocalKind = decode(cell(row, 1)?)?;
        if let LocalKind::Form(spec) = &kind {
            spec.validate()?;
        }
        Ok(kind)
    }
    fn local_pending(&self, a: &LocalAccess) -> Result<Option<String>> {
        let rows=sql(self.database().query("SELECT CASE WHEN length(CAST(intent_id AS BLOB))<=128 THEN intent_id ELSE NULL END FROM artifact_local_intents_v1 WHERE project_id=? AND actor_id=? AND object_id=? AND status='pending' LIMIT 1",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id]))?;
        rows.first()
            .map(|row| cell(row, 0).map(str::to_owned))
            .transpose()
    }
    fn form_state(&self, a: &LocalAccess, spec: &FormSpec) -> Result<FormState> {
        let rows=sql(self.database().query("SELECT CASE WHEN length(CAST(revision AS BLOB))<=20 THEN revision ELSE NULL END,CASE WHEN length(CAST(payload AS BLOB))<=16384 THEN payload ELSE NULL END FROM artifact_local_forms_v1 WHERE project_id=? AND actor_id=? AND object_id=?",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id]))?;
        let mut state = if let Some(row) = rows.first() {
            let state: FormState = decode(cell(row, 1)?)?;
            if state.revision.as_str() != cell(row, 0)? {
                return Err(ContractError::StorageCorrupt);
            }
            state
        } else {
            FormState {
                revision: Revision::new(0),
                values: FormValues::default(),
                manual_fields: vec![],
                field_origins: vec![],
                modified_by: None,
                submitted_intent: None,
                pending_intent: None,
            }
        };
        spec.values(&state.values)?;
        if state
            .manual_fields
            .iter()
            .any(|field| !spec.fields.contains(field))
        {
            return Err(ContractError::StorageCorrupt);
        }
        if let Some(author) = &state.modified_by {
            author.validate()?;
        }
        if state.field_origins.len() > 3 {
            return Err(ContractError::StorageCorrupt);
        }
        let mut seen = Vec::new();
        for origin in &state.field_origins {
            origin.author.validate()?;
            if !spec.fields.contains(&origin.field) || seen.contains(&origin.field) {
                return Err(ContractError::StorageCorrupt);
            }
            seen.push(origin.field);
            match &origin.author {
                AnnotationAuthor::Human { actor_id }
                    if actor_id == &a.project.actor_id
                        && state.manual_fields.contains(&origin.field) => {}
                AnnotationAuthor::Ai { .. }
                    if origin.field == LocalField::Text
                        && !state.manual_fields.contains(&origin.field) => {}
                _ => return Err(ContractError::StorageCorrupt),
            }
        }
        if state
            .manual_fields
            .iter()
            .any(|field| !seen.contains(field))
        {
            return Err(ContractError::StorageCorrupt);
        }
        state.pending_intent = self.local_pending(a)?;
        Ok(state)
    }
    pub fn read_local_form(&self, a: &LocalAccess) -> Result<FormState> {
        let tx = sql(self.database().transaction())?;
        let kind = self.local_binding(&tx, a, ArtifactProjectOperation::ReadOwnLocal)?;
        let LocalKind::Form(spec) = kind else {
            return Err(ContractError::UnsupportedOperation);
        };
        let state = self.form_state(a, &spec)?;
        self.local_binding(&tx, a, ArtifactProjectOperation::ReadOwnLocal)?;
        sql(tx.commit())?;
        Ok(state)
    }
    fn feedback_state(&self, a: &LocalAccess) -> Result<FeedbackState> {
        let rows=sql(self.database().query("SELECT CASE WHEN length(CAST(revision AS BLOB))<=20 THEN revision ELSE NULL END,CASE WHEN length(CAST(payload AS BLOB))<=8192 THEN payload ELSE NULL END FROM artifact_local_feedback_v1 WHERE project_id=? AND actor_id=? AND object_id=?",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id]))?;
        if let Some(row) = rows.first() {
            let mut state: FeedbackState = decode(cell(row, 1)?)?;
            if state.revision.as_str() != cell(row, 0)? {
                return Err(ContractError::StorageCorrupt);
            }
            state.pending_intent = self.local_pending(a)?;
            Ok(state)
        } else {
            Ok(FeedbackState {
                revision: Revision::new(0),
                value: None,
                pending_intent: self.local_pending(a)?,
            })
        }
    }
    pub fn read_local_feedback(&self, a: &LocalAccess) -> Result<FeedbackState> {
        let tx = sql(self.database().transaction())?;
        if self.local_binding(&tx, a, ArtifactProjectOperation::ReadOwnLocal)?
            != LocalKind::Feedback
        {
            return Err(ContractError::UnsupportedOperation);
        }
        let state = self.feedback_state(a)?;
        self.local_binding(&tx, a, ArtifactProjectOperation::ReadOwnLocal)?;
        sql(tx.commit())?;
        Ok(state)
    }
    pub fn prepare_local_form_submit_trusted(
        &self,
        intent: &str,
        a: &LocalAccess,
        expected: &Revision,
    ) -> Result<LocalPreview> {
        identifier(intent)?;
        let result = (|| {
            let tx = sql(self.database().transaction())?;
            let LocalKind::Form(spec) =
                self.local_binding(&tx, a, ArtifactProjectOperation::LocalSubmit)?
            else {
                return Err(ContractError::UnsupportedOperation);
            };
            self.artifact_project_authorize(
                &tx,
                &a.project,
                ArtifactProjectOperation::ReadOwnLocal,
            )?;
            let state = self.form_state(a, &spec)?;
            if &state.revision != expected {
                return Err(ContractError::RevisionConflict);
            }
            if state.submitted_intent.is_some() || state.pending_intent.is_some() {
                return Err(ContractError::IntentConflict);
            }
            let request = Request {
                intent: intent.into(),
                scope: a.project.scope.clone(),
                actor: a.project.actor_id.clone(),
                object: a.object.clone(),
                command: Command::Confirm {
                    expected: expected.clone(),
                    values: state.values.clone(),
                    spec: spec.clone(),
                },
                confirmation: Some(ReviewAuthority::current(a)),
            };
            let (json, digest) = request.binding()?;
            let rows=sql(self.database().query("SELECT CASE WHEN length(CAST(request_json AS BLOB))<=16384 THEN request_json ELSE NULL END FROM artifact_local_reviews_v1 WHERE intent_id=?",&[intent]))?;
            if let Some(row) = rows.first() {
                if cell(row, 0)? != json {
                    return Err(ContractError::IntentConflict);
                }
            } else {
                sql(self.database().exec(
                    "INSERT INTO artifact_local_reviews_v1 VALUES(?,?,?,?,?)",
                    &[
                        intent,
                        a.project.project_id()?,
                        &a.project.actor_id,
                        &json,
                        &digest,
                    ],
                ))?;
            }
            if self.local_binding(&tx, a, ArtifactProjectOperation::LocalSubmit)?
                != LocalKind::Form(spec.clone())
            {
                return Err(ContractError::BindingMismatch);
            }
            self.artifact_project_authorize(
                &tx,
                &a.project,
                ArtifactProjectOperation::ReadOwnLocal,
            )?;
            sql(tx.commit())?;
            Ok(LocalPreview {
                intent_id: intent.into(),
                digest,
                object: a.object.clone(),
                revision: expected.clone(),
                values: state.values,
            })
        })();
        match result {
            Err(error) if requires_original_lookup(&error) => Err(ContractError::Unknown),
            other => other,
        }
    }
    /// Read original preview only; never submit/rebuild it after an uncertain write.
    pub fn lookup_local_form_preview(&self, intent: &str, a: &LocalAccess) -> Result<LocalPreview> {
        identifier(intent)?;
        let result = (|| {
            let tx = sql(self.database().transaction())?;
            self.local_binding(&tx, a, ArtifactProjectOperation::ReadOwnLocal)?;
            let rows=sql(self.database().query("SELECT CASE WHEN length(CAST(request_json AS BLOB))<=16384 THEN request_json ELSE NULL END,CASE WHEN length(CAST(digest AS BLOB))<=64 THEN digest ELSE NULL END FROM artifact_local_reviews_v1 WHERE intent_id=? AND project_id=? AND actor_id=?",&[intent,a.project.project_id()?,&a.project.actor_id]))?;
            let row = rows.first().ok_or(ContractError::NotFound)?;
            let request: Request = decode(cell(row, 0)?)?;
            self.local_project(&request, a)?;
            let digest = request.binding()?.1;
            if request.intent != intent || cell(row, 1)? != digest {
                return Err(ContractError::StorageCorrupt);
            }
            let Command::Confirm {
                expected, values, ..
            } = request.command
            else {
                return Err(ContractError::StorageCorrupt);
            };
            self.local_binding(&tx, a, ArtifactProjectOperation::ReadOwnLocal)?;
            sql(tx.commit())?;
            Ok(LocalPreview {
                intent_id: intent.into(),
                digest,
                object: a.object.clone(),
                revision: expected,
                values,
            })
        })();
        match result {
            Err(error) if requires_original_lookup(&error) => Err(ContractError::Unknown),
            other => other,
        }
    }
    pub fn confirm_local_form_submit_trusted(
        &self,
        intent: &str,
        a: &LocalAccess,
        digest: &str,
    ) -> Result<LocalOutcome> {
        identifier(intent)?;
        let result = (|| {
            let request = {
                let tx = sql(self.database().transaction())?;
                self.local_binding(&tx, a, ArtifactProjectOperation::LocalSubmit)?;
                let rows=sql(self.database().query("SELECT CASE WHEN length(CAST(request_json AS BLOB))<=16384 THEN request_json ELSE NULL END,CASE WHEN length(CAST(digest AS BLOB))<=64 THEN digest ELSE NULL END FROM artifact_local_reviews_v1 WHERE intent_id=? AND project_id=? AND actor_id=?",&[intent,a.project.project_id()?,&a.project.actor_id]))?;
                let row = rows.first().ok_or(ContractError::NotFound)?;
                let request: Request = decode(cell(row, 0)?)?;
                if cell(row, 1)? != digest
                    || request.binding()?.1 != digest
                    || request.object != a.object
                    || request.intent != intent
                    || request.scope != a.project.scope
                    || request.actor != a.project.actor_id
                    || request.confirmation != Some(ReviewAuthority::current(a))
                    || !matches!(request.command, Command::Confirm { .. })
                {
                    return Err(ContractError::BindingMismatch);
                }
                self.local_binding(&tx, a, ArtifactProjectOperation::LocalSubmit)?;
                sql(tx.commit())?;
                request
            };
            self.local_submit(a, request)
        })();
        match result {
            Err(error) if requires_original_lookup(&error) => Ok(LocalOutcome::failure(error)),
            other => other,
        }
    }
    pub fn mutate_local_trusted(
        &self,
        intent: &str,
        a: &LocalAccess,
        mutation: &LocalMutation,
    ) -> Result<LocalOutcome> {
        identifier(intent)?;
        a.object.validate()?;
        if let LocalMutation::Patch {
            changes, author, ..
        } = mutation
        {
            author.validate()?;
            if let AnnotationAuthor::Human { actor_id } = author {
                if actor_id != &a.project.actor_id {
                    return Err(ContractError::InvalidAuthority);
                }
            }
            if changes.is_empty() || changes.len() > 3 {
                return Err(ContractError::InvalidPayload);
            }
            let mut fields = changes.iter().map(FieldChange::field).collect::<Vec<_>>();
            fields.sort();
            fields.dedup();
            if fields.len() != changes.len() {
                return Err(ContractError::InvalidPayload);
            }
        }
        self.local_submit(
            a,
            Request {
                intent: intent.into(),
                scope: a.project.scope.clone(),
                actor: a.project.actor_id.clone(),
                object: a.object.clone(),
                command: Command::Mutation {
                    mutation: mutation.clone(),
                },
                confirmation: None,
            },
        )
    }
    fn local_project(&self, request: &Request, a: &LocalAccess) -> Result<()> {
        if request.scope != a.project.scope
            || request.actor != a.project.actor_id
            || request.object != a.object
        {
            Err(ContractError::BindingMismatch)
        } else {
            Ok(())
        }
    }
    fn local_projection(
        &self,
        intent: &str,
        row: &[Option<String>],
        p: &ArtifactProjectAccess,
    ) -> Result<LocalOutcome> {
        let request: Request = decode(cell(row, 1)?)?;
        let digest = request.binding()?.1;
        if request.intent != intent || cell(row, 0)? != digest {
            return Err(ContractError::StorageCorrupt);
        }
        if request.scope != p.scope || request.actor != p.actor_id {
            return Err(ContractError::InvalidAuthority);
        }
        match cell(row, 2)? {
            "pending" => Ok(LocalOutcome::failure(ContractError::Unknown)),
            "committed" => {
                let receipt: LocalReceipt = decode(cell(row, 3)?)?;
                if receipt.intent_id != intent
                    || receipt.digest != digest
                    || receipt.object != request.object
                    || receipt.revision != request.expected().next()?
                    || receipt.result != request.result()
                {
                    return Err(ContractError::StorageCorrupt);
                }
                Ok(LocalOutcome {
                    status: ArtifactSaveStatus::Committed,
                    receipt: Some(receipt),
                    error: None,
                    recovery_action: RecoveryAction::None,
                })
            }
            "rejected" => {
                let error: ContractError = decode(cell(row, 4)?)?;
                if requires_original_lookup(&error) {
                    return Err(ContractError::StorageCorrupt);
                }
                Ok(LocalOutcome {
                    status: ArtifactSaveStatus::Rejected,
                    receipt: None,
                    error: Some(error),
                    recovery_action: RecoveryAction::None,
                })
            }
            _ => Err(ContractError::StorageCorrupt),
        }
    }
    fn local_submit(&self, a: &LocalAccess, request: Request) -> Result<LocalOutcome> {
        let result = (|| {
            let (json, digest) = request.binding()?;
            let intent = &request.intent;
            let permission = request.permission();
            {
                let tx = sql(self.database().transaction())?;
                self.local_schema()?;
                self.artifact_project_authorize(&tx, &a.project, permission)?;
                self.local_project(&request, a)?;
                let rows = self.journal_rows(JournalDomain::Local, intent)?;
                if let Some(row) = rows.first() {
                    if cell(row, 0)? != digest || cell(row, 1)? != json {
                        return Err(ContractError::IntentConflict);
                    }
                    let result = self.local_projection(intent, row, &a.project)?;
                    self.artifact_project_authorize(&tx, &a.project, permission)?;
                    sql(tx.commit())?;
                    return Ok(result);
                }
                self.local_binding(&tx, a, permission)?;
                if self.local_pending(a)?.is_some() {
                    return Err(ContractError::IntentConflict);
                }
                self.journal_pending(
                    JournalDomain::Local,
                    intent,
                    a.project.project_id()?,
                    &a.project.actor_id,
                    &digest,
                    &json,
                    &a.object.object_id,
                )?;
                self.local_binding(&tx, a, permission)?;
                sql(tx.commit())?;
            }
            let outcome = (|| -> std::result::Result<LocalOutcome, ArtifactSaveFailure> {
                let tx = sql(self.database().transaction())?;
                let kind = self.local_binding(&tx, a, permission)?;
                let rows = self.journal_rows(JournalDomain::Local, intent)?;
                let row = rows.first().ok_or(ContractError::StorageCorrupt)?;
                if cell(row, 0)? != digest || cell(row, 1)? != json || cell(row, 2)? != "pending" {
                    return Err(ContractError::IntentConflict.into());
                }
                let revision = self.local_effect(&request, a, &kind)?;
                let receipt = LocalReceipt {
                    intent_id: intent.clone(),
                    digest: digest.clone(),
                    object: a.object.clone(),
                    revision,
                    result: request.result(),
                };
                self.journal_commit_receipt(
                    JournalDomain::Local,
                    intent,
                    &digest,
                    &encode(&receipt)?,
                )
                .map_err(ArtifactSaveFailure::ReceiptTail)?;
                let tail_kind = self
                    .local_binding(&tx, a, permission)
                    .map_err(ArtifactSaveFailure::ReceiptTail)?;
                if tail_kind != kind {
                    return Err(ArtifactSaveFailure::ReceiptTail(
                        ContractError::BindingMismatch,
                    ));
                }
                self.artifact_project_authorize(&tx, &a.project, permission)
                    .map_err(ArtifactSaveFailure::ReceiptTail)?;
                sql(tx.commit())?;
                Ok(LocalOutcome {
                    status: ArtifactSaveStatus::Committed,
                    receipt: Some(receipt),
                    error: None,
                    recovery_action: RecoveryAction::None,
                })
            })();
            match outcome {
                Ok(result) => Ok(result),
                Err(failure) => {
                    let result = self.journal_failure_outcome(
                        JournalDomain::Local,
                        intent,
                        &digest,
                        failure,
                    )?;
                    Ok(LocalOutcome {
                        status: result.status,
                        receipt: None,
                        error: result.error,
                        recovery_action: result.recovery_action,
                    })
                }
            }
        })();
        match result {
            Err(error) if requires_original_lookup(&error) => Ok(LocalOutcome::failure(error)),
            other => other,
        }
    }
    fn local_effect(
        &self,
        request: &Request,
        a: &LocalAccess,
        kind: &LocalKind,
    ) -> Result<Revision> {
        let expected = request.expected();
        let next = expected.next()?;
        match (&request.command, kind) {
            (
                Command::Mutation {
                    mutation:
                        LocalMutation::Patch {
                            changes, author, ..
                        },
                },
                LocalKind::Form(spec),
            ) => {
                let mut state = self.form_state(a, spec)?;
                if &state.revision != expected {
                    return Err(ContractError::RevisionConflict);
                }
                if state.submitted_intent.is_some() {
                    return Err(ContractError::IntentConflict);
                }
                for change in changes {
                    let field = change.field();
                    if matches!(author, AnnotationAuthor::Ai { .. }) && field != LocalField::Text {
                        return Err(ContractError::UnsupportedOperation);
                    }
                    if !spec.fields.contains(&field) {
                        return Err(ContractError::InvalidPayload);
                    }
                    if matches!(author, AnnotationAuthor::Ai { .. })
                        && state.manual_fields.contains(&field)
                    {
                        return Err(ContractError::IntentConflict);
                    }
                    match change {
                        FieldChange::Text { value } => state.values.text = value.clone(),
                        FieldChange::Choice { value } => state.values.choice = value.clone(),
                        FieldChange::Selections { values } => {
                            state.values.selections = values.clone()
                        }
                    };
                    if let Some(origin) = state
                        .field_origins
                        .iter_mut()
                        .find(|origin| origin.field == field)
                    {
                        origin.author = author.clone();
                    } else {
                        state.field_origins.push(FieldOrigin {
                            field,
                            author: author.clone(),
                        });
                    }
                    if matches!(author, AnnotationAuthor::Human { .. })
                        && !state.manual_fields.contains(&field)
                    {
                        state.manual_fields.push(field);
                    }
                }
                spec.values(&state.values)?;
                state.manual_fields.sort();
                state.field_origins.sort_by_key(|origin| origin.field);
                state.revision = next.clone();
                state.modified_by = Some(author.clone());
                state.pending_intent = None;
                self.local_put_form(a, expected, &state)?;
            }
            (
                Command::Confirm {
                    values,
                    spec: frozen_spec,
                    ..
                },
                LocalKind::Form(spec),
            ) => {
                if frozen_spec != spec {
                    return Err(ContractError::BindingMismatch);
                }
                let mut state = self.form_state(a, spec)?;
                if &state.revision != expected || state.values != *values {
                    return Err(ContractError::RevisionConflict);
                }
                if state.submitted_intent.is_some() {
                    return Err(ContractError::IntentConflict);
                }
                state.revision = next.clone();
                state.submitted_intent = Some(request.intent.clone());
                state.pending_intent = None;
                self.local_put_form(a, expected, &state)?;
            }
            (
                Command::Mutation {
                    mutation: LocalMutation::React { value, .. },
                },
                LocalKind::Feedback,
            ) => {
                let old = self.feedback_state(a)?;
                if &old.revision != expected {
                    return Err(ContractError::RevisionConflict);
                }
                let state = FeedbackState {
                    revision: next.clone(),
                    value: *value,
                    pending_intent: None,
                };
                if expected.value()==0 {sql(self.database().exec("INSERT INTO artifact_local_feedback_v1 VALUES(?,?,?,?,?)",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id,next.as_str(),&encode(&state)?]))?;}
                else if sql(self.database().exec("UPDATE artifact_local_feedback_v1 SET revision=?,payload=? WHERE project_id=? AND actor_id=? AND object_id=? AND revision=?",&[next.as_str(),&encode(&state)?,a.project.project_id()?,&a.project.actor_id,&a.object.object_id,expected.as_str()]))?!=1{return Err(ContractError::RevisionConflict);}
            }
            _ => return Err(ContractError::UnsupportedOperation),
        }
        Ok(next)
    }
    fn local_put_form(
        &self,
        a: &LocalAccess,
        expected: &Revision,
        state: &FormState,
    ) -> Result<()> {
        let payload = encode(state)?;
        if payload.len() > 16384 {
            return Err(ContractError::TextLimit);
        }
        if expected.value()==0 {sql(self.database().exec("INSERT INTO artifact_local_forms_v1 VALUES(?,?,?,?,?)",&[a.project.project_id()?,&a.project.actor_id,&a.object.object_id,state.revision.as_str(),&payload]))?;}
        else if sql(self.database().exec("UPDATE artifact_local_forms_v1 SET revision=?,payload=? WHERE project_id=? AND actor_id=? AND object_id=? AND revision=?",&[state.revision.as_str(),&payload,a.project.project_id()?,&a.project.actor_id,&a.object.object_id,expected.as_str()]))?!=1{return Err(ContractError::RevisionConflict);}
        Ok(())
    }
    pub fn lookup_local_intent(
        &self,
        intent: &str,
        p: &ArtifactProjectAccess,
    ) -> Result<LocalOutcome> {
        identifier(intent)?;
        let result = (|| {
            let tx = sql(self.database().transaction())?;
            self.local_schema()?;
            self.artifact_project_authorize(&tx, p, ArtifactProjectOperation::ReadOwnLocal)?;
            let rows=sql(self.database().query("SELECT CASE WHEN length(CAST(binding_digest AS BLOB))<=64 THEN binding_digest ELSE NULL END,CASE WHEN length(CAST(request_json AS BLOB))<=65536 THEN request_json ELSE NULL END,CASE WHEN length(CAST(status AS BLOB))<=16 THEN status ELSE NULL END,CASE WHEN length(CAST(receipt_json AS BLOB))<=8192 THEN receipt_json ELSE NULL END,CASE WHEN length(CAST(error AS BLOB))<=128 THEN error ELSE NULL END FROM artifact_local_intents_v1 WHERE intent_id=? AND project_id=? AND actor_id=?",&[intent,p.project_id()?,&p.actor_id]))?;
            let result = if let Some(row) = rows.first() {
                self.local_projection(intent, row, p)?
            } else {
                LocalOutcome::failure(ContractError::NotFound)
            };
            self.artifact_project_authorize(&tx, p, ArtifactProjectOperation::ReadOwnLocal)?;
            sql(tx.commit())?;
            Ok(result)
        })();
        match result {
            Err(error) if requires_original_lookup(&error) => Ok(LocalOutcome::failure(error)),
            other => other,
        }
    }
}
#[cfg(test)]
mod tests;

#[cfg(test)]
mod source_tests;
