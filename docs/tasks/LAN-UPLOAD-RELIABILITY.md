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

- First red PR CI [38019875430](https://github.com/mightyoung/Muyon/actions/runs/38019875430) also fails only the same rename assertion, with the same suite counts and 8/8 analyzer passes. Both first-round runs completed; neither was cancelled. ci-log artifacts: push `11657689749`, PR `11658191747` (confirmed not expired).
- Diagnostic source: `1b46b58622a3b74810259615f50f1af3ad4e70a0`; push [38020616831](https://github.com/mightyoung/Muyon/actions/runs/38020616831) and PR [38020618902](https://github.com/mightyoung/Muyon/actions/runs/38020618902) were launched before either consistency fix was pushed. Their outcomes will be recorded, including unexpected failures.

## Review boundary

The final narrow Claude review should examine `_rememberPersisted`, the rename→stop/deadline check→persist→callback ordering and cleanup, internal diagnostic data fields/error classification, and the new fault/restart tests. Codex static pre-review of the actual rename-order change found no blocker. If the second fault assertion fails, the proposed minimal repair is to write a copied map and update the live map only after write+flush succeeds. No await belongs between that write and the map update/callback boundary.

No claims of atomic disk transactions, crash recovery, async host delivery success, real-device validation, macOS golden validation or historical failure repair are made. Linux Actions uses existing font-dependent skips. No load/stress loop or local SDK test was run.

- Diagnostic push CI [38020616831](https://github.com/mightyoung/Muyon/actions/runs/38020616831): **unexpected compile failure**, supplier_core analyzer `return_of_invalid_type` at test:417. The cleanup Directory delegate declared `Future<Directory>` but forwards `Directory.delete`, which returns `Future<FileSystemEntity>`. The new reliability test file failed to load; its fault assertions were **not executed**. Existing supplier_core tests still report +490 ~4; other seven suites pass with first-round counts. `CI SUMMARY: FAILED (analyze:packages/supplier_core test:supplier_core)`. This is a test-harness defect, not product/root-cause evidence. Fix only the delegate return type and rerun before changing the remaining persistence candidate.

- Diagnostic PR CI [38020618902](https://github.com/mightyoung/Muyon/actions/runs/38020618902): same compile/load failure, not a behavioral reproduction. Other suites pass; integrated host count is +1429 ~3 because this PR checkout includes develop's Dream merge. Both diagnostic runs completed, no cancellation. Laya step is skipped after the failing gate, not claimed tested.
- Harness-only correction source: `4480ab697018cb2f3dff74005b3ff562bce7e3b9`. Only the test delegate return type and evidence text changed in that commit; neither persistence consistency fix is in that source.

## Confirmed injected causes and minimal repairs

- Harness-corrected PR CI [38021348919](https://github.com/mightyoung/Muyon/actions/runs/38021348919), source `4480ab697018cb2f3dff74005b3ff562bce7e3b9`: 8/8 analyzer passes; supplier_core +495 ~4 -3. Both consistency assertions fail with expected false / actual true: rename-before-delivery durable record (test:119) and failed persistence map entry included by the next successful upload (test:313). This is behavioral failure evidence before both fixes are pushed. Other seven suites pass; integrated host +1459 ~3, remaining suite counts unchanged. Gate and all 23 doctor scenarios pass; Laya skipped after failing gate.
- Confirmed code cause A: `_rememberPersisted` executes before awaited final-file rename. Repair: rename → check stopped/deadline → persist inside final-file cleanup try → callback. Nonce/message reservations before body remain intact. Failed rename can be retried after restart; same-process repeat and callback-attempt replay after restart remain 409.
- Confirmed code cause B: the live persisted-message map is mutated before synchronous write+flush. Repair: prune/add on a copied map, write+flush the copy, then update the live map without await. This prevents failed writes from contaminating subsequent successful writes. It does not make disk writes crash-atomic.
- Unexpected third failure: the newly added invalid HTTP length test expected 400 but got no parsed status (test:246), with no diagnostic event. This was an unsupported harness assumption, not a new historical 400 reproduction. [Dart SDK 3.13.0 connection error handling](https://github.com/dart-lang/sdk/blob/3.13.0/sdk/lib/_http/http_impl.dart) destroys connections on early header parse errors without forwarding a request/server-stream error. The revised test records this SDK-specific pre-dispatch observation: bounded close, strictly empty response, no observer event, no callback or inbox file. It does not classify other parser errors or alter the existing 150ms/200 regression.
- The other five new tests pass: complete legal upload gated until actual receiver deadline; bad proof classification; callback failure and restart replay refusal; observer exception isolation; simulated cleanup failure with admission release. In the failing rename/persistence tests, the status, stage/error and cleanup assertions preceding the record assertion passed; those tests are still recorded as failed. The two product regressions and revised parser observation require the next full CI gate to pass.
- Historical CI38016276386 remains unexplained. Neither identified filesystem fault has been connected to that run. No claim of historical fix or flaky classification is made.

- Harness-corrected push CI [38021346242](https://github.com/mightyoung/Muyon/actions/runs/38021346242) independently has the same three failures, 8/8 analyzer passes and supplier_core +495 ~4 -3; other seven suites pass (host +1404 ~3). Both corrected-harness runs completed. Their ci-log artifacts are push `11658498167` and PR `11658627981`, confirmed not expired.
- Normative parser check: [RFC 9112 §6.3 item 5](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3) requires an invalid Content-Length request to receive 400 and then connection close. The observed SDK empty close does **not** satisfy that response requirement. The corrected test records SDK behavior and verifies no application admission; it is not a normative conformance test or a claim that empty close is compliant. Fixing SDK HTTP parsing or replacing HttpServer is outside this minimal consistency patch; no fabricated 400 is added to application handling. Historical parser-layer 400 remains unexcluded.
- Final repair commit includes both confirmed consistency fixes and the corrected parser observation. Full push and PR gates must validate its exact SHA; final immutable source/run results will be recorded on [draft PR17](https://github.com/mightyoung/Muyon/pull/17). Do not merge before green gates and parent-arranged real Claude narrow review.
