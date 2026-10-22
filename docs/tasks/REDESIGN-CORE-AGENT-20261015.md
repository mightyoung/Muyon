# Core Agent C1 implementation plan

> **For agentic workers:** Use subagent-driven implementation and independent spec/quality review. User priority Oct15 01:10:54Z Sentinel_b1ebc43f89148191b90f5a4bc7aeaf5e is core Agent first. P09 is parked, no supplier page expansion.

**Goal:** Execute one real Rust kernel loop against an offline synthetic provider: input → model/tool request → trusted host authorization → one durable synthetic effect/original receipt → subsequent answer. Cover cancellation, definite failure, outcome unknown, restart lookup and persistent limits.

**Architecture:** New isolated std-only Rust crate, typed provider/tool/policy ports and private fixture file stores. It reuses the design's existing semantics rather than copying the Dart implementation or supplier business. The sole synthetic tool's actual effect and original receipt share one atomic snapshot; a separate durable task journal marks dispatch before execution. Recovery queries the original effect store; no blind replay. Explicitly experimental, no M03 freeze or product/database/HTTP/native integration.

**Tech:** Rust edition2021 std only (no external crates/downloads), Pythonstdlib independent process checks, installed standard GitHub ubuntu runner Rust for actual compilation. No accessible local compiler; local source checks are not Rust execution evidence.

**Spec:** v1.3.2 chapter5/W4 and D01a/D03a semantics; ADR0005 with later current-source behavior audited privately in /workspace/reports/rd-core-agent-20261015/current-code-audit.md. Existing Dart functionality is retained and P06/P07/P08 are closed inputs.

## Global constraints

- Exact base3b4a7b27afded3f2d3007028d793aa06bd564312. Only new experiments/redesign/core-agent-lab/, owned CORE task docs and new .github/workflows/core-agent-lab.yml. No apps/packages/oldlabs/oldfixtures/oldworkflow/main changes.
- One core writer owns core/; one fixture/CI writer owns checks/, fixtures/, newworkflow and own taskdoc. Root owns parent plan/CONTRACT and integration metadata. No cross-writes or independent-author self-review.
- Typed lab ports are provisional and replaceable. No supplier schema/normalization, model HTTP, credentials, real users/data/models/devices, new packages/install/licenses/payment, deployment, forcepush or deletion. Preserve all writers/evidence and initial failures.
- Provider/model/tool text has no approval/scope/authority. Registered tool set, mode, scope, risk classification and hard prerequisites come from separate trusted host fixture facts. Unknown tool/field/invalid request rejects before effects.
- Four modes stay settled: read-only denies writes; ask-every-time requires a current trusted confirmation; Auto low allows and high requires current trusted confirmation; FullAllow high/taint/new destination adds zero risk asks when hard prerequisites hold. Scope/capability/revocation/business/classification hard denial stops all modes. Confirmation cannot fix a hard denial. Synthetic permission is explicitly not a production issuer or TTL.
- Distinguish Task/Attempt/ModelTurn/Invocation/Receipt; a provider call ID is correlation, never host authority/idempotency. Stable host-owned invocation binding includes task/attempt, tool and exact arguments/scope. Same binding replay returns the original receipt, altered binding conflicts. No digest/canonical wire/product identity selection is implied by exact lab equality.
- Journal dispatch marker persists BEFORE calling the tool. Effect count/data and receipt commit atomically in the synthetic store. If either durability or response is uncertain, retain original binding and outcome_unknown; lookup-not-found/corrupt/unavailable does not permit replay. Reopen preserves limits and original receipts.
- Before dispatch cancellation means zero effects. After dispatch cancellation is a request, not proof of cancellation; a committed receipt stays committed and further model calls stop. Failures must not fabricate success. Provider failure, budget and cancellation paths produce bounded typed terminal outcomes.
- Context preserves user/assistant/trusted tool-result roles and immutable task binding; provider never reads golden/expected/caseID. Persist measured step/model-call/context/output/total-unit counters; check limits before work and after responses, reject zero/invalid/overflow configuration, and do not reset budgets on restart. Synthetic units are measured bytes, not claimed tokenizer/real model cost.
- Single-process/private Linux fixture storage only; strict bounded versioned reader fails closed, exclusive ownership/lock, atomic rename and fsync documented. No power-loss/production DB or exactly-once remote-provider claim.
- Raw logs external. A new isolated CI uses preinstalled runner Rust, `cargo test --offline --locked`, independent process checks; existing Flutter regression gates remain unchanged. No missing local tool is bypassed by an install or false runtime claim.

## Review focus

1. Same invocation / lost response / restart must produce exactly one physical effect and the original receipt; key-with-altered-arguments must reject.
2. A model saying approved or using a registered-name alias must not supply authority, scope or a new hidden invocation; revalidate host facts before execution.
3. Cancellation after actual commit and before reply must retain committed fact, stop following model calls, and not relabel the effect cancelled.
4. Crash between durable dispatch/effect/receipt/task checkpoints must preserve lookup-only uncertainty, including not-found/corrupt/unreadable stores.
5. Exhausted step/context/output/total-unit budgets must survive reopen; unbounded provider scripts/messages, malformed lab input and stale provider events must not continue effects.

## Task1 — Rust core writer

Owner rd_core_agent_writer, exclusive core/ and docs/tasks/REDESIGN-CORE-AGENT-C1-20261015.md. Create Cargo.toml/Cargo.lock std-only library/binary/tests and source startup documentation. No workflow/checker ownership.

Consumes typed host facts, provider script data, tool registry and private fixture directory. Produces Rust Agent/Provider/Authorizer/ToolPort APIs plus CLI protocol described in CONTRACT. Keep modules small and isolate provider/session/policy/ledger/runner concerns. No general framework or new frontend.

- [ ] Write meaningful unit/integration tests and compileable minimal failing implementation first. Commit an immutable RED checkpoint for dedicated Rust CI; absence of a compiler locally is NOT_RUN. Root pushes the dedicated review branch, no author pushes.
- [ ] Implement minimal provider/context/loop, policy boundaries, actual durable synthetic tool/receipt, restart lookup and persistent limits. A scripted response must be input data, never scenario-ID lookup of expected outcomes.
- [ ] Run actual Rust RED/GREEN in authorized existing-runner CI once available. Treat compile failures as setup failures, not behavioral RED. Do not claim tested Rust from static/Python checks.
- [ ] Include targeted inverse mutations for policy bypass, unknown redispatch, receipt/double-effect and budget reset; semantic runtime failures required, restore clean GREEN. Report counts/first failures and storage limits.
- [ ] Commit only owned source/doc files; no push/merge or subagents. Root organizes immutable independent review.

## Task2 — Independent process fixtures and isolated CI

Owner rd_core_agent_checks, exclusive checks/, fixtures/, new core-agent-lab.yml and docs/tasks/REDESIGN-CORE-AGENT-C2-20261015.md. Author independent expected physical effects/state/receipt assertions, no source fixes.

- [ ] Define exact synthetic provider inputs and independent process tests before reading DUT. Happy loop, malformed/unknown tool, provider/tool failure, four-mode hard/soft policy, forged approval, cancel before/after dispatch, double invocation, altered binding, budgets/context and restart counters.
- [ ] Use real subprocess checkpoint notifications and SIGKILL (no sleep-based race), inspect durable physical effect/receipt state independently and restart original task with lookup only. Not-found and corrupted lookup stay unknown and zero new execution.
- [ ] New workflow only standard ubuntu runner with preinstalled Rust/Python, read-only repo permission, existing pinned checkout/upload actions, no dependency installation/network model. Run exact checkout SHA/tool versions, offline locked cargo tests and independent process checker. Preserve tiny synthetic build/test evidence artifact if needed, no private data.
- [ ] RED checkpoint CI deliberately fails behavior tests; record separately and cancel unrelated old regression on that intentional RED branch if needed. Final candidate and postmerge must pass all applicable existing regression plus new core checks at exact full SHA.
- [ ] Commit owned files only, root pushes. A fresh non-author reviews both task implementations and whole candidate. Missing real model setup listed separately.

## Task3 — Leader B coordination and integration

- [ ] Record current Dart/Rust capabilities and exact P09 parking status. Current source audit already delivered; no old acceptance reruns.
- [ ] Keep source/fixture outputs isolated; publish only normal independent review refs to run authorized CI, never product/main/deploy. Preserve original failures and directories.
- [ ] After immutable non-author C0 and exact candidate CI success, normal develop merge only, verify full SHA/ordered parents/tree/main, and await exact postmerge regression and core CI terminal. If runtime/core behavior fails, do not merge.
- [ ] Final evidence separates typed source, actual synthetic Rust/process execution, provider fixtures and production/native NOT_RUN. M03 stays blocked_contract; real model adapter needs separately authorized endpoint/profile/credentials/cost/authority/payload-ledger validation.
