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

## C2 lease regression and final native fix verification

Receipt-only green on131 and d1 does not close C2: source review found a panic-unwind lease drop before reacquisition. The original green results are retained as diagnostic history, not complete C2 closure.

A separate `service_fault_c2_lease_red_cases.json` pins131 and uses `service_lease_fault_probe.rs`. Only the private copy adds `private_probe_worker_finished`, which reads the real JoinHandle::is_finished. The test waits boundedly using yield until the real worker completes, **without calling await_settled**. A separate Python process opens the actual `.lock` and executes nonblocking kernel flock; no controller process slot participates. Old131 actual result: available before join, accepted exact semantic RED101; receipt inspection tail NOT_RUN. Evidence `/tmp/service-fault-131-lease-red-evidence`.

Final native source is frozen at `6e0f1c5752515c2bb8318897832912c57b8d1090` in independent `service_fault_green_cases.json` and `service_host_46_green_cases.json`. The original RED descriptors stay unchanged. Three actual fault runs all accepted diagnostic GREEN0:

- `/tmp/service-fault-6e0-c2-evidence`: Unknown+actualRecordedSuccess+originalopaque, unchanged native.db; worker-finished-before-join child flock Busy, afterjoin Busy, actualClosed Available.
- `/tmp/service-fault-6e0-c3-evidence`: Cancelled+actualRecordedSuccess+originalopaque and unchanged bytes.
- `/tmp/service-fault-6e0-ledger-evidence`: explicit failedledger IO yields Unknown+actualRecordedSuccess+originalopaque, unchanged bytes; Unknown takes priority over cancellation.

The lock Python source hash, selected Rust probe hash, original/private controller hashes, exact source SHA and descriptor hash are recorded in per-run provenance.json. The independent reviewer received both old lease RED and final green evidence.

Source-first host46 inventory is exactly native25+contract8+runtime2+root2+controller4+oracle1+lifecycle4. The first actual default-parallel run at `/tmp/service-host-6e0-46-evidence` is INVALID: native24P1F (`native_store_persist_budget_never_writes_unreadable_snapshot`, reopen after drop returned directory_locked); all other21 passed, including lifecycle4. Preserve this failure. A fresh full46 run using RUST_TEST_THREADS=1 is recorded separately in `/tmp/service-host-6e0-46-serial-evidence`; no source changes or skipped tests. Possible concurrent fork FD inheritance is only a hypothesis, not a proven cause.

Serial final host46 actual result: accepted `diagnostic_host46_green`, exit0, all46 passed. This executes the original entire lifecycle4 test, including the byte-preservation tail that old RED could not reach. Controls:62 passed. Default-parallel failure remains an explicit limitation; no full shipping claim.

Additional evidence SHA256:
- `/tmp/service-fault-131-lease-red-evidence/cargo.log`: `df999aa452ca36672e0a8521d91103d60040ff2a27af1b9997259906f6ce9c13`
- `/tmp/service-fault-6e0-c2-evidence/cargo.log`: `158d4218b12aefb234a2c95a16f65a71a8313d5d8449a9dc0ea45905a602b972`
- `/tmp/service-fault-6e0-c3-evidence/cargo.log`: `5069272755aa5075ce7dde158c9b075007aa4e6fb663da500f930616ca34af5d`
- `/tmp/service-fault-6e0-ledger-evidence/cargo.log`: `0aabc0c5400d437675a05dc597dff53b1a39ead85dcbe8da3bff4a41278cbdc1`
- `/tmp/service-host-6e0-46-evidence/result.json`: `8247b299d126e0f3b384823bebaffde65094e82585a8a8d6da6028ac075ec882`
- `/tmp/service-host-6e0-46-serial-evidence/result.json`: `586dcd59a3f95ad5835956a953cbace6be7960f35e7ef37dadf5662aedfa7581`

## Full-gate source-first inventory delta

`rust-agent-host-lab/checks/cases.json` now describes the intended integrated inventory; this is **not combined-run evidence**:

- Core105 = existing94 plus `integration:http_transport`11, independent family `synthetic-http-transport`; source final03c1628631a07762ac9961f7162d1e49343ca2b8 (implementation d15d5a488e1150a1461d50215b09f99ad06e84d7).
- Plugin22 = existing21 plus `foreign_data_admission_requires_the_referenced_schema_closure` in registration9; source final69a98a8ac9dcc356a2787ca96569fc589bb2d368 (implementation fc728271f9056f706a62e61036443f74080dff58).
- Host46 = existing45 plus `incomplete_temp_evidence_blocks_ready_without_cleanup` in lifecycle4, final6e0f1c5752515c2bb8318897832912c57b8d1090.

Names and test-source SHA256s were read directly from these immutable Git objects. Every old case, family, Python gate, and17 mutation obligations is preserved. `full.sh` and mandatory workflow scheduling/test concurrency are unchanged. Full classifier controls10 pass and reject missing new cases. Independent branch successes remain separate from future combined full-gate execution. The serial46 run is diagnostic only; the earlier default-parallel native lock failure remains open for writer investigation.

C3 verification currently covers turn2cancel and explicit failedledger priority. Deadline-origin followed by latecancel is **NOT_RUN** and not implied closed by those probes.

Core lock inventory follow-up: core107 retains105 and adds the two actual `store::lock_tests` unit names read from fixed c9a31c4cc9538ae7e480fc8920c833ba8966dd58, test commit950406c. `unit:src/lib.rs` now has6 names (legacy-core family90 includes prior88 plus these2); native6 and HTTP11 remain separate and unchanged. The source module hash is pinned. Plugin22, host46, Python obligations and17 mutants remain unchanged. This is source inventory, not a combined-run result. Default parallel full.sh is untouched. Classifier controls11 pass and reject either missing lock unit.

## C3 deadline-origin then late-cancel regression

The earlier NOT_RUN limitation is now replaced by separate actual RED evidence, without changing any old three-case descriptor. New `service_deadline_red_cases.json` pins final6e0 and a dedicated Rust probe that checks summary.reason as well as terminal and actual original receipt/opaque/bytes.

Only in the private source copy, RunControl.deadline becomes Mutex<Instant>, preserving the original5s construction. The actual built-in endpoint turn2 sets this actual deadline to now and executes its original poll; the original Instant comparison emits `FAULT_DEADLINE actual_poll=expired`. No sleeps and no fabricated Err/provider override are used. After real run completion, assert status=budget_exhausted and reason=host_budget, then request late cancellation. Core::drive intentionally rewrites budget_exhausted reason to host_budget, so original native_deadline is established by the real-poll marker, not inferred from this overwritten State string.

First attempt `/tmp/service-deadline-6e0-red-evidence` is INVALID: the probe incorrectly expected State.reason native_deadline and panicked before its receipt tail; retain it as a setup assertion failure. The corrected source-observation probe at `/tmp/service-deadline-6e0-frozen-red-evidence` actually accepted strict semantic RED101: terminal BudgetExhausted/reason BudgetExceeded instead of required DeadlineExceeded, with actual RecordedSuccess/exactopaque and native.db unchanged. All63 Python classifier controls pass. Native writer received the actual RED to activate a first-observed-stopcause fix; GREEN is pending.
