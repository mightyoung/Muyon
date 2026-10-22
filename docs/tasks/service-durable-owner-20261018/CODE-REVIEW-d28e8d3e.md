# Independent immutable repair review

Reviewed source: `d28e8d3ed08d2185198284794dd116e3d6eb3290`.
Execution location: `/workspace/Muyon`, selected execution environment, 2026-10-18.
Inputs: `/tmp/durable-owner-fix-review-d28e8d3e.patch`, original `CODE-REVIEW-bf244606.md`, latest `IMPLEMENTER.md`, complete current production source and all 17 named instrumentation tests. The prior PLAN/design scope and hard boundaries remain applicable. No tests or builds were executed by this reviewer. Root-owned CI is not yet terminal at review time; this report does not claim GREEN or runtime verification.

## Dual conclusion

**Specification: accepted for the bounded prerequisite at static review.** I1 and I2 are addressed in source and have focused regression tests. The reviewed changes retain the stated authority, complete-budget, durable-accounting and one-shot contracts. Production installation and real chat remain outside this delivery.

**Quality: accepted at static review, with runtime acceptance pending root's exact-SHA scoped CI.** No new Critical or Important defect was identified in this repair wave. M1's required coverage cases are now represented in the tests; recommended robustness cases remain explicitly unexecuted. A passing CI result must be separately attached before claiming execution success.

Line references below use **Owner** for `experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/agentipc/DurableServiceHostOwner.kt` and **Test** for the corresponding `src/androidTest/.../DurableServiceHostOwnerTest.kt`.

## Finding dispositions

### I1: addressed

Owner 108–138 now holds the shared authority guard across two SQLite transactions. The first transaction durably advances `high_water` and expires held rows (114–126); only after `endTransaction` returns successfully does the second transaction run fallible reserve/consume work (127–135). A duplicate insert, proof exception or failed admission insert in that second transaction cannot roll back the first transaction's successful clock/expiry writes.

The guard is still held while both transactions complete. All supported same-database owner objects must share this authority; different authorities/processes are excluded by the retained lease. Consequently another supported reservation, commit or authority replacement cannot slip between the two transactions. A process termination between them leaves time/expiry maintenance durable and no new admission. A second-transaction failure retains a held reservation where appropriate and cannot partially consume or create admission metadata: state update and admission insert remain in the second transaction (198–200).

If time is negative or below the durable watermark, the first transaction makes no expiry/accounting mutation and the admission block is skipped (120–127). If the maintenance transaction itself fails or its commit outcome is uncertain, control never reaches admission and returns denial (126, 138). The durable rollback guarantee covers successfully committed time observations; this component cannot record elapsed time it was unable to persist, or reconstruct unobserved elapsed real time after downtime. That storage/clock limitation must not be described as an external trusted monotonic clock.

Test 208–229 directly represents the original counterexample: reserve at 100, duplicate failure after observing 111, reconstruct at 105, deny token and new reservation, then assert durable watermark 111 and expired state. The prior trigger failure test (127–143) remains and checks that consumption/admission rollback is atomic independently of clock maintenance. These are source-level coverage observations; neither test was run here.

### I2: addressed

Owner 75 and 213–234 now share one manifest for creation and validation. Validation requires exact table DDL, all expected implicit primary-key/unique indexes, and no unrecognized schema objects. The original same-columns/missing-UNIQUE database therefore fails both the DDL and index checks. Equivalent but different schemas are intentionally rejected, with no upgrade or constraint repair.

The expected autoindex counts are consistent with the manifest: one for `epochs`, two each for `reservations` and `admissions`; `clock_guard` uses an `INTEGER PRIMARY KEY` and has no separate implicit PK index. Null SQL for implicit indexes is compared explicitly. Optional `android_metadata` is excluded from the admission manifest only when its type, table name and SQL are exactly the standard `CREATE TABLE android_metadata (locale TEXT)` (228–230). An extra index/trigger/view or different metadata definition remains a rejection. This is deliberately strict and may sacrifice availability on an unsupported SQLite schema representation; Android API26 runtime compatibility still requires CI evidence.

Test 231–257 reads only the four new admission table definitions from a fresh synthetic seed, avoiding Android's locale table, builds another fresh v1 database without `request_id UNIQUE`, and checks unavailable metadata/reservation plus unchanged fixture bytes and missing original constraint. The fixture corrects the earlier metadata-isolation issue without touching any legacy database.

The validator runs at open; it is not a security boundary against arbitrary same-process code subsequently editing the SQLite schema directly. The existing synthetic trigger injection deliberately uses such access for failure testing. No production raw-database writer is installed in this scope, and no new support for concurrent external schema writers is inferred.

### M1: required coverage strengthened; recommended cases remain disclosed

- Test 259–268 checks `now == expires` and retains request uniqueness while permitting a distinct fresh request after hold release.
- Test 270–288 makes calls, tokens and micros independently limiting, consumes a call, closes the object, refreshes the same authority epoch and reopens before checking quota remains exhausted. This addresses the prior combined-dimension and consumed-reconstruction gaps.
- Test 290–309 races two connections to commit one token, asserts exactly one admission, and rejects replay and duplicate-request reservations through both connections. The original multi-connection reserve-quota test is retained.
- Test 311–323 exercises `ServiceHostBindings.callback` with the real durable component for metadata, scope, review, reserve, commit, replay and duplicate denial. It is Kotlin callback compatibility only: no Rust prepare, native loading, provider transport or real model call occurs.

Maximum signed-value and unpaired-surrogate round trips, exhaustive binding-field mutation, OS subprocess lease behavior, explicit maintenance-write failure/uncertain-commit injection and crash-between-transactions execution remain untested here. The first four recommended cases were disclosed by the implementer; the latter two are additional robustness opportunities inferred from the new transaction boundary. Static control flow is fail-closed on maintenance failure, but this report does not turn that inspection into tested crash/disk-failure evidence. These are nonblocking limitations for the bounded component and do not justify broadening the allowed test suite.

## Preserved scope and remaining gates

No production hardcoded allow, credential read, network transport or send path was added. The synthetic proof/review fixtures are test authority only. Complete binding/payload/budget/proof checks, conservative epoch accounting, immutable snapshots and the authority/file-lease contract remain in place. Raw payloads and metadata still persist as plaintext indefinitely; production retention/encryption policy is absent and disclosed.

ConfiguredChat remains unavailable pending an approved real authority, Application/Service lifecycle installation, production credential-handle existence source, actual Rust prepare integration with this durable owner and eventual limit-enforcing transport. The static acceptance above is not production approval, old-state compatibility, a HOLD release or evidence of real chat. Auto/FullAllow, UI and SyntheticLab behavior remain outside this patch.

## Activity boundary and ownership release

This repair review used read-only inspection only and wrote solely this report. No tests/suites, I04 operation or indirect suite, old database, HTTP/model call, credential access, implementation edit, remote action, branch mutation or additional agent was used. Prior failed/cancelled CI outcomes remain intact; final execution status must come from root's exact-source evidence. Review complete; report frozen, ownership released and writer stopped.
