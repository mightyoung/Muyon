# Persistent draft owner gate — blocked production mapping

Starting source a1752fc7f3a0471413c5afd2a32bf152078b21fd.

Verified facts:
- Service supplies fixed local-workspace and app-private filesDir/muyon-product-v2.
- BusinessStore stores and checks workspace in SQLite meta; projects have workspace,
  revision and deletion status. These are actual persistent native facts.
- ChatScreen stores conversation UUID in product-chat-state SharedPreferences,
  indexed by UI conversationKey; this key is not project-specific and is not an
  account/workspace/conversation ownership registry. LocalShellDrafts similarly
  stores display text by caller-provided conversation/project keys only.
- Service session, epoch and ProductScopeRegistry generation are ephemeral leases.
  No stable account-owner identity or account/workspace/conversation/project join
  was found in the product source. RunScope.current validates IDs and project read
  scope, but does not establish persistent conversation/account ownership.

Therefore no production save/restore may use these leases, display keys, literal
local-workspace, draft UUID, Android UID alone or a newly invented installation UUID
as a substitute for a verified persistent account owner. Cross-account restore is
unavailable. Existing setup can_save=false/saved=false remains accurate.

Required future host seam: a trusted resolver, re-run at each save/load, must return
verified stable accountId/workspaceId/conversationId/projectId from the current
persistent owner registry, checking current project visibility/deletion. It must
not accept a payload's self-declared account or restore old grants. Current resolver
is unavailable, not an implicit single-account permission grant.

Independent store contract may be built/tested with SYNTHETIC owners only:
- app-private namespace provided by host, separate from catalog, credentials and
  native billing files; no production storage root is opened while owner is blocked;
- explicit stable-owner tuple and actual draft UUID, schema1/editRevision and
  storedRevision, minimal edit fields only; no lease/token/intent/grant/fees;
- OS file lock + exact expected stored revision, temp fsync + atomic rename +
  directory fsync, honest confirmed/unknown/rejected outcome; exact version/digest
  recovery, never latest-as-original receipt;
- strict bounded parsing/schema/owner/integrity validation. No corrupt-file reset
  or migration guess. Old schema stays unavailable; errors never saved=true.

Canonical Bot reducer API at remote6b8f6ab0eacc2921ec23fa7a7862a4df10af47aa was
inspected; safe export/restore interface was not yet present there. Do not reflect,
copy private state or invent a serializable creation receipt. A storage frame does
not implement the reducer adapter; wait for the owner's fixed reviewed API SHA.

Implementation plan: build the storage frame with a minimal edit record and synthetic
failure/concurrency tests; keep production endpoints unavailable until BOTH the real
owner resolver and canonical reducer export/restore adapter are present. This is
partial infrastructure, not actual product persistent save/restore completion.

## Fixed-codec update (supersedes the proposed minimal edit frame above)

Parent released Bot branch53b9b597e190db6b6619a18e8746f2985f488fbc and exact
interface49ad2a8dfe7fe65bad600d985f9e1631252191da. The latter was adopted through
ordinary dependency merge22fda0c795cbcc01d9a3562c64b0a28073e541f4; canonical source
was not locally edited. Storage now accepts ONLY the fixed exportDraft archive and
validates it through explicit restoreDraft; there is no host-specific edit JSON,
step, memory revision, token or creation serialization. Outer JSON carries only
stable owner tuple, actual persistent draft UUID, schema/storedRevision, base64
canonical archive and corruption digest. SHA256 is not authentication/encryption.

Production mapping remains BLOCKED: no verified persistent account/namespace/
conversation-project join, rollback anchor or unresolved creation/stop record guard
exists. Runtime returns setup_persistent_owner_unavailable for save/restore and
persistent_owner_status/persistence_status=unavailable, with saved/can_save=false.
There is no production HostDraftStore callsite and no actual app-private root opened.

Store requires an already-existing trusted durable root; host must durably create
its namespace including parent-directory fsync. It does not create missing roots.
Read/recover take nullable minimumStoredRevision: null means no prior trusted anchor;
non-null including0 refuses missing/lower records. The floor must come from trusted
persistent host state, never a value inferred from the potentially rolled-back file.
The primitive cannot prevent rollback of its entire namespace/anchor together without
that external trusted source; do not claim checksum or app UID solves this gap.

save(owner,id,expectedStoredRevision,exportedMemoryRevision,archive) returns a local
storage receipt for exactly the export memory revision, stored revision and digest.
The memory revision is returned only, never persisted. Host must retain the original
reducer instance/live callback scope and compare current revision before displaying
saved; a late receipt cannot acknowledge newer edits. read/recover after restart
confirms storage only, never marks a new reducer instance saved or restores grants.
The stable record UUID is supplied explicitly as newDraftId only after verified
owner/record checks. Codec restores NAME/revision0/no grants/NOT_REQUESTED; that is
not permission to clear an old unknown creation: host must check the durable original
creation/stop ledger before restore and before any future create. Missing ledger
is a blocker, not an empty ledger. None of these absent production guards is invented.
