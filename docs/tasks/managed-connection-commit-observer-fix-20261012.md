# ManagedConnection post-success notification isolation

Fixed base: `c0b4c3f27a53f5efcdc01a3ec1aacd3303683e40`.
Branch: `task/managed-connection-commit-observer-fix-20261012`.

## Failure and bounded contract

An independently injected synchronous `onCommit` exception occurs after a
successful SQLite COMMIT and after the caller's result has been completed.
The previous transaction catch attempts ROLLBACK without an active transaction;
the resulting queue error prevents subsequent work and normal close. A successful
`exclusiveAsync` operation similarly attempts to complete its result twice.
The new six-case regression suite independently reproduces both failures on the
fixed base (4 passing, 2 assertion failures; exit 1).

`onCommit` remains a best-effort notification after each successful write or
successful exclusive operation. It does not authorize or retry effects. Its
exception cannot change an already committed result, attempt rollback, poison
the queue, or prevent close. A fixed host diagnostic `commit_observer_failed`
contains no raw exception, path or transaction data and clears on the next
successful notification. No exception is sent to another diagnostic callback.
COMMIT marks the transaction ended before notification. Genuine transaction-body,
COMMIT and exclusive-body errors retain the existing propagation/rollback rules.

The existing production observer is ProjectionService's scheduler, whose sync
work already handles errors internally. No real production synchronous observer
throw or production exploit was demonstrated. This is a public API fault proven
with finite synthetic SQLite inputs, not a new production export integration.

## Verification

- Independent baseline RED: 4P/2F, natural exit 1. Failures show ROLLBACK without
  an active transaction and a second completion of an exclusive result.
- Fixed regression: six new cases plus unchanged storage-manager (5), projection
  (5), storage-recovery (2), and local-export-ledger (20): 38P/0F/0S, exit 0.
- Strict analysis of the changed production and test files: no issues.
- Three inverse mutations separately restore direct observer invocation for
  writes, direct observer invocation for exclusive work, and raw observer error
  disclosure. All three produced actual assertion failures (exit 1); the production
  file was byte-identically restored. The post-mutation regression also
  passed 38P/0F/0S.
- Original author branches and original tests are unchanged. Raw logs and
  mutation hash evidence remain outside the repository.

Source CI and a second independent review/current-develop combination are final
integration gates; local success alone is not permission to merge. No develop
or main merge, real file export, picker, real model, Android, platform expansion,
rejected LE04 experiment, or unknown-effect retry is part of this slice.
