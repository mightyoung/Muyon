# Independent offline runtime review

Reviewed from fixed base `7fde617bab8f45644820590529def5b2f2193454`. Production code was not edited by this reviewer. Only synthetic host projections and offline Rust tests were executed; no gateway, provider, search, user files, existing unknown requests or reservations were accessed.

## Finding IR-01 — accepted dissent disappears when an unknown result resolves (P2)

In the reviewed formatted implementation, `collect` replaces the entire latest observation at `crates/muyon-core/src/group_runtime/mod.rs:601`; `summary` builds claims only from latest observations at lines 609–625. A valid Unknown observation carrying a contradictory source is accepted. A later valid Completed observation for the same original request with a higher sequence and a different supporting source replaces it. The summary then reports `disputed == false`, hiding the accepted contradictory evidence. The public observation contract does not require later events to repeat all prior evidence.

Reproduction source: `/tmp/mig20-independent-review.rs`, test `independent_unknown_resolution_preserves_observed_dissent`. Binary: `/tmp/mig20-independent-counterexamples`. Captured failure: `/tmp/mig20-independent-dissent-red.log`. Command: `/tmp/mig20-independent-counterexamples independent_unknown_resolution_preserves_observed_dissent --exact`. Observed result: **0 passed, 1 failed**, with `accepted earlier contradictory evidence vanished`.

Recommended repair: maintain latest child outcome separately from accepted current-epoch evidence history, preserving source versions and primary-origin deduplication. Unknown resolution may update terminal state without erasing earlier disagreement. Keep old-epoch evidence outside the current summary after handoff. A regression must exercise Unknown → Completed and Unknown → Failed with distinct earlier and later evidence.

## Verification and scope

- Original runtime suite: **13 passed, 0 failed** using standalone rustc.
- Existing governance suite: **21 passed, 0 failed** using standalone rustc.
- Cargo integration attempted with explicit toolchain: **blocked before test execution**, offline crates.io cache lacks `serde`. An earlier invocation without explicit RUSTC also failed before execution because rustc was absent from PATH; this is not a code failure.
- Runtime tests and source changed concurrently by the implementation owner; the 13-test run applies to the initial reviewed candidate, not a later candidate. Final revised-suite verification is recorded below when available.

No additional important defect was confirmed within the declared trusted-host boundary. Actual artifact resolution, durable snapshot completeness, host CAS, policy provenance and original gateway execution remain owner integration work, as documented by the candidate. Prepared/Submitted requests intentionally block a second advice until the host has resolved the original request; this review does not claim actual provider parallelism.

## Final recheck — IR-01 resolved

The owner repaired claim aggregation to read accepted current-epoch event history while preserving the latest observation for child state and speaker/artifact attribution. The independent reproduction was recompiled against the revised production module and now passes: **1 passed, 0 failed** (`/tmp/mig20-independent-counterexamples-fixed`). The original RED binary and log remain intact.

Independent final runtime verification: **19 passed, 0 failed** using standalone rustc (`/tmp/mig20-independent-final-runtime`). Cargo integration was rerun with the owner's now-available dependency cache and native library search path, and also passed **19/19**. Command: `CARGO_HOME=/tmp/mig20-cargo CARGO_TARGET_DIR=/tmp/mig20-target RUSTFLAGS='-L native=/tmp/mig20-native-libs' PATH=/tmp/mig20-rust/bin:$PATH /tmp/mig20-rust/bin/cargo test --manifest-path crates/muyon-core/Cargo.toml --locked --offline --test group_runtime`. Cargo emitted existing read/write extern signature warnings in `experiments/redesign/core-agent-lab/core/src/host_session.rs:132`; they did not fail this test. The earlier cache/toolchain failures remain historical evidence, not final blockers.

An additional minor status/advice boundary inconsistency at exactly the budget ceiling was communicated and repaired by the owner (`>` for status overflow/exhaustion, preserving legal zero-reservation advice). The revised `projection_and_advice_share_round_budget_and_capacity_boundaries` test passed. No remaining important defect was confirmed in the reviewed offline candidate. This is not a production gateway, durable CAS, Android integration, real-model parallel execution, or full repository test-suite certification.

## Final 20-test candidate supplement

Independently recompiled and reran the final runtime suite after the additional `exact_budget_allows_zero_reservation_without_hiding_unknown_usage` test: **20 passed, 0 failed; compilation exit 0; test exit 0**. Complete stdout, stderr, command and exit status are preserved in `evidence/independent-final-runtime.log`. No additional production changes were reported for this supplement.

Historical independent IR-01 reproduction source and original RED output have been copied byte-for-byte to `evidence/independent-ir01-historical-reproduction.rs` and `evidence/independent-ir01-red.log`. The source is a historical test snapshot from around the 18/19-test candidate transition and does **not** represent the final 20-test suite; its absolute production imports read the current repaired module when recompiled. `evidence/independent-ir01-evidence-note.txt` records this limitation.

The author reported a prior full Cargo suite run of 187 passing tests for the 19-test candidate and is rerunning the final candidate separately. Those full-suite results are author-run evidence and are not claimed as independently executed by this reviewer. The independent Cargo verification above covered only the runtime integration target for the 19-test candidate.
