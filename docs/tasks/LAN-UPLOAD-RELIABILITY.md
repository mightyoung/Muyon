# LAN upload reliability — bounded investigation

Branch: `task/lan-upload-reliability`; baseline: `b8a9a52308112c9eb2e3a0d2a2f52c87c37b46b9`.

Historical second legal upload HTTP 400 (CI 38016276386) remains unexplained. PR14's diagnostic run did not reproduce it. Do not infer server deadline from client latency, increase 150ms, remove assertions, or label the failure flaky.

Predeclared matrix (each CI run is retained, including failures):

1. Existing 150ms trickle deadline → cleanup → legal upload 200; observe receiver stages and deadline, not client time.
2. Legal complete upload held at a stage until the actual receiver deadline fires; assert 400, no callback/file, counters released, next independent upload 200.
3. Real filesystem rename failure before delivery; assert 400, cleanup, no durable delivered-message record. Keep before-body nonce/message reservation (409 in the same process).
4. Real persistence failure and callback exception; classify stage/error without sensitive values, preserve replay semantics once callback has been attempted.
5. Stop at a pending upload, duplicate requests, idle timeout and absolute timeout; existing trust/replay/restart/security suites and full CI gate.

Diagnostics must be opt-in, in-process, imported from src only, with fixed stages/error categories and numeric cleanup state. Never emit exception text, payload, path, address, IDs, certificate, keys or signature. Timing gates are test capabilities, not network interfaces. No new dependency, workflow, credential or local SDK.

Only fix a reproduced failure. Persisted replay records currently precede file rename; test whether a failed rename wrongly records an undelivered message. Callback failure can have side effects, so never promise automatic safe retry or roll back replay after callback invocation. Crash consistency and async host delivery are outside this narrow patch.

Full CI via existing Actions; raw logs stay in Actions or /tmp, summaries and exact SHAs recorded here. Real Claude narrow review is arranged by the parent before merge. No merge/deploy/main/force push/branch deletion.

Before the diagnostic implementation's first CI run, matrix additions were fixed: malformed HTTP content length (400 before upload admission; HttpServer may not surface parser errors), observer exception isolation, and an explicitly simulated staging-directory deletion failure. The deletion exception is a test injection, unlike rename/persistence failures caused by real filesystem conflicts. No load loops, wall-clock latency comparison, or opportunistic reruns will be used to select green results.

Receiver elapsed time is measured from diagnostic attempt creation; it is not the timer's start time. Only the timer callback's `deadline` event proves that the receiver deadline fired. Unknown stopped/retained state is null outside cleanup snapshots.

Remote develop advanced during execution to `cf672164e4f6c3e7beea8029c8be735e33c3bf19` (Dream merge). Task fork was the then-latest develop. Its six changed files do not touch LAN, and this task does not edit Dream/resume files. A diff of the historical source `2cb616c429a5e27cf3b43e7af93f7eb5d9efca93` versus the task baseline for lan.dart and lan_security_test.dart is empty.

Static inspection during preparation found a second consistency candidate: `_rememberPersisted` mutates its in-memory map before writing the file, so a failed write might be included in a subsequent unrelated successful write. Before the diagnostics run, the persistence-fault test was extended to assert that the later durable map contains only the successful upload. This is a candidate pending failing execution, not a proven historical cause.

## Execution evidence

- Red source: `4534da73e2a1ee1469c3f0082c6d5ef69c72eae8`.
- [Push CI 38019861251](https://github.com/mightyoung/Muyon/actions/runs/38019861251): failure, 8/8 analyzer passes; supplier_core `+490 ~4 -1`, failure only `rename failure never records an undelivered message durably`, expected seen-file existence false, actual true (`test:108`). Other seven suites pass: module_api +68, muyon_ui +323 ~152, prototype +39 ~1, research +220, host +1404 ~3, ui_preview +15, inquiry +289 ~47. Gate regressions pass; doctor all 23 scenarios pass. `CI SUMMARY: FAILED (test:supplier_core)`.
- This proves the new injected rename problem; it does not reproduce or explain historical CI38016276386.
- Commands: `git fetch origin develop`; `git switch -c task/lan-upload-reliability FETCH_HEAD`; `git diff 2cb616c429a5e27cf3b43e7af93f7eb5d9efca93 b8a9a52308112c9eb2e3a0d2a2f52c87c37b46b9 -- packages/supplier_core/lib/src/lan.dart packages/supplier_core/test/lan_security_test.dart` (empty); `git diff --check` (pass); `python3 scripts/test_verification_gates.py` (9 pass). No local Dart/Flutter tests were run because neither SDK is installed.
- Actions runs the unchanged `bash scripts/ci.sh` gate (all packages analyzed and all suites run) and retains ci-log artifacts. Raw logs are not committed.
- Codex read-only static pre-review: no leak/network-interface blocker; replay/restart tests and observer contract clarification requested and added. It is not Claude review. Real Claude review remains assigned to the parent.
