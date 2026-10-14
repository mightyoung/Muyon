# RD-P06A Linux durable laboratory

Provisional one-shot private-directory CLI. This is not a renderer API, product storage/schema, authority service, backup restore, or exactly-once guarantee. The operation is `synthetic_increment` against one fixed private counter/effect source; it is not a supplier rename. Raw UTF-16 is a bounded opaque argument retained in the full binding (including isolated surrogates); no alternate name normalization is implemented or claimed.

## Offline build and commands

```sh
export CARGO_HOME=/tmp/muyon-spike01-toolchain/cargo
export RUSTUP_HOME=/tmp/muyon-spike01-toolchain/rustup
export CARGO_TARGET_DIR=/tmp/rd-p06-target
/tmp/muyon-spike01-toolchain/cargo/bin/cargo +1.99.0 build --offline --locked --manifest-path experiments/redesign/device-deferred/durable-recovery-lab/core/Cargo.toml
/tmp/muyon-spike01-toolchain/cargo/bin/cargo +1.99.0 test --offline --locked --manifest-path experiments/redesign/device-deferred/durable-recovery-lab/core/Cargo.toml
python3 experiments/redesign/device-deferred/durable-recovery-lab/core/tests/process.py
python3 experiments/redesign/device-deferred/durable-recovery-lab/core/mutations.py /tmp/rd-p06a-evidence-20261014
python3 experiments/redesign/device-deferred/durable-recovery-lab/core/tests/process.py
```

Only installed cached serde1.0.229/serde_json1.0.154/sha2 0.11.1/std are used. `RD_P06_BINARY` selects a separately built trusted test executable; `RD_P06_EVIDENCE_DIR` selects reviewer-owned external evidence. Neither is exposed to an application renderer. Tests create actual private tempfile directories, spawn separate OS processes, inspect the physical effects file, and clean up only those test-created directories. Default binary `/tmp/rd-p06-target/debug/rd-p06-durable`.

Example on NEW private directories (never point this experiment at product/user files):

```sh
/tmp/rd-p06-target/debug/rd-p06-durable --state-dir /tmp/rd-p06-demo-state --effect-dir /tmp/rd-p06-demo-effects --request '{"protocol":0,"op":"submit","domain":{"store":"synthetic-store","scope":"synthetic-scope","stream":"synthetic-stream"},"epoch":"epoch-0","intent":"example-intent","operation":"synthetic_increment","args":{"raw_utf16":[30002]}}'
```

Protocol0 serde structures are laboratory-only. Fixed full ordering domain is `synthetic-store/synthetic-scope/synthetic-stream`; no stream rotation is supported. `submit` and `lookup` need intent, operation, args; `snapshot` and `reconnect` omit business fields; `install_snapshot` uses snapshot `{cursor:{store,scope,stream,seq:"0"},state:"initial"}` instead. All requests have protocol/domain/epoch. Unknown fields/type/enum/version, explicit-null optional fields, irrelevant fields, labels outside nonempty <=128 UTF8 bytes and raw arrays over2000 units are rejected before storage access. Epoch is exact equality presentation metadata, not business identity. Lookup with the same original command is read-only. A missing receipt returns unknown (`not_found` or `pending_without_receipt`), never proof of no effect.

CLI flag order is exactly `--state-dir DIR --effect-dir DIR --request JSON [--fault POINT]`. JSON reply fields: kind, reason, receipt, snapshot, display_admission. Counter/seq values are canonical u64 decimal strings. CLI paths/faults are trusted harness inputs, not request capabilities. Fresh `lookup` creates no directories/identity/effect files. Existing lookup opens existing lock files read-only, takes the same advisory locks, validates existing data and never rewrites it. Ordinary snapshot/submit initialize a fresh empty pair; partial business files cannot be treated as empty. All ordinary replies use process exit0, including rejected/unavailable/unknown; abrupt fault exit90 has no stdout. Requests are capped32768 bytes; disk envelopes capped2MiB, exhaustion fails closed. No history compaction is claimed.

## Persistence/source binding

State directory contains `owner.json`, `ledger.json`, `projection.json`, `.lock`; separate effect directory contains `effects.json`, `.lock`. A random durable pair ID and canonical directory bindings bind state owner, effect source and receipts. Both locks are held while checking them. Receipt ID/count/binding is validated against the independently persisted effect entry, not a reducer counter or caller claim. SHA256 envelope checks detect corruption but are not source authentication against an adversary who can rewrite both payload/checksum. State/effect directories are trusted exclusive private test resources.

`ledger.json` persists complete intent/domain/operation/raw arguments with pending BEFORE dispatch. The fixed target is the pair's one private counter, bound by owner/source pair identity. `effects.json` is a genuine separate-file effect: its actual counter and dispatch entry change once per dispatch, non-idempotently. Only after that successful durable write is a receipt constructed from the result and persisted in ledger. Receipt/projection remain independent files. A response after receipt but before projection may recover a receipt with the old coherent snapshot. Lookup does not advance snapshot just because receipt exists. Corrupt/missing projection can still permit read-only receipt verification with snapshot null; submit remains unavailable.

Existing pending without a receipt remains unknown and is never redispatched, even when the external counter is0. A restored ledger from before pending checks the still-existing external history: same complete binding returns unknown, changed binding conflicts, neither dispatches. It does not manufacture receipt from effect count. Existing state cannot adopt missing/replaced/different source; same pathname with a different pair ID fails closed. Simultaneous rollback/cloning of BOTH state and effect stores/identities is unsupported, not a backup recovery workflow. Real source authentication/authority, capabilities, user-new-intent acknowledgement, external provider queries and retention are not implemented.

`projection.json` stores state plus full cursor/domain in one envelope, fsynced temp→rename→directory fsync. Slower snapshot or same-watermark fork cannot overwrite current pair or ledger. Verified old receipt ignores display epoch and leaves current projection intact. Reconnect only persists presentation epoch; it cannot reset ledger/seq or reissue intent.

Linux `flock(LOCK_EX)` uses open FDs; six cooperating processes serialize the SAME state/effect pair. Locks are acquired state then effect; lock files are never unlinked. Process exit/SIGKILL releases ownership automatically. Same directory is rejected before taking a second lock on the same inode. No stale PID-file deletion is used. This assumes local Linux advisory-lock and atomic-rename/fsync semantics with cooperating writers; malicious file replacement, NFS/distributed locking, provider exactly-once and hardware/power-loss survival are not proven. New directory parent entries are synced as created, but tests prove process-failure observations, not power cuts.

## Executed fault matrix

| Trusted fault | Observed effect count on fresh reopen | Receipt | Coherent projection |
| --- | --- | --- | --- |
| after_pending / before_effect | 0 | unknown | seq0 / initial |
| after_effect / before_receipt | 1 | unknown | seq0 / initial |
| after_receipt / before_pair | 1 | verified | seq0 / initial |
| during_pair_temp | 1 | verified | old seq0 / initial; temp not activated |
| after_pair | 1 | verified | seq1 / effect:1 |

Each unique boundary above exits90. `pause_after_pending` / `pause_after_effect` emit only stderr `fault_barrier` then SIGSTOP; the parent selects that marker without sleeps and sends SIGKILL. Both cases reopen in another process, release flock, remain unknown without new dispatch. A real external-write failure test holds effect lock, creates the child's private atomic-temp pathname as a directory, releases the lock, observes File create failure and durable pending/count0, then reopens unknown/count0. Invalid/truncated/missing files do not initialize over existing state.

26 test methods passed; the original RED was14 methods/21 assertion failures including subtests (not21 independent cases). Four inverse mutations compile successfully then fail named actual-process assertions: pending not persisted, unknown redispatch, projection snapshot erases receipts, and restored state ignores source history. finally restores source bytes, ready binary remains untouched (separate mutant target). Raw logs and actual effect-file digest/count observations stay external; only sanitized summaries/hashes are committed.

Android actual load/Compose/Electron NOT_RUN; M03 blocked_contract. Real data/models/device/install/accounts/licences/security settings/payment/deployment are outside scope. Existing CI does not execute this crate; candidate Flutter regression is separate evidence.
