# 独立格式修复复验

精确新源：`d2ac6a87a8bf13d8a22ebd41676683be8d849a22`，已与远端 `task/document-core-contracts-20261022` 核对。精确旧源：`ab9c381cc935be0cd52db5a8a455ce985bdba1db`；此前验证提交 `1c40b8fe6637c512fb491f66b79d0b6e25eeb3a1` 的原始输出、格式失败与 workspace 阻断均保留。

本次在新隔离 detached worktree `/workspace/Muyon-document-formatted` 只读验证新源。没有AGENTS.md；已读作者 FORMAT-FOLLOWUP。报告追加到既有 `task/document-core-verification-20261022`，没有修改作者源码、原工作区、group分支或 main/develop，也没有合并、配置凭据、扩权限、下载依赖或软件。离线测试仅使用临时夹具，未接触真实业务数据、历史unknown请求或费用预占。

## 先核变化范围

旧源到新源只有五个 Rust 文件变化：`documents/{anchor,capability,identity,mod}.rs` 和 `tests/documents.rs`；另三项是作者的格式说明/应用证据。

独立验证没有只依赖作者“仅格式”的声明：从Git读取旧五文件到 `/tmp/muyon-document-format-expected`，使用现有同一 rustfmt 实际格式化**临时副本**，再与新固定源逐字节比较。五个结果全部一致；原/新源身份、具体命令、时间、每文件期待值/实际SHA256见 [format-only-proof.json](independent-verification/format-followup/format-only-proof.json)。不在作者或验证源码工作树运行改写式格式化。

## 新固定源上的真实运行

使用现有 Rust/Cargo/rustfmt 和原依赖缓存，`CARGO_HOME=/tmp/muyon-cargo`、`CARGO_TARGET_DIR=/tmp/muyon-document-cargo-target`、`RUSTFLAGS=-L native=/tmp/muyon-native-libs`、PATH前缀 `/tmp/muyon-rust/bin`。所有测试为 `--locked --offline`，没有下载动作。

```sh
/tmp/muyon-rust/bin/rustfmt --edition 2021 --check crates/muyon-core/src/documents/anchor.rs crates/muyon-core/src/documents/capability.rs crates/muyon-core/src/documents/identity.rs crates/muyon-core/src/documents/mod.rs crates/muyon-core/tests/documents.rs
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test documents
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core
```

**新源结果：scoped fmt exit0（stdout/stderr均为空），targeted exit0 / 18 passed / 0 failed / 0 ignored，完整muyon-core package exit0 / 165 passed / 0 failed / 0 ignored（包含前18项，不能相加为183项）。五文件格式门槛现已由实际复验关闭。** 既有依赖的read/write C声明警告仍在原始stderr中保留，没有修改或降级lint。

每进程实际起止、退出码、argv、cwd、环境、工具与源码哈希见 [新manifest](independent-verification/format-followup/manifest.json)，原始stdout/stderr均同目录保存；未把旧18/165输出当作新源结果。测试计数从原始libtest输出复核，JUnit只是其派生XML，并非原生runner输出。

## 边界不变

本次只可关闭新固定源五个 documents 文件的格式门槛，不关闭 workspace 或生产集成门槛。按本次授权没有重复尝试全workspace的缺缓存 `anyhow v1.0.104` 路径，没有扩大权限或联网补依赖；此前该阻断属于旧源ab9c的实际记录，**不是d2ac全workspace已运行的证据**。前次 workspace fmt 另52个未改文件的问题仍保留，不以scoped fmt通过代替全仓格式通过。

作者初始测试先行尝试因工具链缺失而NOT_RUN，这段历史不变；当前新源测试通过不能追认当时的RED/GREEN或TDD。也不代表实际文档引擎、读取、撤权、缓存、授权租约或字节交付已接线。没有真实执行网关或Office功能验收，本报告不给合入/发布授权，Leader B仍是唯一develop合入者。

新证据文件以本分目录 `SHA256SUMS` 独立封存，可在分目录执行 `sha256sum -c SHA256SUMS`。全量staged diff-check exit2仅由原始libtest stdout末尾空行导致；原字节保留，排除新原始.log后的编写文件检查exit0。精确输出在新whitespace-check.json，不修改原输出以制造通过。
