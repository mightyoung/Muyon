//! Host-derived schema1 envelope mapping only. Every engine response remains HOLD.
//! No launcher, file path, grant decoder, simulated receipt or commit permit exists.
use super::Binding;
use crate::documents::{DocumentFormat, DocumentMetadata};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    convert::Infallible,
    time::{SystemTime, UNIX_EPOCH},
};
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProtocolError {
    InvalidOperation,
    InvalidResponse,
    BindingMismatch,
    SimulationForbidden,
    Expired,
    EnvironmentHold,
}
#[derive(Clone, Debug, Serialize)]
pub struct NumericCellEdit {
    pub sheet: String,
    pub cell: String,
    pub expected: String,
    pub replacement: String,
}
#[derive(Clone, Debug)]
pub struct PreparedEngineRequest {
    binding: Binding,
    json: String,
    identity: Identity,
    source_hash: String,
    expires_at_ms: u64,
}
impl PreparedEngineRequest {
    pub fn binding(&self) -> &Binding {
        &self.binding
    }
    pub fn request_json(&self) -> &str {
        &self.json
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Identity {
    scope_id: String,
    file_id: String,
    base_revision: String,
    operation_id: String,
    idempotency_key: String,
}
fn hash(bytes: &[u8]) -> [u8; 32] {
    Sha256::digest(bytes).into()
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
fn now() -> Result<u64, ProtocolError> {
    u64::try_from(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| ProtocolError::Expired)?
            .as_millis(),
    )
    .map_err(|_| ProtocolError::Expired)
}
fn identifier(s: &str) -> bool {
    super::opaque_id(s) && s.as_bytes().first().is_some_and(u8::is_ascii_alphanumeric)
}
// Normalize for no-op detection ONLY. The request always preserves original
// decimal spelling: an engine changing5.0 into5 must still be rejected by oracle.
fn numeric(s: &str) -> Option<String> {
    if s.is_empty() || s.len() > 32 {
        return None;
    }
    let body = s.strip_prefix('-').unwrap_or(s);
    let mut split = body.split('.');
    let integer = split.next()?;
    let fraction = split.next();
    if split.next().is_some()
        || integer.is_empty()
        || !integer.bytes().all(|b| b.is_ascii_digit())
        || (integer.len() > 1 && integer.starts_with('0'))
        || fraction.is_some_and(|f| f.is_empty() || !f.bytes().all(|b| b.is_ascii_digit()))
        || body.bytes().filter(u8::is_ascii_digit).count() > 15
    {
        return None;
    }
    let fraction = fraction.unwrap_or("").trim_end_matches('0');
    let value = if fraction.is_empty() {
        integer.into()
    } else {
        format!("{integer}.{fraction}")
    };
    Some(if s.starts_with('-') && value != "0" {
        format!("-{value}")
    } else {
        value
    })
}
fn valid_operation(op: &NumericCellEdit) -> bool {
    if op.sheet.is_empty()
        || op.sheet.chars().count() > 31
        || op
            .sheet
            .chars()
            .any(|c| c.is_control() || "[]:*?/\\".contains(c))
    {
        return false;
    }
    let n = op.cell.bytes().take_while(u8::is_ascii_uppercase).count();
    if !(1..=3).contains(&n) || n >= op.cell.len() {
        return false;
    }
    let row = &op.cell[n..];
    if row.starts_with('0') || !row.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    let Ok(row) = row.parse::<u32>() else {
        return false;
    };
    let column = op.cell[..n]
        .bytes()
        .fold(0u32, |a, b| a * 26 + (b - b'A' + 1) as u32);
    row <= 1_048_576
        && column <= 16_384
        && matches!((numeric(&op.expected),numeric(&op.replacement)),(Some(a),Some(b)) if a!=b)
}
/// Trusted metadata mapping. It produces data, not authority; the gateway wrapper
/// resolves real source/grants before calling this function. No format parsing here.
pub fn prepare_request_trusted(
    source: &DocumentMetadata,
    intent: &str,
    operation: NumericCellEdit,
) -> Result<PreparedEngineRequest, ProtocolError> {
    if source.document.format() != DocumentFormat::Xlsx
        || source.blob.validate().is_err()
        || !identifier(intent)
        || !identifier(source.document.document_id())
        || !valid_operation(&operation)
    {
        return Err(ProtocolError::InvalidOperation);
    }
    let scope =
        serde_json::to_vec(source.document.scope()).map_err(|_| ProtocolError::InvalidOperation)?;
    let mut identity = Identity {
        scope_id: format!("scope:{}", hex(&hash(&scope))),
        file_id: source.document.document_id().into(),
        base_revision: source.document.revision().as_str().into(),
        operation_id: intent.into(),
        idempotency_key: String::new(),
    };
    let operation = serde_json::json!({"kind":"set_numeric_cell","sheet":operation.sheet,"cell":operation.cell,"expected":operation.expected,"replacement":operation.replacement});
    let digest = hash(
        &serde_json::to_vec(&(1, &identity, &source.blob.digest, &operation))
            .map_err(|_| ProtocolError::InvalidOperation)?,
    );
    identity.idempotency_key = format!("op:{}", hex(&digest));
    let request = serde_json::json!({"schema_version":1,"scope_id":identity.scope_id,"file_id":identity.file_id,"base_revision":identity.base_revision,"operation_id":identity.operation_id,"idempotency_key":identity.idempotency_key,"source_sha256":source.blob.digest,"operation":operation});
    Ok(PreparedEngineRequest {
        binding: Binding {
            document: source.document.clone(),
            patch_digest: digest,
            intent_id: intent.into(),
            rollback_target: None,
        },
        json: request.to_string(),
        identity,
        source_hash: source.blob.digest.clone(),
        expires_at_ms: now()?.checked_add(30_000).ok_or(ProtocolError::Expired)?,
    })
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Response {
    schema_version: u32,
    status: String,
    identity: Identity,
    engine_execution: String,
    real_roundtrip: String,
    fake_executor_used: bool,
    fidelity: String,
    safety: String,
    dimensions: Dimensions,
    reasons: Vec<String>,
    #[serde(default)]
    source_sha256: Option<String>,
    #[serde(default)]
    source_manifest: Option<serde_json::Value>,
    #[serde(default)]
    candidate_sha256: Option<String>,
    #[serde(default)]
    candidate_manifest: Option<serde_json::Value>,
    #[serde(default)]
    validation: Option<serde_json::Value>,
    #[serde(default)]
    temporary_candidate_cleaned: Option<bool>,
    #[serde(default)]
    hard_timeout_enforced: Option<bool>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Dimensions {
    render: String,
    recalc: String,
    visual: String,
    annotation: String,
}
/// The return type cannot carry a validated candidate or publication permit.
/// Even a seemingly real matching response remains unavailable under runtime HOLD.
pub fn check_response_held(
    prepared: &PreparedEngineRequest,
    bytes: &[u8],
) -> Result<Infallible, ProtocolError> {
    check_at(prepared, bytes, now()?)
}
fn check_at(
    prepared: &PreparedEngineRequest,
    bytes: &[u8],
    at: u64,
) -> Result<Infallible, ProtocolError> {
    if bytes.len() > 65_536 {
        return Err(ProtocolError::InvalidResponse);
    }
    let r: Response = serde_json::from_slice(bytes).map_err(|_| ProtocolError::InvalidResponse)?;
    if r.schema_version != 1 {
        return Err(ProtocolError::InvalidResponse);
    }
    if r.identity != prepared.identity
        || r.source_sha256
            .as_ref()
            .is_some_and(|s| s != &prepared.source_hash)
    {
        return Err(ProtocolError::BindingMismatch);
    }
    if r.fake_executor_used
        || r.status.starts_with("simulat")
        || [&r.engine_execution, &r.real_roundtrip].iter().any(|v| {
            let lower = v.to_ascii_lowercase();
            lower.contains("simulat") || lower.contains("fake")
        })
    {
        return Err(ProtocolError::SimulationForbidden);
    }
    if r.status == "candidate_validated" && r.source_sha256.is_none() {
        return Err(ProtocolError::InvalidResponse);
    }
    // No manifest/oracle payload schema is admitted under HOLD. Refuse opaque
    // nested fields wholesale rather than ignoring unknown paths/claims inside.
    if r.source_manifest.is_some() || r.candidate_manifest.is_some() || r.validation.is_some() {
        return Err(ProtocolError::InvalidResponse);
    }
    if at >= prepared.expires_at_ms {
        return Err(ProtocolError::Expired);
    }
    if !matches!(
        r.status.as_str(),
        "held" | "rejected" | "failed" | "outcome_unknown" | "candidate_validated"
    ) {
        return Err(ProtocolError::InvalidResponse);
    }
    // Parse diagnostic fields strictly, but never treat their claims as isolation,
    // fidelity, actual engine execution or user-authorized validation evidence.
    let _diagnostics = (
        &r.engine_execution,
        &r.real_roundtrip,
        &r.fidelity,
        &r.safety,
        &r.reasons,
        &r.dimensions.render,
        &r.dimensions.recalc,
        &r.dimensions.visual,
        &r.dimensions.annotation,
        &r.source_manifest,
        &r.candidate_sha256,
        &r.candidate_manifest,
        &r.validation,
        &r.temporary_candidate_cleaned,
        &r.hard_timeout_enforced,
    );
    Err(ProtocolError::EnvironmentHold)
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::contract::Revision;
    #[test]
    fn expired_host_preparation_is_rejected_without_sleep_or_clock_override_api() {
        let source = DocumentMetadata {
            document: crate::documents::DocumentRef::new(
                crate::contract::Scope {
                    workspace_id: "w".into(),
                    project_id: Some("p".into()),
                },
                "d",
                Revision::new(1),
                DocumentFormat::Xlsx,
            )
            .unwrap(),
            title: "synthetic".into(),
            blob: crate::contract::BlobRef {
                digest: "a".repeat(64),
                byte_length: Revision::new(1),
            },
        };
        let p = prepare_request_trusted(
            &source,
            "intent",
            NumericCellEdit {
                sheet: "Original".into(),
                cell: "A1".into(),
                expected: "2".into(),
                replacement: "5".into(),
            },
        )
        .unwrap();
        let response = serde_json::json!({"schema_version":1,"status":"held","identity":p.identity,"engine_execution":"not_run","real_roundtrip":"not_run","fake_executor_used":false,"fidelity":"unknown","safety":"unknown","dimensions":{"render":"not_run","recalc":"not_run","visual":"not_run","annotation":"not_run"},"reasons":["environment_hold"]});
        assert_eq!(
            check_at(&p, &serde_json::to_vec(&response).unwrap(), p.expires_at_ms).unwrap_err(),
            ProtocolError::Expired
        );
    }
}
