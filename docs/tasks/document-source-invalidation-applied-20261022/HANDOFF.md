> Superseded implementation status: see [BATCH-AND-GATEWAY-TAIL-HANDOFF.md](BATCH-AND-GATEWAY-TAIL-HANDOFF.md). Final source is a961bb58c08ce77b559ce0d021d2ed50a857bb9e. e3fa had a later independently confirmed ABA RED; its prior validation claims below are historical, and the unchanged gateway remains HOLD.

# Applied source invalidation — trigger-tail fix, pending Rust validation

Branch: `task/document-source-invalidation-applied-20261022`.
Explicit parent-authorized dependency baseline: `662aeec6d6462cabfcc317e855ae23797dd88d51`.
Fixed final source: `e3fa0ee71f071bb8cff667d50ee1c0da6827a7c9`.
Implementation: `3f195f6090727bb8a59dfc11329ba5c38de9fcd4`.
Earlier applied test source: `ed1c4eff13afedaa6d5b8829176911b93a4c1140` (contains the new blob/ignored-ACK counterexample tests before those two fixes; not run locally).

This branch contains REAL APPLIED source, not only docs patches. Its source delta is exactly blobs.rs, documents/mod.rs, documents/storage.rs, documents/source_notifications.rs, and documents/source_notification_tests.rs. No lib.rs, Artifacts/Evidence author files, FFI/Android, harness, B branch, main or develop was edited. The baseline already contains actual resolver and Reader modules. Its artifact local_sources.rs hash is `52b3a4e9eda179d43535218da7452dc68ad98a8c6635e582678399d0b6b3e364`, matching the owner resolver dependency. No manual harness workaround is required. Use this fixed applied source for verification; the older docs-only patch branch is not the final source.

## Preserved RED and root cause

Original independent evidence `67337d3f280d5b522d9066ad03990f36d04f8e26` really ran the OLD b9/36b overlay and found THREE behavior REDs: outbox AFTER INSERT could restore revoked grant.active=1, delete the notification, or set pending=0, while revoke returned Ok. Its prior12/Artifacts41/core727 executions do not close these findings and do not apply to this fix. The original report is copied byte-for-byte as `PRIOR-INDEPENDENT-RUST-VERIFICATION.md`; full original raw logs remain at that immutable evidence commit. Its four-path fmt failure, offline workspace dependency gap (anyhow1.0.104) and missing Reader-baseline group harness apply failure remain historical failures, not overwritten or retagged.

Cause: successful SQL row changes were treated as a durable semantic postcondition. AFTER triggers can undo those semantics without producing an SQL error. Checking only changed==1 or only each just-written event also misses later cross-row tampering.

## Fix and API

Original document publish/COPY and grant issue/update/revoke call the REAL owner source invalidation hook after the mutation in the SAME transaction. Original grant DocumentRef is decoded before overwrite; replacement checks both original and new targets. Uninitialized optional namespace remains compatible, while malformed/previously-installed missing schemas reject. Hook errors and all tail failures propagate for full transaction rollback.

All new outbox writes finish BEFORE read-only verification of every queued exact identity/generation/pending=1 and affected source document identity/inactive source plus inactive binding. These source projections only confirm the real owner's returned invalidation effects; they do not parse its payload, implement permission logic, or mutate owner tables. Grant replacement repeats both batches' tail verification after both hooks. Issue checks exact grant fields, current expiry/project authority and unchanged current metadata. Revoke checks the exact original grant row with active=0. Publish/COPY check exact current metadata plus the blob owner's exact reference/project/target/digest/ready/length receipt; publish also requires committed upload with original project generation/workspace/epoch and no upload pin. No further business writes occur after these read-only tails.

ACK freezes ALL input target states before ANY write, including stale, duplicate and missing rows. The final check verifies exact expected generation/pending/absence for ALL frozen inputs. It does not depend on changes()==1 selecting rows to verify, so DELETE+RAISE(IGNORE) cannot discard a tombstone; later mutations of earlier stale/missing inputs also roll back. Generation tombstones remain retained to prevent ABA.

Trusted Host API is additive and unchanged from the patch contract:
- `pending_document_source_notifications_trusted(after, limit)` returns metadata-only pages of at most256 tokens after source COMMIT.
- Host delivers local Runtime invalidations, then `ack_document_source_notifications_trusted(events)` acknowledges exact generations. Unknown/failed delivery must remain pending.

Host/Runtime poll/deliver/ack adapter is still NOT integrated here; no actual notification was emitted. Notification never substitutes for per-access authorization. Source owner hook accumulates all affected results in a Vec; page256 is not a total mutation memory limit. Tombstone/outbox cardinality follows distinct objects; no total disk quota is claimed.

## Tests and exact verification

There are 20 authored source-notification tests, using real synthetic Text/resolver fixtures. Added successful-trigger cases cover original grant restoration/deleted or pre-acked notification, forged generation, reactivated source/binding, reissue generation tamper, publish/COPY head restoration, later queue write erasing an earlier event, UPSERT, ACK reversal, deleted blob receipt, committed upload/pin conversion, ignored ACK tombstone deletion, and cross-row stale/missing ACK tampering. Prior schema, rollback, 258-binding pagination and manual-value tests remain intact.

`verification.log` records the commands attempted at fixed implementation3f195f60; `final-focused.log` records the final e3fa0ee7 targeted command. Focused tests, full core, workspace, strict Clippy and scoped five-file rustfmt are **NOT_RUN (127)**: accessible cargo/rustfmt absent. `/root/.cargo/bin/cargo` locator read was denied by filesystem; that read was not retried or escalated. This is not an automatic approval rejection and no operation with uncertain execution was retried. No actual local RED/GREEN or fmt pass is claimed. The tests were authored before corresponding fixes; local127 is not RED. Independent actual re-execution is required, including original THREE probes and new blob/ACK cases at the earlier test source where appropriate.

Exact commands for independent existing-toolchain environment:

```sh
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::source_notification_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core
cargo test --offline --locked --manifest-path crates/Cargo.toml --workspace
cargo clippy --offline --locked --manifest-path crates/Cargo.toml --workspace --all-targets -- -D warnings
rustfmt --check --edition 2021 --config skip_children=true crates/muyon-core/src/blobs.rs crates/muyon-core/src/documents/mod.rs crates/muyon-core/src/documents/storage.rs crates/muyon-core/src/documents/source_notifications.rs crates/muyon-core/src/documents/source_notification_tests.rs
```

`git diff --check 662aeec6d6462cabfcc317e855ae23797dd88d51 3f195f6090727bb8a59dfc11329ba5c38de9fcd4` exits0; the final test-only delta also passes whitespace check. Manifest pins exact final source files. Independent static review accepted all final logic and supplementary tests; it is not runtime acceptance.

Remaining blockers: independent compile/RED-to-GREEN/full target/fmt on fixed applied SHA; any existing offline workspace dependency gaps; Host/Runtime post-commit consumer and B integration. Source hook is NOT declared production accepted or product-complete. Real engines remain HOLD and no candidate publication is enabled. No real files, model/search, paid services, credential/permission changes, deployment, merges or actual sends occurred.

Intermediate4498 docs-patch preparation hashes and NOT_RUN logs are retained under `INTERMEDIATE-4498-*`; they describe the pre-applied repair, not the final source or runtime acceptance.
