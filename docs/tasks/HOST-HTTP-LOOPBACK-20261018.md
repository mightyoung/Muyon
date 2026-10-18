# Native host synthetic HTTP candidate — 2026-10-18

Isolated candidate only. Base `aa0bc2cf` (b1 + f60); no push, dispatch, merge,
main change, real endpoint, credential, or model cost.

## Implementation

Only `model_gateway.rs` and the dedicated `tests/host_http.rs` implement this
slice. `LoopbackEndpoint` adapts existing core `LoopbackHttpTransport` to existing
`OfflineEndpoint`; each transport review boundary calls the same native session's
`review_payload` on the exact admitted body. Existing ModelGateway remains owner
of encoding, begin/sent/failed outbound ledger, response SSE parsing and final
answer masking. The adapter registers no plugins/tools and adds no authority or
budget state. Numeric loopback validation and no-retry behavior remain in core.
Gateway preserves native stop, wire budget, cancellation and journal reasons.

Every ModelGateway::respond_controlled entry invokes endpoint.validate_session.
LoopbackEndpoint rejects a different SharedSession using Rc::ptr_eq before
authority polls, ledger admission, or socket work. This also covers later
replacement of the public Gateway session/endpoint fields. Historical synthetic
endpoints retain a default compatible hook.
`model_sends` counts admission attempts, not socket bytes. Actual HTTP request
headers/body and response headers/body are counted by the core AgentControl,
which persists through the existing RuntimePorts and charges existing total.
Ledger `sent` means bounded response received, not semantic answer acceptance;
partial I/O failure records `failed` and makes no delivery certainty claim.

## Evidence

Native-only source commits: `75f3ce6e`, `99909d24`, `fe359f37`, `ba52cae3`.
Dependency: core owner `5d1fdf00` (host charge/checkpoint/shared total/inflight).
Exact tested isolated combination:
`21acf36875da91c75157fddf6ef88e68c677a2ee`, at
`/tmp/Muyon-host-http-combination-review`.

Default-parallel full host command, no RUST_TEST_THREADS override:

```sh
export PATH=/tmp/muyon-tools/cargo/bin:$PATH
export CARGO_HOME=/tmp/muyon-tools/cargo
export RUSTUP_HOME=/tmp/muyon-tools/rustup
export CARGO_TARGET_DIR=/tmp/Muyon-host-http-combination-target
MUYON_PLUGIN_CONTRACT_BIN=/tmp/Muyon-host-http-combination-target/debug/muyon-plugin-contract-lab \
 cargo test --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml
```

Result: **54 passed / 0 failed** (prior host 48 + dedicated HTTP 6).
Dedicated HTTP tests cover:

- Different endpoint/Gateway sessions refused before ledger creation or connection,
  with zero sent/received bytes and zero admission attempts (1 RED then 1 GREEN).
- Completed masked answer, exact observed request/response byte counters, shared
  total equality, and durable task fields/ledger.
- Truncated response, cancellation during pending read, and authority revocation
  during pending read; each terminal state is driven again and the actual
  listener rejects a second connection.
- Pre-send shared budget refusal and initial authority refusal with zero actual
  socket connections/bytes.
- Partial receive exhausting the shared total exactly, with no retry.
- Real request/response followed by synthetic panic before gateway completion:
  persisted provider_inflight=true, begin ledger (neither sent nor failed), and
  same-State subsequent drive refusing wire_interrupted with no second connection.

Raw logs and SHA256 inventory are in `/tmp/Muyon-host-http-evidence/`.
`complete-baseline-red.log` retains 5 baseline failures without core charge fix;
`combination-http.log` retains the first combination (3 pass/2 failed) due to
incorrect test assertions expecting equals instead of actual tab task fields;
`combination-http-green.log` is 5 pass after correcting those assertions.
`final-full-host.log` is the earlier 53-pass result before the session guard.
`session-mismatch-red.log` records the real pre-fix unwanted connection;
`session-mismatch-green.log` records 1 pass with zero connection/bytes.
`session-guard-full-host.log` is the final 54-pass exact-source result.
`native-read-baseline.log` separately confirms existing native_read 25 pass with
only adapter changes. Compiler emits existing FFI read/write signature warnings.

## Limits and ownership follow-up

This is not f60 acceptance or live-provider evidence. There is no live credential,
real model request, Android/JNI/device execution, persistent HTTP session restore,
or production endpoint support. A fresh process must keep using host evidence
reconciliation (never resume/drive persisted task state); core State::load does
not accept this runtime empty-script schema. Unknown coverage intentionally uses
the same State and the durable inflight field, with no schema relaxation.

Existing RuntimePorts::failure maps wire_total_limit/wire_journal to generic
native_host_refused outside service mode (service also lacks dedicated mapping).
The gateway now preserves these error values, but terminal budget classification
is a follow-up owned outside this file scope. The tested guarantee is bounded
shared accounting and no automatic resend, not a new public error/status contract.
Rustfmt is absent in the installed toolchain; no toolchain mutation was attempted.
