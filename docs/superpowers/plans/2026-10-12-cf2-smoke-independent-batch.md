# CF2 / smoke / independent adapters implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement independent slices; preserve a separate non-author review gate for each immutable source. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Deliver independently testable host reason codes, smoke-entry support, single-target inquiry projection, library-2 recompute support and V2 claim-draft preparation.

**Architecture:** Each slice owns disjoint production files and starts at the same fixed develop. The integrator combines only reviewed immutable sources; missing downstream production wiring is recorded rather than replaced with test-only success.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, current workspace packages, existing SQLite and crypto contracts.

**Spec:** `docs/tasks/OIUI-RESEARCH-QUEUE.md`, `docs/design/conversation-fact-card-wiring-2026-10-11.md`, `docs/design/aiui-smoke-test-spec-2026-10-11.md`, `docs/design/research-local-export-facade-2026-10-11.md`, adopted ADR-0001 decisions.

## Incremental authorization and scope

Baseline: develop `e170fff89ba88af6937450ae2e83e2b6a7239da7`, verified remotely.

2026-10-12 user decision (source `Sentinel_e7a824dc14c881919029488712ae6a82`): “先不考虑历史数据迁移或者老的用户数据同步，其他的尽量并行推进”。 Historical migration and old-user synchronization are excluded from this batch; previous decisions/history remain intact. Current-data integrity, permissions, live scope/pin checks and same-candidate acceptance remain required. Newly saved candidate data's runtime restoration is not waived.

## Global constraints

- No default enabling, real paid model calls, Android build/install/adb, deployment, main merge, forcepush or branch deletion; do not export `MUYON_EVAL_REAL`.
- Do not send commercial original values to the model; preserve masking, permission and owner checks.
- LE04 remains held; do not retry its rejected dynamic actions through another tool/environment.
- Preserve original author branches/worktrees. No patching author code to conceal verification failure.
- Keep original logs outside Git; reports use fixed full SHA and actual pass/fail/skip/not-run counts.
- Historical smoke prerequisite-status prose is not current-state evidence: production stream/compiler/library2 and three persisted modes already exist.

## Review focus

- Model-authored reason codes cannot impersonate host errors or user preferences.
- Multiple selected objects cannot silently become the first object; typed masking must not become verified raw facts.
- Recompute candidates must use frozen accepted state and actual library2 validation, preserving version fences and zero business authority.
- Claim exports must reject mixed-scope requests, ambiguous bindings and changed sources without writing business rows/files.
- Smoke evidence cannot disclose secrets/endpoints/paths or count missing events/empty controls as successful acceptance.

## Independent slices and file ownership

### 1. CF2 host reason codes — le05_fix; review le05_review

Branch `task/cf2-host-reason-codes-20261012`.
Production ownership: `assistant/ui_planning.dart`, own reason helper, `platform/ui_planning_tool.dart`, `assistant/agent_context.dart`, `assistant/personal_agent.dart`, `screens/ui_stream_task_view.dart` as needed. Own tests only.
Consumes current UiPlanningResult, actual presentation preference and native stream result. Produces normalized derived result/tool/event/UI reasons and fixed Chinese explanations, separately classifying host/model/user. Existing independent raw model task summaries are outside this cleanup scope; no claim of whole-database sanitization.

- [x] Capture behavioral RED through actual provider/tool and persisted event (4e7d5ae5cdd14ce08dc7acd947d6421d89fd7486; 2 pass / 55 fail).
- [ ] Implement mapping without changing authority or presentation eligibility.
- [ ] Verify unknown reasons and forged host codes, native stream success, three modes, terminal/lifecycle regressions; reverse mutation fails naturally.
- [ ] Freeze source and obtain independent review/analyze/tests/CI.

### 2. Smoke entry — reg3ea_fix; review reg3ea_review

Branch `task/aiui-smoke-entry-20261012`.
Ownership: `integration_test/aiui_smoke_test.dart`, own `integration_test/support/aiui_smoke_*.dart`, own offline tests. Product hooks require collision review before edits.
Consumes real application, host scope source and real gateway/compiler/renderer; strict dart-define config. Produces stable prerequisite failures and a whitelist evidence object; foundation acceptance is distinct from complete real-device items 1–4/7.

- [x] Capture missing-config behavioral RED (59bacb85ee64c573e02171e5848bc5d23317dd7d; 0 pass / 1 fail).
- [ ] Implement config, actual fixture/driver, runtime preflight, faults, observation and evidence support permitted by current production capabilities.
- [ ] Test whitelist outputs and five-sample statistics offline; absent capabilities must fail, never skip/pretend success.
- [ ] Freeze source and review exact covered/not-yet-covered items; no real model/device execution.

### 3. Explicit single-object source — cf_source

Branch `task/cf-explicit-source-20261012`.
Ownership: `platform/inquiry_ui_planning_source.dart`, own helper/tests.
Consumes current task/conversation selected scope and InquiryReadonlySnapshots; produces a bounded one-object UiPlanningHostState after current owner/pin/scope rechecks. No complete CF answer coordinator or suggestions channel claimed.

- [ ] Behavioral RED: multi/duplicate/mixed selections rejected instead of `refs.first`; current-task drift after awaits refuses publication; typed masking is not verified.
- [ ] Implement exactly-one supported selection, conservative fact-state projection and final live-source checks.
- [ ] Run real host/source and existing stream/snapshot/harness regressions, mutations, strict analysis; freeze for non-author review.

### 4. Library2 recompute adapter — lib2_recompute

Branch `task/library2-recompute-adapter-20261012`.
Ownership: `platform/ui_recompute_adapter.dart`, own tests. Shared API/catalog/controller/evaluator unchanged.
Consumes actual library2 catalog and UiRecomputeInput frozen accepted values. Produces validated readonly candidate bundle; unsupported formula types fail closed. Production what-if owner wiring remains separate.

- [ ] Behavioral RED for supported library2 scalar scenario with genuine evaluator and validator.
- [ ] Preserve typed specs/collections/evidence, reject unsupported or view state, strip business capabilities, retain readonly routes.
- [ ] Verify successive edits, version fences, unsupported types, zero side effects and mutations; freeze for review.

### 5. LE03 claim-draft preparation — le04_fix (new unrelated assignment)

Branch `task/le03-claim-preparer-20261012`.
Ownership: new `research_module/lib/src/core/claim_draft_preparation.dart`, public export and own tests; old exchange/export/UI unchanged.
Interface: ResearchClaimDraftPreparer with trusted pinned-ObjectRef readonly source reader; prepareClaimDrafts(projectId, noteIds, resolved scope, generatedAt) returns frozen LocalExportPreparation-derived content. Reader is a trusted host seam, not proof of a production filesystem resolver.

- [ ] Behavioral RED for V2/scope/unique-binding/source restrictions.
- [ ] Implement frozen JSONL, source/manifests, actual included counts, exclusions/warnings and fixed IDs; no file/DB writes.
- [ ] Verify old pinned revisions, duplicates/mixed scope, changed sources, ambiguous binding, hash warnings, all-excluded refusal and immutability; freeze for review.

## Integration gates

- [ ] Source tests/analyze and non-author review against exact fixed SHA; unresolved important findings hold that slice.
- [ ] Exact source CI terminal and source inventory/hash/coverage-floor proof.
- [ ] Combine eligible slices with freshly verified develop, resolve only reviewed source conflicts; run applicable independent target/whole-workspace checks and complete combination CI.
- [ ] Normal merge only eligible reviewed tree into develop; verify full published SHA and post-merge CI terminal. Report held/incomplete pieces separately.
