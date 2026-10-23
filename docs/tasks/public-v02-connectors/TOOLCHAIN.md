# Connectors official toolchain restoration

Later update: parent released fixed Contracts candidate 4d49a580cb518d9b0b80c9df3df1ff564194a639. X1/X2 local implementation and actual verification now appear in [X1 REPORT](../public-v02-X1/REPORT.md) and [X2 REPORT](../public-v02-X2/REPORT.md). Historical dependency-hold text below describes its original stage, not current source availability. Contracts registration/production host gates remain pending.

2026-10-23 UTC. This follow-up supersedes the original toolchain blocker in
[PREFLIGHT.md](PREFLIGHT.md). It does not implement or accept X1/X2.

The parent forwarded the user's explicit authorization to install official Rust
and download Cargo.lock dependencies in the selected development environment.
Only this tool restoration changed scope. C1/C2 source and fixture release is
still pending; the Contracts blocking report is not an interface dependency.

## Version and provenance

Source tested: `782071a7c92a83a27f7a461bf0fb434b9619b75e`, containing only the
preflight document over develop `fd26dcdabcdac996bc2881e8141cac2b519966fc`.
The product CI `.github/workflows/muyon-product.yml:43` fixes Rust 1.93.1.
Prior fixed-source evidence in
`docs/tasks/office-rust-boundary-fix-20261023/REPORT.md` and the Bot continuation
report records successful use of that version. The 1.99.0 rust-toolchain.toml
belongs only to experiments/redesign/spike01-native-lab, not crates/.

Installed locally under `/workspace/connectors-v02-tools/rust-1.93.1`:
rustc 1.93.1 (`01f6ddf75`), cargo 1.93.1 (`083ac5135`), host standard library,
and clippy 0.1.93 (`01f6ddf758`); host `x86_64-unknown-linux-gnu`.
No global profile, sudo, credentials or system security configuration changed.

Official manifest [channel-rust-1.93.1.toml](https://static.rust-lang.org/dist/channel-rust-1.93.1.toml)
matched its official .sha256:
`4812a3c610bacc74eed12c89c312e540722dccccd867bd55096402da13b3a516`.
Every archive matched the manifest's xz_hash before extraction/execution.
Component URLs share the official prefix
`https://static.rust-lang.org/dist/2026-02-12/`:

| File | SHA256 |
| --- | --- |
| rustc-1.93.1-x86_64-unknown-linux-gnu.tar.xz | b9db2636f5a101c4cdaf46a26f8a0c8e4b5767ecdb02ae9c7ccc3ead577732bc |
| cargo-1.93.1-x86_64-unknown-linux-gnu.tar.xz | dbf12e8fd2a245a6bdd9f6c8df267cb2c25b0c56866ee91d8321337df0a00ddb |
| rust-std-1.93.1-x86_64-unknown-linux-gnu.tar.xz | 82c4e41268f1741e4eb68796aeb6ca5042406ae858dd56144155c4ef8d87d8b6 |
| clippy-1.93.1-x86_64-unknown-linux-gnu.tar.xz | 60c0ce83ecc1700de724404a928c30d096c178a610c6707d4f06cee25284cc02 |

Verified official component install.sh scripts ran with
`--prefix=/workspace/connectors-v02-tools/rust-1.93.1 --disable-ldconfig`, each
exit 0. No rustup executable or Android target installation was needed.

## Locked cache and host environment

`cargo fetch --locked --manifest-path crates/Cargo.toml`: exit 0. All 103 external
packages use the lockfile source `registry+https://github.com/rust-lang/crates.io-index`.
Cargo used the standard crates.io sparse index/download configuration without
replacement registries; cached public config specifies `https://static.crates.io/crates`
and `https://crates.io`. Every downloaded .crate archive was independently hashed
and matched its Cargo.lock checksum (103/103). No git dependency or unknown binary
source was downloaded. All local path dependencies remain existing repository code.

Cargo.lock before and after setup:
`d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`.
No dependency or lockfile upgrade occurred.

Environment is explicit per command, not a shell profile change:

```sh
PATH=/workspace/connectors-v02-tools/rust-1.93.1/bin:$PATH
CARGO_HOME=/workspace/connectors-v02-tools/cargo
CARGO_TARGET_DIR=/workspace/connectors-v02-tools/target
RUSTFLAGS=-Lnative=/workspace/connectors-v02-tools/native-links
```

MUYON_EVAL_REAL is removed in the local command recorder. Initial contract build
reached linking but exited 101 because `-lsqlite3` could not find an unversioned
link name. The existing host runtime library
`/usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6` was present (SHA256
`14c4418a06c5c2e30f5fb57bc8add93762236ae17898c6708984cf15e680ca71`).
A task-local `native-links/libsqlite3.so` points to that file, following the
documented prior task setup. No SQLite download, installation or replacement;
the subsequent identical contract command passes with only the native search
path added. This is environment restoration, not a product defect fix or TDD.

## Actual verification and limits

The exact prior command was rerun with the toolchain restored:

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connectors
```

Exit **101**, `no test target named public_connectors`. The test/module/fixture
are intentionally absent pending C1 release. This is neither behavioral RED nor
GREEN. No stub or duplicate shared type was introduced to manufacture a result.

Existing baseline command:

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test contract
```

With the host link setup above: exit **0**, **10 passed / 0 failed**. This is
existing contract baseline validation, not X1/X2 acceptance.

Additional whole-core baseline command:

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked
```

Exit **0**, **562 passed / 0 failed / 0 ignored**, across 30 result groups
(including empty binary/doc-test groups). This is host muyon-core baseline only,
not the full Cargo workspace or Android acceptance. No new tests were written.
Android/real models/Connector consent/revoke, remote effects, X1/X2 RED/GREEN
and X3/X4 gate approval remain NOT_RUN.

Raw installation and command logs stay outside git under
`/workspace/connectors-v02-tools/evidence/`; the local `bootstrap.py` and `run.py`
preserve official URL/hash checks and command argv, UTC interval, explicit
environment, exit status and stdout/stderr SHA256. No raw logs are committed.

## Evidence hashes and review

All paths below are relative to `/workspace/connectors-v02-tools/evidence/`.

Structured inventory SHA256:
`components.json` = `27c21794cade092ad7d4320101d7d8db9fdb954a501fa3145426870054ed2b8f`;
`cache-checksums.json` = `600ad4b023c83e372638bf5d48b95c0fa10c6a0d12244866a1bff0f700f59ba1`;
`native-link.json` = `958d5825141ddd5edf3e6d899a5373e5343dc95f65382eb17e70d48ec0a84565`.
The outside-git local setup recorder `../bootstrap.py` has SHA256
`36c74f7660303b99a013fbb41c045449b467b7ee3d49ff5a41a65bffd224807a`;
command recorder `../run.py` has SHA256
`de911d01cc1e8a5e3ff72d60aaa89e318f199b3d656182a15bde77a425f30570`.

| Command record label | Exit | stdout SHA256 | stderr SHA256 |
| --- | --- | --- | --- |
| locked-fetch | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | 99cfb6efaf4b8709e80a18b3621ff44d4fc1bb520d379e5becd335841d5ff14d |
| x1-after-toolchain | 101 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | ae542e62ebcc8fa3580d89cd0ca913e87a36a223330699c66c6addc131788f12 |
| baseline-contract | 101 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | 33fcf6b8a86d6ed3b22234fddd1b1f4274ffb7ac30898601342d19e2764bb953 |
| baseline-contract-linked | 0 | a02a16144132152f4885fb59c7852babce750decaf272f15ddbe61c4bc4f451a | 0e19dc7b2cbb6869eb39d2b245f785ac84da6e612ba2a10e0038aa72d7f29d68 |
| baseline-core | 0 | b69963560432a7926885bee0e04a5a33c6778875efb0527d705d1aa977f933f0 | 832a735119bea7a02bd43374d71f9544077915839667dbe6b13d3b514041d818 |

Independent read-only reviewer `/root/review_connector_preflight` checked the
official component/manifest hashes, all 103 package checksums, command log hashes,
30 result groups/562 tests, actual Rust/Cargo versions, SQLite target, unchanged
lockfile and docs-only scope. No blocking or important findings; a minor CI line
reference was corrected from 44 to 43. Review did not rerun the test suite and
does not accept X1/X2. Remaining action: wait for parent-released C1/C2 interface
and fixture SHAs, refresh develop before coding, then perform behavioral TDD.
