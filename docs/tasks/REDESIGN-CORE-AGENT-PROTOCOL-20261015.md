# Core Agent P1 protocol seam implementation plan

> **For agentic workers:** Use existing original subagent writers and independent SPEC/QUALITY reviews. Do not create duplicate writers. The user has selected the execution method and authorized choosing this minimal slice then implementing it; report scope before implementation. P09/old OC/CR10 tasks remain closed/parked.

**Goal:** Feed raw fragmented Chat Completions SSE into the actual Rust Agent and prove its next serialized request contains the real original tool result through an independent stdio fake service.

**Architecture:** Add a bounded strict JSON/SSE adapter, request encoder, controlled stdio transport and injectable provider to the existing Rust lab. Preserve C1 policy, counters, Binding/receipt/recovery paths and original scripted API. Distinguish protocol completion, transport interruption and actual effect uncertainty; all native call authority still comes from the host.

**Tech Stack:** Existing std-only Rust crate; Python stdlib fake service/checker; preinstalled GitHub Rust/Python. No new crate/dependency installation or model/network credentials.

**Spec:** `experiments/redesign/core-agent-lab/WIRE-CONTRACT.md`; accepted ADR0005 and v1.3.2 W4, current-source audit outside Git.

## Global constraints

- Exact base `75981959070a4b8d6a6158dbb132e48eea8858fa`. Only core-agent-lab/, owned P1/P2/parent task docs and dedicated core-agent-lab.yml may change. Old product/labs/CI/dependencies remain unchanged; existing process.py/test_harness.py/old fixtures unchanged.
- Same original core writer/checker, no duplicate writers. Root metadata/contracts/integration only. Non-author immutable review, exact candidate and exact postmerge dual CI gates.
- Preserve four modes, hard gates, R1/R2 evidence-vs-control separation and original Binding replay. No real model/HTTP/secret/egress/native/M03 freeze. Raw logs external, no artifact403 workaround; local Rust execution NOT_RUN unless an installed compiler is actually available.
- Exact supported shape, strict terminal, limits and CLI/stdio ABI are in WIRE-CONTRACT. No implicit retry, partial tool execution or output-to-authority conversion.

## Review focus

1. Complete-looking arguments followed by wrong/missing terminal or child failure must yield zero effect, not early execution.
2. Provider call-ref/native role metadata cannot be reconstructed from injected content or replace host invocation identity.
3. Silent stream cancellation, bounded backpressure and child cleanup must not hang or leak unlimited memory/processes.
4. Provider crash/reopen cannot resend or reset charged counters; historical receipt hold cannot consume next confirmation/request.
5. Handwritten std-only JSON must correctly handle escaped Unicode, duplicate keys, strict numbers, deep unknown fields and byte bounds without a permissive partial parse.

## Task 1 — core and byte adapter (same rd_core_agent_writer)

**Files:** create focused `core/src/wire_json.rs`, `wire_sse.rs`, `wire_provider.rs` (split transport if helpful), `core/tests/wire.rs`; modify `core/src/model.rs`, `agent.rs`, `main.rs`, `lib.rs`, existing mutation runner and CLI docs only as required; own `docs/tasks/REDESIGN-CORE-AGENT-P1-20261015.md`.

**Consumes:** WIRE-CONTRACT host flags, raw request/response bytes and existing trusted host facts, ModelRequest and original receipts.

**Produces:** injectable provider/control path and structural call pairing, strict supported SSE turn decoder/encoder, stdio transport, persistent wire counters/inflight barrier. Freeze exact internal signatures in owned doc before integration; no production ABI claim. Public black-box interface is WIRE-CONTRACT CLI/stdio.

- [ ] Write compileable stub and meaningful Rust failing tests first: fragmented valid tool/answer + wrong finish/DONE + native result pairing + cancelled/error exchange. Preserve immutable RED commit; root runs actual preinstalled Rust CI, compilation/setup failure is not semantic RED.
- [ ] Implement strict bounded JSON/SSE plus actual request encoding; tests pin escaped Unicode/surrogates, duplicate fields, per-index metadata conflict, invalid args/old function_call, unsupported multiple calls/choices, usage unknown, terminal plus trailing failure.
- [ ] Inject provider without weakening current C1 path; persist structured call metadata and matched original result, provider in-flight and wire budget charging. Tests assert no authority in payload, legitimate result reaches next request, no implicit resend on reopen and existing R1/R2 barriers.
- [ ] Implement fixed Python stdio service boundary, bounded read/control/idle/total, kill/reap on failures, sanitized errors and request/response caps. Test no effect before terminal, no retry, silent cancellation, post-effect cancellation and budget persistence.
- [ ] Add targeted compiling inverse mutants; retain all existing 8 mutation gates. Commit owned paths only. No push, merge, external models/install or checker changes.

## Task 2 — independent raw-byte/service evidence (same next_contract_evidence)

**Files:** new `checks/wire_process.py`, `checks/test_wire_harness.py`, `fixtures/wire/` with independent fake_service.py and raw .sse inputs; extend dedicated `.github/workflows/core-agent-lab.yml`; own `docs/tasks/REDESIGN-CORE-AGENT-P2-20261015.md`.

**Consumes:** fixed CLI/stdio WIRE-CONTRACT plus actual Rust executable, never expected outputs in DUT or implementation-derived byte goldens.

**Produces:** independent service-captured wire request bytes, physical tool evidence assertions, decoder/cancel/limits/recovery process checks and oracle self-negatives. Existing C1 checker/files remain byte-identical.

- [ ] Before reading implementation, author raw SSE inputs and helper that captures exact stdin request before emitting controlled bytes. Happy second response derives from received tool value/receipt; expected physical facts are separate checker assertions.
- [ ] Add oracle self-tests that reject role=user substitution, wrong call ID and missing assistant tool call; validate fixture/script configuration and deterministic checkpoint synchronization without sleep ordering.
- [ ] Implement process cases for WIRE-CONTRACT's six evidence groups, including per-byte transport read equivalence, complete-call-before-terminal observation, cancellation/no further request, hard policy, original replay/unknown and persistent budgets. Inspect actual effects.db independently.
- [ ] Extend existing scoped offline core workflow with required new harness/process checks; preserve old commands, permissions, action pins and filters. No new general workflow or manual trigger. New checker missing/failure must fail CI.
- [ ] Commit only owned paths; root pushes isolated RED/final review refs and retains all failed logs. Do not adjust assertion expectations to a failing DUT without a sourced contract gap and independent review.

## Task 3 — root/non-author gates

- [ ] Finish current-source audit and provisional design self-review; non-author review WIRE-CONTRACT before implementation. Report selected scope/owners in chat under existing choose-and-implement authorization; no repeated permission for routine reversible lab work.
- [ ] Assemble compileable RED, run dedicated exact CI, preserve real failure and cancel unrelated regression only for intentional RED branch if justified. Implementers continue on their own paths, no cross-writes.
- [ ] Freeze actual fixed author SHAs, compose exact candidate, compare author blobs/modes and allowed baseline delta; independent SPEC then QUALITY review of immutable sources and actual runtime evidence.
- [ ] Require existing C1 + new wire tests/harness/mutations and full existing regression at exact candidate. On important failure use original owner for fix with unchanged independent oracle and preserve RED.
- [ ] Normal expected-head develop merge under standing LeaderB authority, verify ordered parents/tree/main/branches, await exact postmerge core and full regression terminal. Report actual offline capability and unmet product contracts separately.

Self-review: task boundaries follow core vs independent evidence ownership. The spec fixes supported wire semantics and black-box ABI; internal signatures remain replaceable writer-owned implementation details, not a second product contract. No existing checker or product rewrite is used to hide failure.
