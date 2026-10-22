# Muyon：Grok Bot 渐进配置静态分析与改进项 v1.0

2026-10-22，北京时间；执行位置：云端。仅静态解包、结构/资源核读与独立设计规格。未安装或运行 APK、未调用包内接口、未读取凭据、未创建 Bot、未修改 Muyon 仓库。

## 1. 结论先行

已找到并解包用户 Drive 中的 Grok Bot 样本，不是拿普通 Grok APK 代替。样本确有新 Bot、主 Bot、命名、用途描述、队友选择和创建协调的客户端资源与业务标识。用户描述的“按名字渐进选择配置”可作为 Muyon 的明确产品需求，但本轮**尚未完整还原名称输入到推荐选项的控制流**，因此不能声称已确认它使用什么模型、提示词、名称分类算法、调用频率、推荐排序或自动授权逻辑。

最适合 Muyon 的借鉴是：先填写少量信息，再展示可修改建议，最后核对技能、资料范围、权限和成本。不要在输入名字时创建 Agent、自动绑定插件或启动付费任务。下面 GB 项均为独立设计建议，不是假称 Grok Bot 已实现的安全能力。

## 2. 样本与证据链

- 来源：[用户 Drive base.apk](https://drive.google.com/file/d/1KbqHQeFiaclV6qx5vC8lq0i9MNDHbCwx/view)。来自 apk 文件夹直接列举；普通关键词/父目录 search 曾返回空，不能据此判断没有文件。
- 应用名：Grok Bot；package：ai.x.grok.bot；versionName：1.14.1；versionCode：1029。
- 大小：61,696,100 bytes；minSdk 28，targetSdk 36。
- APK SHA-256：ef03c2e090d38318f5d47887d004c223c8b59ab3b40d7c44f390a15f0ed43aed。
- 包含 v2/v3 签名结构；提取 v2 证书 SHA-256：f68872ec9f95894ecea37bf8d096d3609abef72765d9350cf10f1c3231863b74。未与官方发行样本独立比对，不等于确认官方签发身份或完整验签通过。
- 5 个 DEX 与 assets/index.android.bundle。主要业务资源在 Hermes bytecode v98，bundle 大小20,448,436 bytes，不是只搜索 DEX 后就认定没有功能。
- 从 Hermes 字符串表解析81,880条字符串；记录稳定 string ID 与函数索引。自编解析器只读取字节，不执行样本。函数级尝试使用公开 Hermes 格式，但部分指令表版本不匹配，因此不把未可靠解码的控制流纳入确认结论。
- app.config 显示 SandMobile/React Native–Expo 相关标识及 enabled OTA updates。APK 静态 bundle 不一定等于用户实际运行时热更新版本；未请求更新服务器。

### 可定位的静态证据

A. 简体中文语言资源，Hermes string ID 26015：
- 2DQ7aH：为 Bot 取个名字。
- RFtRvq：Bot 名称；qmM-6N：描述 Bot 的用途。
- nHOJ2T：创建新 Bot；g4mJLN：创建主 Bot。
- YQw0qR / qMO3I7：创建失败文案。
- 6Uau97：跳过；wSsj7I：你主要会处理哪类工作。
语言资源里有“跳过”不证明每一步可跳过，也不证明“工作类型”属于新 Bot 流程而非首次使用引导。

B. 稳定业务标识与函数表：
- NewAgentScreen：函数32371，bytecode offset11302750，size1045。
- useTeammateCompose：函数32266，offset11277873，size507。
- TeammateGrid：函数32270，offset11279401，size1934。
- deriveAgentName：函数24566，offset10206829，size59。
- useCreateTeammateMutation：函数25421，offset10292288，size130。
- createAgentWithRetry：函数28451；reconcileCreatedAgent：函数23740，以及异步函数49052。
- 相关字段：firstRunAnswers、committingName、onChangeName、onCentredChange、onPick、busy、botName、createdAgentId、reportedCreatedBotIds、isAmbiguousCreateFailure。
这些证明对应字段/函数存在，不能单靠命名证明其运行语义或成功恢复。

C. 服务边界线索：
存在 CreateGrokBotTemporalAgent、CreateGrokBotAgentFromTemplate、DiscardGrokBotDraft、SendGrokBotDraft 业务标识及模板来源接口名称。不能把通用消息草稿接口当“新建 Bot 配置草稿持久化”的证明。未核完整请求/响应 schema、后端默认值、幂等策略、重试时机或费用。

### 仍未知

名称输入是仅本地更新、点击后生成、每次输入请求还是静态模板筛选；推荐是否由模型生成；是否有防抖/旧响应隔离；每步顺序和可跳过性；自动默认与手动覆盖策略；关闭/回退/重启是否保存；最终创建是否可能先创建再补配置；技能/权限/预算的绑定时点。需后续匹配 v98 的可靠反汇编或用户提供实际创建流程录屏作交叉核验，不能用菜单截图补造这些事实。

## 3. Muyon 七项稳定改进规格

### GB-01 名称与用途的渐进式本地草稿〔P0〕
先让用户输入名称，再补一句用途，不一开始堆完整表单。名称只是标签，不足以可靠推断权限。空白、过长、重名和特殊字符应明确处理；显示名与内部稳定 agent_id 分离。下一步前仅本地保存草稿，不调用模型、不创建 Agent。

验收：仅输入“论文助手”不会联网；中文/emoji/长名布局不崩；同名 Bot 可区分，内部身份不冲突；离开后可继续草稿。

### GB-02 建议配置与用户选择分离〔P0〕
基于用途提供有限候选角色/描述；每项标“建议”“已选”“已修改”。建议可以不采纳，也可全部手填。字段保存 origin（user/template/model）、revision、用户锁定标记。后续改名不覆盖用户已改字段；重新生成先展示差异。首批可用已审查本地模板，网络模型建议为另行接入路径，不能在生产费用证明阻断时启用。

验收：用户手改用途后旧推荐迟到不回写；改名不会重置已选技能；拒绝建议仍可完成；无推荐/生成失败允许手填。

### GB-03 技能与资料范围显式选择〔P0〕
优先复用 Muyon 已有 supplier-overview/paper-overview 内置技能与项目/附件范围，展示适用输入、输出与当前可用状态。只推荐，不自动装插件、连接账户、拓宽资料权限。不可用技能显示原因，不以灰色按钮假装已具备。

验收：选论文助手不能读取其他项目私有附件；所选技能只有当前允许集合；技能被移除/版本变更时重新确认兼容性。

### GB-04 权限与成本独立核对〔P0〕
配置界面区分本地资料读取、外发、外部写入、模型调用；默认不因名称/角色授予新能力。显示现有授权与待审批项，不把下一步当总授权。费用未知显示未知；现有预占和真实费用分列。推荐预算不是可直接执行的预算上限。

验收：“采购 Bot”名称不能自动开付款；“研究 Bot”不能自动上传资料；费用证明不可用时不发真实调用；修改目标/范围后旧批准失效。

### GB-05 最终摘要、幂等创建与不确定态〔P0〕
最后一屏核对名称、用途、技能、资料范围、权限状态、成本门槛。按钮明确“创建 Bot”，不是“开始任务”。创建用稳定 intent_id、expected_revision、配置摘要hash；重复点击同意图仅一次创建。失败和结果未知分开，unknown 先查原意图结果，不再创建新 Bot。

验收：双击无重复；超时后查询到原 agent_id；无法确认时显示待核而非失败重试；创建成功不自动开始有费用任务。

### GB-06 回退、草稿与版本恢复〔P0〕
草稿关联账户/项目/本地draft_id，revision单调递增；步骤导航不清空已选值。可选步骤可稍后配置，但最终摘要必须显示未配置，不把跳过当默认同意。失权资料或能力变化使相关字段失效并说明原因，不静默保留可执行权限。

验收：进程退出重开恢复用户输入；乱序保存不覆盖新版本；换账户不读旧草稿；部分必填未完成不能创建；撤销/修改保留必要审计记录。

### GB-07 创建结果回到主 Agent 与置顶会话体系〔P1〕
沿用用户已确认菜单：顶部为主 Agent 与置顶对话/群组，普通对话在下方。新建 Bot 只加入其真实所属位置，可显式置顶，不默认挤占主 Agent；替换主 Agent 与创建普通 Bot 分开。

验收：创建成功能定位正确 Bot；同名不串会话；群组与 Bot 类型清楚；取消创建不留下假会话；未置顶的新 Bot 不冒充置顶项。

## 4. 步骤契约与状态图（Muyon 拟议，不是 Grok 反编译结果）

步骤输入：draft_id、revision、account_scope、name、purpose、suggested_fields、selected_fields、skills、data_scope、permission_summary、cost_gate、create_intent_id。

步骤输出：仅合法字段 patch、下一步可用条件、缺失项/失效项，不输出任意可执行脚本或工具名。

状态：EMPTY → NAMED → PURPOSED → CONFIGURED → REVIEW → CREATING → CREATED。
每个编辑态可 BACK / SAVE_DRAFT；可选配置可 SKIP，但留“未配置”。建议生成若启用，单独有 SUGGESTING/FAILED，不阻塞手填。
CREATING 后：明确拒绝 → REVIEW；结果未知 → RECONCILING；查到成功 → CREATED；仍未知保持 RECONCILING。不能由 UNKNOWN 直接重新 CREATE。

独立伪代码：

    onEdit(field, value):
        validateLocal(field, value)
        saveDraftCAS(draft.id, expectedRevision, userPatch(field, value))
        invalidateOnlyDependentSuggestions(field)

    onSuggestionResult(requestRevision, proposal):
        if requestRevision != currentRevision: discardStaleResult()
        else: showDiffOfAllowedFields(proposal)  # 不自动覆盖手改字段

    onCreateConfirmed(reviewHash):
        requireCurrentScopeAndRevision(reviewHash)
        requireOnlyExistingAllowedCapabilities()
        intent = prepareCreationOnce(draft.id, draft.revision)
        result = commitExistingIntent(intent)
        if result.unknown: showLookupOriginalIntent(intent)
        elif result.created: openExactAgent(result.agentId)
        else: preserveDraftAndShowReason(result)

生成建议与创建仅在实现、审查和权限边界成立后接线；伪代码不意味着本次已运行。

## 5. 与现有 Muyon / PX / MU 任务映射

基线为 PR100 f4781e16ddf4e542b983fbd77f266a0071148255；本报告使用已有核查，不重新宣布完整复审。已有 agent 台账、作用域与恢复保护需复用；新 UI 不得另建第二套调度/权限系统。

- GB01/02/06 → MU03本地表单、PX07草稿/PX08版本，原任务1证据索引、3设备验收。
- GB03 → PX05资料范围、MU01类型化组件，原任务7检索/工具闭环、9内置插件合同。
- GB04/05 → MU04回执/MU05确认、PX09未知/PX10外发成本，原任务6费用证明、7真实闭环、8Agent执行。
- GB07 → 已确认菜单UI，与原任务5最新APK交付、3设备验收联动；不是替换业务能力。
- 原任务2 API26失败诊断、4独立审查/依赖合入、10Electron产品化继续独立，不因有新设计就视为完成或被替代。

推荐首批仅落地本地草稿、步骤导航、技能/范围选择与最终摘要的原生 Compose 原型和离线测试。真实模型建议、联网创建或启动任务不得借设计批准顺带开放。

## 6. 复用与验证边界

未确认 Grok Bot 专有业务代码的复用许可证，不复制其代码/文案合集/资产到 Muyon。可借鉴机制、独立定义 Kotlin/Compose ViewModel + Rust/Service 合同；不引入 React Native/Expo 作为 Muyon 新路线。公开 Hermes 格式参考为工具层资料，不授予样本业务代码复用权。

[Hermes 文件格式源码](https://github.com/facebook/hermes/blob/static_h/include/hermes/BCGen/HBC/BytecodeFileFormat.h)；本轮格式说明只用于静态解析，精确 opcode 兼容性仍有限。静态发现不证明运行时可用、后端响应、账户权益或安全防护。

完成程度：样本身份与资源层已核、完整渐进控制流未核、Muiyon设计规格已形成、代码未改、设备未测。实际执行位置：云端。
