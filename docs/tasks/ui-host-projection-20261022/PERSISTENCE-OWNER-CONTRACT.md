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
