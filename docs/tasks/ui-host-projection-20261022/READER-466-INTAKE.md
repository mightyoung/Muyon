# Reader FFI466 intake — raw source contract is not a display lease

After completing fifth Service wiring7c85bc8f85779be0e15c6486699d1d39d3cc2a74,
fetched/read466424b13400c3f88b0cfec815ce3450c41b3cff INTERFACE/HANDOFF and actual
crates/muyon-android-ffi/src/document_bridge.rs. No source merge, generated binding,
PFD, provider, grant, native read or real user file operation is performed here.
FFI author's12 tests/generation were NOT_RUN; parent acceptance/B binding pending.

## Exact usable facts and open joins

DocumentReaderScope(service_session,generation,project) is a live host lease, not
persistent owner/account identity. Current native scope() requires NONNULL selected
project; null/blank project is DOCUMENT_SCOPE_MISMATCH, despite typed Option.
Service has actual clients Binder->session and Runtime owns ProductScopeRegistry.
Future reader scope must be joined to the actual selected Runtime generation and
project at every call, not copied unchecked from UI/model JSON. Scope changes,
releaseClient and shutdown must invalidate native reader/evidence owners and drop
late callbacks before output. No second mutable uncoordinated scope truth.

DocumentAccessRequest adds exact canonical DocumentRef JSON + already-issued
persistent grant_id/grant_generation. access() derives workspace/owner_epoch from
opened BusinessStore and verifies reference project/workspace. Generation is core
unsigned decimal Revision, not Kotlin Long. Grant references are NOT authorization
by themselves; persisted core grant/operation/head/active/epoch/expiry must validate.

Concrete current production join gap: no Android source issues DocumentAccess or
maps an actual user-selected registered DocumentRef to an issued grant. Core table
`document_grants` contains document_json, grant_id/generation/owner_epoch/permissions/
expiry/active, not a Binder principal assignment. Existing Service knows Binder
sessions and local-workspace, not that document grant assignment. Existing
BusinessStore::issue_document_grant_trusted explicitly requires authentic current
policy/user authorization and fresh owner epoch/next generation. This Host must NOT
scan latest grants, reuse previous process epoch, equate local-workspace with account
ACL, create a fake grant or silently import a research attachment to fill that gap.

The policy/core owner needs to supply an explicit trusted selection->real grant/ref
join under existing local user policy. That is ordinary implementable local domain
work, not a demand for new account credentials; its exact issuance policy must be
owned/reviewed rather than inferred from a UUID. No new issuer permission is added
by this intake. Proposed Host receives that trusted result privately and never
accepts grant fields/authority booleans from model or UI content.

Native exposes exact-reference metadata/annotations, NOT authorized project-wide
listing. Existing schema document registry/head alone is not authority to enumerate
all grants/documents. Shell list/select flow needs a real authorized list/selection
provider or an existing trusted exact reference; do not fabricate titles/IDs/revisions.

## Exact byte/session boundary — parent core follow-up must land first

466 open explicitly returns display_lease=false, safety_status=not_assessed,
expires_at_ms=null with expiry_status=enforced_by_core_not_exposed. Null does NOT
mean infinite/no expiry; format metadata does NOT mean actual-byte safety assessed.
No fake deadline or renderer capability may be inferred from it.

DocumentReadChunkResult is offset unsigned-decimal String, ByteArray bytes, eof,
session_active. Actual chunk() removes native read mapping at successful EOF and
returns session_active=false. check thereafter is invalidated. Therefore a complete
copy/digest match cannot be converted into accessActive=true or a newly delivered
PFD under that old ID. No silent reopen/latest-head substitution is permitted.

Needed canonical core contract (owner is already implementing): bounded display-
retaining mode on the SAME exact immutable source/pin/grant/generation through EOF,
with current authorization checks, real expiry, explicit close and cleanup failure
semantics. Exact names/signatures must come from core+FFI owner, then B must compile,
test and generate real record bindings. This Host will not guess a Kotlin fifth-
style ABI or construct a different read lease to impersonate that source identity.
Do not widen current15s idle/30s absolute bounds or remove integrity checks. 16MiB
admission is not a completion promise; snapshot64MiB is payload budget, not RSS.
Explicit check hashes whole source; do not call it redundantly for each chunk.

Only after that release may owned host adapters construct a fresh seekable
MODE_READ_ONLY PFD from bounded/digest-verified bytes with real display lease tail
check, typed private Bundle transport, exact session/ref/epoch callback fencing,
owner disposal/expiry/idle invalidation publication, and late descriptor close.
Controlled content URI is descriptive metadata, never ambient path authority.
Android tooling/device checks still mandatory; no SDK workaround or fake FD fixture
is production implementation. Actual byte-format/safety and engine support require
separate acceptance, not extension/format enum or cached research-file substitution.

## Read-only annotations and actual UI seam

466 metadata/annotations expose annotation_editing=false and no save endpoint.
Our current B-derived DocumentReaderSnapshot/Host UI source still lacks an explicit
annotation-edit capability property (snapshot: ref/uri/epoch/accessActive/annotations;
host: openCurrent/isCurrent/saveSidecar). Reader component owner must release a real
read-only gate before Host factory connects, preserving actual annotation rows while
disabling edit/save controls. Do not attach an enabled dummy save returning Rejected
or drop annotations to fake read-only mode. Original annotation intent/immutable old
anchor/CAS/receipt/reconciliation remains separate; existing revision CAS is not it.

## Owned next implementation files and fixed input request

Exclusive paths previously assigned remain product/documents/host/
{DocumentHostLease,DocumentDescriptorBroker,ProductDocumentHost}.kt and
product/agentipc/ProductDocumentClient.kt, dedicated tests, Runtime/Service. Shell
and ui/documents and Rust core/FFI/generated owners remain unchanged.

Required fixed inputs, in order:
1. Core bounded post-EOF display-retaining contract + FFI typed projection preserving
   actual source/scope/expiry/cleanup; independently tested fixed SHA.
2. B actual generated bindings against that exact native combination (466 has none).
3. Policy owner's concrete registered-document selection/issued-grant join, not a
   latest-grant lookup; reader owner's explicit read-only capability gate.

Then implement actual private Service scope/owner mapping, byte/PFD broker and
reader factory with synthetic boundary tests PLUS real native/Android checks.
Until those facts exist, no PFD/display implementation or reader completion is claimed.
No new grants/accounts/credentials, models/search, real files, historical unknown
retry/fee modification, main/develop changes, deployment/payment or permissions.
