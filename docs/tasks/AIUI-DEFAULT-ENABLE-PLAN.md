# AIUI 默认开启计划（条件目标，尚未执行）

日期：2026-10-10 · 负责人已按用户决定固定：**Codex负责生产编译器/新组件接线、业务卡片与三档持久策略，本机Claude Haiku5.5负责真实模型、Android冒烟和首字延迟**。本文排程尚未执行，未改默认开关、未触发构建/安装/发布。全部时间为北京时间（UTC+8）的**条件目标窗口**；设备、真实模型端点/授权/额度仍待落实，条件不具备时顺延并更新状态页。

## 当前事实

- a68 `apps/muyon/lib/app/bootstrap.dart:323-328` 注册 `TaskReceiptUiPlanningSource`，`uiPlanningEnabled:false`。`agent_context.dart:208-226` 在开关启用时可于保存回答后自动规划；`assistant_page.dart:600-609,726-773` 仍提供手动开关/“规划此回答”/打开交互页/保存草稿入口。
- PR40 `650f51a` 的 `InquiryReadonlySnapshots` 和 `InquirySnapshotCard` 只有定义与测试，没有助手shell生产调用点。PR40合入或默认值改成true，都不能单独让询价事实卡在对话出现。
- `ui_planning_source.dart:15-69` 只从成功任务回执的恰好一个对象读取标为未核验的标量事实；不是PR40的当前已保存snapshot source。`personal_agent.dart:243-245` 配置只改内存；`screens/dynamic_workspace.dart:121-179` 只有打开动态workspace才调用持久化controller；harness最新计划是内存态。
- 当前云端无Flutter/Dart/ADB/Xcode工具链与Android设备；模型端点/凭据环境变量仅查存在性，未发现可用配置（不读取secret）。vivo V2324A是历史设备证据，不代表当前连接/可用。无可复用的本轮安装包证据。
- 已亲查 Actions 产物：[旧UI预览37935776194](https://github.com/mightyoung/Muyon/actions/runs/37935776194) 只有未过期 ui-preview-static-package，源为 `cfba2339a4e504207d039e1604631ff5badac4b0`；[verify37403628056](https://github.com/mightyoung/Muyon/actions/runs/37403628056) 只有日志，a68 CI只有coverage/log。这些都不是当前候选Android安装包，不能代替同SHA烟测；本轮不触发手动package-artifacts。
- 既有第二阶段指标照旧：[HANDOVER §4](HANDOVER-LEADER.md)：只读审批中位数0、写任务1；首字本机 `<1.5s`、远程 `<3s`；新外壳询价North Star需真实模型+真机；并要求授权测试、CI和能力覆盖。卡片可见延迟目前没有已采纳阈值。

## 最新前置顺序（2026-10-10用户更正，未实现）

冻结事实源为 `3a78f3d852a081f4b2c624a5da3847f80158092c`：`ui_planning_source.dart:77` 仍选择 `dynamicUiCatalog`，生产规划仅把完整模型JSON交给批校验，没有 `UiStreamCompiler` / `UiStreamSession` 消费链。新 `library2UiCatalog` 和 adapters 已存在，但动态surface只在明确选择该新目录时使用它们；不能把兼容回答扫描器或旧目录卡片当作新生产流水线。

1. **生产编译器与组件库先接入**：按已采纳[流式契约](../design/aiui-stream-contract.md)接通真实gateway token流（library-2必须配stream/2，不把旧batch JSON改名冒充）、宿主冻结session、流式compiler、library2目录/adapters、无动作预览及最终validated-plan。坏行、旧session、版本/范围失效、中断和超限必须拒绝；最终校验前动作禁用，不删坏行后宣布成功。此项独审通过后，才接对话业务卡片。
2. **三档策略与持久化可并行开发，先于默认开启验收**：「自动」「少用」「只用文字」必须在真实规划和渲染路径产生不同策略，持久保存并启动恢复，不用单一bool开关或只改文案替代。自动档仍受全部校验/授权门槛；只用文字不自动规划或安装动态展示卡，文字与固定页面功能保留；三档仅控制内容呈现偏好，不能改变授权，文字档仍保留可执行的明确确认/拒绝路径；少用策略已由用户明确选择A：仅用户明确请求卡片或图表时显示，普通请求不自动生成；判定来自用户触发的宿主明确请求入口（如“规划此回答”或显式展示请求控件），在本次请求冻结且可测试，模型输出/建议不能自行设置该意图或扩大到其他请求。旧关闭选择及缺失/损坏/null持久值须有保守迁移与重启测试，默认开启仍是后置独立候选。
3. **接业务动作时修外部内容标记**：`dynamic/surface.dart:843–902` 两种确认卡未传 `externalContent`；批量卡默认clean会显示“全部允许”，违反[不变量3](../design/ai-native-ui-redesign-2026-10-09.md#6-不变量验收时逐条测试)。标记必须由宿主authoritative task/conversation污染状态贯穿动态controller/action context、流式/最终卡、真实router子任务和业务授权；未知状态保守拒绝，不由模型自报clean，不仅补告警外观。覆盖拒绝路径、late-taint同步deny、旧callback/恢复卡、无grant消费/无新批准/零业务写，以及合法单次审批回执正例。现有后端继承污染并拒绝自动授权，尚未证明后端绕过，不能把已证UI违例升级为已证授权绕过。
4. **卡片与集成测试在前置后完成同候选合验**：Codex接真实saved snapshot与事实/建议/来源；scope、pin、revision、敏感字段和生命周期检查原样保留。独立本地context不冒称模型成功；不能用no-model成功测试替代真实网络失败，不能以请求前已有卡片充当新请求0ms延迟。指定integration test自动项1～4及7，5/6交Haiku手验；已知非法空selected-scope草稿先修，草稿未编译即未验收。

| 最早条件窗口（北京时间） | 实际分工 / 依赖 | 交付与顺延 |
|---|---|---|
| 10/11 09:00–17:00 | Codex aiui8_settings生产接线；Codex aiui_recovery三档设置并行；强非作者reviewer | 先冻结compiler/library生产链与三档策略执行契约，再完成各自真实宿主测试。外部内容业务动作合同同时补齐；前提未过则顺延，不抢接卡或默认开启。 |
| 10/12 09:00–17:00 | Codex aiui8_settings卡片；Codex aiui9_cards integration-test并行 | 依compiler/library已过独审，接卡并合验三档、外部内容拒绝及自动项1～4/7；所有slice纳入同一新功能候选。source及组合8套CI、非作者review未过即顺延。 |
| 10/13 09:00–12:00 | root唯一integrator；非作者reviewer | 前置齐全后另冻默认开启受测候选，验证启动默认、三档保存/恢复/迁移、文字等价功能；独审和该完整SHA组合CI通过才交用户，不发布或提前安装。 |
| 10/13 13:00–17:00 | **Claude Haiku5.5**；仅用户启动；Codex支持 | 仅取得完整受测SHA、独审、组合CI后，按[固定冒烟任务](https://github.com/mightyoung/Muyon/blob/507011c801b5181956b65e6958e31cfc8030e2aa/docs/tasks/AIUI-SMOKE-ANDROID.md)执行。缺前提或资源则顺延；构建完停等用户明确确认连接，之前不轮询adb、不尝试连接；确认后才安装/测试。无论成败均卸载并实际验证无残留，同时删除含密钥的本机APK。 |
| 10/14 09:00–12:00 | root唯一integrator；非作者reviewer | 同候选适用验收与审查齐全才正常集成默认开启，再跟踪精确publisher到终态。任何门槛未过不集成，给新窗口；不触发Actions打包分发或公开部署。 |

当前旧合同12文件开发草稿与405行integration草稿保留，未提交、未编译通过、无新功能sourceCI。按上述新合同重排后继续，不能用旧bool/context草稿冒称AIUI完成。GROK-8用户已抽查无误，仍待推送后由用户写正式审查；收到前不抢合其成果。GROK-9同样不抢合，接线避其agent_eval.dart工作范围。

## 验收矩阵

在默认开启候选同一SHA下记录证据，不把离线fixture写成真实模型/真机：

1. **真实接线与来源**：shell消费宿主真实snapshot；保存事实和建议分离；source label与对象/修订对应；敏感/未核验值按规则遮盖；本轮只读询价卡的所有业务提交仍禁用。验证selected scope、撤权、pin/revision变化都阻止展示旧数据。
2. **生命周期与退路**：取消、超时、错误/空事实、无模型与离线固定模板；重启恢复已保存卡；三档均需真实策略、保存成功后生效、启动恢复，旧关闭选择重启仍保持文字档。配置须先持久化，不能把当前内存设置冒称可恢复。
3. **授权与不变量3**：外部内容确认标记按上节贯穿真实宿主到业务授权并通过拒绝/late-taint测试；未知污染状态不默认clean。只读事实读取不新增业务确认；写入、外传及未授权远端模型端点保留[ADR-0002](../adr/0002-graded-assistant-authorization.md)门槛；读取授权不得扩大scope。
4. **性能记录**：按E-1同口径记每次首字延迟与中位数并对照既有本机/远程目标。卡片可见定义为“提交后到首个已保存事实卡完整布局可见”，至少5次记录原始单次值和中位数；目标阈值另由验收方案确认，不自行加门槛。
5. **发布证据**：固定源SHA、独立review、全8套CI。14项完整场景逐项登记完成/进行/阻塞；未做项继续未验收，不能声称AIUI-6整任务完成。只读已接线切片按自身边界验收，不以虚构“14项全部通过”作为先决条件。

本页的目标时间不代表预约或设备/额度已落实。Android本机构建/安装/卸载已获上述有条件授权，详见[ADR-0001后续记录](../adr/0001-leadership-and-scope-freeze.md#后续记录)；本轮只完成文档与格式化，不提前冒烟、检测设备或启用默认值。不修改权限/CI门禁，不触发Actions应用打包或部署。

最新用户决定：真实模型与Android冒烟执行者是 **Claude Haiku5.5**，覆盖旧engineer负责人文案。两项延迟（首字、提交到首卡完整布局）各记录至少5次原始值及中位数；首字沿用本机<1.5s、远程<3s，卡片只记录、不新增阈值。任务文件允许报告端点路径的旧说明由用户更严格决定覆盖：证据不含任何端点。当前无已通过独审及组合CI的接线/持久开关/integration test完整候选，未启动Haiku。
