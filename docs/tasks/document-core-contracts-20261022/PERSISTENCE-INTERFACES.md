# DOC-01/03/04 persistence slice — interface and ownership

Starting source: `d2ac6a87a8bf13d8a22ebd41676683be8d849a22`.
This continues approved public documents work with real SQLite storage and
synthetic uploads, not another set of engine traits. No third-party engine runs.

## Ownership and shared database

Documents owner: `crates/muyon-core/src/documents/` (new `storage.rs`,
`annotation.rs`, existing contract serde support), `tests/document_storage.rs`,
this task's docs/evidence. `lib.rs` remains exclusively this owner if needed.
No `business.rs`, `sqlite.rs`, `document_edit/`, Android, UI or agent edits.

Reuse `BusinessStore`'s current SQLite connection, exclusive owner lock,
`BEGIN IMMEDIATE`, rollback-on-drop and existing blob upload/publication logic.
Explicit `initialize_documents_trusted()` adds versioned `document_*` tables;
it does not migrate/rewrite existing business tables or create a competing DB.
Access checks use existing project state and current store owner epoch.

Transaction gateway owner must call these BusinessStore methods on the same
owner. Future atomic gateway publication can use
`pub(crate) document_publish_in_transaction(tx, base, title, format, finished)`
to publish immutable blob/revision metadata within its own live transaction;
this function never commits. The gateway must supply its own validated
authorization/operation intent, durable receipt and recovery journal in that
same transaction. It must NOT edit the document tables directly, adopt a second
database or interpret this low-level trusted hook as user confirmation.
Do not co-own/modify each other's source directories.

Authoritative permission/revision read for that same gateway transaction:
`pub(crate) document_access_in_transaction(&self, tx: &Transaction<'_>,
access: &DocumentAccess, required: &[DocumentOperation])
-> Result<DocumentMetadata, ContractError>`. Both hooks reject a transaction
from another connection. Obtain the connection through the existing crate-local
`BusinessStore::database()`; do not begin a nested transaction. Propagate every
hook error and roll back, then journal/query any uncertain outcome through the
gateway's own protocol. Do not call the self-committing public wrapper inside
the gateway transaction. Register/create uses a base DocumentRef at revision0;
existing source publication requires exact current identity/revision and produces
the next revision. Schema SQL and constants are authoritative in
`documents/storage.rs::SCHEMA`. Initialization is explicit, before gateway work.
Permission grants can name all nine typed DocumentOperation variants but do not
establish an engine capability; gateway still checks capabilities separately.

Publication-tail hook (requested by gateway owner):
`pub(crate) document_grant_in_transaction(&self, tx: &Transaction<'_>,
access: &DocumentAccess, required: &[DocumentOperation])
-> Result<(), ContractError>`. It checks same-connection transaction, real
persisted exact grant document binding, active state, epoch/generation, expiry,
requested operation intersection, workspace/project scope and project liveness.
It deliberately does NOT require the old base to remain the current head after
the gateway's own CAS. It returns no bytes or metadata and is not an old-revision
read permit. Required sequence stays access/head check → CAS/publication → tail
grant check → gateway receipt → single COMMIT; any failure rolls everything back.
Gateway does not read/write `document_grants` truth directly. Related gateway
interface: `142c922a44471069f47fbff7b79cf3f1afc1df19`,
`docs/tasks/document-edit-transactions-20261022/DURABLE-GATEWAY-INTERFACE.md`.

## Concrete API

`DocumentMetadata { document: DocumentRef, title: String, blob: BlobRef }`.
Metadata declarations are not actual MIME/safety/reader support claims.

On `BusinessStore`:

- `initialize_documents_trusted() -> Result<(), ContractError>`: exact schema
  identity/version validation and transactional initialization; no hidden migration.
- `register_document_trusted(project_id, document_id, title, format,
  &FinishedBlob) -> Result<DocumentMetadata, ContractError>`: initial revision1;
  validates existing project/upload, publishes blob reference atomically.
- `publish_document_revision_trusted(&DocumentRef, title, format, &FinishedBlob)
  -> Result<DocumentMetadata, ContractError>`: exact expected base CAS; preserves
  old immutable blobs/revision rows. Trusted gateway hook, not model callable.
- `issue_document_grant_trusted(&DocumentRef, &AuthorityBinding,
  &[DocumentOperation], expires_at_ms)` and
  `revoke_document_grant_trusted(&AuthorityBinding)`: persisted exact scope,
  document revision, epoch, generation, bounded expiry and operation permissions.
  Reissuing requires next generation. No decoded grant/permissions are trusted.
  Existing `business_grants` binds one-shot CommandEnvelope operations and
  cannot authorize these new document resources; document grants use the same
  binding type/checks in a separate explicit namespace, never implicit fallback.
- `read_document(&DocumentAccess) -> Result<DocumentMetadata, ContractError>`.
- `save_annotation_trusted(&DocumentAccess, annotation_id, expected_annotation_revision,
  &DocumentAnchor, &AnnotationBody, &AnnotationAuthor) -> Result<AnnotationRecord, ContractError>`.
- `delete_annotation_trusted(&DocumentAccess, annotation_id,
  expected_annotation_revision, &AnnotationAuthor) -> Result<AnnotationRecord, ContractError>`.
- `list_annotations(&DocumentAccess) -> Result<Vec<AnnotationRecord>, ContractError>`.
- `export_annotations(&DocumentAccess) -> Result<AnnotationExport, ContractError>`:
  deterministic sidecar JSON data, no format-native sync/flattening/file output.

`DocumentAccess { document: DocumentRef, authority: AuthorityBinding }` is a
request reference only. Every method resolves persisted active grant, expiry,
epoch/generation, exact project/document/revision and current project deletion
inside the same transaction as the read/write/export. Local read/export never
authorizes cloud transfer. No reusable in-memory permit/cache.

Annotations have stable document-local IDs, own CAS revision, tombstones,
immutable `created_by` and current `modified_by` (`Human{actor_id}` or
`Ai{agent_id,run_id}`). Body is a bounded comment or highlight with quote/note.
Anchor identity/revision/geometry is validated before save; unresolved PDF
geometry is refused. After document publication, older anchors remain stored
and are exported as stale, never silently reattached. Sidecar changes do not
modify original file bytes or increment document content revision.

## Implementation/verification sequence

1. Publish this interface checkpoint before production changes.
2. Write tests for synthetic blob/metadata reopen round-trip, schema identity,
   scope/grant/expiry/revocation/project deletion, immutable revisions/CAS,
   annotation create/update/delete/provenance/stale anchor and export round-trip.
3. Attempt targeted offline tests before implementation; preserve NOT_RUN if
   toolchain unavailable. Implement using real existing SQL/blob primitives.
4. Independent review, corrective tests, exact source SHA, raw logs and push.
   New-source Rust compile/test/format must be rerun in the existing authorized
   verifier environment if this environment still lacks the toolchain.

The existing document-edit state machine at remote
`601f562f98163429103b344aecb3d8639c890a82` is read-only context, not merged.
No competing transaction gateway, actual document parser or Android integration
is introduced in this slice. Full Office reading/editing is still unfinished.
