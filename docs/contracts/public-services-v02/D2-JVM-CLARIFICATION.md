# D2 JVM 合同缺口澄清提案

2026-10-23。状态：**PROPOSAL / IMPLEMENTATION_PENDING**。本轮仅澄清合同，不新增产品代码、不运行 Kotlin、不新增生产接线，也不把下述候选声明为已冻结接口。整体计划已有实施授权；这里待裁定的是原计划未确定的语义和文件交接，不要求已批准范围逐任务重复索批。

## 已核事实

- JVM 报告固定输入：`3c72963a1adcb47fe82819a70310465e3eb8aeb4` 的 [REPORT.md](https://github.com/mightyoung/Muyon/blob/3c72963a1adcb47fe82819a70310465e3eb8aeb4/docs/tasks/public-v02-D2-JVM/REPORT.md)。已有获准 Kotlin 2.2.20 编译器实际启动，原 runner 退出 1，缺 IndexCompatibility.kt 及其四个符号；测试断言未运行。状态为 STRUCTURAL_RED，不是行为 RED / GREEN。
- 原 Documents 交接固定输入：`6e79be12fb537655454e8f28265439da02550530` 的 [PUBLICUI-HANDOFF.md](https://github.com/mightyoung/Muyon/blob/6e79be12fb537655454e8f28265439da02550530/docs/tasks/public-v02-D2/PUBLICUI-HANDOFF.md)。它明确完整条目的 true 语义与生产文件承接仍待确定。
- 已登记 Rust 组合候选为 `f2a3c21fcbb0ef6bd6c84e8c1fca750a990933f7`，尚不称已合 develop。Rust 实际接口是 services/pipeline.rs 的 validate_search / validate_embedding_search；后者消费每个 EmbeddingResult.descriptor，不能只比较 query 与 snapshot。
- ResearchIndex.kt 的 IndexSource(project, paper, revision, digest, modelIdentity) 没有公共 documentId、resultId、tokenizer 或 chunk 版本。paper / digest / modelIdentity 不能猜作公共 ID 或完整向量描述符；旧索引存在不证明来源仍可读。
- 三字段 LegacyIndexEntry 只是原 Kotlin 测试候选类型，不是现存存储 schema；字段齐全也缺完整 DocumentRef、ResultRef、IndexSnapshotRef 和当前授权来源。

本轮不重跑 JVM，不把别人的结构验证记为本轮执行，不改原 fixture 以换通过。

## 最小方案与推荐

方案 A（推荐，待父任务裁定）：先交纯值兼容性及候选字段筛查，名称直接表达没有宿主授权结论。暂不交一参数 isPubliclyResolvable 的 true 能力。优点是可以在已获准 JVM 环境独立 TDD，且不需要引擎、存储或 Reader；代价是调整原测试中的候选函数名和完整条目正向用例，不能声称完成公共解析。

方案 B：现在把 isPubliclyResolvable 改为需要可信解析上下文的接口。它需要准确的当前身份 / scopeGeneration、不可伪造输入来源、原 owner 查询及原子重验、失效与错误语义；只有 callback 或 wire resolved=true 不足以完成它。本轮没有这些生产 owner 的交接和类型，不建议为通过原四个反例而臆造此接口。

不采用“所有条目恒 false 即算功能完成”，也不采用“三字段非空即算公开可解析”。未确定上述选择前，原测试仍是结构阻断，不添加假 GREEN。

## 方案 A 的精确最小候选签名

以下 Kotlin 声明是建议签名，尚未实现；仅属离线值检查，不是新的端口或 wire 授权协议：

```kotlin
package com.mightyoung.muyon.product.services.documents

data class VectorDescriptor(
    val modelVersion: String,
    val tokenizerVersion: String,
    val dimensions: Int,
    val chunkVersion: String,
)

data class LegacyIndexEntry(
    val documentId: String?,
    val resultId: String?,
    val model: VectorDescriptor?,
)

fun validateCompatibility(index: VectorDescriptor, query: VectorDescriptor): Boolean
fun hasPublicReferenceCandidate(entry: LegacyIndexEntry): Boolean
```

validateCompatibility 的输入是已经提供的描述符值，输出仅表示两份声明在当前 JVM 支持值域内兼容：

1. 任一 dimensions <= 0 拒绝；JVM Int 只支持 1..2147483647，未来解码 Rust u32 超出此范围必须明确拒绝，不能截断或转负。本片不实现 codec。
2. 任一 model / tokenizer / chunk 字段按 Rust 参考 guard 的 trim-empty 语义为空时拒绝；不能只用“同一个坏描述符与自身相等”获得 true。Kotlin 空白判定需用跨语言 fixture 验证与 Rust 参考行为一致，不假设两语言默认 isBlank 完全相同。
3. 四个字段逐一精确相等才 true。版本字符串不 trim 后比较、不改大小写、不解析浮点数或推断兼容别名；维数 768 仅为 synthetic fixture 样本，不硬编码为唯一模型。
4. 不解析模型文件，不获取向量，不证明存量向量本身的维数 / 归一化或真实模型身份正确。

hasPublicReferenceCandidate 的输出仅为本地“可送后续解析”的必要条件：

- documentId 符合现有 Rust DocumentRef 的 ASCII `[A-Za-z0-9_.:-]{1,128}`；它不是路径。
- resultId 满足现有 C1 ResultId：非空、UTF-8 编码不超过 128 字节、不含 NUL。不要用 Kotlin UTF-16 length 代替字节上限，不强行套用 DocumentId 的 ASCII 限制。
- model 非 null，且 validateCompatibility(model, model) 为 true。
- 任一不满足则 false。三项满足可返回 true，但仅为结构候选；不表示记录存在、跨账户可访问、版本新鲜、正文可打开或获准查询。

上面的 LegacyIndexEntry 三参数构造顺序保持原测试形状，纯筛查函数改名是显式建议的 source-level 变化。原四个缺字段反例保留并指向新名字；补有效候选 true、空白 documentId / 非法 ASCII、多字节 ResultId 的 128 / 129 字节与 NUL 反例。不得把该三个字段结构扩大包装为可信完整条目。

原 `isPubliclyResolvable(entry: LegacyIndexEntry): Boolean` 的宿主成功语义继续 **UNFROZEN / NOT_IMPLEMENTED**；若父任务选择保留旧名称，须另行冻结含可信解析输入的宿主判定合同，不能保留原名却悄悄改成形状判断。本提案不提供恒 false 兼容壳，也不新增 wire approved / resolved / authorized 字段。

## 可信解析必须保留的输入与结果条件

以下全部是现有 Rust 类型 / owner 能力，不创建一个 JVM“已授权”布尔令牌，也不在本轮承诺 Kotlin DTO / FFI 方法：

- 宿主绑定的当前 ScopeRef（account_id、workspace/project 与 scope_generation），不能从 UI / 模型字段取得授权。
- 精确 DocumentRef（scope、document_id、revision、format）及 ResultRef（result_id、input_document_ref、直接上游 input_result_refs、content_digest、producer_version、parameters_digest）。revision 使用规范十进制字符串 / 现有受检 Revision，不经 Double 或 JS Number。
- 精确 IndexSnapshotRef（snapshot_id、scope、revision、inputs、descriptor），以及原 owner 解析出的实际 EmbeddingResult 列表。每条 descriptor 与 snapshot、获准的 query descriptor 一致，直接 inputs 集合精确匹配且无重复；不能只消费条目自报 metadata。
- 可信 owner 在未来生产接线中必须于返回搜索结果和打开来源时分别重验当前 scope / grant / revision；旧来源仅可依实际历史版本权限访问，不能静默替换新文档。来源锚点仍绑定确定文本结果、digest、normalizationVersion 和 UTF-8 字节范围。
- ResultId 仍表示处理结果身份，不能变为业务 Receipt。失败、未知、找不到或不可访问分别表达；“没有解析结果”不证明文档不存在。

现有 validate_embedding_search 是纯前置 guard，不证明 account / generation 授权或原子发布已完成。完整公共解析不应压成一个丢失失败原因的 Boolean；最终采用既有 ServiceError 投影还是更细的判定封套，留给 Documents / 可信宿主 owner 与 Contracts 明确，不先造新契约类型。

## 文件与责任归属

| 范围 | 当前责任 / 建议交接 | 本轮边界 |
| --- | --- | --- |
| Rust services/documents.rs、sources.rs、pipeline.rs 与来源语义 | Documents owner | 已有候选参考，不在本澄清中修改 |
| product/services/documents/IndexCompatibility.kt | 原计划 owner 为 Documents；建议父任务明确交给 PublicUI 实现方案 A，Documents 负责语义审阅 | 交接未确认前，PublicUI 不擅自取得该生产文件所有权；无需重新申请已有工具授权 |
| 同目录测试 IndexCompatibilityChecks.kt、run-offline.sh | Documents 原规范；PublicUI 已承接 JVM 验证，测试更新需随最终方案共同审阅 | 保留原反例，新增真实行为正向与非法值用例 |
| crates/muyon-core/tests/fixtures/public_pipeline.json | Documents 唯一事实 owner，Contracts 审跨语言一致性；PublicUI 消费 | 添加新跨语言向量由 owner 正常提交，不能两端各自维护模型事实 |
| 当前身份、原授权、派发、可信解析 / 来源打开 | 原可信宿主 / 业务与资料 owner；具体 Kotlin 生产接线 owner 未交接 | 不由 UI / Skill 签发，不在本轮填替代 owner |
| services/mod.rs、core / FFI 登记 | Contracts 唯一 owner | 方案 A 是 Kotlin 纯文件，无新增 Rust / FFI 登记需求 |
| ResearchIndex.kt、Reader / FD / 原生引擎 | 维持现有 owner 与 D3 / Reader gate | 不迁表、不补推断 ID、不接引擎或替代读取通道 |

父任务只需裁定方案 A / B 和具体生产文件交接；整体计划已授权部分继续按既定并行方式推进，不逐项重复申请。

## 可离线实施与验收边界

选定方案并完成文件交接后，承接者可在原已获准 PublicUI 环境中：

1. 消费固定共享 fixture（现 SHA256 `5d32c86bbc3291667632ecf4f94ebf182077a88cd17d3c86706b7068023943f2`）。原 Regex 只读取简单固定样本，不是严格 wire codec；fixture 新向量的解析方式须由 owner 指定并验证 major / synthetic 标记与所需字段，不能把漏读字段当默认值。无需新依赖。
2. 调整到父任务选定的精确签名；保留行为反例，新增有效 descriptor 自比较与有效候选 true。先最小桩成功编译，再观察行为断言失败；结构 RED 与行为 RED 分列。测试未执行前不填 passed=0 或 GREEN。
3. 使用已有 KOTLINC 路径运行原 runner（必要的签名更新按 owner 正常提交），先修真实编译 / 断言失败，再实现纯函数。命令保持 `-Werror -jvm-target 17`，不移除断言或扩大工具安装范围。
4. 覆盖四种 descriptor 单独变更、相等但非法值、两边分别非法、IDs 边界及缺字段、有效候选 true；新增 fixture 向量须两语言分别消费并记录精确版本。
5. 正常提交固定源码 SHA、编译器来源、fixture 摘要、命令 / 退出码 / 日志摘要和独立审查。纯 JVM GREEN 只接受兼容 / 形状筛查，不宣称宿主解析、真实 index / Android / 设备、engine invocation=0 或 Reader 已验。

没有 engine / dispatcher 端口时只报告静态无引擎依赖，不能放一个未连接 fake 计数器宣布零调用。D1 原 spy 的范围不扩大到 JVM 或原生 embedding / build。真实模型、下载、OCR、向量构建、网络请求及 Reader / FD 操作均不属于本轮补测试路线。

## 未决项与本轮完成事实

待父任务 / 对应 owner 裁定：方案选择及候选函数名；IndexCompatibility.kt 的具体承接者；共同 fixture 新增非法 / 边界值的安排。可信完整解析的数据投影、错误封套和实际宿主接线 / 原子重验留在后续工程 gate，不阻塞已明确的纯兼容函数切片。

本轮只读核了固定 JVM 报告、原交接、Rust pipeline / DocumentRef / ResultId 和现有 ResearchIndex 源码，输出此提案。未实施 Kotlin / Rust 产品代码、未安装依赖、未运行 JVM / Rust 测试或真实外部动作；无新的软件 RED / GREEN。本提案不改变 D3 / Reader gate，也不恢复任何被阻断生产 FD 桥。

静态审查：非作者 `/root/documents_registration_review` 已核固定报告 / 源码及本提案，未发现必须修问题；其审阅的文档摘要为 `dcd84bd82985edf9fb4295f89cb8859602ef231668ff89739c640af152ea3507`。可选措辞建议已采纳：把上述搜索 / 来源重验明确写为未来生产接线的必须条件，避免误读为现成搜索接线。审查仅静态读取，未运行软件测试；方案与 owner 交接仍待裁定。
