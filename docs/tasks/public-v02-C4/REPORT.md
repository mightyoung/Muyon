# C4 既有公共合同精度与兼容补覆盖

2026-10-23。状态：测试 / fixture 候选，待 B 审查合入；不新增生产能力或冻结新语义。

## 基线、范围与事实源

已重新 fetch develop，基线 `e943856e4b6e2de26a9c2c8e2fa0912713b590e5`（PR #110 合入 C1 / C2 / C3）。独立候选分支 `task/public-v02-contracts-c4-20261023`，固定测试源码 `689f5c820289de96c3df502b0504ea470148e5e3`。

只新增：

- `docs/contracts/public-services-v02/fixtures/scalar-boundaries.json`：fixture_version=1、contract_major=1、schema_major=1、synthetic=true 的独立测试资料，不是产品 wire DTO。
- `crates/muyon-core/tests/public_service_precision.rs`：通过实际库解析器、编解码器和原 Envelope 校验消费 fixture。
- 本报告。

原 types.json 与产品源码完全保持；不新增/变更 Money、Quantity、DecimalText、ServicePhase、ResultId 命名空间、授权或 dispatch。没有修改 services/mod.rs、core / FFI lib.rs、依赖或 Cargo.lock。

## 测试行为与覆盖

六项测试消费 89 条字面向量：68 条标量、6 条合同协商、5 条 scope 严格解码、10 条原身份。预期数据来自既有已确定合同，未通过被测 parser 计算预期值。

| 测试 | 要捕获的真实回归 |
| --- | --- |
| exact_integer_strings_reject_overflow_and_numeric_tokens | Revision / UnixMs 经浮点数损失 2^53+1 精度，漏拒 u64 / i64 溢出、负零/前导零/指数/JSON number |
| opaque_ids_use_utf8_byte_limits_and_reject_nul | 将 UTF-8 128 字节上限误按字符数或 UTF-16 计算、接受 129 字节或 NUL；同时比对直接 parse 与 wire 接受性 |
| digests_reject_case_length_and_alphabet_drift | 放宽 64 位小写 hex 的长度、大小写或字符集 |
| incompatible_majors_remain_explicit_errors | 未知 contract / schema major 默认为当前版本、错误码不再为 UnsupportedVersion |
| strict_scope_decoding_preserves_precision_and_rejects_ambiguous_authority | 重复 key / 嵌套重复 key / approved 额外字段被接受，scope_generation 转数值或截断 |
| original_envelope_validation_is_required_after_public_id_parsing | 将公共不透明 ID 解析当原命令合法性；多字节 ID 可通过公共 parser，但原 IntentId / plan_id ASCII 校验仍必须拒绝 |

fixture metadata 使用测试内受检结构，拒绝未知字段、未知 scalar kind、重复/空用例 ID、缺少对应类别与错误的 expected 形状。它不是新的运行时 schema 或完整跨语言 codec；当前只有 Rust 消费结果，不宣称 Kotlin / TypeScript 对拍已完成。

## 真实运行历史：无产品行为 RED

初次基线日志包含 contract 10 / 10 与 public_service_types 6 / 6，无测试失败，但外层命令会话最终返回 1；不据此记录该次命令成功。后续固定源码 scoped 命令已单独退出 0，覆盖上述原 16 项和新增 6 项。

新增测试首跑编译成功后 0 passed / 6 failed，原因均为 fixture 的重复用例 ID（scalar 与 native 两组同名），属于测试资料错误。修正 native 向量 ID 前缀后 6 / 6 通过；没有改产品实现或削弱断言。首跑失败不是产品行为 RED，本片不宣称新增 feature 的 RED → GREEN，也没有构造假生产缺陷。

使用此前获准且校验过的工作区 Rust / Cargo 1.93.1，加载 `/workspace/muyon-contracts-tools/env.sh`。本轮无安装 / 下载；所有 Cargo 命令 offline / locked。

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_service_precision
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_service_precision --test public_service_types --test contract
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-core/tests/public_service_precision.rs
```

scoped 命令实际 22 passed / 0 failed / 0 ignored，退出 0；新增测试 6 / 6。workspace all-targets 严格 Clippy 退出 0，新增文件格式检查、git diff --check 通过。完整固定源码回归和独立审查结论在下方最终证据段。

## 边界与回退

没有运行模型、外部 Connector、Android / JVM / 设备，未修改 Reader / FD gate。C4 不改变其他候选的合入状态或 D2 未冻结可信解析语义。公共登记仍由 Contracts 单写，B 唯一合入者；没有改 main / develop、强推、删分支或部署。

普通回退只删除新增测试 / fixture / 报告，无数据迁移、Receipt 或生产代码回退。新 fixture 独立保存，原 types.json 摘要保持；下游需对拍时消费此固定候选资料，不把未跑语言记为通过。

## 固定源码最终证据与独立审查

固定源码 `689f5c820289de96c3df502b0504ea470148e5e3` 的完整 workspace / all-targets 回归退出 0：**625 passed / 0 failed / 0 ignored，37 组结果**。计数包含原有 overlapping targets，不表示 625 个互异业务场景。不得把其他候选分支的 658 等计数套到本基线。

独立只读审查者 `/root/c4_precision_review` 比较固定基线与源码，确认 89 条向量全部实际消费、UTF-8 字节边界与 NUL 正确、字面期望独立、原 Envelope 校验仍独立、无语义扩展，未发现必须修复问题。

审查者加载同一已获准工具环境，使用独立 `/workspace/muyon-contracts-tools/review-c4-target`，在固定源码运行 scoped 三 targets 命令，实际 22 / 22 通过；同三个 targets 严格 Clippy `-D warnings` 通过，git diff --check 通过。没有修改代码或安装依赖。审查明确首跑重复 ID 失败不属于产品 RED。

原始日志在 `/workspace/muyon-contracts-evidence/`，不入 git；摘要 SHA256：

| 日志 | SHA256 |
| --- | --- |
| c4-baseline.log | `50623d496e4201cf0cf2274266ee86b5345f0254f6889c6f680fefa7ca137c1e` |
| c4-initial.log | `a649ba6ca33ef13811f4babf8cef7b0acd4b72845bc776a5ed63eee7978004c4` |
| c4-green.log | `e94f59aad4f3ff2fd05282334d6db6609f6e93440207cd70d10922da7005a34c` |
| c4-focused.log | `7586e393e178fd08ae1fa2ba65d58935f0caa22ba6d2ec21207c302b0ed573cd` |
| c4-clippy.log | `2a1a946f29e7356120cd796bcc4c0bf80e813af6ff624ebf9c39bf8b86850a56` |
| c4-workspace.log | `f7cd30d3f90fbe14dae0e311ef6755fa2805611ad55f3960e14a539d4fed7132` |

新 scalar-boundaries.json SHA256：`567a0af8fd678ad05eff13f9fe9caab626f11e9104c1e4b5f2c2025d44d632d8`。
原 types.json SHA256 保持 `af0e6170bceb8e1a12e0686ab2855353d257f1ca885b06b3e6dfbad3d81b70f5`；Cargo.lock SHA256 保持 `d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`。
