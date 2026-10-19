# Ordinary consecutive Sends — handoff

Draft [PR96](https://github.com/mightyoung/Muyon/pull/96) stacks PR95. Latest executable source: **3aaced7281ab7215416841e46edcf8646ad8dfa3**. Only the coordinator wrote source; independent contract analysis and final source/execution review are in REVIEW.md.

**Final acceptance:** CI39195875864 completed/success, attempt1, all four jobs passed at the exact source above. The two-test device/result gate passed; raw instrumentation output remains inaccessible after a one-shot own-job storage403. This is bounded synthetic API26 emulator acceptance, not physical-device or zero-flake proof.

## Actual change and bounded behavior

Backend distinct-request execution already existed. The compile-time no-network fixture now admits exactly two calls (total synthetic ceilings calls2/tokens16384/micros2, per-call8192/1). The existing ordinary Send route and actual durable owner remain; no second demo, provider implementation or authority was added.

The product fix preserves a terminal error reason when an original-request lookup returns no new events. Previously envelope `none` erased the budget reason. Read-only reconciliation now displays its real pending state, blocks Send and decodes against the captured original request. Budget refusal retains failed status and raw `provider_budget_reservation_failed`, shows a controlled explanation, exposes the existing original-request query and describes the available local Save/manual-send recovery. This page cannot install or increase a budget; a trusted configuration update is a separate capability. No automatic resend/refund is added.

The final named device/result gate succeeded as recorded below. The complete test asserts the following through the original conversation/Send control: first success; Activity recreation -> unknown/nonblank Send disabled/attempts1 -> explicit original query restores first identity/answer; current Service epoch observation; second success with fresh request/run/task/attempt/provider receipt, exact second frozen wire input and attempts2; third exact budget rejection without answer/receipt or another attempt; explicit failed-request lookup preserves all fields/cursor/reason and attempts2. The test requires the agent process PID to persist, preserves the historical first admitted epoch, and binds the second request to the explicitly observed replacement controller epoch. The current third draft remains editable/saveable.

No implicit conversation history is passed to the model: each request still contains exactly one checked current user message, and the UI remains a latest-request projection. This is evidence of consecutive ordinary Sends, not a claim of model memory or persistent multi-turn transcript support.

## Verification and retained failure

Local standalone Kotlin contract/policy probe passes. `terminal-reason-red.log` records the actual assertion failure after extracting the previous decoder behavior; GREEN follows the status+reason fix. Initial missing-helper compilation diagnostics are separately retained in policy-red.log. Only the two production pure files, their two check files and a two-function main were compiled/executed; no aggregate state runner.

Local scoped Rust ordinary_chat_controller at 2fc9ecab (the Rust inputs are unchanged at the later source SHAs): **6 passed, 0 failed**, two inherited foreign read/write declaration warnings retained in evidence/rust-scoped.log. No aggregate crate test command was run.

First source 2fc9ecab381a4106d7680fbb540aeaaa73465193: [CI39194418472](https://github.com/mightyoung/Muyon/actions/runs/39194418472) completed/failure, attempt1. Scoped and both ABI jobs succeeded; APK build succeeded; device step failed. Both direct log reads (scoped job117873964382 and package-device job117874458587) returned storage HTTP403 once and were stopped without retry or alternate evidence route. Individual device outcomes and actual failure location remain unknown. The over-strong cross-recreation epoch assertion was found by source inspection and fixed; it is not asserted to be this run's observed cause.

Epoch-corrected source 66e4510b56c33ba87649b783903b08cb7538260d: [CI39194629849](https://github.com/mightyoung/Muyon/actions/runs/39194629849) completed/failure, attempt1. Scoped/binding, both ABI jobs and APK build succeeded; device step failed. Direct own-job117876316177 raw log read returned storage403 once and was stopped. Native GitHub annotation only says exit1, with no phase/runner/assertion detail. Actual device cause and individual outcomes remain unknown.

A further independently proven test selector defect was repaired at 3aaced7281ab7215416841e46edcf8646ad8dfa3: the draft remains populated after Send, so the global second-prompt text matcher also matches EditableText. The display assertion now targets only the submitted bubble using its unmerged ancestor tag. No product behavior, logging or evidence retrieval route changed. This is not claimed as either historical CI failure cause; neither rejected resource is retried. The distinct changed-source test was verified by [CI39195875864](https://github.com/mightyoung/Muyon/actions/runs/39195875864): **completed/success, attempt1**, exact source **3aaced7281ab7215416841e46edcf8646ad8dfa3**. All four jobs succeeded: scoped Rust/binding reproduction, arm64-v8a, x86_64 and package-device. The APK build and named API26 device/result gate both succeeded. That exact script selects only the two reviewed classes and requires `OK (2 tests)` with no runner failure/crash before passing. This establishes the two-test gate through source plus native job/step metadata; direct instrumentation output and phase TSV were not independently read.

The final own package job117878835350 raw log GET also returned storage403 once. No retry or alternate log/artifact route was used. No artifact was downloaded. Terminal/run-attempt/source/job/step metadata is preserved in evidence/CI39195875864*.json; RESULT.json distinguishes the successful gate from unavailable raw output. Both earlier failed runs remain failed and their individual outcomes/causes remain unknown.

## Restrictions and remaining boundaries

I04 old script/task.db -> HTTP -> original-state reopen and all containing suites remain prohibited and unexecuted. PR86/dependency combination HOLD remains. No denied old log/artifact was retrieved. The new 403 restrictions above are recorded separately and were not bypassed.

No .env/key reads, credential setup, real DeepSeek/model/network provider call, fees, merge into main/develop, deployment, force push or branch deletion. Production remains unconfigured/default-deny; real model ID, currency/spend ceiling/price-token proof, authorized installed provenance/profile/credential-generation owner and HTTPS adapter/acceptance remain separate. Physical-device, foreign-exception and migration/retention boundaries from PR95 remain unverified. UI beautification remains frozen.

## Product changes versus test changes and stop state

Product: preserve original terminal reason on empty-event original-request lookup; display actual reconciling state and keep Send disabled during it; show controlled budget explanation and available query/Save/manual-send guidance with the existing query control. No Rust product runtime or model-context assembly changed.

Test-only: compile-time synthetic ceiling now permits exactly two calls; strengthen the one existing Compose scenario and the six-test Rust target; pure contract/policy regression checks; current-versus-historical epoch assertion and submitted-bubble selector corrections. The dedicated workflow only adds this isolated branch selector. No new app entry point or visual redesign.

Source writers stopped at 3aaced7281ab7215416841e46edcf8646ad8dfa3. Later changes are documentation/evidence only and must have no diff under experiments/ or .github/ against that source. Fresh remote readback before sealing: main cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003, develop 0ab2c4f667681b9aacb017f8cd2eea6f576cf78e, PR95 c1c3ef986efd273225f598e468ce4ed25b427f2a unchanged; PR86 remains draft/open at 3f1be180bb009a91e659c113ba5b1916e5360332. PR96 remains draft/open, stacked on PR95 and mergeable, without merge authority or HOLD release. No additional CI is planned.

Authored source/document whitespace checks pass. The retained raw local Rust output has one final blank EOF line flagged by whole-archive diff-check; the evidence log was not reformatted.
