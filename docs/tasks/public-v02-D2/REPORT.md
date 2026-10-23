# D2 来源/任务纯校验 — Rust切片与Kotlin阻断

2026-10-23。状态：Rust纯合同/验证源码与合成测试交付；Kotlin实现/验证BLOCKED，模块登记PENDING_OWNER；不宣称D2全部完成、OCR/语义检索或生产接线完成。依赖及最终回归共享 [D1报告](../public-v02-D1/REPORT.md)。

固定Contracts依赖HEAD `4d49a580cb518d9b0b80c9df3df1ff564194a639`，原develop `fd26dcdabcdac996bc2881e8141cac2b519966fc`。D2测试/不可用桩RED `5aa76369959303584705f3d6e47bcc381a699726`；独审逐输入descriptor回归RED `2c3c34bf9a2426d92332b44f51478edb43f8f8f1`；最终GREEN组合源码 `4bb47be7b3b34ff66da3b2e9bf740e924f56bd1e`。Money/Quantity/公共error phase枚举未实现；新JobPhase仅为计划指定任务投影，ServiceError.phase是调用点标签，不作派发阶段证明。

## 交付与边界

- 新 `services/pipeline.rs`：PipelineStage/JobPhase/JobSnapshot、VectorDescriptor/EmbeddingResult/IndexSnapshotRef，以及计划签名can_publish_head/validate_search/cancellation_target。复用C1 ResultId/IntentId/ScopeRef/Coverage/ServiceError、旧Revision/DocumentRef，不建任务或结果账本。
- can_publish_head检查精确文档和scopeGeneration；只是原子发布前置条件，必须由原owner在锁/事务内使用。不修改任何当前指针/历史产物；测试中的历史数据/指针为合成局部值，不证明持久生产发布已接线。
- validate_search检查snapshot/query模型、tokenizer、维数、chunk精确相等、各input文档scope、直接输入ID集合精确且无重复；不生成查询向量、不建库。ResultRef不含账户/generation授权，宿主须另行可信绑定并在返回/打开来源重验。
- 新validate_embedding_search消费原owner解析出的EmbeddingResult，逐条descriptor与snapshot相等后复用原scope/集合校验。未来index/search owner必须用这个较强guard检查实际embedding来源；仅validate_search只能验证声明的metadata，不能证明每条embedding的descriptor。
- cancellation_target仅返回可信owner snapshot中的原IntentId，不派发取消、不修改phase/attempt；不得从wire snapshot取得取消权。实际任务映射和C2.cancel_original生产接线仍归可信owner。
- 测试复用C3 resume_action验证游标失效只选择ReadSnapshot；没有新订阅执行系统，UI关闭/后台任务/真实取消未接线。

Rust fixture `crates/muyon-core/tests/fixtures/public_pipeline.json` 标synthetic，descriptor是模型/tokenizer/chunk的合成版本及768维；该维数仅测试输入，不证明真实引擎兼容。fixture SHA256为 `5d32c86bbc3291667632ecf4f94ebf182077a88cd17d3c86706b7068023943f2`。Kotlin测试从同fixture投影语义，不复制另一套模型事实。

## 实际TDD与验证

```sh
source /workspace/documents-v02-tools/env.sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_pipeline
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/services/documents/run-offline.sh
```

Rust结构RED：缺pipeline.rs退出101，不算行为RED。最小unavailable桩后的行为RED为3 failed/1 passed，退出101；纯fixture用例原已通过，不冒称全红。实施后4 passed。独审发现未读取每条EmbeddingResult.descriptor；新增真实反例在同snapshot/query条件下替换某一输入descriptor，RED为4 passed/1 failed（错误接受），退出101；逐条检查后5 passed，退出0，覆盖两条输入分别变更model/tokenizer/dimensions/chunk。

最终D1/D2 focused各5项通过。完整workspace38个二进制629次执行通过/0失败/0忽略；严格Clippy与格式通过，命令及摘要在D1报告。未运行真实模型/引擎、Android、外部连接、付费或原FD生产路径。

## Kotlin精确阻断

已新增 `IndexCompatibilityChecks.kt` 测试规范和 `run-offline.sh`（沿用既有编译器发现方式），未新增生产 `IndexCompatibility.kt`。runner实际退出2：`NOT_RUN: existing Kotlin compiler unavailable; no installation attempted.`，尚未编译测试，不算结构/行为RED。当前安装授权只覆盖官方Rust工具与Cargo.lock缓存，未借此下载Kotlin或第三方程序。

继续条件：提供已有获准kotlinc路径，或父任务单独处理工具准备授权。之后先编译测试、提供最小桩观察行为RED，再写兼容实现。现有测试规范也不证明宿主解析/授权齐全或真实engine invocation=0；这些验证未运行，禁止填PASS。旧paper-only条目仍不能公开，不猜documentId/resultId。

## 独审、裁定与剩余项

非作者 `documents_preparation_review` 独立审查并重跑当时Rust4/4，发现Important：逐条embedding descriptor没有被消费；本轮按下述裁定追加测试/guard完成RED→GREEN，不冒称独立复审修复后的最终源码。D1动态引擎调用计数Minor保留；生产指针原子更新、账户绑定、可信job映射、订阅/取消仍非本纯校验切片交付。

Ruling：保留计划validate_search签名，新增validate_embedding_search消费完整EmbeddingResult — 原签名只有ResultRef，不足以拒绝实际向量模型/维数混用 — 若未来owner仅调用较弱metadata校验仍会漏检，故接线必须使用较强guard，当前不宣称生产search已接通。

Ruling：Kotlin缺编译器时只交测试规范、不写未观察行为RED的实现 — 不扩大Rust安装授权 — 代价是D2跨语言兼容验收仍BLOCKED。

正常回退仅revert新纯模块/入口，保留原IntentId/Receipt/历史结果；D3及Reader保持阻断。

## 仓库外日志

原始日志均在 `/workspace/documents-v02-evidence/`，不提交。

| 原始日志（仓库外） | SHA256 |
| --- | --- |
| d2-structural-red.log | `7f912cd6881f3602b5583f07a31092db25eb54c807a9b739e98e09d81e4f9a61` |
| d2-behavior-red.log | `813d67cf004d730819f206dad2a9920b84869e2e3246391eaf0eef38ec001a5b` |
| d2-green.log | `5c22f57f2b9991009208913dde7d34627a21db614b479f030f3332a6ba0f62ee` |
| d2-embedding-review-red.log | `8b41ab5c42cd89be64c01425fb845c84cfee1f2cbb27a7f9ac52a6bff221e4ad` |
| d12-final-focused.log | `4913cb21ee904803befb8884a3c2ac3eeef6fa6786b67098ba3b86a02225e398` |
| d2-kotlin-not-run.log | `0e44d74d1df1711d2355e0c710cc82fdfaa9f2846df4ef361298cd620e6ebb46` |
