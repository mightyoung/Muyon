# Initial RED setup failure observation

The coordinator inspected the initial rust-red.log before the implementation agent replaced it with a second RED run. Initial run compiled successfully but all 12 tests stopped at fixture initialization. It is **not** target-mechanism RED evidence. The original complete initial file was overwritten; this is an observation excerpt from the tool output, not a recovered full raw log. Any replay of that initial stub must be labeled reconstructed, not original.

Observed excerpt:

```text
Finished `test` profile [unoptimized + debuginfo] target(s) in 10.69s
running 12 tests
atomic_precommit_crash_rolls_back_tombstone_and_outbox ... FAILED
consume_before_revoke_is_recorded_but_future_consumption_denied ... FAILED
commit_crash_reopens_in_other_process_and_blocks_read ... FAILED
cleanup_crash_retries_same_operation_after_lease_expiry ... FAILED
delete_management_survives_automatic_memory_switch_closed ... FAILED
every_member_current_field_is_checked_at_final_consume ... FAILED
partial_failure_unknown_and_retry_are_persistent ... FAILED
quotes_revalidate_source_identity_and_authority ... FAILED
revoke_before_consume_rejects_prebuilt_projection ... FAILED
replay_is_bound_to_complete_payload ... FAILED
stale_delete_has_no_half_writes ... FAILED
utf8_ranges_and_redaction_do_not_forge_contiguous_quote ... FAILED

---- atomic_precommit_crash_rolls_back_tombstone_and_outbox stdout ----
thread 'atomic_precommit_crash_rolls_back_tombstone_and_outbox' (1961) panicked at tests/governance.rs:6:78:
synthetic seed must persist: Denied

---- consume_before_revoke_is_recorded_but_future_consumption_denied stdout ----
thread 'consume_before_revoke_is_recorded_but_future_consumption_denied' (1964) panicked at tests/governance.rs:6:78:
synthetic seed must persist: Denied

test result: FAILED. 0 passed; 12 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

The coordinator requested setup correction and separately preserved target RED source/output before implementation. Subsequent evidence files must not be overwritten. This initial evidence retention failure remains disclosed despite later passing runs.
