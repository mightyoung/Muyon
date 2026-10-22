# Real core private candidate prepare/query bridge

Owner branch task/document-edit-transactions-20261022, baseline156e49c5e97ff13a09ce2626bc64f3a1b60e0f8f.
Source commit 57c326a5ba790ccca44e25a0a7ebbe9cf9604eee.
Exact core initially b49ed859c331b4bd8004d8d3be5b8e12e7c7ff3e, then
8802bf555bfce1265296318d83a2f8a1fb2b787e (same production, added160-reservation
pagination test). Read actual CANDIDATE-INTERFACE/REPORT and candidate.rs/blobs.rs.
No owner-file/worker/lib/FFI modification. Temporary library export only as before.

## Final fixed-dependency result (supersedes earlier worker blocker)

Locked actual core faeef3aec3a9407d7c15490dcdb33866413e7453, source
cab23b69b2aa56f55f3b44e0fe248f026da9c08d. Read WORKER-COMPILE-FIX-HANDOFF.md;
owner adds real documents module to worker, preserves GC policy, formats source.
Our production source57c326a5 remains byte-identical. Verifier now defaults to faeef.

`bash docs/tasks/document-edit-transactions-20261022/verify-durable-combination.sh -p muyon-core`
actually exited0 (raw13), **321 passed,0 failed**,25 distinct target summaries including
0doctests. Library49 and worker48 duplicate some same-source tests, so this is321
executions, NOT321 unique behaviors. New real Cargo bridge target8 passed within321.
Raw14 worker `cargo check --offline --locked ... -p muyon-core --bin business_worker`
exit0. Raw15 exact seven changed core files scopedfmt skip_children=true exit0;
our ownedfmt12exit0. Raw16 has per-target counts,17 fixed source SHA256/env.

Fresh independent reviewer repeated entire core321/0fail, Cargo bridge8, worker check
and scopedfmt; independent5 probes passed, no Important. Final source/probes/raw logs
under bridge-evidence/independent-core-bridge-final/. These overlapping results are
not summed. Original8802 worker E0599 failure02/09 is preserved unchanged and now
actually resolved by the owner fix, not bypassed by the library-only fallback.

Core production unused methods and worker CandidateState/CandidateStatus re-export
warnings remain in logs; this is NOT zero-warning or strict-Dwarnings completion.
Raw18 full workspace still exits101: cargo-platform0.3.3 requires Rust1.91/current1.90.
Flutter remains NOT_RUN. No dependency/toolchain update or engine execution occurred.


## Connected behavior

`EditedCandidateJournal::prepare_core_candidate_trusted(binding,access)` now obtains
ONLY the actual frozen local candidate bytes. It requires original source/head,
current read+edit grant, exact fresh confirmation, CandidateUnvalidated and no cancel.
It persists an invocation claim in edit_candidate_core_claims on the SAME BusinessStore
connection, with grant/confirmation tail check, BEFORE calling core private preparation.
The claim is not a core receipt or mirrored publication/validation truth.

operation_id=`op:<whole patch digest>` (not just the original intent label). That
patch digest already binds full version/policy/true format/source/locator/operation/
intent identity. Deterministic candidate_id also hashes full binding+expected blob
hash/length. Core result must match exact candidate ID, operation ID, DocumentRef,
expected hash and byte length. Core actually writes/hash/fsyncs private bytes and
pin using its own reviewed APIs. No arbitrary caller path, fake pin or new authority.

`lookup_core_candidate` resolves real original core journal/pin/object facts under
current ReadText+StructuredEdit and exact original source. Fresh grant may query
without adopting the old execution confirmation. Both live source/grant and claim
consistency are checked again before delivery. A source-head change is not replaced
by latest. Existing invocation always queries; missing core row returns expected
preparation metadata with PreparationUnknown, never invokes prepare again. This
covers a crash between gateway claim and core reservation as well as core Unknown.

SQL CandidateUnvalidated and core SealedUnvalidated remain distinct facts. First
records local bounded bytes; second requires actual core sealed object+pin inspection.
Neither is Validated/Committed or Office success. Duplicate stage returns the OLD
candidate; a test supplies different new bytes and checks old receipt/hash/actual
object, preventing a false claim that the new payload was saved. Both publish gates
remain hard-disabled; no model/provider/search or third-party engine is called.

Cancellation known before the new invocation blocks it. Cancellation/expiry during
in-flight preparation may retain real private bytes/pin. They are not rolled back
by SQL rollback; recovery only queries. Core currently has no gateway cancel callback,
so no claim of immediate physical interruption is made. No source/ref/revision changes
or success receipt occur; canceled bytes cannot be delivered by edited journal gate.

## Earlier checks (fixed8802, retained history)

- Raw01 exactb49 core candidate unit12 actually passed, not author's cargo127.
- Raw04 exact8802 candidate13 actually passed, including new160-reservation keyset GC
  test across128 rows/project quotas. Its count is a subset of library49, not additional.
- Raw05 exact8802 full library49 passed. Full crate Cargo gate09 exit101 at compile:
  business_worker/blob calls document_candidate_upload_retained and
  document_candidate_reserves_digest without documents module. Parent/core owner
  already coordinating a fixed worker assembly; this worker does not bypass it.
- Explicit fallback07/08/10 builds ONLY the real core library with cargo build --lib,
  then rustc --test links our integration test to the same actual rlib/deps. Final8
  tests passed (real new-byte object+pin, source unchanged, original query/restart,
  no core-row claim, late seal fault, expiry after pin, cancel/revoke-before-write,
  identity/corruption, fresh first confirmation). This is NOT Cargo bin gate PASS.
  Reproduce: `python3 docs/tasks/document-edit-transactions-20261022/verify-core-bridge-direct.py <exact temporary archive>` with same tool env as SCHEMA2-REPORT.
- Independent reviewer: library49/49, direct original6/6 and4 negative probes passed;
  fresh reconfirm cannot resume no-core-row claim, pin removal returns Unknown without
  repair, claim/core hash corruption rejects, canceled sealed pin is retained without
  byte delivery/publication. No Important finding. Own unused CandidateStatus import
  removed; reviewer raw source/probe/logs in bridge-evidence/independent-core-bridge/.
- Owned rustfmt12 exit0; scripts bash/py_compile passed. Exact source/environment11.
  Library production dead-code warnings from unchanged core are retained; no strict
  Clippy/workspace-green claim. Raw06 fallback initially had wrong dependency search
  directory (debug instead of debug/deps), corrected07; it is a harness error, not a
  product test failure. Raw02 includes missing new API RED AND upstream worker errors.

Whole workspace Rust1.91/current1.90 and Flutter NOT_RUN remain from prior slice.
Actual Office parser/read-side provenance, eligibility/validation/license/isolation,
full engine execution and different-bytes publication remain HOLD. The new bridge
adds real private object prep/query only. Retention/journal/global disk quota remains
separate from per-project core32/128MiB and own8MiB/150MiB journal caps; multiple
physical copies are not a promised total disk bound. No unknown write is retried.

## Immediate B Clippy deliverable

Source-only fix for OLD90b7 combination is on independent branch
`task/document-edit-clippy-20261022` at
0e325011d6eb66962669aac284cdccf5fa0685e9 (gateway2lines ONLY). Evidence/report head
69988f01278b9506e04d24090387022306afa720;53 tests and ownedfmt passed. Independent
static confirmation, no allow, no new edited/schema2/core dependency. This source
commit is the one B should cherry-pick; main branch's8b80fad0 also touches new module
and is not needed for old B. No self-merge/main/develop/force-push/deploy performed.
