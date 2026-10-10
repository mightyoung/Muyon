# Coverage parallel follow-up: exact DA and isolated codec regression

Parent instruction: continue implementation without freezing the final combination SHA; keep old baseline/threshold unchanged, coordinate test-file ownership, avoid F5b shared sources.

## Fixed inputs and owner coordination

- develop: `b142e6591ec66a5e9f0e68fb21e064ce17d0aa9f`
- F5b owner head inspected: `3a6e2556a8252ccb57ff65932f86afbfbd399f80`
- F5c core inspected: `97a2e8263a5f38b5659b4123b78fadea90eb35f9`
- Only existing develop was merged into this coverage branch; no pending F5b/F5c shared-source changes were cherry-picked or edited.
- Ownership request: [F5b PR28 comment](https://github.com/mightyoung/Muyon/pull/28#issuecomment-6094189833), proposed unique `packages/muyon_module_api/test/ui_workspace_collection_decode_coverage_test.dart`. Await confirmation or parent assignment; do not infer approval from elapsed time.

## Evidence limits and implemented work

The old integrated measurement `485c33436def8625de247f90d6c9c132342f44e4` showed API loaded executable lines 1389 → 1402 and hits 1298 → 1309. The +13/+11 aggregate is **not** proof of exactly which two lines are unhit. The old machine baseline has per-file line-set fingerprints, not recoverable DA identities.

`scripts/coverage/da_details.py` now reads the existing eight LCOV reports, unions repeated source/line hits, and emits a small derived diagnostic for the six changed API files. It records fixed source SHA, source-file hashes, loaded DA line identities and unhit identities. No source physical-line count becomes a denominator. No records means unknown; missing suite evidence is listed. This does not change `check.py`, the frozen baseline or comparison thresholds. Raw LCOV remains ephemeral; only the small diagnostic joins the existing summary artifact/log.

Four offline regressions verify exact unhit identities, duplicate hit union, missing reports, unknown unreported source, and malformed DA rejection. Existing 9 checker and 10 gate regressions still run; each Flutter suite remains one invocation.

## Existing test mapping and minimal isolated patch

| Behavior | Current develop | F5b inspected head |
|---|---|---|
| stream/1 vs stream/2 collection admission | `ui_stream_v2_test.dart` | same suite plus owner collection coverage |
| runtime named collection constructor | stream suite uses const comparison, so cannot assume runtime constructor coverage | `ui_collection_test.dart:149` calls `BindingRef.collection(cid)` inside `_table`; do not duplicate it or declare this owner path untested |
| stored collection presentation decode rejection | no test found | no test found |
| workspace restoration with collection presentation | no test found | no test found |
| ordinary persisted projection/override | `ui_workspace_test.dart` tests extracted/override round trip without presentation | same existing test |
| new collection/render/typed behavior | not yet final combo | owner suites remain owned by F5b; no edits here |

`QUALITY-COVERAGE-collection-decode.patch` is a concrete new-file patch with three assertions-driven tests: known collection kind rejected by direct decoder with named ArgumentError, workspace restore propagates the same rejection without mutating the payload, and fact-bound presentation/control draft plus binding/event metadata round trips. It does not require publication, CAS or pending F5c interfaces, and does not call private APIs or mutate production sources. It is prepared separately pending ownership confirmation; Flutter execution is not yet claimed.

## Baseline invariants

Frozen baseline SHA256: `b2b05a9f69990aba1a1197142312f4a7c058b09954e801221198d1b2e96271af`.
Checker SHA256: `687d1ecad4f92fd54946709df52646b5aaed31390feca6ec72a1dcb21ffc3348`.
Both remain unchanged. Nineteen sources lacking loaded executable records and whole-package denominators remain unknown; current owner/final combined source must be remeasured before any gate acceptance.
