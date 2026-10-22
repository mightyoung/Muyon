# Independent final graph and owner review

Reviewed immutable source `802844fc`. Read-only; reviewer executed no build, test, generation, network, credential or remote operation. Generated Kotlin is knowingly stale at this SHA and must be genuinely regenerated before claiming build readiness.

## Graph ruling

The exact local bridge build and local UniFFI generation commands at the end of CONTRACT.md are permitted: build with a separate `/tmp/muyon-chat-bindings` target directory and actual source SHA, then invoke that locally built pinned CLI with `generate --library .../libmuyon_android_contract_bridge.so --language kotlin --config uniffi.android.toml --out-dir /tmp/muyon-chat-generated --no-format`. The config selects immutable Kotlin Android bindings and the expected namespace. No application/service/test is started by those commands. Copy only their genuine generated output. A changed/generated commit requires final source identity and binding reproduction evidence; 802844fc cannot be called the completed generated source.

The source graph of `.github/workflows/ordinary-chat-offline.yml` is permitted for its exact `lab/ordinary-chat-wiring-20261018` push trigger. No I04 execution route was found:

- `scoped` runs only `ordinary_chat_controller -- --test-threads=1`, bridge build-only, local UniFFI generation and byte comparison. No unit/aggregate suite is selected.
- ABI producers call `android_gate.py --abi` for the two named ABIs. It installs SDK/NDK prerequisites, fetches locked dependencies, builds only the bridge release library, and inspects ELF/JNA bytes and API26 imports. Its imports from linux_gate/package_gate define helpers; they do not invoke those modules' aggregate main functions.
- `lifecycle_package.py --ordinary-chat` selects only `:app:assembleOrdinaryChat`, `:app:assembleOrdinaryChatAndroidTest`, `:app:lintOrdinaryChat`. It verifies same-source ABI/generated-binding inputs, stages new packaging inputs, inspects APKs and rejects INTERNET permission. The app preBuild verifier reads explicit staged inputs. No connected-test/check/checkState/legacy runner is selected. `state` checkState is attached to check, not these app assemble/lint tasks.
- The sole instrumentation selection is `OrdinaryChatServiceLoopTest`, one test, on a newly created API26 AVD with a distinct ordinaryChat package. The test clicks existing Send, checks text/receipt/synthetic flag/private process, reads only the new `muyon-ordinary-admission-v2.sqlite` chat_attempts table, recreates the Activity, and checks the one-call ceiling. Activity recreation retains the active application/Service; it is not the forbidden old Agent/task.db/HTTP reopen scenario. No other instrumentation class is selected.

This is a graph allowance, not a passing source review or runtime result. The owner issue below prevents claiming the full field contract is complete even if this workflow passes.

## Draft PR trigger audit

For a PR stacked on the existing PR94 lab branch, no aggregate PR test workflow matches the base branch. For the intended source `lab/ordinary-chat-wiring-20261018`, Android Compose's PR job also requires a `lab/android-compose-` source prefix and skips. Android Rust bridge's develop-only PR selector assigns `unselected` for this source prefix and therefore does not run its normal full aggregate; a lab-base stack avoids its PR trigger altogether.

Do not create the Draft against develop/main: `ci.yml` matches those PR bases and unconditionally invokes `scripts/ci.sh` to analyze/test every package, outside the permitted explicit graph. This review does not claim that script is free of I04. Draft status does not prevent the opened event. The other fixed-tree workflows use manual triggers or disjoint push branches, including task/**, review/** and their named lifecycle/service branches. The ordinary chat lab push selects only its new workflow. No pull_request_target or workflow_run chain exists in the reviewed tree. Preserve the exact source branch and PR94 stack base; do not change existing gates to bypass a restriction.

## Blocking owner contract issue

`DurableServiceHostOwner.reserveBudget` freezes binding, scope, payload, request ID and budget/proof. Its ordinary `scopeBytes` encodes the static authority conversation (the fixture uses `*`) plus credential identity/generation, but not the actual conversation, task, attempt or input_ref. The wire payload includes only model and user message. `commitAdmission` therefore cannot freeze these missing actual context fields.

`exchangeChat` receives that context for the first time. It checks task/attempt/input_ref only for nonblank values. Its expected authority conversation is copied from the incoming context conversation; `currentChatAuthority` likewise copies any supplied conversation. Consequently, before its first attempt the same committed admission/payload can be submitted with a different nonblank task, attempt, input_ref or conversation and still pass owner validation. The one-shot marker then permanently binds the attacker/bug-selected context instead of validating an already frozen one. This violates the explicitly required same-owner send binding even though the shipping transport is only synthetic.

Fix within the existing owner: freeze exact versioned context (or its deterministic digest) at ordinary reserve/commit and compare it byte-for-byte at send. Verify request ID/input_ref relationship and actual task/attempt/conversation rather than accepting self-consistency. Pass context through the existing bridge/owner admission protocol or otherwise use an immutable same-owner prepared record; do not introduce another authority. Add a new-root focused negative test mutating each context field between commit and exchange and asserting zero attempted handoffs. Preserve the source proof that this test never opens historical task state or uses HTTP.

## Owner checks that pass source inspection

The implementation reuses ServiceAdmissionAuthority's guard and the same DurableServiceHostOwner. Reserve and commit run with monitor → authority guard → SQLite transaction; exact binding/payload/proof/current scope are rechecked. The scope snapshot carries credential identity/generation, so reserve-to-commit rotation rejects even though the callback commit DTO only carries profile/ref. Send checks exact current capability and stored scope/binding/payload; its attempted row is inserted and transaction committed before calling fakeExchange while holding the authority guard. Unique chat_attempts identity rejects a second exchange. Consumed reservations never refund. A different generation after commit rejects before attempt.

The synthetic fixture declares one-call/full quota bounds and validates the complete closed body. Production authority/transport are absent and rejected. Ordinary schema/file is separate from existing admission v1 and task state. The fixed ABI/package path does not install/read user credentials. Default Application uses an unconfigured host. Provider evidence now persists profile/endpoint/revisions/owner/handle generation and usage beside the answer; Agent reported_usage is implemented. The input bound now derives from full serialized frame bytes, resolving the earlier fixed-512 underbound concern. These remain explicitly synthetic proof/usage, not real model token prices or currency ceilings.

## Evidence limits

Native target safety is approved; broader drift/exhaustion/output-secret/storage-failure acceptance is not proven by its three cases. Android test source demonstrates the intended Compose route but has not been run by this reviewer. Stale generated Kotlin and the context-freeze defect remain concrete work before completion. Real provider model ID, accepted currency/expense ceiling, price proof, production endpoint/profile and an authorized credential capability provider remain unavailable. No real DeepSeek success may be claimed.

I04 old task.db → HTTP → original-state reopen remains denied, including rewritten, split, indirect suite or alternate-environment execution. Old 403 evidence downloads remain prohibited. HOLD/PR90/Dart8 restrictions remain. Physical devices and real foreign constructor/destructor exceptions remain NOT_RUN. Reviewer writer stopped after this file.
