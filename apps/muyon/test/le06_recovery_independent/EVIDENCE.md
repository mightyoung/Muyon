# LE06 independent recovery evidence

Verified on macOS, 2026-10-12 (Asia/Shanghai). Fixed baseline:
`d104986d42e7dd92ea42fa64553010ad22d244d9`.
Branch: `task/le06-recovery-independent-tests`.
Checkout: `/private/tmp/le06-recovery-independent`.
PR base: `task/le06-export-ledger` (remote verified at that baseline).

Only the independent test and this dedicated evidence file are added.
No ledger implementation or original test changes remain. No production defect
was reproduced against the unmodified fixed baseline. Intentional mutations
below were RED and were restored; no skip or weakened assertion was added.

## Actual validation commands and exit codes

Commands run from `apps/muyon` unless stated otherwise.

```sh
flutter pub get
# exit 0; SDK-generated tracked configuration edits restored afterward
dart format test/le06_recovery_independent_test.dart
# exit 0
env NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 flutter test --no-pub test/le06_recovery_independent_test.dart --reporter expanded
# exit 0, 7 tests including the no-op child fixture before raw-error case added
env NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 flutter test --no-pub test/le06_recovery_independent_test.dart test/local_export_ledger_test.dart --reporter expanded
# final exit 0, 28 passed: 7 independent parent cases + 1 child fixture + 20 original tests
flutter analyze --no-pub test/le06_recovery_independent_test.dart
# final exit 0, No issues found
git diff --check
# repository root; exit 0
git diff -- apps/muyon/lib/platform/local_export_ledger.dart
# repository root; exit 0, empty output after all mutations restored
```

The child fixture runs `flutter test --no-pub
test/le06_recovery_independent_test.dart --plain-name 'child process fixture'`
in separate OS processes. Each separately opens the temporary SQLite file;
no ledger instance, issuer, or running-map memory is shared with the parent.
The child mode and directory are passed through `LE06_CHILD_*` environment
variables. `LE06_FLUTTER` optionally selects the Flutter executable.

## Per-case results

| Parent test | Final result | Observed evidence |
| --- | --- | --- |
| disk pending failure rolls back and executes zero callbacks across process | PASS | Child insert trigger abort; callback count 0; safe `ledger_pending_failed`; reopened exports and attempts both empty |
| process exit after completion failure retains pending and read-only unknown | PASS | Child callback 1 after committed pending; completion update trigger abort; child returns interrupted and closes; fresh process reads unknown from persisted pending; replay callback 0; read/check/replay commits 0; probe success stays unknown in model projection; persisted rows unchanged |
| process reopen separates generated success from save cancellation | PASS | Child generated success plus separate cancelled save; parent reopen preserves both phase states; late cancellation preserves cancelled fact |
| disk replay rejects changed content scope and target identity | PASS | Close/reopen after successful generation and save; changed bytes, scope, or new target identity rejected as `export_identity_conflict`; callback 0; only two existing rows retained |
| two independently gated processes contend for one pending reservation | PASS | Two separate connections and tester processes released by one gate; total callback count 1; one successful winner; loser must be unknown or explicit SQLite pending failure; one durable attempt |
| nested audits stay frozen on disk and all model error projections redact canaries | PASS | Nested request and completion maps/lists changed after construction; original values persisted across close/reopen; recovered nested maps immutable; private error token normalized; direct and JSON-roundtrip model receipts exclude path/URI/handle/body/error canaries |
| raw callback error survives disk reopen only in host audit | PASS | Raw thrown error containing four canaries survives only in host completion audit; returned and reopened model stage retain safe unknown/error code; model receipt and JSON roundtrip contain no canaries |

## Reverse mutation evidence

Each mutation was applied alone to `lib/platform/local_export_ledger.dart` in
this checkout. Every command below exited **1** at the indicated assertion.
The exact common command prefix was:

```sh
env NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 flutter test --no-pub test/le06_recovery_independent_test.dart --plain-name '<test name below>' --reporter expanded
```

| Mutation | Exact selected test name | Observed RED |
| --- | --- | --- |
| In `_match`, change identity comparison `!=` to `==` | disk replay rejects changed content scope and target identity | Expected identity-conflict exception; emitted old stage record |
| In pending-write catch, call `await operation(request.preparation.bytes)` before throwing pending error | disk pending failure rolls back and executes zero callbacks across process | Expected child callback count 0; actual 1 |
| In `_record`, project inactive persisted pending as succeeded instead of unknown | process exit after completion failure retains pending and read-only unknown | Expected unknown; actual succeeded |
| Add `le06_private_error_3fa19` to `_modelCode` allowlist | nested audits stay frozen on disk and all model error projections redact canaries | Private error canary appeared in returned model serialization |
| Replace `_freezeMap` recursion with `Map.unmodifiable(value)` | nested audits stay frozen on disk and all model error projections redact canaries | Reopened audit contained changed path instead of original synthetic canary |

Final regression run above was performed after all five mutations were removed.

## Actual scope and limitations

- Persistence evidence covers SQLite file close/reopen and normal child-process
  exit after injected completion-write failure. Abrupt process kill, power loss,
  filesystem failure, and SQLite crash recovery are **not verified**.
- Concurrency evidence covers one synchronized two-process run on macOS using
  separate ManagedConnection instances. LE06 children share an isolated Flutter
  `build-dir` (`build/le06-children`) so native-asset install cannot delete
  the parent suite's `build/native_assets/<os>/*.so` (see CF-FIX-B CI
  38258595733). Startup is still serialized before the shared database gate;
  the database operations are released together after both processes are ready.
  Every scheduler interleaving, fairness, cross-platform locking, and retries
  after lock rejection are **not verified** or promised.
- Same-identity changes bind to content, scope, and target identity digest; the
  target is a synthetic live capability and never writes a real destination.
- Only temporary SQLite files, synchronization/result files, and synthetic
  data are used. No real export, model call, Android run, historical migration,
  deployment, or shared-worktree mutation was performed.
- Initial test invocations without localhost proxy exclusions exited 1 before
  loading any case: `Invalid WebSocket upgrade request`. An unchanged original
  test reproduced the same failure. Localhost exclusions fixed the transport.
- The first concurrent child startup exited 1 due to `install_name_tool` racing
  over generated `libpdfium.dylib`; separating startup from the database gate
  fixed that test harness failure. Neither environment failure is ledger RED.
- Full app build, Linux/device validation, exhaustive fault coverage, and
  mutations beyond the five recorded above remain **not verified** here.
- Leader B must independently rerun this branch before acceptance and assign
  any future production fix to the original owner. This draft does not merge
  or establish platform export acceptance.
