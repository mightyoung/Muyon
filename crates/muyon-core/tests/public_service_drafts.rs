use muyon_core::{
    contract::Revision,
    services::{drafts::*, types::*},
};
use serde_json::Value;
fn fixtures() -> Value {
    serde_json::from_str(include_str!(
        "../../../docs/contracts/public-services-v02/fixtures/drafts.json"
    ))
    .unwrap()
}
#[test]
fn stale_ack_does_not_save_current_draft() {
    let f = fixtures();
    let mut draft: DraftEnvelope = decode_strict(&f["draft"].to_string()).unwrap();
    let mut ack: SaveAck = decode_strict(&f["ack"].to_string()).unwrap();
    let expected = Revision::new(1);
    let original = IntentId::parse("intent:save").unwrap();
    assert!(validate_save_ack(&draft, &expected, &original, &ack).is_ok());
    assert!(validate_save_ack(&draft, &Revision::new(0), &original, &ack).is_err());
    assert!(validate_save_ack(
        &draft,
        &expected,
        &IntentId::parse("intent:other").unwrap(),
        &ack
    )
    .is_err());
    draft.content = serde_json::json!({"title":"edited"});
    assert!(validate_save_ack(&draft, &expected, &original, &ack).is_err());
    draft = decode_strict(&f["draft"].to_string()).unwrap();
    ack.draft_ref.revision = Revision::new(1);
    assert!(validate_save_ack(&draft, &expected, &original, &ack).is_err());
    ack = decode_strict(&f["ack"].to_string()).unwrap();
    ack.draft_ref.scope.scope_generation = Revision::new(2);
    assert!(validate_save_ack(&draft, &expected, &original, &ack).is_err());
}
#[test]
fn draft_schema_and_revision_overflow_are_rejected() {
    let f = fixtures();
    let mut draft: DraftEnvelope = decode_strict(&f["draft"].to_string()).unwrap();
    let ack: SaveAck = decode_strict(&f["ack"].to_string()).unwrap();
    let original = IntentId::parse("intent:save").unwrap();
    draft.schema_version = 2;
    assert!(validate_save_ack(&draft, &Revision::new(1), &original, &ack).is_err());
    draft.schema_version = 1;
    draft.draft_ref.revision = Revision::new(u64::MAX);
    assert!(validate_save_ack(&draft, &Revision::new(u64::MAX), &original, &ack).is_err());
}
#[test]
fn cursor_expiry_only_reads_snapshot() {
    let f = fixtures();
    let mut lease: SubscriptionLease = decode_strict(&f["lease"].to_string()).unwrap();
    let scope = lease.scope.clone();
    assert_eq!(
        resume_action(&scope, &lease, true).unwrap(),
        ResumeAction::ContinueCursor
    );
    assert_eq!(
        resume_action(&scope, &lease, false).unwrap(),
        ResumeAction::ReadSnapshot
    );
    lease.expires_at_unix_ms = UnixMs::parse("0").unwrap();
    assert_eq!(
        resume_action(&scope, &lease, true).unwrap(),
        ResumeAction::ReadSnapshot
    );
    lease.scope.scope_generation = Revision::new(2);
    assert_eq!(
        resume_action(&scope, &lease, false).unwrap_err().code,
        ErrorCode::ScopeChanged
    );
}
#[test]
fn subscription_capacity_and_cursor_are_bounded() {
    let f = fixtures();
    let mut lease: SubscriptionLease = decode_strict(&f["lease"].to_string()).unwrap();
    let scope = lease.scope.clone();
    for capacity in [0, 257] {
        lease.capacity = capacity;
        assert!(resume_action(&scope, &lease, true).is_err());
    }
    lease.capacity = 256;
    lease.cursor.clear();
    assert_eq!(
        resume_action(&scope, &lease, true).unwrap(),
        ResumeAction::ReadSnapshot
    );
}
