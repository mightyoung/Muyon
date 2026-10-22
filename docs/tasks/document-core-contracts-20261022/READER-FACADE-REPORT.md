# Controlled read facade handoff

Interface-first: `e177a9008b1cae103f99809b4ce64ebef0fdeb2d`.
Final fixed Reader source: `b3592e9bc1b0d9c3c52800e5ec1f566e36b8a297`.
Branch: `task/document-core-contracts-20261022`.

## Public entry points and real behavior

Use `muyon_core::documents::reader::{DocumentReaderHost, DocumentReadPurpose}`.
No lib.rs or FFI edit is needed to access this existing documents module export.
The host moves its existing BusinessStore into DocumentReaderHost, keeps it under
the existing Service guard and uses `store()` to borrow existing public evidence
adapters. No alternate database, grant cache or caller-controlled authority issuer
was added. The facade accepts exact DocumentAccess from the trusted host policy;
wire JSON is not authority. Session IDs never become file paths.

`inspect` checks actual Inspect permission; `open` separately checks actual
ReadText or Render. It returns an opaque ID, exact metadata and FileSource with
the real reader lease. `read_chunk` is sequential, bounded to 64 KiB, checks the
same document revision, live project, persisted grant generation/epoch/expiry,
actual reader pin and whole held-file hash before and after reading. A final
grant/head check follows potentially slow hashing. It delivers raw bytes, not a
PDF/Office renderer, UTF-8 interpretation or capability-engine assertion.

At most eight sessions are live, each source at most 30 MiB, idle lifetime 15s
and absolute lifetime 30s using internal monotonic time. Session operations sweep
expiry; is_current does not renew idle time. The host must close_all on logout,
identity switch or background/PFD disposal. No seek, historical source fallback
or model-supplied path exists. Metadata inspection alone cannot authorize bytes.

EOF and invalid sessions release their real pins. close is idempotent; close_all
attempts every session; Drop attempts cleanup before destroying the store. Cleanup
failure withholds successful data and poisons registry reads/opens, preserving
the actual reader solely for explicit cleanup retry. A permanent storage failure
may still leave conservative pins for owner-restart reconciliation; successful
cleanup is not fabricated. Full-file rehashing at each validation is conservative
and can be expensive on large sources/small chunks; there is no performance claim.

## Evidence processing seam

`BusinessStore::with_document_source(access, purpose, max_bytes, callback)` bounds
the whole-source buffer to 2,000,000 bytes, checks its actual hash and invokes a
trusted local callback with DocumentReadView. The view exposes metadata, bytes,
the exact ReadRequest and a DocumentHost implementation backed by the active
owner transaction. Database, Transaction and grant helpers remain private.

The pin is inserted and removed in that same SQL transaction. The callback result
is delivered only after a final live view check, pin cleanup and commit. Errors or
panic roll back its newly inserted pin. The callback must do local computation
only, avoid nested store transactions and defer external output until Ok; it is
trusted host code, not an untrusted execution sandbox. Its borrows do not escape
the transaction as a reusable authorization object.

Existing StoreEvidence public process/find_literal/open/answer remain the evidence
owner's implementation. This seam is available for its adapter; this branch does
not copy it, add fake citations, claim Text support from PDF bytes, or wire FFI,
host PFDs, annotation saves, Android lifecycle or an evidence result cache.

## Tests, review and remaining verification

Thirteen original synthetic Reader tests cover metadata/actual bytes/EOF;
Inspect-only and foreign scope denial; revocation and changed head; generation,
epoch, expiry and project deletion; session cap/idle/absolute life/chunk limits;
deleted pin and equal-length corrupt bytes; oversized blob ledger projection;
one-shot live view/size/tail; callback and cleanup rollback; cleanup failure
withholding followed by explicit retry; host Drop; post-pin authorization failure;
and SQLite deferred-constraint COMMIT rejection mapped conservatively to Unknown.
The COMMIT fault is not a claim to simulate an already-durable unknown response.

Separate read-only review on 09099780 and final test-only b3592e9b found no static
blocking issue or obvious borrow/type failure; the recommended post-pin/commit
fault cases were added. Evidence is in reader-evidence/INDEPENDENT-REVIEW.md.

`reader-evidence/01-test-first.log` and `02-fixed-source-verification.log` retain
raw attempts. Targeted Reader tests, complete core package and scoped rustfmt are
all **NOT_RUN (127)**: cargo/rustfmt absent. `git diff --check` exited 0. Actual
compilation, full worker combination, format and execution acceptance are pending
in the authorized Rust environment. Earlier reported candidate core240/worker48/
fmt0 covers the previous source only and is not reused for this change. No engine,
real model/search request, user file, paid service or old unknown action ran.

## Separate old-combination Clippy patch

Independent branch `task/document-storage-clippy-20261022` is based exactly on
B's `82169330ff6868b5979e351056d538dd496e9519`, not this Reader/candidate branch.
Its fixed commit `8f24e8f5384489e2ee7d86b8494ee1ca47c0cd8b` changes only one line in
tests/document_storage.rs: repeat(' ').take(n) becomes repeat_n(' ', n); byte count,
padding and assertions are unchanged. Independent static review and diff-check
passed; no lint allow was added. B may take that one commit without Reader code.

Rust's official API docs mark repeat_n stable since 1.82.0:
https://doc.rust-lang.org/std/iter/fn.repeat_n.html . B's STRICT-GATE-REMAINING.md
records its actual strict gate uses Rust 1.93.1, which supports that API. These
workspace manifests declare no uniform rust-version/MSRV; no lower unsupported
MSRV is asserted. Actual strict Clippy rerun remains B's fixed-source gate.
The independent branch's exact one-line diff, base and NOT_RUN strict command are
recorded in `reader-evidence/03-clippy-minimal-fixed-source.log`.
