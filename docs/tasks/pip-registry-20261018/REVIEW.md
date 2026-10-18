# Independent review of PIP registry evidence slice

Review date: 2026-10-18 UTC. Read-only reviewer; no repository or Git writes.

Reviewed commit: `25c6cd7d48466a27e7cfcbcaf11e19629f804f7e`

Reviewed tree: `fe9725f3e0169744f309cabb62f43f1a5136bf05`

Baseline: `3f1be180bb009a91e659c113ba5b1916e5360332`

All 12 changed paths are additions under `docs/tasks/pip-registry-20261018/`. HEAD/tree matched these identities before and after review; working tree remained clean.

## Findings, ranked

No critical, important, or blocking findings. One minor documentation precision issue:

- P3 — `VERSION-MAP.md:36–37` says StorageManager rejects mismatched historical `ID/digest/date`. Source `apps/muyon/lib/platform/storage_manager.dart:277–279` compares ID/digest but only checks that `applied_at` is a string parseable as a date. It does not compare historical dates to an expected value. Prefer “mismatched historical ID/digest or invalid applied_at” to avoid implying timestamp integrity verification. This is a wording correction, not a request to change shared migration code.

## Assessment

The slice accurately scopes itself to documentation and characterization evidence. Catalog stages declarations in local collections and mutates its stored metadata/generation only at final publication. Session epoch/tickets are not presented as owner leases. Missing per-bundle removal, retained dependency rows and drain/resource-close contracts are identified without introducing a replacement registry or framework. Existing NativeSession/Service lifecycle claims were checked against source, not executed as host tests.

The added probe uses the real public Catalog API and original fixtures/support. Its seven invalid-publication variants check exact rejection, unchanged inspect state, and successful reuse of the same namespace/binding. The remaining tests exercise existing ticket dispatch/result acceptance, generation invalidation before dispatch, and late admission after close. They characterize public behavior; they do not establish handler drainage, durable failure handling, or a new feature RED.

The supplier map preserves ModuleSchema migrations and digest inputs separately from domain schema12/native contract version1. It distinguishes domain subset reading from hosted schema3 certification and production authority bridging. The fixed store candidate `fdc9aea120925229aa592c3551efab9b3f67a825` was source-inspected only. A path diff against baseline for plugin-contract-lab/core returned exit0; no store-candidate test result is credited.

## Fresh independent verification

Toolchain: rustc1.90.0 (1159e78c4 2025-09-14), cargo1.90.0 (840b83a10 2025-07-30).

Environment: CARGO_HOME=/workspace/pip-toolchain/cargo; RUSTUP_HOME=/workspace/pip-toolchain/rustup; PATH prefixed with /workspace/pip-toolchain/cargo/bin; CARGO_TARGET_DIR=/workspace/pip-review-target. Commands ran from /workspace/Muyon at the fixed reviewed commit.

| Command | Exit | Result / log |
|---|---|---|
| `cargo test --locked --offline --manifest-path docs/tasks/pip-registry-20261018/probe/Cargo.toml` | 0 | 4 passed,0 failed,0 ignored,0 filtered; `probe.log` |
| `cargo test --locked --offline --manifest-path experiments/redesign/plugin-contract-lab/core/Cargo.toml` | 0 | mapping5 + read8 + registration9 =22 passed,0 failed,0 ignored,0 filtered; lib/bin/doc targets each0 tests; `plugin.log` |
| `rustfmt --edition 2021 --config skip_children=true --check docs/tasks/pip-registry-20261018/probe/tests/publication.rs` | 0 | New file only; no output; `rustfmt.log` |

Original crate subprocess coverage is bounded metadata-only Catalog wire behavior; no HTTP or provider execution. Both test runs used locked offline resolution, existing local crates, and external build output.

## Limits and remaining blocker

No host/I04 suite, HTTP/reopen flow, equivalent/split/retry action, supplier-store test, Dart test, migration, real user database, Android/device build, model endpoint, deployment, or integration was executed. I04 remains DENIED_BEFORE_EXECUTION/BLOCKED; the reviewer did not attempt it.

Production lifecycle implementation remains BLOCKED_PENDING parent/LeaderB owner clearance. Exact proposed action is modification of shared Catalog/host lifecycle source and tests identified in README; reason is pending ownership coordination. No such write was attempted, denied, or left with an uncertain outcome during this review. This review supports the bounded documentation/evidence slice only and does not approve production completion or integration.
