# Public services v0.2：真实页面组合与待验收矩阵

本稿配合 [十族变体](component-variants.md)，八个业务页面及 S0 壳组合全部 designStatus=draft，公共组件 codeStatus=absent，integrationStatus=not_connected，acceptanceStatus=NOT_RUN。页面入口“现有”仅说明产品基线源代码有路径；不表示公共 renderer 已接通或设备已测。基线 `fd26dcdabcdac996bc2881e8141cac2b519966fc`；计划 `64900d4a6a46a9ef2919bcf922fb059413b1ce82`；视觉方向 `400e206135690c284c8402521e3135cfb7bfaee8`。用户已否定旧菜单组件外观，全部控件/卡片/菜单/弹窗/气泡按组件文档 W1–W10 重新评审；旧实现只作机制参考。B 暂停旧 UI 候选合入。Shell 只读候选封套 `07aeb5e45fda046446557f5083553ef2c885fc85`，正式 shellFinalSha 待交接。

## 页面入口与组合候选

以下路径均相对 `apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/`。PublicUI 不修改这些文件；原 Shell owner 接线，领域 owner 提供真实快照、版本、来源与原回执。没有实际入口的页面明确 absent，不用独立组件目录充数。S0 为原 Shell 的现有页面组合审阅，PublicUI 仅交设计；P3/P4/P7 与 P8 的新步骤均是 proposed，不增加导航 tab。

| ID / 真实入口现状 | 页面组合（从上到下，按节点槽位读序） | 必须可达的动作与返回 | 接线责任与未接缺口 |
| --- | --- | --- | --- |
| S0 会话壳/菜单/设置：MainActivity → ui/shell/ConversationShell.kt、ConversationHeader、ShellInputDock 现有，设置由原 owner 持有 | 图01菜单品牌/搜索/新增/关闭 → 主Agent+置顶横向区 → 普通会话 → 设置入口；收起后图02居中身份/圆形动作/正文与证据/胶囊输入；更多浮层与设置表单按图08统一 | 当前主Agent选中明确；单聊/群组图标区分；已有icon优先且入库/调用分开核，AgentLibrary陶瓷环与原mascot混用、Manifest图标缺口交原owner；图钉不挤标题；菜单遮罩不穿透；返回保留草稿/锚点；设置权限/预算/unknown 回执保留 | Shell 独占产品文件；旧候选暂停合入；W1–W10 外观重审，公共接入未连，不能把测试宿主作产品验收 |
| P1 聊天正文/资料结果：MainActivity 的 chat → chat/ChatScreen.kt 现有 | Shell 唯一身份 → MessageBlock 原答/独立原文入口 → ResultList 摘要 → SourceCard 引文/版本 → AttachmentCard/TaskProgressCard（有事实才显示）→ ReceiptCard 原请求历史；局部选择可插 ChoiceCard | 查看原答、来源返回原锚点；填草稿只局部编辑；请求动作进入可信确认；unknown 查原意图；停止目标明确 | Shell 接入；公共 renderer absent。保留既有聊天门控与输入；不重排 Shell 当前菜单/设置 |
| P2 文档处理：MainActivity documents → ui/shell/DocumentCapabilitiesScreen.kt 现有；ui/documents/DocumentReaderScreen.kt 组件 present，公共入口仍未接 | 文档身份/精确版本 → AttachmentCard 四阶段 → TaskProgressCard 数量 → 来源/失败单元列表 → SourceCard 精确锚点 → 原任务 ReceiptCard | 来源可用才打开历史版本；失败单元可读；总量未知无百分比；关闭释放订阅；取消仍向原意图请求 | Documents + Shell；Reader Core 生产 FD 安全 gate 未解除。禁止用 URI、路径或新桥补出“可验页面” |
| P3 Skill 配置：当前无统一 Skill 注册/绑定页面，入口 absent；未来经现有配置壳提出入口 | 标识/固定版本摘要 → ChoiceCard Skill 选择 → FormCard 输入/绑定 → DraftArtifactCard 未保存 → 能力与成本说明 → ConfirmationCard 可信 prepared → ReceiptCard；如已运行才显示 Progress | 选择/注册/启用/执行分开；返回保留草稿；未知查询原运行；建议不覆盖 userLocked；无能力不显示可执行 | Skills + Shell；入口/绑定事实/C2/C3 缺失；不把已有 workflow 选择器算公共 Skill 页 |
| P4 Connector 配置：当前无统一 Connector 生命周期页面，入口 absent | 协议/适配器版本 → FormCard 普通配置 → 能力目录只读列表 → 独立授权/连通性/业务状态 → DraftArtifactCard → ConfirmationCard → ReceiptCard | secretRef 不显示为明文；注册不授权；端点/身份变更使旧 prepared 失效；断开不声称远端已撤权；unknown 查原操作 | Connectors + Shell；真实授权/凭据配置禁止；仅以后合成页面验收，不触发 Connector 联网 |
| P5 科研详情：MainActivity research → research/ResearchScreen.kt 项目/材料入口现有，公共详情未接 | 项目/文献版本 → ResultList 被引用/候选分组 → SourceCard 原文 → AttachmentCard 覆盖 → ChoiceCard 纳入候选 → DraftArtifactCard 报告 → ConfirmationCard/ReceiptCard | 打开来源/历史版本；纳入排除为领域动作；保存草稿不提交报告；返回定位/滚动锚点 | Domain Research + Shell；公共来源/业务快照缺口；不复制科研 OCR/索引 |
| P6 询价详情：MainActivity supplier → supplier/SupplierScreen.kt 供应商选择/当前值/历史回执入口现有，公共询价比较详情未接 | 领域对象/版本/币种口径 → ResultList 提取材料 → SourceCard 报价来源 → FormCard/ChoiceCard 草稿 → DraftArtifactCard → ConfirmationCard 变更/披露分开 → ReceiptCard | 编辑只改草稿；预览/批准/查询独立；冲突先比较，原回执不等于当前值；提取结果不认定报价可成交 | Domain Inquiry + Shell；供应商 CRUD 现有入口不算完整公共询价页面 |
| P7 研发提案入口：产品无研发提案页面，入口 absent；候选设计需另审 | 提案身份/固定 commit → MessageBlock 问题 → ResultList 验收项 → SourceCard CI/review 固定 SHA → DraftArtifactCard 提案 → 原动作确认/回执（有可信引用才显示） | 打开固定证据；缺 commit/CI/review 不写通过；普通“继续”不合 PR/发布；未获批方案仅文档 | Domain Development + Shell；B3/B4 设计 gate、入口和事实均缺；U0 不实施研发流程 |
| P8 Bot 渐进配置：MainActivity configuration → ConfigurationPreviewHost → ui/shell/HostSetupScreen.kt 现有；ui/configuration/BotConfigurationScreen.kt 基础 present | 名称 → 用途 → Skill/资料 → 权限/成本 → 确认（步骤为候选）；FormCard/ChoiceCard + DraftArtifactCard；createAgent 的 Confirmation/Receipt 与 startTask 的另一对分开 | 后退保留已编辑内容；user/template/model 来源可读；userLocked 不覆写；稍后不自动创建/启动 | 原 Shell + Bot/Contracts；不覆盖当前配置修复。五步完整布局尚未认可；持久保存、创建/执行不因旧组件存在而开放 |

主要吉祥物由 Shell 在页面层提供；功能页可 Hidden，卡内不重复。Static/Animated 切换只改变装饰。ContextActionBar 只重用本页已验证事件，不额外授权。P1 原答与 P2 文档正文仅在当前读权有效时可回看；scope/read 失效移除受限正文及引文并停止订阅；action 失效保留允许读取的正文并禁领域动作。

## 新外观必须在页面上下文中审阅

S0 必须从真实应用打开菜单，审阅主Agent选中、单聊/群组图标、置顶长名/图钉/横向区域、普通会话、搜索/新增/设置、遮罩与关闭，再返回对话；设置页实际包含表单、权限、预算与未知回执说明。P1 必须同屏审阅居中身份、菜单关闭/展开、短用户气泡、宽助手正文、来源卡、胶囊输入与 unknown 原回执；以400e206图02为方向，不能用空白菜单 fixture 替代。P2 必须显示附件四阶段、部分覆盖、来源和停止；P3/P4/P8 必须显示表单标签、错误、选择、未存草稿、弹窗与返回；P5/P6/P7 必须显示领域快照、版本/证据、草稿及确认/回执的真实层级。每页都要亮/暗、标准/摘要、焦点/禁用/加载/错误的实际组合，用户否定的旧组件形态不默认复用。菜单/弹窗/气泡不归 PublicUI 修改，评审后交对应 owner，不能从两份文档直接宣称全 UI 已改完。

## 七状态逐页场景与预期观察（全部 NOT_RUN）

状态名是展示场景，不冒充可信业务枚举。N 正常、E 空、U 未知、F 失败、O 离线、P 部分、X 过期。每格说明必须验证的行为；所有格的实际结果均为 NOT_RUN，无 synthetic 运行结果可继承。

| 页面 | N 正常 | E 空 | U 未知 | F 失败 | O 离线 | P 部分 | X 过期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S0 | 主身份/置顶/普通会话分层 | 无置顶不造示例会话 | 保留原回执与预算说明 | 设置/导航错误持久显示 | 离线仍可关菜单，不伪造连接 | 不完整目录说明范围 | 失效会话不可静默改指其他身份 |
| P1 | 原答/结果/来源独立 | 无结果不说无资料 | 原 IntentId 查询，无重发 | 留原答和原因 | 快照注明离线/版本 | 只读已验证内容，断流无事件 | 旧来源注明历史；读权失效清文 |
| P2 | 四阶段各自可读 | 无文档不隐式导入 | 阶段/总量未知，无百分比 | 显示失败单元，不换引擎 | 留可读缓存且说明范围 | 明确成功/缺失页与索引覆盖 | 历史版本可辨，原件不可用说明 |
| P3 | Skill 版本/需求可核 | 无 Skill 不自动注册 | 运行未知查原意图 | 留输入与依赖错误 | 已有目录可读，不联网刷新 | 缺依赖阻止运行，保留配置 | 版本/绑定变更使旧确认失效 |
| P4 | 授权/连通/可用性分列 | 无连接不发 consent | 外部效果未知，原查询 | 本地错误不证明未执行 | 不用离线当远端撤销 | 部分目录不扩允许集合 | 身份/端点/代次/目录变化禁旧动作 |
| P5 | 文献/来源/版本精确 | 无文献不启动 OCR | 提取未知不认定可信 | 失败保留材料/草稿 | 当前 scope 下旧快照可读 | 原生文本/OCR 覆盖分别标 | 旧引文不跳新版；删除说明 |
| P6 | 税运币种口径可辨 | 无报价不造零价 | 提交未知查原意图 | 保留手改与错误 | 旧快照不冒充当前报价 | 缺金额/有效期不认定可成交 | 报价/版本过期禁旧确认 |
| P7 | 固定 commit/CI/review 证据 | 无提案不造项目 | CI/审查未知不写通过 | 留提案与失败证据 | 旧证据注明时间/SHA | 仅部分验收不写全绿 | head 变更使旧 CI 不满足新验收 |
| P8 | 建议来源/锁定可见 | 空名称/用途无默认提交 | 创建未知仅查 create 原意图 | 错误留手改/当前步骤 | 保留允许的局部草稿，不造 saved | 缺资料/权限不自动补齐 | 旧建议/确认失效，不覆盖手改 |

## 可访问与布局逐页验收格（全部 NOT_RUN）

每行必须对上一表的 N/E/U/F/O/P/X **分别**验证，不只在正常态抽一张图。320dp × fontScale=2.0 为额外交叉场景；亮/暗分别运行；Hidden/Static/Animated 与 reduceMotion=true/false 分别记版本和现象。以下格目前均 NOT_RUN。

| 页面 | 320dp / 200%（各自及交叉） | TalkBack / 键盘焦点 | 减少动效 / 身份 | 组件代码 | 页面接入 | 实测证据 |
| --- | --- | --- | --- | --- | --- | --- |
| S0 | NOT_RUN：置顶长名不被112dp挤碎；图标显示与48dp热区分开；200%菜单/设置可滚动 | NOT_RUN：主Agent/单聊/群组/置顶/当前状态可读；遮罩不穿透，关闭回原焦点 | NOT_RUN：主角色最多一处，菜单无装饰动效也可用 | 旧壳 present；新外观未实施 | not_connected；旧候选暂停 | NOT_RUN；无产品截图/树/设备 |
| P1 | NOT_RUN：原文/来源/停止可达，输入不遮卡尾 | NOT_RUN：原答→来源→请求→原回执，返回锚点 | NOT_RUN：Shell 最多一个角色，文本阶段保留 | 旧聊天 present；公共 absent | not_connected | NOT_RUN；无截图/树/设备 |
| P2 | NOT_RUN：长文件名/四阶段换行，关闭/取消/来源可达 | NOT_RUN：版本→各阶段→失败单元→原查询 | NOT_RUN：无旋转动画也可读 processed | 旧阅读/附件 present；公共 absent | not_connected，FD gate | NOT_RUN；无截图/树/设备 |
| P3 | NOT_RUN：表单错误/能力/成本完整，按钮纵排 | NOT_RUN：标签/锁定/错误关联，步骤返回聚焦原项 | NOT_RUN：无需角色或进度动画 | 通用表单/公共 Skill absent | not_connected；入口 absent | NOT_RUN；无截图/树/设备 |
| P4 | NOT_RUN：端点/身份/目录说明换行，敏感字段不外泄 | NOT_RUN：三种状态独立朗读，授权动作原因可达 | NOT_RUN：静态状态不等于断连 | 公共 Connector absent | not_connected；入口 absent | NOT_RUN；无截图/树/设备 |
| P5 | NOT_RUN：长论文名/引文/纳入原因不断字隐藏 | NOT_RUN：引用/候选有名称，原文返回旧焦点 | NOT_RUN：功能页允许隐藏角色 | 旧科研/卡片 present；公共 absent | not_connected | NOT_RUN；无截图/树/设备 |
| P6 | NOT_RUN：币种/税运/有效期/错误及批准不截断 | NOT_RUN：本地编辑/披露/修改分开，错误非只颜色 | NOT_RUN：不以动画表达成交 | 旧供应商/卡片 present；公共 absent | not_connected | NOT_RUN；无截图/树/设备 |
| P7 | NOT_RUN：完整 SHA 可读/查看，验收说明可滚动 | NOT_RUN：每证据有版本与结果，不读旧绿为新绿 | NOT_RUN：无装饰仍可读提案 | 公共研发页面 absent | not_connected；入口 absent | NOT_RUN；无截图/树/设备 |
| P8 | NOT_RUN：五步字段/稍后/返回/确认都可达 | NOT_RUN：步骤/建议来源/锁定读出，确认不启动 | NOT_RUN：角色不遮成本/权限/错误 | 旧配置 present；公共 absent | not_connected | NOT_RUN；无截图/树/设备 |

确认、停止和来源在适用场景必须可访问；不适用时说明无可信目标，不能伪造按钮或 default preparedRef。禁用原因必须有可读文本；TalkBack 若跳过禁用按钮，原因仍在正常读序。错误说明非只 toast；焦点不因进度刷新不断跳走。菜单/弹层由 Shell 控制，返回先处理键盘/最上层，再离开，草稿保留规则沿原 owner。

## 证据记录模板与 gate

每次实际验收记录：页面 ID/状态、产品源完整 SHA、Shell 固定 SHA、公共组件/fixture 完整 SHA及摘要、真实应用入口与操作步骤、设备/API/分辨率/宽度/fontScale/主题、TalkBack 版本、reduceMotion/角色模式、断言与实际问题、截图/可访问树路径及 SHA256、读权/动作权前后状态、原回执核对。原始日志在仓库外，报告只写摘要和摘要值。fixture 必须标 synthetic；不需要真实账户、模型或 Connector 授权来验纯页面。

状态更新分别记录 designStatus（draft/reviewed）、codeStatus（absent/present）、integrationStatus（not_connected/connected）、acceptanceStatus（NOT_RUN/PASS/FAIL）。组件 fixture 通过只填组件层，不能填产品页面 PASS；截图不代替 TalkBack 人工核验，编译不代替设备。部分格通过只更新相应格，其余保留 NOT_RUN。

U0 当前：候选文档已提供，具体外观/页面组合尚待用户认可，设计 GREEN pending。U1：C1 SHA/fixture 依赖 pending。U2：C2/C3/U1/具体 U0 审阅与 Shell 交接 pending。U3：U2/真实页面入口/现有 Android 设备与构建输入 pending；不下载工具或绕过 Reader Core gate 来制造通过。
