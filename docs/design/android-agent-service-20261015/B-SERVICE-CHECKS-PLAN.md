# B Service Checker Implementation Plan

> **For agentic workers:** use the preserved original checker with superpowers:executing-plans after root's fixed-contract C0 and task activation. No subagents or implementation before activation. Root alone integrates/pushes.

**Goal:** Extend the existing bridge gate to verify the B Service's actual shared Rust Agent/controller through compiled Rust and generated Linux JVM FFI, plus Android Service/AIDL/build/package compatibility, without claiming Android process runtime evidence.

**Architecture:** Whole Agent and trusted persistent Catalog are inside the Service's Rust worker; Linux child Catalog stays a separate regression. Reuse existing source/build/binding/hash/RED classifier and packaging utilities. No A product runtime, new test framework or parallel workflow.

**Tech stack:** Existing pinned Rust/UniFFI/JNA/Kotlin/JDK/Python and Android API24 two-ABI toolchain; remote temporary runners for real builds. No local large targets, device/emulator, model, credentials, permission/resource additions or license autoaccept.

**Spec:** `/tmp/rd-android-rust-bridge-20261015/ANDROID-AGENT-SERVICE-SLICE.md`; native/UI ABI note `/tmp/rd-android-rust-bridge-20261015/B-SERVICE-ABI.md`, reviewed here at SHA256 `3c5bf11e68afda823bfea1ceb0207d57261dfb3fab44377ae0578173369d55c3` (not yet final root-approved source). This is the preactivation checker plan, not an ABI definition. Root's upcoming immutable docs commit is the implementation base; current source reference0ab remains preserved.

## Scope and fixed ownership

Modify only `.github/workflows/android-rust-bridge.yml` and `experiments/redesign/android-rust-bridge-lab/checks/`. Preserve original author clone/branch clean; after activation create the root-assigned new branch from the fixed docs base, with no branch replacement/history rewrite. No production Rust/Kotlin/AIDL/manifest edits, old workflow changes, new dependency or product test edits by checker.

Reuse `linux_gate.py`, `ffi_evidence.py`, `full_evidence.py`, their small controls, `android_gate.py`, `package_gate.py`, and workflow aggregate guard. Add only a focused `ServiceProbe.kt`, fixed `service_cases.json`, and if needed one narrow `service_mutations.py` plus private inverse oracle. Keep existing BridgeProbe/PanicProbe and immutable metadata RED descriptors unchanged.

Global constraints: bound foreground-visible-only B; no extra FGS/start-service policy; one Service controller, max1Rust initialization/execution worker +1Service-owned settlement waiter, no wait queue; same existing Rust auth/read/receipt/final-byte chain; app private root supplied Service-side; raw/history/projection/answers not shipping output; control independent of worker/session locks; durable IDs/epoch/revision; reconnect/status cannot execute. Unknown is not Failed/Cancelled/NotStarted. Android runtime stays NOT_RUN until a separately authorized actual Android execution lane.

Review focus: ambiguous submit response and no-replay; stale epoch/revision/control; independently responsive cancel/close and actual join; durable raw receipt surviving cancellation/death; hidden fallback that bypasses shared driver or authority. Each is pinned below. Count labels come from fixed source-defined inventory, never DUT output.

## Task 1 — Freeze inputs and add the two actual semantic RED modes

**Files:** workflow; `linux_gate.py`, `ffi_evidence.py`, their controls; new `ServiceProbe.kt`, `service_cases.json`.

**Consumes:** root-reviewed ABI and native author's immutable compiling refusal stub with exact integration target/name/reach guard/assertion and source-defined test inventory. Current ABI proposes `AgentServiceController.new(config)`, `connect`, `start_run`, `status`, `current`, `lookup`, `set_visibility`, `release_client`, `cancel`, `close`; `client_gone` and `await_settled` are Service-only FFI, never AIDL. Actual generated Kotlin methods/classes are read from fresh generation, not manually stubbed. UI owner confirms Service-side invocation of these same methods. No second permissive test driver.

UI owner candidate source paths: state `AgentServiceContract/AgentServiceState/AgentServiceClientState.kt`; app `AgentRuntimeService/AgentBoundClient/ServiceControllerAdapter.kt`; `app/src/main/aidl/com/mightyoung/muyon/androidservice/IAgentService.aidl` plus typed parcelables. Their final source is UI-owned; checker references fixed class/AIDL inventory only after definition.

**Produces:** modes `service-rust-red` and `service-jvm-red` in the existing workflow/CLI; independent required jobs. Normal immutable refs `lab/android-rust-bridge-service-rust-red-*` and `...-service-jvm-red-*` select those exact modes; manual inputs select them explicitly. Existing rust-red/jvm-red modes retain their original contracts. Full is the normal integration/default mode.

- [ ] Current proposed primary case `service_controller_executes_registered_read`, reach `AGENT_SERVICE_STUB_REACHED`, positive panic `AGENT_SERVICE_RED: admitted run must complete the registered physical read` must first be validated against the immutable author test source; integration target, reach qualifier, actual filtered count and JVM guard are frozen only there.
- [ ] Freeze author-source inputs before implementation/output: manifest/lock, exact target and test names/filters, positive fixture variant/seed and expected synthetic projection/raw canary, refusal reach marker, exact named assertion and expected exit/summary; record source/blob SHA256 in service_cases.json. Reject a missing/mismatched inventory, rather than guess count or accept total-only. Native/UI owners must supply method spelling/test names before this step can be completed; no placeholder may activate CI.
- [ ] Extend lightweight classifier controls: real modern/legacy panic format, wrong marker/source/hash/target/count, compile/load/setup/timeout/signal failure, unrelated early denial, skipped case, duplicate summary, and healthy positive sibling. These controls validate the checker only, not product RED or inverse KILLED.
- [ ] Required remote sequence: locked fetch then offline locked no-run; build default shipping library and immediately copy/hash it; build bindgen tool in isolated target; generate matching JVM binding; compile ServiceProbe with pinned actual JNA JAR. Use root checkout HEAD as expected build identity, not PR virtual merge SHA or manifest self-claim.
- [ ] Rust RED: invoke the author's exact named real engine target. Reach proves the correlated actual service-controller entry reached the intended refusing seam, with known safe refusal and actual request/run binding; exact behavior assertion fails after guard. Initial controller RED must not claim Agent dispatch if refusal precedes it. A later dispatch RED requires its own actual shared-drive reach guard. JVM RED: load copied actual shipping .so using generated Kotlin, confirm actual mapped-library/protocol/source, call actual `new→connect→set_visibility→start_run→await_settled→status/current/lookup` controller path and reach same refusal; independent positive assertion then fails. No Kotlin fake status/counters, direct Catalog-only success or setup error can qualify.
- [ ] Save/print bounded raw stage exits, exact test/marker results, source/lock/fixture/binding/library hashes and semantic classification. Required behavior command remains nonzero and CI red; classifier recognition must not wash it green. Root pushes immutable stub combo and obtains both real REDs before native GREEN.

## Task 2 — Actual Linux Rust/JVM GREEN through the B shipping call path

**Files:** ServiceProbe, service_cases, existing Linux/full evidence and controls. Product test targets remain native owner's files.

**Consumes:** author's immutable GREEN using same source-defined fixtures/oracles and generated API, with independently reviewed admission/control state machine.

- [ ] Full Rust checks preserve metadata old9 as its own exact named group (unit3/integration6/doc0) and add new service groups with exact source inventory, no-fail-fast, no skips or unexpected tests; additional unit/doc groups are explicit. Test counts remain NOT_RUN/unfrozen until test-first source exists; never report old9 as all new service tests.
- [ ] JVM positive invokes actual public controller/worker used by Service, not a UI-process Agent product. Four built-in variants run real same driver, physical synthetic input and persistence; independent private oracle proves read1/original receipt1/two exact safe payloads/no raw canary, matching durable identities. Shipping snapshot must agree with authoritative records without exporting raw evidence or counts. Private test probe cannot replace policy/driver or construct a fake success.
- [ ] Pin meaningful negatives with valid siblings: duplicate request Existing versus changed-input conflict; busy concurrent submissions/zero queue; visibility/lease/epoch mismatch; stale result/revision and lookup-only reconciliation; cancel blocked provider and post-handler raw preservation; close/join/slot retention; root lock/quota/corrupt restore; no third model send/second read; auth/purpose/final-byte denial. Controller I/O phases are awaited through bounded barriers/status, never timing guesses. `await_settled` is called from the harness background equivalent of the sole Service waiter: normal Terminal and Closed are not accepted before actual Rust drop/join, and root lease stays held across normal terminal settlement until closed settlement. Freeze only the cases prescribed by reviewed ABI; no broad framework.
- [ ] Preserve default shipping vs test-probe vs bindgen artifacts/targets and old JVM7 metadata/load/panic controls. Test-only controller barriers/exported probes stay absent from default Android shipping build. Print per-case result/identity and overall group outcomes, since artifact downloads can be403.
- [ ] Remote full requires exit0 and exact inventory for every group. Environment/tool absence is INVALID, not skipped/pass; new tests are not assumed GREEN from Rust author logs.

## Task 3 — Narrow real native guard inverses, required with full

**Files:** one focused `service_mutations.py`, service_cases, and a private checker oracle if public test hooks cannot independently observe the required boundary; existing evidence controls/workflow.

- [ ] On fixed GREEN source, freeze a small source-hash-anchored batch: admission dedup/no-resend (duplicate or reconnect must produce attempt/read0 additional), old epoch correlation (stale reply/control cannot affect new run), and independent cancel/join retention or final authority where the reviewed implementation introduces a new essential guard. Exact sites/target names/counts are selected from fixed source, before mutant output; no guessed line patches.
- [ ] Same private oracle baseline must be GREEN first. Each mutation runs in a private isolated copy, compiles/no-run successfully, then hits exactly the named semantic assertion/expected left-right value after reach guards. Preserve public service and native25 inventories; private targets are separately inventoried with their actual filtered count. No product weakening or removing a redundant downstream guard to force physical leakage.
- [ ] Retain before/after source/patch/library/binding hashes, owned PID/processgroup cleanup and natural/forced cleanup distinction. Build/setup/timeout/signal/unreaped child or wrong failure is INVALID; surviving target is SURVIVED. Old17/native3 do not prove new lifecycle/epoch/dedup guards. Required full includes this batch; no continue-on-error.

## Task 4 — Fresh Android Service build/package plus honest aggregate

**Files:** workflow, android_gate/package_gate and corresponding focused controls.

- [ ] Add native-host source dependency paths to existing triggers/inventory; build both actual API24 ABIs with the approved B runtime dependency. Byte-compare fresh generated Android binding; retain exact shipping/probe exclusions, ELF/import/API evidence, JNA and existing graphics AAR hashes, all six native APK bytes/STORED/16KiB alignment/zipalign/min24/target36. No new framework or relaxed inventory.
- [ ] Compile actual author AIDL/Service/proxy and inspect merged manifest for the exact author class, `:agent`, exported=false, isolatedProcess=false, no new permissions/started/FGS declaration. Android source inspection must show Service-side Rust controller construction and no UI Agent construction. These are source/build checks, not proof of runtime process placement.
- [ ] Preserve existing67 state checks/ordinary no-native Compose/lint gates and old metadata/UI behavior tests; new Service/controller UI inventory is a separate exact author-defined group. Never count cancellations as passes. Root retains existing native94/plugin21/host25/process44/harness13/17+3 workflow as regression, avoiding duplicate local compilation.
- [ ] Full always schedules aggregate even if mode selection/producer fails, requires all mandatory Linux/Android/inverse results success and exact same checkout source, and fails otherwise. Preserve final artifact/stdout evidence. Mode/needs/unknown environment controls prove failclosed; genuine remote builds decide acceptance.

## Separate Android runtime acceptance — planned, NOT_AUTHORIZED / NOT_RUN

No emulator/device installation, execution, SDK/NDK local build or new resource request in this plan. Future authorized Android test must show real different UI/Service PIDs/equal expected UID, actual Binder proxy, ART/JNA same engine, service-owned files/modes/locks/fsync, actual Service kill at durable admission/running/raw-finish/task-terminal barriers, UI survivor/new epoch and lookup without new attempt/read. Separate UI death, last-visible/unbind, reply loss, Binder overflow/backpressure, slow/dead clients and independent cancel/close. Host/JVM SIGKILL/fake Binder events/static manifest cannot satisfy this gate. API24 must not rely only on newer callbacks. Offline development/review can finish with this layer explicitly pending; it must never be labeled Android process/death verified.

## Checkpoints and handoff

1. After root fixed-design C0/activation: freeze ABI + inventory, small classifier/workflow commit; actual immutable two-RED remote evidence.
2. Fixed GREEN source: Linux service full/oracles, isolated precise inverse batch, Android package extensions; each small checkpoint independently reviewable.
3. Same final immutable head: normal full required Linux+Android+inverse and existing regressions. Root sole pushes/draft PR; non-author reviewer checks classifier/source/oracles and actual logs. All raw logs/provenance outside Git.

Current status: plan only; no implementation/new tests/builds/runs. Original checker clone clean. Upcoming docs SHA/ABI/test-first inventory have not yet been fixed, so numeric service counts and actual service outcomes are NOT_RUN, not guessed. Local /tmp is ~700MiB per root: no fresh large target or cleanup; canonical real compilation remote only.
