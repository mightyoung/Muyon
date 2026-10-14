# RD-P01 pure Rust domain experiment

Unpublished isolated crate. Complete raw UTF-16 enters `normalize_raw`: raw ≤2000 units → valid UTF-16/XML → whitespace/BOM trim → NFC → nonempty ≤200 Unicode scalars. No NFKC or internal whitespace collapse. Rust normalization data is Unicode 17.0.0; paired Dart reference data is Unicode 8.0. The finite corpus proves only its observed cases.

`ProvisionalSnapshot` and `ProvisionalEditCandidate` are replaceable local structs, version 0.0.0, not a product DTO or frozen M03 schema. `read_name` checks synthetic scope/ID equality and tombstone. `edit_candidate` checks expected nonzero revision and raw input, returns hypothetical revision+1 even for the same normalized name, and never mutates the snapshot. It performs no database writes, grant checks, model/FFI calls or intent deduplication. Repeated calls compute candidates; they are not repeated effects or receipts.

Both UI experiments may use mock responses behind their own reversible adapters. A future authoritative adapter must revalidate snapshot/scope/revision/authority in the transaction and produce a real receipt before displaying saved. These structs confer no authority, store identity, canonical digest or operation key.

From repository root, using the previously installed offline toolchain:

```sh
export CARGO_HOME=/tmp/muyon-spike01-toolchain/cargo
export RUSTUP_HOME=/tmp/muyon-spike01-toolchain/rustup
export CARGO_TARGET_DIR=/tmp/rd-p01-target
/tmp/muyon-spike01-toolchain/cargo/bin/cargo +1.99.0 test --offline --locked --manifest-path experiments/redesign/device-deferred/rust-domain/Cargo.toml
/tmp/muyon-spike01-toolchain/cargo/bin/cargo +1.99.0 build --offline --locked --example normalize_probe --manifest-path experiments/redesign/device-deferred/rust-domain/Cargo.toml
python3 experiments/redesign/device-deferred/rust-domain/tests/differential.py /workspace/reports/device-deferred-rd-p01-20261014
```

`normalize_probe` is an ordinary synthetic offline testing protocol, never a product wire schema. The Python comparison calls the unchanged fixed Dart product oracle and this actual Rust binary. It checks product source bytes and cached Dart dependency hashes; it does not implement normalization. Thirty M04 paired vectors agree. Two >2000 raw-unit vectors are documented expected differences from the old direct normalizer, which has no entry guard. Original fixtures/observations are unmodified.

Raw logs live outside Git. `evidence/` contains sanitized summaries. Android library load is **NOT_RUN**. Device/release acceptance remains required later; M03 is **blocked_contract**, no whole-case migration or Unicode global equivalence is claimed. No new downloads, licenses or accounts are required by these commands.
