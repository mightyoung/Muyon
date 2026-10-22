# COPY-only same-transaction reference clone

Reviewed starting source: `f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac`.
Owner additions are limited to documents/, the new blobs.rs hook (this owner
exclusively authorized for this change), corresponding tests and this task's docs.
No gateway, Android, main/develop or unrelated blob code changes.

## Signature assessment

The proposed signatures fit the existing same-connection transaction seam:

`pub(crate) BusinessStore::document_clone_in_transaction(tx: &Transaction<'_>,
base: &DocumentRef, title: &str, expected_blob: &BlobRef)
-> Result<DocumentMetadata, ContractError>`.

`pub(crate) BusinessStore::clone_blob_reference_in_transaction(tx:
&Transaction<'_>, project_id: &str, target_id: &str, expected_blob: &BlobRef,
new_reference_id: &str) -> Result<BlobRef, ContractError>`.

Both reject a foreign transaction and never BEGIN/COMMIT. Document clone must
resolve exact current base, compare expected_blob to its real metadata source,
preserve format, compute checked next revision and CAS. The lower hook checks
current project liveness, an existing reference in that same project to a ready
blob of exact length/digest, then verifies the existing immutable file and hash.
Only a new reference row and next document revision are written; source bytes,
original references/revisions, uploads, pins and staging remain unchanged.

Both are trusted low-level hooks, not grants. Required gateway sequence in one
BusinessStore transaction: current document_access_in_transaction (appropriate
read/copy permission) → exact COPY binding checks → document_clone_in_transaction
→ durable gateway receipt → document_grant_in_transaction → COMMIT. Propagate
errors and roll back the whole transaction. Tail check must be last meaningful
work before COMMIT; the gateway owns idempotency/query-only recovery.

This advances the SAME document's metadata revision with BYTE-IDENTICAL source
content, not a separately named original-format file or a semantic edit. Receipt
must say COPY-only and preserve identical source/result digest. There is no
candidate-input argument: edited bytes, format changes or engine-success claims
cannot be expressed through this hook. Full Office editing remains unsupported.

## Tests and verification plan

Tests first: same digest/format and checked next revision, unchanged original
bytes and no uploads/pins/staging effects, late receipt failure rollback, stale
base/wrong source/foreign transaction/cross-project/unready source/hash tamper,
duplicate reference rejection, missing source and revision overflow.
Actual Rust commands will be attempted offline; missing toolchain remains
NOT_RUN. Independent static review and fixed source SHA are required, followed
by actual compilation in the existing authorized verifier environment.

## Real edited candidate publication, future work (no engine run)

Retain existing durable blob preparation as a separate explicit **prepare** phase:
write candidate bytes to an immutable private object, fsync and hash, persist
scope/operation/base/candidate identity and a durable pin. Preparation is not a
document commit, does not advance the head and cannot produce a success receipt.
Crash before pin receipt is preparation-unknown/reconciliation only; do not
automatically replay an uncertain external engine job. Orphaned prepared objects
need bounded retention/quota and explicit recovery/garbage-collection policy.

Then in ONE shared SQL transaction resolve current grant/head, match exact
validated candidate hash/pin/scope and reviewed semantic patch/engine validation
evidence, CAS document metadata, convert its pin to a reference through existing
publication, insert the gateway receipt/journal, recheck live grant, COMMIT once.
Failure rolls back SQL to the prepared pin with original document unchanged;
unknown commit is query-only against the original intent. No file rename or
staging operation should occur inside that final SQL commit phase. Blob durable
preparation and authoritative publication are distinct receipts, not two stores
each claiming document success. The existing publish_blob_in_transaction seam
already supports the SQL pin→reference part; complete prepared-candidate intent,
engine safety/fidelity/license and crash-window validation remain separate work.
Do not route an edited candidate through the source-only clone API as a shortcut.
