# Isolated PR87 candidate on develop

Candidate executable source: `0229fa75f7c0e4ff88d22ef845aa982a83f230a6`. Parent: `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e` (fixed develop). Original PR87 tip: `38b59db43f2487700ff15971ee008f0024673a13`; pure increment begins at `0090b6e394abcbd8556a0911f4d5be1ff18687f5` with original parent `6635bc6be057fd36c0e0c6c0aafaf034aca2ecaa`. Exactly 13 added files were copied using immutable git blobs; no ancestor commits were cherry-picked and the original PR/base was not changed. Evidence in this directory refers to the extraction source commit, never to its own later documentation commit.

## Dependency and execution audit

Read service-production-bridges handoff, verification and next-session at immutable `397e25e61111724971e05ba168fd8f5799e16c93`. No AGENTS.md was found under /workspace. Entire `apps/`, `packages/`, root `pubspec.yaml` and `pubspec.lock` trees have zero diff between fixed develop and original PR87; all six actual imported Muyon Dart files exist unchanged. Thus those direct APIs do not require the 130 historical ancestors. This is source compatibility evidence, not a Dart compiler result. No dependency resolution, SDK install or credential access was attempted.

Python imports were inspected before execution, including the subprocess crash worker string. `failure_lab.py`, `test_failure_lab.py`, `run_suite.py` use Python standard library and local failure_lab only; no HTTP, I04, real model, product store or adapter import exists. The two child processes run only the local synthetic Store, use new temporary SQLite files, and intentionally exit71/72. Their parent tests passed. Import inventory and exact command/version are in results.json. The original run_suite.py was not invoked because it overwrites two of the13 preserved historical evidence files; direct unittest discovery targets only test_failure_lab.py and saves fresh raw output here.

The Dart fixture imports dart:async/convert/io, flutter_test and six actual Muyon adapter/storage/workspace modules. It includes HttpServer.loopbackIPv4, new temporary storage, ledger/files inspection and reopening. NONE of these8 tests ran; no compile/formatter/analyzer was attempted because neither dart nor flutter is available (tooling.txt). No scenario was split or run through another executor. Original code, skip settings and assertions remain unchanged. Last2 semantic assertions remain STATIC_EXPECTED_FAIL/UNCOMPILED/NOT_RUN: model_gateway.dart request() finishes succeeded at line346 before chat blank-content validation at233–234 and embed-count validation at275–276. This is not an observed runtime failure. The last2 use the shared setup with temporary ledger and loopback HTTP; their own bodies do not call the reopen helper used by the first6.

## Actual coverage and remaining gates

21 synthetic Python unittest cases PASS,0 failures,0 errors,0 skips, exit0; see python-tests.txt. Coverage includes insert rollback after retirement with durable correction barrier, observer visibility, fake-vector pending commit/repair, process exit before/after commit and reopen, deletion barriers, unknown refusal, blank versus explicit JSON no-op, and3 intentional broken negative controls. This establishes only the synthetic contract. It is not production Rust/Kotlin memory implementation or production recovery acceptance.

The historical old24 Hy tests were NOT_RUN this round; their original inventory is preserved, not relabeled as new coverage. Eight actual adapter Dart tests are UNCOMPILED/NOT_RUN. Production log zero-leak, full24-cell INFO/DEBUG matrix, device/API26 runtime, real provider/credentials/billing, and production memory semantics remain unverified by this candidate. UI and all production code are unchanged. Rust core/Kotlin API26 direction and UI freeze remain intact; no Dart business implementation added.

I04 original denied script→HTTP→original-state reopen remains DENIED/NOT_RUN. No retry, rewrite, split, alternate executor, full suite, production store operation or PR86/dependent combination occurred. No remote writes, workflow dispatch, merge, deployment, force push, branch deletion, credential configuration, paid/real model or Mac sync workaround occurred.

## Publication gate

All9 workflow trigger sections were inspected and captured in workflow-triggers.txt. A push to exact branch `research/memory-isolated-candidate-20261018` does not match any current push branch selector. However `.github/workflows/ci.yml` triggers on every pull_request into develop/main with no path, head-name or draft predicate. Draft status does not prevent it. It runs scripts/ci.sh, which resolves Flutter workspace dependencies, analyzes8 packages, and runs all8 broad Flutter suites, including all apps/muyon/test. The new experiment fixture is outside those test directories and is not directly discovered by that command. No I04/task.db literal match was found in host/inquiry tests, but that alone does not certify the broad execution safe against the existing denial. Do not open a new Draft until LeaderB has resolved this generic workflow trigger under the existing boundary; cancelling a run after creation is not a safe preflight. No workflow was modified to skip tests or obtain green. Other workflows are manual or branch/path restricted and do not match this exact candidate's changed paths.

Original copied documents retain their historical baseline/source/results and owner commands verbatim. They are provenance, not current execution instructions: this report and results.json supersede their local-run claims for the isolated candidate. Do not follow the historical Dart execution suggestion this round.

## Exact extracted files

- `docs/tasks/memory-failure-validation-20261018/ADAPTER-LOG-AUDIT.md`
- `docs/tasks/memory-failure-validation-20261018/COVERAGE.md`
- `docs/tasks/memory-failure-validation-20261018/HANDOFF.md`
- `docs/tasks/memory-failure-validation-20261018/PR-BODY.md`
- `docs/tasks/memory-failure-validation-20261018/REVIEW.md`
- `docs/tasks/memory-failure-validation-20261018/existing-coverage.json`
- `docs/tasks/memory-failure-validation-20261018/python-tests.txt`
- `docs/tasks/memory-failure-validation-20261018/results.json`
- `experiments/redesign/memory-failure-validation-lab/README.md`
- `experiments/redesign/memory-failure-validation-lab/actual_adapter_canary_test.dart`
- `experiments/redesign/memory-failure-validation-lab/failure_lab.py`
- `experiments/redesign/memory-failure-validation-lab/run_suite.py`
- `experiments/redesign/memory-failure-validation-lab/test_failure_lab.py`

Each file's original Git blob and SHA256 is recorded in extracted-files.json. Root remains sole integration/remote-write owner. Worker B releases ownership after this evidence commit and has no background process running.
