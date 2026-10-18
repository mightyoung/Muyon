# Service checks owner, 2026-10-18

Owned changes are checks only. No product source, FFI, feature, provider, old descriptor, or workflow threshold changes.

## Frozen dispatch readiness (read-only)

Repository: `mightyoung/Muyon`. GitHub reads succeeded on 2026-10-18:

- Android Rust bridge workflow ID `385485667`, `state=active`.
- `lab/android-rust-bridge-service-temp-red-20261015` points to `f711fe31cf2f7d5b4be692708efca183ede090a0`.
- `workflow_dispatch` supports `suite=service-temp-red` and boolean `emit_android_source=false`.
- Selection produces `mode=service-temp-red`, `red=[]`; it selects the existing `service-host-checkpoint` job.

Root-only dispatch command, **not executed by checks owner**:

```sh
gh workflow run android-rust-bridge.yml --repo mightyoung/Muyon --ref lab/android-rust-bridge-service-temp-red-20261015 -f suite=service-temp-red -f emit_android_source=false
```

Read success and dispatch definition do not prove dispatch write permission. Root subsequently attempted dispatch and confirmed HTTP401 on both paths; further dispatch attempts stopped. Verify remote SHA again immediately before dispatch. Source126 and temp RED remain distinct from diagnostic native45 success38772045455 and Android handoff14 run38773509116. No full shipping claim.

## Separate C2/C3 fault descriptor

`service_fault_cases.json` pins native-owner C1 source `a9a1dddbfe12bdf57230ee85f0bc603fe29d8b40`, four exact source SHA256s, and separate expected/observed terminal contracts. It does not modify legacy45 or temp46 inventories.

`service_fault_probe.py` obtains the entire Rust host and its two local dependencies via `git archive` of this immutable commit. It checks four hashes and unique anchors before writing private source copies. Original author source remains untouched. A new integration target lives only in the copy. The descriptor, Rust probe and original/private source hashes are written to evidence.

- C2: after real `run_builtin_admitted` returns, validate actual receipt is RecordedSuccess, save original native.db and opaque ID outside the service root, then panic on the real worker before Completion. After `await_settled`, require Unknown plus the actual original success receipt/opaque and unchanged bytes. Current expected RED observation is Unknown/Unknown with missing opaque.
- C3 cancel: at actual built-in endpoint turn2, request cancellation before its original poll. Require Cancelled plus original RecordedSuccess/opaque and unchanged bytes. Current expected RED observation is Failed plus RecordedSuccess.
- C3 failed-ledger sibling: same cancel injection plus explicit private-copy `store::ledger(status=="failed")` error `probe_failed_ledger_io`. Require Unknown plus original RecordedSuccess/opaque and unchanged bytes. This is a named injected I/O failure, **not a disk-full/ENOSPC experiment**. Actual baseline also returns Failed, not required Unknown; it is therefore a third independent semantic RED. The initially predicted diagnostic green was rejected INVALID; the corrected descriptor freezes the observed Failed while keeping the required Unknown unchanged.

Classifier closes on the single exact integration row/summary, expected exit, markers, panic count/messages and original target name. Duplicate output, extra panics, compilation failures, timeout, killed processes and disk-full messages are rejected. Recognized RED preserves exit101.

## Commands and validation

Three prepare-only executions passed and wrote bounded source copies under `/tmp/service-fault-{c2,c3,c3-ledger}-prepared`, with evidence in matching `-evidence` directories. These prove extraction/hash/anchor application, **not native execution**.

```sh
python3 -B -m unittest discover -s experiments/redesign/android-rust-bridge-lab/checks -p 'test_*.py'
```

Result: 59 tests passed, including negative transcript/hash/anchor controls. Test-generated errors in stdout are expected negative fixtures.

Root coordinates actual Rust resource use. For each case, choose fresh empty paths; optionally export an approved shared `CARGO_TARGET_DIR`. Example:

```sh
python3 -B experiments/redesign/android-rust-bridge-lab/checks/service_fault_probe.py --case c2_worker_panic --work-dir /tmp/service-fault-c2-actual --evidence-dir /tmp/service-fault-c2-actual-evidence
```

Other cases: `c3_cancel`, `c3_failed_ledger`. The runner uses exact `cargo +1.99.0 test --release --locked`, only `--test service_private_fault`, captured `--show-output`, one test thread and a 900s bound. `--prepare-only` is available. Actual runs are recorded below; no source-fix or full-shipping claim is made.

## Actual native evidence, official Rust 1.99.0

Root authorized bounded actual execution with `CARGO_HOME=/tmp/muyon-tools/cargo`, `RUSTUP_HOME=/tmp/muyon-tools/rustup`, official cargo bin PATH prefix, `CARGO_BUILD_JOBS=2`, shared `CARGO_TARGET_DIR=/tmp/muyon-build/service-fault`. All probes compiled the real fixed author source from private archives.

| Probe | Actual result | Evidence directory |
| --- | --- | --- |
| C2 worker panic | accepted semantic RED / 101: OutcomeUnknown, receipt Unknown, opaque false | `/tmp/service-fault-c2-actual-evidence` |
| C3 turn2 cancellation | accepted semantic RED / 101: Failed, RecordedSuccess, opaque true | `/tmp/service-fault-c3-actual-evidence` |
| C3 failed ledger, initial prediction | INVALID / actual101: Failed, RecordedSuccess, opaque true; predicted Unknown disproved | `/tmp/service-fault-c3-ledger-actual-evidence` |
| C3 failed ledger, actual-observation descriptor | accepted semantic RED /101: Failed, RecordedSuccess, opaque true | `/tmp/service-fault-c3-ledger-frozen-actual-evidence` |
| C4 original temp gate | accepted semantic RED / 101: 46 observed, 45P+1F | `/tmp/service-temp-red-actual-evidence` |

Each fault raw log proves actual RecordedSuccess before inspection, saved native.db unchanged after settlement, and exact opaque correlation. C2 worker panic is the real beforeCompletion worker failure. Failed ledger is explicit `probe_failed_ledger_io`, not disk full. The native owner received actual C2/C3/C4 evidence and root authorization to activate targeted fixes.

C4 ran original closedgate at checks composition `1fc398c2269f7e77c60a7f2c2eecda8e58d7323c`, retaining product source f711, author test126 and immutable descriptor. It reported `source_inputs_unchanged=true`, exact temp assertion and 45 healthy siblings. The later byte-preservation assertion tail remains NOT_RUN. The shared target was reused via `/tmp/service-temp-red-actual-work/host-target` symlink.

Raw evidence SHA256 index (files remain external to source tree):

- `/tmp/service-fault-c2-actual-evidence/cargo.log`: `79c28024206d7090adcfea2e8bf3e502989d85b1513998584df42dc3874b99b2`
- `/tmp/service-fault-c3-actual-evidence/cargo.log`: `b257ec6a80d9ca1d6d8c3062669c8f71c25372cad237a6e3a3a32b13bb0f4256`
- `/tmp/service-fault-c3-ledger-actual-evidence/cargo.log`: `4fb7c8f55db70eab33f95bc9e2f0cc7a83deb48d8876034231feba45aff2bc8f`
- `/tmp/service-fault-c3-ledger-frozen-actual-evidence/cargo.log`: `648d83f06ae5067149bcbb3a1b943618ae71a97bb2249af6db5b3c2f4f49f190`
- `/tmp/service-temp-red-actual-evidence/verdict.json`: `14cbf94268d50b1d097d2e57a9ba639ffb9332aaaee82520c9cfe5545176c20a`
- `/tmp/service-temp-red-actual-evidence/service-temp-red.log`: `47a1ccfd4837e806a92316182fc368200a306abf44e126254e3e4a5dba74d2b5`
