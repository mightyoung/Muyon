# 独立离线编译验证 — 通过编译/测试，格式仍 HOLD

本验证固定源 `ab9c381cc935be0cd52db5a8a455ce985bdba1db`（远端 `task/document-core-contracts-20261022` 已核对一致）。作者原环境 cargo 缺失、测试/格式 NOT_RUN 的记录保持原样；这次新环境的运行只补当前固定源的编译/行为证据，**不能追认原先测试先行的 RED/GREEN，也不能声称已验证 TDD**。

验证执行者独立于 documents 作者。在新 worktree `/workspace/Muyon-document-verification`、独立分支 `task/document-core-verification-20261022` 运行。验证前搜索 `/workspace/AGENTS.md` 与该 worktree 的 AGENTS.md，均未发现；已读作者接口、交付和独立静态复审。原 `/workspace/Muyon` 与 `/workspace/Muyon-group` 保持干净，group HEAD 保持 `7fde617bab8f45644820590529def5b2f2193454`。没有切换原工作区、修改生产/测试代码或锁文件，没有合并、配置凭据、扩大权限或下载新软件/依赖。

## 实际命令与结果

使用现存 `/tmp/muyon-rust/bin` 工具链、`/tmp/muyon-cargo` 缓存和现存 SQLite linker alias，所有 cargo test 均明确 `--offline --locked`。本验证未做安装或依赖下载。

```sh
export PATH=/tmp/muyon-rust/bin:$PATH
export CARGO_HOME=/tmp/muyon-cargo
export CARGO_TARGET_DIR=/tmp/muyon-document-cargo-target
export RUSTFLAGS='-L native=/tmp/muyon-native-libs'
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test documents
/tmp/muyon-rust/bin/rustfmt --edition 2021 --check crates/muyon-core/src/documents/anchor.rs crates/muyon-core/src/documents/capability.rs crates/muyon-core/src/documents/identity.rs crates/muyon-core/src/documents/mod.rs crates/muyon-core/tests/documents.rs
cargo test --offline --locked --manifest-path crates/Cargo.toml
cargo fmt --manifest-path crates/Cargo.toml --all -- --check
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core
```

精确 argv、cwd、实际 UTC 起止、每进程退出码、明确选取的环境字段、工具版本/二进制哈希、源/锁文件哈希与 SQLite link 目标哈希见 [manifest.json](independent-verification/manifest.json)。原始 stdout/stderr 分开保存，没有改写作者旧证据。

| 检查 | 结论 | 原始输出 |
|---|---|---|
| documents targeted compile/test | **PASS exit0，18 passed / 0 failed / 0 ignored** | [stdout](independent-verification/targeted.stdout.log)、[stderr](independent-verification/targeted.stderr.log) |
| documents 5文件 rustfmt --check | **FAIL exit1**，五个文件全部有格式差异 | [stdout](independent-verification/documents-fmt.stdout.log)、[stderr](independent-verification/documents-fmt.stderr.log) |
| 全 workspace cargo test | **BLOCKED exit101**，缓存缺 `anyhow v1.0.104`，停在解析/下载前，没有 workspace 测试执行证据 | [stdout](independent-verification/workspace-test.stdout.log)、[stderr](independent-verification/workspace-test.stderr.log) |
| workspace fmt --all --check | **FAIL exit1**，共57文件，其中5个本批新增、52个相对作者固定UI基线未修改 | [stdout](independent-verification/workspace-fmt.stdout.log)、[stderr](independent-verification/workspace-fmt.stderr.log) |
| 完整 muyon-core package cargo test | **PASS exit0，165 passed / 0 failed / 0 ignored**；16测试二进制、另0项doc-test；包含本批18项，不能相加算183个独立用例 | [stdout](independent-verification/core-full.stdout.log)、[stderr](independent-verification/core-full.stderr.log) |

仅有既有依赖 `core-agent-lab/core/src/host_session.rs` 的 read/write C声明两条 `suspicious_runtime_symbol_definitions` 编译警告，没有因而降低 lint 或改源。缺 anyhow 的 workspace 行为是离线环境阻断，不是 documents 行为测试失败；未尝试联网补依赖。

## 给父侧和作者的结论

- 本固定源没有在实际编译和已有18项测试中显示编译或行为失败；其权限/lease/几何的生产正确性仍以原有限合同和未来可信宿主实现为界。没有新增产品能力、实际文件读取、引擎解析或撤权集成验收。
- **格式应改，交回作者修复，不由验证者代修。** 新增 `documents/{anchor,capability,identity,mod}.rs` 与 `tests/documents.rs` 均不通过所用 Rust 1.99.1 工具链的 rustfmt。具体原始格式 diff 已完整保留。作者可在自己的分支处理这5个文件后，由父侧对新固定源复验；不要以本报告替新源背书。
- 全仓另外52个格式路径经 `git diff 3ecb544ad0a47ccc38fe830777f35588b92e8afc ab9c381cc935be0cd52db5a8a455ce985bdba1db -- <path>` 确认本批未改。见 [路径归因](independent-verification/format-diff-paths.json)。它们不是授权扩大修复的理由，也没有被本报告隐瞒或豁免。
- workspace 全量测试仍缺缓存依赖；本次仅完整验证了 muyon-core package，未验证 FFI workspace 全量。没有下载未知软件、填补凭据或执行真实模型/搜索、部署、费用请求、历史 unknown 重试或拒绝动作。
- 此报告不取代原静态安全审查，不证明 DocHost 已接线。preflight 不是可重用读取许可，实际字节交付仍需可信宿主原子复核。格式/全workspace条件未闭合，整体不可宣称全部绿色、可合入或完整Office功能完成。仍由 Leader B 唯一执行 develop 合入。

## 原输出、派生 JUnit 与封存

[验证材料目录](independent-verification/) 保存所有原始 stdout/stderr。`targeted.junit.xml` 与 `core-full.junit.xml` 是从原始 libtest stdout **派生**的 JUnit，非原生 runner XML；转换脚本保留，按原输出统计18/165，不虚构时长。`test-summary.json` 给出计数。

`SHA256SUMS` 覆盖同目录所有其他证据文件（自身除外），可从该目录运行 `sha256sum -c SHA256SUMS`。原始工具输出的空白保留；全量 diff-check 与排除原始 `.log` 后的检查分别记录，不能用格式化原始输出来制造干净结果。本次新增路径只在作者报告目录内，原生产和测试树对固定源 diff 为空。
