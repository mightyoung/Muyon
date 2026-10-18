# Synthetic memory governance lab

This standalone Rust crate exercises the contract in
[`hy-memory-governance-20261018.md`](../../../docs/design/hy-memory-governance-20261018.md).
It is an isolated SQLite fixture authority, not a second production ledger. It has
no application, model, HTTP, tool-send, Android, backup, or external-service wiring.
All test inputs are synthetic.

Run the entire crate suite:

```sh
export PATH=/workspace/hy-tools/cargo/bin:$PATH
export CARGO_HOME=/workspace/hy-tools/cargo
export RUSTUP_HOME=/workspace/hy-tools/rustup
cargo test --locked --manifest-path experiments/redesign/hy-memory-governance-lab/Cargo.toml
cargo fmt --check --manifest-path experiments/redesign/hy-memory-governance-lab/Cargo.toml
```

`rusqlite` builds bundled SQLite; Cargo.lock is retained. Tests use unique real
SQLite files under the OS temporary directory, and the `crash-worker` executable
exits abruptly at three explicit synthetic fault points. Temporary files are
intentionally retained for inspection; no private data is read.

## What the fixture demonstrates

* Deletion checks the current full member ticket, management authority, and
  management purpose under `BEGIN IMMEDIATE`. Tombstone, generation, three cleanup
  jobs, and payload-bound receipt commit together. An identical request replays
  the receipt, while a changed payload conflicts. Length-delimited hashes bind
  every receipt field and each cleanup operation identity.
* Independent memory fields represent content identity, authority, policy,
  scope/use, memory reading, automatic writing, disabled/expired state, lineage,
  and tombstones. A separate source table represents source identity, version,
  bytes/digest, authority, availability, and tombstones. Current byte digests are
  recomputed for projections. Closing automatic writing still permits a fresh
  projection of existing readable memory; management deletion also remains allowed.
* Per-sink status, attempts, lease expiry and retry eligibility persist. Claim
  attempts fence old acknowledgements. Deletion is idempotent; a process can die
  after deleting a sink but before acknowledging it, then retry the same operation.
  `failed` and `unknown` remain distinct. A synthetic `done` adapter outcome
  performs and verifies deletion; it represents successful reconciliation after
  an unknown result. The fixture clock is caller supplied and uses ten-unit
  leases/backoff; this is not a production scheduler.
* Consumption checks every member inside the SQLite write transaction that also
  commits the synthetic consumption record. Revocation uses that same write
  fence. Tests cover prebuilt tickets, both commit orders, and real contention
  with another SQLite connection holding the revocation transaction open.
  The committed record is the linearization point; it is not an external send.
  Previously committed consumption cannot be recalled.
* Quotes return structured source identity, source revision/digest, original
  UTF-8 byte ranges and rendered segments. Replacement inputs are allowlisted
  reason categories (`sensitive`, `credential`), with generated visible markers.
  Hidden bytes are never copied into returned replacement segments. A continuous
  quote rejects replacement or gaps; a segmented display marks gaps explicitly.
  Current source/memory gates apply before returning a quote. Returning it is a
  synthetic read consumption boundary, not reusable authority for a later send.

## Cleanup scope and limitations

The manifest covers `memory-body`, `vector`, and `cache` for the exact target.
`memory-body` empties the governed memory row body; vector/cache are synthetic
presence rows, not real search engines. All jobs must be `done` before callers
can infer logical completion for those three targets. The independently identified
source row is retained: deleting a memory does not authorize deleting its source.
Source revocation/tombstones nevertheless deny projections derived from that source.
No whole-system cleanup-complete API or production sink inventory is supplied.

SQL updates/deletes demonstrate logical cleanup only. SQLite WAL, free pages,
filesystem snapshots, logs, crash dumps, backups, third-party copies and previously
exported content are outside this lab. Secure physical erasure, domain-external
ForgettingReceipt persistence, restore ordering, cross-device recovery, real
expiry clocks, multi-scope policy engines, and production sender fencing remain
unimplemented. The fixture models a single local scope and the `context` read use;
its independent flags are deterministic test facts, not a production permission
model. Lineage is one direct source identity equality, not recursive multi-source
graph or DAG evaluation. Crash hooks and fixture mutation methods are deliberately lab-only APIs.

## Evidence

Raw test logs, exits and source snapshots are under
[`docs/tasks/hy-memory-governance-20261018/evidence`](../../../docs/tasks/hy-memory-governance-20261018/evidence).
See `rust-evidence.md` for the chronological RED/GREEN record and limitations.
The parent integration task records the final source commit and exact-SHA rerun;
precommit snapshots and passing runs alone do not prove that final revision.
