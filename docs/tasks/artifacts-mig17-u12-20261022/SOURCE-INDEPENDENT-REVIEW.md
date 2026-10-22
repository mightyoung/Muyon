# Independent review: live Evidence source binding

Separate reviewer: `artifact_review`; production sources were read only. The
reviewer wrote this report and independent execution logs, but made no production
edit or Git commit.

Fixed starting artifact commit: `65fb35c6195a03b48dc476a0917527aa310d02c5`.
Fixed Evidence dependency: `78cdff32dee68b664c4fe71b4bbd6b81251af5e7`.
Reviewed combined checkout: `7d7edf027c50f595b5987ebd7a2051487ece71ac` plus
owned working-tree changes fingerprinted below. No source identity was inferred
from another task's working directory.

## Findings and closure

**Valid source counts could block atomic revocation — closed.** Initial hook
used LIMIT 257 and returned TextLimit above 256 rows, while legitimate issuance
had no corresponding cap. A source with 258 bound objects caused the caller's
same-transaction revocation hook to fail. This was an open Important finding;
the early review could not be considered complete. The author retained a real
failing Rust regression (`source-batch-red.log`, TextLimit), replaced the cap with
actor/object keyset pagination, and obtained GREEN. Final independent execution
also passed the 258-object regression. Cursor advancement includes valid rows,
so they cannot repeat forever while invalid rows are deactivated.

**Frozen source authority prevented normal durable-draft recovery — closed.**
Initial renewal required byte-identical Snapshot, including a short-lived source
grant. Refreshing ReadText generation/epoch stranded the original local object;
a fresh proof then failed BindingMismatch. The author retained a real failing
renewal test (`source-renewal-red.log`). Fresh real resolution may now explicitly
renew authority/reactivate the source row only when canonical metadata, exact
reference JSON and evidence ID stay equal. The original local binding generation
must advance. Draft values/revision/manual origins do not change, and an old
preview fails confirmation. Independent final execution passed this regression.

**Proof context was too reusable — addressed.** The proof now borrows its actual
BusinessStore and freezes its resolving actor. Issuance compares both, and source
resolution requires a live independent LocalDraft or LocalFeedback purpose in
the exact source scope. Save/Discover are not substitutes. Tests reject reuse
across actors and even across distinct stores with matching synthetic identities.

**Persisted reference could be paired with a different real document — closed.**
The author found and retained a real negative test (`source-identity-red.log`):
replacing Snapshot metadata/authority with another registered Text document while
keeping the old evidence reference previously passed a read. Private
StoredReference validation now checks exact source document/blob, evidence ID,
source content address, range bounds, quote-digest shape, Text format and absent
PDF page. The negative regression passed in the independent final run.

No remaining confirmed Important finding or scoped correctness/security defect
was found in the final reviewed source. This statement does not approve the
unimplemented integration boundary below.

## Source/permission assessment

- Initial proof construction calls actual StoreEvidence::open, which validates
  the current registered source, controlled reader, UTF8 passage range/quote hash
  and current ReadText inside the real owner transaction. It then rechecks exact
  canonical metadata and project purpose. No quote/body is persisted here.
- ResolvedLocalEvidence cannot be deserialized or fabricated from display/model
  IDs. Holding it is not enduring authority: local_binding resolves the stored
  exact DocumentAccess against current document head, scope, grant generation,
  epoch, expiry and live project on every use, including the final receipt tail.
- The StoredSource serialization order (document, blob), compact JSON SHA-256
  source ID and colon-separated source/range/quote-digest evidence ID match the
  actual fixed Evidence implementation. Decoder checks are not a replacement
  for initial StoreEvidence::open. They prevent persisted ID/metadata mismatch;
  original text bytes are neither duplicated nor silently replaced with latest.
- Initial unresolved Evidence and all Message bindings fail closed. Generic
  issuance can only renew an already resolved original source. Source publication
  invalidates current reads/previews immediately, independent of lease TTL or
  whether notification callbacks are wired.
- Source authority renewal is separate from immutable source identity. The local
  generation advances atomically with source authority, preserving human edits
  and field-level origins while invalidating old previews. A different source
  revision/reference cannot be smuggled in as an authority refresh.
- Final local receipt UPDATE is still followed by local source/binding/kind and
  project-purpose checks. Source grant revocation/expiry/generation failure here
  rolls back state/receipt and leaves original pending with Unknown/QueryOriginal.
  Existing duplicate/lookup paths return historical operation metadata only;
  they do not authorize current content or replay the original effect.

## Invalidation-hook scope

The hook requires the same BusinessStore transaction and exact workspace/project/
document identity; pagination stays inside that scope. It rechecks each stored
source and deactivates only affected source/local binding rows. Returned events
contain only project/actor/object IDs. It does not enumerate projects, confer
Discover, change local values, reconcile pending intents or create receipts.

This is a privileged core-owner callback, not a model/UI endpoint. Call it after
the source mutation in the same transaction and deliver events only after commit.
Rollback invalidates both the mutation and the returned event list. Tests exercise
rollback and commit and verify journal/value preservation. Missed notifications
still fail closed because reads and mutations independently validate source truth.

## Independent real execution

The reviewer used the existing locked official Rust toolchain, existing cached
packages and native SQLite link directory. No software was installed, dependency
updated, network/model/search request made or owner source modified.

The existing author runner was inspected and independently invoked with a
separate `CARGO_TARGET_DIR=/tmp/artifacts-independent-target`; it generates only
module declarations for actual core/Evidence/artifact files and refuses dependency
version/source/checksum drift from the repository lock. This is a module
combination harness, not a production lib.rs export or Android bridge change.

- `source-independent-cargo.log`: 9 source tests passed, 0 failed, exit 0.
- `source-independent-artifacts.log`: 41 artifact tests passed, 0 failed, exit 0.
- `source-independent-final.log`: repeat before the final whitespace cleanup,
  41 passed, 0 failed, exit 0.
- `source-independent-final-formatted.log`: final repeat on the final fingerprinted
  sources after whitespace cleanup, 41 passed, 0 failed, exit 0. This includes
  the old 17 artifact tests, original
  15 local tests on real Evidence fixtures and 9 source integration tests.

Command shape:

```text
env CARGO_HOME=/tmp/artifacts-cargo CARGO_TARGET_DIR=/tmp/artifacts-independent-target \
 RUSTC=/tmp/artifacts-rust/toolchain/bin/rustc RUSTFLAGS='-L native=/tmp/artifacts-link' \
 python3 docs/tasks/artifacts-mig17-u12-20261022/run_source_combination.py \
 --repo /workspace/Muyon --cargo /tmp/artifacts-rust/toolchain/bin/cargo --filter artifacts
```

The final runner's actual Rust source manifest SHA-256 was independently recomputed
after completion and matched the current files exactly:
`cd5e8aa60465b88f5c2a4a910646384438f3cb80fe70f38e3d25b84c86f6d0c8`.
Runner SHA-256: `7c5652f0c33508f6b1069084fbfd65502d860432ff63241b40ca12239be9206d`.

The author also records a full workspace run and retained historical failures.
That is separate from the reviewer's targeted reruns. Strict Clippy remains red
on two core-owner unused hooks (blobs.rs clone_blob_reference_in_transaction and
documents/storage.rs document_clone_in_transaction); no owner edit or allow was
added. Full formatting failure is retained. These are not represented as passing
checks by this review.

## Remaining integration limits

- Canonical Message/request/side/revision identity and transactional authority
  still need a real Runtime owner contract; Message remains unsupported.
- Actual source-grant eligibility for the authenticated actor remains trusted host
  policy. Actor-bound proof prevents context reuse; it does not invent an actor
  ACL column that the existing document-grant model does not contain.
- Core publication/revocation callback wiring, after-commit notification delivery,
  Service/FFI/Android binding and designated module exports remain owner work.
  No push/UI integration, completed ordinary Message form flow or device acceptance
  is claimed here.
- PDF/OCR evidence is unsupported by this fixed Evidence backend. No document
  engine HOLD is bypassed or capability enabled by these tests.

Source delivery is reviewable and the scoped real tests pass. Product integration
and the non-green owner checks remain explicit limits; old unknown requests and
held-cost reservations were not read, changed or retried.

Reviewed owned source SHA-256:

- local_sources.rs: `52b3a4e9eda179d43535218da7452dc68ad98a8c6635e582678399d0b6b3e364`
- local_interactions.rs: `b54c147c38c9628b00679b215945037c5ffa8cbe0c043f709250ce6d4e86354d`
- local_interactions/tests.rs: `c483aad458df1088f9ddc96824aecb60e5aef1dec10fefdf5bef9228cc31dec5`
- local_interactions/source_tests.rs: `c107eb7a38fac27d07302ffa9dc8893724257320c3daed22d0abdeedab5c51b2`
- mod.rs: `2ca104e9440f5288e482a589efede316ea0f5f8deb9f4f573cb6ffcedda125c1`

Final follow-up: the final local_interactions whitespace cleanup was inspected,
then the reviewer reran the complete 41-test artifact filter against the final
source files with an independent target directory. Exit 0 and the newly recomputed
current Rust source manifest match `source-independent-final-formatted.log` exactly.
The source hashes above therefore cover the final reviewed implementation. No
Important finding remains open in this scoped source review; listed integration
limits and non-green owner checks remain.
