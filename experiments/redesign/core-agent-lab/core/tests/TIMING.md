# Batch4 timing investigation

The original Batch3 logs remain read-only under `/workspace/leaderb-b3-evidence`.
New raw results and source manifests are under `/workspace/batch4/evidence/timing`.
The fixed input is d25a407830ef624802583983c0be2414bbd59dc4.

## 100ms idle helper PID

`wire_provider::respond_controlled` starts the exchange deadline before spawning
Python. The test helper writes its PID only after Python startup and several
imports. The old test unconditionally read that file after a 100ms idle timeout;
a correctly killed/reaped child need not have run far enough to create the file.
The original log has ENOENT at `wire.rs:110:356`, not a failed reaping assertion.

Adding a controlled 150ms delay before PID creation reproduced ENOENT (exit101),
after both ordinary hold modes passed. The test now pauses at the existing
`wire-open` checkpoint until an actual live PID and the requested hold mode have
been observed. It then releases Rust and checks its timeout and reaping. The
100ms idle and 500ms total deadlines still start before spawn and are unchanged;
readiness time is not excluded from either budget. In delayed cases the timeout
may already be due when the checkpoint is released. These cases verify cleanup
of the observed hold, not a fresh 100ms window after readiness.

The test owns a new process group, bounded readiness/completion waits, and a
checkpoint-EOF cleanup path with a process-group kill fallback. A fifth subcase
drops the run at the checkpoint and asserts both Rust and helper disappeared.
An external negative control removes only product kill/wait cleanup; the test
then fails specifically with `child must be reaped`. Its negative harness adopts
and reaps the deliberately leaked helper. That forced cleanup is not counted as
product success. No product source change is needed for this test race.

## 5000ms escaped-pair/read-bound1

The original failed run had sent331/received272 bytes after the helper emitted377
bytes. Each configured one-byte write/read invokes `AgentControl::charge`, which
saves task state with file fsync, rename and directory fsync. These operations,
Python startup, host scheduling, and the stream pump all consume the original
5000ms exchange deadline. The deadline is checked between operations; synchronous
fsync is not preempted by the deadline.

Run the causal experiment with an actual Rust executable:

```sh
python3 core/tests/timing_diagnostics.py --binary /absolute/path/to/muyon-core-agent-lab --evidence-dir /absolute/external/evidence
```

The script uses the unchanged escaped-pair fixture and explicit 5000ms total /
2000ms idle limits. It compares chunks8192/1/7 with and without a 5ms delay per
fsync. The shim still performs every real fsync. Without injection all three
complete; with injection chunk1 times out after receiving part of the actual377
bytes, with zero effects, no resend on reopen and reaped helper, while chunks8192
and7 complete with the same physical value/receipt. Three preparatory runs
reproduced this contrast; the final pinned run is recorded separately.

This establishes a reproducible persistence-cost amplification mechanism and
shows the total budget includes host work. It does not identify the exact disk
latency or scheduling events in the historical run: Batch3 retained no syscall or
scheduler trace. Neither a later green run nor this injected failure closes that
historical attribution gap. There is no evidence justifying a product deadline,
chunk-bound, or durability relaxation; all are preserved.

## Verification and scope

The default-parallel complete core suite retains115 tests (including six unit
tests). Actual physical process26 and wire18 checks are also run separately.
Initial RED/GREEN development runs were made with dirty test inputs over d25;
those HEAD labels are not claims that the entire tested tree was clean d25.
The final pinned regression/causal runs record the commit and test-source hashes.
Runtime `core/src` is byte-identical to d25; the release executable SHA256 is
b3624c75a99cb83bd1b53f3fec5ce7403d98b2f09043955b3806a998aea5d6d5,
which also matches the original Batch3 wire-process binary.

The two inherited Rust1.99 warnings about C read/write pointer signatures in
`host_session.rs` remain outside this test-only change. No official gate script,
workflow, Android code, or production memory behavior is changed.
