# Rust evidence identity and chronology

All runs used `/workspace/Muyon`, synthetic inputs, and the isolated manifest
`experiments/redesign/hy-memory-governance-lab/Cargo.toml`. Common environment:

```sh
PATH=/workspace/hy-tools/cargo/bin:$PATH
CARGO_HOME=/workspace/hy-tools/cargo
RUSTUP_HOME=/workspace/hy-tools/rustup
```

For every named run below the command was:

```sh
cargo test --locked --manifest-path experiments/redesign/hy-memory-governance-lab/Cargo.toml > docs/tasks/hy-memory-governance-20261018/evidence/NAME.log 2>&1
result=$?
echo "$result" > docs/tasks/hy-memory-governance-20261018/evidence/NAME.exit
```

`rust-red` was preceded by an initial dependency-fetching run without `--locked`.
That initial run failed all twelve tests at the seed setup stub. Its full log was
accidentally overwritten; it is NOT counted as twelve mechanism REDs. The parent
retains an observation excerpt in `rust-initial-red-observation.md`. No original
full-log recovery or reconstructed replay is claimed.

| Run NAME | Exit / observed result | Source identity / interpretation |
| --- | --- | --- |
| rust-red | 101 / 12 failures | `rust-red-source.tar.gz` and `.sha256`; seed returns a nonpersistent synthetic ticket, other APIs are stubs; weaker preliminary RED |
| rust-red-targeted | 101 / 8 failures, 4 passes | Matching `-source.tar.gz` + `.sha256`; real persistent fixture setup works, deletion/worker/consume/quote mechanisms remain stubs. Four pure rejection negatives already pass and are NOT counted as RED. Positive deletion, consumption and quote assertions fail; crash tests fail expected exit-code assertions. |
| rust-green-01 | 0 / 12 passes | Pre-review implementation. No exact contemporaneous snapshot was saved; do NOT attribute it to a final commit or infer an exact source identity. |
| rust-red-marker-fence | 101 / 1 failure, 13 passes | Matching source tar/hash; marker/reason failure, contention test already passes. |
| rust-red-review-fixes | 101 / 4 failures, 13 passes | Matching source tar/hash; automatic-write/read separation, colon operation collision, body cleanup and marker failures. |
| rust-red-structured-claims | 101 / 7 failures, 13 passes | Matching source tar/hash; adds structured quote source metadata, independent source/read fixture mutation and fenced claim behavior failures. |
| rust-green-02 | 0 / 20 passes | Matching source tar/hash. Unformatted source; rustfmt was initially unavailable and then installed in the isolated toolchain. |
| rust-red-body-fork | 101 / 1 failure, 22 passes | Matching source tar/hash; actual memory bytes altered without revision/digest change were incorrectly consumable. Independent direct-column gates and real missing-source/SQLite-table read failures already passed. |
| rust-green-03 | 0 / 23 passes | Matching source tar/hash; recomputes governed memory body digest as well as source bytes, independent flags and source table, private claim tokens, structured quote output; formatting applied. |

| rust-red-current-tombstone | 101 / 1 failure, 23 passes | Matching source tar/hash; direct current tombstone without generation bump incorrectly allowed a new deletion request. |
| rust-green-04 | 0 / 24 passes | Matching source tar/hash; explicit current tombstone check before new deletion, with unchanged receipt replay behavior. |

Each source archive excludes `target/` and retains Cargo.lock; SHA-256 is in its
adjacent `.sha256` file. `rust-pre-review-fix-source.tar.gz` is merely the current
pre-fix snapshot, not claimed to match GREEN01: it includes later marker/fence tests.
All snapshots and logs are retained even where they expose incomplete behavior.

The three child-process crash observations are process exit 71 between tombstone
and outbox writes, exit 72 after commit, and exit 73 after durable sink deletion
before job acknowledgement. Another process reopens the SQLite file for the
post-commit read-denial assertion. The full crate suite includes actual lease
expiry/retry, independent state gates and a real SQLite read error (dropped table).

No production behavior or global physical erasure is proved. Read the lab README
for exact sink, retained-source and SQLite WAL/free-page boundaries. Final
exact-commit verification and independent review are recorded by the parent task.
