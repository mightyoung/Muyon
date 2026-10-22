# Exact-source verification and disposition

Product/workflow source: `d28e8d3ed08d2185198284794dd116e3d6eb3290`.
Base PR91: `4b609602f76996ec69e9f51da8bc4261d6a2d94a`.
Draft PR92: https://github.com/mightyoung/Muyon/pull/92 . HOLD remains; no merge acceptance or production approval.

## Execution locations and commands

Controller/static inspection: `/workspace/Muyon`, selected Linux execution environment, 2026-10-18 UTC. No local Gradle/kotlinc/Android SDK was installed; local Android compilation/instrumentation **NOT_RUN**. Worker Python SQLite manifest inspection was structural only; independent reviewers ran no tests. Local root verification: YAML parsing, `bash -n` on every scoped workflow run block, `git diff --check`, immutable SHA256 inventory/working-tree equality, and `git diff --exit-code` for frozen Rust/UniFFI/Application/Service/UI paths. All are static checks, not runtime evidence. `evidence/source-d28e8d3e-sha256.json` explicitly includes the new workflow, addressing the reviewer’s checksum-inventory limitation without changing the frozen workflow.

Actual CI location: GitHub Actions `ubuntu-24.04`, `/home/runner/work/Muyon/Muyon`. New workflow `.github/workflows/service-durable-owner.yml` checks out exact source and records it. JDK17, checksum-verified Gradle8.13, AGP8.11.1/Kotlin2.2.20, compileSdk36/buildTools35.0.0/minSdk26. Build tasks:

```
gradle --no-daemon --stacktrace --console=plain -p experiments/redesign/android-compose-lab \
  :state:check :app:assembleDebug :app:assembleDebugAndroidTest \
  :app:compileDebugUnitTestKotlin :app:lintDebug
```

No optional native bridge inputs were supplied. Runtime uses a fresh `android-26;google_apis;x86_64` emulator and only:

```
adb shell am instrument -w -r -e class \
  com.mightyoung.muyon.androidlab.agentipc.DurableServiceHostOwnerTest \
  com.mightyoung.muyon.androidlab.test/androidx.test.runner.AndroidJUnitRunner
```

Success must match every source-counted `@Test fun`, not merely a positive test count. Every ledger file is a new UUID-named synthetic object in the fresh test application's cache. No test opens old task data, HTTP, model provider, Activity or native controller. Genuine generated callback interface is used for a Kotlin callback compatibility smoke only; actual Rust prepare/final_admit with this owner is **NOT_RUN**. No production lifecycle restart has been tested; component object close/reconstruction is distinct.

## Preserved earlier outcomes

- Compile RED: [39127290205](https://github.com/mightyoung/Muyon/actions/runs/39127290205), source `987d49759143709d6c60cb4cfc6e50476d9609e6`, **FAILURE**. Android test compilation reports unresolved ServiceAdmissionAuthority/DurableServiceHostOwner. This is expected missing-implementation RED; no Android runtime pass is claimed. Initial tests commit is `24ea801be0d97d4173741098df802e9a8e637a38`.
- Initial implementation: [39127459970](https://github.com/mightyoung/Muyon/actions/runs/39127459970), source `bf244606d162c4b60ee5b3073e53c4d367d8e24c`, **SUCCESS**, original 11/11 named API26 tests plus build/JVM/lint. Independent review nevertheless found I1/I2. Do not cite this run as acceptance of the corrected final component or proof that those defects were absent.
- Regression RED: [39127714894](https://github.com/mightyoung/Muyon/actions/runs/39127714894), source `a8eacbcbb1858b0108f65a5965c967edb520a1d8`, **FAILURE**, build succeeded; 16 named API26 tests ran, 2 failed. I1 is dynamically reproduced: `duplicate_failure_after_expiry_cannot_resurrect_on_rollback_and_reconstruction` expected null but received an admission UUID. The second failure is **fixture setup**, `table android_metadata already exists`; it does not dynamically reproduce I2. The corrected fixture and callback smoke were committed at `3373004bd182798b4a9aeaa80d9f2886074e6d6f` before production fix `d28e8d3e`. Keep the raw failure log intact.
- Automatic android-compose selector runs [39127496101](https://github.com/mightyoung/Muyon/actions/runs/39127496101), [39127719169](https://github.com/mightyoung/Muyon/actions/runs/39127719169), [39127899712](https://github.com/mightyoung/Muyon/actions/runs/39127899712) are **SKIPPED** on the three respective source heads. No branch-name waiver or fabricated pass was applied.
- Prior PR91's exact-base three successful runs and PR89's cancelled/successful runs are rechecked and preserved in `evidence/prior-runs-preserved.json`. Host48/adapter9 and previous native API26 loop results belong to that prior source, not this new component. They were not rerun or relabeled as new native integration evidence.

## Independent gates

Design accepted subject to stated contracts. Original immutable source review found I1/I2, retained verbatim. Repair review and fresh whole-slice review independently accept the corrected `d28e8d3e` source with no Critical/Important blocker, conditional on terminal exact-source CI. Reviewers and implementer stopped writes and released their owned files. Root alone integrates evidence and remote state.

## Scope, final disposition and next actual lifecycle slice

This delivery is a durable admission component prerequisite. Application/Service installation is **NOT_IMPLEMENTED**, actual production authority/source/profile/credential owner is **UNBOUND**, and ConfiguredChat remains **UNAVAILABLE**. Existing Rust/ABI/UI/SyntheticLab/Auto/FullAllow/Dart are untouched. Sensitive payload/proof/request data is retained as local plaintext indefinitely; distributed authority, cross-process lease execution, full field/signed-limit/surrogate matrix, maintenance-storage failure, crash/power-loss execution and physical/ARM64 runtime remain unproven. See the full review limitations.

The parent's later request to prioritize actual lifecycle arrived after final exact-source CI started; source was kept frozen as instructed. `NEXT-LIFECYCLE-SLICE.md` gives concrete file/call-chain changes, owned-binding cleanup semantics, a process-held authority and Context-derived ledger path, the missing metadata-only native prepare/final_admit execution contract, default real-config denial, and actual private-Service/new-schema restart acceptance. Readiness alone never reserves or commits and cannot satisfy that next task.

I04 historical platform denial remains DENIED_BEFORE_EXECUTION/NOT_RUN; no retry/rewrite/alternate execution/indirect suite. Final archive download was denied with remote HTTP403 Forbidden and was not retried or bypassed; previously obtained logs/terminal JSON remain available (see evidence/artifact-download-denial.md). No hold release, main/develop changes, merge, force push, branch deletion, deploy, credentials, provider network, paid/real model use, old task state or PR90/Dart execution. Final remote snapshots and terminal run results are attached by root below.

## Final terminal result

[39127896088](https://github.com/mightyoung/Muyon/actions/runs/39127896088), exact source **`d28e8d3ed08d2185198284794dd116e3d6eb3290`**, **SUCCESS**. Actual log shows **BUILD SUCCESSFUL**, required JVM state markers and **OK (17 tests)** on the new API26 x86_64 emulator. All 17 named tests completed; no skipped/ignored test fixture was added. This accepts the bounded component only, not actual App/Service lifecycle binding or native provider prepare integration.

Full log, summary and terminal JSON are retained under evidence/GREEN-39127896088*. The named downloadable artifact archive could not be copied because remote artifact storage returned403 Forbidden; see the exact denied action and completed independent evidence in evidence/artifact-download-denial.md. No retry/bypass occurred. Final docs are an evidence-only commit after this tested immutable source; their SHA is reported separately by root. The root watcher is stopped after terminal success; all implementer/reviewer writers are stopped/released. No runtime gate is falsely attributed to a subsequent docs-only SHA.
