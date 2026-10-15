# Android Rust Offline Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development with the explicitly retained original owners and independent non-author reviewers. Steps use checkbox syntax for tracking.

**Goal:** Connect the existing Compose settings flow to an actual stateless Rust declaration diagnostic without enabling business or model execution.

**Architecture:** A new UniFFI facade calls existing Rust mappings and fresh Catalog register/inspect; no Linux NativeSession is exported. An application-process shared Kotlin coordinator serializes actual synchronous FFI calls and ignores stale presentation results. Dedicated CI proves Rust, real Linux/JVM FFI, new Android API24 cross-link, and source-matched APK packaging separately.

**Tech Stack:** Rust1.99.0, UniFFI0.32.2, Kotlin/Compose2.2.20, JNA5.19.1, Gradle8.13, AGP8.11.1, JDK17, NDK28.2.13676358.

**Spec:** docs/design/ANDROID-RUST-OFFLINE-BRIDGE-20261015.md

## Global Constraints

- Begin product work only after root has merged fixed reviewed PR80/79 into develop and verified remote tree identity. Never modify main, force-push, delete histories/workspaces, deploy, or merge old Dart PR76.
- Root alone integrates/pushes. Original native, UI and checker owners retain the exclusive directories below; no competing writers or worker-spawned reviewers.
- Protocol1. request_id exactly [A-Za-z0-9_-]{1,64}; DiagnosticVariant Equipment/Research/Inquiry/SeededEquipment with fixed seed0x7631. Never send user drafts into the diagnostic.
- Export only true catalog_generation and data/operation/relation/view counts. No grants, receipts, execution or handler counters. BridgeInfo operation booleans are staticfalse surface declarations, never global permission measurements.
- Native function names, exact DTOs and four unit errors are copied from the spec. Build identity is full clean source40SHA from MUYON_BRIDGE_BUILD_ID; external manifests bind source/lib/generated-bindings hashes.
- Existing executing RustUiPort remains NOT_CONNECTED. UI diagnostics are separate, local and not chat/task/receipt successes. No real model, credentials, business database, child process, Android install/emulator/device execution or new license acceptance.
- Android minSdk24/compile-target36 unchanged. Keep permissions unchanged. Rust API24 new libraries for arm64-v8a+x86_64; no old API26 spike binary reuse. Runtime loading/render/page-size behavior remains NOT_RUN.
- Generated Android Kotlin source can be committed reproducibly; no binaries or raw logs enter Git. Android/JVM generation use the separate explicit UniFFI0.32.2 global configs specified in the spec.
- Actual synchronous FFI work retains the application-process single-flight slot until return/error-finally. Dismiss, timeout, cleared/reopened UI invalidate presentation only, never acknowledge native cancellation or admit a second call.

## Review Focus

1. Missing/mismatching native library or generated API checksum must stay unavailable; compilation is not a handshake (Tasks2/3).
2. Close/timeout/reopen while a native call is blocked must keep the slot occupied; late results must not overwrite a new holder (Task3).
3. Non-ASCII/control/oversize correlation IDs and wrong protocol must reject before declaration work, with valid siblings succeeding (Tasks1/2).
4. Catalog inspection malformed/missing/overflow fields must fail closed rather than become zero; declared counts must not imply executable tools (Task1).
5. API24/JNA platform cleaner compatibility and stale/mixed ABI artifacts must fail setup/packaging, never be counted as semantic RED or Android runtime evidence (Tasks2/3).

---

### Task1: Rust typed declaration facade — original rust_native_host_owner

**Files:** Create experiments/redesign/android-rust-bridge-lab/core/{Cargo.toml,Cargo.lock,build.rs,src/lib.rs,src/bin/uniffi-bindgen.rs,tests/bridge_contract.rs}; add core/uniffi.android.toml and core/uniffi.jvm.toml with the spec global profiles. Do not edit existing Agent/plugin/native-host product code.

**Interfaces:** Consumes existing mappings and Catalog API. Produces library/namespace muyon_android_contract_bridge, package muyon-android-contract-bridge-lab, bridge_info()->BridgeInfo and validate_bundled_contract(DiagnosticRequest)->Result<DiagnosticReport,BridgeError> exactly as spec. Runtime direct dependencies only existing plugin path and uniffi=0.32.2; CLI feature limited to bindings. Own and commit a fresh Cargo.lock.

- [ ] Write compiling refusing facade and named behavior tests; freeze exact inventory and positive RED target/marker with checker before first remote run. Handshake can report only the true narrow surface; validate must reach a Rust marker and return the frozen typed failure until implemented.
- [ ] Generate lockfile with pinned dependency resolution; build --locked/no-run first. Observe the positive target's compiled semantic failure, not compile/load/timeout failure. Keep source/log/provenance outside Git and fixed RED commit intact.
- [ ] Implement protocol/ID validation before mapping, fixed variant/seed mapping, actual fresh Catalog registration and inspect parsing with checked integer conversion. Return exact protocol/id/variant/namespace/build identity and true counts/generation. Reject internal missing/type/overflow cases without exposing raw reasons.
- [ ] Require fixture-derived counts in data/op/relation/view order: Equipment2/1/1/1, Research2/1/1/1, Inquiry2/1/2/1, SeededEquipment2/1/1/1. Expected values are frozen from input fixtures, not generated from DUT output.
- [ ] Test protocol/ID invalid cases with valid siblings; exact ID/variant echo; repeated calls with fresh generation1; staticfalse business/model surface; malformed inspection; panic containment with a bounded private test path and release unwind. Any Linux-only probe feature must not enter default Android artifacts or change the frozen business API.
- [ ] Run the complete new named suite and commit GREEN implementation separately. Provide fixed SHA, exact commands/counts, source/lock/config identities and report task1-native-report.md. No broad local build if disk budget is insufficient; request remote evidence via checker/root.

### Task2: Real FFI and Android build gate — original host_checks_owner

**Files:** Create .github/workflows/android-rust-bridge.yml and experiments/redesign/android-rust-bridge-lab/checks/**, including Linux JVM probe and stdlib verify_inputs.py. Canonical schema lives in docs/design/ANDROID-RUST-BRIDGE-INPUTS-V1.schema.json; shared CLI/closedfields in the companion.md are binding. Do not edit normal ci.yml, existing Rust/Compose workflows or product directories.

**Interfaces:** Consumes Task1 fixed Cargo/API/config/test inventory. Produces normal lab/android-rust-bridge-* full gate; explicit immutable rust-red/jvm-red modes; generated Android binding source for UI owner; matching-source two-ABI native library artifacts and manifests for Task3. Namespace approved by root.

- [ ] Pin actual tooling/download hashes from checker-ci-plan.md. Validate YAML/bash/context before push. Resolve Cargo dependencies using fetch --locked before offline --locked builds. Existing permitted SDK/NDK only; missing/new-license setup is a reported blocker.
- [ ] Independently classify compiled Rust RED and real generated Linux/JVM native-call RED; build, bindgen, load/symbol/checksum/setup/timeout failures are INVALID. Keep intentional RED as required nonzero CI failure; no classifier-washed success.
- [ ] Full Linux job must run actual Rust suite, compile fresh release cdylib and pinned bindgen, freshly generate desktop bindings and run real JVM/JNA probe with the matching library. Assert actual native build/protocol/capabilities, all four fixture counts, typed errors/correlation and valid siblings. Record actual library path+hash and binding source/hash; no Kotlin fake can satisfy this gate.
- [ ] Android API24 arm64/x86_64 jobs must freshly link default-feature Rust libraries, inspect ELF target/DT_NEEDED/exports/LOAD/RELRO and matching JNA AAR assets, reject desktop/GLIBC/stale inputs. Preserve exact minAPI/ABI/source/toolchain manifest. Freshly generate Android bindings and byte-compare with committed UI binding.
- [ ] Package consumer requires matching exact source/ABI/config manifests and rejects missing/extra/stale libraries before Gradle. Run state checks with unchanged16+22 markers plus fixed new diagnostics inventory, API compatibility/lint, app and androidTest assembly. Verify APK Rust/JNA entries against producer hashes and zipalign structure. No Android execution.
- [ ] Add lightweight classifier/provenance/watchdog controls where behavior can be misclassified; exact test inventories may be frozen only from fixed author test sources, never guessed from a green run. Print bounded safe diagnostic summaries for ordinary run-log review; artifact403 is not bypassed.
- [ ] Preserve all previous gates. Explicitly dispatch original Rust full workflow and normal Compose workflow on final bridge head when claiming same-head regression results; absent job is NOT_RUN. Commit checker changes and supply task2-checks-report.md.

### Task3: Observable diagnostic adapter and Settings panel — original workbuddy_android_ui_owner

**Files:** Modify only experiments/redesign/android-compose-lab/**: new pure diagnostic state/coordinator/port, app/src/main/kotlin/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt generated bindings, native adapter and settings panel, build.gradle inputs/dependencies, focused state/instrumentation-source checks and concise documentation. Existing execution port and business controls stay disconnected.

**Interfaces:** Consumes Task1 typed API and Task2 real generated Android bindings+two-ABI artifacts. Produces application-process RustDiagnosticCoordinator shared across panel/holder recreation, independent observable diagnostic state, and explicit source-checked Gradle native inputs. No separate Agent loop or model endpoint.

- [ ] Write focused failing state cases for missing library/protocol mismatch, exact request correlation/variant, stale results after dismiss/timeout/reopen, and a controlled blocking backend across two holders. While first synchronous call is blocked, second holder cannot queue/start another call; slot releases only after actual return/error. Do not use sleeps for ordering or equate local dismissal with cancel acknowledgment.
- [ ] Keep pure state tests independent of generated/native bindings. Implement coordinator with bounded single flight and no automatic retry; never execute FFI/listeners under the admission lock, and test reentrant/detach responsiveness while a worker is blocked; safe typed errors only. UI captures no user draft in a native request, and diagnostics never mutate conversations/tasks/records/receipts. Reuse latest-state field merging and keep all38 prior checks required.
- [ ] Commit actual reproducibly generated Android Kotlin binding source with headers and only Android JNA@aar dependency; Linux probe uses separate JVM JAR/binding. Normal Compose compile must work without Rust build tools/native inputs and remain unavailable when library absent. Do not hand-write generated native stubs or fake a ready handshake.
- [ ] Implement app adapter through actual generated native functions, off main thread, all FFI including handshake through the same shared slot. Observe result identity/generation before state update. Add separate Settings local-Rust diagnostic panel as the only active FFI entry, with no input capability-sheet native-call entry; show checked declarations, not executable tools or business success. No generic CONNECTED execution enum.
- [ ] Invoke the shared verify_inputs.py CLI exactly as the packaging contract using an argv vector and actual resolved JNA AAR before optional-native preBuild/packaging; no raw-JSON duplicate parser. Normal no-input builds never search for Python. Set BuildConfig.MUYON_BRIDGE_PROTOCOL=1 and MUYON_BRIDGE_SOURCE_SHA=validated expectedSHA or empty. Add -PmuyonBridgeInputs=/absolute/bridge-inputs plus required -PmuyonBridgeSourceSha=<expected40SHA> with bridge-inputs.json and the two jniLibs ABI subdirectories. Require both input properties absent or both present; sourceSha alone/inputs alone fails. CI expected SHA is independently current HEAD, never copied from the manifest. Add only the validated <inputs>/jniLibs directory. Fail for mismatching source/config/binding/library manifests, package expected Rust/JNA inputs with only arm64-v8a/x86_64 filters, keepDebugSymbols for both named libraries so hash equality is honest, preserve minSdk24/permissions. Add source instrumentation cases only as compile evidence unless separate device authorization arrives.
- [ ] Run new focused checks and preserved38, provide immutable RED/GREEN/changed-case evidence, generated source/config provenance, safe failure/lifecycle report task3-ui-report.md. Independent reviewer then checks actual Compose uses this adapter and all disabled business controls.

## Integration and task review

Task1 and Task2 first establish real compiled Rust/JVM REDs before GREEN source is accepted; the stable API lets Task3 state work proceed after root merges the existing PRs. Root imports only exclusive-owner commits, never product fixes authored by root. Native/FFI security reviewer and UI non-author reviewer gate their respective fixed sources; scoped fix reviews preserve findings and exact SHA. Final whole-branch check verifies the three interfaces and artifact identities together. A new review PR is permitted for this bridge; this plan does not authorize automatically merging it or deploying.

Root records no-build, source identity, all actual test/CI terminal states and deferred Android runtime separately. Preserve raw evidence outside Git, all original branches/workspaces, and the paused Dart oracle. No cleanup deletion.
