# Task 3 — independent host-chain checker

Frozen inputs and expectations: commit `6795ce0`, based on approved contract
`2cd3ad0`, before new DUT implementation was read. See
`experiments/redesign/core-agent-lab/host-checks/EXPECTATIONS.md`.

Owned files are `apps/muyon/test_host/**`, `host-checks/**`, the new
`core-agent-host.yml` workflow and this report. No existing tests or product code
are changed. Positive tests use the real facade, gateway, authorization, ledger,
registered inquiry.object handler, native registry receipt and compiled Rust.
Fake HTTP implements transport only. The recorder forwards exact bytes and
waits for the child; fake child data is confined to recorder self checks.

Required workflow builds the std-only Rust binary with `cargo build --offline
--locked --release`, records source/binary SHA, then explicitly invokes
`flutter test test_host/core_agent_host_test.dart --reporter expanded` with an
absolute `MUYON_TEST_CORE_AGENT_BIN`. Missing binary is a load error. The default
full suite permits no skipped tests. Workflow dispatch `suite=positive-red` is
an explicitly labeled initial compiling-stub subset, never full GREEN evidence.

The positive test asserts successful terminal task state before inspecting IPC,
so a compiling unavailable backend yields semantic assertion RED immediately.
Expected metadata comes from the fixture's selected actual reference. The second
model response is conditional on the exact projected result; raw native record
data remains observable only in the local receipt.

Validation pending actual GitHub runner execution. Local Rust, Flutter and Dart
are absent; no local compile or product PASS is claimed. Python recorder self
checks are executable locally. Device and real-model evidence: NOT_RUN.

Raw outputs remain outside Git. Root owns fixed-SHA integration, runner evidence,
non-author review and the draft PR. No merge is authorized.

Additional negative tests use a clearly separate artificial child to exercise
malformed frame lengths/UTF-8/keys, integer typing, wrong correlation, duplicate
callbacks, untrusted stderr and fabricated receipt terminals. They are never
substitutes for the positive Rust roundtrip. Effective tool confirmation/denial,
identifier bounds and incomplete SSE responses are also covered.

Local checker verification: `python3 -B
experiments/redesign/core-agent-lab/host-checks/test_record_process.py` reports
2 tests OK, covering byte transparency/reaping and terminal no-skip enforcement.
`git diff --check` passes. This is helper evidence only, not Rust/Dart execution.
