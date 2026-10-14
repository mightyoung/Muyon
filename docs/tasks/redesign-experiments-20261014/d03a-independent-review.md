# D03a isolated experiment — independent fixed-SHA review

**C0 for the isolated experimental seam and evidence intake at `eef7561289421c58e88896fa69c868403ca1d3c5`.** No product recovery acceptance or M03 freeze follows. Non-author reviewer inspected and ran this immutable artifact in `/workspace/Muyon-leader-b-d03a-experiment-independent-20261014`, detached at the exact SHA. Author branch/worktree untouched; no commit/push/merge/install/model/Android activity.

Fixed inputs read: first-batch result `8f8edf95983476a8963ea4cb35ee0a3b948aa862`, develop `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`, D03a contract `40f3cddb6e62baa2374bde288120d2385cb14c3f`, original fixture `55480f06490983a54e38908b043b06b4b02df451` and fixed v1.3.2 source `58fe9c62612d74a973614c41677e62a54332e6d6`. Scope: exactly ten additions, nine experiment files and the D03a experiment task. No product, schema, CI or original fixture edits. Original v1 JSON byte SHA256 remains `9bf16af1bf0098302bd80a6944cccf1535edd6cb24f58eeb8ead137677db00e0`; all 19 groups/72 historical cases remain not_run with actual/golden null.

## Independently rerun evidence

Commands run with PYTHONDONTWRITEBYTECODE=1 from the review worktree; no dependency setup required:

1. `python -B -m unittest discover -s experiments/redesign/d03a-contract/tests -v`: **24 tests, exit 0**, including two actual child-process SQLite crashes with exit 77 and database reopening to inspect committed state/cursor pairs.
2. `python -B experiments/redesign/d03a-contract/run_experiment.py --output experiments/redesign/d03a-contract/reviewer-observations.json --evidence-dir /workspace/reports/redesign-d03a-experiment-independent-20261014/driver`: **63 partial / 9 not_run / 0 complete scenario PASS**, 274 assertion matches / 0 mismatch, exit 0. Fresh per-case observations/comparisons/gaps exactly match committed observations. Temporary reserved output copied outside Git and removed.
3. `python -B experiments/redesign/d03a-contract/mutations.py --evidence-dir /workspace/reports/redesign-d03a-experiment-independent-20261014/mutations`: three actual behavioral RED results, each exit 1; required target tests report AssertionError, not import errors or timeout cascades. Source restored byte-identically, tool’s restored suite exit 0. Generated mutation report copied outside Git, original report bytes restored.
4. Fresh complete suite after all restoration: **24 tests, exit 0**; final `git status --porcelain` empty and diff check exit 0.

| Actual inverse mutation | Independently observed failure |
| --- | --- |
| Remove full cursor-domain rejection | wrong store/scope/stream advances instead of rejection; domain safety test fails |
| Drop old-epoch effect hint before independent current lookup | original effect association disappears; old-epoch receipt split test fails |
| Commit state before cursor update | real child process dies mid-update; reopened SQLite contains mixed new state/old cursor; rollback-pair test fails |

Restored seam source SHA256: `6c270f56c043ac85810e20902435c3a52a2e29aa353f1078407fbe1dfec5a5d0`.

## Oracle isolation and additional non-author probes

AST/read review confirms the DUT seam does not access expected/case_id/group_id/golden; thin adapter passes only deep-copied input facts/stimuli. Beyond the author’s mock-adapter tests, reviewer executed the **real DUT twice for every original case** using separate temporary SQLite stores, changing oracle, IDs and golden fields: **72/72 actual results identical**. For the 63 cases with processed actions, deliberately wrong oracle values caused post-execution comparison mismatch while actual remained unchanged. Thus expected is used only as a comparator, not copied to actual.

Six additional direct real-DUT/temporary-SQLite probes passed: volatile active11/durable10 plus event12 preserves durable10 and pauses for missing11; existing checkpoint11 is not overwritten by input active50 and progresses to12 using committed state11; foreign scope cannot activate existing checkpoint or modify it; receipt hint missing digest creates no lab effect; permitted minimal pending identity persists only non-body metadata; explicitly disallowed minimal identity audit produces no pending row. These are bounded lab/policy checks, not a real provider receipt, signed authorization, message deduplication or body-recovery proof.

Static evidence checks passed: five implementation/test hashes, two safe-report hashes, all twelve external author log hashes, reserved paths, source diff check and clean workspace. Author initial/incremental RED logs contain actual named FAIL/AssertionError, with no load ERROR replacing behavioral RED. Historical initial 33/34 pass classifications are not accepted as complete scenario results; they remain only external historical logs. Current immutable artifact uses conservative partial/not_run classifications.

## Corrections and stop conditions

In-flight review identified overbroad PASS from constants/default counters and an active/durable initialization gap. Fixed artifact now records action mechanisms, observation provenance and layer-limit gaps; compression and duplicate IPC are explicitly unimplemented decisions, aggregate hard-prerequisite flags are not individual authorization checks, connection reopening is not actual process restart, and unmaterialized body is not body restore. New initialization tests first failed then were narrowed to resume from committed checkpoint; reviewer independently confirmed both non-skipping and checkpoint preservation. Reviewer did not fix author code.

No blocking issue remains for this bounded experiment intake. Mandatory product/M03 stop conditions remain:

- Original projection payload/body/digest absent: symbolic lab state/cursor only; no product projection-content equivalence.
- Snapshot integrity/schema/permission/advance proof are synthetic labels; no real parser/signature/proof verifier or transport schema. Stream bootstrap remains unsupported.
- Old-epoch receipt path uses injected lab lookup response and lab persistence. Missing real receipt identity/digest/source validation remains partial; no authoritative Rust/provider EffectReceipt.
- PendingInput tests prove limited metadata behavior. No compression/draft transform, real IPC message deduplication, actual process-restart body recovery or new retention policy established.
- Unknown/new-intent/FullAllow/hard-limit observations are policy decisions and symbolic facts; zero counters cannot prove real executor non-dispatch. Trusted association lacks production signature; real scope/capability/CAS/business execution and receipt transaction absent.
- Supplier actual submission/idempotency/same-name new-intent revision semantics, original seven crash-injection fixture actions and backup-ledger preservation remain unsupported/partial/not_run. Two physical SQLite crash tests cannot be promoted to the original 19-group product gate.

All product runtime cases remain not_run; 52 primary cases and 29 classification cases unchanged; M03 blocked_contract. No claims of Rust/IPC/UniFFI/Android native operation, true secrets, actual user data or model/network execution. Supporting external evidence: runtime-proof.json, observations-fresh.json, mutation-observations-fresh.json, independent-boundaries.json, static-evidence-proof.json, prereview-input-proof.json, and raw logs in driver/mutations subdirectories. Raw logs are not repository deliverables.
