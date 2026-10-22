# Durable original save preparation / native owner handoff

Priority source: Host9d2c4119d0c66d1748955cee1d86e63deb7ce16f
SERVICE-BINDING-REPORT.md and parent's confirmation. Interface-first commit
15c65c7c9c1f0af1e73c8092b2de2ac78939eea7 was pushed before implementation.
Exact owned native source argument/JSON/status contract: SAVE-PREPARATION-INTERFACE.md.

## Implemented concrete chain

- New ProductCore.local_draft_prepare_save calls actual core prepare_save under
  existing store mutex, with typed ByteArray/Vec archive and actual open workspace.
  No model dispatcher, arbitrary path, reflection, account/credential or new grant.
- Strict two-table v1 extension shares BusinessStore connection/owner/transaction;
  original schema1 registry/archive/receipt DDL remains unchanged. Explicit prepare
  alone initializes extension; unknown/partial schema refuses without repair/reset.
- Prepare validates canonical archive/version/digest and persists full original
  scope/draft/generation/base/next/export/editor/digest plus one exact pointer.
  No saved fields/archive publication happens at prepare. Exact duplicate prepare
  is idempotent; changed binding rejects; unresolved original blocks new attempt.
- Resolve/read expose that exact current pointer, including committed callback-loss
  recovery. New save refuses an absent preparation. Actual archive/CAS/original
  receipt and journal committed state publish in one transaction. Receipt echoes
  captured host editor revision alongside export revision. Old receipt without
  editor/journal remains queryable, with no fake retroactive original pointer.
- Original lookup returns exact committed receipt, or atomically fences prepared
  state to not_committed_local_storage. A queued old save cannot commit after this
  definite result; if save won the mutex first, lookup returns committed. Storage
  errors remain unknown, never successful. No replay from discovered attempt.
- Pointer replacement only after definite terminal state; original terminal history
  retained. No timestamps/latest-digest search and no cross-scope listing. Journals
  retain at most4096 originals and reserve existing receipt capacity; no eviction.
- Existing unknown/reserved business ledgers, documents, core lib.rs, Service,
  Runtime, shell and generated bindings remain untouched. Only new private FFI API,
  core provider, synthetic tests and task docs are source-owner changes.

## Host/B next exact integration

The new fifth method takes LocalDraftPrepareRequest, with named exported_memory_revision,
host_editor_revision and archive fields (see the complete exact Rust record). This
supersedes the queued098d positional fifth signature before its first accepted B
generation. Keep four existing signatures. Host must capture reducer instance/scope/export/editor
from the SAME snapshot, await successful native prepare before dispatching save, and
retain exact original on unknown. Cold resolve obtains save_attempt then only lookup
that ID. not_committed_local_storage permits a NEW explicit user save; committed
acknowledges its captured snapshot only. A different editor/reducer is never marked
saved. New JSON fields require Host's strict codec update before enabling verified.

B owns sole core export and regeneration of actual fifth UniFFI method/bindings on
its fixed combination. This task has NOT edited generated Kotlin or adopted all
of B's independent branches. Host owner must wire actual prepare/discovery/outcome
consumer using the fixed signature; this native source is a real callsite, not a
claim that Kotlin/Android consumer acceptance is complete. verified stays false.

## Tests, review, actual limits

26 Rust provider tests in source (prior19 adapted to required prepare-before-save,
7 added cold recovery/exact binding/fencing/legacy/fault regressions), plus2 FFI
native consumer tests. Raw commit calls test unprepared refusal and late-save fence;
not every save is hidden behind a preparation helper. Legacy fixture explicitly
seeds a receipt without journal/editor, queries before and after extension creation.
Faults target receipt insertion, pointer publication and terminal journal update.
No original assertions/failed evidence were removed to claim a pass.

Test-first attempt is preserved at evidence/preparation-test-first.log: shell127,
cargo absent. Repaired-source Rust tests/Clippy/fmt/UniFFI, Kotlin host adaptation and
Android are NOT_RUN here. Prior original-source19/core202 and B's combination405
passing results do not apply to this new state machine. Original14 RED and later
results remain preserved as historical evidence. No software installed.

Source-extracted SQL executes all five exact DDL and every source SQL statement,
actual persisted restart pointer/export/editor, no archive at prepare, conditional
terminal fence, injected terminal-failure atomic rollback, exact committed/original
history and bounded corrupt payloads. PASS in evidence/preparation-sql.log. Existing
archive projection/transaction SQL regressions also PASS in preparation-regression-sql.log.
These are SQL checks ONLY; they do not execute Rust branch/serde/control flow.

Independent read-only review found two low issues: pointer error flattening and
missing explicit legacy fixture. Both repaired/rechecked; no outstanding static
finding. Reviewer also verified SQL transition/rollback. Static/SQL review is not
provider/FFI acceptance. Overall HOLD pending B's actual new-source Rust+bindings
and Host's actual consumer/Android checks.

Reader work remains the earlier source-inspection preplan, with a real crate-private
atomic ReadText hook gap requiring core-owner coordination. No PFD/engine/annotation
write is claimed; annotations remain unavailable without their original intent journal.
