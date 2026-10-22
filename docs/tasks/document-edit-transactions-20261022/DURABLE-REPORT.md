# DOC06/08 durable COPY delivery

Branch: `task/document-edit-transactions-20261022`. Preserved prior independent
review baseline601f562f98163429103b344aecb3d8639c890a82. Source commit:
4e041abf5ba8b2f7d541a3feb2cfb7c715da80ca. See FINAL-HANDOFF.md. No merge or changes to main/develop/UI/business/lib.rs.
Core dependency actually compiled: a27f04aa2460971940d4bdf2c8263bdf81f381c2.
Core clone production: f6ab7fd78f46319cf46e9754d80c7cf0f6781205.
The later pure core formatting commit93de8ad99fad105bc3ca32036de30803d87fd6c7
was advertised but is NOT part of our exact tested source or claimed formatting.
UI remote advanced to74a39791774f85514a03b0a578ecff788e048130; fetched and checked:
no overlap with owned source/tests (evidence65). Original fixed UI base is retained.

## Delivered behavior

Real BusinessStore SQLite journal on the same owner connection, lock and
BEGIN IMMEDIATE: prepare -> authentic bound confirmation -> durable copying claim ->
bounded persisted original-byte candidate -> SHA256/length validation -> durable
publishing claim -> same-transaction immutable blob reference clone, checked-next
metadata CAS, original receipt and terminal intent write. Final real grant-only
recheck follows the last receipt write and view construction immediately before
COMMIT. No new grant implementation or duplicate document revision truth table.

Publication uses the core-owned `document_clone_in_transaction` and blob-owner
helper. It creates a new revision and reference to the same immutable source bytes.
It does not create uploads, staging, files, engine output or a differently edited
candidate. The explicit CopyReceipt.operation is ByteIdenticalCopy. Different-hash
candidates reject even if the stored candidate digest was also changed. Actual
candidate bytes are stored as bounded hex TEXT (30MiB per source; aggregate150MiB)
with bounded SQL metadata reads and repeated live ReadText checks. This is COPY
persistence and publication, not Office parsing/fidelity or comprehensive editing.

Bindings freeze full Scope, DocumentRef/source revision/format/blob/title, plan
hash and original intent. Old confirmations, different binding, source CAS changes,
revoked/expired/changed generation or epoch, missing validation and damaged source,
candidate or receipt fail closed. A new authentic confirmation may renew a known
stage after reopen, never an uncertain in-flight operation. Receipt validation also
checks exact frozen title (last independent P2 fixed with behavioral RED60).

Original intent queries require a current real Inspect grant. Byte delivery separately
requires current ReadText over the same blob; permission for different newer content
cannot reveal an old candidate. Same-intent duplicate returns original receipt or
Unknown, never replays a copy/publication. Durable copying/publishing uncertainty
survives restart and is query-only; recovery does not infer failure or retry effects.
Cancellation records local intent and cannot erase a receipt or roll back a commit.
Rollback in the earlier contract is a newly confirmed increasing-revision transaction;
this COPY gateway has no real engine rollback/export pipeline and claims none.

Schema1 XLSX numeric request mapping binds actual host metadata and full operation;
response validation has Result<Infallible,...> and cannot produce authority/success.
Fake, simulated, wrong/unknown/duplicate version/key/identity/hash and expired requests
reject; opaque manifest/oracle payloads reject until reviewed typed consumption.
All real engine routes remain HOLD/UnsupportedOperation. Read upstream77a000 and
schema2 fixed6b796c8d6e094d45ef25e28698048c21ef0ae7b3. Schema2/DOCX/PPTX are rejected,
not downgraded. Hidden/protected/merged eligibility and expanded-tree-json-v1 golden
cases remain future integration gates. No launcher or third-party code was copied.

## Actual verification

Toolchain rustc/cargo1.90.0, cached locked dependencies, system SQLite link through
local alias; details and exact source hashes in evidence64. No added dependencies.
The script archives exact core a27 into a temporary directory, copies our owned
source/tests, adds `pub mod document_edit;` ONLY to temporary archive lib.rs, and
runs offline. Working tree lib.rs remains untouched; permanent export belongs to
core owner. Our branch alone is an owner-isolated patch, not a standalone merged build.

```bash
export CARGO_HOME=/workspace/document-edit-tools/cargo-home
export RUSTC=/workspace/document-edit-tools/toolchain/bin/rustc
export RUSTDOC=/workspace/document-edit-tools/toolchain/bin/rustdoc
export CARGO=/workspace/document-edit-tools/toolchain/bin/cargo
export RUSTFLAGS='-L native=/workspace/document-edit-tools/native'
export CARGO_TARGET_DIR=/workspace/document-edit-combination/crates/target
bash docs/tasks/document-edit-transactions-20261022/verify-durable-combination.sh -p muyon-core
```

- Final actual full core: exit0, **243 passed,0 failed,0 warnings**,21 distinct target
  summaries (including0 doctests), evidence61. Gateway19, protocol6 and memory28 are
  subsets of243, not additional totals. Core unit28 includes protocol expiry and
  dependency clone/storage tests. No upstream fake-test count is included.
- Final independent reviewer: exact same gateway/protocol hashes;86/86 integration
  (19+6+28+15+18),28/28 library unit,4 gateway+1 protocol independent probes passed.
  No remaining blocker found. Probe checks physical object/staging/inode/mtime,
  active/expiry/generation/epoch receipt-tail trigger rollback, Inspect-only recovery,
  and corrupted receipt title on lookup/late-copy/duplicate-commit. Raw source/output
  under evidence/independent-durable-title-final/. Counts overlap full core; do not sum.
- Owned rustfmt check exit0 (evidence63). Dependency a27's later advertised pure
  formatting patch was not silently added. No claim of workspace formatting success.
- Full workspace attempt exit101 (evidence62): locked cargo-platform0.3.3 requires
  Rust1.91, current1.90. No dependency downgrade or toolchain expansion in this batch.
- Flutter/full application gate remains NOT_RUN: Flutter unavailable (original
  evidence06). No UI/FFI/agent product integration test or real Office round-trip ran.

## Tests first and preserved failures

Raw35-65 include initial API/compiler blockers (NOT behavioral RED), actual behavioral
RED38/43/45/48/55/56/60, then green39/44/46/49/51/57/61. In particular55 fails on
old upload path and56 fails historical-candidate byte disclosure; clone hook and
current-blob check close these.59 was a test fixture mistakenly opening SQLite
read-only, not a product failure; fixed test then60 demonstrated the real title bug.
Independent durable-final contains original title finding; durable-title-final/tests.log
used an old mixed combination tree and is explicitly superseded by exact-tests.log
and source-note.txt. Preserve all failures; none are relabeled success.
Original historical mutation scripts/results belong to the earlier in-memory batch;
they were not rerun or counted as coverage for this durable batch.

## Remaining integration boundaries

Leader B/core owner must integrate exact dependencies and permanent lib.rs export;
no self-merge performed. Host actor/group/admission and model tool/UI routing are not
connected. No real Office engine admission or edited-candidate publication exists;
license/environment/format-specific validation and real receipt consumers remain HOLD.
The clone API cannot publish different bytes and must not be used to claim editing.
There is no automatic Unknown replay, cleanup/compaction policy or durable rollback/
export product integration. Unknown rows retain bounded candidates for explicit owner
reconciliation. Final-time authorization is checked, not a promise of future access.
Full workspace MSRV and missing Flutter remain explicit gates. No real model/search,
user file, paid operation or old unknown request/reservation was touched.
