# Fixed provider handoff

Native facade is `ProductCore` in **muyon-android-ffi**, not a new crate.
Workspace comes exclusively from opened BusinessStore. All calls use the same
ProductCore state mutex and BEGIN IMMEDIATE transaction. Project deletion/visibility
is checked using ReadScope::current inside that transaction; session/epoch is not a
persistent owner. Host must supply app-issued canonical lowercase UUID conversation.
Only resolve explicitly creates a NEW namespace/registry. No legacy file import.

Methods (String arguments, optional project String; all return Result<String,ProductError>):

- local_draft_resolve(conversation, project)
- local_draft_read(conversation, project, namespace_id, draft_id,
  expected_generation, expected_stored_revision)
- local_draft_save(conversation, project, namespace_id, draft_id,
  expected_generation, expected_stored_revision, attempt_id,
  exported_memory_revision, archive: Vec<u8>/ByteArray)
- local_draft_lookup_save(conversation, project, namespace_id, draft_id, attempt_id)

Success JSON descriptor: schema=1, owner_kind=local_workspace, namespace_id,
workspace_id, conversation_id, project_id (nullable), draft_id,
registry_generation, stored_revision, lifecycle=editing_only, archive_present.
Revisions/generation are decimal strings 0..Long.MAX_VALUE; generation starts at1.
Read adds status=not_saved/stored, archive_hex and archive_digest (nullable).
It never asserts saved on a new reducer instance. Hex bytes are exactly canonical
MYBD schema1 exportDraft (<=32768 bytes), checked header/revision/hash/structure.
Kotlin restoreDraft remains the semantic codec boundary. No alternative edit JSON.

Save receipt descriptor adds expected_stored_revision, attempt_id,
exported_memory_revision, archive_digest, status=committed_local_storage.
It is persisted atomically and returned exactly for original lookup, including after
newer saves. Same attempt plus same binding/export/digest is idempotent, otherwise
local_draft_attempt_conflict. New attempt with stale CAS fails local_draft_version.
Original lookup has no write/retry behavior. Never use latest read as original receipt.
Any storage/commit error is local_draft_storage_unknown: original attempt lookup only.
Missing attempt returns local_draft_attempt_not_found, never saved=true.
Host keeps original attempt ID through unknown; receipt export revision must match
captured reducer instance + live scope + editor revision before displaying saved.
A late callback cannot acknowledge newer edits. No saved/created/grant fact is input.

Stable failure codes: local_draft_identity, local_draft_scope, local_draft_schema,
local_draft_corrupt, local_draft_lifecycle, local_draft_version,
local_draft_archive, local_draft_capacity, local_draft_attempt_conflict,
local_draft_attempt_not_found, local_draft_storage_unknown, local_draft_unavailable.
No raw DB error/data is returned. Lifecycle other than editing_only refuses all calls.

Capacity:128 drafts,4096 retained original receipts,8MiB total archive_hex.
No receipt eviction; repeated original lookup/read remains possible at capacity.
Checksum is corruption detection; no authentication or full-DB rollback prevention.

Core owner action required (this task does NOT edit core lib.rs): apply
CORE-EXPORT.patch to add `pub mod bot_drafts;`. This export must accompany FFI when
integrating the task branch. No documents/Kotlin/engine changes are required here.
Do not enable UI can_save until this native dependency and host canonical adapters
are compiled/tested on the parent integration branch.
