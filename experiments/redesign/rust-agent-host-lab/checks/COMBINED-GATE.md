# Exact combined candidate gate

The d25 source adds eight core and eleven host tests to the product contract.
`cases.json`, its product classifier default and all existing classifier controls
remain unchanged. `full.py --contract combined` uses the named additive
`http_batch.contract()` (115/22/59); missing, renamed, repeated, skipped or
filtered cases remain INVALID. This is an explicit contract selection, not a
fallback after failure. The full shell gate now selects this combined contract.

The old stale-usage mutation matched `wire.is_some()`; d25 clears stale usage
under `wire_counters.inflight` instead. Only this exact validation anchor was
updated. All 17 broad legacy inverses still run. In addition, `legacy_precise.py`
requires all sixteen exact Rust baseline/mutant pairs, exit101, the exact panic
source location and semantic assertion, natural owned cleanup, and raw hash
identity. `test_legacy_semantics.py` retains all 144 batch3 rejection controls.
The physical seventeenth retains the actual ACK and preterminal-effect oracle.
The precise contract is derived from the reviewed batch3 code and is now local
to the repository; no external runner or historical result is accepted by CI.

Historical HTTP runner defaults remain exact8e. `--expected-source` explicitly
selects a new candidate and requires a full lowercase 40-character SHA matching
clean HEAD before execution/archive. Formal full/native/HTTP execution always
uses `combined_gate.py --expected-source SHA`, which also freezes every tracked
source file and checks source and scoped baseline-binary integrity afterwards. Full components require a retained executable manifest; native3 references and verifies its own summary baseline seals. HTTP7 has no retained outer baseline executable manifest and explicitly reports `not_recorded` with `verified: null`, never an inferred integrity pass. Evidence
and target directories must be outside the checkout; default Rust parallelism
is required. Source mismatch, dirty inputs or any failed gate fails closed.

`.github/workflows/leaderb-combined.yml` runs core, plugin, host, native3 and
HTTP7 in five independent required matrix jobs. Core includes process26,
wire-process18, harness6+7, broad legacy17 and precise legacy16. Every job runs
all old/new classifier controls and uploads raw evidence even on failure.
Automatic push is restricted to `lab/leaderb-batch4-combined-20261018` and checks
out `github.sha`; optional dispatch accepts an exact `source_sha`. The generic
Flutter `ci` push filters do not match this lab branch. New workflows may need
an automatic branch push before dispatch is available on the default branch.

Local controls are classifier evidence only. Android/package/device and remote
CI acceptance are separate obligations; no batch3 result certifies a new SHA.
