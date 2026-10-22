# Parent review fixes: intended configuration and original Register recovery

Base96d90fd0b264552ec93a997b59da56099d345937; isolated task/mig20-group-config-recovery-fix-20261022. Changes only owned group runtime/store/bridge, two dedicated group tests and this artifact directory. No protected owner/lib/FFI files or external requests.

## Fixed findings

1. **Committed Configure with old configuration.** Actually reproduced both an AFTER UPDATE OF record mode/leader revert and the parent's exact revision2->3 trigger restoring OLD.record with only its revision updated. Old code returned Committed/revision3/per_task after a fixed/b request. Now the complete intended group row is captured before INSERT/UPDATE, and checked after grant consumption. Both original counterexamples return PendingOriginal with old revision/config/run/event/receipt/grant restored. Normal explicit host_only/fixed/per_task plus fixed leader b remain persisted and usable after restart and in new local runs.
2. **Unqueryable pending Register without group.** Actually reproduced effect INSERT storage failure: durable pending but no group; original UI lookup returned NotFound. Now original command and authenticated local Human identity are persisted as exact journal-bound facts in the same pending transaction. Query uses actual workspace/project/group/intent/digest binding and original submitter/current group management authorization, without requiring registration succeeded. New pending Register stays queryable across owner-epoch restart; repeated query leaves journal/grants/groups/events unchanged. Missing legacy identity stays Unknown when no real group management proof exists; no account/group is fabricated.
3. **Independent followup: initial journal tail.** Reviewer reproduced a new binding-table INSERT trigger corrupting journal.binding_digest before the pending transaction committed, making a returned pending intent unreadable. Native RED retained. The initial transaction now verifies BOTH the complete pending journal row and exact command after all writes and before commit. Determinate failure rolls both back and returns Storage; later uncertain effects retain PendingOriginal. Existing status-tamper test strengthened to assert no falsely durable journal/binding rather than weakened or skipped.

The new seventh owned table and explicit atomic schema1->2 migration are detailed in INTERFACES.md. Original six table/core DDLs are untouched. Migration preserves old journal/receipt bytes and does not backfill guessed identities. Response adds identity_source; public native signatures/v1 request schemas remain stable.

## Evidence

-01/02: both actual configuration trigger counterexamples EXIT101, Committed with reverted mode.03: both GREEN, PendingOriginal+rollback.
-04: pending Register lookup EXIT101, actual Err(NotFound).05: missing durable identity migration EXIT101 (schema remained1).
-06: bridge42 pass.07: existing store65 pass.08: bridge47 pass after broader recovery/normal-selection/metadata fault controls.
-09: independent-discovered initial journal-tail native RED EXIT101.10: bridge48/store65 GREEN after exact initial proof.
- All original independent failures and unchanged independent reproducer sources are retained, along with fresh final review logs.

Final full-suite, combination, hashes and independent final outcome are recorded below after verification. Counts are executions, including repeated source tests; no claim that all are new distinct tests. Existing read/write runtime extern warnings remain, and fixed document-core adds existing dead-code warnings.

NOT_RUN: protected FFI/host/Android integrated acceptance, real Agent/model/search/provider execution, deployment. Prior canonical request/unique-gateway owner hooks remain unimplemented in their protected files and are documented precisely in the preceding slice. No action denied or pending approval; no live data, historical Unknown/hold or security authority was changed.

Reproduce final current-core checks with `python3 docs/tasks/mig20-group-config-recovery-fix-20261022/verify.py`. Reproduce fixed document-core combination with `python3 docs/tasks/mig20-group-config-bridge-20261022/verify-combination.py` (it imports CURRENT owned sources into a temporary fixed10d snapshot and supplies the previous documents harness shim). No unknown software is installed. Raw output logs may have blank EOF lines; source/document diff checks exclude raw evidence formatting.

## Final verification

| Check | Result |
|---|---|
| Full current core (`verify.py`) |301 passed,0 failed |
| Bridge |48 passed =30 dedicated+18 repeated source tests;10 added test functions in this repair |
| Existing store |65 passed =47 group+18 repeated source tests |
| Standalone runtime/governance with warnings denied |20/21 passed |
| Formatting and source/document diff checks |passed |
| Fixed document-core10d actual library combination |77+94=171 passed, including repeated29 document tests per harness |
| Independent exact parent cases |4/4 passed |
| Independent added recovery fault controls |3/3 test functions passed, containing multiple fault cases |
| Independent native bridge/store |48/65 passed |
| Frozen source hashes |all matched final verifier and independent report |

301 includes bridge48/store65 and repeated source modules; it is not301 new distinct tests. Combination171 is separate integration evidence, not171 new tests. Source SHA256 and every final command/exit/time are in evidence/final-manifest.json and independent-final-frozen-five-sha256.txt. All new independent initial-journal-tail RED evidence and original source are retained; the independent review explicitly checks this repair and does not retroactively certify the defective96d90 base. See INDEPENDENT-REVIEW.md.

Only raw log blank EOF lines may fail a whole-artifact whitespace check; original logs remain verbatim. New code/docs pass checks excluding raw evidence. Canonical request/gateway/FFI owner integration and the existing business_worker documents-import seam remain exactly the previously reported pending integration work; this patch neither modifies them nor claims acceptance.
