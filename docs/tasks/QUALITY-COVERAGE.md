# QUALITY-COVERAGE: sustained baseline and gradual regression gate

User-authorized cloud implementation, isolated branch `task/quality-coverage-baseline`; parent task reviews, no merge.
Fixed develop base: `8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d`.

## Small reviewable design

- Reuse the existing eight test invocations in `scripts/ci.sh`, adding coverage to each once. Inquiry runs from host for asset keys, so all suites have distinct output paths. Instrument only the eight workspace package names; merge duplicate source/line records by logical OR.
- Require a fresh, nonempty LCOV report with repository lib executable records for every suite. A failed test still fails existing CI. Missing report fails measurement.
- Summarize hit / loaded executable DA lines per package, list all lib Dart sources absent from LCOV, and report their executable denominator and whole-package percentage as **unknown**. Source file counts are inventory, never executable line counts.
- Exclude only outside-repository dependencies and paths outside the eight lib directories. No low coverage or generated lib source exclusion. No goldens, skipped tests, platform-dependent tests or uncovered source lines are invented as LCOV.
- Existing UI behavior tests are included. Linux self-skips include macOS font goldens and external/model/platform requirements. Store runner summary, exit code, skipped count per suite separately; exact attribution of skip reasons is unknown and requires declarations/logs. Manual macOS verify remains separate and unchanged.
- The actual Actions measurement is frozen into `scripts/coverage/baseline.json` only after success. Measurement version, checker hash, platform, Flutter version, scopes, and per-file denominator line-set SHA256 fingerprints are comparison contracts.
- Initial gates: module API lib (registration/contracts), host model services (credential/model boundary), host transfer services (task coordination). Other scopes, including UI, research, prototype, supplier and inquiry, remain observational. Gate scopes are selected for critical behavior, not chosen by coverage percentage.
- Gate scope source inventory drift, loaded line identity drift, or hit-line decreases fail with explicit remeasurement/review guidance. New source cannot disappear silently from inventory. Drift needs a new fixed-SHA Actions baseline and parent review; never auto-rewrite baseline or lower thresholds.
- Only small derived summaries upload to existing Actions artifacts (a compressed derived snapshot is also printed for connector retrieval); raw LCOV stays ephemeral, no paid service. Existing CI raw logs remain existing workflow behavior and do not enter git.

## Validation and handoff

Offline fixtures must catch missing reports, denominator drift (including equal line count), newly unloaded source, contract changes, and coverage decrease; duplicate report merge verifies actual behavior. Existing exit-status fixtures still verify eight calls, all tests retained, continuation after failure, and accurate failure propagation.

Baseline commit and final commit/run IDs, numbers and unknowns are recorded after actual Actions completion. Merge-time revalidation is required on the integrated SHA; baseline is not evidence for new parallel code. No Dart business code, AIUI core, analysis_options or pubspec changes.

## Skip/golden/platform evidence (declarations, not measured attribution)

| Category | Declaration evidence at fixed base |
|---|---|
| macOS golden only | `packages/muyon_ui/test/component_goldens_test.dart:155`, `component_library_goldens_test.dart:110` |
| golden/font availability | inquiry `screenshot_test.dart:627`, `ontology_screenshot_test.dart:89` |
| non-golden font requirement | supplier `pdf_test.dart:117` |
| unbuilt external binary | prototype `prototype_store_test.dart:181`; supplier `hub_client_test.dart:154` |
| real model / credentials | supplier `ai_jobs_test.dart:143`; host `agent_eval_test.dart:1254`, `llm_selection_eval_test.dart:877` |
| model directory availability | host `ocr_real_model_test.dart:96` |

Counts by reason are unknown from compact runner summaries; declared conditions do not prove which skips occurred. Loaded DA records count independently of these categories. A golden declaration does not imply that the package's UI behavior tests are skipped.

## Actual frozen baseline

- Source SHA: `633858b21ef1afcf8d5cfe6d0839f662f97b0b0a`. Measurement v1, checker SHA256 `687d1ecad4f92fd54946709df52646b5aaed31390feca6ec72a1dcb21ffc3348`.
- Exact-source push CI: [38022790820](https://github.com/mightyoung/Muyon/actions/runs/38022790820), **success**; `CI SUMMARY: OK (analyze 8/8, test 8/8 suites)`.
- Independent PR CI: [38022794286](https://github.com/mightyoung/Muyon/actions/runs/38022794286), **success**, measured merge SHA `2c614f29f3fd78d972d3a5080fe6e50af6f02532`; package data and gate denominator/hit data are identical to the push measurement.
- Machine baseline: `scripts/coverage/baseline.json`, with run ID and eight runner outcomes. Reports are unioned across the eight suites by source and executable line.

| Package | Hit / loaded executable | Loaded % | Unloaded source files |
|---|---:|---:|---:|
| packages/muyon_module_api | 1298 / 1389 | 93.4485 | 2 |
| packages/muyon_ui | 2471 / 2647 | 93.351 | 3 |
| packages/prototype_module | 677 / 768 | 88.151 | 1 |
| packages/research_module | 4586 / 5397 | 84.9731 | 1 |
| packages/supplier_core | 9548 / 10280 | 92.8794 | 3 |
| packages/inquiry_module | 9241 / 11977 | 77.1562 | 2 |
| apps/muyon | 15932 / 18555 | 85.8636 | 4 |
| apps/muyon_ui_preview | 475 / 527 | 90.1328 | 3 |

All eight whole-package percentages and all unloaded executable denominators are **unknown**. The 19 unloaded source files are named in baseline JSON; they are not automatically called untested executable code. API has two unloaded sources, so its gate covers the measured executable subset plus inventory drift, not all possible API executable code.

| Gate scope | Hit / loaded executable | Loaded / inventory files |
|---|---:|---:|
| packages/muyon_module_api/lib/ | 1298 / 1389 | 26 / 28 |
| apps/muyon/lib/services/models/ | 751 / 778 | 10 / 10 |
| apps/muyon/lib/services/transfer/ | 827 / 882 | 3 / 3 |

No fixed 80% target is used. Gates require identical per-file denominator fingerprints and source inventory, and no per-file or scope hit decrease. Other scopes are observational. Skips measured per suite: API 0, UI 152, prototype 1, research 0, supplier 4, host 3, preview 0, inquiry 47; reason-level counts remain unknown.

Self-review: allowed scope only (CI, checker/fixtures, ignore scratch outputs, task/evidence document, baseline); no business Dart, AIUI core, pubspec or analysis_options edits. Failure fixtures assert behavior and do not change package tests. No model calls or secrets were added. Script tests are fixtures, and the baseline numbers above come from actual Actions. No merge, force-push, branch deletion, deployment or paid service. Parent review and integrated-SHA measurement are required before merge.
