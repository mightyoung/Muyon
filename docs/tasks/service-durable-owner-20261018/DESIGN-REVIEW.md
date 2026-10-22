# Independent bounded-slice design review

Reviewed source: `4b609602f76996ec69e9f51da8bc4261d6a2d94a` in `/workspace/Muyon`; reviewed the uncommitted task `PLAN.md`, `ServiceHostBindings.kt`, and Rust `core/src/service_provider.rs`. This is a design review, not verification of implementation. No tests, network actions, old databases, credentials, or remote writes were performed. No AGENTS.md was present in the workspace file search.

## Decision

Accept the bounded durable admission component as a prerequisite, subject to the concrete contracts below. The proposed scope correctly leaves production authority approval and Application/Service installation unresolved. A synthetic authority proves the mechanism only; it does not establish a trusted production policy owner. ConfiguredChat remains unavailable. Existing SyntheticLab mode and Auto/FullAllow semantics must stay unchanged.

The Rust bridge provides repeated current-binding checks and exact prepared-call correlation, but those checks do not make the final callback atomic with authority mutation. The new owner must supply that guarantee itself. The existing callback intentionally converts owner failures into denial; it must never convert a storage/authority failure into SyntheticLab or an allow.

## Required implementation contracts

1. **Authority linearization.** Define one authority operation that keeps its current exact scope, provider, permission, credential-existence, owner identity and conservative full-call proof stable until the enclosing database transaction has committed or rolled back. Every policy/profile/quota revision, revocation and credential-existence mutation must participate in that same protocol. An owner-instance mutex or a snapshot followed by an unlocked commit is insufficient. All owner objects sharing one authority must share the guard. Document lock order and forbid reentrant mutation inside the guard. If multiple independent authorities/processes can address the same database, either provide a shared fencing protocol or explicitly reject that unsupported deployment. SQLite locking alone does not serialize an external authority.

2. **Durable quota meaning.** Pin an immutable quota ceiling and its exact authority binding to an epoch. Within that epoch, atomically require `consumed + outstanding live holds + candidate <= ceiling` for calls, tokens and micros, with checked arithmetic. Transitioning a hold to consumed must not count it twice. Never reset consumed accounting merely because an owner object is reconstructed, a database connection changes, or the authority returns the same revision/proof again. A changed epoch must be authorized explicitly; stale holds cannot be promoted into it. State whether exposed remaining values are an epoch ceiling or a live balance, and avoid subtracting the same usage twice. The existing binding remains stable during reserve as PLAN requires.

3. **Exact durable identity.** Use versioned, unambiguous encoding for the complete binding, profile, capability flags, all budget fields, request ID and original payload bytes. Credential correlation and owner identity must be persisted and compared at commit. For unsigned ABI integers exceeding SQLite signed range, use a lossless representation or reject them before writing; never narrow or overflow silently. Unique constraints and transaction checks must reject duplicate requests across connections and reconstruction, including previously consumed or expired requests under the documented namespace. Persist the exact proof or proof-correlated authority state and validate it again for the stored full budget.

4. **Atomic failure semantics.** A single transaction changes reservation state, consumed accounting and admission metadata. Failure at any intervening step leaves no partially admitted record or released quota. An uncertain transaction result must never lead to a fresh admission for the same request. Schema mismatch, corruption, storage failure and missing authority deny without deleting or repairing storage. Fresh schema setup must be distinguishable from silently replacing a bad existing database.

5. **Expiry semantics.** Define an injected clock and a persisted monotonic high-water rule so reopening after wall-clock rollback cannot revive a released/expired reservation. Expired holds may stop counting against quota only through a serialized durable transition; stale reservations remain uncommittable. Document whether absolute expiry can be prolonged by time rollback before the prior expiry has ever been observed, including across process restart. If this cannot be ruled out, use a conservative fail-closed rollback policy and state its availability cost.

6. **Data retention and lifecycle.** Raw payload persistence is necessary to prove exact bytes in this slice and must be documented as sensitive local retained data. Specify database name/version and retention limits; do not claim encryption or production retention policy absent implementation. Closing/reopening the component must preserve accounting. No mandatory lifecycle holder is needed if it adds untested production installation claims. The authority must remain separately injected and absent authority must deny.

## Test boundary and evidence required

Run only a named new API26 instrumentation class on fresh synthetic databases using the new schema. Do not run a suite that can include I04, reopen old task.db, migrate old state, invoke HTTP, use real model credentials, or modify PR90. Build-only checks may compile the frozen bridge. Report each command with exact immutable source SHA, execution path/device and result; retain failed/cancelled outcomes.

The minimum meaningful coverage includes:

- Complete field/flag and unsigned-boundary round trips, byte-exact payload mismatch denial, and complete CallBudget preservation after close/reconstruction.
- A deterministic authority race: use latches/barriers to attempt revision or credential revocation while final commit owns the authority guard. Demonstrate a valid linearization (commit first or revocation first), then deny stale admission after revocation. A sequential mutation test alone does not establish this contract.
- Two independently opened SQLite connections racing to reserve the last quota, then competing commit/replay and duplicate request attempts. Assert row state and all three accounting dimensions after reopen. Include consumed usage surviving reconstruction and unchanged-epoch authority refresh.
- Wrong full tuple, owner/credential mismatch, stale policy/profile/budget/quota, missing authority, proof denial and changed proof at commit. A permissive synthetic fixture is not production approval.
- Exact expiry boundary, persisted expired state and wall-clock rollback across reconstruction; no resurrection or counter underflow.
- Injected failure between counter/state/admission writes with durable rollback assertions, plus unsupported schema and corruption denial without destructive repair.

A provider callback synthetic smoke case is useful to demonstrate the component feeds the existing Rust bridge; it must be described as local admission only. No test can claim transport, send/retry safety, credential access, real chat, production owner installation, or old-state compatibility in this scope.

## Remaining integration gates

After implementation, require an independent review of an immutable source SHA and actual scoped test/CI evidence. Production remains blocked on an approved trusted authority, concrete Application/Service installation, production credential-handle integration, and a future transport that enforces the approved full-call limits. This slice must not replace any gate with hardcoded allow.

Review complete; ownership released. This reviewer wrote only this file and is stopped.
