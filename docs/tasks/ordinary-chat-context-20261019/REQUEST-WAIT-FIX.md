# Second-request completion synchronization

Resumed with user-supplied raw failure evidence, not a new read of denied logs: CI39198796362 at f6af8ac4e76127cffe89f7921e1421ab55a121c6 ran two tests with one failure. OrdinaryChatServiceLoopTest.composeSendUsesPrivateServiceSameRustAgentAndDisplaysPlainProviderAnswer failed at line105, expected 离线普通文本响应, actual empty; runOnIdle was line102. Instrumentation command exit0 was followed by result FAIL1; not acceptance. No previously403-denied resource was retried or accessed by another route.

## Trace and diagnosis

Line105 reads the SECOND submission, after the first answer, Activity recreation, conservative unknown, explicit original-request query, restored receipt and changed current Service epoch have passed. The second text assertion on that same line passed before its answer assertion failed. It does not establish that the second request reached completed.

MuyonLabShell.kt copies chats.snapshot into remembered chatView every100ms (lines55–59). AgentChatReadSession.submit synchronously installs the new request/text with status=submitting and empty answer (lines44–47). Therefore a legal interleaving leaves the rendered status at the FIRST completed request while the actual snapshot already contains the SECOND request with an empty answer. The old status-text-only wait can return against that stale rendering. runOnIdle synchronizes Compose idleness, not the delayed Shell snapshot copy or native work.

The compile-time provider always returns the nonempty offline answer; Rust controlled execution checks binding/history/usage and appends answer_delta, provider_receipt then terminal. The Service returns cursor events; the UI decoder requires a receipt for completed. Epoch identity conflicts/protocol failure and disclosure denial become unknown; cancellation/late-answer becomes outcome_unknown; budget failure becomes failed with controlled reason. None supplies evidence for changing provider/Rust/Service logic here. The stack plus deterministic interleaving supports a test synchronization defect; it cannot independently prove every possible later product outcome.

## Minimal change and retained assertions

Only OrdinaryChatServiceLoopTest changes executable source. After the second click, capture the newly allocated requestId on the main thread and assert it differs from the first. Wait on the same conversation and exact captured requestId reaching status=completed, reading snapshots on the main thread. Keep the rendered status check and every existing answer, identity, epoch, wire/history and attempts assertion. Also assert final requestId/status. No answer-based wait, sleep, retry/resend, production behavior or quota change.

The private requestCompleted predicate is pure and test-only. evidence/RequestWaitProbe.kt copies it verbatim; compile with repository-pinned Kotlin2.2.20 plus state ChatReadContract.kt and FrontendChatPolicy.kt, then java -jar. The companion RequestWaitRed.kt reproduces the old predicate against the same frozen state interleaving and intentionally exits1. RED/GREEN logs retained. GREEN checks wrong request, missing request, all intermediate/failure states, valid completion, and completed-empty still reaching the failing answer assertion. This is synthetic policy evidence, not an Android execution. test_ordinary_chat_device_evidence.py passed all six phase failures and success using disposable fake tools; no SDK/model/network operation in that probe.

## Independent review and execution scope

Read-only independent_review reviewed both whole JUnit methods, relevant runtime and the actual15-line patch. Approved after local targeted GREEN and diff check for dedicated CI verification; made no edits, tests or network log calls. Its independent diagnosis matched the stale Shell copy. All original assertions remain, including the later second-message/answer UI display checks that require rendering to catch up.

Dedicated ordinary-chat-offline.yml is unchanged: only exact ordinary_chat_controller Rust integration tests (15), build-only bindings, API26 arm64-v8a/x86_64 producers, ordinaryChat APK/instrumentation APK/lint and the two explicitly named JUnit classes. The owner negative test touches only its new UUID synthetic owner database. No aggregate suite, old task.db/HTTP/reopen/I04, real model, key/.env, paid call, merge/deploy/delete or PR86/dependency HOLD change. A single normal raw-log GET for the NEW CI39214397484 scoped job117934779992 was storage403-denied. Raw log/artifact retrieval is now stopped, with no retry or alternate route; sanitized denial is retained in evidence/CI39214397484-OWN-SCOPED-READ.json. Native run/job/step metadata remains available. No individual test stdout was obtained.

CI result for the new source must be recorded separately with full SHA. Prior CI39198555958 success does not accept this source; historical CI39198796362 failure remains retained.

## Reproduction commands

Use Kotlin2.2.20 (the version pinned by android-compose-lab/build.gradle.kts). The original RED run used /tmp/muyon-chat-probe/WaitRed.kt, archived verbatim as evidence/RequestWaitRed.kt, hence the retained WaitRedKt stack class. Its intentional assertion failure is the expected RED result. No Android/store/HTTP/native target is involved.

```bash
state=experiments/redesign/android-compose-lab/state/src/main/kotlin/com/mightyoung/muyon/androidlab
evidence=docs/tasks/ordinary-chat-context-20261019/evidence
kotlinc "$state/ChatReadContract.kt" "$state/FrontendChatPolicy.kt" "$evidence/RequestWaitRed.kt" -include-runtime -d /tmp/request-wait-red.jar
java -jar /tmp/request-wait-red.jar # expected exit1; stale first status passes before new answer assertion
kotlinc "$state/ChatReadContract.kt" "$state/FrontendChatPolicy.kt" "$evidence/RequestWaitProbe.kt" -include-runtime -d /tmp/request-wait-green.jar
java -jar /tmp/request-wait-green.jar # expected exit0
python3 experiments/redesign/android-rust-bridge-lab/checks/test_ordinary_chat_device_evidence.py
```

The GREEN predicate was extracted directly from OrdinaryChatServiceLoopTest.kt before compilation. Independent review compared the archived predicate and actual patch, and approved the complete evidence scope. The repository checkout contains no .agents/skills or AGENTS.md; available systematic-debugging, test-driven-development and verification-before-completion skill guidance was consulted, with the explicit user prohibition on aggregate/I04 execution taking precedence.

## New-source terminal verification

Frozen executable source **d1df23200df0ffaccac6edddd3b2115aaa6cfb42** passed dedicated CI39214397484, completed/success attempt1 at2026-10-19T07:19:06Z. Native metadata confirms all four jobs and both Build fixed offline chat APK / API26 exact Compose Service Agent ordinary chat steps succeeded. The unchanged device runner gates on OK (2 tests) and rejects failure markers; this is native CI gate evidence, not downloaded individual stdout. No cancellation/rerun, no source change after that acceptance. Scoped job117934779992 raw log remains403-denied and unretried; no artifacts downloaded. Old CI39198796362 failure remains archived. This source has fresh acceptance; previous success is not substituted.
