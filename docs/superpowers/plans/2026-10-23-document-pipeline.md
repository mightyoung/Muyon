# 文档、OCR、Embedding 与 Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将既有资料身份和引擎逐步接入精确来源链，首片交付受权限保护的已有文本读取，不重复建科研引擎。
**Architecture:** documents/storage 与 StoreEvidence 保持资料/授权 owner；Android 现有 LocalOcr、LocalEmbedding、ResearchIndex 只做引擎适配；新结果合同不改变原业务回执。
**Tech Stack:** 现有 Rust documents/evidence/muyon-office、Kotlin Android ml；不装模型或依赖。
**Spec:** [v0.2](../specs/2026-10-23-public-services-ui-design.md) §3–5、10–11。
**Baseline:** 完整 SHA 和约束见[总索引](2026-10-23-public-services-index.md)。

## Global Constraints

- 文档特定版本 → 解析/OCR 结果 → 确定文本与分块 → embedding 结果 → 索引快照 → 检索命中及来源锚点。
- 新文档版本不能复用旧结果冒充当前结果。
- 查询不触发隐式建库；查询外发、付费 embedding 或模型下载须先走既有授权链。
- 原生文本和 OCR 文本分别保留来源；总量未知不制造百分比。
- Reader Core 生产 FD 桥保持明确阻断，D3 不提供替代读取通道。

## Review Focus

- 旧任务晚于新 head 完成：D2 保留历史产物但不能覆盖当前指针。
- 跨项目同内容 digest：D1/D2 每次读与打开来源重验 scope。
- 中文/emoji 的 UTF-8 范围：D1 精确边界，不用 UTF-16 index。
- 异维数/模型/分词/分块混用：D2 搜索前拒绝。
- 文件删除、资源过期、订阅断流：D1/D2 返回失效/重新快照，零隐式工作。

## 已有接口与缺口

- `documents/identity.rs` 已有 DocumentRef；`documents/mod.rs` 已有 DocumentHost::resolve_current、validate_read、ReadRequest、CurrentDocument；具体受控读取使用 storage.rs 的 DocumentAccess。
- `documents/storage.rs` 已有 BusinessStore::read_document(&DocumentAccess) → Result<DocumentMetadata, ContractError>、register/publish/grant/annotation 可信入口。
- `evidence/store.rs` 已有 StoreEvidence::new(&BusinessStore)、process(&DocumentAccess,InputKind) → Result<StoredProcessing,StoreEvidenceError>、find_literal/open/answer；Utf8Text 真实受限读取可复用，PDF/OCR 返回 Unsupported，不是已支持解析。
- `crates/muyon-office/src/package.rs` Package::open(bytes:&[u8],limits:&Limits) → Result<Package,OfficeError>；extract_text() → Result<Vec<Section>,OfficeError>，编辑仅窄操作候选，不能据此宣称完整 Office 保真。
- Android `product/ml/LocalOcr.kt` recognize(bitmap:Bitmap,checkCancelled:()->Unit={}) → List<OcrLine>，LocalEmbedding.embed(text:String,query:Boolean=false) → FloatArray。
- `product/ml/ResearchIndex.kt` search(project:String,queryVector:FloatArray,modelIdentity:String,limit:Int=10,isCurrent:(IndexSource)->Boolean) → List<SearchHit>；固定 DIMENSIONS=768、页范围0..<200、chunk<=3200，当前身份依赖 paper/project。不能直接对外包装成泛文档 IndexPort 或恢复第二索引库。
- 原始 FD 访问及 Reader Core 阻断须由原任务解除；本计划仅复用已存在且合法的 StoreEvidence 文本 owner，不把它写成 FD 替代路线。

## D1：已有元数据、精确文本结果与来源读取

**Owner:** Documents。**Files:** 新增 `crates/muyon-core/src/services/documents.rs`、`services/sources.rs`、`tests/public_documents.rs`；复用既有 evidence/store.rs，不修改它的授权策略；模块登记由 Contracts 执行。依赖 C1/C2。独立审查交付是只读适配，process 仍按实际效果在命令侧调用，get/read 不触发 process。

**Interfaces，新增合同与函数：**

```rust
struct TextResult {
    reference: ResultRef, text_digest: Digest, normalization_version: String,
    coverage: Coverage,
}
struct SourceLocator {
    text_result_ref: ResultId, text_digest: Digest, normalization_version: String,
    evidence: EvidenceRef,
}
struct OpenedSource { document: DocumentRef, locator: SourceLocator, quote: String }
struct ResourceHandle {
    id: String, scope: ScopeRef, purpose: String, expires_at_unix_ms: UnixMs,
}
fn get_metadata(store: &BusinessStore, access: &DocumentAccess)
    -> Result<DocumentMetadata, ServiceError>;
fn describe_processing(processing: &StoredProcessing) -> Result<TextResult, ServiceError>;
fn source_locator(processing: &StoredProcessing, evidence: &EvidenceRef) -> Result<SourceLocator, ServiceError>;
fn read_blocks(store: &BusinessStore, access: &DocumentAccess,
    processing: &StoredProcessing, blocks: &[EvidenceRef]) -> Result<Vec<String>, ServiceError>;
fn resolve_anchor(store: &BusinessStore, access: &DocumentAccess,
    processing: &StoredProcessing, locator: &SourceLocator) -> Result<OpenedSource, ServiceError>;
```

上述 imports 为 C1 公共类型、既有 documents/business 类型及 evidence::store::StoredProcessing、evidence::local::EvidenceRef。describe_processing 仅适配已有 Utf8Text 且 extraction=Available 的处理结果：result_id 只适配 ProcessingReceipt.receipt_id 所标识的处理结果，具体编码映射在 Contracts/Documents 一致审阅后确定；它不是原业务 Receipt，也不形成执行账本。producer_version 沿用 processor，input_document_ref 与 content_digest 分别取 source.document/source.blob.digest，上游列表为空；parameters_digest 对固定输入种类 Utf8Text 的规范编码求摘要。其他种类返回 capability_unavailable，不把未解析内容标全文。

TextResult 不含明文缓存，不授予权限。P1 read_blocks 只打开原 find_literal 返回的已绑定 EvidenceRef，逐个调用原 StoreEvidence::open；resolve_anchor 也使用该原入口，每次重验 bytes/digest/grant，禁止构造“可信 host”或直接读本地缓存。source_locator 先检查 evidence.source 与 processing.receipt().source 一致；text_digest 对此原样 Utf8Text 使用 blob.digest，normalization_version 固定 `utf8-original-v1`。EvidenceRef 已有 start_byte/end_byte/quote_digest/page_index_zero_based，半开 UTF-8 字节范围不重定义。测试中篡改范围或伪造引用必须被原 open 拒绝。任意范围读取、全篇分页和新解析结果持久注册放 D3，不能误称 P1 已完成全部 readBlocks。

SourceLocator 的图像位置不在本片新增，继续既有 DocumentAnchor/PdfAnchor，结果绑定扩展见 D3。

ResourceHandle 是合同声明，P1 不签发 FD；宿主临时表管理 lease/释放，openReadHandle 的生产实现等 D3。read_blocks 对历史版本没有显式历史 grant 即拒绝，不能自动跳当前版本。

- [ ] `exact_utf8_anchor_checks`：文本 "甲😀乙" 的字节范围 [3,7) 返回 emoji；[4,7) 拒绝；错 result/textDigest/normalization_version 拒绝；伪造 EvidenceRef 也拒绝。
- [ ] `scope_revocation_and_old_version_checks`：项目 B 重用 A 的 digest/ResultId 拒绝；读取前撤权拒绝；head 升级后旧引用无历史 grant 拒绝；删除原文返回明确不可用。
- [ ] RED：`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_documents`，结构 RED 与具体行为 RED 分列。
- [ ] 实施对原 StoreEvidence 已生成处理结果的适配，不增加数据库旁路、不在 getter 调 process；加入调用计数断言 getter 的 parse/ocr/embed/build 次数=0。
- [ ] GREEN：同命令通过；回归 `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test evidence_local --test document_storage --test documents`。
- [ ] 提交 `feat: expose version-bound document text reads`；审查 open 时授权原子性与全文缓存是否泄漏；本片不宣称 PDF 读取完成。

## D2：任务、结果图和索引适配的确定性合同

**Owner:** Documents。**Files:** Rust 片为 `services/pipeline.rs`、`tests/public_pipeline.rs`。Kotlin 原候选路径为 `apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/services/documents/IndexCompatibility.kt` 与对应测试 `IndexCompatibilityChecks.kt`、同目录 `run-offline.sh`；其中生产文件及未决接口改列后续联合设计，不在本轮补实现。依赖 D1/C1/C2；只测合成结果与任务，不调用真实引擎。

**Interfaces，新增 Rust 类型/纯校验：**

```rust
enum PipelineStage { Parse, Ocr, Embedding, Index }
enum JobPhase { Accepted, Running, Succeeded, Failed, UnknownOutcome, CancelRequested, Cancelled }
struct JobSnapshot {
    job_id: JobId, original_intent_id: IntentId, scope: ScopeRef,
    stage: PipelineStage, attempt: u32, phase: JobPhase, coverage: Coverage,
}
struct VectorDescriptor {
    model_version: String, tokenizer_version: String, dimensions: u32, chunk_version: String,
}
struct EmbeddingResult { reference: ResultRef, descriptor: VectorDescriptor }
struct IndexSnapshotRef { snapshot_id: String, scope: ScopeRef, revision: Revision, inputs: Vec<ResultId>, descriptor: VectorDescriptor }
fn can_publish_head(expected: &DocumentRef, current: &DocumentRef,
    expected_generation: &Revision, current_generation: &Revision) -> Result<(), ServiceError>;
fn validate_search(snapshot: &IndexSnapshotRef, query_descriptor: &VectorDescriptor,
    inputs: &[ResultRef]) -> Result<(), ServiceError>;
fn cancellation_target(job: &JobSnapshot) -> IntentId;
```

JobSnapshot 是只读公共投影，不新建执行任务账本；attempt 表示原 owner 报告的尝试数，不能 UI 自增以获得重试。TaskPort 后续 getTask/subscribeProgress 消费同 snapshot，requestCancel 只能调用 C2.cancel_original(cancellation_target(job))。任务与原意图映射在可信 owner 保存，不能由 wire JobSnapshot 决定取消目标。

**Kotlin 后续联合设计（UNFROZEN / IMPLEMENTATION_PENDING）：** 原候选 `VectorDescriptor(modelVersion:String,tokenizerVersion:String,dimensions:Int,chunkVersion:String)`、`validateCompatibility(index:VectorDescriptor,query:VectorDescriptor):Boolean` 与 `LegacyIndexEntry(documentId:String?,resultId:String?,model:VectorDescriptor?)` 保留为待明确提案，不是当前已交付生产合同。`isPubliclyResolvable(entry:LegacyIndexEntry):Boolean` 是旧测试候选名，其可信完整解析输入、成功 / 失败语义及生产接线 owner 未冻结；旧名或四个缺字段反例不表示已具备公共解析能力，恒 false 通过反例也不是完成证据。

Documents、PublicUI、Contracts 与原可信宿主 owner 后续联合明确：纯兼容 / 形状筛查和可信宿主解析的边界；最终名称 / 签名；具备来源、精确 revision、scope / grant 与逐 embedding descriptor 核验的成功条件；`IndexCompatibility.kt` 的具体实现承接。Documents 保持原计划文件 owner，未明确交接前不转给 PublicUI。澄清稿 [D2-JVM-CLARIFICATION.md @ b15c7af6](https://github.com/mightyoung/Muyon/blob/b15c7af6d17f79de0eb393fc66aacd8b142118e9/docs/contracts/public-services-v02/D2-JVM-CLARIFICATION.md) 仍为提案；其中 `hasPublicReferenceCandidate` 若以后采用，也只表示形状候选，绝不表示可信可解析或获授权。本轮不实现上述未决接口，也不为消除结构 RED 扩展生产语义。

原 [JVM 结构验证 @ 3c72963a](https://github.com/mightyoung/Muyon/blob/3c72963a1adcb47fe82819a70310465e3eb8aeb4/docs/tasks/public-v02-D2-JVM/REPORT.md) 实际退出 1，原因是缺生产文件 / 符号；没有行为 RED / GREEN。未来 Kotlin 字段仍须消费同一 Rust fixture 真源；旧 paper-only 记录不能猜公共 ID 或冒充 ResultRef。当前优先 U1 修复与已完成 Rust 候选审查合入，Kotlin 联合设计不阻塞这些工作。

- [ ] `late_job_cannot_publish_current`：旧 revision/旧 scopeGeneration → StaleRevision/ScopeChanged；精确相等成功；旧产物保留于旧版本且当前指针不变。
- [ ] `descriptor_mismatch_is_rejected`：模型、分词、维数、分块各单独变化均拒绝；同摘要跨 scope 输入也拒绝；IndexSnapshotRef 直接 inputs 集合必须精确匹配且无重复。
- [ ] `job_cancel_maps_original_only`：取消总得到登记的 IntentId；unknown/取消请求不变 succeeded；游标失效只拉快照，关闭订阅不取消任务。
- [ ] RED/GREEN：`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_pipeline`；先 stub 行为失败再实施校验。
- [ ] 后续 Kotlin 联合设计完成并明确文件交接后，才更新旧测试候选名与精确签名、补完整正向 / 错误用例，并运行 `bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/services/documents/run-offline.sh`。结构 RED、真实行为 RED / GREEN 分列；兼容 / 形状检查不得记成宿主解析通过。未接入 engine / dispatcher 端口时只报告静态无引擎依赖，不虚构 engine invocation=0；原生引擎覆盖与 D3 / Reader / FD gate 保持。本轮不补此实现。
- [ ] 提交 `feat: validate pipeline provenance and task projections`；审查只交付来源/任务合同，不能说已完成 OCR 或语义检索。

## D3：生产资料管线工程 gate 与分段接线

**Owner:** Documents；Contracts 拥有命令/FFI 登记。**Files:** 先新增 `docs/implementation/public-services-document-engine-gate.md`、`docs/tasks/public-v02-D3/REPORT.md`，不得先改 Reader Core；通过 gate 且原阻断解除后才在后续计划中列出既有 ml 与 document owner 的确切修改。依赖 D2、原 Reader Core 明确解除、引擎许可/平台核验、原 UI Shell/内核交接。

**Inputs/outputs:** 输入 DocumentRef/ResultRef/ResourceHandle/JobSnapshot/VectorDescriptor、原 Reader Core 完整通过 SHA 与批准记录；输出工程决定文档的字段：引擎固定版本+许可证/NOTICE+Android minSdk/ABI、原 owner、任务/回执映射、受限资源表、配额/淘汰/订阅策略、实际任务签名和测试命令。未收到解除记录时输出 BLOCKED，不创建替代桥或 FD 新实现。

- [ ] 写 gate 核对清单，每个 port 的 getter/command 均标 present、contract_only、blocked 或 deferred，不以空实现凑全接口。
- [ ] 为每项写批准前失败条件：缺原 FD 解除 SHA、固定许可、账户绑定来源或资源释放方案任一项 → BLOCKED；gate “RED”是文档审查拒绝记录，不虚构软件测试红灯。
- [ ] 顺序评审：先 DocumentPort getMetadata/listVersions/readBlocks/resolveAnchor/openReadHandle；再 importDocument/createVersion/requestParse；后 OCR getResult/getCoverage/requestOcr；再 embedding getDescriptor/getCoverage/requestEmbedding；最后 index getCoverage/search/resolveHit/requestBuild/requestRefresh。每段单独分支和原 owner 同意，不一次上线。
- [ ] 对每段补精确实施签名和行为 RED/GREEN 后才编码；任何新增 Operation 先由 Domain/Contracts 明确原执行路径与幂等 owner。只读调用在失败时仍不得启动工作。没有原 owner 支持时 command=capability_unavailable。
- [ ] 单独评审图像 SourceLocator 坐标系/单位/旋转、Office 六态能力矩阵、批注保存/候选/确认发布/导出四个阶段及原回执。Office narrow edit 不升格完整 Office 支持。
- [ ] 性能/资源决定必须给每 scope 任务数、最大结果字节、缓存失效条件、订阅容量/游标过期、慢消费者处理、关闭/取消/释放时序；不得把 C3 测试容量当生产结论。
- [ ] gate 的 GREEN 是所有前置有固定证据且详细接线计划经用户审阅；只有此时另行申请生产实施。真实模型/外连/新增许可费用仍单独授权。

## 回退与验收

P1/P2 无引擎启动，正常 revert 新合同即可。未来产物版本只追加；切回旧读取不删新历史结果和原 IntentId。未知或部分产物不挂 current 指针；引擎不可用明确 unsupported/unknown，不切未经授权的网络服务。D3 生产 FD、完整格式渲染和向量端到端均为未完成显式依赖，不阻止 D1/D2 的离线合同交付。
