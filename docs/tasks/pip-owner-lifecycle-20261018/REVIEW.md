# Independent read-only lifecycle review

Reviewed commit: `853687cb0ce7d7e0133808f05a07258175c6b486`.
Reviewed tree: `133e03b30b57f8ead0aa687537d149173b105bb6`.
Base: `05d224f4b4fb31b3e015ea88cdaa7a14b03978b8`.
Ownership source inspected: `52906b50db1825c165ac237a7f7a21efdc5a0bbf`, PIP-PATH-OWNERSHIP.md.
Requirements inspected: docs/tasks/pip-owner-lifecycle-20261018/{README,API,LEDGER}.md.
Review time: 2026-10-18 UTC. Rust 1.90.0. Repository remained clean; no source or Git writes.

## Ranked findings

No blocking findings in the reviewed Catalog scope. No actionable correctness/security regression found requiring a source revision.

Nonblocking integration limits, in impact order:

1. **Host settlement remains a trust precondition.** lifecycle.rs:315-333 invokes the supplied synchronous persistence callback and cannot verify actual handler quiescence, durable storage completion, or the original receipt identity. The host must retain WorkLease, stop/join its actual handler outside the Catalog lock, persist its original final/unknown receipt, then acknowledge settlement. Empty test callbacks do not certify these properties. This is explicitly documented and consistent with the authorized scope; adopting the seam still requires host integration review.
2. **Mixed legacy/managed dependencies can prevent selective unload indefinitely.** A legacy consumer is recorded as a dependent, correctly blocking provider stop; legacy enrollment returns no OwnerLease and cannot be selectively released through this API. Global wire close fences it but does not remove it. Hosts needing selective unload must enroll the consumer as managed from the start, or reconstruct the Catalog under their recovery policy. No legacy wire enrollment is silently migrated. Confirmed by external probe; no unsafe bypass was found.
3. **Callback panic recovery is the host's responsibility.** Actual callback panics leave Catalog work/ownership metadata intact but unwind; a surrounding standard Mutex can become poisoned. Close/persistence may already have produced external effects, so explicit retry must follow the host's recovery policy and use retry-safe callbacks. This is retention, not automatic retry or end-to-end recovery certification.

## Review conclusions

- Registration retains exact owner key sets only after complete closed validation. Bounds remain eight modules and per-bundle declaration/schema/wire limits; outstanding managed work is bounded globally at 128. Failed registration does not reserve namespace/binding, and quota refusal preserves the pending ticket.
- Owner identity uses an opaque Catalog Arc plus monotonically checked owner epoch. Stale same-Catalog leases observe Released; foreign Catalog leases fail. Stale release skips cleanup, including after same-name reenrollment. Work IDs do not reuse within a Catalog; old successful settlement skips its callback and cannot consume a replacement ticket.
- Managed operation wire invoke returns owned_dispatch_required. Typed dispatch checks owner identity/epoch, module, closed state, existing authority, generation and one-shot admission before retaining work and returning dispatch. Wrong-owner attempts preserve the ticket. Legacy enrollments retain the old wire execution path.
- Dependency metadata covers direct DATA schema references, relation endpoints and operation/view DATA references. Operation schema references must already appear in data_refs. Registration validates the full explicitly admitted foreign schema closure. Provider stop is blocked by every registered direct consumer, so retaining those edges also protects transitive dependencies. New admission cannot reference a stopping provider. Stop rejection does not partially fence or cancel.
- Stop fences owner discovery/preparation/dispatch, retains namespace reservations, requests cooperative cancellation and removes its tickets. A generation change also invalidates unrelated prepared tickets, as explicitly documented. Existing dispatched work survives cancel, accept_result, global close, handle drop and ticket deletion until successful settlement.
- Release requires stopping, zero tracked work and no registered dependents. Successful close precedes removal of exactly that owner's metadata/bindings/counts. Close errors and actual panics retain ownership/fencing. No Catalog business-data deletion or receipt manufacture was introduced.
- The original 22 tests are unchanged relative to base. The 15 committed lifecycle tests cover stale/foreign identities, wire bypass, authority denial, fencing/dependencies, retained work, idempotence, cancellation, quota, exact removal and a disposable completion marker. The marker test is not production receipt/store/HTTP/reopen coverage.

## Independent verification

Environment for cargo commands:

```sh
export CARGO_HOME=/workspace/pip-toolchain/cargo
export RUSTUP_HOME=/workspace/pip-toolchain/rustup
export PATH=/workspace/pip-toolchain/cargo/bin:$PATH
export CARGO_TARGET_DIR=/workspace/pip-lifecycle-review-target
cd /workspace/Muyon
cargo test --locked --offline --manifest-path experiments/redesign/plugin-contract-lab/core/Cargo.toml
cargo test --locked --offline --manifest-path docs/tasks/pip-registry-20261018/probe/Cargo.toml
rustfmt --edition 2021 --config skip_children=true --check experiments/redesign/plugin-contract-lab/core/src/lifecycle.rs experiments/redesign/plugin-contract-lab/core/tests/owner_lifecycle.rs
```

- plugin-suite.log: exit 0; 37 passed = 22 original + 15 lifecycle, no failures.
- registry-probe.log: exit 0; four publication audit probes passed.
- rustfmt.log: empty successful output; exit 0 for only the two requested new files. Legacy lib.rs style intentionally not checked/reformatted.
- adversarial.rs and adversarial.log: three **separate external reviewer probes**, exit 0. These test actual persistence and close callback panic retention, legacy dependent rejection with no partial cancellation/ticket loss, and unrelated generation changes preserving leases while invalidating old tickets. Deliberate caught panic output is expected. These do not increase the committed suite's 37 count.
- identity-and-scope.log: fixed commit/tree, empty git status, changed-file inventory.

The external probes are compiled directly with rustc against the rlib produced by the locked/offline plugin builds; no additional Cargo manifest or dependency was created. adversarial.log contains the exact rustc and test commands, and adversarial.rs is retained alongside it. The support fixture/module is read directly from the reviewed fixed repository. No product edit was made.

## Explicit exclusions / remaining blockers

No rust-agent-host-lab source was inspected or modified, no host test suite ran, and no UI/Android/OCR/store/receipt-authority work was undertaken. No network provider, real user data, migration, deployment or integration operation ran. No host handler drain/durable original-receipt persistence/process recovery/Android acceptance claim is made. Dynamic schema evolution is not certified.

I04 original legacy script-provider -> HTTP -> reopen, and every equivalent/retry/split, was not executed. It remains DENIED_BEFORE_EXECUTION/BLOCKED with its existing merge hold. This report approves no merge, host adoption or deployment and does not change that hold.
