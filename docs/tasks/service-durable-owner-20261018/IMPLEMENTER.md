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

## Independent-review repair wave

Reviewed `CODE-REVIEW-bf244606.md` against source and repaired both Important paths. Regression tests were committed first at `a8eacbcbb1858b0108f65a5965c967edb520a1d8`; corrected Android-metadata fixture isolation plus callback smoke at `3373004bd182798b4a9aeaa80d9f2886074e6d6f`. Local behavioral RED remains NOT_RUN (no Gradle/Kotlin); root owns actual CI runs and preservation of their failures.

I1: inside the same authority guard, clock high-water and expiry cleanup now commit in their own SQLite transaction before fallible reservation/admission work begins. The admission transaction still atomically consumes and inserts metadata. A duplicate-request failure can no longer roll back the preceding successful clock observation. New test observes expiry 111 through a failed duplicate attempt, closes/reconstructs at 105, and checks denial plus persisted high-water/expired state. The original failed-commit trigger test continues to check independent consumption/metadata rollback.

I2: schema initialization and validation share one exact DDL manifest. Existing files must match all supported tables, definitions and implicit unique/primary-key indexes; extra objects or changed constraints deny. Standard Android locale metadata is separately recognized. No schema is upgraded/repaired. New malformed-v1 fixture drops request uniqueness while retaining expected column names and version; owner unavailability and unchanged original bytes are asserted.

The named instrumentation class now has 17 tests, additionally covering exact expiry 110, each independent quota dimension with consumed-ledger reconstruction and same-epoch authority refresh, two-connection competing commit/replay/duplicate attempts, and `ServiceHostBindings.callback(real durable owner)` metadata/review/reserve/commit/replay smoke. This is generated Kotlin callback compatibility only; it does not execute Rust prepare or prove real chat.

Local repair checks at `/workspace/Muyon`: `git diff --check` exit 0; host Python standard-library SQLite in-memory DDL/implicit-index manifest comparison PASS (structural check only, not Android/Kotlin execution). Build/instrumentation remain NOT_RUN locally. Dedicated OS subprocess lease execution, maximum signed-value/surrogate round trips, and exhaustive binding mutation matrix remain unexecuted; no extra harness was installed. All original production integration gates and I04 exclusions above remain unchanged.
