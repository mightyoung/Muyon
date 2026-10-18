# Rust business/controller handoff

## Implemented path

`submit_supplier_read(client, request_id, text, key, revision)` → existing
`AgentServiceController::start_internal` → same root lock / one worker / owner /
`RunControl` → durable admission → atomic `source.db` semantic payload →
`supplier_lab_source::run_lab_supplier_read` → actual schema12 SQLite source →
registered trusted `inquiry.supplier_name` Agent dispatch → original `native.db`
receipt → bounded ordered answer/projection/receipt/terminal ledger →
`supplier_read_events(client, request_id, after)`.

UniFFI exposes those exact two String-returning methods. Old summary ABI is
unchanged. Cancellation uses existing `cancel`, Inquiry variant, same request/run.
No second controller, model driver, network endpoint, production source or external
plugin path was introduced. Existing Service isolation remains unchanged.

The fixed source is explicitly synthetic: key
`11111111-1111-4111-8111-111111111111`, revision `7`. The store worker owns its
immutable source and synthetic authority implementation. Unsupported production
selection cannot obtain this authority.

## Identity and recovery

- Semantic payload includes exact chat text, supplier key and revision; lease is
  excluded. Changed payload or a legacy run using the ID is a request conflict.
- Submission initially returns `accepted / queued_volatile`; durable run identity
  appears through polling. No queued-only reply claims durable acceptance.
- The same controller controls visibility, release, cancellation and teardown.
- Reconnect polling restores original admitted epoch/run and event ledger. It
  validates original durable receipt binding and current synthetic source before
  disclosing any values. It never dispatches another read.
- Receipt corruption or source replacement returns `unknown /
  DISCLOSURE_UNAVAILABLE` with no business events.
- Interrupted runs retain UNKNOWN. A genuinely recorded receipt survives overall
  cancellation/storage/disclosure failure when its binding can still be validated.
- Events are a bounded poll stream, currently produced as one ordered terminal
  batch for this short local read. No token/model streaming is claimed.

## Verification

Command (official Rust toolchain installed by integrator):

```sh
env CARGO_HOME=/workspace/toolchains/cargo RUSTUP_HOME=/workspace/toolchains/rustup \
  CARGO_TARGET_DIR=/workspace/build-targets/rust-business \
  /workspace/toolchains/cargo/bin/cargo test \
  --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml \
  --test supplier_business_controller --test service_controller --test service_runtime
```

PASS: 7 tests (4 existing controller, 2 existing runtime, 1 new end-to-end Rust
business test containing admission/payload binding/original receipt/replay/cursor/
epoch/unknown/corruption/revocation/cancel assertions).

`rust-logs/controller-green.log` is the final run. The initial
`rust-logs/business-red.log` records an actual failing read using the wrong
synthetic selection; correcting the test to the store-owned fixture produced
`rust-logs/business-green.log`. This is not evidence of a complete test-first
implementation cycle.

No I04 HTTP suite was run. Existing core ffi declaration warnings are recorded in
the logs; they predate this slice.

## Remaining evidence and limits

Android/API26 Binder and native artifact composition: delegated to Android worker
and integrator; this report alone does not establish device execution. Live model:
NOT_RUN. Production current ScopeResolver authority bridge: unavailable/fail-closed.
There is no model API/credential configuration or model call in this change.
