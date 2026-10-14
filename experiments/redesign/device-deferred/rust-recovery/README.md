# RD-P02 provisional host recovery seam

This std-only, publish=false Rust crate is a reversible developer experiment.
It is not the M03 schema, a transport DTO, an authenticated receipt API, or a
production executor. Android actual load is NOT_RUN; M03 is blocked_contract.

Inputs are caller-provided synthetic facts, never fixture case IDs or expected
outputs. Domain requires exact store/scope/stream equality; seq completes the
event identity. Projection payload is an actual synthetic String applied by the
reducer. A gap buffers bounded event count, pulls from the committed checkpoint,
and switches to snapshot-required on overflow. Snapshot installation and proven
filtered advances are deliberately unsupported. Bytes budget and permission
verification remain future adapter responsibilities.

`commit` pairs projection and cursor in memory only. It proves no physical
persistence/atomicity/crash recovery. Reconnect restores this in-memory checkpoint
and discards uncommitted application/dedup state, so replay is possible. A future
adapter must atomically persist the pair before acknowledging delivery. The seen
map is a laboratory event history, not a bounded production journal.

Epoch uses equality only for display callbacks. Receipt reconciliation ignores
epoch and checks all original intent/action/attempt/scope/parameter values plus
receipt ID/effect against exact entries in an injected synthetic ledger. It also
rejects conflicting known receipt IDs. This is actual equality verification of
lab records, not cryptographic digest verification, source authentication, read
permission validation or a real core ledger query. It never displays receipt
body, overwrites current supplier state or mutates unknown on new success.

There is no dispatch/executor API: reconnect cannot auto-dispatch. A nonempty
caller-injected trusted synthetic instruction may register a distinct related
intent, leaving original unknown untouched; this does not authorize or execute
it. Production user instruction provenance, scope/authority, capabilities,
CAS, normalized parameters and stable intent bindings require M03/adapters.
Public fields are developer inspection seams; untrusted callers must not receive
this mutable state directly. All temporary types can be replaced behind an
adapter without altering product libraries or the original oracle.

## Reproduce without installation

Use the already installed toolchain; no download/license/device action:

```sh
export PATH=/tmp/muyon-spike01-toolchain/cargo/bin:$PATH
export CARGO_HOME=/tmp/muyon-spike01-toolchain/cargo
export RUSTUP_HOME=/tmp/muyon-spike01-toolchain/rustup
export CARGO_TARGET_DIR=/tmp/rd-p02-target
cargo test --offline --manifest-path experiments/redesign/device-deferred/rust-recovery/Cargo.toml
python3 experiments/redesign/device-deferred/rust-recovery/mutations.py /workspace/reports/device-deferred-rd-p02-20261014
cargo test --offline --manifest-path experiments/redesign/device-deferred/rust-recovery/Cargo.toml
```

19 unit/integration behavior tests cover paired checkpoint, exact-domain dedup,
payload conflicts including buffered duplicates, gap drain/overflow/zero budget,
epoch/receipt separation, complete identity matching, absent/forged/conflicting
receipts, unknown retention, and synthetic new intent trust/relation/dedup.
Inverse mutations remove domain rejection, erase receipts on reconnect, and erase
original unknown on new intent. Each must fail a named assertion (cargo exit101);
script restores exact source bytes in finally. Raw logs stay outside git.

Original 29/77/19/72 fixture catalogs remain not_run and unchanged. These tests do
not promote original scenarios or establish device readiness, schema freeze,
actual database persistence or business success.
