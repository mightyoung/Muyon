# MIG20 offline group runtime implementation

Approved task scope: deterministic advisory scheduler, fixed/per-task coordination and bounded epoch handoff, parallel result/evidence collection, dissent summaries, stop/deadline/round/budget gates and original-request lookup. No external Agent execution, persistence owner or second accounting ledger.

Fixed inputs read: governance `7fde617bab8f45644820590529def5b2f2193454`; design intake `400e206135690c284c8402521e3135cfb7bfaee8` (2026-10-22 master and group research GR-01–08); UI `98baa979223d96094f11a56c3ac6d48f9b84c0eb`; document core `f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac`. Worktree based on governance commit; dependencies are read at fixed commits, no assumed shared directories. No AGENTS.md or .agents skills found in the workspace or fixed governance/design trees. Existing embedded paper/supplier skills concern model tools and are not invoked.

## Owned files and interfaces

- New `crates/muyon-core/src/group_runtime/mod.rs`: standard-library-only coordination state and advisory scheduling against existing group_governance types. Reuses host_only validator using an explicit host-only *validation projection* after separately validating captured runtime coordination configuration. Does not alter unsupported-mode behavior of original API.
- New `crates/muyon-core/tests/group_runtime.rs`: offline synthetic event contracts, standalone rustc and Cargo integration test compatible.
- This task directory: plan, raw verification outputs and review/report.
- No edits to lib.rs/group_governance/documents, MainActivity/ChatScreen, ProductService/ProductChatRuntime or existing accounting/requests.
- Core owner integration request: `pub mod group_runtime;` only; host owner must reconstruct runtime from trusted durable config/epoch/handoff count and feed consistent complete host snapshots, named policy grants, original receipts and monotonic host time. Atomically recheck before existing intent/reserve/claim gateway. Advisory decisions confer no authority. No new transport trait or fake external success.

## Steps

1. Write behavioral contracts, observe RED (compile-missing distinct from behavioral failures).
2. Implement mode selection, exact snapshot fencing, deterministic next intent, safe bounded handoff and minimal reference package.
3. Implement source/version-aware parallel result collection with identity/request attribution, stale epoch evidence separation and dissent aggregation without majority truth.
4. Negative tests for scope, epoch, malformed/replayed events, unknown/submitted/prepared, missing cost usage, stops/deadlines and arithmetic limits; preserve host budget unchanged.
5. Independent read-only reviewer reruns tests; repair issues with regression RED/GREEN. Run existing governance and Cargo suite, preserve failed and NOT_RUN evidence.
6. Commit new owned files, push independent task branch, verify remote full SHA. No merge, deployment, real model/search/user file access; existing two unknown requests and reservations untouched.

Modes remain explicit options; absent configuration uses host_only only. Production persistence/host wiring/UI/real Agent execution remain integration work for owners and HOLD gates.
