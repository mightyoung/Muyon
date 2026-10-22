# Fixed local-workspace provider handoff — five native methods

Native ProductCore is in **muyon-android-ffi**. Workspace comes exclusively from
opened BusinessStore; calls use its same mutex/connection/BEGIN IMMEDIATE domain.
ReadScope::current validates actual selected project inside each transaction.
Conversation must be the private host's app-issued canonical lowercase UUID.
No account/credential, arbitrary path, old file import or execution ledger binding.

All arguments String except nullable project and archive Vec<u8>/ByteArray; return
Result<String,ProductError>. Four original method signatures remain unchanged:

- local_draft_resolve(conversation, project)
- local_draft_read(conversation, project, namespace_id, draft_id,
  expected_generation, expected_stored_revision)
- **local_draft_prepare_save**(conversation, project, namespace_id, draft_id,
  expected_generation, expected_stored_revision, attempt_id,
  exported_memory_revision, host_editor_revision, archive)
- local_draft_save(conversation, project, namespace_id, draft_id,
  expected_generation, expected_stored_revision, attempt_id,
  exported_memory_revision, archive)
- local_draft_lookup_save(conversation, project, namespace_id, draft_id, attempt_id)

Descriptor: schema=1, owner_kind=local_workspace, namespace_id, workspace_id,
conversation_id, project_id (nullable), draft_id, registry_generation,
stored_revision, lifecycle=editing_only, archive_present, **save_attempt**.
Revisions/generation are canonical decimal strings0..Long.MAX_VALUE; generation>=1.
Read adds status=not_saved|stored, nullable archive_hex/archive_digest. Never saved.

save_attempt is null or the exact persisted SavePreparation pointer, including
terminal committed for callback-loss recovery. Preparation contains schema/owner/
namespace/workspace/conversation/project/draft/generation, attempt_id,
expected_stored_revision, next_stored_revision, exported_memory_revision,
host_editor_revision, archive_digest and state=prepared|committed|not_committed.
This is an explicit durable pointer, not a timestamp/latest-receipt search.

Host protocol (full state machine in SAVE-PREPARATION-INTERFACE.md): capture live
reducer/scope/export/editor and canonical archive from one snapshot; await successful
prepare BEFORE dispatching save. A new attempt requires an exact prepared binding.
Same prepare parameters are idempotent; changed params conflict; unresolved original
refuses new attempts. Archive/CAS/original receipt and committed journal state share
one transaction. Canonical MYBD v1 archive<=32768 bytes; header/version/hash/structure
checked natively, Kotlin restore remains semantic codec boundary. No edit JSON.

Committed save/lookup returns original status=committed_local_storage receipt,
including descriptor storage binding (without save_attempt), expected_stored_revision,
attempt_id, exported_memory_revision, host_editor_revision, archive_digest.
Legacy receipts omit host_editor_revision and remain queryable/idempotent, never
retroactively assigned a preparation or imported historical identity.

Cold start resolve/read discovers save_attempt, then ONLY lookup that original ID.
Lookup committed returns original receipt, never latest head. Lookup uncommitted
atomically fences prepared -> not_committed and returns its preparation fields plus
status=not_committed_local_storage. Thus a queued old save cannot publish later.
This lookup writes only an outcome fence, never an archive or replay. Repeated
terminal lookup is stable; a NEW explicit user save may prepare after a definite
terminal result. Storage errors remain unknown and prohibit a new attempt until
original outcome reconciliation. A missing receipt alone is never a noncommit proof.

Only exact captured live reducer/scope/export/editor can acknowledge a save; a late
receipt or cold recovered receipt must not mark a new/different editor saved. No
saved/created/grant/fee fact is input or inferred. All calls recheck editing_only.

Stable failures: local_draft_identity, local_draft_scope, local_draft_schema,
local_draft_corrupt, local_draft_lifecycle, local_draft_version,
local_draft_archive, local_draft_capacity, local_draft_attempt_conflict,
local_draft_attempt_not_found, local_draft_storage_unknown, local_draft_unavailable,
local_draft_not_prepared, local_draft_pending, local_draft_terminal. No raw DB data.

Capacity:128 drafts,8MiB archive_hex,4096 original receipts,4096 retained preparation
rows. Preparations reserve receipt capacity; no history eviction. Separate strict
v1 journal tables initialize only on explicit prepare. No partial-schema reset.
Checksum is corruption detection, not authentication or adversarial full-DB rollback.

Core owner export stays the existing single `pub mod bot_drafts;` CORE-EXPORT.patch;
this task does not edit core lib.rs. B must regenerate actual fifth UniFFI method.
Host owns Kotlin codec and prepare/discovery/outcome callsites. Keep verified/can_save
false until fresh native/host/Android validation; see SAVE-PREPARATION-REPORT.md.
