# UI-4a code/build validation

Base: `5afb08f2b0d53ca5d8578e63073fea6ac385a8af`.
Branch: `task/ui-4a-dynamic-runtime`. Dedicated worktree: `/tmp/ui-4a-dynamic-runtime`.

## Implemented boundary

Typed complete, node-only patches validate the entire candidate before atomic acceptance; incomplete messages, stale surface/snapshot/catalog/intent, malformed values, repeated node mutations and reused IDs with different contents reject without changing current. Same-ID retransmissions are idempotent. Patch history survives a higher-revision complete plan. Snapshot facts and computations cannot be changed by patch operations.

One validated shared renderer maps the minimal catalog plus layout/status/scope/confirmation/warning/sort adapters. Stable node keys retain focused inputs during reorder; confirmation value equality retains expansion on unrelated updates. Pure view sorting does not increment the business draft revision and cannot bind host draft inputs. Edits invalidate old confirmation references. Local events stay local; guarded business/semantic events reach the attached port. Pending requests freeze input references and correlate event/snapshot/plan/operation/draft revisions. Cancelled/stale/duplicate submissions do not reach the port. Rendering or awaiting a sink is not success. Receipts come only from the attached port with matching event, operation and draft; transport errors retain unknown pending results and operation locks. Unsupported catalogs/components fall back to read-only trusted facts/states/sources plus original text.

Public preview adds an explicit simulated memory operation (quantity 10→12), cancellation, semantic explanation without a model, and complete-patch controls. The old preview and host pages remain available. Batch mapping represents one existing host operation; per-record grants and business execution remain host responsibilities. `ui-preview` CI builds and uploads a static package only, without deployment. `scripts/ui_preview/smoke.mjs` is syntax-checked but has NOT run against a real deployed URL.

## RED evidence and independent review

Observed assertion failures before implementation/fixes: required unknown/source lost on fallback; patch stayed at revision4 or accepted incomplete/invalid candidates; business/semantic returned unsupported; controls unavailable; unsafe malformed patch threw; actual sort row order unchanged; full replanning lost patch ID history; sorting incremented draftRevision; reordered field lost its FocusNode; unrelated events collapsed confirmation payload; batch cancel and single pending/failure states were mislabeled. Test-location/source-span mistakes were corrected before treating their failures as evidence.

Independent reviewer initially requested changes for patch-history loss, view sorting changing draft revision and unstable component state, plus batch state presentation. Each was reproduced as RED and fixed. Read-only re-review: **APPROVE**, no remaining Critical/Important. Current5 test proves the next semantic event/sink sees actual patched event/current revisions; it does NOT claim UI-4b automatic/explicit planning or a real GPT call exists.

## Fresh local verification

Flutter3.47.5 / Dart3.13.4, existing isolated SDK. Commands run from their package with `test --no-pub --concurrency=1 --reporter=expanded --timeout=30s` (host timeout60s):

| Scope | Result |
| --- | --- |
| packages/muyon_module_api full suite | 37 passed, exit0 |
| packages/muyon_ui full suite | 246 passed, exit0 |
| apps/muyon_ui_preview full suite | 8 passed, exit0 |
| apps/muyon existing inquiry_write_tools_test.dart | 19 passed, exit0; real SQLite, original approval flow, quantity10→12 and rejection/cancel/stale paths |
| dart analyze module_api, muyon_ui, preview | No issues, exit0 |
| node --check scripts/ui_preview/smoke.mjs | exit0; syntax only |
| preview build web --no-pub --release | success, exit0 |
| git diff --check | exit0 |

Total310 local tests. UI Widget coverage includes390×844 /1440×900, dark theme, text scale1.8 edit/patch/back, light-theme confirmation, real sorting, focus and state assertions. No new screenshot baselines or accepted Mac exception were used. The entire monorepo Linux gate will run on the exact pushed task commit; its result is reported separately.

The runner temporarily adds sqlite3.source=system to root pubspec and restores its exact original bytes in finally; nothing is committed there. SDK configuration/cache and localhost proxy exceptions are isolated. Host tests use public temporary SQLite data and existing tools, not the browser port. Raw logs/build manifest remain in `/tmp/ui4a-logs`; build output remains ignored.

## Explicitly unverified/deferred

User-paused controlled cloud deployment, real browser smoke, screenshot/theme/accessibility browser matrix and actual hosting/URL; REG-4a V2 business catalog integration; UI-3b disk persistence; UI-4b planning providers/automatic and explicit calls; native OCR/files/permissions/transport/device/lockscreen capabilities. Compilation and Widget tests do not satisfy cloud/browser/native acceptance. Host tool regressions are separate evidence, not runtime host integration.

For later GPT exam replay and fine-tuning candidates, still needed: complete question/answer and task/turn recorder, versioned JSON parser/serializer, actual planning boundary, event/patch acceptance history, immutable source digests/snapshot revisions, actual receipts/user corrections, redaction/consent and candidate review. No API, credentials, paid models or training work was introduced; exam files are question/regression material, not gold runtime records.

Local Web main.dart.js SHA-256: `f2932abe0ade5b1f0a72a47becb63f0c53b43aec2c77fcc33e0c92bdf91f8a17`.
