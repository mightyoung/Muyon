# Receipt-tail authority correction — production acceptance still HOLD

Fixed starting artifact source: `53badad9f6bab5321af3c1409a564184446cc4b8`.
Inherited core: `aec085fafef8aa02f86f2fc60626f168b10f4caa`.
Delivery branch: `task/artifacts-receipt-tail-20261022`.

Parent independent review identified an Important gap: archive/revise helpers
checked document/source authorities before writing the final committed receipt.
An AFTER UPDATE receipt trigger could then revoke/expire/change grant generations
or historical policy before COMMIT, while the previous final check consulted only
project Save. A second issue routed a future effect ContractError::Unknown into
semantic rejection even though its later rejected projection refused Unknown.

## Correction

The last committed-receipt UPDATE is now followed, before COMMIT and without any
further writes, by:

1. Output ReadText+StructuredEdit persisted grant-only publication-tail check.
   Revision publication already changed the head; current-base document reading
   would be incorrect here. This grant-only hook authorizes the just-performed
   publication tail, never historical content reading.
2. Every frozen source's current authority and explicit exact historical target
   policy, via the existing snapshot/core history helper; returned canonical
   metadata must still match the frozen source snapshot.
3. Independent project Save permission.

The internal ArtifactSaveFailure phase distinguishes ReceiptTail invalidation
from a determinate pre-receipt semantic rejection. The effect transaction drops
and rolls back before failure dispatch. ReceiptTail errors return Unknown with
the original reason and QueryOriginal; no rejected journal write occurs, so the
original durable pending remains available for read-only recovery. Receipt UPDATE
changing zero rows likewise returns Unknown rather than a fabricated terminal.

The unified requires_original_lookup classifier includes ContractError::Unknown
as well as storage failures. Submit, lookup, effect-failure dispatch and rejected
projection validation use the same classification. An Unknown error from any
future effect hook leaves pending unchanged, never Rejected(Unknown).

No public API, schema, document/body truth, owner file, scope/grant issuance,
source identity, sticky-human behavior, external action or retry was added.
Form/feedback extension was paused before implementation; only read-only inventory
of existing form/component contracts had occurred when the pause arrived.

## Tests and honest execution status

Two regression functions were authored before implementation. A separate
behavioral-regression-only commit `c5ee7041e3ab22dc7b00e8e9708f3b9a5b4c8f5c`
retains the original production code and the receipt-trigger regression. B can
run that immutable candidate to establish actual RED, then the final fixed
candidate to establish GREEN. This test-only commit has no dependency on the new
failure-dispatch helper. The local test command
was attempted first and preserved. Actual local command result: cargo absent,
shell127, NOT_RUN. No Rust RED or GREEN was observed or claimed.

- receipt_tail_invalidation_rolls_back_all_effects_and_preserves_original_pending:
  a real receipt AFTER UPDATE trigger performs 10 mutations: output and source
  grant revocation/expiry/generation changes; historical source policy revocation,
  expiry/generation changes; independent project grant revocation. Test source
  asserts Unknown/QueryOriginal, no returned receipt, unchanged output metadata,
  artifact history, document revision rows, blob references, upload status and
  blob pins; original intent stays pending with NULL receipt/error. Removing the
  trigger and restarting cannot reexecute the pending intent.
- effect_unknown_uses_original_lookup_without_writing_a_rejection:
  injects a future hook's Unknown into the real production failure dispatcher for
  a persisted pending intent; checks Unknown/QueryOriginal and byte-for-byte SQL
  journal row preservation. This exercises the production failure dispatcher,
  not a fabricated model/engine or a claim that an existing hook emits Unknown.

There are now 17 Rust artifact test functions in source (prior15 plus2). All remain
NOT_RUN locally. The authorized B compiler environment must run the targeted
regressions and full combined suite, and preserve any failures before acceptance.
The disposable harness still adds only the artifacts module export in its own
temporary copy; the real lib.rs and documents/** are unchanged.

Raw evidence: evidence/receipt-tail-test-first.log,
evidence/receipt-tail-post-fix.log, evidence/receipt-tail-final-rust.log.
Independent review/SQL evidence are separate: see
RECEIPT-TAIL-INDEPENDENT-REVIEW.md and the reviewer's explicit execution limits.
Prior SQL checks remain SQL-only. They are not Rust authorization/timing,
transaction-drop or runtime dispatch verification.

No real user files, original unknown/reservation, model/search requests,
main/develop, deployment, paid settings, credentials or security permissions
were touched. Original remote source branches remain unchanged.
