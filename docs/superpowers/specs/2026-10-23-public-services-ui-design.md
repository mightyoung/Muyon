版本 0.2 · 2026 年 10 月 23 日 · 首稿待评审；本次补充 Skill 与 Connector 公共能力及统一命名。

评审记录 2026 年 10 月 23 日：用户已同意按 v0.2 作为阶段设计基线继续，下一步编制实施计划。原首稿状态文字保留作为历史；本记录不表示产品实现完成或实施计划已经获批。

# 一 目标与本稿定位

本规范把已采纳的方向整理成可共同评审的接口基线：公共能力进入公共服务层，科研、询价、开发管理插件在其上进行领域定制；UI 延续 Intelligent UI 的原文保留、结构化呈现和宿主执行分离。目标是让三个插件复用同一套资料、任务、来源和交互语义，而非各自维护解析器、索引库和执行入口。

分层方向及此前讨论的调用与 UI 合同作为本稿基础。下文 ServicePort、DTO、方法及字段名是待评审的候选命名，不表示代码已实现或接口已经冻结。旧 Dart 合同仅供语义迁移参考，不恢复 Flutter 路线；桌面 Electron 的 UI 框架尚未确定。本稿不包含产品实现、迁移承诺或新增测试通过声明。

# 二 层间责任与依赖

采用“类型化端口、宿主注入、平台适配”的方式，而非插件直连存储或统一重写所有引擎。

- 公共服务拥有原始文档、不可变文档版本、解析与 OCR 结果、embedding、索引及其任务状态。负责身份、精确版本绑定、覆盖率和资源生命周期。

- 业务插件拥有领域对象、业务规则及领域数据库。例如文献纳入规则、报价税运口径、仓库合并条件；引用公共服务的 documentId、revision 和 resultId，不复制另一份资料真源。修改公共资源只能通过公共命令入口，不能读取内部表或取得裸数据库连接。

- 可信宿主拥有当前身份、scope、权限、预算、命令调度和原始 IntentId/Receipt。插件声明所需能力，宿主注入实际可用端口；“能发现”或“支持该能力”均不等于获准执行。

- UI 拥有呈现、可访问交互和局部查看状态。业务事实来自只读快照，业务操作发出意图；UI、模型与插件展示模板均不能签发权限或成功回执。

- 平台适配器负责 Android/Electron 的资源访问、生命周期和引擎接线。Rust 承担已确立的可信策略与执行语义，OCR、PDF 或向量引擎可按平台选择成熟实现，不要求全部改写为 Rust。

依赖方向为插件/UI → 公共合同 → 宿主调度 → 服务实现与平台适配。公共合同不得引用某个插件的业务类型；跨插件访问同样经 scope 和权限检查。类型化端口是调用边界，不自动提供进程沙箱。

# 三 共享类型与版本字段

端口接受类型化请求，不把 Binder JSON、任意 IPC 方法名、SQL 或文件路径当公共 API。传输编码可以不同，但必须保持相同语义与校验。

|类型或字段|首稿约束|
|---|---|
|contractVersion / schemaVersion|协议与数据结构分别版本化；不与文档、业务、UI revision 混用。|
|DocumentId、ResultId、IntentId、JobId|带类型的非空不透明字符串，不用浮点数编码。IntentId 继续由既有宿主机制管理；JobId 仅关联执行任务。|
|revision / expectedRevision|规范十进制字符串，非负，无多余前导零；使用精确相等或 CAS，不转成 JavaScript Number，不跨对象比较大小。|
|DocumentRef|scope、documentId、revision、format；绑定确定版本，不接受含糊的“当前版本”代替执行前提。|
|ScopeRef / HostContext|账户、工作区、项目、scopeGeneration 及权限/能力版本由宿主绑定。调用方提供的选择只能被校验，不能充当授权事实。|
|时间与计量|时刻使用带 UnixMs 后缀的毫秒值，以有符号64位十进制字符串传输；时长明确 durationMs。金额用十进制数值与币种，数量带单位。|
|ResourceHandle|宿主签发的临时、不透明资源引用，带用途、有效期、scope 和释放语义。FD、URI授权或缓存路径不是持久文档身份。|
|ResultRef / Provenance|resultId、inputDocumentRef、直接上游 inputResultRefs、contentDigest、producerVersion、parametersDigest；检索命中另绑 indexSnapshotRef，embedding 增加模型/分词版本、维数与分块版本。|
|SourceLocator|绑定 textResultRef、textDigest、normalizationVersion；页索引从0起，展示页码另算，文本范围为该结果的 UTF-8 字节半开区间；图像位置携带坐标系、单位与旋转信息。|

宿主可缓存可用能力快照，但执行时必须重验。字段缺失、未知和读取失败分别表达；空值不变成零，未找到不自动证明从未发生。

# 四 公共服务端口清单

以下方法名描述语义，不新增第二套执行协议。只读请求不得顺带启动解析、OCR、下载模型、索引构建或付费模型调用。会创建持久结果、启动任务、对外披露或修改状态的请求按实际效果进入现有授权与命令链。

|候选端口|只读能力|命令能力与主要结果|
|---|---|---|
|DocumentPort|getMetadata、listVersions、openReadHandle、readBlocks、resolveAnchor|importDocument、createVersion、requestParse；返回 DocumentRef、解析 ResultRef 或关联任务。版本内容不可原地覆盖。|
|OcrPort|getResult、getCoverage|requestOcr；绑定文档版本、页范围、语言和引擎配置，返回文本块、位置、置信信息及失败单元。|
|EmbeddingPort|getDescriptor、getCoverage|requestEmbedding；绑定确定文本结果、分块及模型版本，返回向量集引用，不暴露内部库句柄。|
|IndexPort|getCoverage、search、resolveHit|requestBuild、requestRefresh；绑定精确输入结果集合与索引版本，命中返回原始来源链，查询不触发隐式建库。|
|TaskPort|getTask、subscribeProgress|requestCancel；返回阶段、attempt、进度计量及终态。执行任务关联原 IntentId，不以 JobId 替代业务身份。|
|DraftPort|getDraft|createDraft、saveDraft、discardDraft；使用 expectedDraftRevision，返回匹配版本的 SaveAck。仅保存草稿，不等于提交业务对象。|
|HostCommandPort|lookupOriginal|prepare、confirm、cancelOriginal；复用原 IntentId/Receipt，负责授权、去重、调度及回执投影。|
|SkillRegistryPort|listSkills、getDescriptor、getBinding|registerVersion、bind、setEnabled、unbind；管理 SkillRef 与绑定修订，注册不执行、不授权。|
|SkillRuntimePort|inspectRequirements、validateInputs、getRunSnapshot|requestRun；绑定精确 Skill 版本与输入，通过宿主编排公共能力，复用原 IntentId/Receipt 与 TaskPort。|
|ConnectorRegistryPort|listConnectors、getDescriptor、getConfigSchema|registerDescriptor、setEnabled、retireVersion；管理受信适配器声明，不隐式安装或运行程序。|
|ConnectionPort|getConnection、getBinding、getCapabilitySnapshot|configure、bind、requestConsent、requestConnect、requestReconnect、requestRevoke、refreshCapabilities；具名 requestCallTool、requestReadResource、requestGetPrompt 按实际效果经宿主执行。|

TaskPort 取消必须由宿主映射到原 cancel_original(intent_id)，不另设取消权威；按 JobId 取消子任务的映射及影响范围另行设计。向量检索消费已获准生成且与索引模型匹配的查询向量；查询外发、付费 embedding 或模型下载须先走既有授权链，不藏在只读 search 中。

PDF 阅读与批注、Word/PPT/Excel 的预览及受支持编辑统一归 DocumentPort 与公共阅读组件。能力矩阵按格式和操作声明 supported、read_only、unsupported、needs_license、needs_network 或 unknown；查看、生成编辑候选、确认发布和导出分别处理，不以某个编辑方法存在宣称完整 Office 能力。批注保存及文档编辑同样绑定预期版本与原回执。

DraftPort 统一草稿封套、版本和保存确认；领域内容及校验归所属插件，不能借它建立第二业务库。所有订阅有 scope、游标、容量与释放规则；断流或游标过期重新读取快照，不补播业务命令。关闭界面只释放界面持有资源，不默认取消后台任务。

## Skill 与 Connector 公共能力

外部应用、服务和 API 接入统一称 **Connector**；“业务插件”仅指科研、询价、开发管理等领域模块，不另设外部 Plugin 概念。MCP 是 Connector 可采用的一类协议，不等于全部连接方式，也不意味着所有连接都使用 OAuth。Skill 描述如何组织和使用能力，业务插件可注册、绑定自己的 Skill，对公共能力进行声明式二次编程。

SkillRegistryPort 管注册、内容版本、兼容范围和绑定；SkillRuntimePort 管依赖解析及运行编排。Skill 描述符至少记录 skillId、ownerPluginId、version、contentDigest、input/outputSchema、requiredCapabilities；SkillRef 固定版本与摘要，BindingRef 固定账户、工作区、项目或 Bot 的绑定修订。注册、绑定、启用与执行分开，不因某一步完成就获得网络、资料或写入权限。

首批维持可信内置业务插件边界。Skill 默认是提示、步骤和结构约束，不是任意代码执行入口；包中脚本只视为附带资源，可执行扩展的安装、隔离与运行需单独设计。宿主将当前权限、插件绑定范围、Skill 声明需求和连接实际授权取交集，每步派发前重验；Skill 只能收窄能力。上下文按需投影，不向 Skill 暴露裸凭据、整份数据库或无关会话。Skill 指令、远端 prompt、工具描述与结果都不能覆盖用户指令和宿主策略。

Connector 描述符包含 connectorId、adapterVersion、protocol、configSchema、authMethod 和声明能力；Connection 实例包含 connectionId、端点、外部账户/租户身份、配置修订、授权代次及当前状态。普通配置与 secretRef 分离，凭据由可信宿主解析，不进入 Skill、UI、日志或回执。配置继承和连接复用不能暗中扩大跨账户、跨项目访问。

能力目录分别记录 tool、resource、prompt，以及协议版本、schema 摘要、catalogRevision、获取时间与新鲜度。只读 getter 只取已有快照；联网健康检查、目录刷新、远端资源或 prompt 读取必须按实际外发行为处理。发现不等于授权；重连或新增工具不自动扩大允许集合，远端自报只读不能代替宿主判断。协议支持、授权状态、连通性和业务可用性分别展示。

连接生命周期包含同意、最小 scopes、到期、撤权和重连；扩权、换身份或端点变化使旧 prepared 失效。本地断开不等于服务端令牌已撤销；已发出动作由原 owner 收束。外部调用绑定 connectionId、外部身份、授权代次和目录版本；MCP 请求编号只作协议关联，不替代 IntentId。超时、取消及错误返回不自动证明未执行，保持原回执并查询或对账；不能核实时保留 unknown_outcome，不创建第二套 Skill/Connector 执行账本。

新增验收：绑定或升级 Skill 不扩权；恶意提示不能扩大工具集合；账号/端点/目录变更使旧调用失效；敏感配置不进入 UI 或日志；断开后旧操作可按原意图核对；同一连接在三插件中的权限隔离可验证。配置界面复用公共 FormCard、状态、确认和回执组件。

已有 Rust 中可确认两项编译期 Skill 及宿主工具子集入口，但这不等于上述统一注册和 Connector 生命周期已经接通。依据：[现有 Skill 目录](https://github.com/mightyoung/Muyon/blob/7aa852ab8134545c6312cd71de5c12cd49f66b5b/crates/muyon-core/src/agent/workflow.rs#L95-L122)、[宿主工具限制](https://github.com/mightyoung/Muyon/blob/7aa852ab8134545c6312cd71de5c12cd49f66b5b/crates/muyon-core/src/agent/owner.rs#L299-L310)、[Agent Skills 规范](https://agentskills.io/specification)、[MCP 宿主架构](https://modelcontextprotocol.io/specification/2025-11-25/architecture)、[MCP 授权](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)。

# 五 文档到来源锚点的精确链路

处理链固定为：文档特定版本 → 解析/OCR结果 → 确定文本与分块 → embedding结果 → 索引快照 → 检索命中及来源锚点。每一步记录直接输入的身份、版本、摘要及生成配置；原生文本和 OCR 文本分别保留来源，不用一个“已读取”标签掩盖差异。

不可变版本指内容不原地改写，不代表无限期保留，也不禁止依权限和保留策略删除。删除后保留所需的最小审计或失效标记，不保证原文仍可打开。新文档版本不能复用旧结果冒充当前结果。旧任务完成后可以保留其版本下的历史产物，但更新“当前可用结果”指针必须校验预期版本和 scopeGeneration，不能覆盖新版本。不同模型、维数或分块版本的向量不得混进同一未声明兼容的索引。

来源锚点必须能定位原文版本与范围。打开旧引用时，明确显示历史版本；原件不可用则显示原因，不静默跳到新文件。来源存在、文本提取成功与主张可信是不同事实。跨项目检索、共享缓存或内容摘要去重不得扩大访问范围，结果返回和打开来源时都重验 scope。服务复用不要求跨 scope 共用物理索引，可按权限域分区隔离。

解析、OCR、embedding、索引分别报告完整、部分、失败及未知覆盖。已保存附件不等于全文可检索，搜索无命中不等于资料不存在；总量未知时显示阶段和已处理数量，不制造百分比。

# 六 执行回执与恢复

现有 Rust 的 prepare(operation, project, expected_revision)、confirm_user_plan(plan_id)、lookup_original(intent_id)、cancel_original(intent_id) 是衔接基准。公共合同做类型适配，不替换其身份与权威状态。DomainIntent、DomainReceipt 若保留为设计名称，只能表示既有意图和回执的投影，不能新增 operationId 账本或插件自有去重真源。

prepare 绑定目标、规范化参数、scope、预期版本和适用授权；confirm 再验当前状态。改参数、换账户/项目、修订变化或撤权，旧确认即失效。模型、卡片或插件不能自报 approved=true；确认卡只能从可信 prepared 状态生成。写入许可与对外披露许可按各自目的核验。

展示需要覆盖 waiting_for_confirmation、accepted、running、succeeded、failed、unknown_outcome、cancel_requested、cancelled，并与既有 Receipt/Job 枚举建立明确映射。accepted 仅表示受理；进度事件不能作为成功证明；业务提交是否发生以原回执及原业务 owner 核对结果为准。

超时、断连、崩溃或结果丢失不能直接判定失败。unknown_outcome 保留原 IntentId，先 lookup/对账，不生成新意图盲重发。取消请求、实际停止和撤销副作用分别表示；语言侧丢弃 future 或关闭页面不构成 Rust 任务已经取消的证据。恢复只恢复可读快照和允许的草稿，不恢复旧授权，不自动执行历史事件，不宣称外部副作用已回滚。

统一错误封套候选字段为 code、phase、retryability、effectKnowledge、originalIntentId、safeMessage、detailsRef。稳定原因至少区分 invalid_argument、unsupported_version、capability_unavailable、permission_denied、stale_revision、scope_changed、resource_expired、partial_result、cancelled、unknown_outcome。是否重试须同时依据效果是否确定和当前授权，不能只凭 retryable=true。

# 七 Intelligent UI 呈现合同

保留六份独立内容：原始回答、UIPlan、UiState、BusinessSnapshot、业务意图、原始 Receipt。原答在当前读取权限有效时可回看；UIPlan 改变呈现，不改写原文或业务事实。UiState 保存展开、排序、选项和滚动；领域草稿另有版本。BusinessSnapshot 绑定原业务版本和来源，不能由模型文案替代。

|候选合同|最小字段与限制|
|---|---|
|PresentationRequest|requestId、answerRef/revision、snapshotRef、displayIntent、catalogVersion、capabilityViewRef；宿主构造事实和能力。|
|PresentationResult|decision、reasonCode、plan、diagnostics；可纯文本、补充呈现或替换呈现，均保留原答。|
|UIPlan / Node|schemaVersion、surfaceId、planRevision、snapshotRef、root/nodes；节点仅有白名单 componentType、typedProps、bindingRefs、children、eventBindings。|
|UiState|surfaceId、planRevision、uiStateRevision、viewState、draftStateRef；保存确认必须匹配当前修订。|
|UiEvent|eventId、surfaceId、nodeId、observedPlanRevision、observedUiStateRevision、eventKind、typedPayload；宿主追加真实交互、scope、业务版本与权限上下文。|
|UiEventOutcome|applied_local、draft_updated、requires_confirmation、accepted(intentId, receiptRef?, jobId?)、rejected、stale、duplicate；accepted 不显示成功。|

动作撤权立即禁用执行；读取权限或 scope 失效则停止订阅、隐藏受限内容并说明原因，不能把“保留原文”当持续展示许可。渲染器只接收宿主验证后的计划。校验包括 schema、组件/动作白名单、必显事实状态、来源绑定、大小深度限制和当前能力。流式预览未完整验证前没有执行事件；未知组件、坏数据或缺失来源安全降级为可读文字和原因，不能动态加载任意 HTML/JS 或按名字调用工具。

事件分为局部查看、草稿编辑/预览、领域动作请求。前两类不暗中提交、外发或增加付费调用；后者由宿主映射 actionRef 进入原命令链。双击、过期回调及历史重放沿原身份处理。渲染、草稿保存、执行、事实有效性是四条独立状态轴，允许“正文可读、草稿未存、执行未知、来源过期”同时存在。

# 八 首批组件与语义槽位

首批固定十类组件，插件扩展业务内容，不复制交互与执行规则。

|组件族|职责及关键边界|
|---|---|
|MessageBlock|文字与结构化块共存，原答可回看。|
|ChoiceCard|单/多选及自定义输入；选择与提交分离。|
|FormCard|类型化字段、局部校验及错误；业务校验仍归插件。|
|ResultList|区分查看、打开来源、填草稿和请求动作。|
|SourceCard|版本、范围、摘要与主张关系；可定位不等于可信。|
|AttachmentCard|附件身份与各处理阶段，明确部分覆盖。|
|TaskProgressCard|阶段、计量、子任务与明确取消目标。|
|DraftCard / ArtifactCard|一类草稿成果展示；草稿保存与成果提交各有身份和回执。|
|ConfirmationCard|可信目标、变更、范围、成本和到期条件；普通“继续”不替代批准。|
|ReceiptCard|原意图、结果、证据及历史状态；未知时查询原回执。|

固定槽位为 identity/header、status、summary、content、evidence、localEditors、primaryAction、secondaryActions、receipt/history、help/error。可留空但保持层级及无障碍阅读顺序。ContextActionBar 和 MascotPresenter 为共享附属组件，不另开权限入口；地图、专用交易卡及任意 HTML 扩展不列首批必需。

视觉沿用柔黑/柔白、炭黑主操作、少量低饱和来源链接及原 Muyon 角色和 m 图标，不回到米棕铺底或旧蓝白。每屏最多一处主要吉祥物，支持隐藏、静态与减少动效；姿态来自可信任务状态，动画暂停不暂停任务。审批、来源、错误和停止入口不得被遮挡。

# 九 三个插件如何定制

科研插件定义论文、研究项目、阅读记录、证据口径与纳入排除规则，复用资料处理和来源定位；不建立科研专属 OCR 或第二索引库。询价插件定义供应商、物料、报价、币种、税运、有效期和比较口径，公共服务只交付提取材料，不能自行认定报价可成交。开发管理插件定义仓库、issue、PR、验收项和流程规则，引用固定 commit、CI 与 review 证据，合并等真实动作仍走宿主命令。

三者使用同样的快照、错误、能力、来源和回执封套。插件贡献 data/relation、operation、view 的版本化声明；数据登记不自动迁库，动作声明不授予权限，页面声明不运行任意脚本。

Bot 配置复用以上组件，按名称、用途、技能与资料、权限/成本、确认渐进呈现。建议字段标记 user/template/model 来源及 userLocked，新建议不能覆盖手改。createAgent 与 startTask 保持独立意图和回执；入口沿既有菜单壳，配置页或对话内布局留待页面评审。

# 十 兼容策略与实施边界

每个端口声明合同版本、支持范围和错误语义；宿主先协商再启用。未知 major、影响授权/来源/执行的未知字段或不兼容 schema 拒绝；仅明确标为可选、可忽略的展示字段可降级。schema、DTO 编解码与三个插件的合同 fixture 应来自同一事实定义，避免 Kotlin、Rust、TypeScript 各自解释。升级不能删除原回执或把旧未决意图改成新请求。

插件和服务遵循注册、合同校验、启用、停用/撤权、排空/关闭的生命周期。注册仅登记元数据，不读取业务正文或自动授权；停用后停止新调用，旧 prepared 引用失效。已派发任务继续由原 owner 收束和核对，回执不随界面关闭或插件停用删除。引擎不可用应如实报告，不静默切换到未经授权的联网服务。

已有源码能确认部分 Android 聊天门控、原请求查询、草稿保存与候选卡接线；旧 Dart 包保存了 Intelligent UI 语义。尚不能据此宣称所列公共端口、全部卡片、跨端恢复或完整来源链已投入生产。

ReaderCore 的生产 FD 桥仍待单独获授权且解除阻塞的任务完成，本稿不提供绕过现有阻塞的路线，也不把替代读取方式写成已获准。桌面 UI 框架、IDL/生成器、各平台引擎选择、资源配额、缓存淘汰与订阅缓冲上限，留在后续详细工程设计中确认，不影响本稿的责任与安全边界。

# 十一 验收标准

以下均为待执行的验收要求，不是本轮测试结果。

1. 三插件通过相同端口完成资料读取和业务定制；UI/插件无内部数据库直连，无独立执行账本。

2. 文档、OCR、分块、向量、索引与锚点可逐级追溯精确版本；旧任务不能覆盖新版本，跨 scope 无泄漏。

3. 无效 schema、未知组件/动作及流式中断安全降级，零意外执行；动作撤权禁用操作，读取权限或 scope 失效隐藏受限内容，仍有读取权时原答可回看。

4. 双击、旧回调、参数变更和权限失效不能绕过原 IntentId/Receipt 门控；状态未知先查原结果，不能盲重发。

5. 草稿保存确认准确绑定修订；业务成功有原回执依据；cancel_requested 不显示为已停止或已撤销。

6. 合同测试覆盖编解码、兼容协商、并发修订、进程恢复、资源过期与订阅断流；三个插件运行同一组共享 fixture。

7. 正常、空、未知、失败、离线、部分覆盖、过期来源均有可视验收；小屏、200%字号、TalkBack 和减少动效下关键内容可用。

8. 每项能力交付时附实际版本、测试范围及证据；未接通、未验证或受阻项保持明确标识，不用编译通过替代端到端验收。

# 十二 依据与参考

Muyon 代码引用固定提交，不以变化中的分支名称替代证据。竞品样本仅帮助识别组件、状态和宿主边界，本稿不包含第三方反编译代码、专有资源或未经运行验证的功能承诺。

- [Muyon Intelligent UI 规划合同 7aa852a](https://github.com/mightyoung/Muyon/blob/7aa852ab8134545c6312cd71de5c12cd49f66b5b/packages/muyon_module_api/lib/src/ui/planning.dart#L19-L49)

- [Muyon UI 校验合同 7aa852a](https://github.com/mightyoung/Muyon/blob/7aa852ab8134545c6312cd71de5c12cd49f66b5b/packages/muyon_module_api/lib/src/ui/validation.dart#L420-L531)

- [Muyon Android 聊天接线 7aa852a](https://github.com/mightyoung/Muyon/blob/7aa852ab8134545c6312cd71de5c12cd49f66b5b/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat/ChatScreen.kt)

- [Muyon 统一 UI 规范 400e206](https://github.com/mightyoung/Muyon/blob/400e206135690c284c8402521e3135cfb7bfaee8/docs/design/2026-10-22/ui-v1.0/Muyon-%E7%BB%9F%E4%B8%80UI%E8%A7%84%E8%8C%83%E4%B8%8E%E8%A6%86%E7%9B%96-v1.0.md)

- [Backstage 服务架构](https://backstage.io/docs/backend-system/architecture/services/)：参考服务引用与依赖注入边界。

- [VS Code Extension Host](https://code.visualstudio.com/api/advanced-topics/extension-host)：参考宿主与扩展运行环境分离。

- [Android 数据层](https://developer.android.com/topic/architecture/data-layer)：参考数据所有权、仓库与生命周期边界。

- [Electron Context Isolation](https://www.electronjs.org/docs/latest/tutorial/context-isolation)：参考受限桥接，不向渲染层直接开放宿主能力。

- [UniFFI Futures](https://mozilla.github.io/uniffi-rs/latest/futures.html)：参考跨语言异步与取消边界，不将调用端取消等同于底层任务已停止。
