# 外部内容与确认路径合入后审计（CR-10，ChatGPT 6 Pro）

基线 develop `13d3539`（PR42 未合，不计其补丁）· 只读 GitHub，构造点检索覆盖 873 个 Dart 文件，未运行测试 · 原稿由用户转交，leader A 整理入库，代码位置以原稿为准。口径：含外部内容时单项写入仍可「仅这一次 / 拒绝」，去掉「更多」、会话级放行、批量「全部允许」；固定页面一次性人工接纳仍是有效确认（`docs/design/v6/frontend-memo.md:15-16`）。

**结论：有缺口；本次所查链路未证实当前 Muyon 宿主可以绕过确认写入。**

| 编号 | 严重度 | 缺口 |
|---|---|---|
| F1 | 中；接真实业务动作前须作为阻断项 | 污染变化不驱动动态卡刷新，旧渲染回调也不因污染变化失效；当前生产写入能力未开放，影响受限 |
| F2 | 中；确认流程可用性 | 受污染批量卡隐藏「全部允许」后，「逐项决定」回调为 `null`，无法逐项继续 |
| F3 | 中（非宿主兼容路径）/ 低（当前宿主入口） | Folio 只记录本轮网页工具使用，缺本地第三方文本与跨轮历史的来源继承；宿主模式另有强制确认 |
| F4 | 低；防御边界 | 已有 clean 任务读到 unknown 或损坏的会话事实时，仍可能返回任务自身的 clean；未证实普通外部输入能形成此组合 |

## 1. 入口是否拿到宿主污染标记
未传探针的控制器均按「含外部内容」（`surface.dart:96-105`，缺探针或抛错为 true；`workspace.dart:51-60,152-165` 透传）。生产 3 处：助手动态工作区 `dynamic_workspace.dart:146-165` 传入 `authorizationFacts.readTask(taskId).requiresConfirmation`；导入审阅 `import_review_projection.dart:171` 与询价清单审阅 `inquiry_list_review.dart:231` 未传（默认 true，当前计划只有编辑 / 查看来源，原生人工提交走固定回调）。UI 内部 4 处（工作区内部透传；恢复草稿临时候选不挂载；`DynamicUiSurface` 兜底两处默认 true）、预览 3 处（模拟回执）、测试 71 处 + 5 个子类实例化点。SN-1 / OC-4 覆盖挂载前的 tainted / unknown / 缺失 / 伪造 false 与默认值；**未覆盖挂载后的污染变化，也没有探针抛异常的独立测试。**

## 2. 任务级还是会话级、是否继承
按任务 ID 查询，合并任务、会话与来源事实；只有显式 clean 才不强制确认；来源身份摘要不含 revision，换版不清污染；`markExternal` 在排队写库前锁存，持久化失败不解除本进程锁存。同会话后续任务、UI 语义 / 规划子任务、动态卡业务子任务（`startTool(previousAttemptId: task.id)`）、重试与 checkpoint 恢复、草稿恢复都继承。独立子对话没有通用父子污染合并，但只建空会话、子摘要回父侧为 `display_only`、子对话强制只读——建议把「父回答进子任务」「子摘要进父模型上下文」视为来源装载点，将来开放时同步合并污染，并加测试锁住当前边界。正常路径未发现 unknown → clean（clean 需宿主证明：绑定有效、无 previousAttemptId、会话无历史 / 记忆 / 经验 / 事实行 / 旧任务）。**F4**：对已有 clean task，`readTask` 只在会话事实为 tainted 时提升；会话为 unknown 或损坏（`_read` 返回 null）仍用 task 自身 clean（`host_authorization_facts.dart:219,247-287`）。修复：区分「会话事实从未存在」与「已存在但 unknown / 损坏」，后者使已有 task 降为 unknown。

## 3. 渲染后 clean → tainted（F1、F2）
F1 三处断点：探针是普通函数无变化订阅（`DynamicUiSurface` 只监听 controller 自身通知）；`UiRenderCapture` 不含污染版本，`dispatchCaptured` 不比较污染或来源集合（`surface.dart:62-73,309-328`）；`canConfirm` / `dispatch` / router 业务路由前都没补这项检查（`surface.dart:381-435`、`ui_planning_events.dart:30-59`）。后果：无其他重建事件时旧批量卡「全部允许」继续显示、外部警告不出现；plan 未变时旧回调不因污染失效。限定：当前生产规划源只允许 `detail/back`、助手打开工作区不传 `businessActions`；即使配了映射，router 起的新任务继承污染，自动执行要求事实为 clean，否则进新的人工确认。修复：宿主污染变化提供通知与可比较版本驱动刷新；渲染捕获绑定任务与污染版本 / 来源快照，陈旧回调在业务路由前拒绝；工作区持久化等待后、创建业务子任务前再查一次；单次确认与拒绝保留。拒绝测试：clean 挂载后仅调真实 `markExternal` → 警告自动出现、「全部允许」消失；保存旧回调、污染后不重建直接调用 → 拒绝且无新 pending / 子任务 / 审批 / handler；已 tainted 再加新来源摘要 → 旧确认失效；探针变 unknown / 缺失 / 抛错不恢复放行；旧业务事件送到执行层不得静默写入。现 `aiui5_render_capture_test.dart:49-110` 靠换 plan revision 使回调失效，不能替代。**注：PR42 已在 capture 中加入 `externalContent` 并对业务动作比较 `capture.externalContent != hasExternalContent`，但无污染变化订阅，F1 须在 PR42 基础上补齐。**
F2：动态适配器给 `BatchConfirmCard` 的 `onIndividual` 固定为 `null`（`surface.dart:904-916`、`confirmation.dart:363-372`），污染时只剩不可用的「逐项决定」文字。修复：接入逐项审阅或降为逐项 `ConfirmCard`。测试：污染批量卡无「全部允许」；点「逐项决定」真能进入单项审阅；确认一项只准备这一项，拒绝其他项无副作用（SN-1 只断言了文字存在）。

## 4. Folio（F3）
宿主模式：附着链 `AppState.attach` 固定 `_isHosted = true`，存储的 bypass 读成 `confirmWrites`；执行器只有 `permission == bypass` 且 `requireApproval` 不要求时才跳过确认，缺确认接口则拒绝；宿主 UI 还拦截 `Section.ask`、Folio 会话任务改走宿主助手；`assistant_permission_hosted_test.dart:106-155` 已断言确认前不写。所以宿主 AskPage 漏读污染事实也不会变回 bypass。非宿主兼容路径：`_send` 每轮把 `externalContent` 置 false，只有 `_ReviewedWebTools.onUsed` 置 true——本地读取的供应商备注等第三方文本不触发；开启「使用近期对话」时上轮网页影响只变成字符串历史，来源状态不传；同轮已读网页后再次联网，`autoApprove` 按开始时 permission 固定。**推测**：第三方文本诱导可能导致非本次意图的写入或外发，未运行真实模型不宣称已实证。本基线可见的非宿主 `AppState` 构造只在测试里，正常生产附着为 hosted。同轮 web → write 的标记时序成立（`onUsed` 在 `_web.execute` 前同步调用）。修复：在 `inquiry_plugin.dart:279-290` → `inquiry_module.dart:21-43` → `AppState.attach` → `ask_page.dart:308` 注入宿主只读污染探针，绑定真实宿主 task / conversation（不能把 Folio `AiJob.id` 当 `PersonalTask.id`），未绑定 / 缺失 / unknown / 读取失败都要求确认，保留 hosted 的 bypass → confirmWrites；非宿主路径持久保存来源状态并在本地第三方数据、跨轮历史、恢复时继承，自动联网每次读当前来源状态。测试：本地备注 → supplier 更新须审阅；上轮 web → 近期对话 → 下轮无 web 直接写仍须确认且重建页面不丢；宿主探针缺失 / 抛错 / unknown / 身份不匹配不恢复放行；污染后第二次联网拒绝前 resolver / transport 调用次数不增加。

## 5. 其他确认入口
导入审阅（动态计划只 `edit/source`，原生「确认导入」经 `commitSelected` 冻结确认）、询价清单审阅（固定 `commit` 校验任务 / 修订 / 字段 / 可见选择）、授权控制中心（只读，无 grant issuer）、组件画廊（需 debug 与显式开关，按钮只 toast）、宿主助手固定确认弹窗（只有本次确认）——**未发现可被模型或外部内容取得免确认、会话级或持久放行的入口**。导入执行在业务写入前先 `markSourceExternal`（`import_coordinator.dart:174-191`），现有测试覆盖确认后编辑、伪造 payload、过期确认。最值得补的组合测试：先打开 clean 动态卡，再经真实人工导入接纳外部内容，旧回答卡必须自动收紧、旧回调不得新增业务任务（把已成立的导入来源标记与 F1 连起来）。
