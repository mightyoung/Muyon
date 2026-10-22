# CI selection and excluded paths

Execution controller/root: `/workspace/Muyon`, selected cloud Linux environment, 2026-10-18 UTC.

Fresh branch `lab/service-durable-owner-20261018` starts at immutable PR91 source `4b609602f76996ec69e9f51da8bc4261d6a2d94a`. Initial task branch name was renamed locally before first publication so `ci.yml` push `task/**` does not trigger broad Flutter tests. Main/develop were only read. No old writer process or extra local worktree was found; two new workers have disjoint ownership.

No AGENTS.md found in `/AGENTS.md`, `/workspace/AGENTS.md`, `/workspace/Muyon/AGENTS.md`, recursive workspace search or PR91 git tree. Fixed handoff and NEXT-SESSION read directly from `9eeadbb73aff159575f5d261650e9796d350cba1` objects. PR86–91 and main/develop rechecked; exact initial results in evidence/. No untrusted test script instruction is authority to relax user boundaries.

New `.github/workflows/service-durable-owner.yml` is a pinned-action build and new named Android instrumentation gate. It runs only:

- ordinary Gradle `:state:check :app:assembleDebug :app:assembleDebugAndroidTest :app:compileDebugUnitTestKotlin :app:lintDebug` without `muyonBridgeInputs`;
- temporary fresh API26 x86_64 emulator; only `com.mightyoung.muyon.androidlab.agentipc.DurableServiceHostOwnerTest` via explicit `am instrument -e class`;
- artifact upload, exact source SHA and build/test evidence.

Ordinary app Gradle without bridge inputs does not invoke Rust, Python native staging or external verification. `:state:check` uses pure JVM state checks; it cannot invoke a host binary. Android runner initializes Application but lazy agents/diagnostics are not requested; tests do not start Activity, private Service or native controller. All ledger tests create new UUID-named synthetic database files. No original-state old database, HTTP or process model request is involved. The component's close/reconstruction tests apply only to these fresh new-schema SQLite objects and do not represent legacy compatibility.

This workflow does not call `scripts/ci.sh`, `scripts/verify.sh`, any unfiltered cargo test, android_gate.py, platform_package.py, legacy HTTP/recovery target, or I04. Existing frontend-service-loop workflow is not invoked, because its UI/native runtime is outside this component's gate. Existing service-production-bridges workflow, if dispatched separately, must retain its exact named integration targets and filtered supplier_business terminal regression module; that module does not include old HTTP recovery tests.

Existing android-compose-lab pull_request workflow may appear skipped because this branch is not `lab/android-compose-*`; preserve that outcome. Draft PR base must be `lab/service-admission-bindings-20261018`, keeping dependent HOLD explicit and avoiding main/develop PR automatic broad suites. New scoped gate push filters source/workflow paths, so final evidence-only commits do not relaunch runtime checks. Tests refer to immutable source SHA; final docs head is reported separately if different.

Only existing runner Android licenses are used; SDK installation has no license-acceptance command. GitHub/tool distribution network is build infrastructure, never provider/model network. No credential values are read/configured. No deployment, paid model, merge, force-push, branch deletion, hold release or PR90/Dart change is authorized or attempted.
