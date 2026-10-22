# CORE-HTTP-SYNTHETIC: bounded loopback transport

2026-10-18 UTC. Writer: core owner. Base: PR85 design head
`3024d723b6bad007feced165051bab7439862786`. This is an explicitly bounded
synthetic transport slice; real endpoints, credentials, models, fees, devices and
deployment were not used. Only LeaderB/root may integrate or dispatch remote CI.

## Delivered boundary

Implementation: `d15d5a488e1150a1461d50215b09f99ad06e84d7`.
Reachable behavioral RED: `3c7233a` (compiled, assertion failed with
`HTTP_LOOPBACK_TRANSPORT_RED: http_transport_not_implemented`, exit 101).

Only core `src/http_transport.rs`, `tests/http_transport.rs` and the necessary
`pub mod http_transport` in `src/lib.rs` change. No host, public plugin schema,
Android, Dart, authority policy, receipt store or existing Agent drive logic was
changed. The transport is not wired to the product gateway by this slice.

`LoopbackHttpTransport::new(LoopbackHttpConfig)` accepts a numeric loopback
socket address and bounded idle/total/HTTP-response-byte limits. No DNS, remote
address, credentials, TLS, redirect following or retry exists. The path is fixed
to `/v1/chat/completions`. Response framing supports Content-Length or connection
close; transfer-encoding/chunked, upgrade, non-200, conflicting framing and wrong
content type fail closed. SSE body is returned to the existing decoder, which
requires complete terminal framing before producing a model event. This is a
synthetic HTTP contract, not a general OpenAI-compatible networking client.

`exchange(payload, control, review) -> Result<Vec<u8>>` passes the same exact body
to `review` before connecting and before each subsequent socket I/O operation.
The callback must synchronously recheck current authority, purpose, projection,
classification and source/receipt eligibility. `ProviderControl::poll` observes
current cancellation. Actual sent/received HTTP bytes (including headers) are
charged; insufficient initial request budget prevents connecting. The connection
attempt is single and capped at 50 ms; nonblocking I/O checks idle/total deadlines.
No record or model narrative can authorize this callback.

## Host integration contract and remaining work

The actual `ModelGateway`/`OfflineEndpoint` seam and final `review_payload` live
in `rust-agent-host-lab/core/src/model_gateway.rs` and `src/lib.rs`, owned by the
native host owner. That owner must supply an adapter and real current-authority
callback, preserve the exact admitted body in the durable outbound journal, and
provide a control implementation whose accounting remains durable under faults.
Existing `AgentControl` rejects `charge`/`checkpoint` for host ports; this slice
does not conceal or remove that limitation.

Transport errors can occur after some request bytes reached the server. An error
is not proof of no remote effect. The host must retain unknown/receipt barriers,
never automatically resend, and apply its existing recovery contract. SSE
argument observations are not completed invocations. No new host ABI is added.
Transport tests do not establish gateway/Agent-drive end-to-end admission,
durability or receipt correctness; those integrated tests remain separate.

## Executed evidence

Rust: `rustc 1.99.0 (b940084d7 2026-09-28)`. No dependency installation. The
shared pre-existing toolchain and one small core target were used:

```sh
env CARGO_HOME=/tmp/muyon-tools/cargo RUSTUP_HOME=/tmp/muyon-tools/rustup \
  PATH=/tmp/muyon-tools/cargo/bin:/usr/local/bin:/usr/bin:/bin \
  CARGO_TARGET_DIR=/tmp/muyon-build/core \
  cargo test --offline --locked -j2 \
  --manifest-path experiments/redesign/core-agent-lab/core/Cargo.toml -- --nocapture
```

Full core crate suite: **105 passed, 0 failed**: unit 4, host 32, HTTP transport 11,
kernel 21, native ports 1, native protocol 5, wire 27, wire review 4. HTTP tests
exercise actual loopback traffic/exact payload, nonloopback rejection, zero-byte
cancellation/budget failure, final review after connect, truncation without retry,
incomplete SSE call rejection, cancellation/revocation after send, exact remaining
response budget, idle/total deadlines, invalid HTTP framing and the existing
Agent unknown/evidence-hold barrier before provider entry.

Two inherited warnings remain at `host_session.rs:132`: Rust 1.99 flags the
existing extern `read`/`write` pointer signatures. There are no new transport/test
warnings. No test failed in the full run.

Raw evidence outside Git:

| File | SHA256 |
|---|---|
| `/tmp/core-http-transport-red.log` | `616939c6bf8a9bfc5da214a81aeba7358b15182373f6b6dc35fdcc162ed9eaaa` |
| `/tmp/core-http-core-suite.log` | `1be466af9933bc5e60e32eaa9b7396c6cf113b87167b444368f28d013e0d552b` |
| core `src/http_transport.rs` | `ad8d20829e23b6981f390d8ac6e0679b8e6d8bd4365c32172bfd484040f80af1` |
| core `tests/http_transport.rs` | `98d874da58ba46adbce64688e931b371d3b4694d672b1bec83a4f18461dc04da` |

Independent review, remote CI on the final SHA, host gateway integration, Android
integration and real endpoint/model tests: **NOT_RUN by this owner**.

## Memory candidate remains frozen, not implemented

Latest user gate: structured failure/decision/evidence records, transactional
compression/recovery and neural soft memory require evidence of experimental
utility before implementation. The earlier isolated `context-memory-lab`
candidate/spec is frozen at `962a58ab5b32a05947343414289c9aab5ff89661` with an
unimplemented projection stub. It was not executed; it is not needed by this HTTP
slice and must not be described as an effective or admitted capability. Its
synthetic protocol checks cannot establish model utility even when later run.

All original PR85 new design acceptance cases remain **NOT_RUN**:

| ID | Still unexecuted design acceptance |
|---|---|
| CTX-T01 | Repeated failure after compression |
| CTX-T02 | Re-evaluation after changed tool/version/conditions |
| CTX-T03 | Partial real-user decision supersession; forged replacement rejection |
| CTX-T04 | Unknown preserved across actual compression |
| CTX-T05 | Compression cancellation/revocation and late receipt |
| CTX-T06 | Call/result pairing and unsent input across compression |
| CTX-T07 | New-turn CAS collision and bounded rebuild |
| CTX-T08 | Atomic compression publication, crash/restart |
| CTX-T09 | Forgetting, disabled memory and backup tombstones |
| CTX-T10 | Rewritten/missing/cross-scope compression sources |
| CTX-T11 | Summary failure and budget fallback validity |
| CTX-T12 | Optional/malicious plugin context contribution, third domain |
| CTX-T13 | Repeated compression and model/backend compatibility |
| CTX-T14 | Both clients display all actual compression states |

No original PR85 documents or acceptance status were edited. The existing Agent
unknown test in this slice is not a CTX-T04 compression acceptance run. PR85's
prior docs-only CI/static review is not model-effectiveness evidence.
