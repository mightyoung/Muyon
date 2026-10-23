# D1 处理请求spy与不可注入的引擎边界

2026-10-23。固定测试源码 `421f7e88c4e035e44d6cc0c97674a4dc10fce399`，生产documents/sources/pipeline适配及原StoreEvidence与此前 `4bb47be7b3b34ff66da3b2e9bf740e924f56bd1e` 逐字相同。仅修改 `tests/public_documents.rs` 并新增 `tests/support/read_owner_spy.rs`，没有生产trait/新依赖、登记或引擎接线。

## 最小可测试边界及实际计数

现有公开函数接受具体BusinessStore/StoredProcessing，不接受OCR/embedding/index引擎或dispatcher，不能直接注入真实引擎spy。本片采用集成测试的crate导入边界：实际适配源码仍通过include编译，其 `crate::evidence::store::StoreEvidence` 在测试内解析为spy。fixture准备继续使用原muyon_core owner；只对适配调用进行观察，不复制公共类型或构造可信host。

spy.open先计数，再逐项委托原StoreEvidence::open；权限、实际bytes、版本与cleanup检查仍在真实owner中执行。spy.process是fake不可用工作接收端：按InputKind计数后立即返回原类型NotAvailable错误，绝不委托真实processor/引擎。它能记录“请求后丢弃错误”的隐式工作，不能被旧receipt相等断言替代。计数为thread-local；当前适配函数同步执行，无跨测试计数串扰。

| 运行场景 | real-owner open | process请求 | parse请求 | OCR请求 |
| --- | --- | --- | --- | --- |
| 正向控制：依次调用fake Utf8Text/Pdf/Ocr | 0 | 3 | 2 | 1 |
| getMetadata/describe/sourceLocator/readBlocks/resolveAnchor正常读取 | 2 | 0 | 0 | 0 |
| 撤权后getMetadata/readBlocks/resolveAnchor拒绝 | 2（两次均由原owner拒绝） | 0 | 0 | 0 |

“parse/OCR”是按InputKind分类的处理请求计数，非引擎实际调用次数。没有给embedding/build填虚构0；这些方法根本不在此owner API上。

## 突变验证（非生产功能缺陷修复）

新增测试对本已只读的实现直接通过，因此没有伪造新产品feature行为RED。另做两个明确的负向控制：在read_blocks的 `describe_processing(processing)?;` 后分别临时插入以下任一行，丢弃返回值：

```rust
let _ = StoreEvidence::new(store).process(access, InputKind::Utf8Text);
let _ = StoreEvidence::new(store).process(access, InputKind::Ocr);
```

两次均只命中fake接收端，没有运行真实processor/OCR。parse突变实测open=2/process=1/parse=1，OCR突变实测open=2/process=1/OCR=1；目标测试均0 passed/1 failed/6 filtered，退出101。突变未提交：可按固定基线421f7e88及仓库外对应patch重现，不声称存在独立RED commit。每次后恢复原文件，最终生产documents.rs SHA256为 `cac58f91838ee304564d720631f9999f95aed9cce1942687d7ab5ce45d13f6ed`，与固定源码一致。

```sh
source /workspace/documents-v02-tools/env.sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_documents adapter_getters_make_zero_processing_requests_on_success_and_denial -- --exact
# 恢复后：
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_documents
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
CARGO_TARGET_DIR=/workspace/documents-v02-tools/clippy-target cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --all-targets --offline --locked -- -D warnings
```

恢复后D1实际7/7，退出0；完整workspace38个测试二进制631 passed/0 failed/0 ignored；严格Clippy退出0。它们是离线合成Rust/存储验证，不是模型、Android或端到端生产证明。

## 原生OCR/embedding/build的代码级无调用证据

| 实际代码入口 | 当前调用链 | 不能外推的结论 |
| --- | --- | --- |
| services/documents.rs:74 get_metadata | BusinessStore::read_document（原Inspect检查） | 未经登记的公共/FFI入口仍未验 |
| 同文件:81 describe_processing | StoredProcessing::receipt、原stable_digest和C1受检值构造 | 元数据投影不证明当前授权或实际engine状态 |
| 同文件:113 read_blocks | describe_processing → StoreEvidence::new/open | 当前读取链只消费已有结果；不能推断未来新增旁路的调用数 |
| services/sources.rs:27/44 | source_locator元数据检查 → StoreEvidence::new/open | 没有通用FD或缓存正文getter |
| evidence/store.rs:99 open | with_source真实事务/bytes检查 → LocalEvidence::open | 不调用store.rs:79 process；权限仍由原owner控制 |
| evidence/local.rs:345 open/:281 passage | check → 已有text范围/摘要校验 → check | 不调用process_local，不启动OCR/embedding |
| services/pipeline.rs纯guard | 精确值比较、集合校验与snapshot投影 | 没有query/embed/build执行入口，不证明生产任务/取消已接线 |

这三个生产适配模块没有LocalOcr、LocalEmbedding、ResearchIndex、模型/原生库加载或可调用engine端口。Android的实际引擎在product/ml中，不由这些Rust getter引用。本次不为凑四个动态0扩展生产架构。现有spy不能覆盖未来绕过此导入的新直接调用；代码级调用图和独立审查必须继续保留。生产原生引擎接线时，需在真实宿主dispatcher提供可测的fake/spy边界另验；D3仍BLOCKED。

## 独立审查及剩余范围

非作者 `documents_preparation_review` 确认spy并非空洞、reads仍走原授权、fake process绝不执行真实工作；独立重跑D1 7/7退出0，核对两份突变计数失败与完整workspace631/0/0日志，无新增Important。可关闭“旧receipt相等不能证明零处理请求”的测试缺口，关闭范围限于此读取导入边界，不表述为全部原生engine计数验收。

公共登记仍需Contracts owner添加三行 `pub mod documents;`、`pub mod sources;`、`pub mod pipeline;`。Kotlin只交规范到 [PublicUI交接](../public-v02-D2/PUBLICUI-HANDOFF.md)，不扩大UI环境安装授权。

Ruling：使用test-only导入spy拦截既有process请求，open继续委托真实owner；不为测试新增生产引擎trait — 维持固定接口及授权边界 — 代价是原生embedding/build及未来绕过该导入的调用无法由该spy计数，当前仅提供明确代码级无调用证据，生产接线需另验。

## 仓库外证据

原始日志/突变patch位于 `/workspace/documents-v02-evidence/`，不提交。

| 文件 | SHA256 |
| --- | --- |
| d1-spy-green-first.log | `50e53c0b3a2169756d580f087243befab609ec8c90b41f8f1a376abd9210f3df` |
| d1-spy-parse-mutant.patch | `2eedce1ad034632620da542fb88d58ccf700b32f763021d793f8fcffb64d2173` |
| d1-spy-parse-mutant-red.log | `ae6e8bcb9873cbfc1f8eef53848f736ff4188d404f3b26d4216b1eeaedbfe6be` |
| d1-spy-ocr-mutant.patch | `ecdbab499916fd6820e3c8930bdeae1e84f84aad76626c69bf7fe6709bbb2e79` |
| d1-spy-ocr-mutant-red.log | `cadb0a35a95cf2ec1c2fb7a2d95ea2fcd83be3e4c7e6143e2b360702ee4f53ce` |
| d1-spy-final-green.log | `a3cf5d0a9bc2ac9beaf0b50df65d92df967d8c174f47edd27246902e80ab8e8b` |
| d12-spy-workspace.log | `12858a60babfa225629e7eb31f659bd2f88ddcb87e16792bb84c1ed37248f6ed` |
| d12-spy-clippy.log | `3b6675ca0c2e4c60ceb7fa9e11e2222cb8df42a89f39e00217b5c4de715e442c` |

最终补充文档审查：同一非作者reviewer只读核对7份当前文档、33处日志/patch摘要及源码调用链/行号，无新增Important或实质误述；确认Kotlin仅READY_FOR_HANDOFF、生产登记/FD仍未放行。该次为文档/证据审查，未再运行全套。

执行者当前文档静态检查日志 `d12-spy-document-check.log` SHA256：`6b01f07b058cf8b0cd17150a4d43571822825add4848ab86634e4b4761a4a5a0`；固定421f7e88测试源又跑D1 7项+D2 5项通过，日志 `d12-spy-fixed-source-focused.log` SHA256：`5ac9c163dc40fa9ab4679cf510955b68f46ff01fad6de7b5319f3c7400e9f5bb`。
