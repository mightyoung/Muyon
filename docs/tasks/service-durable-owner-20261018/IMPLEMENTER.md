# Implementer handoff

Base source: `4b609602f76996ec69e9f51da8bc4261d6a2d94a`.
Tests-first source: `24ea801be0d97d4173741098df802e9a8e637a38` (8 initial tests; production class absent).
Execution location: `/workspace/Muyon` in selected execution environment, 2026-10-18.

## Delivered bounded prerequisite

`DurableServiceHostOwner` implements the existing owner callback source, without ABI, Rust, UI, Application, Service, mode or Dart changes. Its new dedicated SQLite v1 schema stores full binding/profile/capabilities, exact scope, original request and payload bytes, full CallBudget, owner, proof, absolute expiry and reservation state. Versioned length-prefixed UTF-16 preserves strings without lossy UTF-8 normalization; unsigned quota/cost beyond signed SQLite range is rejected. Epoch identity is exact owner + budget revision + quota proof; immutable ceilings are pinned and consumed plus live holds are counted across connections/reconstruction. Successful commit atomically changes held to consumed and inserts admission metadata. No credential values or send operation exist.

`ServiceAdmissionAuthority` is a concrete guard protocol, not an installed policy source. Immutable state replacement and every owner operation share its guard, which remains held through SQLite commit/rollback. Proof and payload review callbacks must be pure/non-reentrant and depend only on immutable trusted facts; the embedding production owner must supply actual conservative full-call proofs. Same-database owner instances must share the same authority object. A retained OS file lease rejects concurrent different authorities or processes. Lock order is owner monitor -> authority -> SQLite. There is no distributed/multiprocess authority support.

Payloads and metadata remain sensitive plaintext local records indefinitely. Expired rows remain as duplicate/replay tombstones; only their quota hold is released. No encryption, pruning, backup or production retention policy is implemented. Persisted high-water time denies admission while clock time is below prior observations; an expiry cannot be resurrected. Unobserved elapsed real time during process downtime cannot be measured; availability may wait for wall time to recover. Existing schema mismatch/corruption fails closed with a non-deleting corruption handler and no upgrade/repair.

## Evidence and limits

Named `DurableServiceHostOwnerTest` contains fresh synthetic SQLite-only tests; no native loading, HTTP, credentials, old application state or I04. Coverage includes reconstruction, exact tuples/bytes/budgets, replay/duplicates, two connections/quota ceiling, proof/revocation, expiry/rollback, transactional trigger failure, schema/corruption/missing authority/overflow, guard-vs-mutation contention and independent-authority rejection.

Local `command -v gradle` and `command -v kotlinc`: no executable; local build/instrumentation RED/GREEN are **NOT_RUN**. No tools/SDK/licenses installed. Root owns scoped CI and actual immutable execution evidence. `git diff --check`: exit 0 before commit. No full suite was run because I04 is explicitly excluded. Initial tests were written and committed before production implementation; no locally observed RED is claimed.

Production is **not installed or complete**. ConfiguredChat remains unavailable: approved real authority, App/Service lifecycle installation, production credential-handle existence source, real Rust prepare integration with this durable component and eventual limit-enforcing transport remain unresolved. No old-state compatibility or migration was attempted. Auto/FullAllow and explicit SyntheticLab remain unchanged. No remote actions were performed by implementer.
