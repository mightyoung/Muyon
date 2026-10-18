# Service host native follow-up — 2026-10-18

Owner scope: `rust-agent-host-lab/core`, `android-rust-bridge-lab/core`, this task document. Base `f711fe31cf2f7d5b4be692708efca183ede090a0`; product baseline `81424c87`; frozen C4 test `126374094e7d5e8a5cf1ed901328d852b2dc1943` remains unchanged. Contract/ABI and implementation plan remain `docs/design/android-agent-service-20261015/`; no Core/Plugin, public API, checker or Android writer ownership changes. Root alone imports/pushes/dispatches/integrates.

## C1: prompt connect entropy

Source commit `a9a1dddbfe12bdf57230ee85f0bc603fe29d8b40` prepares exactly two client lease nonces in the existing Service background constructor, before controller publication. The existing epoch nonce is separate. Any entropy error returns InternalFailure before acquiring the process slot. `connect` consumes a prepared lease with `pop`, and performs no entropy or filesystem operation while holding the controller mutex. The existing same-key repeat path precedes consumption; the two-entry inventory including inactive tombstones precedes consumption. Leases are never replenished or recycled. Closing/Closed read-only reconciliation retains the existing remaining capacity.

Validation performed: `git diff --check` passed. Source inspection confirms the only new entropy calls are in construction, exactly two client slots are allocated, and repeated connections return the original lease before pop. Existing `client_epochs_generations_and_visibility_are_fail_closed` and `close_and_reconnect_preserve_original_durable_outcome` are relevant runtime siblings. Rust compilation/tests are **NOT_RUN** here: `cargo`, `rustc`, `rustfmt` are absent from PATH and no local toolchain is installed. Remote fixed-source compilation is required. No previous 45-pass diagnostic is claimed as C0 or this commit's test result.

## C2/C3 probe handoff, before product fixes

C2–C4 product fixes remain paused until root/checker confirms actual semantic RED. These are private source-copy injection requirements, not shipping changes. Checkers own source hashes, descriptors, exact test inventory and classifiers; no new shipping FFI, Cargo feature, alternate provider, widened authority or replacement Agent loop is required.

Fixed source for C2/C3: `a9a1dddbfe12bdf57230ee85f0bc603fe29d8b40`. SHA-256:

| File below `experiments/redesign/rust-agent-host-lab/core/src/` | SHA-256 |
| --- | --- |
| service_controller.rs | 544b82853e24b877f2e01d241aaa44f9efab9f1d5200311525ec365fd893a2c9 |
| service_runtime.rs | 0790d6ebd5b04a776036bf2c05a13d19eec90379a120c786056a38f40c39164a |
| model_gateway.rs | 18fff57d394562742abb3bb3c3a8fb5e9f9d34ad78dfff070b67a4ead8a78410 |
| store.rs | eaec3e50d7ddabfdbfa3250276228d4df395bbe4af8fcbcb872098eed722192e |

C2 unique insertion anchor in `service_controller.rs`:

```rust
    // Preserve original receipt success even when overall cancellation or storage failure occurs.
```

This is after the real `run_builtin_admitted` returns and before receipt reconciliation/summary persistence/`Completion::Executed`. In the private source copy, assert the real execution succeeded, original `service_evidence::receipt(&dir, &run)` is RecordedSuccess with Some opaque ID, and original `native.db` contains the matching persisted row. Save original bytes/opaque identity into test-owned observation storage before an actual `panic!`. Do not use the diagnostic observer as a panic hook: its callback is caught by `catch_unwind`. The actual worker's JoinHandle must return Err; `await_settled` must publish unresolved uncertainty while preserving RecordedSuccess and the exact opaque ID. Require unchanged original native bytes across current/lookup, no replay/new drive, and RecoveryRequired. Existing code calls the generic `unknown()` constructor in JoinError and loses the committed receipt; this is source evidence, not an executed RED claim. A healthy sibling must complete the same original read and expose matching original receipt bytes.

C3 unique replacement anchor in `service_runtime.rs`, inside the actual `BuiltinEndpoint::exchange`:

```rust
        self.control.poll()?;
        control.poll()?;
        let position = self.frames.borrow().len();
```

Immediately before the first original poll, only when `self.frames.borrow().len() == 1`, request `self.control.request_cancel()`. Keep the original poll and real ModelGateway, physical source, NativeStore, outbound ledger and same Agent drive. Turn one has physically read and committed the receipt; turn two has reached the actual endpoint but must not admit a second successful frame. Assert Cancelled/Cancelled with RecordedSuccess and exact original opaque ID/bytes, rather than Failed/InternalFailure. Preserve a healthy two-turn sibling. Deadline is the same lost-reason class, but do not simulate it using a slow sleep or count an unexecuted deadline probe as evidence.

Failed-ledger sibling: in a separate private source copy layered on the C3 cancel injection, inject `Err("probe_failed_ledger_io".into())` on the actual `NativeStore::ledger` call whose `status == "failed"`, after an explicit reached marker. The method's unique signature is `pub fn ledger(&self, status: &str, body: &[u8]) -> Result<()>`. Keep begin/sent paths intact. This is a bounded synthetic port failure, explicitly **not disk-full or ENOSPC evidence**. The actual ModelGateway failure path uses `ledger("failed", &bytes)?`; require Unknown to take priority over observed cancellation while retaining original RecordedSuccess/opaque/native bytes. Cancellation must not normalize this I/O uncertainty into normal Cancelled. The checker must distinguish reached failure from setup/panic/compile errors.

Existing checker entry points are `android-rust-bridge-lab/checks/host_checkpoint.py`, `linux_gate.py`, and the source-frozen `service_temp_red_cases.json` for C4 only. No C2/C3 descriptor or executed private probe existed in this restored workspace at handoff; checker owns adding them. Require exact-once anchor matching and source hash rejection before injection.

## C4 preserved frozen target

`incomplete_temp_evidence_blocks_ready_without_cleanup` remains byte-identical. A valid prior terminal plus `.task.db.9.1` currently passes root census as a recognized candidate and restoration ignores it. Required actual RED remains the existing `SERVICE_TEMP_RED` assertion with the other 45 host cases healthy; setup/compiler errors are INVALID. After actual RED, correction must retain candidate/original evidence bytes and original receipt, publish RecoveryRequired and refuse new drive. No cleanup or expectation relaxation is authorized.

## Actual RED activation and fixed-source corrections

Checker executed the private probes against source `a9a1dddbfe12bdf57230ee85f0bc603fe29d8b40` with shared Rust 1.99.0. C2 accepted semantic RED exit 101: before-panic RecordedSuccess persisted, post-join OutcomeUnknown/Unknown lost exact opaque, original native bytes unchanged (`/tmp/service-fault-c2-actual-evidence`). C3 cancel accepted semantic RED exit 101: actual Failed/RecordedSuccess with original opaque (`/tmp/service-fault-c3-actual-evidence`). C3 failed-ledger initially classified INVALID because the diagnostic expected GREEN; actual explicit `probe_failed_ledger_io` returned Failed/RecordedSuccess, so the checker froze a separate RED descriptor without changing the required Unknown expectation. This is injected I/O failure, not disk-full evidence. C4 actual frozen source composition `1fc398c` accepted semantic RED exit 101 with 45 passing and the single original incomplete-temp failure (`/tmp/service-temp-red-actual-evidence/verdict.json`); byte-preservation assertions after the failing assertion remained NOT_RUN in RED.

After root explicitly activated fixes, independent product commits were C2 `131fd0d54a57496f40a9e967c963ade218f60f69`, C3 `8d4c6a92be92bde18943ba061764eea46bafd1fd`, C4 `d1d3d3cb75165215da8a5cfbfeb40ecda5186c41`. C3 preserves endpoint native_cancelled/native_deadline only after the real failed ledger succeeds; a ledger Err becomes a distinct model_ledger_failed signal that Service RuntimePorts classifies OutcomeUnknown/StorageFailure. Begin/sent ledger errors use the same uncertainty precedence. Legacy child failure mapping remains unchanged. C4 keeps recognized atomic candidates in place, poisons admission and restores RecoveryRequired while retaining validated original summaries and receipts. Old test fixtures and checker expectations are untouched.

The first C2 receipt probe GREEN at `131fd0d` proved original receipt recovery only. Independent review and owner self-review identified that its post-panic RootLease reacquisition still left a cross-process flock gap. It is superseded by lifecycle correction `bd20de7ed3aee1b7aeec8757d9ef5b19b38000d8`: the worker outer closure owns the original root; execute only borrows it. catch_unwind saves that same root to controller storage and immediately resume_unwind continues the original panic, so the real JoinHandle still returns Err. The waiter reads original durable index/receipt outside the controller mutex, keeps overall Unresolved and retains the original flock until true Closed settlement. Spawn rejection returns the same unconsumed root via a bounded single-use transfer slot. There is no post-panic reacquisition or replacement Agent. The process slot also remains occupied. The checker has been asked to add an actual child-process flock contender: Busy after panic/join and before true Closed, lockable only after Closed; same-process PROCESS_OCCUPIED is not accepted as flock evidence.

C1 independently passed source C0 at `a9a1ddd`; source review is not runtime GREEN. Initial local rustfmt attempts could not run (component unavailable); no component was installed. Product `git diff --check` passes. Shared toolchain availability supersedes the earlier no-toolchain observation, but builds are coordinated through checker to avoid duplicate targets. Final same-probe and all-46-host GREEN plus fixed-source independent lifecycle review remain pending at this writing. No Android/device/real-model execution or new FFI/API is claimed.
