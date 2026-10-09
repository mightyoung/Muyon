# UI-3b projection persistence validation

Base: `52e4d3b0065304c3cac4200a7132a2cfd44f3817` (published develop).
Task branch: `task/ui-3b-workspace-persistence`.
Dedicated worktree: `/private/tmp/ui-3b-workspace-persistence`.

## Boundary and decisions

`UiWorkspaceStore` is a pure UI projection contract. Stored state includes task/surface/scope identity, schema/catalog/snapshot/intent/presentation/draft revisions, separate extraction and manual override layers, view values, continuation step, selected references, detail/source/cancel state, return/scroll anchors and operation references. It contains no domain object bodies, grants or copies of receipt results. UIPlan serialization does not manufacture a ValidatedUiPlan: recovery validates presentation against the current supplied snapshot, intent and catalog.

Ruling: use the existing FoundationRepository managed SQLite `settings` table for this minimal projection rather than adding a migration/state table. The transaction owner serializes compare-and-swap; historical schema/migration facts 1–12 are unchanged. Cost: projection lookup is JSON-backed rather than a dedicated relational index. Existing TaskRecords/ToolRegistry remain task/receipt authorities; agent_drafts remains an in-memory streaming reply layer.

Native save requires the current existing task scope, an exact prior revision and nextRevision=prior+1. A changed scope cannot load or overwrite an earlier projection. Compare-and-swap/SQL errors preserve the old bytes. A damaged projection stays discoverable and reports a load error without deletion. The assistant exposes already-saved task drafts; no UI-4b planner or production dynamic/host operation integration is claimed.

Manual override12 survives extraction suggestion11 and re-open; only explicit adoption removes the override. Same-ID binding/component changes, removed nodes/fields, incompatible schema/catalog/intent and snapshot rollback retain a readable old draft and disable ports. Restored old operation references are queried first and remain locked regardless of successful/failed/unknown receipt status. Restoration never executes them. The native lookup is limited to invocation references already present in that task's payload/events. Current calls must checkpoint their pending operation reference before reaching an attached port; save failures block that port.

A shared workspace page checkpoints before back, guards concurrent returns and records scroll changes. A disabled/unattached native dynamic page still reads the saved draft and existing registry receipts. UI planning providers, real domain action attachment, scope authority, approvals and retry decisions remain existing host responsibilities.

The public browser fixture uses the same contract/codec with localStorage and same-origin Web Locks for writer serialization. Permission/quota/lock failure leaves the old checkpoint and a visible save error. It does not migrate the product SQLite database to Web, store business credentials or call a model/network tool. `?workspace=1` opens the persisted fixture; the old UI-3a/4a preview remains available.

## RED and independent review

Actual assertions failed before implementation: saved manual12 displayed10; SQLite saves/CAS winner missing; re-open lost manual field/current patch; old schema did not disable ports; no operation receipt lookup. Widget page scaffolds lacked editable controls. Scope/event/finder test setup errors and FakeAsync/transaction-queue hangs were corrected and are not treated as behavioral RED evidence. The native Widget test uses a real event loop for its real SQLite queue.

A same-ID changed-binding regression returned editable instead of read-only, then passed after compatibility checking. Fresh independent read-only review requested changes for two Important findings: concurrent back during a slow checkpoint could pop the parent route, and scroll was only captured on back. Both were verified as actual RED (after correcting the tooltip test locator), fixed and covered by GREEN tests; the latter also asserts position after recreation. No Critical or Minor findings were reported. Author verification addresses the findings; no independent re-approval is claimed.

## Verification

Flutter3.47.5 / Dart3.13.4, existing isolated SDK; package tests use `--no-pub --concurrency=1 --reporter=expanded`, timeout30s (host60s).

| Scope | Result |
| --- | --- |
| module_api full suite | 38 passed |
| muyon_ui full suite, including final review regressions | 253 passed |
| public preview full suite | 9 passed |
| host workspace store/return + existing agent_resume/import_recovery/task_events | 38 passed |
| same-version dart analyze four touched packages | No issues, exit0 |
| public preview Web release | success, exit0 |
| workspace_smoke.mjs | syntax checked only |

The slim existing SDK lacks Flutter's `dev/` directory, so `flutter analyze` cannot enumerate that directory; direct same-version `dart analyze` is used for the touched packages. Web external interop method tear-offs initially failed compilation and were replaced by explicit closures; the subsequent build passed. No compiler assertion or lint was disabled.

The native runner temporarily uses sqlite3.source=system and restores root pubspec bytes; SDK config/cache, raw logs and build output remain temporary/ignored. Raw test/build logs and hashes are not committed. Exact pushed task-branch Linux CI and static-package run are reported separately; neither replaces browser interaction or native acceptance.

## Deferred acceptance

Ruling: honor the user-paused cloud deployment; no authorized deployment URL or installed local Playwright was available, and no installation/deployment was performed. The browser reload script is prepared, but real browser/cloud reload, viewport/theme/accessibility screenshots and interaction acceptance remain unverified. The browser fixture-recreation Widget test and real host SQLite tests are separate evidence.

REG-4a/4b business integration, UI-4b planning/providers, process-kill/lockscreen/device/platform/OCR/file/permission/transport acceptance and Mac full screenshot baseline recovery remain pending. The existing limited Mac baseline exception is not extended. This code/build slice does not mark the entire UI-3b task or product acceptance complete, does not call a paid API and does not merge develop/main/release.

Final local total: 338 passed. Web main.dart.js SHA-256: `d8baa0921774058ac005a7ee9172f05106f3274abd024e1811d8d41806746f97`.
