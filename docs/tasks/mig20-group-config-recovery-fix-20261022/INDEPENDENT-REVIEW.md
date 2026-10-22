# Independent recovery-fix review — 2026-10-22

Scope: branch `task/mig20-group-config-recovery-fix-20261022`, base `96d90fd0b264552ec93a997b59da56099d345937`. This is a NEW review of the recovery patch; prior branch approval does not establish that this patch or its base had no remaining defects. Reviewer edits are restricted to this task report/evidence. All synthetic databases and extra harness files reside under /tmp. No provider/network/user-file/owner/lib/FFI operations were performed.

## Confirmed new finding P2 — initial binding insertion can commit an unverifiable pending journal

Location at discovery: group_runtime/store.rs pending transaction immediately after `INSERT INTO group_runtime_intent_bindings` and `group_verify_original_command(c)`. The exact new metadata row is checked, but the corresponding journal row is not revalidated after that trigger-capable insertion. An AFTER INSERT trigger on the new table that changes journal.binding_digest to 'wrong' leaves a committed pending row with a matching original command that can no longer prove its journal binding.

Offline actual repro: force Register group INSERT to fail with RAISE(ABORT), and install the above new-table insertion trigger. `execute_group_local` returns Ok(PendingOriginal). Original native actor lookup returns BindingMismatch; no group exists and the caller cannot recover the claimed durable pending. This is limited to the synthetic SQL-trigger fault model used throughout the local tail review, not a claim that a model may inject SQL.

Repro source: `evidence/independent-recovery-review-harness.rs`, appended test `independent_pending_binding_insert_tail_cannot_corrupt_recovery_journal`; runnable project `/tmp/mig20-recovery-review`. Original failed output: `evidence/independent-initial-journal-tail-RED.log` (EXIT101). Recommendation: immediately before initial pending transaction commit, prove BOTH exact original command and exact expected pending journal fields (scope/digest/status/null receipt); fail Storage and roll back when those cannot be established. Do not return a receipt implying durable pending.

## Independently verified before fixing the new finding

- Ran native bridge **42/42**, original store **65/65**: pass. These counts include source-imported duplicate tests.
- Reran four parent counterexample/regression functions in a standalone /tmp same-crate harness: **4/4 pass**. Exact revision trigger (OLD revision2 to NEW3, OLD record preserving NEW revision) returns PendingOriginal and restores original group. Current group expected bytes are built BEFORE INSERT/UPDATE, not trusted from an already-triggered database snapshot, and compared after grant consumption.
- Pending Register lookup succeeds with no group, survives restart with a new owner epoch, rejects unrelated human and wrong group, does not mutate journal/grants/group/events. Original command digest/scope/Human identity is checked. Current group managers remain allowed for legacy bindings; no-command/no-group remains Unknown.
- Explicit schema1->2 migration preserves legacy journal and leaves missing historical commands missing. Migrated legacy pending without group returns Unknown.
- Extra independent controls: BEFORE INSERT metadata IGNORE/ABORT causes error and atomically leaves no journal/binding, with no group/event/grant consumption. Receipt and consumption triggers corrupting command result in PendingOriginal and roll back metadata/group/event/receipt/grant. Migration schema version UPDATE ignored causes rollback to version1 with no new metadata table. These controls pass. Extra source: `evidence/independent-recovery-extra-controls.rs` (appended in the /tmp runnable harness).

Original failed evidence remains preserved. Final disposition of the new P2 will be appended after its repair is independently verified. No denied action or environmental blocker.


## Final independent re-review — recovery patch verified

The newly discovered initial-pending P2 is fixed. `group_verify_pending_tail` compares the exact intended journal tuple (workspace/project/group/binding/pending/null receipt), then verifies the exact original command row; the caller next commits without another intervening write. A mismatch returns Storage BEFORE the initial transaction commits, and transaction drop rolls journal plus metadata back. This is correctly an error rather than PendingOriginal: the original durable journal has positively not been committed. This classification does not convert uncertain already-durable effects into a false rejection or replay.

The independent original counterexample and its assertion were not weakened. The saved original harness SHA256 is `7e09bf40ee0a6fffc10f4499a19a79907796886804b6c05cc0e08422d9b55199`; the current /tmp runnable harness retains it as an identical byte prefix and only appends two extra controls. Rerun output now reports `INITIAL_RESULT=Err(Storage)`, `RECOVERY_RESULT=Err(NotFound)`, with the journal absent. All three extra independent test functions pass, including four metadata-fault cases and migration IGNORE rollback. See `evidence/independent-final-recovery-controls.log`. The original RED log remains untouched.

Reran all four original parent regression/counterexample functions in the standalone harness after repair: **4/4 pass**, including the exact revision-preserving group trigger and pending Register lookup across restart/owner epoch change, identity failure and no writes/replay. See `evidence/independent-final-parent-counterexamples.log`.

Reran CURRENT native targets independently: bridge **48/48**, store **65/65** pass, including new metadata-missing/tamper, migration-abort rollback, three normal mode/default leader cases, and receipt/consume command-binding damage cases. See `evidence/independent-final-native-regression.log`. Counts continue to include imported source-module tests; 48 is not 48 newly authored tests.

Reviewed the store regression adjustment: the old changed-pending trigger now fails earlier in the initial journal transaction, returning Storage with BOTH journal/binding absent. The changed test strengthens that earlier rollback guarantee instead of accepting an unverifiable pending receipt. Existing later rejection/Unknown and consumption-tail cases remain present and pass.

Source fingerprints are in `evidence/independent-final-source-sha256.txt`. Current group-row witness is computed before group INSERT/UPDATE and compared after exact grant consumption; original command binding is verified at terminal receipt tails. Read-only historical original identity checks do not require stale grant/epoch reauthorization, and missing old commands are not fabricated by migration. No owner/lib/FFI/network access was added.

Final disposition for THIS recovery branch: both supplied parent defects and the additional independent initial-journal defect are remediated in the verified source. No further important defect identified in this bounded review. This does not retroactively assert that the previous base branch had no defects. No denied, pending or uncertain action; no remaining review blocker.

Frozen three group_runtime source files and two tests: `evidence/independent-final-frozen-five-sha256.txt` (includes unchanged mod.rs). The final reviewed store/bridge/test hashes remain identical to the successful final rerun. Parent-reported fixed document-core/full-core results are not counted as independent executions in this report.
