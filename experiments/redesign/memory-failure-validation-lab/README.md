# Memory failure validation lab

The Python fixtures are offline, synthetic contract experiments only and import neither the existing Hy crate nor production stores/adapters. The separate Dart canary fixture imports actual Muyon adapters and uses a synthetic loopback server; it is NOT_RUN here. No weights, external model, paid service, credential or private data is needed. `FakeProvider` has no transport. I04 is forbidden and is not implemented here.

From repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 experiments/redesign/memory-failure-validation-lab/run_suite.py
```

Python 3.10+ and stdlib SQLite suffice. Results and complete unittest output go to `docs/tasks/memory-failure-validation-20261018/`. Temporary databases are synthetic and removed after each test. Two subprocesses intentionally exit 71/72 to exercise crash boundaries; their parent tests assert those exact codes.

The SQL fault uses an actual SQLite `RAISE(ABORT)` insert trigger after retirement. A separately committed correction intent blocks the already overruled old fact even when the replacement transaction rolls back. Replacement SQL and its index-pending state share one transaction; an explicit SQL fallback exposes the new truth while a fake vector sink fails. Restart, observer visibility and deletion before late repair are checked. Unknown is a durable blocked state with no replay. This demonstrates a possible contract; it does not prescribe a production schema, implement multi-user authority/revision/hash policy, certify concurrency, or prove production behavior.

A confirmed NOT_COMMITTED replacement can be repaired explicitly; a known committed index may be rebuilt without repeating SQL/model execution. There is no autonomous retry loop. Tombstones remain terminal in this fixture. The separate correction-intent commit is an intentional truth barrier, distinct from the replacement commit; if intent persistence itself fails, acceptance must not be acknowledged (that storage failure window is not tested here).

Model parsing distinguishes missing/empty/whitespace from explicit JSON `[]` (NO_CHANGE). A valid operation is only PROPOSED, never a claim that memory was committed. Invalid shapes fail clearly. The minimal REPLACE schema is local to this fixture, not Muyon's API contract.

Three deliberate broken controls verify the oracle rejects autocommit silent empty memory, rollback that exposes an overruled fact, and blank-as-no-op parsing. These controls are not observed product bugs. Existing current-member/revision/body-hash tests are inventoried rather than reimplemented.

Actual adapter canary fixtures and runtime limitations are documented in [ADAPTER-LOG-AUDIT.md](../../../docs/tasks/memory-failure-validation-20261018/ADAPTER-LOG-AUDIT.md). No production log zero-leak claim is made. See the task HANDOFF for exact scope and unrun checks.
