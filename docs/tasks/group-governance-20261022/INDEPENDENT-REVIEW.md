# Independent GR offline model review — 2026-10-22

Reviewer: independent child agent; read-only review, no working-tree edits, commits, push, real model/search calls or gateway execution.
Reviewed base: f4781e16ddf4e542b983fbd77f266a0071148255. Reviewed unstaged implementation: `crates/muyon-core/src/group_governance/mod.rs` (446 lines), `crates/muyon-core/tests/group_governance.rs` (480 lines), and one `pub mod group_governance;` export.

## Validation

- `/tmp/muyon-rust/bin/rustc --edition=2021 -D warnings --test crates/muyon-core/tests/group_governance.rs -o /tmp/muyon-group-review-tests`: exit 0, no warnings.
- `/tmp/muyon-group-review-tests`: exit 0, 20 passed, zero failed/ignored.
- Read `git diff -- crates/muyon-core/src/lib.rs`, `git diff --name-only f4781e16ddf4e542b983fbd77f266a0071148255`, and `git ls-files --others --exclude-standard`: only the three permitted code paths at review time. Untracked code is included in this scope review.
- Confirmed actual existing workflow boundary at `agent/workflow.rs:563–590`: root parent requirement; historical child count includes root, and queued/running/waiting_confirmation/unknown consume active capacity. New model removes root by adapter contract and derives 8 lifetime/2 active from rows, not mutable parallel counters.
- No Cargo integration claim is made by this review; the command above compiles the exact production module through a socket-free test inclusion, not the entire crate or Android product.

## Findings

**应改 R1 — unknown child can be hidden by an inconsistent budget/request projection.** `mod.rs:278–285,318–333`: the stop check considers budget unknown IDs and command Submitted/Unknown records but not unknown child state. A snapshot with one `LedgerChild { state: Unknown }`, no commands, and empty accounting unknown IDs returns `Eligible` for a different new child. This is an inconsistent snapshot, but a fail-closed validation boundary should reject it rather than depend on an unimplemented adapter to preserve that invariant. Recommendation: after the active-cap check, return `ReconcileOriginal` for any unknown child; preserve the existing two-unknown active-cap behavior if desired. No reserve clearing or retry should be added.

Independent minimal probe was built outside the worktree at `/tmp/group-governance-review-probe.rs`, by including the exact production module and adding only `review_unknown_child_without_accounting_marker_must_pause`. Command: `/tmp/muyon-rust/bin/rustc --edition=2021 -D warnings --test /tmp/group-governance-review-probe.rs -o /tmp/muyon-group-review-probe` (exit0), then `/tmp/muyon-group-review-probe --exact review_unknown_child_without_accounting_marker_must_pause` (exit101). Observed `Ok(Eligible { child_id: "a" })`, expected `Err(ReconcileOriginal)`. This is pure in-memory verification, no external execution.

**可选 R2 — identify policy layers by type when wiring.** `mod.rs:220,229,334`: four identical `Grant` values are accepted positionally. The present intersection is conservative, but types cannot prevent an adapter from accidentally duplicating one layer and omitting another. Before production wiring, use named user/group/task/tool authority fields or independently verify the adapter's provenance. The module explicitly labels inputs trusted, so this is not an execution bypass in this isolated batch.

## Delivery assessment

- Owner/admin versus member/coordinator: satisfied for this model. Only `Principal::Human` can manage; owner/admin can narrow, not widen. Host-only rejects a coordinator and modeled fixed/per_task execution is unsupported.
- Exact scope/capability intersection: satisfied for proposed nodes across four supplied policies plus member capability; unknown members/invalid grants fail closed.
- DAG and deterministic selection: satisfied; all proposed components cycle checked, missing dependencies rejected, next ready node is deterministic by ID, only completed ledger dependencies unlock nodes.
- Capacity: satisfied; depth1, lifetime8 including cancelled/failed, active2 including queued/unknown. No persistent alternate count introduced.
- Versions/epochs: satisfied as pure comparison against the caller's current trusted snapshot, not live ownership proof.
- Duplicate commands: satisfied for identical stable IDs; returns original lookup including unknown/stopped cases. Payload collision rejects; no send or mutate occurs.
- Budget: checked integer arithmetic and explicit unresolved request stop preserve supplied reserve. R1 remains an inconsistent-snapshot gap.
- Rounds: bounded by all original command records across cloned/restored snapshots. No persistent counter exists here.

## Limits and recommendation

This is a standalone advisory model, not a scheduler, actual host authority token, durable queue, receipt writer, cost proof, production group schema migration, handoff executor or exactly-once gateway. It has no transport, filesystem mutation, database schema, UI or model calls. Real integration needs authoritative complete root/child and original request/budget projections (no truncated event feed), immutable configuration/scope binding and transaction/claim recheck in the sole host gateway. An adapter must never treat `Eligible` as permission to execute.

## Independent fix recheck

The author added the real regression `unknown_child_blocks_even_when_request_and_budget_projection_omit_it` at tests:483–492 and the minimal unknown-child guard at module:334–337. I reread that diff and independently rebuilt/reexecuted the full suite: `rustc --edition=2021 -D warnings --test crates/muyon-core/tests/group_governance.rs -o /tmp/muyon-group-review-tests` followed by `/tmp/muyon-group-review-tests`: exit0, **21 passed, zero failed**, no warnings. I also rebuilt the original independent probe against the updated module as `/tmp/muyon-group-review-probe-fixed`; its one targeted test now passes (exit0). R1 is CLOSED for this offline model. The guard does not mutate snapshot/reserve, add dispatch or implement receipt lookup execution.

Final reviewed module: 450 lines; SHA256 `0cea48fe4e01a95c0980e0d77d4ece899f6aa86adc58c4c43a8d2b068a2b0099`.
Final reviewed tests: 492 lines; SHA256 `1487f996311cd8d9a65970d6f02cc135f36ee5cd35b39fe790e57d119a477076`.

Recommendation at this review revision: the **isolated offline model is acceptable for handoff**, with R2 and the documented production integration limits retained. No remaining blocking code finding was identified in this scoped read-only review. This does not claim Cargo/product CI/Android/runtime integration or approve merging/deployment; Leader B remains the unique develop integrator.
