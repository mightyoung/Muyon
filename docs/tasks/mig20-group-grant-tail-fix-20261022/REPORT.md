# MIG20 parent Important: authority/rejection tail fix

Outcome: **fixed for the two reported local mutation findings**. Fixed base `ecef00d8b296930bd40ad8f1ed06890fd7b8a7fc`; independent branch `task/mig20-group-grant-tail-fix-20261022`. New UI/FFI/gateway work was paused and is not mixed into this patch.

## Vulnerable path and preserved contract

`execute_group_local` formerly performed group_effect, then its last group_authority read, then wrote events and a committed receipt, and finally consumed a grant without matching expiry or auditing the post-consumption state. A SQL trigger on those later writes could expire the grant or invalidate the project/group scope while still obtaining a committed local result. Ordinary generation/epoch/revocation cases were already rejected by the old WHERE; they are retained as regression controls so a consumed-looking active=0 row can never be mistaken for proof of consumption by this transaction.

The error branch formerly ignored rejected UPDATE row count. RAISE(IGNORE), changed pending state or a receipt-tail trigger could leave no terminal journal record while the caller received Rejected. Original-owner read failures were also overclassified: request_chain errors became a definite local rejection, and request_conversation storage errors were mislabeled NotFound.

The local security invariant is that an exact live original local grant and current workspace/project/group must still authorize the final business write, this very transaction must consume exactly one matching active grant, and every returned terminal result must have its exact persisted original receipt. Failure/uncertainty cannot manufacture Rejected or discard the original Unknown/hold. Legitimate registration, task-local modes/leaders, handoff/stop, duplicate historical receipt lookup and definite refusal of a handoff with a positively observed unresolved original remain supported. This patch does not create external execution rights.

## Narrow shared-boundary repair

Only owned `crates/muyon-core/src/group_runtime/store.rs` and `tests/group_runtime_store.rs` are changed, plus this task's plan/review/raw evidence. No lib.rs, FFI, BusinessStore/AgentOwner owner file, documents, schema, Cargo dependency/lock, UI or host/gateway edit.

1. The actual active grant is read in the effect transaction with a private expiry witness. It must belong to the local grant namespace (`admission_id IS NULL`) and have a canonical u64 expiry strictly after the current time. The expiry is compared exactly; there is no TEXT ordering or signed SQLite CAST.
2. After the events and committed receipt writes, final consumption rechecks the witness and matches grant ID, generation, owner epoch, binding digest, original expiry, NULL admission and active=1. The live Transaction must belong to this BusinessStore Db, and the UPDATE must affect exactly one row. Merely reading active=0 is never accepted as consumption proof.
3. After the consumption write and its triggers, only reads follow: complete consumed grant identity/expiry, current project and actor scope, newly persisted group scope/revision/record, exact committed original intent receipt and exact event are audited, then that same transaction commits. Register also checks the new group, rather than only its pre-creation actor assertion. Authority/scope failure rolls back effect/event/committed receipt/grant together.
4. The Rejected path updates only the exact scoped/bound pending intent and requires exactly one row. It reads back the exact original terminal receipt before COMMIT. Suppressed/changed/tampered/failed/uncertain rejection persistence returns PendingOriginal, with no definitive Rejected assertion. A real SQLite COMMIT failure follows that same conservative path.
5. Mutation callers treat failed request-chain reads as inconclusive (PendingOriginal). Original identity reads map only the actual owner's explicit `agent_request_not_found` to NotFound and explicit invalid identity to InvalidIdentity; storage failures remain inconclusive. A positively observed unresolved conversation still gives a definite local handoff refusal while the original request remains Unknown. No AgentOwner mutation, settlement, retry or release is invoked.

These checks close the validation-to-use gap at the shared local transaction tail, including triggers on the final consumption itself. They do not certify arbitrary trigger-induced changes to every possible unrelated business row or guarantee a cross-database external execution transaction.

## Ordered verification / independent review

Pre-patch investigation inspected the implementation, direct callers, native SQLite transaction/changes semantics and existing BusinessStore effect-tail precedent. A fresh read-only investigator independently confirmed the boundary and canonical expiry constraints. This was followed by a single fresh bypass/regression review, with same-cycle repair/recheck of its confirmed additional original-identity storage-error route.

Test-first raw output:

- Initial tail/rejection matrix against ecef behavior: **42 passed / 16 failed**, exit101 (`01-tail-red.log`), including commits after expired grants/project/group invalidation and fabricated Rejected without a durable terminal receipt.
- After the first tail repair: **58/58**, exit0. Added original chain-read fault regressions then produced **0 passed / 2 failed**, exit101 (`03-request-read-red.log`), followed by **62/62**.
- Independent reviewer reproduced identity-read Storage → NotFound → persisted Rejected. The native regression also failed before repair (`05-independent-identity-red.log`). The repaired frozen candidate preserves PendingOriginal, durable `[pending,NULL]`, and unchanged original owner observation/hold.
- Final store harness: **65/65**, exit0 = **47 group-store tests (17 previous +30 new) +18 repeated existing source-module tests**. The new cases include events/receipt/consumption trigger matrices, suppressed/tampered rejection, Register scope validation, original-owner chain/identity read faults and two actual deferred-FK COMMIT failures. The latter exercise COMMIT itself in both success and rejected transactions and verify rollback of stop/revision/receipt/event/grant.
- Independent final main harness: **65/65**, exit0; original independent identity fault reproduction recompiled unchanged and now passes **1/1**. RED, GREEN, historical harness/manifest and frozen reviewed hashes are archived. See [INDEPENDENT-REVIEW.md](INDEPENDENT-REVIEW.md).
- Fresh original runtime **20/20**, governance **21/21**, -D warnings standalone compiles, and rustfmt check all exit0.
- Fresh whole locked/offline muyon-core suite: **253 passed / 0 failed**, 18 test binaries plus 0 doc tests, exit0. The 18 source-harness repeats are included in that execution count; this is not 253 new group cases. Two existing dependency read/write extern warnings remain; no newly introduced store warning.

Fresh final commands, UTC timestamps, exits and frozen implementation/test/lock hashes are in `evidence/final-manifest.json`, and were checked against the final files. Earlier pre-final full-suite output is retained with `intermediate-` prefix; it is not used as final-candidate proof. Raw failures are retained without formatting. Authored-file staged whitespace check and full raw-evidence exceptions are recorded separately in staged-check-status.json. Reproduction snapshots that import current production paths are identified as historical test inputs, not frozen old production implementations.

## Remaining limits / NOT_RUN

NOT_RUN: new UI/configuration/FFI wiring; canonical request binding/RunLedger or sole gateway integration; live external Agent/model/search/provider calls; paid requests, production settlement or historical unknown lookup; Android/device/remote CI terminal checks. Deferred-FK tests prove actual local COMMIT failure handling; arbitrary OS/device failures at every commit timing are not claimed exhaustively tested. External execution gates and engine isolation remain unchanged. The historical two Unknown requests and ¥0.002620 hold are untouched; all owner fixtures and PDF/project data here are synthetic temporary databases.

No main/develop write, force push, deletion, deployment, paid configuration, credential change, security permission expansion or protected-owner edit. No automatic approval denial or mutation with an uncertain outcome. Publish only the independent fix branch; no merge. This report deliberately does not claim the paused broader MIG20 connection work completed.
