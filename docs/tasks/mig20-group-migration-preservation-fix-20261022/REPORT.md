# Focused schema1->2 migration preservation repair

Base: d50d3415ed3794b10b7277dd95d8faa5c7e1eafe. Branch: task/mig20-group-migration-preservation-fix-20261022. Preflight confirmed clean checkout, exact remote d50d and no previous migration-preservation work to overwrite. The first read attempt was NOT_RUN while the selected environment was still starting; when the existing environment became usable, reads and all work completed normally. No environment/model/permissions or unknown software changes were requested.

## Actual defect and minimal repair

The original version UPDATE could run a trigger deleting legacy-pending, rewriting a historical receipt, injecting a journal row, or inserting a fabricated binding. It verified version2 and the new DDL but not preserved history or empty new bindings. All four actual synthetic SQLite cases returned Ok on the defective code. Native RED retained:1 normal control passed,4 fault tests failed with EXIT101.

The only production change is14 added lines in group_runtime/store.rs initialize_group_runtime. For actual schema1->2 only, it captures the entire ordered legacy journal set BEFORE creating the new table or updating version: intent_id/workspace/project_id/group_id/binding_digest/status/receipt, with exact string bytes and NULL values. After existing version/table-DDL checks it compares all original rows and proves the new bindings table is empty. No writes occur after verification before this same transaction commits. Any discrepancy returns Storage, and transaction drop rolls back version, DDL and journal mutations together.

The witness is not applied to an already-version2 path, so actual bindings created by later confirmed local operations remain valid on repeated initialization. This changes no schema/API/FFI/default/role/grant/gateway behavior. No owner/lib/FFI file or unrelated security scope was modified.

## Native tests and final evidence

Five added test functions use actual local registration/start/rejection/storage-failed Register facts, then reproduce the exact old v1 namespace. Four faults DELETE pending, rewrite receipt, inject journal and inject binding now return Storage, preserve the complete old journal/receipt set, leave version1 and leave no new bindings table. The fifth control proves normal migration preserves all old rows, legacy committed/rejected reads stay actual/read-only, missing legacy no-group identity stays Unknown without creating a group, and actual new v2 configuration/binding remains usable through repeated initialization.

| Verification | Result |
|---|---|
| New migration tests |5/5 GREEN; original1pass/4fail RED preserved |
| Full current core suite |306 passed,0 failed |
| Bridge target |53 passed =35 dedicated+18 repeated source tests;5 new functions this repair |
| Existing store target |65 passed =47 group+18 repeated source tests |
| Standalone runtime/governance with warnings denied |20/21 passed |
| Fixed document-core10d actual-library composition |82+94=176 executions passed; repeated29 document tests per harness |
| Formatting, frozen hashes and source/document diff checks |passed |

Counts are executions;306 includes bridge53/store65 and repeated source tests. Do not count306 or176 as new distinct tests. Historical301 results do not cover this defect and were not reused as its verification. Raw RED/GREEN logs, final command/timestamp/exit/source-hash manifest and independent review are retained under this directory. Existing dependency read/write runtime extern warnings and pinned document-core dead-code warnings remain recorded. Raw log blank EOF lines are preserved verbatim and excluded from source/document whitespace checking.

Reproduce current core with `python3 docs/tasks/mig20-group-migration-preservation-fix-20261022/verify.py`. Reproduce pinned document-core combination with `python3 docs/tasks/mig20-group-config-bridge-20261022/verify-combination.py` (uses CURRENT group sources, fixed10d and the existing disposable documents-import harness shim). No dependency/lock/install change. Independent final results are in INDEPENDENT-REVIEW.md.

NOT_RUN: Android/FFI integrated acceptance, real model/search/provider execution, deployment. Existing protected-owner canonical/gateway hooks and business_worker documents-import seam remain outside this focused migration fix. No action denied or uncertain remote write; push/fullSHA verification is reported in the delegation final response. main/develop and original saved checkout are checked before delivery.

Independent final review passed: exact immutable d50d old store with the same five tests reproduces1pass/4fail EXIT101; current same assertions5/5 pass. Four independent additional controls pass: NULL vs text-null, trailing receipt whitespace, same-cardinality intent rename, and an actual existing-group legacy pending. For the latter, owner/admin repeated read returns PendingOriginal/null/current_group_management; a member is rejected; migration/query/v2 initialization preserve journal/grants/groups/runs/nodes/events and produce no binding or replay. Independent bridge53/store65 pass. No remaining important finding or blocker reported. Base RED/current GREEN/extra controls/native logs and exact source snapshots/hashes are in evidence; this is focused validation, not a claim that the defective d50d base was safe.
