# Product Rust Agent Host Seam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development. Root owns integration; directory owners implement and independent tests remain separate.

**Goal:** Real PersonalAgent facade drives the same Rust Agent through a default-off host backend and a genuine readonly inquiry.object roundtrip.
**Architecture:** Rust owns one loop; host supplies existing gateway/authorization/registry callbacks and retains original results/receipts. Use bounded private stdio and a metadata-only projection.
**Tech Stack:** Existing Dart/Flutter and std-only Rust; no new runtime dependency or model service.
**Spec:** `experiments/redesign/core-agent-lab/HOST-CONTRACT.md`.

## Global constraints

- Base3836149416020a0ac58f9e7ca788c20e66688e0e; preserve all legacy defaults and fixture/SSE contracts.
- Config default-off; no silent fallback, parallel legacy drive, model-issued approval or callId replay authority.
- No true model/credential/real data/write/history migration/default-permission change/M03 freeze/device claims.
- Raw validation logs outside Git. Rust toolchain absent; restored Flutter may be used with /tmp caches. Real compiled Rust RED/GREEN comes from existing GitHub runners, not invented local PASS.
- Isolated clones in/tmp; root sole pusher/integrator. Draft PR only; this task does NOT authorize merge.

## Review focus

1. Callback arrives for wrong task/turn or repeats after terminal: reject, no extra invoke/model request.
2. Real invocation result arrives around cancel/close: host original receipt survives, no further send, child is reaped.
3. inquiry record name/notes/raw summary contains private or credential canary: only fixed metadata projection crosses.
4. Core task is resumed/compacted after restart or backend fails: explicit unsupported/failure, never legacy fallback.
5. Enabled invalid binary/state path or disabled configuration: fail closed or unchanged legacy behavior respectively.

## Task 1 — Rust common loop and host process (host_rust_owner)

**Files:** Own `experiments/redesign/core-agent-lab/core/**` and `docs/tasks/REDESIGN-CORE-AGENT-HOST-P1-20261015.md` only.
**Consumes:** Exact internal protocol and metadata projection in HOST-CONTRACT.
**Produces:** Existing binary's explicit `host-session` command, `Agent::run_with_ports` or equivalent common-loop injection; existing CLI/Provider APIs retained. Trusted CLI `--root ABS --idle-ms N --total-ms N`; defaults5000/30000, positive capped overrides.

- [x] Add compileable types/command stub and behavior tests first; stub returns host_not_implemented. Commit immutable RED checkpoint before logic.
- [x] Run actual Rust test CI; observe assertion failure for a valid host roundtrip, not build/transport error.
- [ ] Inject host ports into SAME Agent loop; genuine inquiry arguments/result, separate invocation identity, control/limits and matching callback handling.
- [ ] Run targeted host units and retained legacy Rust/process/mutation checks. Add precise inverse for callback identity or one-loop budget guard, requiring compiled semantic failure.
- [ ] Commit source/report; non-author review fixed SHA; same owner fixes scoped findings.

## Task 2 — Actual Dart product backend (host_dart_owner)

**Files:** Own `apps/muyon/lib/assistant/**`, narrow `apps/muyon/lib/app/bootstrap.dart`, owner-only `apps/muyon/test/core_agent_process_owner_test.dart`, and `docs/tasks/REDESIGN-CORE-AGENT-HOST-P2-20261015.md`. Do not change registry/business handlers/grant defaults.
**Consumes:** host-session contract; actual AgentContext, ToolRegistry and model-gateway authority.
**Produces:** `CoreAgentProcessConfig` in `assistant/core_agent_process.dart`; nullable `coreAgentProcess` on PersonalAgent/MuyonHost.open; `modelClientFactory` narrow test transport hook; actual default-off facade routing.

- [x] Add compileable default-off config/facade stub first. Enabled stub fails with fixed core_backend_unavailable; legacy path intact. Commit before complete behavior.
- [x] Independent Task3 tests compile and fail assertions against this stub and actual Rust stub.
- [ ] Implement framed process/lifecycle adapter and genuine host callbacks, exact-request model admission, live prepared reference, original receipt lookup and field-by-field projection.
- [ ] Route cancel/close and unsupported continuations; no default changes/no fallback/raw errors. Add owner unit tests where blackbox cannot deterministically expose result/cancel race.
- [ ] Validate against actual Task3 tests and app analyze/regression; commit report; non-author fixed-SHA review.

## Task 3 — Independent product-chain tests and CI (independent checker)

**Files:** Own `apps/muyon/test_host/**`, `experiments/redesign/core-agent-lab/host-checks/**`, `.github/workflows/core-agent-host.yml`, and `docs/tasks/REDESIGN-CORE-AGENT-HOST-P3-20261015.md` only. Tests directory is explicitly invoked by required host workflow; ordinary test discovery is unchanged.
**Consumes:** Public config/facade/MuyonHost APIs and protocol contract, not implementation output as expected values.
**Produces:** Offline real-facade/compiled-Rust integration suite, transparent process recorder and real gateway offline HttpClient; required CI with source/binary SHA and no-skipped-test evidence.

- [x] Freeze synthetic supplier store + actual selected ObjectRef using existing business_tools_test setup; model returns one native inquiry.object call then answer dependent on captured actual result.
- [ ] Write semantic assertions for all Required offline evidence and five Review focus cases. No chat/chatStream override, substitute business handler or separate demo driver for positive case.
- [ ] Required CI builds Rust `--offline`, uses existing Flutter setup, invokes `flutter test test_host/core_agent_host_test.dart --reporter expanded` with `MUYON_TEST_CORE_AGENT_BIN` absolute binary. Missing binary is error, never skip/pass.
- [x] Run first fixed compiling stub RED; preserve raw logs outside Git and fixture/input provenance. No output-driven golden rewrite.
- [ ] Run GREEN on exact combo. Add minimal semantic inverse controls for projection leakage/authority-correlation/one-driver behavior, in isolated copies; compiler/timeout/unrelated failure does not count.
- [ ] Non-author review checker/helpers/workflow separately; keep original assertions during owner fixes.

## Task 4 — Root integration/review/draft PR

**Files:** Root owns this plan, HOST-CONTRACT, final task-review doc and external per-plan ledger/evidence only. Root does not implement product code.

- [x] Formal short SPEC/QUALITY review before implementation; resolve only genuine scope/interface conflicts.
- [x] Separate task branches/clone directories; cherry-pick into one review branch, prove owned blobs equal fixed author sources.
- [ ] Preserve RED branch and logs, all source failures and independent expectations; actual semantic negative controls.
- [ ] Non-author Task1/Task2 and checker review, then whole exact-candidate review. Fix same owners; scoped re-review.
- [ ] Exact final host/Core Agent/full-regression CI terminal and actual checkout SHA/source/binary evidence; all required gates success.
- [ ] Create draft PR→develop; final report exactSHA/CI/reviews/remainingdevice+realmodel limits. Do NOT merge/main/forcepush/delete/deploy.
