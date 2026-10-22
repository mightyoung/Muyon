# Independent review: artifact save journal, project discovery and history hook

Separate reviewer: `artifact_review`, read-only on production/test source. Only
this review, an independent SQL script and evidence were written by the reviewer.
This continuation supersedes the original review's missing project-discovery and
historical-policy integration observations; original evidence stays historical.

Fixed core history implementation: `64017cd443a32b131c0d0851ba9346625d95819c`;
fixed inherited core handoff: `aec085fafef8aa02f86f2fc60626f168b10f4caa`.
Final reviewed integration tree: `b223a3237752cdec3d904beff66821e9a5aeb4e6`.
Reviewed `artifacts/{mod,project_access,save_journal,catalog,tests,workflow_tests}.rs`,
the concrete core-owned historical metadata hook and existing BusinessStore/SQLite
transaction/publication seams. Rust execution remains NOT_RUN; this is not merge
or product acceptance.

## Findings corrected during review

1. **P2: own-receipt lookup revealed existence of other actors' intents.** Initial
   lookup queried by global intent ID then returned InvalidAuthority for another
   actor, unlike Unknown/NotFound for an absent ID. Lookup now filters by intent,
   project and actor in SQL. Other-actor and absent queries both return no row;
   the new Rust assertion compares their projected outcomes. Global intent lookup
   remains only in submit, where an exact semantic request collision must fail.
   Correction is confirmed statically and at SQL level.
2. **P2: rejected projection did not require a durable terminal update.** Initial
   non-storage failure handling ignored the rejected UPDATE's row count and could
   return a definite Rejected with no pending row changed. It now requires exactly
   one changed row, otherwise returns StorageCorrupt, mapped by the public submit
   boundary to Unknown/QueryOriginal. SQL execution confirms that the conditional
   UPDATE returns zero for non-pending intents. Correction is confirmed statically;
   the Rust branch itself is NOT_RUN.

Final follow-up covered all six `.rs` files currently in `artifacts/` and the
fixed core-owned history hook. Added test source covers receipt UPDATE failure
rollback with a durable pending intent, a trigger that ignores rejection (zero
changed rows must remain Unknown), project permission separation, stale grant
generation/epoch, revocation and project revision invalidation. The historical
test grants output policy first (source still denied), then exact source policy
(successful original frozen metadata), then revokes it (denied). No latest refs
are substituted. A rejected row claiming a storage/Unknown error is also rejected
as corrupt rather than projected as a definite business failure.

No further confirmed static correctness, compile or privacy defect was found.
Compilation has not been established because cargo/rustc are absent.

## Save protocol assessment

- The public production save path is the intent journal. Low-level write wrappers
  are test-only; real archive/revise helpers operate inside the journal's same
  BusinessStore transaction.
- First transaction checks live project Save permission, current output write and
  source read permissions and commits the pending request before artifact effects.
  Request scope, actor, project revision, output/source identities and operation
  are SHA-256 bound with a domain prefix; changed parameters conflict.
- Pending, committed and rejected duplicate intents return their stored projection;
  none enters the effect branch again. A pending outcome is Unknown/QueryOriginal.
  Lookup never changes rows, reconciles uploads or schedules effects.
- Second transaction includes document/blob publication, artifact CAS/history and
  original receipt. Storage failures preserve uncertainty instead of claiming
  rollback/success or directing automatic retry. Determinate effect failures are
  journaled only after that transaction has dropped and rolled back.
- Committed receipts exclude content, title, origin details and source snapshots.
  They describe the original operation; they do not prove the current head or
  grant access to historical bytes. Duplicate submit can recover its own original
  receipt under live Save authority, while lookup requires LookupOwnSaves.
- Human provenance remains actor-bound for human edits; generated origin remains
  host-authenticated input. Sticky-human protection, exact expected revisions and
  source snapshot preservation remain on the real effect path.

## Discovery and historical reading assessment

- Project Discover is independently issued by a trusted host after real current
  actor/project membership authorization. Document grants are not accepted as
  project grants. Persisted scope, actor, project revision, owner epoch, generation,
  expiry and revocation are checked. Inventory DTOs exclude content and sources.
- The new project permission namespace is narrow and shares BusinessStore's actual
  connection; it is not a second document store or an authorization dispatcher.
  Actual host membership/identity issuance remains the integration owner's duty.
- Historical artifact/source reads now consume the real core hook
  `document_history_access_in_transaction`, rather than comparing revision order
  or reusing the publication-tail hook. Returned canonical metadata must equal
  the archived snapshot. Missing explicit historical policy denies the read.
- Both output and each source require live current authority plus explicit exact
  historical policy when older. Source/history grant revocation is consulted;
  original refs never point silently at latest content. Historical content after
  a source change can therefore be returned only when the host explicitly grants
  the exact old target. No engine or reader lease is created by this catalog.

## Independent execution and limits

Command:
`python3 docs/tasks/artifacts-mig17-u12-20261022/independent_workflow_sql_check.py`

Evidence: `evidence/workflow-independent-sql.log`.
The script extracts actual source SQL and uses a temporary on-disk synthetic
SQLite database. Passed: exact DDL round-trip; project grant SQL bindings and
revocation; pending durable across reopen before a failed effect; effect rollback
with pending retained; effect+receipt atomic SQL commit; conditional terminal
transitions; project catalog scope/cursor; actor/project filtered lookup with
absent equivalence; exact core historical grant SQL binding and revocation.

These results do not execute Rust, SHA-256/serde validation, wall-clock expiry,
permission enum interpretation, host membership checks or no-retry control flow.
Those are static review only or NOT_RUN. The synthetic commit sequence checks SQL
atomicity, not crash injection into a compiled Rust process.

Remaining acceptance blockers: Rust compile/format/targeted/full offline tests;
designated core-owner lib.rs export integration; actual trusted host/UI save,
lookup and project-grant issuance wiring. No real model/search call, user document,
engine, deployment or original unknown request/reservation was touched.

Reviewed source SHA-256:

- catalog.rs: `6cf4969a1582e5daddf63bc0976d6c615003e9d2257be15ba6da164c12d708a0`
- mod.rs: `25647bfcb5226e480996ade3b57ba7e97135f9d972b2ca232b26412d4cf8f39a`
- project_access.rs: `e5784f84d72aa719f518b7975a45388b7b2857d799a54aa7a8f26007efecc392`
- save_journal.rs: `5e072b00afc3ff748e162d0ddea4e1b8885f57b00d8f6d191365b0b76e2c0237`
- tests.rs: `cb4f79fb0f9a52a036031952895853880958457e69ac521c2417ecfcb47e2e14`
- workflow_tests.rs: `f400ca20b44e2b45900e4025557ae2ebe05ed7439c6a7738343aed44cec26e1c`
