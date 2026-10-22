# Storage lint fixed; exhaustive core target scan

Fixed code4b98072eda94db4c937a00adea452bd985ddc00d imports only core owner
8f24e8f5384489e2ee7d86b8494ee1ca47c0cd8b one-line repeat_n test correction.
No new reader/candidate source. Actual document_storage15PASS/0FAIL, exit0.

Full strict workspace/all-target Clippy exit101 now emits:
- muyon-android-ffi/src/lib.rs:181:5 too_many_arguments10/7 (existing ABI boundary).
- muyon-core/tests/document_edit_transactions.rs:387:11 needless_update.
  Binding already lists all4fields; trailing `..binding()` has no effect.
  Original gateway/transaction owner should remove only that redundant update,
  preserving rollback binding fields/receipt/CAS assertions and no candidate work.

A failing aggregate command can terminate compilation of later targets early.
To enumerate remaining core issues without disabling lint, integrator separately
ran the same strict command for core lib+bins and EACH23 integration test target:
24 commands total,23exit0 and only document_edit_transactions exit101 with the
same single needless_update. These are static checks, not test executions or a
workspace green claim. They do not include FFI/lib, which remains known failing.
Each exact command/exit/raw log is preserved under evidence/core-clippy-per-target/.
No old/I04 tests executed, no allow or bypass; compiled product targets only.

Parent explicitly authorized source owner to retain a documented method-local
too_many_arguments ABI exception if keeping the existing UniFFI/Host/generated
contract is necessary. This exception is pending source, not applied here. The
final report must name it as an ABI exception rather than claim reduced arguments.
All other lint remains strict. Typed-record alternative only with planned protocol
compatibility, no integrator-only ABI redesign while host owner is consuming it.

Last complete workspace435PASS/fixed-source review remains67fd14c4. Current
reversible test-only change has fresh affected15PASS; do not retag435 as a fresh
run of4b98072e. Full gates/review to rerun once both remaining source fixes arrive.
See NEXT-BATCH-QUEUE.md for deferred inputs. No next batch started before strict
closure, no main/develop/PR/device/external-engine/credential/paid action.
