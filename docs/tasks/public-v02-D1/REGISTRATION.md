# Documents 公共库登记与组合候选

2026-10-23。状态：离线 Rust 候选，待 B 审查合入；不表示完整 D1 / D2、Kotlin 或原生引擎验收通过。

## 输入与隔离集成

- 已登记 Skills / Connector 基线：`1e1c0ee22580971b188300dfdaf783847aa3ccfb`。
- Documents 最终候选：`6e79be12fb537655454e8f28265439da02550530`；生产适配源码 `4bb47be7b3b34ff66da3b2e9bf740e924f56bd1e`，spy 测试源码 `421f7e88c4e035e44d6cc0c97674a4dc10fce399`。
- 共同祖先 `4d49a580cb518d9b0b80c9df3df1ff564194a639`，没有复制第二份公共合同。
- 新隔离分支 `task/public-v02-documents-registration-20261023`，普通合成提交 `befe1998490c629a514d9d5d785ff87edd9ff933` 的双亲为上述两候选；原分支和历史保留。
- 最终登记源码 `47d3f16158847dd5e89e5633e5efb3f92d97b237`。

已读取最终 SPY-BOUNDARY.md、D1 / D2 报告。登记产品差异限三文件：services/mod.rs 增加 documents / sources / pipeline 导出；public_pipeline.rs 改用真实库导出；public_documents.rs 的五项普通读取 / 来源用例改用真实库导出。

D1 的两项 spy 用例保留原测试边界：正向控制仍直接调用 fake process；零处理请求用例新增局部导入，继续使用实际源码的 instrumented include，让 crate::evidence 解析到原 spy。它们没有被冒称为真实库原生引擎计数。其余五项 D1 测试调用库实际导出，D2 五项全部调用真实库。没有改断言、spy 实现、生产三个模块、原 owner、fixture 或 Cargo.lock；没有为计数增加生产引擎 trait。

## 已执行的结构性 RED / GREEN

使用此前获准、校验过的工作区 Rust / Cargo 1.93.1，加载 `/workspace/muyon-contracts-tools/env.sh`；所有 Cargo 命令带 --offline --locked，本轮未安装或下载依赖。

- 合成基线的原 test-local 测试：D1 7 / 7、D2 5 / 5，退出码 0。
- 改真实库导入但尚未登记：退出码 101，unresolved import documents / sources / pipeline。此为结构性 RED，不是行为断言 RED；该临时状态未保存为不可变 RED 提交。
- 登记后三模块的 scoped GREEN：D1 7 / 7、D2 5 / 5，退出码 0。spy 原计数和真实 owner 的授权 / bytes 检查继续通过。
- 登记后的 workspace all-targets 严格 Clippy 退出码 0；固定源码又运行一次该命令，最终结果记录在下方。变更三份 Rust 文件 rustfmt --check 和 git diff --check 通过。

命令（仓库根目录）：

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_documents --test public_pipeline
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-core/src/services/mod.rs crates/muyon-core/tests/public_documents.rs crates/muyon-core/tests/public_pipeline.rs
```

## 未完成范围与回退

本片不是生产 DocumentPort / TaskPort 全量接通：没有新任务派发、原子发布接线、可信取消 adapter、订阅系统、账户级宿主授权接线或 FFI。原生 OCR / embedding / build 没有可注入端口，spy 仅覆盖测试内 process 请求导入边界，覆盖缺口及代码级证据继续见 [SPY-BOUNDARY.md](SPY-BOUNDARY.md)。pipeline guard 不能替代宿主在锁 / 事务内重验和执行。

Kotlin 文件随原候选保留为测试规范；本轮未运行编译器 / runner、未实现 Kotlin 生产兼容器、未安装工具。Kotlin 验收仍 NOT_RUN，交接见 [PUBLICUI-HANDOFF.md](../public-v02-D2/PUBLICUI-HANDOFF.md)。D3 与 Reader gate 不变，不接 FD / Reader 生产路径。

没有运行真实模型或外部 Connector，没有新增付费 / 授权范围；历史真实请求 unknown 与费用未知保持。仅 B 可合入 develop；本任务未改 main / develop、强推、删除分支或部署。

回退可用普通提交移除 Documents 三行登记并恢复原测试导入方式；保留已登记 Skills / Connector，不做数据迁移、历史结果或原 Receipt 删除。

## 最终回归与独立审查

固定源码 `47d3f16158847dd5e89e5633e5efb3f92d97b237` 的完整 workspace / all-targets 命令退出码 0：**658 passed / 0 failed / 0 ignored，42 组结果**。计数包含原有 overlapping targets，不表示 658 个独立业务场景。同一固定源码的 workspace all-targets Clippy `-D warnings` 退出码 0。

独立只读审查者 `/root/documents_registration_review` 核对合成双亲与共同祖先、三个模块源码不变、真实库 helper 可见性及类型 / 授权读取身份，确认只修改登记与测试导入，未削弱断言或 spy。无新增问题。

审查者使用独立 target `/workspace/muyon-contracts-tools/review-documents-export-target`，在同一固定源码运行上述 scoped 测试命令，实际 D1 7 / 7、D2 5 / 5，退出码 0；另运行同两个 test targets 的 Clippy `-D warnings`，退出码 0。其结论仅覆盖公共库登记及 Rust 验证，未外推原生引擎、Kotlin 或 D3 / Reader。

原始日志留在 `/workspace/muyon-contracts-evidence/`，不入 git；摘要 SHA256：

| 日志 | SHA256 |
| --- | --- |
| documents-registration-baseline.log | `a95297cebc261a95a847f329aa3352bd62105b5bd791b9fa05ea474752c1ed6c` |
| documents-registration-red.log | `79243e4514af971f48790291a5d92f879f6127a436cb37eebd8b0dcc06f6f56f` |
| documents-registration-green.log | `870b47d2c47f46e6fd430a30ac2f18209037192a885bfcf8bfd6f3662df77022` |
| documents-registration-clippy.log | `a3aab4763d19ea57349c912752bc9a02605b74c91629056e022b40e3e3a81c0b` |
| documents-registration-clippy-fixed.log | `6f1bbdc595ae28b3b2bde6ecaadbc2d182d8864612cfed2321501a1a7f99a15a` |
| documents-registration-workspace.log | `401106d82791d8f31084e2b650f3e145fcd818b8b7d39eb4b6d33ca797f1b40b` |

Cargo.lock SHA256 保持 `d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`；pipeline fixture SHA256 保持 `5d32c86bbc3291667632ecf4f94ebf182077a88cd17d3c86706b7068023943f2`；documents.rs SHA256 保持 `cac58f91838ee304564d720631f9999f95aed9cce1942687d7ab5ce45d13f6ed`。
