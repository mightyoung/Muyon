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

Read success and dispatch definition do not prove dispatch write permission. Verify remote SHA again immediately before dispatch. Source126 and temp RED remain distinct from diagnostic native45 success38772045455 and Android handoff14 run38773509116. No full shipping claim.

## Separate C2/C3 fault descriptor

`service_fault_cases.json` pins native-owner C1 source `a9a1dddbfe12bdf57230ee85f0bc603fe29d8b40`, four exact source SHA256s, and separate expected/observed terminal contracts. It does not modify legacy45 or temp46 inventories.

`service_fault_probe.py` obtains the entire Rust host and its two local dependencies via `git archive` of this immutable commit. It checks four hashes and unique anchors before writing private source copies. Original author source remains untouched. A new integration target lives only in the copy. The descriptor, Rust probe and original/private source hashes are written to evidence.

- C2: after real `run_builtin_admitted` returns, validate actual receipt is RecordedSuccess, save original native.db and opaque ID outside the service root, then panic on the real worker before Completion. After `await_settled`, require Unknown plus the actual original success receipt/opaque and unchanged bytes. Current expected RED observation is Unknown/Unknown with missing opaque.
- C3 cancel: at actual built-in endpoint turn2, request cancellation before its original poll. Require Cancelled plus original RecordedSuccess/opaque and unchanged bytes. Current expected RED observation is Failed plus RecordedSuccess.
- C3 failed-ledger sibling: same cancel injection plus explicit private-copy `store::ledger(status=="failed")` error `probe_failed_ledger_io`. Require Unknown plus original RecordedSuccess/opaque and unchanged bytes. This is a named injected I/O failure, **not a disk-full/ENOSPC experiment**. A successful sibling is diagnostic, never aggregate shipping green.

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

Other cases: `c3_cancel`, `c3_failed_ledger`. The runner uses exact `cargo +1.99.0 test --release --locked`, only `--test service_private_fault`, captured `--show-output`, one test thread and a 900s bound. `--prepare-only` is available. Actual C2/C3 Rust run is pending; no source-fix or native-behavior claim is made from Python controls.
