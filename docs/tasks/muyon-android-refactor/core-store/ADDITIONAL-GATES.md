# Additional DB01–DB04 admission evidence — 2026-10-21

Only new `crates/muyon-core/tests/store_admission_additional.rs` and this report belong to this slice. Existing production/test/worker files, device DBs, paid providers and I04 were not changed or invoked. Three new top-level tests were added, below the five-test limit. All use isolated temporary SQLite stores and existing public APIs. No production fault hook was introduced.

## Existing evidence retained, not recounted as new

The 14 existing business tests already prove complete supplier lifecycle and reopen; exact binding/intent/CAS semantics; revoked/expired/stale grants; a real SQLite revocation-first transaction barrier; receipt-value tampering rollback; durable unknown and cancellation recovery; cross-process owner refusal; SIGKILL after real uncommitted SQL and after COMMIT before reply; schema-v1 refusal with original pending identity retained. Existing worker/P05 evidence separately covers actual publication/receipt/reference faults. The additional tests do not present those old runs as new coverage.

## New executed evidence

```
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test store_admission_additional -- --nocapture
```

Exit **0**: **3 passed, 0 failed, 0 ignored**. Actual fixed output includes `SQLITE_WRITE_REFUSED:storage_io`.

| New test | Actual evidence and distinction |
| --- | --- |
| sqlite_rejects_pending_domain_history_business_history_and_receipt_writes_atomically | Four real SQLite BEFORE triggers call RAISE(ABORT): pending INSERT, supplier history INSERT, generic business history INSERT, and committed intent/receipt UPDATE. These are SQL operation failures rather than the existing post-write value-corruption trigger. Independent read connections find zero supplier/history/committed receipt effects. Pending admission failure returns StorageConstraint with no intent; later failures preserve one pending/unknown intent and the unconsumed grant. Removing the fault does not redispatch an existing pending intent. Actual store reopen confirms original unknown/notFound distinctions. |
| real_os_file_size_write_failure_has_no_business_or_receipt_effect | A dedicated OS child initializes no new production hook. After the real grant is persisted, it sets only its own RLIMIT_FSIZE to zero and ignores SIGXFSZ, then calls the real public execute. Actual SQLite WAL write fails with **StorageIo**. The parent opens/queries the physical store independently and finds no supplier/history/committed receipt, and original lookup remains unknown. No host disk is filled, no global quota is changed, and no device path is touched. This proves an actual OS write failure, not a manually returned error. |
| os_process_races_preserve_original_intent_and_reject_stale_cas_after_owner_exit | Two independent OS processes synchronize before opening the same real store; the winner holds its owner until the competing open has actually refused with InvalidAuthority. In the same-intent case the owner commits once and a new legitimate owner obtains/replays the exact original receipt with one supplier/history effect. In the CAS case two distinct commands both expect revision 1; after the winning process commits revision 2 and exits, the refused process's command is submitted by a legitimate new owner and is rejected with RevisionConflict. There is one winning update, with original+update history count two. This goes beyond the old single hold-owner probe without inventing two concurrent legal writers. |

The process tests launch this same test binary with a narrowly selected test and child mode, using pipe barriers and temporary serialized synthetic commands. They invoke existing BusinessStore APIs and SQLite; they do not add or weaken a production interface. The file-size limit applies only in the dedicated child, which exits before other tests can inherit it. Host runtime checks confirmed SIGXFSZ=25 / RLIMIT_FSIZE=1. An initial harness signal constant was corrected after that check; its pre-gate child termination was a harness diagnostic, not a production regression or behavioral mutation RED.

## Explicit remaining boundaries

- **Exact SQLite SQLITE_FULL / exhausted physical filesystem**: not claimed. The new test exercises real filesystem write refusal and observes StorageIo. Filling the shared host disk or mounting a quota filesystem was outside the bounded safe test surface; current public APIs do not expose the product SQLite handle for a same-connection max_page_count test.
- **Two simultaneously admitted product writers**: unreachable under the actual process-lifetime exclusive owner invariant. The new OS race verifies the denial and subsequent public CAS/receipt behavior; it does not bypass the owner to manufacture a second authorized writer.
- **Cancellation/revocation at both sides of the exact business COMMIT**: existing tests cover revoke-first writer serialization and committed-before-reply/cancel semantics. A live pause specifically after pending COMMIT but before business BEGIN is not exposed by the current public API or existing worker. Another legitimate host owner cannot enter while the current owner holds flock. No new production hook was added to claim this exact narrow scheduling window. That remaining gate needs an explicitly approved test seam or Service scheduling evidence.
- **Per-history / intent / receipt I/O fault at every native disk flush**: the four new actual SQL rejection points supplement the real OS write failure; they do not claim per-syscall power-loss or VFS fault coverage.

No assertions, transaction checks, receipt checks, quota checks or unknown protections were removed. Final targeted Clippy with warnings denied and rustfmt/diff checks accompany the handoff.
