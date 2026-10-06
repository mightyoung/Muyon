# Research migration checkpoint — 2026-10-04

Development priority changed to the supplier plugin. This document records the
completed research slice; it does not claim M1, M2, device or release acceptance.

## Implemented

- All tracked research-workbench `lib` files except `main.dart` and all original
  tests migrated, with package imports adapted. MIT LICENSE and NOTICE retained.
- The only former WorkbenchApp/MaterialApp wrapper lives in test support.
  ResearchHome requires an explicit native project ID, has no project fallback
  or global selector, and keys its state by that ID.
- WorkbenchStore attaches to a host-owned connection, exposes the six original
  schema migrations, and leaves closing to the owner. `open` remains a baseline
  test helper. Scoped reads and writes check project/object ownership.
- UI note, task, assessment, acceptance, binding and outline writes use the
  host's synchronous write queue; transaction-aware store calls avoid nesting
  BEGIN. ResearchServices exposes the same scoped rules to host callers.
- ResearchRuntime prepares snapshots separately from synchronous commits;
  checks stored bytes against the prepared digest; persists project/business
  changes, import receipt and import change-log entry atomically; supports
  receipt lookup and commit retry after restart.
- Task preparation exposes the original native project ID and task revision.
  The host chooses the workspace; prepareTaskImport preserves native identity.
  ResearchHome accepts `importTaskThroughHost` after its explicit import dialog.
- ReaderPage supports initialPageIndex and initialQuote for host source opens.
- Module schema 7 adds receipts/change log; schema 8 integrates the separately
  implemented card/knowledge schema.

## Fresh validation

From `packages/research_module`:

```text
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy NO_PROXY=localhost,127.0.0.1 flutter test --no-pub
94 tests passed
```

The suite includes the original regression coverage plus prepare-without-DB,
concurrent commit idempotency, receipt restart, frozen-input recovery, failed
refresh preserving an independent note, scope rejection, task identity/replay,
and modified staging rejection. One obsolete global project chooser assertion
was replaced by an assertion that no chooser appears; its refresh data checks
remain intact.

Direct Dart analysis completed with no errors/warnings. At this checkpoint the
only remaining informational lint was in the independently owned package test:
`research_package_test.dart:100` (`avoid_function_literals_in_foreach_calls`),
reported to its owner. Host build/device validation belongs to root integration.

## Remaining acceptance gaps

- Host routing must exercise all four task/workspace branches; this module
  supplies identity and atomic commit APIs and rejects foreign scoped imports.
- The research view's own refresh menu still uses the scoped exchange directly;
  it does not create the host's cross-database import intent/receipt. Route it
  through the host coordinator before claiming full import recovery coverage.
- Change-log entries currently cover runtime imports. Ordinary UI domain writes
  need projection invalidation events before claiming complete M2 directory
  recovery and indexing freshness.
- Research commit parses cached text synchronously and may hash a legacy old
  document synchronously; it has no await in its transaction, but fully moving
  parsing/legacy comparison to prepare remains open.
- Uncommitted or failed runtime staging directories are retained; reconciliation
  and orphan cleanup still need the host's file recovery implementation.
- Schema definitionDigest currently uses stable version identifiers rather than
  a generated SHA-256 of the migration definitions; finalize before release.
- No real research project/external execution journey or physical-device
  acceptance was performed by this slice.
