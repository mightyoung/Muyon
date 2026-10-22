# Candidate GC pagination regression follow-up

Fixed test source: `02db15524dc4f3a1eccbd6571fe68c56e4ab62a7`.
Base delivered branch head: `b49ed859c331b4bd8004d8d3be5b8e12e7c7ff3e`.
Only candidate tests and evidence changed; production behavior remains the prior
`10d3aa83e2a93581107ad2e9f44331b5ea99d866`. No transaction-owner files changed.

## New regression and boundaries

`candidate_gc_crosses_page_boundary_preserving_exact_objects_and_project_quotas`
creates 160 genuine committed upload+journal reservations, using a test-only
helper at the existing crash point after reservation commit but before file
creation. Five projects hold 32 each; their 33rd preparation is denied before
new output. The helper now derives project scope from the actual DocumentAccess
instead of hardcoding the original project. Each reservation binds its own unique
expected hash, real source document and real authority. No validator is constructed.

After sorting actual opaque upload IDs, the test creates expected immutable files
for rows 0, 127, 128 and 159: before, on and after the first 128-row page boundary,
and at the tail. These model rename durability before the blob-ledger transaction;
they have no ledger row/pin that could mask missing reservation retention. The
last upload also has actual partial durable staging. A separate unreferenced file
has a hash absent from every reservation. After owner restart, maintenance must
retain all candidate reservations and partial staging. GC must remove only that
unrelated object, keep all four expected objects, preserve the complete original
upload/journal rows, and remove nothing on a second pass. It must terminate across
multiple pages without silently skipping the tail or repeatedly deleting data.

A sixth project's real candidate preparation succeeds despite 160 other retained
candidates, checking project-local rather than global quota. Its authorized access
cannot query the first project's candidate. Cross-project GC must still inspect
all project reservations because content-addressed objects share the same store;
filtering the GC cursor to just one project could delete another project's output.
Production cursor ordering is strict `upload_id > cursor`, within the same SQL
transaction as each deletion decision; the terminal empty/short page remains the
stop condition. No production cursor or publication behavior was changed.

Existing faults cover reservation insert failure, partial fsync beyond last SQL
length, late sealing failure after durable pin, expiry after pin, missing/corrupt
objects and missing pins, restart owner change, and exact source revision advance.
The new test adds two crash locations across pagination: reservation-before-create
and renamed-expected-file-before-ledger, plus partial staging on the final row.
These are synthetic local fixtures, not a claim of exhaustive power-loss testing.

## Verification and integration

Raw logs: `candidate-evidence/06-pagination-test-first.log` and
`candidate-evidence/07-pagination-fixed-source.log`. The targeted pagination test,
candidate suite, full core suite and owned rustfmt check are **NOT_RUN (127)**
because cargo/rustfmt are absent. `git diff --check` exited 0. There is no local
red/green claim and no new production validator; publication remains hard denied.

The prior >128-row *source coverage* gap is addressed by this new regression, but
runtime acceptance remains HOLD until the authorized Rust environment executes the
fixed source. Earlier COPY/core counts do not verify this revision. Retained
candidates still consume the 32-entry/128-MiB per-project budget; no cleanup or
global disk-quota implementation is implied.

Read-only cross-owner check: remote transaction source/report
`156e49c5e97ff13a09ce2626bc64f3a1b60e0f8f` was fetched and its SCHEMA2-HANDOFF and
EDITED-CANDIDATE-INTERFACE read. Its earlier a27-based SQL-byte journal is separate
from core private blob/pin preparation. Its reported 262 tests and Unicode counts
are not claimed for this branch. Current core CandidateStatus grants no byte
delivery/reader lease or validated publish handle; an opaque operation ID also
does not establish a complete operation digest or fresh confirmation. Transaction
owner must retain its exact request/confirmation/intent binding. No real validator
exists, so successful edited publication and an externally reusable prepared
handle remain unavailable; no suggested success interface was fabricated.
