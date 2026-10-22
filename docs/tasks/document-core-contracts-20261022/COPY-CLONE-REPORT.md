# COPY-only reference clone source handoff

Base: `f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac` (existing formatter output
preserved; no wholesale formatting rollback).
Interface/assessment published first:
`8d6cc642086fcdd12889aa22fec77797dd6c56e2`.
Final production/test source:
`f6ab7fd78f46319cf46e9754d80c7cf0f6781205`.

## Delivered code and transaction boundary

New crate-local BusinessStore methods:

```rust
document_clone_in_transaction(
    tx: &Transaction<'_>, base: &DocumentRef, title: &str, expected_blob: &BlobRef,
) -> Result<DocumentMetadata, ContractError>
clone_blob_reference_in_transaction(
    tx: &Transaction<'_>, project_id: &str, target_id: &str,
    expected_blob: &BlobRef, new_reference_id: &str,
) -> Result<BlobRef, ContractError>
```

Both reject foreign transactions and never commit. The document hook verifies
exact authoritative current base and source BlobRef, preserves source format,
checks revision overflow and performs expected-base CAS plus immutable revision
INSERT. The lower hook requires a live same-workspace project, an existing
same-project reference to an exact ready blob, validates physical file/length/hash
through the existing NOFOLLOW verifier, and only INSERTs a new reference.

No upload, staging file, pin conversion, object write, overwrite, new DB/schema,
SDK or third-party engine. Original references, revision rows and file bytes are
retained. SQL errors require caller rollback of the whole transaction, including
any newly inserted reference; neither low-level hook grants user authority.

Gateway must use the SAME BusinessStore transaction for:
initial document_access_in_transaction → exact COPY binding → clone → durable
gateway receipt → document_grant_in_transaction → one COMMIT. The tail grant
check belongs after receipt work, immediately before commit. Actual combined
gateway implementation and end-to-end receipt tests remain its owner's work;
this author's synthetic receipt-constraint test is not that production gateway.

**COPY means a new revision of the same document with identical content digest
and format.** It is not a separate file, edit, rendering, semantic validation,
format conversion or complete Office feature. An edited candidate cannot be
passed to this source-only API. Receipt/UI labels must retain this limitation.

## Tests and independent review

Six new synthetic same-owner tests in documents/storage_tests.rs cover:

- byte identity, format/next revision, retained original data and no upload/pin/
  staging changes;
- rollback after a synthetic late receipt constraint failure;
- wrong source digest/length, stale base and both hooks' foreign transaction;
- cross-project, unready/missing reference and duplicate reference;
- actual synthetic file tampering/hash mismatch and missing object;
- post-reference metadata failure rollback and checked u64 revision overflow.

Test source was added before implementation. The attempted targeted command
before code was NOT_RUN, shell127, cargo absent. Subsequent all document unit
tests, full core and three-file rustfmt checks were also NOT_RUN. Raw commands
and results: [01-test-first.log](copy-clone-evidence/01-test-first.log) and
[02-verification.log](copy-clone-evidence/02-verification.log). git diff --check
passed. New-source runtime behavior/formatting is not inferred from prior
183-test results, formatter evidence, or static review.

Separate read-only reviewer document_contract_review examined fixed f6ab7fd7
against f4a8e8d, confirmed source/transaction/hash boundaries and six-test static
coverage, and found no blocking logic, permission, transaction or statically
confirmed compile issue. It did not run Rust, modify files or install tools.
Conclusion: static review passed, actual Rust compile/tests remain NOT_RUN.

## Actual edited-candidate plan and limits

[COPY-CLONE-INTERFACE.md](COPY-CLONE-INTERFACE.md) records the proposed follow-up:
persist a scope/operation/base-bound immutable candidate object and durable pin
as preparation with its own recovery status; then authorize/validate the exact
candidate, CAS, convert pin→reference, write the original-intent receipt/journal,
tail-check authority and COMMIT in one shared SQL transaction. Preparation must
never be reported as document success. Failure preserves the original and the
prepared pin; an unknown final commit is query-only, never replay. Orphaned
preparation and engine crashes require a separate retention/quota/reconciliation
policy. There is no claim that filesystem preparation and SQL publication become
one atomic operation, nor that this edited-candidate protocol is implemented.

Persistent aggregate history/blob quota, actor/group authentication, reader/cache
byte-delivery authorization and actual engine safety/license/fidelity gates remain
unfinished. No user files or third-party engines were used. No main/develop,
gateway, Android or lib.rs edits; no force push, merge, deployment, paid action,
credential/permission change, real model/search or historical unknown retry.
Leader B remains the only develop merger.
