# 统一 UI 与 Intelligent UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在既有 Compose 基础与卡片上提供经过宿主验证的呈现合同，保持原答、草稿与执行状态独立。
**Architecture:** 新公共模型不改旧 CardBinding 语义。纯校验输出受控计划，renderer 不持有命令端口；真正接入 ChatScreen 和 Shell 由原 Shell owner 收束。
**Tech Stack:** 现有 Kotlin/Compose、org.json、Rust 共享 fixture；无 HTML/JS 动态执行。
**Spec:** [v0.2](../specs/2026-10-23-public-services-ui-design.md) §7–11。
**Baseline:** [总索引](2026-10-23-public-services-index.md) 的完整 SHA、约束与证据要求适用。

## Global Constraints

- 保留六份独立内容：原始回答、UIPlan、UiState、BusinessSnapshot、业务意图、原始 Receipt。
- 渲染器只接收宿主验证后的计划；流式预览未完整验证前没有执行事件。
- 每屏最多一处主要吉祥物，支持隐藏、静态与减少动效。
- 首批十族；固定槽位不改变无障碍顺序；读取权限失效隐藏受限正文。
- Shell 在途任务拥有 ChatScreen、既有壳页面及接线，本计划不重复修页面。

## Review Focus

- Long 与十进制大 revision：U1 不溢出或截断。
- 模型 approved=true、未知 action/组件与嵌套爆炸：U1 退回可读文本且零 dispatch。
- 断流和重复事件：U2 只展示已验证计划，原身份去重交宿主。
- Read 撤权与 Action 撤权不同：U2 前者隐藏正文、后者仍允许有读取权的原答。
- TalkBack、200% 字号、减少动效：U3 检查关键按钮和原文入口。

## 真实基础和所有权

现有 `product/chat/components/ComponentContracts.kt` 已有 ComponentScope、SourceRef(revision: Long,page: Int)、ComponentDecoder 和 PendingSubmission；它不是新 UIPlan。
`product/ui/cards/CardModels.kt`、`ActionCards.kt` 已有 Attachment/Evidence/Choice/Draft/Confirmation/Receipt/Project 卡及精确 OriginalCardRequest；
`product/ui/foundation/` 已有主题/控件，不能重建 token。
`chat/persistence/HostDraftSaveState.kt` 与 `ui/shell/ReadOnlySnapshot.kt` 保留原 owner 行为。
旧 Dart `packages/muyon_module_api/lib/src/ui/planning.dart`、`validation.dart` 只读取语义。

下文路径以 `apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/publicservices/` 为根 P；测试根 T 是对应 `app/src/test/kotlin/com/mightyoung/muyon/product/ui/publicservices/`。P/T 是此处定义的路径缩写，新增文件均在该真实父项目下。

## U0：规范、变体、页面组合的可审阅设计 gate

**Owner:** PublicUI。**Files:** 先新增 `docs/design/public-services-v02/component-variants.md`、`page-acceptance-matrix.md`；读取既有 `product/ui/foundation/` token，不能另建一套值。依赖 v0.2 与 Shell 现有修复结果；不修改设置/菜单页面。

**Inputs/outputs:** `reviewPublicUi(existingFoundationPaths, approvedVisualDirection, cardInventory, shellFinalSha) -> {tokenReferences, proposedVariants, pageCompositions, designStatus, codeStatus, integrationStatus, acceptanceStatus}`。这是设计文档封套，不是产品 API。每项分别写 draft/reviewed，absent/present，not_connected/connected，NOT_RUN/PASS/FAIL。

- [ ] RED（设计审阅）：十族任一缺尺寸/密度/禁用/错误/加载/焦点/可访问变体或真实页面入口时列 gaps，不用“组件已有代码”通过设计验收。
- [ ] 对照 Foundation 标明已存在 token 的真实名称和值及来源完整 SHA；新增间距/圆角/尺寸只列 proposed，不把本计划的工程节点限制当视觉定稿。
- [ ] 为十族给可审阅变体与组合：聊天正文/资料结果、文档处理、Skill/Connector 配置、科研/询价详情、研发提案入口；卡片动作和回执依然同一套边界。
- [ ] 为每页面列正常/空/未知/失败/离线/部分/过期、320dp/200%/TalkBack/减少动效的待验收格，并标组件代码、页面接入与实测证据三栏。
- [ ] GREEN（设计审阅）：用户认可具体 token/变体/页面组合后才进入涉及外观的 U2/U3；U1 纯合同可以独立推进。设计未批准不填 PASS。
- [ ] 提交 `docs: define reviewable public UI variants and page acceptance`，不顺带建设孤立展示目录，不覆盖 Shell 原设置/菜单修复。

## U1：公共呈现模型、严格校验与跨语言 fixture

**Owner:** PublicUI。**Files:** 新增 P/PresentationModels.kt、PlanValidator.kt、PublicValueCodec.kt；T/PlanValidationChecks.kt、run-offline.sh。依赖 C1；不修改 ChatScreen 或现有 ComponentContracts。

**Interfaces，以下类型全部在 PresentationModels.kt 新增：**

- revision 全用 Kotlin String，由 `parseRevision(raw: String): String` 以字符长度/词典范围检查 0..u64::MAX；不用 Long/Double 中转。`parseUnixMs(raw: String): String` 校验规范 i64，返回原字符串。
- `AnswerRef(id: String, revision: String)`、`SnapshotRef(id: String, revision: String)`、`SourceBinding(resultId: String, documentId: String, revision: String, textDigest: String, startByte: String, endByte: String, pageIndex: Int?)`。
- `PresentationRequest(requestId: String, answerRef: AnswerRef, snapshotRef: SnapshotRef, displayIntent: String, catalogVersion: String, capabilityViewRef: String)`。
- `ComponentType` 为 MessageBlock/ChoiceCard/FormCard/ResultList/SourceCard/AttachmentCard/TaskProgressCard/DraftArtifactCard/ConfirmationCard/ReceiptCard 十项。
- `Node(id: String, componentType: ComponentType, typedProps: Props, bindingRefs: List<String>, children: List<String>, eventBindings: List<EventBinding>)`；Props 是封闭 sealed interface，U1 为十族逐个定义只含该族只读展示字段的 data class，不采用 Map<String,Any>。字段取下方 U2 组件表，授权/回执只能存引用。
- `EventBinding(eventKind: EventKind, actionRef: String)`；EventKind=LocalView/DraftEdit/DomainRequest。actionRef 必须属于宿主给出的动作引用集合。
- `UIPlan(schemaVersion: Int, surfaceId: String, planRevision: String, snapshotRef: SnapshotRef, root: String, nodes: List<Node>)`。
- `ValidationContext(snapshotRef: SnapshotRef, scopeGeneration: String, allowedActions: Set<String>, sources: Map<String,SourceBinding>, readAllowed: Boolean, actionAllowed: Boolean)` 由宿主提供；不是 wire 授权字段。
- `ValidatedPlan` 内部构造，仅 validator 可创建，持有 plan 与 context 的不可变副本。
- `PresentationResult(decision: Decision, reasonCode: String, plan: ValidatedPlan?, diagnostics: List<String>)`；Decision=TextOnly/Supplement/Replace；拒绝时 TextOnly，原答仍由独立 AnswerRef 读取。
- `validatePlan(request: PresentationRequest, plan: UIPlan, context: ValidationContext): PresentationResult`。
- `toLegacyRevision(raw: String): Long?` 只在 <=Long.MAX_VALUE 精确转换，否则返回 null 并禁用旧组件动作；SourceRef 1 基 page 显式转公共 pageIndex=page-1，page<=0 拒绝。新模型不退化为旧 Long。

Props 的十个新增构造签名为（字段集合是本计划候选合同，显示细节仍等 U0）：

```kotlin
sealed interface Props {
    data class Message(val text: String, val answerRef: AnswerRef) : Props
    data class Choice(val optionIds: List<String>, val selectedIds: Set<String>, val customText: String?) : Props
    data class Form(val fieldIds: List<String>, val fieldTypes: Map<String,String>,
        val values: Map<String,String>, val validationMessages: Map<String,String>) : Props
    data class Results(val itemIds: List<String>, val labels: List<String>, val sourceBindings: List<SourceBinding>) : Props
    data class Source(val sourceBinding: SourceBinding, val quote: String, val claimRelation: String) : Props
    data class Attachment(val documentRef: String, val stageCoverageRefs: List<String>) : Props
    data class Progress(val jobRef: String, val stage: String, val processed: String, val total: String?) : Props
    data class DraftArtifact(val draftRef: String, val contentSummary: String, val saveStatus: String) : Props
    data class Confirmation(val preparedRef: String) : Props
    data class Receipt(val originalIntentId: String, val receiptRef: String?) : Props
}
```

Form.fieldTypes 只允许 text/decimal/choice/boolean 且 keys 与 fieldIds 精确匹配；Results 的 itemIds/labels/sourceBindings 三列表长度相等、itemIds 唯一并同位关联；不满足则降级，不猜来源。claimRelation 首片只允许 unassessed/cited/candidate，不表示事实可信。saveStatus 只允许 unsaved/saving/saved/unknown/conflict；来源与处理覆盖 ref 必须宿主成功解析，不能由模型填 status=saved/complete 获信。十种 ComponentType 与 Props 一一匹配，其余组合拒绝。

U1 工程候选限制：单计划 <=256 nodes、深度 <=16、每节点 <=32 children、文本 UTF-8 总量 <=65536 字节；环、重复 id、悬空 children、未知 schema major/安全字段、缺 snapshot/source 一律 TextOnly。限制属于可评审 P1 值，生产配额见 D3；typedProps 的 Confirmation/Receipt 仅持有宿主对象引用，模型伪造内容不得构造可信卡。

- [ ] `planSafetyChecks`：unknown component/action、approved 字段、257 节点、17 层、环、缺 source、snapshot 修订不符全部 TextOnly；fake command 调用计数=0。
- [ ] `revisionAndPageChecks`：9007199254740993 往返不变；9223372036854775808 不映射 Long；旧 page=1→新 0，旧 0 拒绝；多字节 UTF-8 来源区间用字节。
- [ ] RED：`bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/publicservices/run-offline.sh`；先建同既有 cards/run-offline.sh 的无下载 runner，缺编译器 BLOCKED；结构失败单列。
- [ ] 实施封闭 Props、codec、图校验及 ValidatedPlan；runner 消费 C1 JSON 正反 fixture，不另造 Kotlin 事实定义。
- [ ] GREEN：同命令断言全部通过；回归 `bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/run-offline.sh`。
- [ ] 提交 `feat: validate public presentation plans`；审查仅模型/纯校验，不可顺带接 UI 事件。

## U2：十族卡片、四轴状态、事件和 Bot 配置投影

**Owner:** PublicUI。**Files:** 新增 P/PublicRenderer.kt、PresentationState.kt、EventProjection.kt、PublicCards.kt；T/PresentationStateChecks.kt、CardCatalogChecks.kt；既有 cards/foundation 文件只有取得相应 owner 交接后允许修改，优先组合现有组件。依赖 C2/C3/U1/U0 已审变体，Shell 页面接线另等原任务交接。

**Interfaces，新增精确定义：**

```kotlin
data class UiState(val surfaceId: String, val planRevision: String,
    val uiStateRevision: String, val viewState: Map<String,String>, val draftStateRef: String?)
data class BusinessSnapshot(val ref: SnapshotRef, val sourceRefs: List<SourceBinding>)
data class UiEvent(val eventId: String, val surfaceId: String, val nodeId: String,
    val observedPlanRevision: String, val observedUiStateRevision: String,
    val eventKind: EventKind, val typedPayload: EventPayload)
sealed interface EventPayload {
    data class View(val key: String, val value: String) : EventPayload
    data class Edit(val draftRef: String, val fieldId: String, val value: String) : EventPayload
    data class Request(val actionRef: String) : EventPayload
}
sealed interface UiEventOutcome {
    data object AppliedLocal : UiEventOutcome
    data class DraftUpdated(val draftRef: String) : UiEventOutcome
    data class RequiresConfirmation(val actionRef: String) : UiEventOutcome
    data class Accepted(val intentId: String, val receiptRef: String?, val jobId: String?) : UiEventOutcome
    data object Rejected : UiEventOutcome
    data object Stale : UiEventOutcome
    data object Duplicate : UiEventOutcome
}
data class PresentationAccess(val scopeGeneration: String, val readAllowed: Boolean, val actionAllowed: Boolean)
fun projectEvent(plan: ValidatedPlan, state: UiState, event: UiEvent,
    access: PresentationAccess, seenEventIds: Set<String>): UiEventOutcome
@Composable fun PublicRenderer(plan: ValidatedPlan, state: UiState,
    snapshot: BusinessSnapshot, access: PresentationAccess, onEvent: (UiEvent) -> Unit)
```

PresentationAccess 由宿主当前订阅投影并持续更新；其 scopeGeneration 与验证时不符或 readAllowed=false 时 renderer 隐藏受限内容，projectEvent 返回 Rejected。actionAllowed=false 时禁用领域执行动作，不能靠旧 ValidatedPlan 继续执行。seenEventIds 来自本 surface 已观察事件集，命中即 Duplicate；持久去重仍由原 owner 负责。projectEvent 是纯投影：LocalView→AppliedLocal，DraftEdit→DraftUpdated 仅表示局部领域草稿已改变，保存状态仍未存；DomainRequest→RequiresConfirmation；Accepted 只能来自可信宿主调度结果，纯函数永远不能返回 Accepted。重复 eventId 的持久/原意图去重归宿主，本地只拒绝已知重复。UICallback 不实现 HostCommandPort。未完整流式输入不生成 ValidatedPlan，关闭 UI 仅释放订阅。

| 族与 Props 最小内容 | 复用/新增及验收 |
| --- | --- |
| MessageBlock：text、answerRef | 原答独立入口；读权有效可回看 |
| ChoiceCard：optionIds、selectedIds、customText | 复用 Choice，选中不提交 |
| FormCard：fieldIds、fieldTypes、values、validationMessages | 新通用表单；字段类型限 text/decimal/choice/boolean；领域校验归插件 |
| ResultList：itemIds、labels、sourceBindings | 查看/填草稿/请求动作分离 |
| SourceCard：sourceBinding、quote、claimRelation | 复用 Evidence；Unassessed 不改可信 |
| AttachmentCard：documentRef、stageCoverageRefs | 复用 Attachment；四阶段各自状态 |
| TaskProgressCard：jobRef、stage、processed、total | 新公共进度；无 total 不给百分比 |
| DraftArtifactCard：draftRef、contentSummary、saveStatus | 复用 Draft；保存/业务提交分离 |
| ConfirmationCard：preparedRef | 只解析可信 prepared 对象；普通继续不确认 |
| ReceiptCard：originalIntentId、receiptRef | 只读可信 C2 投影；unknown 只有原查询 |

Props 的 ref 均为 String 不透明引用，宿主按当前 scope 解析；text 等字符串限制沿 U1。固定十槽位顺序为 identity/header → status → summary → content → evidence → localEditors → primaryAction → secondaryActions → receipt/history → help/error；空槽不影响阅读顺序。新 ContextActionBar/MascotPresenter 只投影上述事件与可信状态，不持有执行权限。Bot 展示建议字段需 `SuggestedField(value: String, origin: Origin, userLocked: Boolean)`，Origin=User/Template/Model；锁定后建议不可覆写。createAgent 与 startTask 的 preparedRef/IntentId 分开，Bot 布局不在此冻结。

- [ ] `eventRevisionChecks`：旧 plan/state revision→Stale；错误 actionRef→Rejected；LocalView/Edit 的 fake host 次数=0；DomainRequest 不直接 Accepted。
- [ ] `fourAxesAndRevocationChecks`：正文可读+未存草稿+执行未知+来源过期同时呈现；action 撤权禁按钮但正文仍可读；read/scope 失效清正文并停止订阅；关闭 renderer 不调用 cancelOriginal。
- [ ] `catalogAndBotLocksChecks`：十族都登记且按十槽位排序；确认只接 preparedRef；userLocked 不被 Model 覆写；创建/启动回执 ID 不相等。
- [ ] RED/GREEN 使用 U1 runner；增补断言后先失败，再实现纯 state/event 和组合卡片；通过后单独提交 `feat: compose public service cards and event projections`。
- [ ] 审查通过后交 Shell owner 函数签名、fixture 与新组件；不得由本任务直接抢改 ChatScreen 或 ProductService。

## U3：真实呈现与无障碍验收

**Owner:** PublicUI；Shell owner 负责应用入口接线。**Files:** 新增 `apps/muyon_android/app/src/androidTest/kotlin/com/mightyoung/muyon/product/ui/publicservices/PublicCardsTest.kt`、`docs/tasks/public-v02-U3/REPORT.md`。依赖 U2 与实际 Android 环境，无依赖不运行或下载。

**Inputs/outputs:** 输入 U2 的 `ValidatedPlan/UiState/BusinessSnapshot`；输出仪器测试 assertions 与截图/可访问树摘要，不新增业务接口。

- [ ] 写 `normalEmptyUnknownFailureOfflinePartialExpired` 七状态 fixture 的 Compose 测试，assert 确认/停止/来源按钮始终可达；先在 U2 接线前 RED，记录源 SHA。
- [ ] 实施必要布局修正：320dp 小屏、fontScale=2.0、暗/亮、reduceMotion=true、吉祥物 Hidden/Static/Animated；每屏主要角色计数<=1，主操作炭黑，不复制 Linear 视觉。
- [ ] GREEN 命令：`cd apps/muyon_android && ./gradlew --offline :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.mightyoung.muyon.product.ui.publicservices.PublicCardsTest`；测试设备与已准备 native/model 构建输入必须来自原构建任务，缺失即 BLOCKED，不新增下载。
- [ ] TalkBack 人工核验朗读顺序、焦点、来源与错误说明；录明设备/API/字体/状态、实际问题，不用纯 JVM 或截图代替。
- [ ] 提交 `test: verify public cards accessibility and state coverage`，独立审查再申请页面接入；生产验收仍与 Shell owner 合作。

## 回退与验收

默认新 renderer 未启用。回退切回现有正文/卡片并释放本 UI lease，原后台任务不取消。验收须分纯模型、Compose 编译、设备与 TalkBack 四类证据；本轮均 NOT_RUN。桌面 Electron renderer 待框架和受限桥审阅，不生成未经验证的 TypeScript 实现。
