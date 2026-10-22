//! Android business wire v1. Validation is pure: a decoded grant is never authority.
use serde::{
    de::{self, MapAccess, SeqAccess, Visitor},
    Deserialize, Deserializer, Serialize,
};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{collections::BTreeMap, fmt};
use unicode_normalization::UnicodeNormalization;

pub const PROTOCOL_VERSION: u32 = 1;
pub const BUSINESS_VERSION: u32 = 1;
pub const MAX_COMMAND_BYTES: usize = 1_048_576;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ContractError {
    InvalidJson,
    InvalidVersion,
    InvalidIdentity,
    InvalidRevision,
    InvalidPayload,
    InvalidXml,
    RawLimit,
    Required,
    TextLimit,
    UnsupportedOperation,
    ScopeMismatch,
    InvalidDigest,
    InvalidAuthority,
    BindingMismatch,
    IntentConflict,
    RevisionConflict,
    NotFound,
    Cancelled,
    Unknown,
    Storage,
    StorageBusy,
    StorageConstraint,
    StorageCorrupt,
    StorageIo,
    Unsupported,
}
impl fmt::Display for ContractError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{self:?}")
    }
}
impl std::error::Error for ContractError {}

/// Decimal wire text avoids Kotlin/JavaScript floating-point truncation.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(transparent)]
pub struct Revision(String);
impl Ord for Revision {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.value().cmp(&other.value())
    }
}
impl PartialOrd for Revision {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}
impl Revision {
    pub fn new(value: u64) -> Self {
        Self(value.to_string())
    }
    pub fn parse(value: &str) -> Result<Self, ContractError> {
        if value.is_empty()
            || !value.bytes().all(|b| b.is_ascii_digit())
            || (value.len() > 1 && value.starts_with('0'))
            || value.parse::<u64>().is_err()
        {
            return Err(ContractError::InvalidRevision);
        }
        Ok(Self(value.into()))
    }
    pub fn value(&self) -> u64 {
        self.0.parse().expect("validated revision")
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
    pub fn next(&self) -> Result<Self, ContractError> {
        self.value()
            .checked_add(1)
            .map(Self::new)
            .ok_or(ContractError::InvalidRevision)
    }
}
impl<'de> Deserialize<'de> for Revision {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        Self::parse(&String::deserialize(d)?).map_err(de::Error::custom)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Scope {
    pub workspace_id: String,
    pub project_id: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AuthorityBinding {
    pub grant_id: String,
    pub generation: Revision,
    pub owner_epoch: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SupplierPayload {
    pub name: String,
    pub aliases: Vec<String>,
    pub address: Option<String>,
    pub categories: Vec<String>,
    pub notes: Option<String>,
    pub merged_into: Option<String>,
    #[serde(default)]
    pub rating: Option<String>,
    #[serde(default)]
    pub rating_note: Option<String>,
}
impl SupplierPayload {
    pub fn normalize(&self) -> Result<Self, ContractError> {
        if self.merged_into.is_some() {
            return Err(ContractError::UnsupportedOperation);
        }
        if self
            .rating
            .as_deref()
            .is_some_and(|v| !["preferred", "caution", "disabled"].contains(&v))
        {
            return Err(ContractError::InvalidPayload);
        }
        Ok(Self {
            name: normalize_text(&self.name, 200, true)?.unwrap(),
            aliases: normalize_list(&self.aliases, 20, 200)?,
            address: normalize_optional(&self.address, 500)?,
            categories: normalize_list(&self.categories, 20, 100)?,
            notes: normalize_optional(&self.notes, 2000)?,
            merged_into: None,
            rating: self.rating.clone(),
            rating_note: normalize_optional(&self.rating_note, 500)?,
        })
    }
}

/// The whole raw string is checked before trimming. No caller-side preprocessing.
pub fn normalize_name(raw: &[u16]) -> Result<String, ContractError> {
    if raw.len() > 2000 {
        return Err(ContractError::RawLimit);
    }
    let text = String::from_utf16(raw).map_err(|_| ContractError::InvalidXml)?;
    Ok(normalize_text(&text, 200, true)?.unwrap())
}
pub fn normalize_text(
    raw: &str,
    limit: usize,
    required: bool,
) -> Result<Option<String>, ContractError> {
    if raw.encode_utf16().count() > limit * 10 {
        return Err(ContractError::RawLimit);
    }
    if !raw.chars().all(
        |c| matches!(c as u32, 9 | 10 | 13 | 0x20..=0xd7ff | 0xe000..=0xfffd | 0x10000..=0x10ffff),
    ) {
        return Err(ContractError::InvalidXml);
    }
    let value: String = raw
        .trim_matches(|c: char| c.is_whitespace() || c == '\u{feff}')
        .nfc()
        .collect();
    if value.is_empty() {
        return if required {
            Err(ContractError::Required)
        } else {
            Ok(None)
        };
    }
    if value.chars().count() > limit {
        return Err(ContractError::TextLimit);
    }
    Ok(Some(value))
}
fn normalize_optional(
    value: &Option<String>,
    limit: usize,
) -> Result<Option<String>, ContractError> {
    value
        .as_ref()
        .map(|v| normalize_text(v, limit, false))
        .transpose()
        .map(Option::flatten)
}
fn normalize_list(
    values: &[String],
    count: usize,
    limit: usize,
) -> Result<Vec<String>, ContractError> {
    if values.len() > count {
        return Err(ContractError::TextLimit);
    }
    let mut result = values
        .iter()
        .map(|v| normalize_text(v, limit, true).map(Option::unwrap))
        .collect::<Result<Vec<_>, _>>()?;
    result.sort();
    result.dedup();
    Ok(result)
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BlobRef {
    pub digest: String,
    pub byte_length: Revision,
}
impl BlobRef {
    pub fn validate(&self) -> Result<(), ContractError> {
        digest(&self.digest)?;
        if self.byte_length.value() == 0 || self.byte_length.value() > 268_435_456 {
            return Err(ContractError::TextLimit);
        }
        Ok(())
    }
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PaperPayload {
    pub title: String,
    #[serde(default)]
    pub authors: Vec<String>,
    pub year: Option<u16>,
    pub doi: Option<String>,
    pub url: Option<String>,
    pub notes: Option<String>,
    pub attachment: BlobRef,
    #[serde(default)]
    pub attachment_upload_id: Option<String>,
}
impl PaperPayload {
    pub fn validate(&self) -> Result<(), ContractError> {
        if let Some(upload_id) = &self.attachment_upload_id {
            identity(upload_id)?;
        }
        normalize_text(&self.title, 500, true)?;
        normalize_list(&self.authors, 100, 200)?;
        normalize_optional(&self.doi, 500)?;
        normalize_optional(&self.url, 2000)?;
        normalize_optional(&self.notes, 2000)?;
        if self.year.is_some_and(|y| y == 0 || y > 9999) {
            return Err(ContractError::InvalidPayload);
        }
        if self.attachment.byte_length.value() > 30 * 1024 * 1024 {
            return Err(ContractError::TextLimit);
        }
        self.attachment.validate()
    }
}
/// Imported JSON remains opaque data; no metadata field grants a capability.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ImportedPaper {
    pub source_id: String,
    pub source_revision: Revision,
    pub record: Value,
    pub raw_json: String,
    pub attachments: Vec<BlobRef>,
    #[serde(default)]
    pub attachment_upload_ids: BTreeMap<String, String>,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum Operation {
    SupplierCreate {
        supplier_id: String,
        payload: SupplierPayload,
    },
    SupplierUpdate {
        supplier_id: String,
        payload: SupplierPayload,
    },
    SupplierDelete {
        supplier_id: String,
    },
    SupplierRestore {
        supplier_id: String,
    },
    ProjectCreate {
        project_id: String,
        name: String,
    },
    PaperCreate {
        paper_id: String,
        payload: PaperPayload,
    },
    ResearchImport {
        source_id: String,
        source_revision: Revision,
        snapshot: BlobRef,
        #[serde(default)]
        snapshot_upload_id: Option<String>,
        #[serde(default)]
        records: Vec<ImportedPaper>,
    },
    BlobPin {
        blob: BlobRef,
    },
    BlobRelease {
        blob: BlobRef,
    },
}
impl Operation {
    pub fn target_id(&self) -> &str {
        match self {
            Self::SupplierCreate { supplier_id, .. }
            | Self::SupplierUpdate { supplier_id, .. }
            | Self::SupplierDelete { supplier_id }
            | Self::SupplierRestore { supplier_id } => supplier_id,
            Self::ProjectCreate { project_id, .. } => project_id,
            Self::PaperCreate { paper_id, .. } => paper_id,
            Self::ResearchImport { source_id, .. } => source_id,
            Self::BlobPin { blob } | Self::BlobRelease { blob } => &blob.digest,
        }
    }
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CommandEnvelope {
    pub protocol_version: u32,
    pub business_version: u32,
    pub intent_id: String,
    pub scope: Scope,
    pub expected_revision: Revision,
    pub authority: AuthorityBinding,
    pub plan_id: String,
    pub plan_digest: String,
    pub command: Operation,
}
impl CommandEnvelope {
    pub fn decode(raw: &str) -> Result<Self, ContractError> {
        let value = decode_json(raw)?;
        let command: Self =
            serde_json::from_value(value).map_err(|_| ContractError::InvalidPayload)?;
        command.validate()?;
        Ok(command)
    }
    pub fn validate(&self) -> Result<(), ContractError> {
        if self.protocol_version != PROTOCOL_VERSION || self.business_version != BUSINESS_VERSION {
            return Err(ContractError::InvalidVersion);
        }
        for id in [
            &self.intent_id,
            &self.scope.workspace_id,
            &self.authority.grant_id,
            &self.authority.owner_epoch,
            &self.plan_id,
        ] {
            identity(id)?;
        }
        if let Some(project) = &self.scope.project_id {
            identity(project)?;
        }
        if self.authority.generation.value() == 0 {
            return Err(ContractError::InvalidAuthority);
        }
        digest(&self.plan_digest)?;
        identity(self.command.target_id())?;
        match &self.command {
            Operation::SupplierCreate { payload, .. }
            | Operation::SupplierUpdate { payload, .. } => {
                payload.normalize()?;
            }
            Operation::ProjectCreate { project_id, name } => {
                normalize_text(name, 200, true)?;
                if self
                    .scope
                    .project_id
                    .as_deref()
                    .is_some_and(|p| p != project_id)
                {
                    return Err(ContractError::ScopeMismatch);
                }
            }
            Operation::PaperCreate { payload, .. } => {
                self.require_project()?;
                payload.validate()?;
            }
            Operation::ResearchImport {
                source_id,
                snapshot,
                snapshot_upload_id,
                records,
                ..
            } => {
                self.require_project()?;
                if let Some(upload_id) = snapshot_upload_id {
                    identity(upload_id)?;
                }
                identity(source_id)?;
                snapshot.validate()?;
                if snapshot.byte_length.value() > 150 * 1024 * 1024 {
                    return Err(ContractError::TextLimit);
                }
                if records.len() > 10_000 {
                    return Err(ContractError::TextLimit);
                }
                for record in records {
                    identity(&record.source_id)?;
                    if !record.record.is_object() || record.attachments.len() > 100 {
                        return Err(ContractError::InvalidPayload);
                    }
                    if decode_json(&record.raw_json)? != record.record {
                        return Err(ContractError::BindingMismatch);
                    }
                    for blob in &record.attachments {
                        blob.validate()?;
                    }
                    for (blob_digest, upload_id) in &record.attachment_upload_ids {
                        digest(blob_digest)?;
                        identity(upload_id)?;
                        if !record
                            .attachments
                            .iter()
                            .any(|blob| &blob.digest == blob_digest)
                        {
                            return Err(ContractError::BindingMismatch);
                        }
                    }
                }
            }
            Operation::BlobPin { blob } | Operation::BlobRelease { blob } => blob.validate()?,
            _ => {}
        }
        let create = matches!(
            self.command,
            Operation::SupplierCreate { .. }
                | Operation::ProjectCreate { .. }
                | Operation::PaperCreate { .. }
        );
        if (create && self.expected_revision.value() != 0)
            || (!create && self.expected_revision.value() == u64::MAX)
        {
            return Err(ContractError::InvalidRevision);
        }
        if matches!(
            self.command,
            Operation::SupplierUpdate { .. }
                | Operation::SupplierDelete { .. }
                | Operation::SupplierRestore { .. }
        ) && self.expected_revision.value() == 0
        {
            return Err(ContractError::InvalidRevision);
        }
        if self.plan_digest != self.expected_plan_digest()? {
            return Err(ContractError::BindingMismatch);
        }
        Ok(())
    }
    fn require_project(&self) -> Result<(), ContractError> {
        if self.scope.project_id.is_none() {
            Err(ContractError::ScopeMismatch)
        } else {
            Ok(())
        }
    }
    /// Plan hash excludes grant, intent and its own digest; binds raw parameters and revision.
    pub fn expected_plan_digest(&self) -> Result<String, ContractError> {
        stable_digest(
            &serde_json::json!({"protocol_version":self.protocol_version,"business_version":self.business_version,"scope":self.scope,"expected_revision":self.expected_revision,"command":self.command}),
        )
    }
    /// Full retry identity: includes raw values, intent, grant, scope and plan.
    pub fn binding_digest(&self) -> Result<String, ContractError> {
        self.validate()?;
        if self.plan_digest != self.expected_plan_digest()? {
            return Err(ContractError::BindingMismatch);
        }
        stable_digest(&serde_json::to_value(self).map_err(|_| ContractError::InvalidPayload)?)
    }
}

fn identity(value: &str) -> Result<(), ContractError> {
    if value.is_empty()
        || value.len() > 128
        || !value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
    {
        Err(ContractError::InvalidIdentity)
    } else {
        Ok(())
    }
}
fn digest(value: &str) -> Result<(), ContractError> {
    if value.len() != 64
        || !value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        Err(ContractError::InvalidDigest)
    } else {
        Ok(())
    }
}

/// Recursive sorted JSON keys, UTF-8, no whitespace. JSON metadata numbers retain
/// serde_json's finite number representation; revisions always use decimal text.
pub fn stable_digest(value: &Value) -> Result<String, ContractError> {
    fn canonical(v: &Value) -> Result<Value, ContractError> {
        match v {
            Value::Object(map) => {
                let sorted: BTreeMap<_, _> = map
                    .iter()
                    .map(|(k, v)| Ok((k.clone(), canonical(v)?)))
                    .collect::<Result<_, ContractError>>()?;
                Ok(Value::Object(sorted.into_iter().collect()))
            }
            Value::Array(items) => Ok(Value::Array(
                items.iter().map(canonical).collect::<Result<_, _>>()?,
            )),
            _ => Ok(v.clone()),
        }
    }
    let bytes =
        serde_json::to_vec(&canonical(value)?).map_err(|_| ContractError::InvalidPayload)?;
    Ok(Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect())
}

/// Parse before typed decoding so duplicate fields cannot disappear into Value.
pub fn decode_json(raw: &str) -> Result<Value, ContractError> {
    decode_json_with_limit(raw, MAX_COMMAND_BYTES)
}
pub(crate) fn decode_research_json(raw: &str) -> Result<Value, ContractError> {
    decode_json_with_limit(raw, 30 * 1024 * 1024)
}
fn decode_json_with_limit(raw: &str, limit: usize) -> Result<Value, ContractError> {
    if raw.len() > limit {
        return Err(ContractError::TextLimit);
    }
    let mut decoder = serde_json::Deserializer::from_str(raw);
    let value = StrictValue::deserialize(&mut decoder)
        .map_err(|_| ContractError::InvalidJson)?
        .0;
    decoder.end().map_err(|_| ContractError::InvalidJson)?;
    Ok(value)
}
struct StrictValue(Value);
impl<'de> Deserialize<'de> for StrictValue {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct StrictVisitor;
        impl<'de> Visitor<'de> for StrictVisitor {
            type Value = StrictValue;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("bounded JSON without duplicate keys")
            }
            fn visit_bool<E: de::Error>(self, v: bool) -> Result<Self::Value, E> {
                Ok(StrictValue(v.into()))
            }
            fn visit_i64<E: de::Error>(self, v: i64) -> Result<Self::Value, E> {
                Ok(StrictValue(v.into()))
            }
            fn visit_u64<E: de::Error>(self, v: u64) -> Result<Self::Value, E> {
                Ok(StrictValue(v.into()))
            }
            fn visit_f64<E: de::Error>(self, v: f64) -> Result<Self::Value, E> {
                serde_json::Number::from_f64(v)
                    .map(|n| StrictValue(Value::Number(n)))
                    .ok_or_else(|| E::custom("non-finite number"))
            }
            fn visit_str<E: de::Error>(self, v: &str) -> Result<Self::Value, E> {
                Ok(StrictValue(v.into()))
            }
            fn visit_string<E: de::Error>(self, v: String) -> Result<Self::Value, E> {
                Ok(StrictValue(v.into()))
            }
            fn visit_unit<E: de::Error>(self) -> Result<Self::Value, E> {
                Ok(StrictValue(Value::Null))
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
                let mut values = Vec::new();
                while let Some(value) = seq.next_element::<StrictValue>()? {
                    values.push(value.0);
                }
                Ok(StrictValue(Value::Array(values)))
            }
            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
                let mut values = serde_json::Map::new();
                while let Some(key) = map.next_key::<String>()? {
                    if values.contains_key(&key) {
                        return Err(de::Error::custom("duplicate key"));
                    }
                    values.insert(key, map.next_value::<StrictValue>()?.0);
                }
                Ok(StrictValue(Value::Object(values)))
            }
        }
        d.deserialize_any(StrictVisitor)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExecutionStatus {
    Pending,
    Unknown,
    Committed,
    Rejected,
    Cancelled,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecoveryAction {
    QueryOriginal,
    InspectDependency,
    None,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Receipt {
    pub protocol_version: u32,
    pub intent_id: String,
    pub binding_digest: String,
    pub scope: Scope,
    pub authority: AuthorityBinding,
    pub admission_id: Option<String>,
    pub target_id: String,
    pub revision: Revision,
    pub status: ExecutionStatus,
    pub result: Value,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ExecutionResult {
    pub status: ExecutionStatus,
    pub receipt: Option<Receipt>,
    pub error: Option<ContractError>,
    pub recovery_action: RecoveryAction,
}

impl Receipt {
    /// Validates receipt shape and original command identity, not SQL origin.
    pub fn validate_for(&self, command: &CommandEnvelope) -> Result<(), ContractError> {
        if self.protocol_version != PROTOCOL_VERSION {
            return Err(ContractError::InvalidVersion);
        }
        if self.status != ExecutionStatus::Committed
            || self.intent_id != command.intent_id
            || self.scope != command.scope
            || self.authority != command.authority
            || self.binding_digest != command.binding_digest()?
            || self.target_id != command.command.target_id()
            || self.revision != command.expected_revision.next()?
        {
            return Err(ContractError::BindingMismatch);
        }
        if let Some(id) = &self.admission_id {
            identity(id)?;
        }
        Ok(())
    }
}
impl ExecutionResult {
    pub fn validate(&self) -> Result<(), ContractError> {
        let valid = match self.status {
            ExecutionStatus::Committed => {
                self.receipt
                    .as_ref()
                    .is_some_and(|r| r.status == ExecutionStatus::Committed)
                    && self.error.is_none()
                    && self.recovery_action == RecoveryAction::None
            }
            ExecutionStatus::Pending | ExecutionStatus::Unknown => {
                self.receipt.is_none() && self.recovery_action != RecoveryAction::None
            }
            ExecutionStatus::Rejected => {
                self.receipt.is_none()
                    && self.error.is_some()
                    && self.recovery_action == RecoveryAction::None
            }
            ExecutionStatus::Cancelled => {
                self.receipt.is_none()
                    && self.error == Some(ContractError::Cancelled)
                    && self.recovery_action == RecoveryAction::None
            }
        };
        if valid {
            Ok(())
        } else {
            Err(ContractError::InvalidPayload)
        }
    }
}

/// Opaque capability metadata returned by the trusted file owner; never an
/// arbitrary caller-selected filesystem path. Runtime must resolve the lease.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FileSource {
    pub snapshot_id: String,
    pub blob: BlobRef,
    pub lease: ReadLease,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReadLease {
    pub lease_id: String,
    pub owner_epoch: String,
    pub generation: Revision,
}
impl ReadLease {
    pub fn validate(&self) -> Result<(), ContractError> {
        identity(&self.lease_id)?;
        identity(&self.owner_epoch)?;
        if self.generation.value() == 0 {
            return Err(ContractError::InvalidAuthority);
        }
        Ok(())
    }
}
impl FileSource {
    pub fn validate(&self) -> Result<(), ContractError> {
        identity(&self.snapshot_id)?;
        self.blob.validate()?;
        self.lease.validate()
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArchiveMethod {
    Stored,
    Deflated,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ArchiveEntry {
    pub snapshot_id: String,
    pub name: String,
    pub method: ArchiveMethod,
    pub crc32: u32,
    pub data_offset: Revision,
    pub compressed_length: Revision,
    pub expanded_length: Revision,
}
impl ArchiveEntry {
    /// Only a regular relative member is represented. ZIP producer/type/flags,
    /// CEN/LOC consistency, descriptors and CRC are verified by A01 reader.
    pub fn validate_for(&self, source: &FileSource) -> Result<(), ContractError> {
        source.validate()?;
        if self.snapshot_id != source.snapshot_id {
            return Err(ContractError::BindingMismatch);
        }
        if self.name.is_empty()
            || self.name.len() > 1024
            || self.name.contains(['\\', '\0', ':'])
            || self
                .name
                .split('/')
                .any(|p| p.is_empty() || p == "." || p == "..")
        {
            return Err(ContractError::InvalidPayload);
        }
        let end = self
            .data_offset
            .value()
            .checked_add(self.compressed_length.value())
            .ok_or(ContractError::TextLimit)?;
        if end > source.blob.byte_length.value()
            || self.expanded_length.value() > 30 * 1024 * 1024
            || (self.method == ArchiveMethod::Stored
                && self.compressed_length != self.expanded_length)
        {
            return Err(ContractError::TextLimit);
        }
        Ok(())
    }
}
