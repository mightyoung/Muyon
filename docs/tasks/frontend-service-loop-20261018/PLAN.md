# Frontend/service loop Implementation Plan

> **For agentic workers:** Use test-first implementation after ownership handoff;
> an independent worker implements the isolated oracle and a fresh reviewer checks a fixed SHA.

**Goal:** Preserve the approved UI and connect Send to the private Android Service,
the existing Rust Agent and trusted supplier-name read, with streamed results and receipts.

**Architecture:** Extend a separate private business contract on the existing Service
and controller. Keep source authority and native execution host-owned; client state
only renders bounded, identity-checked observations.

**Tech Stack:** Android API26, Compose, AIDL, UniFFI, Rust; Python stdlib contract oracle.

**Spec:** [CONTRACT.md](CONTRACT.md), based on fixed NEXT-REAL-LOOP handoff.

## Global constraints

- Only `docs/tasks/frontend-service-loop-20261018/**` and
  `experiments/redesign/frontend-service-loop-lab/**` are writable in this phase.
- B06 is the sole integration owner until parent explicitly hands off ownership.
- Preserve subprocess isolation and trusted built-ins; minimum Android API26.
- No main/develop integration, force push, branch deletion, deploy, spend or credential setup.
- No I04 retry/reroute; dependent merges stay held. Synthetic tests are not live-model evidence.

## Review focus

- Lost Binder reply after durable admission must reconcile without a second execution.
- Reconnected lease must not overwrite the original run's admitted epoch.
- Revoked authority must hide current values while retaining authorized historical receipt metadata.
- Cancel/complete races must retain the actual settled outcome and original receipt.
- UTF-8 boundaries, replay gaps and retired observers must not corrupt another conversation.

## Task 1: bounded contract oracle (authorized now)

Create only files under `experiments/redesign/frontend-service-loop-lab/`.
Consumes the proposed fields/events in CONTRACT.md; produces independently executable
validation and reducer tests, without importing or replacing existing runtime code.

- [x] Write tests for strict submission, matching selection/revision, receipt identity,
  ordered/replayed/terminal events, cancellation and transport loss.
- [x] Run RED and preserve the failure log before implementation.
- [x] Implement the smallest stdlib oracle; run GREEN and preserve command/output.
- [x] Commit the isolated changes and request independent fixed-SHA review.

## Task 2: sole integrator prepares production contract (pending ownership)

Exact path prefix `experiments/redesign/` applies to all lab paths below.

| Required ownership | Exact files/directories and responsibility |
| --- | --- |
| Service and Binder | `android-compose-lab/app/src/main/aidl/com/mightyoung/muyon/androidlab/agentipc/**`; `android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/agentipc/**`: private typed submit/events/lookup/cancel, bounds, lifecycle |
| State/wire | `android-compose-lab/state/src/main/kotlin/com/mightyoung/muyon/androidlab/AgentService{Contract,Wire,ClientState}.kt`, new business DTO/reducer files and corresponding `state/src/test/**` |
| Rust lifecycle | `rust-agent-host-lab/core/src/service_{types,controller,runtime}.rs`, `service_evidence.rs`, `lib.rs` and corresponding `core/tests/**`: durable payload binding, events, result/receipt projection |
| Native bridge | `android-rust-bridge-lab/core/src/**`; generated `android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt`; related bridge checks |
| Store/authority | New `rust-agent-host-lab/core/src/` adapter files and `core/tests/`; reconcile C's `supplier_{sqlite,store}.rs` only after inspecting its fixed SHA |

- [ ] Parent receives B06 final SHA, CI disposition and stopped-writer confirmation;
  recheck remote refs and choose the actual combined source (not this inventory base).
- [ ] Freeze Kotlin/AIDL/Rust typed fields, bounded decoding and stream retention policy.
- [ ] Write failing codec/admission/recovery tests before adding production methods.
- [ ] Wire the existing controller and Catalog; do not add a fixture-only alternative route.
- [ ] Implement synthetic schema12 Android readonly adapter plus explicit test-only
  authority composition; production bridge remains a separate, fail-closed acceptance gate.

## Task 3: frontend adapter (pending separate ownership)

Modify `android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/`:
`conversation/ChatPage.kt`, `MuyonLabShell.kt`, new conversation execution adapter/state/tests;
entry wiring only if necessary in `MuyonLabApplication.kt`/`MainActivity.kt`.
Consumes the frozen production Service DTO; produces Send/Cancel/stream/receipt UI behavior.

- [ ] Write failing tests: input reaches typed submit once, cancellation only requested,
  Binder loss calls lookup only, stale display-generation response is ignored.
- [ ] Preserve layout/assets and local Save; wire real Send and read result/receipt display.
- [ ] Run Kotlin state and Compose device tests against the new combined source SHA.

## Task 4: combined platform proof (pending integration + toolchain)

Integrator may need `android-compose-lab/app/build.gradle.kts`, native build scripts,
bridge staging/verifier configuration and targeted workflow changes. These are currently
outside write authorization; do not change shared Gradle preemptively.

- [ ] Enforce min26 in actual combined Compose source (inventory base still has min24).
- [ ] Build both native ABIs and Compose APK with optional native inputs from the same SHA;
  inspect manifest, ABI contents and source/build identities.
- [ ] API26 device test happy read plus wrong object/revision, revoked/missing authority,
  Binder loss after admission, reconnect/lookup, cancellation and UNKNOWN settlement.
- [ ] Save logcat/test reports and original receipt correlation; fresh fixed-SHA review.
- [ ] Record PASS/FAIL/NOT_RUN separately for platform/synthetic store/production authority/live model.

Do not dispatch the budget-gated manual artifact workflow. Its documented Flutter
plugin-regeneration concern must be resolved before anyone relies on it for packaging.
