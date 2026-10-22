
#[test]
fn independent_migration_preserves_null_distinction() {
 check_legacy_migration_fault("UPDATE group_runtime_local_intents SET receipt='null' WHERE intent_id='legacy-pending'");
}
#[test]
fn independent_migration_preserves_receipt_raw_bytes() {
 check_legacy_migration_fault("UPDATE group_runtime_local_intents SET receipt=receipt || ' ' WHERE intent_id='register'");
}
#[test]
fn independent_migration_preserves_identity_with_unchanged_row_count() {
 check_legacy_migration_fault("UPDATE group_runtime_local_intents SET intent_id='renamed-pending' WHERE intent_id='legacy-pending'");
}
