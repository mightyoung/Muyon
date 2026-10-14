# SPIKE-01 throwaway native laboratory

This isolated crate is not a product schema, CoreHost, authorization issuer or Android acceptance. Its single Rust `LabRequest` definition derives both Serde and UniFFI; two entrypoints call the same normalization code. `LabReply` includes laboratory canonical bytes/digest instrumentation, not a frozen business response. Missing/null note collapse to None only by this explicit lab policy. Canonical revision is decimal text; the request/typed reply still tests real u64 handling. Unknown JSON fields/enums and invalid integer shapes are rejected.

User approved official tool installation. Tools, binaries, generated bindings, caches and raw logs are external under `/tmp/muyon-spike01-toolchain/` and `/workspace/reports/spike01-runtime-20261014/`. Google SDK/NDK terms were explicitly accepted by the user at 2026-10-14 06:27:47 UTC; SDK/NDK download and installation have not occurred. No Android library has been linked or loaded; aarch64 `cargo check` only proves target type checking. Rust/Cargo1.99.0, UniFFI0.32.2, JDK17.0.20.1, Gradle8.13, Kotlin2.2.20, JNA5.19.1 are installation observations, not M03 version selections.

From repository root, with tool-specific CARGO_HOME/RUSTUP_HOME/CARGO_TARGET_DIR/PATH:

```sh
cargo test --manifest-path experiments/redesign/spike01-native-lab/Cargo.toml -- --test-threads=1
cargo build --manifest-path experiments/redesign/spike01-native-lab/Cargo.toml --features bindings --bin uniffi-bindgen
cargo build --manifest-path experiments/redesign/spike01-native-lab/Cargo.toml --release --lib
```

From this crate directory (UniFFI0.32 resolves cargo metadata from cwd):

```sh
uniffi-bindgen generate /tmp/muyon-spike01-toolchain/target/release/libspike01_bridge_lab.so --language python --language kotlin --no-format --out-dir /tmp/muyon-spike01-toolchain/generated
```

Copy that exact `.so` adjacent to the generated Python file, then from this crate:

```sh
PYTHONPATH=/tmp/muyon-spike01-toolchain/generated python3 -B -m unittest discover -s tests -p 'test_*.py' -v
```

Current observations: true behavioral RED11 tests before core implementation, GREEN11; lifetime RED5 while core11 remained GREEN; complete Rust suite16 GREEN. Actual generated Python binding loaded the Linux `.so`; 10 FFI tests GREEN cover canonical semantics/digest, u64 boundary values, domain/shape errors, controlled panic interception, actual foreign callback errors, unsubscribe/release, close waiting, reentrant close rejection and native Drop count. The Rust object count tests intentionally run serially; spawned-thread tests still exercise concurrency.

The first generated Kotlin compilation failed because exported `close()` collided with generated `AutoCloseable.close()`. Only lab source was renamed to `close_session`; regenerated Kotlin now compiles. Original failure log retained. Domain close and generated native-handle release remain distinct. JVM runtime tests and Dart Unicode differential are still pending in this snapshot.

Normalization uses Rust unicode-normalization0.1.25/Unicode17.0.0 versus fixed Dart unorm0.3.1/Unicode8.0. Limited vector comparisons cannot establish whole-Unicode equivalence. No binding-generation or Linux result establishes Android packaging, library load, 4KB/16KB/ABI compatibility, Android lifecycle, package-size/SLA selection or M03 freeze. No model, real user data/database, credential, deployment or product/main/develop write occurs.

Handoff update: immutable original snapshot `fadaeb797733ade84be2ebcfb8910c931a4ccd39` has independently confirmed H1: a foreign observer destructor reentering `close_session` or `unsubscribe` can self-deadlock after callback replacement. Both actual independent FFI probes timed out after five seconds (exit124). Existing 16 Rust/10 Python historical greens do not cover this sequence. No fix is included in this handoff; lifecycle correctness remains conditional/incomplete. Sanitized status and tool checksums are in `evidence/`; original logs remain outside Git. M03 remains blocked.
