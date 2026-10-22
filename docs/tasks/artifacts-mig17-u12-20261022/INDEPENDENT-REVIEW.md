# MIG17 / U12 independent review

Reviewer: separate `artifact_review` agent, read-only against production sources.
Fixed dependency base: `f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac`.
Reviewed new artifacts module, tests, existing document storage hooks, blob
publication/reader seams and SQLite transaction implementation. This is static
review plus independent SQL execution, not Rust acceptance or merge approval.

## Finding and correction

**P1, historical access must not broaden a revision-specific grant — corrected
statically.** The initial `artifact_authorize_record` accepted newer revisions of
an output or source as authorization for older captured metadata. Existing
`DocumentAccess` grants bind exact `DocumentRef`; the core publication-tail hook
explicitly does not authorize old revision reading. A `current >= historical`
comparison therefore cannot establish historical read authority.

The author changed both output and source checks to exact `DocumentRef` equality.
Reading a changed output/source now fails with `RevisionConflict`, and tests
expect the denial while checking that the captured snapshot stays unchanged.
This closes the identified authorization broadening in the current source.
`CORE-HOOKS.md` correctly requests a concrete core-owned historical authorization
hook, including current policy, rather than treating the publication-tail check
as read permission. Historic reading after either revision advances remains HOLD.

## Other conclusions

- Storage extends the same BusinessStore connection and transaction. Artifact
  rows reference canonical document metadata; no copied document body or second
  document/grant truth is introduced.
- Initial archive requires output `ReadText + StructuredEdit`; sources require
  `ReadText`, same scope, distinct identities and bounded source count. Read and
  write paths consult persisted current document/grant state.
- Revision publication uses the existing in-transaction document/blob hook,
  artifact head CAS, immutable revision insert, output grant tail check and source
  recheck before commit. Failure propagation rolls back the shared transaction.
- A sticky human-edit flag rejects generated overwrite, including a fresh CAS
  after a human edit; original and current origin fields remain separate.
- Canonical snapshot equality, SQL-side payload size guards and bounded page
  sizes reduce corruption/allocation risk. Decimal length/text sorting preserves
  u64 revision order.
- No confirmed additional compile defect was found statically. This statement
  does not establish compilation: neither cargo nor rustc is available.
- The module intentionally has no project-wide artifact discovery endpoint.
  A grant on one document must not authorize project enumeration. Project-level
  authorized discovery, host/UI wiring and history permission policy remain
  unimplemented integration work, not completed U12 product acceptance.

## Independent execution evidence

Command: `python3 docs/tasks/artifacts-mig17-u12-20261022/independent_sql_check.py`.
Evidence: `evidence/independent-sql.log`.

The script extracts the actual DDL and pagination SQL from the Rust module,
executes them with Python sqlite3 in a temporary on-disk synthetic database, and
checks exact schema round-trip, u64 order, exclusive cursor/limit and trigger
failure rollback. All those SQL checks passed. It does **not** execute the Rust
BusinessStore, permission checks, blob publication or Rust unit tests.

Rust test and formatter execution: **NOT_RUN**, toolchain absent. The module also
needs the designated core owner to add `pub mod artifacts;` in lib.rs; the author
must not modify that owned file. A test command on the unintegrated production
crate alone cannot establish that artifacts compiled or tests were discovered.

Review source fingerprints after the historical access correction:

- mod.rs SHA-256: `939c6f798108f8b0b65decf2ca0807feb7723ef5b3132e5d543079ec31629210`.
- tests.rs SHA-256: `6fcb4529fa946129fd08948619f2fa5595e5b3c104ae12ff57c0c8ec93953708`.

Follow-up static review covered `exact_scope_and_write_permission_are_required`:
a real second-project source, output with only ReadText, mismatched owner epoch,
stale grant generation, and expired source grant all have denial assertions.
The test setup follows the existing persisted grant lifecycle. No new static
issue was identified; all Rust execution remains NOT_RUN. Acceptance stays HOLD
until core integration and targeted plus full offline Rust tests run successfully
in an authorized environment.
