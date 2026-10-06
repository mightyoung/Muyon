# Research Workbench synthetic Android acceptance, 2026-10-03

Device: V2324A, Android 16, USB `adb -d`. Only `com.muyi.research_workbench` and its directly opened synthetic file picker/save sheet were used. No task command executed, no network transfer, no private research file read, no install/reset/code change.

| Step | Observation |
|---|---|
| Previously imported synthetic research | PASS: Markdown and 1-page synthetic PDF opened; page 1 quote and note saved. See `../native-research-imported.png` and previous native acceptance state. |
| Synthetic task import | PASS: `SYNTHETIC_TASK_20261002.zip` selected alone; `synthetic-task-20261002` r1 appeared. |
| Manual run | PASS: `cfa88634-bf9c-4f08-81a8-3e054b108823` saved as `completed`, metric `synthetic_score=0.82`, log explicitly says `no command executed`, conclusion pending human review. |
| Export | PASS: app-opened Android save sheet wrote new `SYNTHETIC_MANUAL_RESULT_20261003.zip` (612 bytes) in `Download/ResearchWorkbenchSynthetic`; `unzip -t` passed. |
| Same-device reimport | FAIL: app toast `操作未完成：FormatException: Run ID already exists with different contents`; exact UI dump: `reimport-error.xml`. The original row stayed pending; no second row was inserted. |
| Two-run comparison | PASS for UI display only: a second fictional local manual run `da808c67-dd5c-4c8e-897e-b938336b6e46`, score 0.73, joined the same task r1 comparison. Both 0.82 and 0.73 appeared side by side, both pending; `comparison-two-runs.xml`. No scientific assessment was performed. |
| Human acceptance | BLOCKED by same-device reimport failure. Source UI only offers `确认关联为证据` when `_localManual != true`, so neither local manual row exposes the action. A separate imported result was not used under the request to reimport only the just-exported file. |
| Markdown report | PASS for local file export: `SYNTHETIC_REPORT_20261003.md` (170 bytes). The synthetic project header and goal appear; no accepted evidence is present, so the output has an empty reading-notes section. `writing-empty-evidence.xml` shows the writing state. |
| Cross-device transfer | NOT TESTED. One phone and its local save/import path cannot establish two-device behavior. PaddleOCR is not integrated or tested. |

## Read-only cause analysis

The exact SQLite row (`synthetic-run-row.txt`), queried with `sqlite3 -readonly` by run ID from the app's own database, contains `"_localManual":true` in its `data` JSON; exported `result.json` in `SYNTHETIC_MANUAL_RESULT_20261003.zip` does not. All common public fields match; `accepted=0` is a separate column, no timestamp or attachment path appears, and artifacts are `[]` in both. `lib/core/store.dart` inserts `_localManual`; `lib/core/exchange.dart` exports only public fields and then compares `jsonEncode(old)` against `jsonEncode(data)` after stripping only `_snapshotPath`. The JSON field order also differs (`artifacts`/`conclusion`), so the string comparison is not semantic. This proves the same-device conflict. A first import on a distinct device without that run ID takes a different insert branch and remains unverified here.

Evidence here is synthetic and local only. Do not interpret `completed` as a real experiment or `pending human review` as a validated scientific finding.
