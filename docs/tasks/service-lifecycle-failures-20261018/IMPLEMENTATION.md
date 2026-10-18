# Actual Service failure lifecycle implementation

Source parent: 7181aed3 (contract/plan baseline). Implementation commit is the commit containing this report; obtain its full immutable SHA from `git rev-parse HEAD`. No push, PR, workflow dispatch, test, compile, lint or executable verification was performed by the implementer. All runtime results remain **NOT_RUN** pending independent graph approval and exact-source CI. Tests were written before implementation edits; no baseline execution was authorized.

## Fixed acceptance surfaces

Exact test: `com.mightyoung.muyon.androidlab.agentipc.ServiceLifecycleFailureTest#fixedActualServiceFailureLifecycle`. The build-time APK package suffix selects assertions only; no Intent, Binder, environment or file grants authority or selects service faults. Every APK has a separate fixed manifest class in `src/fail{Setup,SetupOwner,Unknown,Owner,Native,Inflight,Ready}`; shared compiled implementation is `src/failureFixture/.../FailureFixtureApplication.kt`. Ordinary debug/release omit these sources and retain SyntheticLab UI composition.

| Fixed APK | Expected boundary/result |
| --- | --- |
| failSetup | Throw after acquiring/retaining actual durable owner, before native entry; close owner exactly once then release slot; second actual Service can acquire. |
| failSetupOwner | Same definitely pre-native setup failure, owner close throws; failed close latched permanently; zero completed closes/releases and replacement denied. |
| failUnknown | Genuine generated/native construction returned; throw before publication; retain actual controller and durable owner, deny replacement. This simulates uncertain ownership after constructor entry, not a genuine native constructor exception. |
| failOwner | Actual native cleanup succeeds; owner release hook throws before underlying durable close; slot/owner stay retained and replacement denied. |
| failNative | Actual controller constructed, retirement reaches CLOSED, injected hook throws immediately before genuine native.close; seal/handle/owner/slot retained, replacement denied. A genuine generated destructor throwing remains NOT_RUN/not safely injectable. |
| failInflight | Connect real Binder liveness client; genuine UniFFI metadata admission enters actual durable-owner review callback and holds bounded latch. Actual framework unbind/onDestroy must RETURN before replacement bind, before callback drain. Replacement rejected with no acquired duplicate, no native/owner close/release. Replacement onDestroy return releases fixed latch. Genuine admission consumes one durable reservation; then callback-return -> genuine native-close -> owner-close -> slot-release. Sealed controller rejects another probe. |
| failReady | Installed controller is published, then onReady throws; Service unavailable and proactive backend retirement cleans native/owner/slot; second Service can acquire. |

Inflight latch is bounded 30 s; waiting for initial connected client is bounded 20 s. Evidence polling is bounded 45 s; unavailable Binder checks run with 5 s timeout. No external IPC/file control releases the native callback. The fixed compiled schedule releases only after the original and denied replacement actual onDestroy both return. SQLite readbacks inspect only this dedicated fresh APK's `agent-admission-root/muyon-admission-v1.sqlite`; no legacy DB is opened. Final stdout includes full bounded synthetic evidence JSON, process PID/UID/API26 and private `:agent` assertions. No process kill/restart is used in new tests.

## Ownership changes

- AgentRuntimeService denies all calls synchronously after retirement, then dispatches potentially mutex-blocking native retirement to existing backend/settlement pump. Platform onDestroy never waits behind native owner callback.
- onReady throw requests real controller disposal and settlement instead of leaving a published unavailable native controller forever.
- ServiceHostLease records attempted versus completed close. Failed owner close never becomes successful through a second no-op close; native/owner/slot stay retained conservatively.
- Internal no-op lifecycle hooks are installed only through Application/lease composition; no IPC or runtime selector was added. Successful cleanup remains genuine native close, then owner close, then unique-slot release.

## Auditable execution graph (proposed, NOT_RUN)

`.github/workflows/service-lifecycle-failures.yml` has only exact branch push `lab/service-lifecycle-failures-20261018`; no dispatch or PR trigger. Scoped job performs `cargo build --locked ...android-rust-bridge-lab/core/Cargo.toml --features bindings`, generates Kotlin via genuine built uniffi-bindgen, compares checked-in binding. It runs **no Rust test target**.

Two native jobs call existing `checks/android_gate.py` with exact arm64-v8a / x86_64 ABIs. Its transitive helpers require independent read-only review; no aggregate test entry is intentionally added. Package jobs download only three explicitly named artifacts from their current run (`failures-scoped`, `failures-arm64-v8a`, `failures-x86_64`), never a prior archive or another run.

Packaging calls existing `checks/lifecycle_package.py` with new allowlisted `--failure-variant failX`. Existing default lifecycle behavior is retained. This helper imports only package_gate constants/APK checks, linux_gate download/run/hash, verify_inputs and android_gate SDK setup. It verifies exact source identities/native hashes, builds exactly assembleFailX + assembleFailXAndroidTest + lintFailX, inspects both resulting APK package IDs and absence of INTERNET, checks alignment and copies two bounded output APK aliases. Gradle `preBuild` invokes only existing verify_inputs.py; it does not execute legacy scripts.

Each separate API26 emulator runs exactly the named instrumentation method above against its fixed package. There is no instrumentation suite discovery. Each matrix case initializes NOT_RUN status before download/packaging; packaging failure records FAIL with instrumentation NOT_RUN, instrumentation/setup failures preserve FAIL and logs. Matrix fail-fast is false and per-case artifact upload is always() with unique names. Parent must retain terminal failed/skipped/not-run job metadata too if producer failure prevents matrix job creation.

The source graph contains no invocation of denied old script task.db -> HTTP -> original-state reopen and no old workflow dispatch. PR86/I04 HOLD remains; PR90/Dart/UI untouched. No credential/configuration access, real model call, deployment, payment, force push, branch deletion, main/develop merge or denied archive retry was attempted.

## Remaining limits and handoff

Independent immutable source/graph audit and exact-source CI execution are still required. The implementer made no runtime pass claim. Native cleanup fault is injected immediately before destructor entry; native-constructor uncertainty is injected immediately after successful genuine construction. Actual native destructor/constructor exceptions, physical devices, provider transport, credential provisioning and real model requests are NOT_RUN. Production use still requires approved configuration/authority and separate authorized provider/physical-device work; this task proves synthetic metadata admission ownership only.

All implementation writers stop after the source commit; reviewer and parent may perform read-only audit, publish the authorized new branch/Draft PR, monitor dedicated CI to terminal, and retain direct logs. No merge is authorized.
