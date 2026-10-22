use super::super::{DocumentAccess, DocumentMetadata, DocumentOperation, DocumentRef, reader::DocumentPresentationInfo};
use crate::contract::{ContractError, Revision};
use serde::{Deserialize, Serialize};
pub type PolicyResult<T> = Result<T, ContractError>;
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PolicyScope { pub service_session: String, pub generation: Revision, pub project: String }
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReadingSurfaceBinding { pub surface_id: String, pub lifecycle_epoch: String, pub selection_sequence: Revision }
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all="snake_case")]
pub enum PolicyAvailability { Valid, NaturallyExpired, Revoked, Replaced, Unavailable }
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all="snake_case")]
pub enum PolicyKind { Begin, Renew, Handoff, Stop }
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all="snake_case")]
pub enum PolicyOutcomeStatus { Prepared, Begun, Issued, Stopped, FencedNotCommitted, HandoffCompleted, HandoffFailedFenced, Unknown }
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all="snake_case")]
pub enum PolicyHandoffState { Pending, Completed, FailedFenced, Unknown }
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all="snake_case")]
pub enum PolicyRootState { Active, Terminal }
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all="snake_case")]
pub enum PolicyStopReason { Background, WindowLost, RouteExit, ScopeChanged, SelectionReplaced, UserClose, Revoked }
#[derive(Clone, Debug, Serialize)]
pub struct PolicyObserveRequest { pub scope: PolicyScope, pub access: DocumentAccess }
#[derive(Clone, Debug, Serialize)]
pub struct PolicyBeginRequest { pub scope: PolicyScope, pub access: DocumentAccess, pub source_digest: String, pub presentation_id: String, pub frame_generation: Revision, pub surface_binding: ReadingSurfaceBinding, pub original_attempt_id: String }
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PolicyPrepareRequest { pub scope: PolicyScope, pub root_id: String, pub expected_root_revision: Revision, pub expected_grant_id: String, pub expected_grant_generation: Revision, pub original_attempt_id: String, pub surface_binding: ReadingSurfaceBinding, pub expected_presentation_id: String, pub expected_frame_generation: Revision }
#[derive(Clone, Debug, Serialize)]
pub struct PolicyRenewRequest { pub scope: PolicyScope, pub root_id: String, pub expected_root_revision: Revision, pub original_attempt_id: String, pub challenge_id: String, pub surface_binding: ReadingSurfaceBinding, pub observation_id: String }
#[derive(Clone, Debug, Serialize)]
pub struct PolicyReconcileRequest { pub scope: PolicyScope, pub original_attempt_id: String, pub kind: PolicyKind }
#[derive(Clone, Debug, Serialize)]
pub struct PolicyStopRequest { pub scope: PolicyScope, pub root_id: String, pub expected_root_revision: Revision, pub original_attempt_id: String, pub reason: PolicyStopReason }
#[derive(Clone, Debug, Serialize)]
pub struct PolicyContinueRequest { pub scope: PolicyScope, pub root_id: String, pub resulting_root_revision: Revision, pub original_renew_attempt_id: String, pub continuation_token: String, pub predecessor_presentation_id: String, pub predecessor_frame_generation: Revision, pub presentation_id: String }
#[derive(Clone, Debug, Serialize)]
pub struct PolicyObservation { pub schema: u32, pub document: DocumentRef, pub source_digest: Option<String>, pub grant_id: String, pub grant_generation: Revision, pub active: Option<bool>, pub expires_at_ms: Option<u64>, pub now_ms: u64, pub readonly_operations: Vec<DocumentOperation>, pub availability: PolicyAvailability }
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OriginalPolicyOutcome {
    pub schema: u32, pub kind: PolicyKind, pub original_attempt_id: String, pub fingerprint: String,
    pub outcome_id: String, pub status: PolicyOutcomeStatus, pub scope: PolicyScope,
    pub root_id: Option<String>, pub root_revision: Option<Revision>, pub root_state: Option<PolicyRootState>, pub access: Option<DocumentAccess>,
    pub readonly_operations: Vec<DocumentOperation>, pub native_selection_epoch: Option<Revision>,
    pub source_digest: Option<String>, pub surface_binding: Option<ReadingSurfaceBinding>,
    pub presentation_id: Option<String>, pub frame_generation: Option<Revision>,
    pub challenge_id: Option<String>, pub continuation_token: Option<String>, pub valid_for_ms: Option<u64>,
    pub issued_at_ms: Option<u64>, pub expires_at_ms: Option<u64>, pub handoff: Option<PolicyHandoffState>,
    pub cleanup_pending: bool, pub historical: bool,
}
pub type PreparedPolicyOutcome = OriginalPolicyOutcome;
#[derive(Debug)]
pub struct PolicyContinuation { pub outcome: OriginalPolicyOutcome, pub presentation: Option<DocumentPresentationInfo> }
/// Native SQL projection, not a permit. Consumers must validate it in their tx.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(in crate::documents) struct GrantRecord { pub access: DocumentAccess, pub operations: Vec<DocumentOperation>, pub expires_at_ms: u64, pub active: bool }
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct RootRecord {
    pub id: String, pub instance: String, pub owner_epoch: String, pub scope: PolicyScope,
    pub surface: ReadingSurfaceBinding, pub selection_epoch: Revision, pub revision: Revision,
    pub metadata: DocumentMetadata, pub parent: GrantRecord, pub current: GrantRecord,
    pub child_id: Option<String>, pub presentation_id: String, pub core_session_id: String,
    pub frame: Revision, pub readonly_operations: Vec<DocumentOperation>, pub pending_renew: Option<String>,
    pub stop_fingerprint: Option<String>, pub stop_outcome: Option<OriginalPolicyOutcome>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct AttemptRecord {
    pub kind: PolicyKind, pub scope: PolicyScope, pub id: String, pub fingerprint: String,
    pub prepared: Option<PolicyPrepareRequest>, pub root_id: Option<String>, pub renew_fingerprint: Option<String>,
    pub observation_id: Option<String>, pub outcome: OriginalPolicyOutcome,
    pub handoff_fingerprint: Option<String>, pub handoff_outcome: Option<OriginalPolicyOutcome>,
}
