# Service durable admission owner — bounded slice

Base: 4b609602f76996ec69e9f51da8bc4261d6a2d94a. Root is sole integrator.

## Binding scope and ruling

Implement the platform-owned durable admission component behind the existing Rust/UniFFI callback, using Android API26 SQLite. It implements ServiceHostOwnerSource and holds a separately injected trusted authority. No production approved authority exists, so this slice must not invent one or change the explicit SyntheticLab UI mode. Application/Service production mode selection remains uninstalled; provide a lifecycle holder/factory only if it materially improves this tested component. This bounded slice is a prerequisite, not production completion.

The existing Rust ServiceProviderBridge remains responsible for generic profile, wire payload and capability validation. No Dart, UI, transport, credentials, or generated ABI changes.

## Task 1

Implement a durable ServiceHostOwnerSource using a dedicated new database name/schema, separate from old task.db and the existing service database. The trusted authority supplies current scope/provider/existence and explicit payload review plus conservative full-call budget proof for exactly the binding/payload/budget. Never use a hardcoded allow, inferred permission or arbitrary payload-size token estimate. Authority and ledger operations must have one documented synchronization/linearization contract: no revision/existence changes between final authority check and commit can slip through. Do not hold a sampled approval as permanently current.

Store exact full admission binding and full CallBudget, original request/payload bytes, owner identity, expiry and reservation state. Canonical encoding must capture every field without lossy hashing/normalization. Reserve atomically counts outstanding holds and consumed admissions under a durable quota epoch; no concurrent overspend; do not silently mutate exposed current budget at reserve. Commit rechecks exact authority, credential correlation and existence, exact full reservation tuple and stored budget/proof under a DB transaction, consumes once and creates metadata admission atomically. Deny stale policy/profile/budget/quota/revocation, expiry, replay, duplicate request and overflow. Keep conservative consumed accounting; no send, retry or resend. Clean expired holds conservatively and prevent wall-clock rollback from resurrecting them. Fail closed for SQLite/corruption/schema errors, never repair/delete existing storage silently. Define whether raw payloads persist and document privacy/retention limits.

Tests: named new Android instrumentation class only, synthetic non-network fixtures, new schema fresh synthetic databases only. Cover full tuple mapping, exact bytes, complete CallBudget persistence across object close/reconstruction, one-shot commit/replay/duplicate, two connections contention and quota, authority mutation/revocation/credential loss, exact budget proof denial, expiry, rollback/failure atomicity, missing authority and schema/corruption fail closed. Tests must not run I04 or any old state. Preserve failed/RED evidence and exact source SHA/location. No false production claims.

Ownership: implementer owns new production and instrumentation files for this component, and IMPLEMENTER.md in this task directory. Existing ServiceHostBindings.kt may be changed only if needed for a narrow authority interface; existing Application, Service, UI and Rust sources are frozen unless root explicitly revises scope. No workflow/remote operations by implementer. Commit source changes and report immutable SHA, commands/results, limitations; then stop writes and release ownership.

## Global constraints

I04 old script task.db→HTTP→original-state reopen was platform denied possible cybersecurity risk. Never execute/retry/rewrite/split or delegate it, or run suites indirectly containing it. PR86 and dependents remain HOLD. No main/develop edits, merge, force push, branch deletion, deploy, paid services, credential reading/configuration, real model calls, license acceptance, PR90 changes or Dart retries. UI frozen; Rust core/Kotlin API26; default Auto/FullAllow semantics unchanged. Stop a denied action immediately, report exact target/reason/status without alternate route.

## Review and validation

Independent design review before implementation, independent immutable code review after. Root owns CI workflows, push/Draft PR and final evidence. Scoped Compose build and named API26 instrumentation only; audit workflow call graph before dispatch. All reports name exact source SHA and execution location. Keep old failed/cancelled outcomes.
