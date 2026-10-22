# Local-workspace provider — inspected facts and exact core handoff

Read-only source inspection on6f35eb837d88d15f50c073d7e541408e9159f758.
Decision: implement a NEW explicitly tagged local_workspace draft registry/archive
inside the existing BusinessStore SQLite transaction. No account identity or new
permission/credential is needed. Registering a new local record is authorized local
product development, not a claim that an old account/conversation join already exists.
The prior account-oriented blocked-frame report must not be interpreted as requiring
login/cloud secrets for local-only save. can_save stays false only until this actual
provider/bridge is implemented and verified.

## Existing real facts (inspected code)

- apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agentipc/ProductService.kt:28-29:
  epoch is a fresh UUID; workspace literal is local-workspace. open():130-134 uses
  Context.filesDir/muyon-product-v2 and ProductCore.open. Client session/generation
  remain current-call leases, never persistent owner identity.
- crates/muyon-android-ffi/src/lib.rs:86-125: ProductCore.open derives business-v2.sqlite
  below trusted absolute filesDir root, opens BusinessStore, acquires exclusive owner
  and reconciles native state before publishing. health():134 reports that actual
  opened workspace and protocol1; it is not a stable installation/account ID.
- crates/muyon-core/src/business.rs:159-179: initializes workspace in durable meta
  under WAL/synchronous FULL transaction. open_existing():185-219 checks schema and
  exact workspace; meta must retain exactly its two existing keys. Do not add a
  namespace key to this strict meta table. Additional dedicated tables can be checked
  by their own module; existing required-table validation does not reject extra tables.
- business.rs:670-681 project(id) queries id+current workspace and returns revision/
  deleted. crates/muyon-core/src/agent/mod.rs:121-133 ReadScope::current rejects a
  deleted/missing selected project, derives actual workspace/owner epoch from store.
  Use this check in each new transaction, not a paginated UI project list.
- agent/workflow.rs:74-94 RunScope::current verifies session/conversation IDs and
  current project ReadScope. Its scope key is persistent workspace/conversation/
  project; session/epoch are separately used for live control. It does not register
  a persistent Bot draft owner. Its runs/events/skills schema at252-258 and
  cancel_requested handling around704-720 are task-run facts, not Bot creation.
- business.rs:21 intents are generic business command pending/unknown/committed/
  rejected/cancelled with command+binding+receipt. AgentOwner requests at owner.rs:185
  have charged/default0 and cancelled; cancel_trusted():561-568 may preserve unknown.
  Neither is a Bot draft create/stop lifecycle keyed to a draft registry record.
  No agent_create/bot_create/pending-creation producer was found in core/FFI.
- AgentCatalog.kt:94-95 immediately commits LOCAL organization records to private
  preferences; it does not supply draft-scoped durable creation intent or execution
  grant. Do not infer a provider record or clear unknown from catalog presence.
- ChatScreen.kt:45-46 issues/saves native conversation UUID by UI key; project is
  separate. New registry may register the current app-issued UUID+selected project
  as a NEW join; do not infer old project/account history or import old files.
- AndroidManifest.xml:3-6: app backup disabled, private :core Service unexported.
  res/xml/data_extraction_rules.xml excludes app files/db/preferences from backup/
  transfer. No stable install/account ID exists. New registry namespace UUID would
  be an actual newly persisted local namespace identity, NOT an account/OS identity.

## Chosen minimal persistence design

Prefer one SQLite transaction for registry, archive, monotonic stored revision and
exact local-save receipt; do not force the earlier optional file primitive into a
two-store protocol. It remains tested standalone infrastructure, unused by production.
Do not use its legacy accountId model as the new local owner type.

New core module: crates/muyon-core/src/bot_drafts.rs (unique writer assigned by parent).
Module export only through existing crates/muyon-core/src/lib.rs owner.
Private bridge only through existing crates/muyon-android-ffi/src/lib.rs owner.
Tests: crates/muyon-core/tests/bot_drafts.rs and private facade tests owned accordingly.
Kotlin Runtime/Service and exclusive adapter tests remain this thread's files.
No ChatScreen/MainActivity edits here. Parent coordinates fixed Rust source/FFI SHA.

Own strict-schema tables under BusinessStore.database(), using existing owner lock:

1. local_bot_draft_meta: schema1, actual workspace, generated namespace UUID. Not an
   extra row in BusinessStore.meta. Initialize only on explicit first resolve/create;
   unknown schema/partial existing tables refuse, no drop/reset or legacy import.
2. local_bot_drafts: actual draft UUID, workspace, nullable project, app-issued native
   conversation UUID, unique structured scope key, persistent record generation,
   stored_revision, lifecycle=editing_only, archive bytes/encoding+digest or absent.
3. local_bot_draft_saves: original local attempt UUID, namespace/draft/scope binding,
   expected/new stored revisions, original exportedMemoryRevision, content digest,
   exact committed local-storage receipt. Unique attempt ID; changed params reject.

namespace and draft UUIDs are newly minted real local records in the registration
transaction. No account_id, credential, session or runtime generation is persisted as
owner. Record generation is an actual persistent CAS counter born in that transaction,
not an asserted account identity. First record: storedRevision0/archive absent/
editing_only. No archive means not saved. Exact stable UUID is supplied to canonical
restore newDraftId only after registry scope/namespace/lifecycle checks.

Use canonical exportDraft/restoreDraft from reviewed49ad2a8d. Store opaque canonical
archive <=32768 bytes, NOT another JSON edit serializer. SQLite wrapper currently
binds text; a strictly bounded archive_hex TEXT (<=65536 chars) avoids new SQLite
BLOB API/dependency. SHA256 is only corruption detection. Kotlin is the canonical
semantic codec boundary; no payload bytes may come directly from model/UI JSON.
Rust still checks byte limit, fixed archive header/checksum/version and expected
stored revision before atomic save, and never interprets archive as authority.

Limits proposed for core owner: <=128 registered drafts per workspace, <=8MiB total
encoded archive data, <=4096 local-save receipts. Refuse capacity before mutation;
query/read remain possible. Do not delete unresolved or original receipts to make
room. Exact limits are provider schema contract, to be finalized with its owner.

## Exact proposed private facade methods

All workspace is derived from the opened ProductCore/BusinessStore; none accepts
caller account/workspace. Return existing-style bounded JSON String. Revisions and
persistent generation use decimal strings bounded to signedLong MAX for canonical
Kotlin codec interoperability. Byte archive input is typed Vec<u8>/ByteArray.
These method names/contracts are PROPOSED until the core owner publishes the fixed API.

- local_draft_resolve(conversation: String, project: Option<String>) -> String:
  explicit resolve-or-create registry transaction, current project check, canonical
  app-issued conversation UUID validation; returns descriptor below. Does not save
  fields or create/start an Agent. Repeated scope resolves retain actual draft UUID.
- local_draft_read(conversation, project, namespace_id, draft_id,
  expected_generation, expected_stored_revision) -> String:
  recheck exact registry scope, current project and editing_only; exact version read,
  not latest substitution. Returns descriptor plus archive_hex/digest if saved;
  absent archive is not_saved. Deleted project or other lifecycle refuses.
- local_draft_save(conversation, project, namespace_id, draft_id,
  expected_generation, expected_stored_revision, attempt_id,
  exported_memory_revision, archive: Vec<u8>) -> String:
  recheck scope/project/lifecycle/CAS/size/capacity; next=checked_add1 with MAX refusal;
  canonical archive stored revision must equal next. Atomically persist archive,
  new revision and exact original-attempt receipt in the SAME SQLite transaction.
  Same attempt+same binding returns original receipt without another write; changed
  attempt binding rejects. Receipt binds exported memory revision+stored revision+
  original digest. Never accept externally supplied saved/created/grant facts.
- local_draft_lookup_save(conversation, project, namespace_id, draft_id,
  attempt_id) -> String:
  original local-save receipt only; never fetch latest as original, auto-repeat the
  save, adopt foreign lifecycle or inspect/retry old remote unknown requests.

Descriptor schema1: owner_kind=local_workspace, namespace_id, workspace_id,
conversation_id, project_id, draft_id, registry_generation, stored_revision,
lifecycle=editing_only, archive_present. Save receipt additionally echoes original
attempt_id/exported_memory_revision/archive_digest/new stored_revision and committed
local-storage status. No business intent, execution receipt, actual fee or Agent ID.
Failures have stable scope/version/lifecycle/schema/capacity codes, no raw data.
Core errors/timeout are unavailable or unknown until original attempt lookup; never
successful save on exception. Existing native business and two remote unknowns are
outside this registry and are never relabelled, settled or cleared.

## Kotlin adaptation after exact bridge handoff

ProductService derives workspace/native core and live Binder session/project scope,
then calls only the fixed private facade. Runtime persistence port remains separate
from transport/provider config. Explicit open/resolve obtains descriptor, not an
invented draft ID; safe restore loads only registered exact record, validates codec,
passes current live scope and stable record UUID, resets privileges as canonical
codec requires. CAS rejects stale local editor, record generation or stored version.
Save captures canonical memory revision and local editor revision from SAME snapshot,
exports next stored version, and generates one original LOCAL save attempt UUID.
On callback compare still-live reducer instance, scope, draft ID and revisions;
a late receipt acknowledges only its export, never current newer editing. Original
unknown local-save query is distinct from old remote execution lookup. No auto retry.

Only NEW registry-managed records are enabled. Legacy account-field files/old unknown
origins are never selected, guessed or auto-imported. Registry lifecycle is truthfully
editing_only because this new domain has no create/run transition. Future formal
create/run MUST first add durable pending/stop lifecycle registration in that same
domain before any side effect; restore/export/save then reject those states. Missing
legacy global Bot create ledger does not block new editing_only local drafts, and
archive NOT_REQUESTED never clears another original pending/unknown creation.

No adversarial OS/full-app rollback guarantee: ordinary local consistency uses the
single authoritative transactional registry+archive+receipt store. No cloud secret,
account permission or new credential is required or proposed.

## Required test boundaries

Rust: restart/same scope stability; wrong workspace/project/namespace/draft; deleted
project; null project distinction; record-generation/version conflict; duplicate and
changed attempt; transaction failure before/after commit; exact receipt after callback
loss; archive/capacity/schema/overflow corruption; lifecycle !=editing_only refuses;
old unknown remote ledgers unchanged. Kotlin: real descriptor consumption, canonical
archive restore edits/locks with no grants, stale local scope/request and late save
receipts, actual saved only from exact confirmed export. Android remains separately
unverified until toolchain runs. Current can_save=false remains until fixed core
provider/bridge and these adapters pass; no permanent missing-account blocker.
