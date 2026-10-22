# P03 / S01 / S02 verification — 2026-10-20

Worktree `/private/tmp/muyon-android-refactor-20261020`; initial integration base `cebc6876`. Shared manifest/lib/SQLite/Android/FFI files remain owned by the integrator. This report covers the Rust store and its local process tests, not the installed Android app, paid model/search, physical power loss or release acceptance.

## Fresh final checks

```
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test business --test contract
```

Exit 0: **business 12 passed, contract 10 passed; 0 failed, 0 ignored**. The last run includes the P05 schema and upload-binding additions. Temporary dead-code warnings identify the P05 helper API before its consumer module is integrated; these were not hidden with lint suppression.

```
rustfmt --edition 2021 --check crates/muyon-core/src/business.rs crates/muyon-core/src/bin/business_worker.rs crates/muyon-core/tests/business.rs
git diff --check -- crates/muyon-core/src/business.rs crates/muyon-core/src/bin/business_worker.rs crates/muyon-core/tests/business.rs docs/contracts/muyon-android
```

Both exit 0, including after the final additive P05 handoff. Contract JSON files all parse with Python standard library.

| Real test | Evidence |
| --- | --- |
| explicit initialization | missing open creates no database; existing namespace is not truncated; version 99 stays refused/unmodified |
| complete supplier lifecycle | all eight fields normalize/persist, duplicate names remain separate IDs, full update, soft delete, old reference preserved/new reference refused, restore and process reopen |
| authority | fabricated/revoked/expired/stale generation/wrong workspace/new epoch rejected; expiry during actual SQL rolls the effect back |
| binding/idempotency/CAS | exact duplicate original receipt once; same intent altered arguments conflicts; two updates at revision 1 yield one commit and one revision conflict; a real new same-name intent increments revision |
| corrupt receipt tail | real SQLite AFTER UPDATE trigger corrupts the receipt; actual supplier/history SQL rolls back, durable pending remains unknown and never reruns |
| revocation barrier | separate actual SQLite transaction holds BEGIN IMMEDIATE, revokes active grant, synchronizes via thread Barrier and commits before blocked business admission; no supplier or pending row is admitted |
| owner isolation | child process acquires real flock; second store open refuses; SIGKILL releases the lock and a new epoch can open |
| SQL-before-COMMIT fault | child reaches an explicit marker only **after actual supplier INSERT inside the product execute_with transaction**, then parent SIGKILLs it; independent SQLite/reopen finds no supplier/history/receipt effect, original pending remains unknown and cannot redispatch |
| COMMIT-before-reply fault | child actually commits, withholds the result at an explicit marker and is SIGKILLed; new store retrieves exact original receipt and repeated original command has one supplier/history/effect |
| fixed SQLite errors | real duplicate reference constraint becomes StorageConstraint; real non-SQLite bytes become StorageCorrupt |
| project reads | real project create/history/receipt, bounded list/detail and process reopen |

`business_worker` is a local test binary compiling the same product business source to access the crate-private transaction seam; it is not an Android authorization path. SIGKILL tests prove process-loss behavior, not device power loss or a separate-file/SQL atomic transaction.

## Behavioral mutation checks

Mutations ran only in `/private/tmp/muyon-store-p03-mutation-20261020`, with its own target and offline lockfile; shared product source was never temporarily weakened. Each mutant compiled successfully and failed a runtime assertion, exit **101**. Each mutation was then reverted and the exact test rerun, exit **0**, 1 passed/0 ignored.

Command prefix:

```
cargo test --offline --locked --manifest-path /private/tmp/muyon-store-p03-mutation-20261020/Cargo.toml --test business TEST_NAME -- --exact
```

| Mutation | TEST_NAME | Actual behavioral RED |
| --- | --- | --- |
| remove business BEGIN/COMMIT, leaving SQL independently autocommitted | corrupt_receipt_tail_rolls_back_all_effects_and_never_reexecutes_pending | persisted supplier count **1**, expected **0** |
| erase existing pending identity and repeat its business effect | sigkill_after_actual_sql_rolls_back_and_original_pending_cannot_redispatch | status **Committed**, expected **Unknown** |
| bypass both current-revision precheck and SQL revision predicate | duplicate_binding_conflict_cas_and_same_name_new_intent | second stale edit **Committed**, expected **Rejected** |

Mutation baseline `business.rs` SHA-256: `4411925b28dbb89b919048df202de428eca2ef64b254a255213bca3e82950eef`. Restored mutation source matches that snapshot. Subsequent additive P05 schema/root/helper handoff and explicit transaction-token closure changed shared `business.rs` to `7a35b598e5b107acffa2e3b03fa5d94edf8a37f49a87d268e52816af5cdcb086`; none of the three tested guards changed, and the fresh full 12+10 test command above passed after that addition. This explicitly distinguishes the mutation snapshot from the later integration source.

## Remaining integration proof

Trusted Android confirmation/Service/FFI ownership and read permissions, Kotlin matching digests, product native packaging, actual project/paper/import/file ports, real APK API26 UI paths, live provider/search and I04 recovery remain downstream work. New schema and passing local process tests cannot substitute for those gates.
