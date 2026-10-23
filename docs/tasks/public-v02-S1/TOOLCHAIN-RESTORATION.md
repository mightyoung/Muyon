# Authorized toolchain restoration — 2026-10-23 UTC

This follow-up supersedes the missing-toolchain blocker in REPORT.md. C1 is still pending; S1/S2 product implementation and behavioral RED/GREEN remain NOT_RUN.

## Authorization, version and source

Parent relayed the user's explicit permission to install official Rust and cache Cargo.lock dependencies in the selected development environment. No sudo, system security changes, credentials, paid/model/Connector calls or arbitrary program installation. Parent's authorization covers toolchain installation, not the missing C1/C2 product interfaces.

Product-source baseline remains `fd26dcdabcdac996bc2881e8141cac2b519966fc`; tested branch head before this report is `b78c107be0cc0073071d278ca7b3d55404f542eb` (documentation-only differences from baseline). No root or `crates/` rust-toolchain file exists. The separate `experiments/redesign/spike01-native-lab/rust-toolchain.toml` pins 1.99.0 only for that spike. Parent explicitly allowed previously verified Rust 1.93.1; prior verification evidence is recorded in the baseline's `docs/tasks/bot-core-continuation-20261023/REPORT.md`.

- Toolchain manifest: https://static.rust-lang.org/dist/channel-rust-1.93.1.toml ; companion `.sha256` checked, actual SHA256 `4812a3c610bacc74eed12c89c312e540722dccccd867bd55096402da13b3a516`.
- Manifest release date `2026-02-12`; every component URL starts `https://static.rust-lang.org/dist/2026-02-12/`.
- Archives downloaded by HTTPS curl, SHA256 matched before extracting or running their official install.sh with `--prefix=/workspace/skills-rust-tools/prefix --disable-ldconfig`.
- No rustup bootstrap, shell profile or system directories modified. Official archive install scripts are toolchain installation, not Skill scripts.
- Actual `rustc -Vv`: 1.93.1, commit `01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf`, host x86_64-unknown-linux-gnu, LLVM 21.1.8. `cargo -Vv`: 1.93.1, commit `083ac5135f967fd9dc906ab057a2315861c7a80d`. Both exit 0.

| Component | Official archive | SHA256 matched to manifest |
| --- | --- | --- |
| rustc | `rustc-1.93.1-x86_64-unknown-linux-gnu.tar.xz` | `b9db2636f5a101c4cdaf46a26f8a0c8e4b5767ecdb02ae9c7ccc3ead577732bc` |
| cargo | `cargo-1.93.1-x86_64-unknown-linux-gnu.tar.xz` | `dbf12e8fd2a245a6bdd9f6c8df267cb2c25b0c56866ee91d8321337df0a00ddb` |
| rust-std | `rust-std-1.93.1-x86_64-unknown-linux-gnu.tar.xz` | `82c4e41268f1741e4eb68796aeb6ca5042406ae858dd56144155c4ef8d87d8b6` |
| rustfmt-preview | `rustfmt-1.93.1-x86_64-unknown-linux-gnu.tar.xz` | `2ad6fa7ad2b5e42e1ca39299039ea0110b8cb2a45847553e4cbab82181a351e0` |
| clippy-preview | `clippy-1.93.1-x86_64-unknown-linux-gnu.tar.xz` | `60c0ce83ecc1700de724404a928c30d096c178a610c6707d4f06cee25284cc02` |

## Cache and native linker setup

`cargo fetch --manifest-path crates/Cargo.toml --locked` exited 0. All 103 external packages in this lock are from `registry+https://github.com/rust-lang/crates.io-index`; downloaded cache archives were separately hashed and matched every lockfile checksum. Official sparse registry configuration downloads from `https://static.crates.io/crates`. No source replacement or alternate mirror configured. Lockfile SHA256 before/after remains `d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`.

Existing native SQLite runtime lacked the unversioned linker filename. Workspace-local `native-lib/libsqlite3.so` points to existing `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6` (SHA256 `14c4418a06c5c2e30f5fb57bc8add93762236ae17898c6708984cf15e680ca71`); no SQLite download, package installation or system change. This supports the existing host SQLite seam, not the blocked Reader bridge.

Use in this environment only:

```sh
source /workspace/skills-rust-tools/env.sh
# sets PATH prefix/bin first, CARGO_HOME=cargo-home,
# CARGO_TARGET_DIR=target, LIBRARY_PATH=native-lib under the same tools root
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test agent_workflow
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
```

All cache/build artifacts are outside the checkout. Existing locks, manifests, product code, credentials and shared registration remain unchanged.

## Fresh verification

The first restored command is a baseline regression rerun, not S1 behavior GREEN: `agent_workflow` exited 0, **17 passed / 0 failed / 0 ignored**. It ran offline/locked at the baseline product source above. These are existing synthetic host/SQLite tests; fake provider responses and fixture authority do not represent actual transport or model execution. Prior exit-127 attempts are preserved and remain historical environment failures, not RED.

Workspace regression exited 0: **603 passed / 0 failed / 0 ignored**, 33 test-binary result groups including zero-test binaries. UTC 05:05:03–05:06:33. Expected boundary-fault stderr contains `ZipWriter::drop: failed to finalize archive: Io(Kind(FileTooLarge))`; the process still exited 0. S1 `public_skills` tests do not exist and were not run. No S1 fixture or stub has been authored before C1. Android, devices, real external effects, new runtime wiring, parser, Clippy and bindings generation NOT_RUN in this follow-up.

## Raw evidence outside repository

Raw commands, UTC start/end, explicit environment, stdout/stderr and SHA256 are in `/tmp/muyon-skills-v02-evidence/` as `cargo-fetch.*`, `installed-rustc.*`, `installed-cargo.*`, `restored-agent-workflow.*`, `restored-workspace.*`. The runner `run-toolchain.py` captures output without rewriting it. Package archive hashes are in `locked-package-checksums.json` (SHA256 `51f9840fcadad9ebb9a0cfa9ada923783eef45fd7ec972e653d630b621326840`). Installation archive manifest and log stay in `/workspace/skills-rust-tools/downloads/components.json` and `installation.log`.

Independent review of this follow-up: pending; the earlier review covered preparation only. No merge/deployment or rejected/uncertain action occurred.

Captured output hashes (raw logs are not committed):

| Run | stdout SHA256 | stderr SHA256 |
| --- | --- | --- |
| cargo-fetch | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | `2415b258edb29b3d2632e557450cc4c798e8c3936d940ff70c9a687e46037875` |
| installed-rustc | `b1008d5f7681db91d446d2bb0a07af00372bb6cb4d4599e95212e3a8edce4e11` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| installed-cargo | `a15410ae4b0c976fc6db49c65833186ecac06d9c2b90245c46940de00145f913` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| restored-agent-workflow | `d572b58b9882dba21c9061af281eecdba5736520cbf1772b2211ef9d12bfdbc8` | `2953403f915c234d4b78fec5e6827ad66bb6fc0206ccb4d6ebd85a719ba6c386` |
| restored-workspace | `c4074796799c6961b1d9b35f2ae80174f8abeeba6b8e59a412e995190952b4b4` | `7aa793045a92274bae3af72155301641d074c0fc3281629d16eb65d3493d9997` |
