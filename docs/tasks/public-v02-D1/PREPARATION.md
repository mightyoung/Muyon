# Documents D1/D2 独立准备与接口交接

历史准备说明；本片原作于C1/C2未交付时。当前Rust候选交付与剩余登记/验证项以 [D1报告](REPORT.md) 和 [D2报告](../public-v02-D2/REPORT.md) 为准；工具准备以 [TOOLCHAIN.md](TOOLCHAIN.md) 为准。下方“待交付/未实施”为原准备阶段记录，不作为当前完成状态。

代码基线：`fd26dcdabcdac996bc2881e8141cac2b519966fc`（2026-10-23 从远端 develop 获取，PR107 已合入）。环境初始 `work` 为旧 main 合并点 `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`，未用作产品基线。独立工作区 `/workspace/muyon-documents-v02`，分支 `task/public-v02-documents-20261023`。

固定计划：`64900d4a6a46a9ef2919bcf922fb059413b1ce82` 下 [Documents](https://github.com/mightyoung/Muyon/blob/64900d4a6a46a9ef2919bcf922fb059413b1ce82/docs/superpowers/plans/2026-10-23-document-pipeline.md)、[总索引](https://github.com/mightyoung/Muyon/blob/64900d4a6a46a9ef2919bcf922fb059413b1ce82/docs/superpowers/plans/2026-10-23-public-services-index.md)、[设计](https://github.com/mightyoung/Muyon/blob/64900d4a6a46a9ef2919bcf922fb059413b1ce82/docs/superpowers/specs/2026-10-23-public-services-ui-design.md)。已完整读取三份；总索引的实际文件名带日期。未将计划分支作为代码父提交，也未移植尚未审查候选。

已扫描 /workspace 与固定 develop 文件树，未发现 AGENTS.md。已读任务 README、REVIEW、HANDOVER-LEADER 当前交接头、Android controller 交接、[StoreEvidence 交接](../evidence-local-chain-20261022/HANDOFF.md)、[Reader 交接](../android-document-reader-20261022/HANDOFF.md)及其 REVIEW-FOLLOWUP。旧阶段人员/工具链/通过记录不恢复当前授权或证明本环境通过。

## 既有真源与只读路径

以下路径均相对仓库根，源码观察固定于上述 develop SHA。

| 真源/入口 | 已有行为 | D1/D2 适配边界 |
| --- | --- | --- |
| `crates/muyon-core/src/documents/identity.rs` `DocumentRef` | 私有字段、受检 constructor/deserialize；scope/workspace/project、document_id、Revision、format | 复用原类型，不能新建另一文档身份。原 scope 尚不含账户；公共 ScopeRef 的可信绑定等 C1/宿主，不从 wire 猜账户 |
| `documents/storage.rs` `BusinessStore::read_document(&DocumentAccess)` | 原连接、Inspect 检查；访问值只是请求，持久 SQL 才是授权 | get_metadata 只委托原入口；Inspect 与 ReadText 各自检查，不能用 metadata 成功授予文本读取 |
| `evidence/store.rs` `StoredProcessing` | 私有缓存、只提供 source_metadata/receipt/projection；不能反序列化成可信处理结果 | describe_processing 是历史元数据投影，不发正文、不授予读取；只接受 Utf8Text + Available |
| 同文件 `StoreEvidence::process` | 创建本地处理结果，有实际处理效果 | 放命令侧；getter/read/resolve 不调用 process；无 Service/FFI 接线声明 |
| 同文件 `StoreEvidence::open` | 重新打开实际 controlled bytes；最终 BEGIN IMMEDIATE 内重验 ReadText、head、scope、grant、lease、长度与摘要，发布尾重验；清理失败丢弃成功 | read_blocks 逐条委托 open；不建立缓存 getter、替代 DocumentHost 或 FD 路线。批次并非共同事务快照，不据此保证整批原子读取 |
| `evidence/local.rs` `EvidenceRef` | source_id/source、evidence_id、UTF-8 半开字节范围、quote_digest、可空 0 基页索引 | 不重定义范围；source_locator 先核对完整 source；真正打开仍由原 open 校验 |
| `documents/storage.rs` 历史授权入口 | 基线已有独立历史策略 | StoreEvidence 当前文本路径仍拒绝非 head；本片不自动发历史 grant，也不把其他历史入口替换进 read_blocks |
| `crates/muyon-office/src/package.rs` | Package::open / extract_text 既有窄文本能力 | 仅列可复用引擎；D1 不接 Office，不宣称版式保真或完整编辑 |

完整处理身份投影候选（待 C1 实际签名核对）：ResultId 沿用 receipt_id，producerVersion 沿用 processor，inputDocumentRef 取 receipt.source.document，contentDigest/textDigest 对原样 Utf8Text 取 source.blob.digest，直接上游为空，normalizationVersion 固定 `utf8-original-v1`。parametersDigest 的 Utf8Text 规范编码与 Digest constructor 等 C1 fixture 冻结，当前不选择另一种编码。ResultRef 不携带原文缓存。

## F6.4 处理身份澄清（父任务审查结论，源码已核对）

`evidence/local.rs::ProcessingReceipt.receipt_id` 的注释明确为 deterministic processing identity，非业务 intent/commit receipt。生成值为 `processing-<64hex>`，ASCII共75字节；摘要输入包含 processor、source_id与InputKind，source_id又对完整SourceVersion序列化取摘要，包含文档scope/身份/版本和blob信息。不得因字段名receipt_id而把它当作业务回执。

D1可将该legacy processing identity一对一受检适配为typed ResultId，并显式保留ResultRef.inputDocumentRef与source/scope关联；读取/打开仍重验原owner权限。不得转成IntentId、业务Receipt或授予执行/取消权限，不另建结果账本。外部审查“混用业务回执”的措辞不能作为否定该ResultId适配的依据；真正要阻止的是跨身份类型替换、遗漏来源关联或绕过授权。

C1交接时需核对ResultId受检构造能否原样容纳75字节标识及共享fixture的编码；不截断、重编号或自行放宽公共类型。待写测试应覆盖同一处理的稳定映射、不同scope/文档/版本的来源区分，以及该标识不被解释成业务意图/回执；这些均未实施，不记录PASS。C1固定SHA仍为编码前置。

## D1 测试与精确合成输入映射（待写测试，非测试结果）

| 计划目标 | 已有可参考用例 | 新公共边界需证明 |
| --- | --- | --- |
| exact_utf8_anchor_checks | `tests/evidence_local.rs::synthetic_text_has_real_receipt_and_bound_utf8_anchor`、`forged_ranges_source_and_page_do_not_resolve` | 原样 UTF-8 `甲😀乙` 共10字节；find_literal("😀") 得 [3,7)，open 返回 emoji；改成 [4,7) 拒绝。独立篡改 ResultId、textDigest、normalizationVersion、EvidenceRef 的 source/evidence_id/quote_digest/page 均拒绝 |
| scope_revocation_and_old_version_checks | `src/evidence/store_tests.rs::persisted_revocation_expiry_generation_epoch_and_project_deletion_deny_cached_results`、`changed_current_revision_never_rebinds_old_evidence`、`corrupt_controlled_blob_never_uses_previous_cache_as_success` | A/B 项目同字节摘要，用 B access 打开 A processing/hit 必须拒绝；撤权、head 升级、删除/不可用原字节明确拒绝。不得仅以同 digest 或 ResultId 允许访问 |
| 实际 owner 原子性 | `reader_lease_and_grant_mutation_in_same_transaction_block_delivery`、`owner_delivery_transaction_excludes_other_sqlite_writer` | 原存储测试保留；公共 wrapper 不增加交易外正文发布或跳过 cleanup 的分支 |
| 零隐式工作 | `actual_registered_pdf_and_ocr_have_unsupported_receipt_not_fake_content`、`original_unknown_intents_are_not_looked_up_retried_or_changed` | getter 调用前显式准备处理结果；调用后无 parse/ocr/embed/build 增量，unsupported 不改 available；观察手段需与 owner 对齐，不为计数改原授权策略 |

新增 `tests/public_documents.rs` 和服务模块在 C1/C2 固定 SHA 到达后才写。先记录结构 RED，再提供最小 unavailable stub 观察具体行为 RED；编译/工具缺失不算行为 RED。不能把已有纯 Host 用例当真实 store 授权验收。原 StoreEvidence 测试位于同 crate module；若公共模块尚未登记，先交登记要求给 Contracts，不能自行修改 lib.rs 或复制 types/harness 冒充生产接线。

## Android OCR、embedding、索引映射

| 源码 | 保留的信息/限制 | 公共结果仍缺什么 |
| --- | --- | --- |
| `product/ml/LocalOcr.kt` `OcrLine(text, confidence, points)` / recognize | Bitmap 原尺寸传入检测框；输出四边形 PointF，confidence 来自 CTC 去空白/重复后输出 token 概率均值；recognize 支持 checkCancelled，资源 close | confidence 不是主张可信度；必须保留原引擎置信算法来源和图像位置。尚无文档 ResultId、页绑定、明确坐标系/单位/旋转及引擎版本封套；不能丢框只缓存文字 |
| `product/ml/LocalEmbedding.kt` | 构造即 nativeOpen；dimension=768；embed 区分 query/text 模板，native 分词，输出大小/有限值检查；close 释放句柄 | 不能在 getter 构造此类；公开 descriptor 需精确模型、tokenizer、维数、chunk 版本与文本 ResultRef，不以 768 推断兼容 |
| `product/ml/ResearchIndex.kt` IndexSource | project/paper/revision/digest/modelIdentity；SQLite sources/chunks；768维归一化向量；0<=page<200；最多3200 chunks、每chunk 768字符，总200万字符 | 没有公共 documentId/resultId、文本 normalization、tokenizer/chunk descriptor、索引 snapshot 身份/输入集合。旧 paper-only 条目不可补猜 ID 或冒充完整公共来源 |
| 同文件 search | 消费预先生成 queryVector；按 project/model 选择并调用 isCurrent；不联网、不构建索引 | 不能把 isCurrent 缓存或旧 paper 身份当公共授权；返回与打开来源分别重验 scope。查询向量生成不藏在 search 内 |

上述为静态观察，无真实模型、下载、native library 加载、ONNX 推理或 SQLite 向量检索运行。

## D2 synthetic 场景映射（等 C1/C2）

- late_job_cannot_publish_current：文档 id/scope 相同，仅 revision 不同，预期 StaleRevision；文档版本相等仅 scopeGeneration 不同，预期 ScopeChanged；全部精确匹配成功。保留旧产物与当前指针的断言需要可信 owner 场景，纯 can_publish_head 不能单独证明持久发布已接线。
- descriptor_mismatch_is_rejected：对 model/tokenizer/dimensions/chunk 各做单字段变化；输入集合少、多、重复、同摘要跨 scope 均拒绝；snapshot inputs 与直接 ResultRef IDs 精确对应。模型/template/tokenizer/分块兼容性不能由 digest 一项代替。
- job_cancel_maps_original_only：JobSnapshot 是只读投影；wire 的 original_intent_id 不可直接驱动 cancel。可信 owner 登记映射与 C2 cancel_original 才是执行路径；unknown/cancel_requested 不变 succeeded，关闭订阅不取消任务，游标过期只重新快照。
- Kotlin 的 VectorDescriptor / LegacyIndexEntry 与兼容矩阵依照 Rust fixture 投影；字段齐全只满足形状，仍需宿主解析/授权才可交付。父任务固定 fixture 前不复制第二份公共事实定义。没有查询时引擎调用计数为0的断言仍待实施。

## 发给 Contracts / 父任务的依赖清单

1. C1 最终完整 SHA、独立审查状态、共享 fixture 路径与 SHA256；ResultRef/ResultId/Digest/ScopeRef/Coverage/ServiceError/UnixMs/JobId 的实际受检构造与编码；Utf8Text parametersDigest 规范字节。
2. C2 最终完整 SHA、可信 IntentId 映射及 cancel_original 签名。ScopeRef 与旧 DocumentRef scope 的绑定策略，账户身份的可信来源和 ServiceError 的既有错误映射，不能默认补值。
3. Contracts 串行登记 `services/documents.rs`、`sources.rs`、`pipeline.rs`；确认既有 evidence 模块导出可供公共模块使用。Documents 不改 services/mod.rs、core lib.rs、FFI lib.rs。
4. 可用且已批准的现存 Rust/Kotlin 工具路径/缓存，或由父任务在已具备环境跑固定候选；不安装、不下载、不扩大权限。

D1、D2 代码与行为 RED/GREEN、回归、FFI/Android 接线均 NOT_RUN。D3 前置明确保持 BLOCKED；见 [工程 gate 草案](../../implementation/public-services-document-engine-gate.md)。
