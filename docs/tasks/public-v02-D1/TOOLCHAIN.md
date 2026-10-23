# 官方 Rust 工具链与既有基线复验补充

2026-10-23。状态：工具就绪，既有 Rust 基线两组共61项通过；D1/D2 未实施，C1/C2 接口/fixture 仍未交付；Kotlin/Android/D3 仍未验证或受阻。这不是新公共服务的行为 RED/GREEN。

本次用户明确允许“从官方 Rust 来源安装工具链，并按仓库 Cargo.lock 下载依赖缓存”，由父任务转交。仅在当前已选云环境 `/workspace` 配置，无 sudo、系统安全设置修改、账号凭据、付费、真实模型或新产品依赖。先前禁止安装的执行记录保留为历史，以本次新授权为范围内补充。

## 版本、来源与校验

工作区 `7ae1a273af3911b7069309083fd8820ffbcc8edc`，产品源码与原基线 `fd26dcdabcdac996bc2881e8141cac2b519966fc` 相同；只含前片 Markdown。远端 develop 本次只读复核仍为该基线。

根与 crates workspace 没有适用的 rust-toolchain 文件。`experiments/redesign/spike01-native-lab/rust-toolchain.toml` 的1.99.0仅作用于该 spike，不用来替换公共 crates 工具链。采用 Rust 1.93.1 的仓库依据为 `docs/tasks/evidence-local-chain-20261022/HANDOFF.md` 及 `docs/tasks/overall-combination-20261022/evidence/rust-toolchain-setup.log` 中既有验证记录。

安装目录 `/workspace/documents-v02-tools/toolchain`，Cargo home `/workspace/documents-v02-tools/cargo`，target `/workspace/documents-v02-tools/target`；无全局 profile 修改。`env.sh` 仅设置当前任务的 PATH/CARGO_HOME/CARGO_TARGET_DIR/LIBRARY_PATH。安装前对组件包核验官方 manifest 摘要，之后才执行官方包内 install.sh，使用 `--prefix=... --disable-ldconfig`。

官方 manifest URL：`https://static.rust-lang.org/dist/channel-rust-1.93.1.toml`；对照同 URL 加 `.sha256`，SHA256 为 `4812a3c610bacc74eed12c89c312e540722dccccd867bd55096402da13b3a516`。

三个组件均来自 `https://static.rust-lang.org/dist/2026-02-12/`，目标 `x86_64-unknown-linux-gnu`；文件完整命名为 `<组件>-1.93.1-x86_64-unknown-linux-gnu.tar.xz`。

| 组件 | 官方 manifest 对照并实际匹配的 SHA256 |
| --- | --- |
| rustc | `b9db2636f5a101c4cdaf46a26f8a0c8e4b5767ecdb02ae9c7ccc3ead577732bc` |
| cargo | `dbf12e8fd2a245a6bdd9f6c8df267cb2c25b0c56866ee91d8321337df0a00ddb` |
| rust-std | `82c4e41268f1741e4eb68796aeb6ca5042406ae858dd56144155c4ef8d87d8b6` |

实际 `rustc --version --verbose`：rustc1.93.1，commit `01f6ddf7588f42ae2d7eb0a2f21d44e8e96674cf`；cargo1.93.1，commit `083ac5135f967fd9dc906ab057a2315861c7a80d`。安装执行退出0。

`cargo fetch --manifest-path crates/Cargo.toml --locked` 退出0。Cargo.lock 所有103个 registry包来源均为 `registry+https://github.com/rust-lang/crates.io-index`；官方 sparse registry 配置的下载地址是 `https://static.crates.io/crates`。没有 git 或其他 registry来源。逐个缓存 `.crate` SHA256 均与 Cargo.lock 的 checksum 匹配；完整清单在仓库外日志。未运行未知来源安装程序或添加依赖。

Cargo.lock 安装前后 SHA256 均为 `d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`，`git diff --exit-code -- crates/Cargo.lock` 退出0。

当前系统有 SQLite runtime但无 libsqlite3.so 开发链接和 pkg-config元数据。仅在任务目录创建 `link/libsqlite3.so -> /usr/lib/x86_64-linux-gnu/libsqlite3.so.0`，通过 LIBRARY_PATH 提供链接；没有系统安装/修改或下载 SQLite。

## 实际命令和结果

从独立工作区执行，先设置当前进程变量：

```sh
export PATH=/workspace/documents-v02-tools/toolchain/bin:$PATH
export CARGO_HOME=/workspace/documents-v02-tools/cargo
export CARGO_TARGET_DIR=/workspace/documents-v02-tools/target
export LIBRARY_PATH=/workspace/documents-v02-tools/link
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test evidence_local --test document_storage --test documents
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --lib evidence::store::tests
```

第一条测试命令退出0：document_storage 15/15，documents 18/18，evidence_local16/16，共49项。第二条退出0：StoreEvidence真实 owner 测试12/12，过滤99项。两组覆盖范围不同，总共61项；均是原有测试，无新增产品测试或公共服务实现。

另一次历史 harness 尝试：同环境变量，`python3 crates/muyon-core/src/evidence/run-store-tests.py --repo /workspace/muyon-documents-v02`，退出1，断言路径 `src/group_runtime_store/mod.rs` 不存在。该脚本未处理当前 lib.rs 中 `#[path = "group_runtime/store.rs"]`；尚未运行编译/测试，不算行为 RED。当前 lib.rs 已有正式 evidence 导出，所以采用上面的原生 Cargo目标运行现有测试，无需修改或生成模块接线；未修改脚本。

## 仓库外原始证据

下表均在 `/workspace/documents-v02-evidence/`，原始日志不提交。

| 文件 | SHA256 |
| --- | --- |
| rust-install.log | `49fc96f9c2b6333510994b2b745dd958961af1922fd859e4f61f2f5db13fedb6` |
| cargo-fetch.log | `e3d968fd5f556348bf120494a2fdb97fb94e84b4936b48d0d2574d74e2ad3911` |
| cargo-cache-check.log | `751a1965773b9fee8078c8593f732cbb3e4bdc28785aeafa68367b7fa7583ee0` |
| baseline-rust-ready.log | `e80b783d604d9b12dc5736c364ef207ce60895b175b3dc23bcda04f9348407a3` |
| store-baseline-ready.log | `d233c606f8de62e33fb40ed0451e1a74d70e807653aa9e458187b5fabb7c9327` |
| store-native-ready.log | `181e8609559c688f19c76a17a9153e884992cd3ef76a2f22f6a5ffc2af938cd9` |

## 验证与独立审查

本次文档静态检查退出0，核对2份Markdown、6个原始日志摘要、49+12测试计数及锁文件未变；原始日志 `toolchain-document-check.log` SHA256为 `514d61585f543bdda899df517dbcec6a63534d17675e7dd4de6d32aea14142b6`。

非作者 `documents_preparation_review` 独立核对官方manifest/三个组件包、103个缓存包checksum、六份日志SHA256及产品源码相对基线无变化，并独立重跑上面两条离线测试命令，49/49与12/12均通过。无阻断；不构成新公共服务验收。

Final: minor (deferred): REPORT顶部已解释新授权/验证覆盖旧状态，但后文历史段仍使用“最新/当前”字样；跳读时需结合顶部说明。保留原始报告，当前工具就绪状态以本补充为准。原准备片路径缩写Minor继续保留。

Ruling：旧Python harness在编译前路径解析断言失败，未改其模块生成逻辑；改用当前正式导出模块的原生Cargo目标验证相同既有owner测试 — 避免触碰Contracts独占登记文件或生成替代接线 — 代价是旧harness的兼容性仍未修复，失败日志明确保留。
