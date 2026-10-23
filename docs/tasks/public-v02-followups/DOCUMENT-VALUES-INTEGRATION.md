# Documents 纯值 / fixture 补片组合验证

2026-10-23。状态：离线 Rust / 测试资料组合候选，待 B 审查合入；形状筛查不是可信解析 / 授权，不改变 Reader / FD gate。

## 固定基线与增量

- 本轮 fetch develop 仍为 `456effb553315026ccf7432889e9785426418427`。
- 新隔离分支 `task/public-v02-document-values-integration-20261023` 从上一全登记及 Connector / Skills 第二片组合 `fd1107b7db27ab05ffd778213624cbc7223a8e38` 创建；这是候选基线，不冒称整个组合已合 develop。
- 原 Documents 最终候选 `041d283445754de182c494dd3e0990faebf84864`，固定源码 / 数据 `c95bc6a881bf721a982f907f1bd0bd37031dec40`。已读取 VALUES-REPORT.md、VALUES-FIXTURE-HANDOFF.md 与实际源码。
- 只挑入新增 82194347、8021b2c7、c95bc6a8、041d2834 四个提交，组合本地对应 06a69656、1269f935、246bafa1、9800111c；没有重复合入旧模块、登记或旧 test-local headers。
- 最终验证源码 `598ef0356573350be2d1a64b43d9115f8c41b421`：新 public_pipeline_values 测试改为 `muyon_core::services::pipeline` 真实库导入，移除 include 本地模块；测试主体 / 断言未变。

pipeline.rs、public_pipeline.json、public_pipeline.values.tsv 均与原固定数据逐字相同。没有修改 services/mod.rs、既有真实库导出测试、D1 spy、core / FFI lib.rs、Cargo.lock。新 helper 属于已登记 pipeline，无新登记行。

## 合同和资料边界

- validate_vector_compatibility 提取原 validate_search 的既有 guard：四字段原值精确相等、非零 u32、Rust trim-empty；validate_search 继续执行精确 inputs、scope 和 snapshot ID 校验。没有新增引擎或解析权限。
- 唯一事实 JSON 为 fixture_revision=2；81 个 descriptor 向量、28 个形状向量，另列 Rust White_Space 的 25 个码点。其 null / 空串 / NUL / 多字节与版本原文不被投影归一化。
- TSV 只是严格派生的测试资料，Rust 独立核其完整投影；Python exporter 及其 7 项测试不成为生产 codec 或 IDL。只消费旧 base descriptor 不算完整对拍。
- 形状正向只消费既有 DocumentRef / ResultId 及 descriptor 值条件，不证明记录存在、scope / grant 有效或正文可打开。kotlin_api_frozen=false、trusted_resolution_implemented=false 保持。
- Rust u32 大于 JVM Int 的合法值必须保留并明确标为投影域外，不能转负 / 截断；0 是可构造 Int 的必须执行反例。Rust 空白判定不改成 JVM 默认 trim；未配对 UTF-16 的生产政策不在本片冻结。

PublicUI 已由父任务另行承接固定输入对拍，本组合不编辑 Kotlin 文件、不代报 JVM 结果。Documents 单写 Rust / fixture，PublicUI 单写 Kotlin 生产文件、测试及 runner 的分工保持。

## 实际命令与运行记录

使用此前获准、已校验的 Rust / Cargo 1.93.1，加载 `/workspace/muyon-contracts-tools/env.sh`；无安装 / 下载，全部 Cargo offline / locked。Python 仅使用标准库。

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_pipeline_values --test public_pipeline --test public_documents
python3 crates/muyon-core/tests/support/test_export_pipeline_values.py
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-core/tests/public_pipeline_values.rs crates/muyon-core/src/services/pipeline.rs
```

最初两 targets 日志显示新 values 5 / 5、原 pipeline 5 / 5，外层执行器会话返回 1；未以该外层状态报命令成功。随后在固定最终源码用 Python subprocess 直接记录 Cargo argv / exit_code / SHA，实际三 targets exit0、17 / 17（5 + 5 + D1 7）。Python exporter 检查实际 7 / 7、exit0。未改变断言换通过。

原 owner TDD 失败 / 成功历史见其固定 VALUES-REPORT.md；本轮只重跑完整实现，不把挑入的历史 stub 提交冒称新观察到的产品 RED。

## 未运行与回退

没有运行 Kotlin / Android / 设备 / 模型 / OCR / embedding / index 引擎或外部 Connector；没有生产可信 resolver、来源打开、原子发布 / 取消接线。Reader / FD、D3、SDK HOLD、历史真实请求 unknown 和费用未知保持。

C4 仍为独立候选，没有混入本组合。B 唯一决定候选依赖与合入；未改 main / develop、强推、删分支或部署。普通回退可撤回本补片 helper / fixture / 派生资料及测试，恢复前一组合，不删除业务数据或原回执。消费新 fixture 的 PublicUI 候选必须与其固定版本共同审阅，不静默换回旧 TSV。

## 固定源码最终结果与独立审查

固定源码 `598ef0356573350be2d1a64b43d9115f8c41b421` 的完整 workspace / all-targets 命令实际 Cargo exit0：**676 passed / 0 failed / 0 ignored，43 组结果**。同一固定源码 workspace all-targets 严格 Clippy `-D warnings` exit0；变更 Rust 文件格式检查及 git diff --check 通过。计数含原有重叠 targets，不表示 676 个独立业务场景，也不计入单独 Python 7 项。

只读独立审查者 `/root/document_values_integration_review` 核对同一固定源码、四份挑入补丁与 owner patch-id、源码 / 数据摘要 / TSV 完整性、真实库导出及原 guard 语义，未发现阻断问题。

审查者使用独立 `/workspace/muyon-contracts-tools/review-document-values-target` 执行三 Rust targets，实际 17 / 17、exit0；Python 7 / 7、exit0；同 targets 严格 Clippy exit0。确认 81 descriptor / 28 shape / 25 White_Space、34 单字符输入、TSV 各类完整列数，且无 Kotlin / Reader / SDK / 登记或旧导出修复的变化。审查者未修改仓库，不把纯 Rust / Python 验证扩大为 JVM、可信解析或引擎验收。

原始日志 / 精确 argv 与 Cargo 返回码元数据在 `/workspace/muyon-contracts-evidence/`，不入 git；SHA256 摘要：

| 文件 | SHA256 |
| --- | --- |
| document-values-focused.log | `0d2627b75570f9e3d6e03f9f6ddb7cc4bb76a0ccf39cab81354f2e8cbc87d0c8` |
| document-values-focused-confirmed.log | `43250e911a89ae65a865364d0ee40ed95b66383bb09e2c6cf0e546036082dc41` |
| document-values-focused-confirmed.json | `ed57f377016c2e09871f2f6c464afaf3f4edac6ee28489ded2504dbfb0ffd3a8` |
| document-values-python.log | `55c443882838af1a647fbd8c514e974fa1fc55b0f5546ea5d7e5f0d11fdd0998` |
| document-values-workspace.log | `4b4c246ef31d64840b1855505c6f68a6a5736cd49e71d828a8a24ae8a2751c2b` |
| document-values-workspace.json | `08015160fb2ad71996935b47aafff9faa50cbffcf7231963d5c5d7ac7d859418` |
| document-values-clippy.log | `2826e3c2c993dabeeead3129691f038f404bcff20d65441e05428f97356f9c70` |
| document-values-clippy.json | `14ff99cdf2d72adeb6604ceb7a965f860d99dde4cc4b678f8638468db7fc63b2` |

唯一 JSON SHA256 `4f7fcb8f988ee390b6f8fffa39603e6b92f8d1e7ccb13667c414906a247d3cf5`；派生 TSV SHA256 `547e83849749b77397e460876da78ae1d881e4a58ae6c60151d1a99cc321412c`，均与 c95 固定输入相同。Cargo.lock SHA256 保持 `d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`。
