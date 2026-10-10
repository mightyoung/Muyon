# QUALITY-COVERAGE: sustained baseline and gradual regression gate

User-authorized cloud implementation, isolated branch `task/quality-coverage-baseline`; parent task reviews, no merge.
Fixed develop base: `8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d`.

## Small reviewable design

- Reuse the existing eight test invocations in `scripts/ci.sh`, adding coverage to each once. Inquiry runs from host for asset keys, so all suites have distinct output paths. Instrument only the eight workspace package names; merge duplicate source/line records by logical OR.
- Require a fresh, nonempty LCOV report with repository lib executable records for every suite. A failed test still fails existing CI. Missing report fails measurement.
- Summarize hit / loaded executable DA lines per package, list all lib Dart sources absent from LCOV, and report their executable denominator and whole-package percentage as **unknown**. Source file counts are inventory, never executable line counts.
- Exclude only outside-repository dependencies and paths outside the eight lib directories. No low coverage or generated lib source exclusion. No goldens, skipped tests, platform-dependent tests or uncovered source lines are invented as LCOV.
- Existing UI behavior tests are included. Linux self-skips include macOS font goldens and external/model/platform requirements. Store runner summary, exit code, skipped count per suite separately; exact attribution of skip reasons is unknown and requires declarations/logs. Manual macOS verify remains separate and unchanged.
- The actual Actions measurement is frozen into `scripts/coverage/baseline.json` only after success. Measurement version, checker hash, platform, Flutter version, scopes, and denominator line identities are comparison contracts.
- Initial gates: module API lib (registration/contracts), host model services (credential/model boundary), host transfer services (task coordination). Other scopes, including UI, research, prototype, supplier and inquiry, remain observational. Gate scopes are selected for critical behavior, not chosen by coverage percentage.
- Gate scope source inventory drift, loaded line identity drift, or hit-line decreases fail with explicit remeasurement/review guidance. New source cannot disappear silently from inventory. Drift needs a new fixed-SHA Actions baseline and parent review; never auto-rewrite baseline or lower thresholds.
- Only small derived summaries upload to existing Actions artifacts; raw LCOV stays ephemeral, no paid service. Existing CI raw logs remain existing workflow behavior and do not enter git.

## Validation and handoff

Offline fixtures must catch missing reports, denominator drift (including equal line count), newly unloaded source, contract changes, and coverage decrease; duplicate report merge verifies actual behavior. Existing exit-status fixtures still verify eight calls, all tests retained, continuation after failure, and accurate failure propagation.

Baseline commit and final commit/run IDs, numbers and unknowns are recorded after actual Actions completion. Merge-time revalidation is required on the integrated SHA; baseline is not evidence for new parallel code. No Dart business code, AIUI core, analysis_options or pubspec changes.
