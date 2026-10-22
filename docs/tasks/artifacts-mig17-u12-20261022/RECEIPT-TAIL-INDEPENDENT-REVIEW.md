# Independent review: receipt-tail authorization and Unknown preservation

Separate reviewer: `artifact_review`. Read-only review of production/test changes;
only this review and independent SQL evidence were written. No git commit was
created by the reviewer. Base: `53badad9f6bab5321af3c1409a564184446cc4b8`; branch:
`task/artifacts-receipt-tail-20261022`.

## Assessment

No remaining confirmed static defect was found in the scoped correction. The
reported post-receipt invalidation gap is closed in source: the final receipt
UPDATE now precedes output publication-grant, exact source/history and project
Save checks; no further SQL write occurs before COMMIT. This is **not** a Rust
runtime passing result. Compile, test discovery and Rust behavior remain NOT_RUN.

The earlier WORKFLOW-INDEPENDENT-REVIEW did not exercise invalidation caused by
receipt UPDATE triggers. This review supersedes that assessment of tail coverage.
The former SQL tests established atomicity but did not establish last-write
permission validation.

## Code and control flow reviewed

- On revise, the output document head has already advanced through the authorized
  CAS. Therefore the output tail uses `document_grant_in_transaction` with the
  original binding and ReadText + StructuredEdit; it does not misapply a current
  head read check or turn the publication hook into historical permission.
- Sources are checked against `record.sources` through
  `artifact_authorize_snapshots`: current source access is freshly resolved and
  each exact old snapshot requires the real core-owned historical policy hook.
  Metadata equality prevents replacing the archived source with latest metadata.
- Project Save permission is rechecked after these guards. All three final checks
  run after the receipt UPDATE, which is the final write.
- `ArtifactSaveFailure::ReceiptTail` distinguishes late invalidation from a
  determinate semantic failure. Returning from the effect closure first drops
  its Transaction, rolling back document/blob/artifact/receipt/grant writes.
  Failure projection then returns Unknown + QueryOriginal without journaling a
  Rejected row. A zero-row receipt UPDATE follows the same uncertain path.
- `requires_original_lookup` includes Unknown and storage errors. Public submit,
  lookup, effect failure handling and rejected-row validation use it consistently.
  A future effect hook returning Unknown before receipt publication therefore
  keeps the original pending row; it cannot become a durable business rejection.
- After the durable pending phase, repeat submission still returns its projection
  before effect dispatch. Removing the synthetic trigger or restarting does not
  authorize rerunning the pending save. Lookup performs no recovery write.
- No empty trait, success stub, automatic historical grant or model/search call
  was introduced. Human-edit protection and canonical document truth remain on
  the existing effect path.

## Test-source review

Two new Rust test functions were read; no Rust tests were executed:

1. Ten real `AFTER UPDATE` receipt-trigger mutations: output and source grant
   withdrawal/expiry/generation; exact source history policy withdrawal/expiry/
   generation; project grant withdrawal. Assertions cover Unknown/QueryOriginal,
   no receipt, document metadata/revision history, artifact history, blob refs,
   upload status, blob pins and pending journal rollback. They also remove the
   trigger, reopen and resubmit the original intent without reexecution.
2. Unknown injection into the real production failure dispatcher checks pending
   rows remain unchanged and lookup remains Unknown. This validates the intended
   dispatcher contract in test source; it is not a real engine Unknown test.

Static inspection found no obvious ownership, error-conversion or visibility
compile defect. This does not replace actual compilation. There is no supported
RED-to-GREEN claim: both cargo attempts exited 127 because cargo is absent.

## Independent SQL execution

Command:
`python3 docs/tasks/artifacts-mig17-u12-20261022/independent_receipt_tail_sql_check.py`

Final evidence: `evidence/receipt-tail-independent-sql.log`.

The independent script extracts actual schema, publication and grant-query SQL;
creates a temporary on-disk synthetic SQLite database; runs all ten receipt
AFTER UPDATE mutations; executes exact source grant queries; verifies every
mutation is detectable; then rolls back and compares document revisions, blob
refs/uploads/pins, artifact revisions, receipt and grant tables with their prior
state. Reopening retains the original pending/no-receipt row. All these SQL
checks passed.

The script deliberately performs the rollback after detecting the SQL row
invalidation. It does **not** execute Rust Transaction Drop, source metadata
comparison, tail-check ordering, Unknown dispatcher or duplicate submission.
Those claims remain static review only or Rust NOT_RUN.

The first independent script attempt failed because its DDL extractor regex
incorrectly excluded the letter `n`, leaving no projects table. The corrected
script passed. That review-script failure is retained separately in
`evidence/receipt-tail-independent-initial-attempt.txt`; it is not a production
or Rust failure.

## Remaining acceptance blockers and source custody

Rust compilation, targeted/full offline tests and formatting remain NOT_RUN
(toolchain absent). The designated core owner still controls module-export
integration; host/UI wiring is separate. Source delivery and SQL evidence do not
prove the product flow works. Forms are paused; no new forms implementation was
included in this review. Original unknown requests and held-cost reservations were not
read, changed or retried.

Reviewed SHA-256:

- save_journal.rs: `7364454b2788d71696581e1d85a3ffe381adfe6b0c48c5193e025b762e1714d8`
- workflow_tests.rs: `ab940c385a9b42c2653792cd7a5db6e569e516de8d71df3f2ed3c3b95cb4cfc3`

Acceptance remains HOLD pending real integrated Rust execution.
