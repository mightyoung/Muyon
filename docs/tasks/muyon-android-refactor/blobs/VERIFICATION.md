# P05 private attachment staging and recovery

The initial hard-link implementation below was superseded after an actual API26
SELinux denial. Current code uses verified private copy + serialized rename;
see [API26 solidification fix](API26-SOLIDIFICATION-FIX.md) for the actual failure,
current protocol and fresh validation. Earlier mutation/hash records are retained
as historical evidence, not current implementation identities.

Implementation: `crates/muyon-core/src/blobs.rs`, public integration tests
`crates/muyon-core/tests/blobs.rs`, unit/process/barrier tests in `blobs.rs`.
No dependencies added; schema/accessors belong to the business store owner.
All production SQL uses the owning `BusinessStore`'s existing connection.

## Contract

Trusted host picker calls `begin_upload(project_id)` and receives random opaque
`upload_id` and `snapshot_id`. The active project and workspace are checked and
the project revision/owner epoch are captured. A durable copying row commits
before the private staging file is created. The public API takes opaque IDs,
never user-selected paths. Root is the owning database filename plus `.blobs`;
private directories use mode 0700 and new staging files 0600. Regular-file
opens use O_NOFOLLOW. The single OS-lock business owner serializes calls.

`append_chunk` accepts 1..65536 bytes, checks the persisted length against the
actual staging file and caps the whole upload at 150 MiB. Each file write is
synced before the corresponding length ledger commits. These two operations
are deliberately not called atomic: a failed/unknown append must not be blindly
retried. A mismatch is rejected; restart recovery aborts old copying uploads.
Unexpected multi-link staging inodes remain refused defensively. Current
publication copies to a different inode, so later staging writes cannot mutate
an object after a failed pin transaction.

`finish_blob(upload_id, BlobKind)` verifies digest/length before publishing a
ready blob row and durable upload pin. Pdf/Document cap at 30 MiB, Archive at
150 MiB. Pdf checks `%PDF-` at the start and `%%EOF` within the last 1024 bytes;
this is a basic envelope check, **not a PDF parser or malware certification**.
Document is opaque. Archive invokes the A01 bounded ZIP32 metadata reader;
this does **not** validate decompressed entry contents. Publication creates a
bounded, rehashed private `pub_<upload_id>` copy in staging, syncs it and the
directory, checks the target again and renames only that copy. An existing
target (including a dangling symlink) is never replaced; only a regular file
matching its actual SHA-256 and length is reused. This check/rename guarantee
depends on the private directory and sole locked business writer, not POSIX
rename itself being a no-replace syscall. Target file and both directories are
synced before the pinned ledger commit. After
that commit, removing the redundant staging name is only cleanup.

`lookup_upload` is SQL-read-only. It neither creates directories, repairs state,
renews authority nor collects files. A repeated same-kind finish of a pinned
upload verifies the current pin, ready state, exact snapshot and file bytes.

`publish_blob_in_transaction(tx, upload_id, reference_id, project_id, target_id,
expected_blob)` is crate-private. The transaction must belong to the exact
business database. It validates current epoch, workspace/project/revision,
the pinned snapshot/digest/length, expected BlobRef and actual object bytes,
then inserts the reference, marks upload committed and releases its upload pin.
It never commits or mutates files. The research business owner must call this
inside the **same transaction** as record/history/receipt, and require Pdf kind
for a manual paper. This helper alone is not proof of a real paper receipt.

`open_upload_reader` permits a current pinned upload; `open_blob_reader`
requires a published reference in the requested active project. Both check
ready state and actual SHA-256/length before committing a durable reader pin.
The returned `ControlledReader` has private fields and exposes a `FileSource`
with opaque lease identity, snapshot, digest and length, never a raw path.
Reads require a current matching owner/lease and ready state and are bounded
to 64 KiB plus the expected total length. `close_blob_reader` closes its OS file
before releasing the DB pin. Dropping without explicit close conservatively
retains the DB pin until explicit restart reconciliation.

## Recovery and collection

`reconcile_blobs_after_restart` is explicit maintenance. The OS owner lock
proves no previous connection owner remains; callers must supply a fresh epoch
on restart. Stale copying uploads can be aborted because publication requires
pinned state. Stale pinned uploads can be aborted only when there are **no**
pending/unknown business intents. Unknown uploads are retained. Old reader pins
can be released once the old owner is known dead. No wall-clock expiry exists.

Conservative GC blocks on **any** pending/unknown business intent, even one that
might be unrelated, and on any nonterminal upload that might refer to the blob.
This can retain extra disk space; it avoids inventing missing intent-to-file
proof. Aborting pinned uploads also refuses while business outcome is unknown.

`collect_blobs` checks no references, pins or unresolved related uploads in a
business DB transaction, commits `deleting`, then unlinks and syncs the private
object directory. Only afterward does it remove the deleting ledger row in a
new transaction. Read and publish acquisition require `ready`; a same-digest
finish cannot revive deleting state. Recovery can finish either deleting step.
An orphan file renamed before its ledger commit is admitted to deleting only
after validating its digest path and actual bytes and proving no live pin/intent.

## Executed evidence (2026-10-20)

From `crates`:

```sh
cargo test --offline --locked -p muyon-core --test blobs
cargo test --offline --locked -p muyon-core --lib blobs::tests -- --nocapture
```

Before the API26 fix: **8 integration tests passed**, **11 unit tests passed**,
exit 0. Current copy/rename implementation has **8 integration tests passed**,
**14 unit tests passed**, exit 0.
The unit count includes one child-process harness test that is inert unless
started with its private test environment. The twelve actual SIGKILL cases are
executed by `real_sigkill_and_reopen_at_twelve_cross_media_windows`.
Two additional SIGKILL processes in
`real_paper_effect_receipt_and_blob_reference_survive_or_roll_back_together`
execute the actual trusted `PaperCreate` business command, making **14 real
process deaths** per full unit suite run.

| Actual SIGKILL point | Independent SQLite state on reopen | Recovery obligation proved |
| --- | --- | --- |
| upload-intent committed, before file creation | copying | No reference; explicit abort cleans safely |
| chunk synced, before length ledger commit | copying, prior length | Divergent partial copy is not published |
| private publication copy created, before first write | copying | Empty temporary is tied to upload; original retained |
| first publication chunk synced | copying | Partial temporary is shorter than expected and never reused |
| private publication copy durable | copying | Complete temporary cleans through explicit old-owner recovery |
| copy renamed before directory sync | copying | Original retained; target is an independent verified inode |
| object solidified, before pinned ledger commit | copying | Orphan object recovered only by explicit cleanup |
| pinned commit, before redundant staging cleanup | pinned | No business reference; old upload pin released only when outcome known |
| reference/pin changes applied, before tx commit | pinned | Rollback preserves pin and removes reference |
| reference transaction committed, before caller reply | committed | Reference and bytes survive; upload pin released |
| deleting committed, before object unlink | aborted upload; deleting blob | New acquisition blocked; collection resumes |
| object unlinked, before ledger removal | aborted upload; deleting blob | Collection finishes missing-file case |

Each child was a separate real OS process, paused at a test-only checkpoint;
the parent called `Child::kill`, waited and asserted Unix signal 9. No thrown
exception is presented as process death. Reopen uses a fresh owner epoch and
queries through a separate read-only SQLite connection. Production compilation
contains no test checkpoint environment logic.

Two actual OS-thread Barrier tests use the host's `Arc<Mutex<BusinessStore>>`
single-owner write discipline: GC racing publication preserves either upload
pin or committed reference, and GC after upload-pin release preserves an open
reader until explicit close. Further tests cover wrong-DB transaction tokens,
project/revision/digest binding, trigger-induced ledger failure after physical
solidification, no-overwrite reuse, source-file deletion, read-only lookup,
sticky pending/unknown protection, sparse-file quota boundaries and deleting
state refusing new acquisition.

Actual PaperCreate integration additionally proves the real outcome boundary:
at publication-applied SIGKILL, independent SQLite queries find zero paper,
document, binding, reference and business-history rows, an original pending
intent without receipt and its retained upload pin. Lookup projects unknown;
reconciliation and GC preserve the still-unresolved blob. At
publication-committed SIGKILL those five row counts are all one, the original
receipt is committed and recoverable, the upload pin is released and the blob
is protected by its actual reference. Repeated lookup leaves stored status and
receipt unchanged. This supplements the helper-only cases with actual business
effect/history/receipt evidence.

Equal-content uploads also prove one physical verified object with independent
upload pins/snapshot identities. Symlink fault tests prove staging/object/root
redirection is rejected and outside sentinel files/directories stay untouched.
Pinned-state corruption without an actual persisted pin cannot authorize a
repeat finish, reader or publication.

## Isolated mutation evidence

This section records the initial implementation before the API26 repair. In
particular, the hard-link inode guard mutation is superseded by independent-copy
isolation tests; it is not represented as current copy/rename regression proof.

All P05 mutations ran only under `/private/tmp/muyon-p05-mutation.2NM5PJ`, with
its own Cargo target directory. Shared implementation was never mutated.
Each guard change was tested individually, and the copied source was restored
from the working implementation before the next change.

| Disabled guard | Exact test name under `blobs::tests::` | Observed behavioral failure |
| --- | --- | --- |
| staging inode must have one link before append | failed_ledger_after_solidification_cannot_mutate_content_addressed_inode | append returned Ok(35), expected BindingMismatch |
| uncertain business outcomes retain old upload pins | pending_unknown_never_expire_and_lookup_does_not_recover | reconciled one stale upload, expected zero |
| reader pins block GC | gc_and_reader_barrier_covers_reader_after_upload_pin_release | GC reached unsafe deletion and DB foreign-key refusal, expected protected no-op |
| transaction must belong to owning database | publication_binds_expected_bytes_project_revision_and_real_transaction | foreign-DB token returned Ok(BlobRef), expected InvalidAuthority |
| expected digest/length must match upload | publication_binds_expected_bytes_project_revision_and_real_transaction | wrong expected digest returned Ok(BlobRef), expected BindingMismatch |
| deleting state blocks same-digest finish | deleting_rejects_new_read_or_same_digest_upload | finish returned Ok(FinishedBlob), expected Unknown |

Each command was `cargo test --offline --locked -p muyon-core --lib
blobs::tests::<exact-test-name> -- --exact`, and each returned exit **101** with
an actual failed assertion. During the initial copied snapshot an unfinished
parallel research dispatch lacked its module; that unrelated dispatch line was
excluded **only in the temporary copy** to obtain runnable P05 mutation evidence.
After research wiring completed, all current core source files (including full
research dispatch) were copied back into the isolated workspace; its restored
full P05 unit suite passed **11/11**, including actual PaperCreate SIGKILL.

## Initial diagnostics and pre-API26 review identities

`rustfmt --check --edition 2021 crates/muyon-core/src/blobs.rs
crates/muyon-core/tests/blobs.rs` and `git diff --check` returned exit 0.
`cargo clippy --offline --locked -p muyon-core --lib --test blobs -- -D warnings`
returned exit 0. A broader `--all-targets` attempt found only two then-current
research-lane test warnings (`tests/research.rs:8` unused `Value`, `:409`
cloned-ref-to-slice-refs); these were reported to the parent, not edited outside
P05 ownership. Full-workspace revalidation belongs to integration owner.

Frozen implementation SHA-256 for independent review:

| File | SHA-256 |
| --- | --- |
| `src/blobs.rs` | `1164db981a9aa3ca1dfaab0d8b8b32150a5d4d820b25329d53214ef514156e6a` |
| `tests/blobs.rs` | `4bf097c920deb1a84b70a58a23ce6efab02a93cb69cee898bb1b4a1d706b2ca8` |
| `src/archive.rs` | `436648302dd36ce4ee74a783cc7b82efb2fd1578cd615005c6eafaed62b4655b` |
| `tests/archive.rs` | `40a5065257a60bdeb7c4e248b9cc58a07400787a14d222b49ba0a346f78d0153` |

## Boundaries still open

- Source-file removal is proven on the host filesystem. API26 SAF URI revocation,
  Service death/lease registry, UI picker and Kotlin controlled-stream behavior
  remain downstream device gates.
- Full archive expansion CRC/length checks remain A01 decoder-consumer duties;
  an archive upload being pinned does not certify its research records.
- Process SIGKILL tests do not simulate OS power loss or a dishonest storage device.
- No historical migration, automatic database clearing, PDF parser, network
  metadata extraction, standalone blob database or new dependency was introduced.
