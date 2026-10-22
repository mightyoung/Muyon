# New-byte candidate preparation and disabled publication gate

Base `aec085fafef8aa02f86f2fc60626f168b10f4caa`. Core owns documents/candidate.rs,
necessary documents module export, blob reservation/materialization/inspection
hooks and conservative restart pin retention. No document_edit, FFI or engine edits.
Gateway schema2, original intent/receipt and unknown execution state remain its owner.

## Shared concrete API (BusinessStore)

- `initialize_document_candidates_trusted() -> Result<(), ContractError>`:
  explicit exact candidate-journal schema on the existing DB, not a second store.
- `prepare_document_candidate_trusted(access: &DocumentAccess, candidate_id: &str,
  operation_id: &str, bytes: &[u8]) -> Result<CandidateStatus, ContractError>`:
  host-owned bytes only, no path/URL/script, bounded by existing 30 MiB document
  maximum. Bind immutable base/source, exact authority and expected bytes/hash.
  Same SQL transaction reserves candidate ID plus actual upload ID before any
  file write. Identical repeated preparation is query-only; a pending/unknown
  original is never automatically rewritten/resumed, and mismatches conflict.
- `lookup_document_candidate(access, candidate_id) -> Result<CandidateStatus,
  ContractError>`: fresh real current read authority, exact base identity and
  read-only inspection of original journal/upload/hash/pin facts. No engine replay,
  file mutation, renewal of old authority or automatic repair. Changed base denies
  access; future historical recovery needs explicit historical policy integration.
- `document_publish_candidate_in_transaction(tx, access, candidate_id)
  -> Result<DocumentMetadata, ContractError>`: **production default UnsupportedOperation**
  after current real authorization, exact candidate binding and shared-transaction
  checks. No real trusted validator exists, so no success path/validation boolean/
  credential constructor/test override. No metadata/head/reference publication.

`CandidateStatus` reports candidate/operation/base, actual expected BlobRef and
preparation state (`Preparing`, `SealedUnvalidated`, `PreparationUnknown`). It
never reports Validated/Committed or becomes a reader lease. Candidate IDs and
operation IDs are opaque identifiers, not file paths. Exposing candidate bytes
or reauthorizing prior execution is not part of the status API.

## Actual storage and crash boundaries

1. Under current ReadText+StructuredEdit authority, journal+upload reservation
   share one existing SQLite transaction, then COMMIT. Before this commit no
   output bytes exist. A COMMIT error is Unknown and requires original lookup.
2. Materialize a new private 0600/NOFOLLOW staging file, append bounded chunks
   and fsync through existing blob primitives. **File writes are not undone by
   SQL rollback.** A failure may leave reservation/staging/partial durable bytes;
   mark PreparationUnknown best-effort and inspect original state, never rerun.
3. Existing finish_blob verifies full bytes/hash and durably creates the immutable
   object/pin. This is preparation only. Recheck authority/base and seal the exact
   journal binding; late failure leaves an unpublished object/pin and Unknown,
   never a success receipt or source update. The original document is unchanged.
4. Restart queries do not resume writes. Existing blob restart maintenance must
   conservatively retain uploads/pins named by a durable live candidate journal,
   even after old owner death. No automatic engine retry, orphan deletion, pin
   adoption, original overwrite or guessed compensation. A missing/inconsistent
   object/pin is Unknown, not Sealed. Cleanup/recovery policy is explicit future work.

Candidate preparation is limited to 32 journal entries / 128 MiB expected bytes
per project (including unknown/unvalidated entries), plus per-document 30 MiB.
These are conservative candidate admission limits, not a global history/blob
disk quota. Until explicit cleanup is implemented, retained entries consume the
budget; do not silently discard uncertain output to make room.

## Future real publication

Gateway must durably claim the original intent BEFORE any engine job. A future
core-owned real validator must inspect the immutable source/candidate identities,
actual bytes, supported patch semantics, unmodified-region invariants, structure,
fonts/layout and format-specific recalculation/annotation/fidelity facts. No
caller bool, hash-only check, successful byte copy or synthetic fixture can mint
production validation. Engine/license/isolation gates remain HOLD.

Only after that integration: same existing SQL transaction rechecks original
intent, current source/grant, exact prepared pin and trusted validation; performs
metadata CAS + pin→blob reference, gateway receipt/state, final grant check, one
COMMIT. Failed SQL retains the private prepared pin; unknown commit is query-only.
Preparation commit and authoritative document commit remain distinct receipts.
This slice does not enable this path and does not modify schema2 gateway truth.

Tests: real new synthetic bytes/hash preparation, no original mutation; duplicate
query-only binding; sealed/unknown restart lookup; trigger failure before reservation
and after durable object pin; revocation/base conflict; invalid/oversized inputs;
restart retention; production publication remains Unsupported with no mutations.
Rust commands are offline; missing tools remain NOT_RUN, never successful TDD.
