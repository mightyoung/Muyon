# Minimal COPY-only atomic publication hook requested from owners

Resolved and consumed: core a27f04aa2460971940d4bdf2c8263bdf81f381c2; production
f6ab7fd78f46319cf46e9754d80c7cf0f6781205; interface
8d6cc642086fcdd12889aa22fec77797dd6c56e2. Actual same-transaction clone replaces
the upload route entirely. Gateway tests assert new reference/revision but no new
upload rows or object/staging files. Different-hash edited candidates reject.
Final grant-only recheck follows receipt write immediately before COMMIT.
The original request and reason below are retained as history.

Current integration source f043c6b9b8d850acb590a9a3e567d1f2634a95cd works for the
metadata/receipt/grant-tail atomic transaction, but existing upload APIs own their
own transactions. Independent review therefore does not accept staging-write grant
atomicity. This is an active dependency request, not an accepted permanent gap.

## Core owner: documents/storage.rs only

```rust
pub(crate) fn document_clone_in_transaction(
    &self,
    tx: &crate::sqlite::Transaction<'_>,
    base: &DocumentRef,
    title: &str,
    expected_blob: &crate::contract::BlobRef,
) -> Result<DocumentMetadata, ContractError>;
```

Check transaction belongs to this owner, current project/head/reference equals base,
current metadata.blob equals expected_blob, and checked next revision. Reuse the
existing canonical doc-reference ID scheme. Ask blob owner helper to create the new
reference to that same immutable object. Insert new metadata revision and CAS head
without COMMIT. Preserve old revisions and source bytes. Return actual metadata.
No new format, fake FinishedBlob, arbitrary object/path, decoded authority or engine
receipt is accepted. This is low-level trusted mechanics; gateway still resolves
current real grant and authentic confirmation before calling it.

## Blob owner: blobs.rs only (needs parent ownership coordination)

```rust
pub(crate) fn clone_blob_reference_in_transaction(
    &self,
    tx: &crate::sqlite::Transaction<'_>,
    project_id: &str,
    target_id: &str,
    expected_blob: &crate::contract::BlobRef,
    new_reference_id: &str,
) -> Result<BlobRef, ContractError>;
```

Same live owner connection; check project liveness and restricted IDs, ready object,
existing source reference in same project/target/digest and real private file
length/hash. Insert only the new blob reference in caller's transaction. Do not
begin/commit another transaction, create/append/finish an upload, write/rename a
file, alter grants or expose arbitrary paths. Returns verified existing BlobRef.
Could equivalently be a blob-owner approved existing-reference hook with the same
invariants; this worker will consume the exact published signature, not patch blob
or document source files privately.

## Gateway owner: document_edit/ only

A real bounded byte-identical candidate already persists separately as hex bytes in
edit_journal_intents and is hash/length verified against the frozen source. COPY-only
publication may legitimately deduplicate its immutable object: an output revision
and reference are new; source file bytes and previous revisions stay immutable.
Gateway will replace begin_upload/append_chunk/finish_blob path entirely with the
core clone hook. In one BEGIN IMMEDIATE: current authorization and exact source,
clone/CAS, receipt+intent terminal write, view construction, final grant-only
recheck immediately before COMMIT. No visible success before COMMIT. Unknown
queries original intent and never repeats clone, copy, upload or publication.

Tests will assert no new blob_uploads or files for copy publication; exact metadata
revision+original receipt do change atomically. Existing receipt-tail rollback,
source conflict, grant-tail triggers, restart and idempotency tests must remain.
Engine requests remain HOLD, including simulated_validated/fake responses.
