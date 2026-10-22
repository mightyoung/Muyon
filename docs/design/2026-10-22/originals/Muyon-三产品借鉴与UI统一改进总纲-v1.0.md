# Muyon 三产品借鉴与 UI 统一改进总纲 v1.0

2026-10-22，北京时间。执行位置：云端。性质：证据整合、产品规格与 UI 场景规划，未修改代码、未创建实现任务、未构建 APK、未调用真实模型或竞品接口。本文件与本轮 UI v1.0 设计图配套；图是设计示例，不是当前 APK 截图或功能完成证明。

## 1. 总结：不是拼三个产品，而是形成一个闭环

**Perplexity 借鉴信息与证据链；Muse 借鉴对话中的可操作对象及持久状态；Grokbot 借鉴名称/用途起步的渐进配置方向。** 三者统一为：

问题与资料 → 明确范围 → 实际处理事件 → 回答与可操作组件 → 可核对原文/回执 → 按版本留存的项目成果。

Muyon 应保留自己的核心：本地科研资料、稳定来源身份、权限与费用门控，以及可恢复的业务回执。不重复建立第二套索引、任务台账、审批系统或资料库。不要把未核实竞品行为写成已验证实现，也不要把设计图中的可点击形状等同于真实能力。

最小优先级是现有 PDF 的本地闭环和原生操作卡，不是一次加入连接器、地图、邮件、支付、任意 HTML、动态插件和所有 Bot 自动化。原三项科研工作仍各自保留来源、实验类型与任务边界，本报告不把它们合并成新项目或代为宣布进展。

## 2. 证据、限制与基线

证据分四类：**观察**＝用户截图能直接看见；**静态**＝本次样本的资源/类型/方法；**建议**＝为 Muyon 独立设计；**未知**＝没有足够证据。任何静态结果都不等同于运行通过、服务端正确或账号已开通。

|样本|核实身份与范围|支持的设计线索|仍不支持|
|---|---|---|---|
|Perplexity|2.101.0 / 260665；ai.perplexity.app.android；资源、DEX结构与部分方法、前次核读官方文档|附件阶段、搜索步骤、正文/引用/候选结果分离、可定位来源、项目组织|准确页面布局、排序/引用正确率、当前权益、服务器实现|
|Muse 标记包|11.0.0.8.164 / 1061601403；com.facebook.aura；10张用户截图及DEX定义/方法引用|可操作列表/选择、渲染注册、版本化组件状态、独立审批链、HTML桥存在|截图与包版本一致、服务端幂等、所有表单均来自同一schema、已连接邮件/日程|
|Grok Bot|1.14.1 / 1029；ai.x.grok.bot；Hermes v98 bundle字符串|名称/用途/新Bot/主Bot文案，以及创建、模板、创建后协调相关符号|“根据名字动态生成选项”的完整控制流、模型/服务端推荐机制、运行效果|

三个包均未安装运行，官方签名/发行归属未完成可信对照；包名和标签本身不是认证。Muse 专有代码和资源不能因反编译可读就直接复制进生产。优先复用 Muyon 自有组件与已确认许可证的依赖，独立实现交互思想。

Muyon 固定参考提交：**f4781e16ddf4e542b983fbd77f266a0071148255**，[PR100](https://github.com/mightyoung/Muyon/pull/100)。已有代码核查支持：本地 PDF/项目/快照、OCR/索引来源与页码修订过滤、任务/回执、原请求查询、请求预览和作用域确认。生产费用证明仍有缺口；构建 CI 成功不等于同一候选的设备验收成功。实施时须重新核实际分支，不能用本报告冻结的基线替代最新状态。

现状分类：**复用**＝已有静态路径；**待核差距**＝全链路是否完整未知，不等于完全没有；**明确阻断**＝已有证据指出未闭合，如生产费用证明。以下建议不是已执行任务。

## 3. 三家意见去重后的统一清单

U 编号是统一索引，PX/MU/GB 原编号保留，避免丢失历史与重复派发。

### A. 信息收集与证据

|统一项|来源映射与证据|Muyon 复用、差距及规定|优先级|
|---|---|---|---|
|U01 附件生命周期|PX-01/07；Perplexity静态|复用PDF附件/OCR/索引；补核各入口真实阶段。已选择、已保存、提取中、已提取、索引中、可检索、部分失败必须分开。移除草稿chip不删除源文件。|首批|
|U02 来源范围与草稿|PX-05/07、GB-03；PX静态、GB建议|复用项目过滤；明确本次选定材料与追问继承范围，保留草稿和附件。切换项目不得隐式保留旧私有范围；选择材料不等于同意外发。|首批本地，网络后置|
|U03 主张到原文定位|PX-02/06、MU-02；静态+建议|复用来源ID、页码与修订身份；回答块→证据片段→正确文件版本/PDF页。来源失效不静默改指最新版；原文可定位≠结论被证实。|首批|
|U04 回答与证据分层|PX-04/06、MU-01/02；静态|复用现有搜索结果卡。正文、实际引用、其他检索候选分层；同源转载不计独立支持。来源类型、阅读/代码/实验核验程度和主张支持状态分字段，禁止万能“可信”绿标。|首批结构，详情后续|

### B. 对话操作与状态

|统一项|来源映射与证据|Muyon 复用、差距及规定|优先级|
|---|---|---|---|
|U05 类型化消息块|MU-01/02、PX-04；Muse静态|复用Compose/现有卡片，建立有限renderer registry。只读行、打开来源、填入草稿、明确发送、本地提交、宿主操作分型；未知schema安全降级，不允许payload决定IPC方法。|首批|
|U06 本地表单/选择|MU-03、GB-01/02/06；观察/静态/建议|单选、复选、文本等有限字段；草稿、保存中、保存失败、提交中、锁定独立。重做是新attempt；模型判分标AI评估，不当人工真值。建议选项不自动代替用户选择。|第二批|
|U07 真实过程与停止|PX-03、MU-06；静态+观察|复用持久任务/AgentWorkflowSurface。排队、执行、等待确认、取消中、已取消、部分完成、失败、unknown各有真实事件。停止文本生成、取消任务与回滚是三回事。吉祥物只表现真实状态。|首批语义，第二批视觉|
|U08 原回执与恢复|PX-09、MU-04、GB-05/06；Muyon静态+建议|复用原intent与lookup；双击不重复执行，unknown先查原回执。切会话旧回调不能更新新页面；历史回执不是当前记录状态。预占与实际费用分开。|全批强制|
|U09 轻反馈与专门卡|MU-07/09/10；观察+建议|reaction不产生业务授权。地图先只读、合理视口、许可与来源；邮件/日程/商品示例不意味着权限。HTML仅后置独立隔离评审，不能直连Service或持有密钥。|反馈第二批；其余后置|

### C. Bot 渐进配置

|统一项|来源映射与证据|Muyon 复用、差距及规定|优先级|
|---|---|---|---|
|U10 从名称与用途到配置草稿|GB-01/02/06；名称用途入口静态，其余建议|名称只帮助理解意图，不从名字直接发放权限。渐进展示：名称/用途→建议角色或模板→能力/资料范围→最终摘要。保留手工编辑、返回、跳过可选项与恢复；用户修改不被后续推荐覆盖。|第二批本地草稿|
|U11 创建前可解释复核|GB-03/04/05、MU-05、PX-10；建议+已有安全路径|展示已选能力、资料范围、权限需求、费用边界和仍未配置项。创建Bot不等于启动任务/连接账号/授权工具；重复提交同intent只建一次，结果unknown查创建回执。|第二批；外发后置|

Grokbot 的名称动态推荐究竟来自规则、模板、模型或服务端，目前未知；本轮Hermes v98部分opcode不兼容，未可靠还原完整控制流，useTeammateCompose/TeammateGrid等名称也只作为静态线索。以上渐进流程是 Muyon 设计建议，不冒称反编译已还原其算法。若先使用确定性模板，应清楚标“模板建议”，不假称智能生成。

### D. 项目与报告

|统一项|来源映射与证据|Muyon 复用、差距及规定|优先级|
|---|---|---|---|
|U12 对话对象转长期成果|PX-08、MU-08；静态+建议|复用项目/PDF/快照。会话组件属于message+attempt；报告属于project+artifact+revision。显式保存、保留来源快照与人工修改，新增版本不静默覆写。删除聊天不暗中改变已归档报告。|第二批|

项目页将资料、证据、会话、报告版本分清；不以“收藏成功”替代实际写入回执。Rule2Region、StepTrace、pre-combination-governance 保留各自项目身份、实验记录和授权；开发小试、正式实验、AI预标注、人工真值不得混用。

### E. 权限、费用与治理

|统一项|来源映射与证据|Muyon 复用、差距及规定|优先级|
|---|---|---|---|
|U13 可信确认与费用门控|PX-09/10、MU-05、GB-04；已有路径+建议|复用prepare/confirm、scope/digest/revision、费用证明。目标、接收方、实际外发内容、影响与预算完整可见。修改业务与披露结果分别确认；参数变化旧批准失效。普通选择/reaction不能当审批。|全批强制；网络后置|
|U14 群组协调研究入口|GR专题；用户新增研究方向|分别论证有协调leader和无固定leader，不提前固定一方。人类owner的权限/最终责任与任务协调角色分离；无leader不代表无治理。群组写入、成本、调度、冲突与成果汇总另留设计任务，不能仅画头像就宣称支持。|先研究，不启动实现|

既有两次真实请求为unknown、保留预占¥0.002620、实际费用未知的事实不得被新UI改成失败、成功或零费用；本次不重发，不解除原停止状态。

### F. 视觉与导航

|统一项|来源映射与证据|Muyon 复用、差距及规定|优先级|
|---|---|---|---|
|U15 菜单与会话层级|GB-07、用户附件与明确说明|菜单外框参附件1，内部结构参附件3；顶部主Agent+置顶对话/群组，普通会话在下，绝非项目网格。会话参附件2：顶栏单一身份、右用户短气泡、宽助手回复、底部胶囊输入。|本轮UI|
|U16 柔黑柔白与吉祥物|用户最终指令、MU-06|背景保持柔白/柔黑，不转成蓝白主色或大面积米棕。棕仅耳内/眼睛/小配饰，功能蓝克制。原m图标保留原资产；单一顶部角色/空态角色不盖正文、不重复每条头像、不用卖萌诱导批准。|本轮UI|
|U17 全组件与可访问性|原UI组件矩阵、PX/MU全域|按钮/菜单/对话框/气泡/卡片/表单/来源/任务/确认/反馈共用语义状态、焦点、48dp目标与大字布局。动画尊重减少动态效果，重大错误持久可见。|本轮规范，后续真机验收|

## 4. 最终视觉约束与全 UI 场景覆盖

用户已定的是方向与布局语义，不是批准了所有色号、动效、功能入口或尺寸。建议浅色背景 #F5F5F3、面板 #FAFAF8、主字 #2E2D2B；深色背景 #252523、文字 #E9E8E4。具体token需真实渲染验收，不拿生成图当像素规范。

本轮配套图按以下场景组织；此表是覆盖目标，不在图未完成时冒称已交付：

|场景|必须可见|关键语义|
|---|---|---|
|01 菜单展开|主Agent、置顶单聊/群组、普通会话、搜索/新增/设置、右侧灰化会话|菜单关闭后回到原锚点；无点击穿透；群组能力未实现不假可用|
|02 日常对话与来源|宽回复、短用户气泡、引用展开、胶囊输入|正文优先，引用与候选结果分开，返回原文后不丢阅读位置|
|03 材料与检索过程|附件生命周期、步骤、部分失败、unknown|计数来自事件；不知道总量不造百分比；unknown只查原回执|
|04 可操作组件|普通行/链接/快捷回复、选择、表单、保存状态|编辑不等于发送，提交不等于外部执行，保存失败不丢草稿|
|05 可信确认与回执|目标、范围、外发/费用、允许/拒绝、取消中、结果待核|批准与披露分开；关闭弹层不执行；停止不宣称回滚|
|06 Bot渐进创建|名称用途、模板建议、范围、能力、摘要|配置草稿与正式创建分开；推荐机制不装成已验证Grok算法|
|07 项目与报告版本|材料/证据/报告入口、版本关系、来源快照|预览≠已保存；用户改动保留；AI预标注≠人工真值|
|08 全控件与状态板|主次危险按钮、菜单/弹窗、开关/单选/输入、空态/错误/禁用/焦点|文字+图标表达状态，深浅色覆盖，大字/键盘/读屏另做运行验收|

首批基础组件族：按钮/图标按钮、输入/搜索、选择器、chip、导航抽屉、会话行/Agent/群组卡、用户气泡、助手块、消息菜单、附件条、EvidenceCard、来源详情、TaskSummaryCard、ReceiptCard、TrustedApprovalSheet、标准弹窗/底部菜单、删除确认、toast/snackbar/banner、空态/骨架/离线、项目/报告/PDF卡、表单/快捷回复、反馈组件。

通用状态至少含普通、按压、聚焦、选中、禁用、加载、确定失败、部分完成、unknown；不是所有控件都套同一状态枚举，例如按钮选中不代表任务成功。未配置能力显示明确原因或隐藏，不照图开放Word、相机、网络、插件、邀请或群组执行。示例图不能假作真实数据或APK截图。

## 5. 一份共享数据契约，多个视图

以下是设计语义，实施前映射已有类型，而不是要求另造同名字段。

- **身份层**：schema_version、component_id、message_id、conversation_id、project_id、agent_id、revision。稳定ID与对象归属不可仅从显示文本恢复。
- **来源层**：source_id、source_version/hash、locator/page、excerpt_ref、access_state、metadata、support_status、verification_kind、checked_at/actor。资料发布时间未知留空，不用核查时间冒充。
- **内容层**：kind、payload、引用集合、检索候选集合、artifact_ref。流式引用加入不得使原编号换源。
- **动作层**：action_id、typed_action、target_scope、params_digest、expected_revision、intent_id、permission_requirement、cost_proof_ref。类型白名单local_edit/open_source/compose_message/submit_local/request_host_action；模型只能建议，宿主决定能否执行。
- **持久状态层**：state_revision、values、attempt_id、status、last_intent_id、receipt_ref。乐观显示与已确认写入分离；CAS防旧回调覆盖新值。
- **任务层**：task_id/parent、event_seq、stage、source_refs、result_ref、cancel_state。去重、乱序与终态覆盖由宿主处理。
- **回执/成本层**：operation、scope、committed、occurred_at、result_status、held_cost、actual_cost、currency、lookup_ref。actual_cost未知不是0；历史committed不说明记录如今未变。
- **Bot草稿层**：draft_id/revision、name、purpose、template_ref/version、suggested_values、user_overrides、selected_capabilities、material_scope、permission_plan、budget_plan。建议来源与用户选择分开；后续推荐不得覆盖用户改动。

统一动作状态：草稿→校验→准备完毕→等待确认（如需）→执行中→成功/确定失败/结果未知；取消请求是独立阶段，只有权威结果才能显示已取消。附件提取、自动保存和任务执行各保留自己的阶段，不压成一个“loading”。

核心不变量：同intent重复点击只得同回执；参数/作用域变动使旧确认失效；unknown先lookup；重做产生新attempt；失权/版本不匹配拒绝；本地编辑不外发；展示文本不能产生批准；原始历史和人工更正不被静默覆盖。

## 6. 最小实施批次与依赖（仅建议，未派发）

**门槛0：先对齐候选证据。** 按实际最新SHA核已有接口、当前CI终态和设备验收。PR99设备失败、PR100 HOLD及新候选需复验的问题不能被设计工作跳过。对每一项标“复用/接线/补测/新增”，共享契约只设一个维护者。

**批次A：本地证据闭环。** U01/02本地范围、U03/04/05、U07/08及U13约束。以既有PDF固定样例做到导入→真实处理→本地检索→正文/来源→正确原文页→持久回执。可并行附件视图、来源定位和原生组件适配；先冻结source/task/intent语义，回答卡再接线。无外部模型请求，无新增权限。

**批次B：原生互动与配置。** U06、U10/11本地草稿、U12，U09轻反馈及U15–17统一视觉。Bot创建先查现有持久对象与接口，不能把草稿页当已可运行Agent。审批仅用现有可信链，真实外发仍关闭。

**批次C：生产闭环。** 沿原生产费用证明、模型/搜索/工具和Agent编排任务推进；达到证据、预算和授权门槛才开放相应网络入口。不能以“用户批准UI”推定批准真实收费验收。

**后置研究：** 地图/领域卡、HTML沙箱、群组协调GR专题、可信插件与桌面产品化各按原任务独立评审，不能成为本地首批的捆绑依赖。

合入仍沿原依赖和唯一合入者制度，不改main、不强推、不部署。本次只产出规格与视觉设计，不执行上述工程批次。

## 7. 验收矩阵：图看起来对不等于实现正确

|维度|正向案例|必须保留的反例|证据要求|
|---|---|---|---|
|附件|保存/解析/索引各真实推进|坏页、格式不支持、重启、重复回调|固定样例+持久记录/回执|
|来源|正确文档版本和页码|同名文件、失权、删除、旧版本、伪source ID|原文定位与权限测试|
|证据|引用2条与候选10条分清|同源转载、无支持主张、未知日期|结果契约与UI断言|
|组件|编辑/选择/保存/提交分型|未知schema/action、超长块、脚本/URL伪装|离线负例与宿主拒绝日志|
|持久状态|重开恢复已确认值|CAS冲突、乱序保存、双击、进程退出|数据库/状态迁移测试|
|权限|可信目标/范围/费用预览|换项目、变参数、旧批准、模型伪按钮|批准绑定与零外发反例|
|unknown|查原回执保留费用未知|断连后盲重试、取消当回滚|原intent追踪与无重复副作用|
|Bot|返回保留草稿、摘要再创建|名字隐式授权、推荐覆盖手工值、重复创建|本地创建/恢复/幂等测试|
|报告|显式保存新版本|用户编辑覆盖、来源变更、保存unknown|版本与来源快照校验|
|导航/视觉|焦点/返回锚点/输入安全区|200%字体、长文、键盘、窄屏、遮挡|同候选真机/模拟器截图+TalkBack|
|交付|APK与SHA/报告一致|旧测试复用为新候选通过|完整提交SHA、构建与CI终态、审查记录|

本文件没有声称上述测试已运行。图稿逐张核看仅验证静态排版与语义，不证明对比度、48dp、系统返回、取消或读屏已通过。

## 8. 与原工作清单对齐，避免产生重复工程

原任务1版本/状态索引承载全部新证据；2设备失败诊断、3当前候选离线验收、4独立复审/依赖裁定、5APK交付仍是发布前门槛。任务6费用证明和7真实工具闭环承接U13，而非新建计费系统；任务8Agent编排承接U07观察层并另评GR；任务9可信内置插件复用类型化动作与审批，不扩大动态插件；任务10Electron仅未来复用稳定语义，不因Android设计稿启动桌面工程。

原PX-01–10、MU-01–10全部保留并映射上表；GB-01–07为本轮工作编号，未知项不得转为已核竞品事实。GR是独立研究入口，不算实施完成或批准固定leader。

群组研究暂定索引：GR-01角色与协作模式schema；GR-02确定性调度与容量门控；GR-03 Leader提案与移交；GR-04权限/数据scope/副作用唯一执行；GR-05预算与unknown回执恢复；GR-06分歧与来源汇总；GR-07群组模式UI与状态；GR-08离线正反验收。研究建议先GR-01/02/04/05/08，再GR-03/06/07；保持当前深度1、活跃2、累计8的既有边界，不因新增群组概念扩大额度。完整GR研究建议三种模式共用宿主硬门控，先host_only离线底座，再固定/每任务leader；这是建议顺序，不是替用户决定最终模式。用户要求是先研究、设计并放入任务，不是立即实现。


逐项反向索引（不新增任务）：
- PX-01→U01；PX-02→U03；PX-03→U07；PX-04→U04/U05；PX-05→U02；PX-06→U03/U04；PX-07→U01/U02；PX-08→U12；PX-09→U08/U13；PX-10→U13。
- MU-01→U05；MU-02→U03/U05；MU-03→U06；MU-04→U08；MU-05→U13；MU-06→U07/U16；MU-07→U09；MU-08→U12；MU-09→U09；MU-10→U09。
- GB-01→U10；GB-02→U10；GB-03→U02/U11；GB-04→U11/U13；GB-05→U08/U11；GB-06→U06/U08/U10；GB-07→U15。

## 9. 可复核来源与版本

- [Muyon固定ChatScreen源码](https://github.com/mightyoung/Muyon/blob/f4781e16ddf4e542b983fbd77f266a0071148255/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat/ChatScreen.kt)：原请求/lookup、prepare/tool、业务与披露确认、现有搜索卡和WorkflowSurface。仅静态核读，不代替测试。
- [ResearchIndex](https://github.com/mightyoung/Muyon/blob/f4781e16ddf4e542b983fbd77f266a0071148255/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ml/ResearchIndex.kt)、[Android FFI](https://github.com/mightyoung/Muyon/blob/f4781e16ddf4e542b983fbd77f266a0071148255/crates/muyon-android-ffi/src/lib.rs)、[workflow.rs](https://github.com/mightyoung/Muyon/blob/f4781e16ddf4e542b983fbd77f266a0071148255/crates/muyon-core/src/agent/workflow.rs)。
- [产品CI](https://github.com/mightyoung/Muyon/actions/runs/39547561616)、[PR99失败CI](https://github.com/mightyoung/Muyon/actions/runs/39279706227)：前次核验记录；在实施日重新核，不当永久状态。
- Perplexity [样本](https://drive.google.com/file/d/1oS9T7TS8m4GG6fzvatOQvnBzu40y6PN4/view)，SHA-256：643142eb02102f466c5b8e051e78ae006a5675c969dab56ae9ff1d2fcb3be86f。原报告定位AttachmentState Lj12、SearchResultsStep Lifm、Ask Lrs0、MarkdownCitations Lcvd。
- Perplexity官方补充：[文件](https://www.perplexity.ai/help-center/en/articles/10354807-file-uploads)、[Research](https://www.perplexity.ai/help-center/en/articles/13600190-what-s-new-in-advanced-deep-research)、[Projects](https://www.perplexity.ai/help-center/en/articles/10352961-what-are-projects)。前次拆解已核读，是跨平台描述，不是本轮APK运行结果。
- Muse标记[样本](https://drive.google.com/file/d/1U8RgVCVXvavevoCEeNKs9H2Tf6k1Vjc6/view)，SHA-256：c7e788b5df855912dffbefc4c017f2e621b54aaeef954424f56339bd994fcefa。静态定位ConversationWidgetRenderers.rendererFor、GenericListSelectionDelegate.select、WidgetStateSetRequestJson、WidgetStateSyncSlot、AgentPermissionApprovalsViewModel、WidgetJsBridge；用户截图S01–S10版本未知。
- Grok Bot [样本](https://drive.google.com/file/d/1KbqHQeFiaclV6qx5vC8lq0i9MNDHbCwx/view)，SHA-256：ef03c2e090d38318f5d47887d004c223c8b59ab3b40d7c44f390a15f0ed43aed。当前可复核assets/index.android.bundle Hermes v98字符串NewAgentScreen/deriveAgentName/createAgent/createAgentFromTemplate/reconcileCreatedAgent；不是完整调用链证据。

本总纲整合既有《Perplexity APK信息收集与展示设计分析》《Muyon Perplexity借鉴改进项v1.0》《Muyon Muse对话组件借鉴报告v1.0》与用户最新黑白/菜单/主Agent置顶要求。旧蓝白和大面积暖棕提案保留为历史但不再作为本轮方向。后续更正按版本追加，不静默抹除旧证据。
