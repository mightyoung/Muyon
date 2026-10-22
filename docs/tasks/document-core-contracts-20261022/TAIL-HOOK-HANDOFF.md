# Shared transaction tail hook and digest correction

Parent's actual combination compile of source `54b45d97` found that the locked
sha2 Digest array does not implement LowerHex. Source correction:
`bf086451d82017f418b1ccbf66d680ad124c8e4e`. It encodes each byte with `{byte:02x}`
instead of formatting the whole digest. This report preserves that real compiler
failure and does not infer a successful new Rust compile from the source fix.

Final production/test source:
`4c6b706f8cf071b14227c5093f0e0b1d65109f43`.
Branch: `task/document-core-contracts-20261022`.

## Gateway integration

On the existing BusinessStore and the same live SQLite transaction:

1. `document_access_in_transaction(tx, access, &[operation])` returns current
   authoritative metadata after checking the real persisted authorization.
2. `document_publish_in_transaction(tx, base, title, format, finished)` performs
   expected-base CAS and immutable revision/blob publication without COMMIT.
3. **New** `document_grant_in_transaction(tx, access, &[operation]) -> Result<(),
   ContractError>` checks the original exact persisted document grant, active
   state, epoch, generation, expiry, operation intersection and current project
   liveness without requiring old base still be head after the gateway's CAS.
4. Gateway writes its receipt/journal and commits once. Propagate all errors and
   roll back everything on any failure. If significant work occurs after step3,
   recheck immediately before COMMIT. No direct document_grants truth access.

All hooks reject another connection's transaction. The new tail hook returns no
bytes/metadata/permit and cannot replace the initial head check or authorize old
revision reads. Gateway owns edit_journal_meta/intents; this author did not edit
its directory or lib.rs. Its published interface
`142c922a44471069f47fbff7b79cf3f1afc1df19` was read before this implementation.

read_document/list_annotations/save_annotation/delete_annotation/export_annotations
also recheck the real grant at their own COMMIT boundary, after validation,
serialization and writes. An expired/revoked grant rolls back sidecar/history
changes. Returned data does not acquire perpetual authorization.

## Tests, review and evidence

Three crate-local hook tests cover own CAS followed by successful tail grant
but rejected old-head read, revoked/expired/generation/epoch/deleted-project/
wrong-operation authority, foreign transaction and wrong document binding.
Two integration regressions use original synthetic SQLite triggers to expire
the grant after history or sidecar mutation and require complete rollback.
There are now 15 document_storage integration tests plus three hook unit tests.

Independent read-only reviewer document_contract_review statically reviewed
bf086451 and then 4c6b706f, found no new blocking issue and confirmed final grant
checks close the initial-check-only expiry gap. It did not execute Rust or modify
files. Publication acceptance still requires actual new-source Rust verification.

Actual commands/results are in
[12-tail-verification.log](persistence-evidence/12-tail-verification.log):
targeted hook/storage tests, full muyon-core test and format check all NOT_RUN,
shell127 because cargo is absent. git diff --check passed. The source SQL smoke
still passes for all 19 source statements and disposable synthetic row reopen,
CAS, revocation, bounds and rollback; see
[11-tail-source-sql.log](persistence-evidence/11-tail-source-sql.log). SQL smoke is
not Rust execution, blob publication, engine validation or a passing TDD cycle.
Parent's existing authorized Rust environment must compile/retest this exact source.

## Explicit unfinished work

- Persistent history/revisions and retained immutable blobs have **no aggregate
  disk quota in this slice**. Row/JSON/read limits are not a bounded-total-store
  claim. Existing blob per-upload/per-file limits remain; historical compaction,
  retention and total workspace storage admission require a coordinated policy.
- Authenticated actor/group provenance and live membership-to-grant issuance
  still need a trusted host adapter. Model-supplied Human/Ai metadata is not
  authenticated by the sidecar value type.
- A reader/derived-cache adapter must use current scope/grant/revision checks at
  byte delivery. Existing blob readers alone do not establish that integration.
- End-to-end gateway receipt atomicity is not verified by this author's isolated
  slice; no third-party engine, user file or native format editing was exercised.

No main/develop write, deployment, fee, credential, permission change, real model/
search request, historical unknown retry or user-file access. Prior raw NOT_RUN
history stays unchanged; Leader B remains sole develop merger.
