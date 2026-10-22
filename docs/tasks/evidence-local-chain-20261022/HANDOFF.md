# MIG16 real store adapter / parent B integration

Verified implementation source: 3296cb8402afd5003279ad443d701dda1fee9f56.
Required core: aec085fafef8aa02f86f2fc60626f168b10f4caa (includes Text).
Original pure delivery: 741274f6ef628501cc8c75c61f156b9f003c81d7.
Apply the new evidence source commit after the original delivery and fixed core.

## Implemented API

```
evidence::store::StoreEvidence::new(&existing_business_store)
  .process(&trusted_document_access, InputKind::Utf8Text)
    -> Result<StoredProcessing, StoreEvidenceError>

StoredProcessing::projection() -> StoredProcessingProjection
StoredProcessing::receipt() -> &ProcessingReceipt
StoredProcessing::source_metadata() -> &DocumentMetadata

StoreEvidence::find_literal(access, processing, query, limit)
StoreEvidence::open(access, processing, evidence_ref)
StoreEvidence::answer(access, processing, body, hits, explicitly_cited_indices)
```

Use under the Service's existing store guard. The concrete adapter supplies the
real DocumentHost privately; callers cannot construct it, pass a bool, substitute
an arbitrary host or extract unguarded cached text from StoredProcessing.
StoreEvidence methods always consult current persistent authority and real bytes.
For wire projection, serialize `processing.projection()` using serde_json. No
body markup controls actions and no automatic [1] citation is created.

## Actual owner boundary

No new core hook is needed. Reuse exact existing methods:
`document_access_in_transaction(tx, access, &[ReadText])`, `open_blob_reader`,
`read_blob_chunk`, `close_blob_reader`. Inspect alone fails; ReadText-only works.

The existing reader-open method starts its own transaction. The adapter first
resolves metadata in a short ReadText transaction, opens its controlled reader,
then starts the final BEGIN IMMEDIATE transaction. That final transaction checks
the registered current head/grant again, reads all bounded bytes using the actual
reader and verifies digest. Parser, source resolution and answer/quote construction
occur under the same final transaction. The private DocumentHost holds that live
Transaction and the actual EOF reader; each resolution checks persistent grant/
head/project and uses core's EOF read to verify live reader pin/generation/epoch.
The preliminary check is never delivery authority. The real lock and final
transaction, not two unlocked preflight calls, provide writer exclusion. Tail
checks cover time-based expiry, then commit. Reader cleanup follows commit or
rollback; cleanup failure returns an error and discards a would-be success.

No transaction, reader or host escapes. Cache reads reopen and verify actual
controlled bytes, bounded at 2 MB. This trades some I/O for current grant/source
checks and does not add an index. Public operations expose no arbitrary callback.

## Processing and saved/index facts

Text requires exact `DocumentFormat::Text` plus explicit Utf8Text and actual UTF-8.
Unknown/contradictory formats and canonical PDF bytes relabelled Text are rejected.
Pdf/Ocr on an actual registered Pdf produce Unsupported without content. The
processor does not claim to be a complete file-format detector or PDF engine.

`muyon.stored-processing.v1` contains:
- `registered_source_snapshot`: actual core metadata observed under the owner
  transaction; historical observation, not a new import/save intent receipt.
- `processing`: actual `muyon.processing-receipt.v1` parser result, including
  immutable source/version/digest and available/failed/unsupported extraction.

There is no synthesized `saved` flag, durable commit receipt or import stage.
Existing import/saved intent owner must supply its actual receipt. ResearchIndex
is not connected; index remains NotRun. A successful parser result cannot make
it searchable/indexed. Original unknown intents/reservations are untouched; no
lookup, retry, cancellation or new business intent is performed by this adapter.

Text anchors are exact UTF-8 byte ranges with quote digest and complete source
identity. PDF page is null for text and non-null is rejected. Current reads do
not use the publication tail to authorize old versions. This adapter deliberately
rejects stale revisions; it never auto-issues historical permissions or rebinds
to latest. Explicit historical delivery would require separately coordinated
current+historical policy and controlled bytes, and is not implemented here.

## Parent B actions remaining

Apply core's `integration/combination-module-exports.patch` only on the designated
combination branch with real artifact/evidence/bot modules present. This task
never edits core-owned lib.rs/documents/blobs source, shell, Service or FFI.

Host/FFI owner must call StoreEvidence under its existing trusted owner guard and
bind real UI actions/receipts to its serialized outputs. This source supplies a
concrete store adapter; it does not claim a Service/FFI call site exists. Rebuild
and test the actual combination with the export applied before claiming native
product integration, Android acceptance or any engine HOLD change.

## Reproduce

Standard pure suite: `cargo test --locked --offline --manifest-path crates/Cargo.toml -p muyon-core --test evidence_local`.
Standard workspace: `cargo test --locked --offline --manifest-path crates/Cargo.toml`.
Real store: `python3 crates/muyon-core/src/evidence/run-store-tests.py --repo /workspace/Muyon`.
All actual core sources + every original core integration target:
`python3 crates/muyon-core/src/evidence/run-store-tests.py --repo /workspace/Muyon --full-core`.

The runner generates only a module entrypoint in /tmp, retaining original module
visibility and referencing actual source files. It adds evidence in that test
entrypoint; no original source is copied/rewritten. Dependency versions/source/
checksum are constrained to the repository lock. This demonstrates actual store
Rust compilation/execution before the owner export is applied, and is explicitly
not a production export or Service integration acceptance test.

Session tools: PATH=/tmp/evidence-rust/toolchain/bin:$PATH,
CARGO_HOME=/tmp/evidence-cargo, LIBRARY_PATH=/tmp/evidence-link. These are disposable
known CI Rust 1.93.1 tools and a symlink to the installed SQLite runtime, not new
product dependencies. Official checksums and failures remain in evidence/.
