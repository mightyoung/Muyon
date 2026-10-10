# F5c H1b implementation and five-blocker review closure

Status: proposed, no develop/main merge. Native implementation follows the parent's explicit exclusive assignment of state.dart, surface.dart, publication.dart, ui_contract.dart and corresponding tests. F3b retains apps port/PR18 tests; F5c provides patches/review; parent is sole integrator.

## Sources and independently verified baselines

- 480b0e0bd34b28a6a1e124c87d042ac0677223af: both exact-head CI38029997319 and CI38029994065 completed success, gh run watch exits0, independently read back head/status/conclusion.
- a9f0c4cdcc65fa746de548c348ad144d87c928eb: pushed fixed constructor/real port consumption baseline, local API190/UI499 PASS. Later confirmed-record/nodeId/test changes are not covered by that result or its CI.
- F3b live port read-only source pinned11c6af36d94da4df4bc893f06b74400fcd779eb8 matches the constructor documented in AIUI-5-F5c-live-injection-contract.md.

## Implemented H1b

The sole coordinator now supports an already validated same-snapshot plan bridge that retains publication floor and invalidates pending requests; immutable mutation fences over a monotonic clock; and opaque owner/base/epoch-bound split recompute requests with synchronous completion/failure. The existing asynchronous standalone convenience wrapper reuses those primitives. There is no second evaluator/router/runtime.

Controller current derives only from coordinator current. Host work is awaited before layer preparation. Its same-layout raw candidate removes event refs disallowed by the returned intent, then uses the existing validator. Session layer preparation and final fence precede synchronous publication/install; listeners run only afterward. No callback or await intervenes after the final freshness check. Actual session mutation clocks cover view/source/edits/adoption/restore/plan changes. Same external controller snapshot rebuild preserves mounted fields/focus. Pending locks and original receipts remain in the same controller; duplicate semantics are preserved.

Legal non-view edits start one real UiRecomputePort call with frozen complete scalar state and a full host token. UiRecomputeResult remains snapshot/intent-only; there is no extra batch injection and no second adapter evaluation. F3b currentPlan must resolve the actual accepted capability per invocation. Runtime admission is checked in controller and direct session event dispatch for read-only/outdated/recomputing/pending. Workspace readOnlyProbe injection and full 33-widget visual loading/error/degraded projection remain distinct caller/component follow-ups; this report does not claim they are all wired.

## Review findings with actual evidence

1. Parent's additional unreadable-draft finding: old event gate rejected a legal correction to a retained invalid scalar. Witnessed expected applied/actual invalid. Local editField now reaches the existing payload/spec validation; rejected correction and wrong type retain original readable value/revision, accepted correction clears the reason and increments draft revision. Non-edit gates remain restrictive.
2. Public inline4236613892: view key classified as confirmedRecordRef bypassed the draft-only guard. Paired non-view/view and draft/confirmed-record cases witnessed missing view_business_input before the fix. Every typed business input is now checked against view specs regardless of classification, at the shared node/plan validator and direct event defense.
3. Public inline4236613894: row open callback lacked the originating node ID. Actual two-table/same-object rendered clicks witnessed empty origins instead of target/second. UiObjectOpen now requires named String nodeId; dispatch sends the captured node's ID. F4c can construct its return anchor and still owns final scope/lease/source checks after awaits.

Old public4236410550 was previously fixed by the draft guard;4236410552 sorting was adjudicated against the adopted String.compareTo rule. The parent subsequently delivered the full five-item report directly. Its source was static review; our independently executed behavior regressions and exact closure matrix are in AIUI-5-F5c-five-blocker-review.md. All five findings are now repaired and covered; earlier public findings are not substituted for the complete checklist.

## RED to GREEN evidence

External logs only in /tmp/aiui-f5b-logs; no raw logs committed:

- unreadable-repair-red.log: legal edit actual invalid; green retains invalid correction and accepts valid one.
- h1b-core-real-red.log: original16 PASS + new4 behaviorFAIL; core/session integration later31 PASS.
- session-fence-real-red.log: final source/view mutation actual published instead of staleToken; fixed actual session clock.
- h1b-mounted-real-red.log: actual rendered edit produced0 host inputs instead of1. Initial fixture compilation failure is excluded. Mounted GREEN preserves same session/controller/field controller/focus and sequential accepted bases.
- view-confirmed-record-red.log and row-origin-real-red.log: real validator/callback failures, restored GREEN.
- h1b-surface-integration-matrix.log:6 PASS, including reverse completion, both-object final probe, readonly direct event gate and actual publication retaining pending/receipt.

Final full package source checks: API190 PASS, UI505 PASS. Strict flutter_lints: own code/tests and whole UI have no diagnostics; only prior context.dart:33 and ui_recomputation_contract_test.dart:246 owner-external infos remain. Temporary analysis configs are removed. No download, proxy replacement, credential/security change or paid channel.

## Remaining blockers and ownership

F3b must inject its real live port/full token probe into the two original mounted PR18 Widget tests, preserve30/40/extracted2/same-controller/database total_changes assertions and test sequential accepted bases. The deferred protocol fixture here is not a formula or database acceptance claim. Consume the exact shared-core commit, not independently guessed constructor/batch policy.

The complete private report was delivered directly by the parent and no longer blocks this task. The earlier cross-thread evidence-request message was rejected by automatic approval; no message was sent or workaround attempted. No cross-thread messaging permission is needed to use the report now provided.

Maintain one writer for shared files. This task retains assigned core ownership until parent reassigns it; apps/workspace host injection and navigation scope ownership are not taken over. No production catalog switch, runtime activation or merge approval is inferred from these checks.

## Final synchronous-reference repair

A further actual controller subclass regression showed the public overridable current getter could run after coordinator publication but before session installation, mutate view and leave the objects split (expected published, actual staleToken). The controller now retains its constructed session privately and uses the private coordinator capability during the final install; no public virtual host getter is read in that section. The public session/current API remains available. post-probe-getter-real-red.log and post-probe-getter-green.log witness failure/restoration. The controller integration matrix is now7 PASS. Final UI full regression is506 PASS; module API source is unchanged from its final190 PASS. Strict own-file/UI analysis has no diagnostics, with only the same two external-owner infos. Temporary configs removed again.

## Full five-item closure supplement

The real StatefulWidget bottom callbacks now capture their rendered widget and refuse a callback once that widget has been replaced, before local mutation or dispatch. Choice freezes option identity at build time; it never reinterprets a saved old index against new option IDs. Tabs/Disclosure retain the same State and current controlled behavior. Both actual InkWell and Semantics closures are tested across accepted publication and rebuild. Initial typed Tabs values missing from the current child list are accepted and render home without rewriting the scalar. Runtime unknown child events remain rejected.

The same-object/two-table regression now uses actual tester.tap and asserts zero business calls. The rebase rule is exactly String '2' or '4', with controller/direct-session unresolved business input rejection even when active value, host draft and revision match. Temporary gate removal is a separately labelled negative control, restored before any full run or commit. See the shared five-blocker checklist for source, test and evidence boundaries.

Final five-item closure source: module API190/UI514 PASS; strict own-file/whole-UI diagnostics0, with only the same two external-owner infos. Temporary configs removed. Exact CI for this additional source must be checked independently of the prior9a dual-green baseline.
