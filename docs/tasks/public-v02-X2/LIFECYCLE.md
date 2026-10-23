# X2 lifecycle follow-up — local validation only

2026-10-23 UTC. Latest develop `e943856e4b6e2de26a9c2c8e2fa0912713b590e5` was fetched and ordinarily merged into the existing isolated candidate. C1-C3/root toolchain are now integrated in that develop; earlier reports retain their historical candidate status. New root review/addendum was read. No AGENTS.md was present in the earlier workspace; no new AGENTS.md appears in this develop tree.

RED source: `e1bbeadfa2800bd64bf58aad199279c8e110c8f4`, clean and unchanged during test: successful compilation, old6 pass/new6 fail, exit101. GREEN/review source: `1afb93e47114b052411b7ccac1fbf175380cdedb`, clean and unchanged during fixed focused/full runs.

## What this slice establishes

- Borrowed ConnectionAdmission combines current binding, connection snapshot, catalog, plugin binding, scope, enabled state and per-plugin host grants. validate_admission cross-checks identity/revisions and original validate_call guards, then requires Authorized/Ready/Connected/Available. Disabled admission is denied. Snapshot projection is not used to reconstruct original endpoint digests.
- validate_lifecycle_change checks a proposed snapshot without applying/persisting/sending it. LocalDisconnect changes network/availability; Disable changes enabled/availability; both preserve auth knowledge. RevokeUnknown keeps remote revocation uncertain (AuthState::Unknown). Scope/identity/config/descriptor/endpoint/catalog cannot silently change under those events.
- Each conservative lifecycle transition advances existing authorization_generation exactly once; overflow or stale candidates reject without application. An observed reconnect cannot revive an old prepared binding. A newly validated binding is still only a pure preflight result, never automatic replay/approval.
- Lifecycle rejection errors retain Unknown/AfterLookup and optional original IntentId, since rejecting a snapshot does not establish that an earlier remote revoke/call was not dispatched.
- The in-memory fake owner now actually applies production-validated disconnect, disable and uncertain-revoke transitions after a synthetic timeout. New attempts fail admission while two original-ID lookups retain C2 Unknown without a Receipt; dispatch_count stays1. No second execution ledger, real token or server exists.

Rulings and costs: borrowed validation views are not command APIs, so future production wiring must still map a concrete Operation and trusted identity to original C2 authority. The existing authorization_generation is used as the local invalidation barrier; a future owner must adopt or explicitly adapt that policy rather than silently reuse old prepared bindings. Uncertain revoke is not promoted to Revoked, and lifecycle validation errors are not proof of NotStarted. See LEDGER.md for the complete decision record.

## Actual verification

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connections
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connectors --test public_connections
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-core/src/services/connections.rs crates/muyon-core/tests/public_connections.rs
```

Scoped connections12/12, combined19/19 (connections12, connectors7), full workspace **638 passed/0 failed/0 ignored** across38 result groups. Counts include existing cross-target execution, not638 distinct scenarios. Clippy and changed-file formatting exit0. Existing negative archive boundary logs still include ZipWriter FileTooLarge diagnostic, while all tests pass. Rust/Cargo1.93.1 and existing locked caches/native SQLite link were reused; no installation or lockfile change in this slice.

Independent reviewer `/root/review_connector_lifecycle` inspected fixed source1afb93e47114b052411b7ccac1fbf175380cdedb and reran19/19 offline/locked with a separate target. No P0-P2 findings. Review explicitly excludes real auth/revoke/lifecycle acceptance and C2/host/Operation production wiring.

## Raw evidence outside git

Directory `/workspace/connectors-v02-tools/evidence/`; JSON records include argv, explicit environment, UTC interval, source before/after, pre-run status and exit. Raw logs are not committed.

| Label | Exit | stdout SHA256 | stderr SHA256 |
| --- | --- | --- | --- |
| lifecycle-fixed-red | 101 | 8abec3b187d7081fb0293c73eb719198a85c60864f131f579d96a5bbf5ee2525 | 22a9986b82d223667ae11aa35924cc3b3ef313cbf14a088b9f5619856cfae90e |
| lifecycle-green | 0 | d3ff10c7ca33a0c7fa8be4172b0579504a22ea4918ba651eec3a09f4041624ee | c18bc49d14a7e7a3f4ff909d6aaf709537c0f5717531509b593c86b3c245c9c6 |
| lifecycle-fixed-green | 0 | f3e16473a012672ff04d44f35922e3be95a413e59124bb27ed5d41138bf3eade | e2e3bce28b3b064010a4b37cd1002b76fe7c8157f9cd373121e2aa31e5459877 |
| lifecycle-workspace | 0 | 265b510b482e809b23001d951be1e8b67a3ed30228996603131fc8dba1b77874 | a29ead3266579c7ffdbba0c73eb58b6abf922e05187df847a220b9be40ec0453 |
| lifecycle-clippy | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | 29482e0bc40e3daa3825d982886a1ef99abd6da4fcf58014578a3e9ed5d94897 |
| lifecycle-fmt | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |

## Open gates

Existing deferred pure lifecycle coverage is supplemented here; real disconnect, OAuth, server-side revoke failure, cancellation/rollback, protocol transport, Android and external effects remain NOT_RUN. No public configure/connect/revoke command signature is frozen. Production dispatch remains unavailable. Contracts alone registers connectors/connections modules, core lib.rs and FFI lib.rs; no local changes to those files. X3 remains a license/package/Android/credential-owner gate; X4 awaits provider-specific official evidence and Domain review. Reader FD/real-request unknown and charge holds remain unchanged.

No denied action, uncertain write, credential configuration, new dependency, deployment, force push, deletion or main/develop mutation occurred. Normal rollback removes the new helpers; original receipts and unknown outcomes stay with the original owner.
