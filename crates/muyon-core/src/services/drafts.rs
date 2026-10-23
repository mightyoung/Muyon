//! Draft acknowledgements and subscription recovery; no persistence or commands.
use super::types::*;
use crate::contract::Revision;
use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DraftRef {
    pub owner_plugin_id: String,
    pub draft_id: String,
    pub scope: ScopeRef,
    pub revision: Revision,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DraftEnvelope {
    pub draft_ref: DraftRef,
    pub schema_version: u32,
    pub content: serde_json::Value,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SaveAck {
    pub draft_ref: DraftRef,
    pub original_intent_id: IntentId,
    pub content_digest: Digest,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SubscriptionLease {
    pub scope: ScopeRef,
    pub cursor: String,
    pub capacity: u32,
    pub expires_at_unix_ms: UnixMs,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ResumeAction {
    ReadSnapshot,
    ContinueCursor,
}
/// Validates a save observation, never permission or a business commit.
/// A mismatch does not prove that the original save did not happen.
pub fn validate_save_ack(
    current: &DraftEnvelope,
    expected: &Revision,
    pending: &IntentId,
    ack: &SaveAck,
) -> Result<(), ServiceError> {
    let fail = |code| ServiceError {
        code,
        phase: "draft_save".into(),
        retryability: Retryability::AfterLookup,
        effect_knowledge: EffectKnowledge::Unknown,
        original_intent_id: Some(pending.clone()),
        safe_message: "保存确认与当前草稿不匹配，请核对原请求。".into(),
        details_ref: None,
    };
    if current.schema_version != 1 {
        return Err(fail(ErrorCode::UnsupportedVersion));
    }
    if current.draft_ref.scope != ack.draft_ref.scope {
        return Err(fail(ErrorCode::ScopeChanged));
    }
    if ResultId::parse(&current.draft_ref.owner_plugin_id).is_err()
        || ResultId::parse(&current.draft_ref.draft_id).is_err()
    {
        return Err(fail(ErrorCode::InvalidArgument));
    }
    let revision = expected
        .next()
        .map_err(|_| fail(ErrorCode::StaleRevision))?;
    if current.draft_ref.revision != *expected
        || ack.draft_ref.revision != revision
        || current.draft_ref.owner_plugin_id != ack.draft_ref.owner_plugin_id
        || current.draft_ref.draft_id != ack.draft_ref.draft_id
        || ack.original_intent_id != *pending
    {
        return Err(fail(ErrorCode::StaleRevision));
    }
    let digest = crate::contract::stable_digest(&current.content)
        .map_err(|_| fail(ErrorCode::InvalidArgument))?;
    if ack.content_digest.as_str() != digest {
        return Err(fail(ErrorCode::StaleRevision));
    }
    Ok(())
}
/// Cursor validity is supplied by the read owner; expiry is checked again here.
/// Recovery can only select a read, never replay a command.
pub fn resume_action(
    expected: &ScopeRef,
    lease: &SubscriptionLease,
    cursor_valid: bool,
) -> Result<ResumeAction, ServiceError> {
    if expected != &lease.scope {
        let mut e = invalid();
        e.code = ErrorCode::ScopeChanged;
        return Err(e);
    }
    if !(1..=256).contains(&lease.capacity) {
        return Err(invalid());
    }
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .map(|t| t.as_millis());
    let expires = lease
        .expires_at_unix_ms
        .as_str()
        .parse::<i64>()
        .unwrap_or(i64::MIN);
    let expired = expires <= 0 || now.is_none_or(|now| expires as u128 <= now);
    if !cursor_valid || expired || lease.cursor.is_empty() || lease.cursor.len() > 128 {
        Ok(ResumeAction::ReadSnapshot)
    } else {
        Ok(ResumeAction::ContinueCursor)
    }
}
