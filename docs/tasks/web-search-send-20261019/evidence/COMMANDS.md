# Exact-source local validation

Executable source: `590fbc026b2fc5d200236d1877482b03752d0d8f`.

```sh
CARGO_HOME=/tmp/muyon-cargo RUSTUP_HOME=/tmp/muyon-rustup MUYON_PLUGIN_CONTRACT_BIN=/tmp/muyon-plugin-contract-built/debug/muyon-plugin-contract-lab /tmp/muyon-cargo/bin/cargo test --locked --offline --manifest-path experiments/redesign/web-search-lab/core/Cargo.toml --test contract --test agent_search --test service_send -- --test-threads=1
MUYON_UI_KOTLINC=/tmp/muyon-kotlin/kotlinc/bin/kotlinc bash experiments/redesign/android-compose-lab/run-search-checks.sh
CARGO_HOME=/tmp/muyon-cargo RUSTUP_HOME=/tmp/muyon-rustup CARGO_TARGET_DIR=/tmp/muyon-search-bridge-target MUYON_BRIDGE_BUILD_ID=590fbc026b2fc5d200236d1877482b03752d0d8f /tmp/muyon-cargo/bin/cargo build --locked --offline --manifest-path experiments/redesign/android-rust-bridge-lab/core/Cargo.toml --features bindings
# From experiments/redesign/android-rust-bridge-lab/core:
PATH=/tmp/muyon-cargo/bin:$PATH CARGO_HOME=/tmp/muyon-cargo RUSTUP_HOME=/tmp/muyon-rustup /tmp/muyon-search-bridge-target/debug/uniffi-bindgen generate --library /tmp/muyon-search-bridge-target/debug/libmuyon_android_contract_bridge.so --language kotlin --config uniffi.android.toml --out-dir /tmp/muyon-search-generated-exact590 --no-format
# From repository root:
cmp /tmp/muyon-search-generated-exact590/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt
```

32 Rust checks (contract5 + agent_search20 + service_send7) and13 pure Kotlin checks passed. Exact-source bridge build, genuine generator and cmp passed. The bridge log preserves an initial generator failure because cargo was absent from PATH; the corrected invocation succeeded. Historical logs retain earlier iterations and do not replace these exact-source results. Local Android instrumentation is NOT_RUN: no local SDK/device. Dedicated CI must independently establish API26 packaging/lint/device completion. No inherited aggregate/I04, HTTP, real owner/TLS, real SearchHost, real model or paid call was run.
