# Durable original save preparation — interface first

Requirement source: host9d2c4119d0c66d1748955cee1d86e63deb7ce16f,
SERVICE-BINDING-REPORT.md. This interface extends the existing local_workspace
provider; it is not an account, execution journal, grant or second store.

## Fixed native signature / host sequence

New private ProductCore method (String arguments except optional project/ByteArray):

```
local_draft_prepare_save(conversation, project, namespace_id, draft_id,
  expected_generation, expected_stored_revision, attempt_id,
  exported_memory_revision, host_editor_revision, archive: Vec<u8>) -> Result<String, ProductError>
```

Four existing method signatures remain unchanged. prepare receives exactly the
snapshot archive that host will send to existing local_draft_save; validates header,
next stored revision, digest and bounds; durably commits preparation BEFORE save
is dispatched. The preparation stores no archive or authority token, only bounded
original identity/binding/revisions/digest. It does not mark the editor saved.

Existing resolve/read add `save_attempt: null | SavePreparation`. It is the exact
persistent pointer for this registered draft/scope, including terminal committed
so callback loss/process death can discover it. Never enumerate other scopes,
search latest-by-time/digest, or recover an attempt from a guessed receipt.
prepare returns SavePreparation directly, idempotently for the exact same attempt
and all parameters. New attempt refuses while prior state=prepared. Old attempt
with changed base/export/editor/digest refuses even after completion.

SavePreparation fields: schema=1, owner_kind=local_workspace, namespace_id,
workspace_id, conversation_id, project_id, draft_id, registry_generation,
attempt_id, expected_stored_revision, next_stored_revision,
exported_memory_revision, host_editor_revision, archive_digest,
state=prepared|committed|not_committed. All revisions canonical decimal strings
0..Long.MAX_VALUE, registry_generation>=1. No saved flag.

Existing save now REQUIRES an exact durable prepared row for every NEW attempt.
Legacy committed receipts remain lookup/idempotently queryable; no implicit prepare
is done by save. All scope/project/lifecycle/CAS and preparation fields are checked
under the same BusinessStore transaction. Archive/CAS/original receipt and journal
state=committed publish atomically. New committed receipts additionally echo
host_editor_revision; old receipts omit it. This binds the original host snapshot
without acknowledging a different/new reducer instance.

## Restart and exact outcome lookup

Cold start: resolve -> exact save_attempt -> existing local_draft_lookup_save with
that exact original ID. NEVER dispatch/save/replay from the discovered pointer.

- If already committed, returns the original committed_local_storage receipt,
  including captured export/editor revision. No latest-head substitution.
- If prepared but uncommitted, lookup transaction verifies no original receipt and
  atomically changes that exact attempt to not_committed before returning
  status=not_committed_local_storage + its preparation fields. This is an explicit
  fence: any already-queued/later save of that ID now refuses. If save won the store
  lock first, lookup instead observes the committed receipt. Thus a missing receipt
  alone is never presented as proof of noncommit while a save could still publish.
- Repeated not_committed lookup is stable and never resaves. A new explicit USER save
  may prepare a new attempt; the terminal original history remains queryable.
- Storage/commit/cleanup errors remain unknown, requiring exact lookup; no new attempt
  until a definite terminal result. Project revocation/corruption/absence fails closed.

## Persistence / compatibility / limits

Existing schema1 registry/archive/receipt tables and records remain byte-compatible.
New dedicated `local_bot_save_attempts_v1` and `local_bot_save_pointer_v1` tables have
strict DDL identity, created atomically ONLY at explicit prepare. They deliberately
avoid the existing `local_bot_draft*` schema prefix. No partial-schema reset or guessed
migration. resolve/read expose null when neither new table exists, reject partial or
unknown schema. Every journal row binds actual namespace/draft and structured scope.
One pointer per draft; retained original attempts bounded4096 (no eviction), and
preparations reserve the existing receipt capacity. No SQL touches old business
unknowns/reservations. Core lib.rs remains B's sole export; no Service/Runtime edit.

Host upgrade must add prepare-before-save and parse save_attempt/original outcome.
Until accepted native signatures/bindings/host changes and real Rust/Android checks
pass, verified remains false. This document was published interface-first at15c65c7c9c1f0af1e73c8092b2de2ac78939eea7;
implementation follows on the same owner branch. Source delivery is not runtime
acceptance. New failures are local_draft_not_prepared, local_draft_pending and
local_draft_terminal; existing stable failures remain. Core groups export/editor
arguments in SaveRevisions; the native signature above exposes them separately.
