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
