# Private new-byte candidates: preparation and fail-closed publication

Interface-first commit: `81a7270ec4ef1eafff4b6e0e37bbd14314f5e5bb`.
Final source: `0ddb5d2a76ae42efcc7b252c86d2992a8a85c9f3`.
Production behavior is fixed at `10d3aa83e2a93581107ad2e9f44331b5ea99d866`;
the final source adds an equal-length hash-corruption test and corrects the
documents module description. Branch: `task/document-core-contracts-20261022`.

## Delivered behavior

`CANDIDATE-INTERFACE.md` is the gateway handoff. The existing BusinessStore owns
the explicit `document_candidates_v1` journal and original document/grant/blob
truth; no second database, engine, FFI or document_edit implementation was added.
Host-only preparation accepts bounded bytes and opaque IDs, never arbitrary paths.
It computes actual output length/hash, freezes the exact source revision/blob and
authority, reserves the journal and upload in one SQL transaction, then creates a
private new staging file and uses the existing chunk/fsync/immutable-object/pin
primitives. Actual output bytes may differ from source bytes. The source document
and its references remain unchanged.

Preparation is not validation. Status exposes only `Preparing`,
`SealedUnvalidated` and `PreparationUnknown`. The same-transaction production
publication hook always returns `UnsupportedOperation` after real authorization
and binding checks. It creates no head, reference, receipt or validated credential.
There is no caller boolean, test success override, fake format validator or engine
job. The lower-level earlier COPY/upload hooks must not be used to bypass this
gate. Real Office rendering/editing and edited-candidate publication remain HOLD.

Identical retries query original facts only. Changed bytes, operation, source or
execution authority conflict; unknown state never resumes file writes. Recovery
requires fresh real current permissions and the exact original source; a changed
head is rejected instead of substituted. It inspects the original recorded pin,
file hash and length without adopting the old owner's execution authority.
Revocation/expiry is rechecked between preparation stages and before sealing or
returning status. History reading still requires the separate explicit history
grant, never the publication-tail hook.

## Durable failure boundaries

Reservation commit precedes byte creation. Filesystem writes and object renames
are not undone by SQLite rollback. After reservation, failures return Unknown and
best-effort mark the journal unknown; lookup must inspect original facts. A late
seal failure may retain real bytes and an unpublished pin. Restart maintenance
retains journal-associated uploads/pins, including partial staging, without
resuming work. A missing pin/object or corrupt object yields unknown preparation,
without repair or promotion to validated.

GC preserves a journal-backed incomplete upload's exact expected digest, while
allowing unrelated orphan objects to be collected. Unresolved uploads are scanned
in bounded 128-row keyset pages. Legacy unknown uploads keep their conservative
retention behavior. Corrupt journal facts fail closed rather than permit deletion.

Admission limits are 30 MiB/output and 32 retained candidates / 128 MiB expected
bytes per project. Retained unknown/unvalidated entries consume the budget;
explicit cleanup is not implemented. These limits are not a total disk quota:
staging/object copies, existing blob storage and annotation history have separate
costs. Actor/group provenance authentication and reader integration remain future
work from the earlier persistence slice.

## Tests and evidence

Twelve offline candidate tests were authored. They cover actual synthetic-byte
preparation, source preservation and publication denial; exact query-only repeats
and conflicts; reservation and late-seal SQL faults; restart retention and authority
epochs; invalid/oversized input and revocation; partial staging plus a durable tail
not reflected in SQL; unrelated GC versus exact-digest retention; bounded SQL
projections; admission limits before file writes; expiry after durable pin; separate
corrupt/missing object and missing pin states; and source-head advance rejection.
The raw partial-tail and orphan fixtures exist only under `cfg(test)` and never
construct a production validation credential.

Raw logs are in `candidate-evidence/01-test-first.log` through
`05-final-source-verification.log`. On this environment:

- `cargo test -p muyon-core --offline documents::candidate_tests`: **NOT_RUN**, tool absent (127).
- `cargo test -p muyon-core --offline`: **NOT_RUN**, tool absent (127).
- Scoped `rustfmt --check --edition 2021` for candidate.rs, candidate_tests.rs,
  documents/mod.rs and blobs.rs: **NOT_RUN**, tool absent (127).
- `git diff --check`: exit 0.

No dependency/tool installation, network/real model request or document engine
execution was attempted. Earlier real COPY 6/hooks 9/core 189 verification and
format evidence apply only to their older fixed source, not this new source.
The new candidate and history/Text changes require the authorized Rust verification
environment to compile and run before integration. Static independent review is
recorded separately and is not execution evidence.

## Next integration boundary

The transaction owner retains schema2 original intent/receipt ownership and must
claim the original intent before an engine execution. Future publication requires
a real core-owned validator's immutable facts, same-transaction source/revision
CAS + pin-to-reference + gateway receipt + final grant and one commit. Unknown
commit must query its original receipt; no automatic engine retry. The current
disabled hook deliberately offers no successful partial substitute.

Leader B applies only fixed deltas to the separate integration branch, including
the unapplied module-export patch once its source modules are present. This branch
does not change main/develop or other owners' modules. No aggregate completion or
workspace-green claim is made.
