# Independent initial execution-graph review

Immutable reviewed source: `21ba62a4472b161b542bc8a34b6f4bd362dfb4b2`.

## Decision

The exact command below is approved for the initial expected RED compile check at this SHA:

```sh
cargo test --locked --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml --test ordinary_chat_controller
```

At the reviewed SHA the test references missing ordinary-chat APIs/module, so compilation is expected to fail before any test body executes. Record the actual compiler result as RED, not runtime acceptance. This review does not approve execution against later implementation commits without reviewing the newly reachable ordinary-chat/controller/provider code.

No I04 execution route was found in this command's repository-controlled compilation graph. No tests, builds, generation or network were executed by the reviewer.

## Reviewed graph and boundaries

- `ordinary_chat_controller.rs` is the sole selected integration target. It contains three tests, an in-memory Owner/fake exchange, a fresh uniquely named temporary root per controller, closed event reads and teardown of only that newly created root. No socket client, subprocess, script invocation, Agent::open, old database lookup or HTTP request exists in this test. The HTTPS `.invalid` string is profile metadata only.
- Host crate has two path dependencies: core-agent and plugin-contract; plugin-contract depends on core-agent. These three manifests have no repository build script, custom runner, dependency execution hook or HTTP recovery dependency. No repository `.cargo/config` was found in the fixed tree. Core/plugin binaries may be compiled by Cargo but are not run by this target selection. Other integration tests, unit test modules and doc tests are not selected.
- Existing controller construction opens/inventories the supplied fresh root via ServiceRoot and metadata restore. At the reviewed test boundary it contains no historical runs and is never reopened. This is not the denied old `task.db → HTTP → original state reopen` sequence. Later implementation must preserve that fresh-root-only behavior and must not fall through ordinary chat into `run_builtin_admitted`/supplier execution.
- `libsqlite3-sys` is Android-target-only. The selected host target does not execute Android SQLite build paths. No deferred-recovery/core-port experiment dependency is reachable from the host manifest.

## Build-only binding stage

The reviewed bridge manifest depends on plugin-contract, the same host crate, and pinned UniFFI 0.32.2. Feature `bindings` enables UniFFI CLI and `src/bin/uniffi-bindgen.rs`; that binary only invokes `uniffi::uniffi_bindgen_main()`. The sole repository build script validates `MUYON_BRIDGE_BUILD_ID` as 40 lowercase hex and emits Cargo directives. It does not execute application code, scripts, HTTP, database restore or tests.

Repository graph permits build-only:

```sh
MUYON_BRIDGE_BUILD_ID=21ba62a4472b161b542bc8a34b6f4bd362dfb4b2 cargo build --locked --manifest-path experiments/redesign/android-rust-bridge-lab/core/Cargo.toml --features bindings
```

For an implementation build, substitute the actually reviewed immutable implementation SHA. This is not permission to launch the produced application, bridge service, any test or recovery binary. Registry build dependencies/procedural macros are ordinary pinned compilation inputs; their source contents were not separately security audited here, and no claim of exhaustive registry execution audit is made.

Local UniFFI generation is suitable in principle, but the exact generate invocation, library/config inputs and output directory have not been provided. Therefore generation remains NOT_RUN and requires that concrete invocation to be checked. Do not substitute a script that also launches tests/APK/recovery. The generation binary must be the locally built pinned CLI and output only generated bindings for this slice.

## Before a GREEN runtime run

The test currently creates one service per test but the existing controller enforces process-global `PROCESS_OCCUPIED`. Cargo runs test cases concurrently by default; the three cases can reject each other's construction as Busy. Serialize them in the test source or explicitly add `-- --test-threads=1` to the newly reviewed runtime command. This is a test reliability issue, not an I04 concern.

These are controller tests, not evidence of Compose Send rendering. The first test's name does not prove the Kotlin/UI chain; Android instrumentation and its complete build/CI graph remain a separate NOT_RUN gate. These tests also install a test-local owner, so production durable-owner enforcement requires later source review and focused coverage.

I04 remains prohibited, including execution through any suite, rewritten/split path, alternate environment or recovery helper. No old 403 download, real provider/key operation, merge or HOLD removal is authorized. Reviewer writer stopped after this file.
