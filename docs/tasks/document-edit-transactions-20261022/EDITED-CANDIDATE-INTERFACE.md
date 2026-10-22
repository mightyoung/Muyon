# Edited candidate preparation and atomic publication boundary

Authorized follow-up to90b7a35a49f4acb09ff73a2b088df4c1d1a037a6; exact core
read a27f04aa2460971940d4bdf2c8263bdf81f381c2 COPY-CLONE-{REPORT,INTERFACE}.md.
Only document_edit/, own tests/docs. No engines, user files, lib.rs, FFI, blob/core edits.

## Current implementable preparation

Separate journal table, same BusinessStore owner/transaction. A held schema1/2
request binds policy version, true document format, actual metadata/blob identity,
original intent and complete typed operation. Prepare is not confirmation. Authentic
confirmation binds exact request+source+authority. Candidate ingestion is claimed
durably once, then bounded bytes/hash are persisted in the SAME authorized SQL
transaction; uncertainty is query-only Unknown. Receipt says candidate_unvalidated,
not document success. No independent upload/staging API is invoked. SQLite journal
bytes are not an immutable blob object/pin and cannot enter core publication.

This local storage protocol may be tested using original synthetic different bytes;
it does not prove those bytes are OOXML, actual engine output, safe or faithful.
There is no validation success API; edited publication always rejects. Current grant,
source CAS and tail checks apply to preparation/confirmation/byte delivery. Inspect
lookup cannot read bytes or resume Unknown; cancellation cannot undo a commit or
replay an engine. Existing COPY tables and receipt path remain independent.

## Minimum cross-owner follow-up requested (not fabricated here)

Core/blob owner should supply a reviewed prepared-object handle, minted internally
from authorized candidate bytes, bound to workspace/project, document ID, original
intent, exact base/source blob/format, operation digest and candidate hash/length.
Handle construction/deserialization by model or caller claims must be impossible.
Preparation should persist its own original-intent receipt and pin; query same intent
on unknown. Live authorization must cover each source/read/write and preparation tail;
ordinary begin_upload/finish_blob separated transactions do not meet this contract.

Suggested trusted seams, final type/signature belongs to core owner:
- `prepare_document_candidate_trusted(access, binding, bounded_bytes)` ->
  `CandidatePreparationOutcome` (Prepared/Unknown; no document success);
- `lookup_document_candidate_trusted(access, original_binding)` -> original outcome;
- `document_publish_candidate_in_transaction(tx, base, title, format,
  &PreparedDocumentCandidate, &ReviewedValidation)` -> actual DocumentMetadata.

Final hook must reject foreign tx, match exact prepared pin/scope/intent/base/source/
operation/true format/hash/length, verify immutable object, CAS checked next revision,
convert pin->reference in caller SQL tx, never write/rename files or COMMIT. Gateway
then inserts original receipt/journal and performs grant-only tail check before one
COMMIT. All failure rolls back to original document+prepared pin; Unknown queries
original intent only. Validation is host-owned reviewed evidence, never bool or
fake/simulated engine receipt. Retention/quota/crash reconciliation policy must be
explicit before external object prep is enabled. COPY hook is unusable for this.

Unpublished byte delivery additionally requires fresh exact edit confirmation and
ReadText+StructuredEdit; a source-only ReadText or new unconfirmed grant cannot
read prepared different bytes. Cancellation retains data but blocks delivery.
