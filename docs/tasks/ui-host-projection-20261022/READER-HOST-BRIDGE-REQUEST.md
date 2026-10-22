# Shared-document read host — exact boundary and native request

Inputs read without merging/unreleased composition:
- Shell request74a39791774f85514a03b0a578ecff788e048130,
  docs/tasks/ui-shell-20261022/READER-WIRING-REQUEST.md.
- Reader6cdaaa23ca1c194c0c32599cc1293f6c50907dcd:
  DocumentReaderModels/Screen/SharedDocumentJson and reader HANDOFF.
- Core documents473b7eb15fb199b5e20b96e52859b48ea09acef6, whose existing APIs are
  documents/storage.rs::{read_document,list_annotations,save_annotation_trusted},
  DocumentAccess/DocumentMetadata, identity DocumentRef and shared anchors.
Reader2 has pending Important fixes; no final combination or editing integration yet.

## Exact Kotlin writer boundary (this thread)

Already owns ProductChatRuntime.kt and agentipc/ProductService.kt. Proposed NEW
exclusive paths, to avoid shell/reader ownership conflicts:

- product/documents/host/DocumentHostLease.kt — live ref/lease/epoch invalidation,
  exact original snapshot and bounded check/delivery policy, with dedicated tests.
- product/documents/host/DocumentDescriptorBroker.kt — bounded authorized byte source
  to a new seekable READ_ONLY PFD; no ambient ContentResolver/path access.
- product/documents/host/ProductDocumentHost.kt — concrete reader factory after exact
  reader2/native interfaces, snapshots and lifecycle invalidation are released.
- product/agentipc/ProductDocumentClient.kt — typed Messenger/Bundle descriptor reply
  and idle invalidation client. Existing ProductClient and ui/documents stay untouched.
- matching dedicated test paths under product/documents/host and agentipc.

No manifest/provider/permissions change is needed for the chosen first design:
the private same-UID Service may return a PFD object in a typed Bundle. An opaque
content://.../lease handle is descriptive host-selected metadata mapping to that
exact active session, not an externally resolvable provider or authority token.
DocumentReaderHost.openCurrent uses the typed private client, never ambient
ContentResolver.openFileDescriptor. URI alone, document IDs or JSON never grant access.

No these-file implementation is claimed in this request document; names and private
native calls remain proposed until the sole core/FFI owner fixes the bridge.

## Real native gaps found

DocumentAccess is document+AuthorityBinding; storage.document_access resolves exact
head, live project, persisted grant generation/epoch/permissions/expiry on each access.
read_document/list_annotations authorize metadata/sidecar, not byte delivery.
BusinessStore.open_blob_reader(project,BlobRef)/read_blob_chunk/close_blob_reader
already control blob sources, but do not by themselves re-check the document grant
at each use. A new document-scoped read session must compose these checks; cannot
wrap ResearchFileHost.attachment or a cache/PDF file path as document authority.

Document storage currently has register/publish/read/grant/annotation operations,
but no bounded authorized listing/private session+byte FFI. Persisted document heads
and grants are the one truth; no title/paper/digest-derived substitute DocumentRef.
If the shared store is actually empty, display real empty/unavailable, never fixtures.

save_annotation_trusted currently opens its own transaction, validates grant+revision,
and writes sidecar/history. It has NO original intent or receipt argument and allows
anchor input to differ from an existing annotation's old anchor. Existing revision
CAS therefore does not implement idempotent original annotation-save recovery.
Do not report an arbitrary call as Saved/re-entry-safe or clear unknown after closing.
A future intent gateway needs the original immutable anchor+expected annotation CAS
and journal+effect+receipt in one transaction; nested transactions are not a solution.

## Request to sole native/FFI owner01a16210-a70d-7639-bfe0-5eca5fc01024

Coordinate document-core ownership before touching documents/storage.rs; its author
owns canonical document truth. Only existing core/lib.rs owner adds exports. Only
the assigned FFI owner edits crates/muyon-android-ffi/src/lib.rs; this thread will
not concurrently change either Rust lib.rs.

First deliver READ ONLY, with bounded existing-style JSON metadata and typed byte
chunks. Names below are requested contract proposals, not calls already coded:

1. document_list(project,limit,offset): validate current BusinessStore workspace and
   live project, list exact registered current DocumentMetadata/Ref rows using one
   shared store. No implicit source registration/research-cache import or guessed ID.
2. document_read_open(service_session, ref_json): host resolves current trusted
   DocumentAccess for that user's explicit selection, effective read permissions,
   actual authority generation/epoch/expiry; returns opaque read_session_id, exact
   immutable metadata, actual blob length/digest, current annotations and expiry.
   Keep grant binding/native reader table private; no caller self-declared grant,
   permissions, actor or path. Missing trusted issuer policy must be explicit.
3. document_read_check(service_session, read_session_id): current DocumentAccess,
   exact head/source/project, grant generation/epoch/expiry revalidation; return exact
   bound ref/session and active/invalidation reason, not reusable permission proof.
4. document_read_chunk(service_session, read_session_id,max<=65536): before reading
   and again before returning bytes, recheck that SAME current DocumentAccess and
   immutable blob source. Bind native ControlledReader to exact ref+grant+owner.
   Revoke/expiry/revision/project/source change closes reader and yields no bytes.
   Source safety and actual-byte format/MIME admission must be checked, not inferred
   from extension or caller ref.format alone. Bound whole-document size too.
5. document_read_close(service_session,read_session_id): release exact owned native
   reader; Binder release/revoke closes all its handles. Cross-session use refuses.

No raw path or user-provided URI is a native input. Check/Open/Read operate on
native-owned current authority, not an authority JSON round-trip. Core errors expose
sanitized stable codes, no source bytes/paths or tokens in logs. Revisions remain
bounded unsigned decimal STRINGS, never through Double/Long. Format support is a
separate host capability decision, not inferred from DocumentFormat enum membership.

Service can turn those bounded verified bytes into a fresh private temporary
seekable artifact, verify exact byte count/digest and actual-byte safety, obtain
ParcelFileDescriptor.open(..., MODE_READ_ONLY), unlink after ownership transfer,
and check current native session immediately before delivery. It must never reopen
an old cache file with a new grant. Client/Service both fence fd responses by exact
Binder lease/ref/epoch, close late/foreign descriptors, and close mounted copies on
invalidation. ReadOnly flags and seekability require actual Android tests later.

Idle invalidation is required, not just checks on button taps. Host owns a bounded
set of active reader sessions, emits changes on native mutation/scope/Binder release,
schedules native revalidation at expiry and bounded local idle refresh as needed,
and publishes accessActive=false/new mounted epoch. Client then drops output and
closes descriptors; open/start and render/parse-before-delivery checks remain fresh.
A delivered FD cannot be remotely erased from an arbitrary recipient: do not claim
OS-level retroactive revocation. This is the private trusted reader lifecycle plus
mandatory fresh checks/idle invalidation, not transferable authority to other apps.

## Annotation phase — explicitly disabled until separate fixed transaction bridge

Reader2 must expose an explicit edit capability gate (read_only snapshot/host flag)
so annotations can remain visible while save controls are disabled. Returning
Rejected from an enabled fake save callback or dropping real annotation rows is not
a capability gate. This thread will not change reader-owned code to invent one.

Later private prepare/save/lookup-original-annotation bridge must:
- derive a genuine trusted local actor rather than accept actor ID from edit JSON;
- use exact shared DocumentAnchor parsing, unchanged immutable document+old anchor,
  existing annotation ID and expected annotation revision; no invented location;
- persist original local annotation intent/params digest and receipt in the SAME
  SQLite transaction as canonical sidecar mutation, rechecking current grant at tail;
- retain exact original outcome across close/process death/scope epoch changes;
  Unknown remains lookup-only, no new write until that original is reconciled;
- return actual refreshed annotation snapshot after confirmed commit, and distinguish
  historical receipt from current document/annotation state.

Canonical owner may extract a transaction-owned annotation mutation hook analogous
to document_access_in_transaction/document_publish_in_transaction; do not duplicate
annotation SQL or call the current internally-transactional function inside another
transaction. Parent should assign that exact module change to its document owner.

## Next actual host work and acceptance

With fixed read-only FFI, this thread implements the new adapter files and Service
PFD response path, then actual factory for the reader owner's released read-only
capability gate. Shell keeps its unchanged signature and sole route ownership.
Offline tests use synthetic documents/ports only: scope/session/source/revision/
expiry invalidation, out-of-order descriptor callbacks, size/digest/safety failure,
idle invalidation, and close/cancellation cleanup. Android compile/PFD/renderer/
Binder tests stay NOT_RUN until the recorded Gradle/SDK issue is resolved without
bypass; source work and honest JVM tests can proceed. No true user files, new engine,
network/provider requests, new credentials, permissions, paid/deploy or main/develop.
