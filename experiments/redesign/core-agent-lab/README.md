# Rust core Agent — deterministic offline laboratory

This is an executable synthetic Rust Agent kernel, not a real-model integration or frozen M03 product API. A bounded session/context feeds a typed scripted provider; complete tool requests pass trusted host policy, then one registered synthetic tool writes its effect and original receipt atomically. The actual tool result enters the next model request. No supplier page, HTTP client, credentials, real business database or native runtime is involved.

The four settled modes are exercised with trusted fixture facts: Auto-low runs, Auto-high/Ask need an exact pending confirmation, FullAllow adds no risk/new-destination confirmation, and hard limits deny every mode. Model text cannot provide authorization. Same-reference/same-argument repeats map to the original host Binding and verified receipt without another effect; changed arguments conflict. Unknown results remain lookup-only. Receipt restoration cannot reopen a completed/cancelled/failed/denied/budget terminal. Context and byte/step/call limits are persisted and checked before effect admission.

See [boundary](CONTRACT.md), [exact CLI and storage format](core/CLI.md), [independent process checks](checks/README.md) and [task plan](../../../docs/tasks/REDESIGN-CORE-AGENT-20261015.md).

## Run with an existing Rust toolchain

From repository root, without installing dependencies:

```sh
cargo build --offline --locked --release --manifest-path experiments/redesign/core-agent-lab/core/Cargo.toml
fixture_root="$(mktemp -d /tmp/muyon-core-agent.XXXXXX)"
binary=experiments/redesign/core-agent-lab/core/target/release/muyon-core-agent-lab
"$binary" start --dir "$fixture_root/task" --script experiments/redesign/core-agent-lab/fixtures/happy.tsv --input 'synthetic user input' --mode auto
"$binary" run --dir "$fixture_root/task"
"$binary" inspect --dir "$fixture_root/task"
```

Use a new task subdirectory inside the private temporary directory; never point at a product/user database. Reuse the same task path to inspect or lookup the original operation. Do not recreate an uncertain task to retry it. `lookup` reconciles facts; it does not grant a new operation. Preserve fixture directories when collecting evidence.

Current cloud workspace has no Rust compiler, and artifact download returned403; the binary has **not run locally** here. Actual Rust compilation/execution is recorded by the dedicated CI using its preinstalled Rust1.99.0, with no tool installation or external crates. Existing Flutter regression CI is a separate gate and does not execute these new checks.

## Verification boundary

The fixed implementation at verification SHA `0b7c0c4002436397ff600420064bf14797b5b2b9` passed [Core Agent CI38666230275](https://github.com/mightyoung/Muyon/actions/runs/38666230275):20 Rust tests,25 independent process methods,6 harness selfchecks and7 compiling semantic inverse mutations detected. Those are different layers, not a sum of product acceptance cases. Final candidate and postmerge evidence must bind their own full SHA.

Original compiled semantic RED and the actual R1 terminal-recovery failure are retained in separate review branches/CI; fixes do not rewrite that history. Storage is a one-owner private Linux fixture with atomic file replacement/fsync and flock, not production SQLite, power-loss or remote exactly-once assurance. Script inputs are synthetic event data, not expected-result dispatch tables. Provider fixtures do not prove real model accuracy, protocol compatibility, billing or live cancellation.

Before real model verification: separately authorize an existing endpoint/profile/credential reference and cost budget; implement and review the model transport adapter, current source/value/authority gates, final payload/outbound ledger-before-send, streaming/timeout/usage semantics and secret handling. Formal M03, production issuance/retention/migration, Electron/Android and real-model execution remain open. Missing devices do not block further isolated core development.
