# Public controlled reader facade (core owner)

Read provider `098d9aca214e6642c1b3ffde64921ebedbae335d`
READER-FFI-PREPLAN.md and evidence `78cdff32dee68b664c4fe71b4bbd6b81251af5e7`
StoreEvidence. This slice owns documents/reader.rs, tests, documents module
exports and minimal crate-private blob transaction/cleanup seams. No FFI/lib.rs
or evidence-owner files are changed. No grant issuance, arbitrary file path,
engine, text-decoding assumption or annotation save is introduced.

## Host-facing API

`DocumentReaderHost::new(store: BusinessStore)` owns the existing store and a
bounded in-memory session registry; no second connection or authorization cache.
The trusted Service may borrow `store()` for existing public StoreEvidence calls.
That does not expose database() or transaction/grant internals. Service must
derive DocumentAccess from actual host identity/policy, never issue grants from
caller JSON, and serialize this !Sync owner in its existing guard.

- `inspect(access)` returns existing exact persisted metadata under Inspect.
- `open(access, purpose)` returns opaque session ID plus exact metadata and
  actual FileSource/lease. Purpose is only ReadText or Render; Inspect cannot open
  bytes. These permissions allow raw bounded source delivery, not engine support.
- `read_chunk(id, max_bytes)` reads sequentially up to 64 KiB, with current
  scope/project/head/generation/epoch/expiry and actual reader pin/bytes checked
  in the same owner SQL transaction before delivery and at its tail. EOF releases
  the session. No caller authority, path, seek or replacement source is accepted.
- `is_current(id)` checks the same real current binding and lease; invalid
  sessions are closed. `close(id)` is idempotent; `close_all()` handles host
  background/logout/actor switches. Registry Drop attempts all cleanup.
- Maximum 8 live sessions; fixed 15-second idle and 30-second absolute lifetime,
  each source at most existing 30 MiB. Monotonic time is host internal. Expired
  sessions are swept on operations; host should explicitly close on background.
  Cleanup failure never returns successful read data and poisons further opens.

## Controlled evidence adapter seam

`BusinessStore::with_document_source(access, purpose, max_bytes, callback)` is a
bounded one-shot read/processing boundary. Maximum whole-source buffer is 2 MiB.
It supplies a nonconstructible borrowed DocumentReadView with metadata, exact
bytes and request, implementing DocumentHost against the active transaction.
No database or Transaction is passed publicly. The callback is trusted, local
processing only: defer externally visible output until the method returns Ok;
no nested store transactions or I/O side effects in the callback. Callback result
is delivered only after a final live authority/lease check and reader cleanup.
Existing StoreEvidence already has public controlled process/find/open/answer;
its owner may later adopt this seam without replacing exact citation checks.

Publication/candidate validation, historical reads, project-wide document listing,
PFD ownership and Android lifecycle integration remain separate. This API accepts
only exact current references and never substitutes latest or opens history via
tail-grant authorization. New tests and logs are separate from the older candidate
core240/worker48/fmt0 evidence.
