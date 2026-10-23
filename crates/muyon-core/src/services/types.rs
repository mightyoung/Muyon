//! Public value contracts. Decoded values never grant authority.
use crate::{
    contract::{Revision, Scope},
    documents::DocumentRef,
};
use serde::{
    de::{self, DeserializeOwned},
    Deserialize, Deserializer, Serialize, Serializer,
};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    InvalidArgument,
    UnsupportedVersion,
    CapabilityUnavailable,
    PermissionDenied,
    StaleRevision,
    ScopeChanged,
    ResourceExpired,
    PartialResult,
    Cancelled,
    UnknownOutcome,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Retryability {
    Never,
    AfterLookup,
    AfterReprepare,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EffectKnowledge {
    NotStarted,
    Confirmed,
    Unknown,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ServiceError {
    pub code: ErrorCode,
    pub phase: String,
    pub retryability: Retryability,
    pub effect_knowledge: EffectKnowledge,
    pub original_intent_id: Option<IntentId>,
    pub safe_message: String,
    pub details_ref: Option<String>,
}
pub(crate) fn invalid() -> ServiceError {
    ServiceError {
        code: ErrorCode::InvalidArgument,
        phase: "decode".into(),
        retryability: Retryability::Never,
        effect_knowledge: EffectKnowledge::NotStarted,
        original_intent_id: None,
        safe_message: "公共合同输入无效。".into(),
        details_ref: None,
    }
}
macro_rules! scalar {
    ($name:ident, $valid:expr) => {
        #[derive(Clone, Debug, PartialEq, Eq, Serialize)]
        #[serde(transparent)]
        pub struct $name(String);
        impl $name {
            pub fn parse(raw: &str) -> Result<Self, ServiceError> {
                if ($valid)(raw) {
                    Ok(Self(raw.into()))
                } else {
                    Err(invalid())
                }
            }
            pub fn as_str(&self) -> &str {
                &self.0
            }
        }
        impl<'de> Deserialize<'de> for $name {
            fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
                Self::parse(&String::deserialize(d)?)
                    .map_err(|_| de::Error::custom("invalid public scalar"))
            }
        }
    };
}
fn opaque(raw: &str) -> bool {
    !raw.is_empty() && raw.len() <= 128 && !raw.contains('\0')
}
scalar!(ResultId, opaque);
scalar!(JobId, opaque);
scalar!(IntentId, opaque);
scalar!(Digest, |raw: &str| raw.len() == 64
    && raw
        .bytes()
        .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)));
scalar!(UnixMs, |raw: &str| raw
    .parse::<i64>()
    .is_ok_and(|value| value.to_string() == raw));
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ScopeRef {
    pub scope: Scope,
    pub account_id: Option<String>,
    pub scope_generation: Revision,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResultRef {
    pub result_id: ResultId,
    pub input_document_ref: DocumentRef,
    pub input_result_refs: Vec<ResultId>,
    pub content_digest: Digest,
    pub producer_version: String,
    pub parameters_digest: Digest,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoverageState {
    Complete,
    Partial,
    Failed,
    Unknown,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "CoverageWire")]
pub struct Coverage {
    pub state: CoverageState,
    #[serde(serialize_with = "serialize_count")]
    pub processed: u64,
    #[serde(serialize_with = "serialize_optional_count")]
    pub total: Option<u64>,
    pub failed_units: Vec<u32>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CoverageWire {
    state: CoverageState,
    #[serde(deserialize_with = "deserialize_count")]
    processed: u64,
    #[serde(deserialize_with = "deserialize_optional_count")]
    total: Option<u64>,
    failed_units: Vec<u32>,
}
impl TryFrom<CoverageWire> for Coverage {
    type Error = &'static str;
    fn try_from(v: CoverageWire) -> Result<Self, Self::Error> {
        if v.total.is_some_and(|n| v.processed > n)
            || (v.state == CoverageState::Complete
                && (v.total != Some(v.processed) || !v.failed_units.is_empty()))
        {
            return Err("inconsistent coverage");
        }
        Ok(Self {
            state: v.state,
            processed: v.processed,
            total: v.total,
            failed_units: v.failed_units,
        })
    }
}
fn serialize_count<S: Serializer>(n: &u64, s: S) -> Result<S::Ok, S::Error> {
    s.serialize_str(&n.to_string())
}
fn serialize_optional_count<S: Serializer>(n: &Option<u64>, s: S) -> Result<S::Ok, S::Error> {
    match n {
        Some(n) => s.serialize_some(&n.to_string()),
        None => s.serialize_none(),
    }
}
fn deserialize_count<'de, D: Deserializer<'de>>(d: D) -> Result<u64, D::Error> {
    Revision::parse(&String::deserialize(d)?)
        .map(|n| n.value())
        .map_err(|_| de::Error::custom("invalid count"))
}
fn deserialize_optional_count<'de, D: Deserializer<'de>>(d: D) -> Result<Option<u64>, D::Error> {
    Option::<String>::deserialize(d)?
        .map(|raw| {
            Revision::parse(&raw)
                .map(|n| n.value())
                .map_err(|_| de::Error::custom("invalid total"))
        })
        .transpose()
}
pub fn negotiate(contract_major: u32, schema_major: u32) -> Result<(), ServiceError> {
    if contract_major == 1 && schema_major == 1 {
        Ok(())
    } else {
        let mut error = invalid();
        error.code = ErrorCode::UnsupportedVersion;
        error.phase = "negotiate".into();
        Err(error)
    }
}
/// Strict transport parsing; T must be a declared DTO with deny_unknown_fields.
/// This validates shape, not the caller's authority or the provenance of data.
pub fn decode_strict<T: DeserializeOwned>(raw: &str) -> Result<T, ServiceError> {
    let value = crate::contract::decode_json(raw).map_err(|_| invalid())?;
    serde_json::from_value(value).map_err(|_| invalid())
}
