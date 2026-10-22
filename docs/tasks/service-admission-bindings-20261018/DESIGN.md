# Trusted Service admission callback binding

Status: independently approved (including UniFFI compiler constraint correction); bounded implementation in progress.
Base: `fc8ffd7e061736fdf9f4897d7c1c7914d429400a`.
Worker A owns only the files below. Root owns CI, remote publication and general handoff.

## Problem and bounded result

Android's actual Service owner can currently supply current scope, provider metadata and credential-handle existence. Rust's `ServiceProviderHost` already requires payload review, conservative reservation and atomic final admission, but `CallbackProvider` returns unavailable for all three. Add an explicit trusted bootstrap callback seam for those operations, with unavailable defaults. A deliberately synthetic test owner may exercise prepare/final_admit through the real Rust adapter. No owner, reviewer, quota ledger, credential capability or transport is installed by this change.

The Service controller's ConfiguredChat remains `configured_transport_unavailable`; no new UI/Binder request can prepare/admit a payload. No permissions, network, Dart implementation, production source installation or paid calls change.

## Proposed contract

- Add a typed `ServiceOwnerAdmissionBinding` UniFFI record containing the complete existing ProviderBinding: full profile/destination/capabilities, profile/policy/grant revisions, authorization owner, model/outbound authorization, budget revision/quota proof/remaining counters. It excludes the availability-only Boolean, which is not authority.
- Add callback methods for review(binding, exact payload bytes) -> Boolean; reserve(binding, request id, exact payload bytes, full call budget) -> optional reservation id; commit(reservation id, binding, request id, exact payload bytes, credential profile id/ref) -> optional record id. UniFFI0.32.2 forbids exported Rust trait default bodies (compiler failure retained); callback implementors must explicitly supply all methods. Kotlin trusted owner-source methods also default deny/null. Kotlin adapter catches owner exceptions and denies/null. There are no generated Kotlin interface defaults: regenerate and explicitly implement every new method in ServiceHostBindings.callback, then compile all Kotlin callers. Existing trusted Kotlin owner-source implementations retain defaults; the generated callback interface itself has no source-compatibility promise.
- Convert snapshots without JSON, lossy hashes, normalization, omitted fields or accepting Binder-supplied owner data. Bindings come from `current_provider`, preserving the existing generic Rust checks around review/reservation/commit.
- Existing `ServiceProviderBridge` performs its exact-current checks and accepts only valid nonempty ids. Its post-reserve full binding comparison includes budget revision/counters: reservation holds must not silently mutate that exposed snapshot and claim success. Drift safely denies and may strand a hold; the durable owner owns release/expiry, with no automatic resend. CallbackProvider delegates only to the bound trusted callback; absence or rejection maps to the existing generic fail-closed errors.
- Commit receives profile id/ref only for owner correlation. The stable existence-only sentinel remains inside Rust, is never exported to Kotlin and never acquires secret-read/send capability. It does not prove real handle identity or rotation. No handle value is read or configured. A returned row is metadata admission, never proof of transport or a usable secret capability.
- Trusted durable owner MUST atomically recheck current binding, credential existence, reservation/payload/request/budget identity and consume reservation once. The existing commit core port has no CallBudget argument: the owner must look up the complete budget captured durably with the reservation during reserve, validate it at commit, and never reconstruct or default a budget. The owner must prove conservative total input plus output tokens, one call/choice and spend for the exact payload; wire token caps alone are insufficient. Reservations are owner-bound and capture the entire CallBudget. Replay, stale reservations and concurrent quota require that owner's durable implementation. A synthetic in-memory ledger can prove delegation/rejection behavior only; durability and real-owner installation remain NOT_RUN/unbound.

## File ownership

- `experiments/redesign/android-rust-bridge-lab/core/src/service_host_bridge.rs`
- `experiments/redesign/android-rust-bridge-lab/core/tests/service_host_bridge.rs`
- `experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/agentipc/ServiceHostBindings.kt`
- Genuine generated `experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt` (confirm actual checked-in generator path before writing; never manual edit).
- `experiments/redesign/android-compose-lab/app/src/androidTest/kotlin/com/mightyoung/muyon/androidlab/agentipc/ServiceHostBindingsTest.kt` (3 metadata-only JUnit tests, approved by root; uses existing androidTest dependencies).
- `docs/tasks/service-admission-bindings-20261018/**`

No host core, UI layout, Service lifecycle, existing workflows or general handoff edits.

## Synthetic TDD and exact boundary

First add adapter tests exercising new callbacks; compile RED is retained separately from behavioral RED. Then add minimum implementation and rerun only named targets. Tests cover complete snapshot and unchanged bytes/budget/request/reservation mapping, missing/default owner denial, explicit review rejection, failed reservation/commit, revision change before reserve/final commit, and a synthetic ledger refusing replay/stale reservation. Existing scope/metadata/existence tests remain.

Exact Rust commands (root-provisioned isolated toolchain only):

```
CARGO_HOME=/workspace/toolchains/cargo RUSTUP_HOME=/workspace/toolchains/rustup PATH=/workspace/toolchains/cargo/bin:$PATH cargo test --locked --manifest-path experiments/redesign/android-rust-bridge-lab/core/Cargo.toml --test service_host_bridge -- --nocapture
CARGO_HOME=/workspace/toolchains/cargo RUSTUP_HOME=/workspace/toolchains/rustup PATH=/workspace/toolchains/cargo/bin:$PATH cargo build --locked --manifest-path experiments/redesign/android-rust-bridge-lab/core/Cargo.toml --features bindings
```

Generator command/cmp follows `.github/workflows/service-production-bridges.yml` literally from its working directory. Root runs Kotlin/Android checks in scoped CI if local compiler unavailable. Rust `--test service_host_bridge` selects only that integration binary; it compiles host lib without its `cfg(test)` HTTP recovery module, does not execute any other target, has no HTTP/process reopen test, and cannot trigger I04. `cargo build --features bindings` executes no tests. Never run unfiltered cargo, generic CI, HTTP/recovery targets or denied original-state action. All RED/failed/cancelled/NOT_RUN outcomes are retained.

## Acceptance and limits

Independent design acceptance precedes implementation. Independent immutable implementation review follows final source freeze. Genuine binding regeneration/cmp and scoped Kotlin/API26 compile remain required evidence; root controls remote runs. Success demonstrates an available trusted admission seam only. Real durable owner/approved budget, production installation, actual secret handle use, transport, billing, model connection and ARM64 device runtime remain NOT_RUN. I04 and PR86/dependent combinations stay HOLD; no retry/rewrite/split/alternate executor.
