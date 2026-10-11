# GB-1 AI 原生五条不变量 · 对抗性静态审计

日期：2026-10-11 · 执行：工程师 2 号（grokbot）· 分支 `review/gb-1-invariant-audit` · 审查：leader A

## 范围与基线

- 任务书：[GB-1](../tasks/GB-1.md)。视角是找**违反路径**，不重复 [GROK-8 追溯](2026-10-10-aiui-acceptance-trace.md)。
- 代码基线：本分支 tip（与 `origin/develop` 同步时为 `cf75546` 之上的任务派发提交）。只读代码与写本文档；未改业务/测试；未运行 Flutter。
- **[PR42](https://github.com/mightyoung/Muyon/pull/42)**（生产 stream/2、可视化三档、受信确认标记）**不在范围**；下文对「生产流式接线」只记当前 develop 事实，不评 PR42 补丁。
- 任务书写「SN-1 刚修了 `externalContentProbe`」。审计时 `origin/develop` **尚未**包含 SN-1 merge（`2ff1224` 在 `review/leader-a-batch-20261011` / `task/sn-1-dynamic-confirm-external-content`）。不变量 3 对动态确认卡同时写清：**当前 develop** 与 **SN-1 落地后**。

推测处标「推测」；静态看不清处写「未能静态确认」。

---

## 不变量 1

> 界面上的任何数值都来自事实绑定或登记过的公式；模型输出的裸数字不渲染为数据（只能出现在文字里，并标「模型所述」）。

### 反例或疑点

1. **助手文字气泡不加「模型所述」**  
   `apps/muyon/lib/screens/assistant_page.dart:677` 对 `message.content` 直接 `SelectableText`，角色仅标「助手」。模型回答里的裸数字会以普通正文出现，无前缀。  
   **后果**：用户无法区分「模型所述」与宿主事实/公式结果（与方案 §6.1 字面要求不符）。

2. **`Heading` 文本可含模型数字且无标注**  
   `packages/muyon_ui/lib/src/dynamic/catalog.dart:178-181` 允许 `text`/`level` 属性；`component_adapter.dart:119-123` 原样渲染 `Heading`，**不**加「模型所述」。规划/流若输出 `Heading`「合计 12800」，数字出现在标题位而非数据组件。  
   **后果**：视觉上更像权威标题数据，而非模型文字（弱于 Prose 路径）。

3. **生产规划目录无 Metric/Chart，但库目录有**  
   生产 `TaskReceiptUiPlanningSource` 钉 `dynamicUiCatalog`（`ui_planning_source.dart:77`），该目录无 Metric/Chart/CompareTable/Prose。`libraryUiCatalog` / library-2 才有数据组件（`catalog.dart:169-241`）。  
   **疑点**：当前生产路径几乎走不到「数据组件吃裸属性数字」；若日后切库目录而未守住绑定规则，风险面变大。未能静态确认所有未来接线。

4. **事实源是工具回执标量，非模型 JSON 字段**  
   `ui_planning_source.dart:27-46` 只把**已成功**工具回执的标量写入 `facts`（`FactState.unverified`）。这不是「模型裸数字属性」，但是模型可间接促使工具返回数字再被渲染。  
   **推测**：属宿主事实管线，不直接违反字面「模型输出的裸数字」；若产品把 unverified 回执数当作「已核数」，仍有误读风险。

### 现有拦截

- 数据组件模式拒绝数值属性、要求绑定：`catalog.dart:169-171`、`208-241`（Metric/CompareTable/Chart）；未知属性键在校验里 `property_type` 拒绝（`validation.dart:204-207`）。
- 适配器读数只走 `c.value` / collection cell → session.resolve 绑定：`component_adapter.dart:177-185`、`238-254`；Chart 几何仍来自绑定 cell（`:252`）。
- NumberStepper/Slider 的 min/max/step **渲染**取自宿主 `UiNumberEdit`（`component_adapter.dart:294-307`），不是节点 props 里的模型数。
- Prose 强制前缀：`component_adapter.dart:124-130`。
- 流契约 §5：绑定不得带 formula/expr/value 结果字段（契约文档；协议层把非法 bind 当坏行的测试在 `ui_stream_test.dart`）。
- 测试：`ui_components_test.dart`「chart and data components take numbers only from bindings」；`aiui5_revision2_review_test.dart` 断言「模型所述」。

### 结论

**有缺口**（文字通道标注不全：助手气泡、Heading；生产数据组件面较窄故「裸数字进 Metric」当前难触发）。

### 建议的拒绝路径测试

构造含裸数字的助手气泡与 `Heading` props，断言生产渲染必须出现「模型所述」或拒绝将该节点当数据标题；并对 Metric/Chart 再钉一条「props 含 number → validateUiPlan 失败且不渲染数值」。

---

## 不变量 2

> 任何写入或外传都只能经过确认卡或授权执行；点击回答里的按钮本身不等于成功，成功以回执为准。

### 反例或疑点

1. **回答内 ConfirmCard 成功态只认回执（守住）**  
   `surface.dart:874-886`：`BusinessStatus.success` 仅当 `receipt?.status == succeeded`；点击只 `dispatch`（`:858-860`），pending 文案为等待宿主回执（`:903-904`）。

2. **生产打开交互页不传 `businessActions`**  
   `assistant_page.dart:742-757` 构造 `DynamicWorkspace` 时默认 `businessActions = const {}`（`dynamic_workspace.dart:31`）。路由器在缺映射时抛 `business_port_unavailable`（`ui_planning_events.dart:48-51`）。  
   **后果**：回答里确认按钮**无法**真正落到写工具（偏「功能未接线」而非「点了就成功」）。仍是验收缺口：确认卡到执行未闭合。

3. **本体卡提交按钮禁用、无写路径**  
   `ontology_card.dart:32` `FilledButton(onPressed: null)`；快照注释「No submit path」（`ontology_card_snapshot.dart:143`）。无「点了显示成功」路径。

4. **通用写工具仍走工具确认门**  
   `inquiry_record_tools.dart:324+` 注册 `ToolEffect.write`；`UiPlanningEventRouter` 业务路由 `startTool` → `AgentDispatch` 对写操作进 `waitingConfirmation`，再 `confirm` / grant。回执经 `tools.receiptFor` 写入 surface（`ui_planning_events.dart:95-111`，`isSimulated: false`）。  
   **未能静态确认**：所有写工具是否无一例外经过同一门（需对照全量 `ToolEffect.write` 注册表，本次未穷尽）。

5. **Folio 询问页自定义对话框**  
   `assistant_confirmation.dart`：`AlertDialog`「确认新增/允许此次请求」，点确认只 `pop(true)`，成功与否取决于后续 Store/工具结果，对话框本身不显示「已成功」。  
   **疑点**：bypass 权限下可免确认写（`assistant_actions_test.dart` 名暗示），直到外部内容触发 `requireApproval`——这是**授权/权限档**，符合「或授权」，但与「确认卡」字面不同。

6. **导入审阅 / 清单审阅的「确认导入」**  
   `import_review_projection.dart:777`、`inquiry_list_review.dart:504` 等固定页按钮；导入后查回执，未知回执则报错不重放（如 list review `:337`）。不是回答内按钮，但是「点确认」路径；成功依赖回执逻辑，静态看起来对齐。

### 现有拦截

- `canConfirm` 要求 business 路由、operationKey、draftRevision、非 pending/locked 等（`surface.dart:368-392`）。
- `acceptReceipt` 校验 eventId / operationKey / draftRevision（`:532-541`）。
- 传输失败不伪造回执（`:525-527` 注释与行为）。
- Form 提交标为 business（`catalog.dart:171-172` 注释）。
- 助手 `confirm` 要求 digest/过期/范围一致（`personal_agent.dart:453-476`）。

### 结论

**有缺口**（回答内确认→业务执行生产未接线；bypass 免确认属授权路径需产品确认边界）。回执驱动成功态与工具确认门**在已接线路径上大体守住**。

### 建议的拒绝路径测试

在生产助手打开交互页（空 `businessActions`）点确认，断言不出现 success 态且无写工具回执；另测「仅点 ConfirmCard、无 host receipt」绝不变绿。

---

## 不变量 3

> 外部内容进入任务后，回答里不出现放行类按钮（与 Q11、备忘录一致）。

### 反例或疑点

1. **当前 develop：动态 Confirm/Batch 不传 `externalContent`（默认 false）**  
   `surface.dart:871-897`（本基线）构造卡时**无** `externalContent:`。  
   **后果**：污损任务上 `BatchConfirmCard` 仍可画「全部允许」（`confirmation.dart:369-370`）；ConfirmCard 仍可露出持久授权类选项（若 `allowPersistentChoices` 为 true；动态路径已 `allowPersistentChoices: false`，`:873`，写类 persistent 已关，但 outbound/model 的 conversation 级选项仍依赖 `external` 标志）。

2. **SN-1（未合入 develop）意图修复**  
   `d0c6520`：`externalContentProbe` 来自 `HostAuthorizationFacts.readTask(taskId).requiresConfirmation`；无 probe / 抛错 / 非 clean → `true`（fail-closed）；Confirm 与 Batch 都传入。  
   **结论若按任务书「已知已修」**：动态回答卡路径在 SN-1 后**已守住**组件侧；本基线仍有缺口直至合入。

3. **Folio 询问页外部标记仅本轮 web `onUsed`**  
   `ask_page.dart:209-240`、`:308`：`externalContent` 局部变量，仅 `_ReviewedWebTools.onUsed` 置位，再喂 `requireApproval`。  
   **疑点**：任务若已因导入/LAN/`markSourceExternal` 污损（`host_authorization_facts.dart`），询问页**不读** `HostAuthorizationFacts`，bypass 仍可能免确认写，直到本轮真的调了 web。  
   **后果**：外部内容「已进入任务」与 Folio 本地标志不同步 → 放行类行为（bypass 自动写）可能残留。

4. **Folio 确认 UI 不是 `ConfirmCard`，无 `externalContent` 旋钮**  
   `assistant_confirmation.dart` 固定提供「允许此次请求 / 确认*」FilledButton。这是逐次确认，不是「全部允许」，但也不接 Q11 组件语义。

5. **导入审阅 / 清单审阅**  
   固定页「确认导入 / 确认关系 / 确认新建项目并导入」——用途是人工接纳外部导入，**不是回答内放行按钮**。未见图上的 `externalContent` 标志（导入本身即外部）。  
   **未能静态确认**：导入完成后任务污损是否总能传到助手动态确认（依赖 SN-1 probe + 导入路径是否 `markSourceExternal`；导入协调器确有标记：`import_coordinator.dart:183`）。

6. **授权控制中心只读**  
   `assistant_control_page.dart:81` 注释：无签发入口，不画放行按钮。

7. **调试目录示例**  
   `catalog.dart:206` `onAllowAll: () => notify(...)` 为画廊示例，非生产回答。

### 现有拦截

- 组件：`confirmation.dart:157-186`、`:335`、`:369-370`（external 时警告条、藏「全部允许」、藏 persistent / conversation 级选项）。
- Folio：web 使用后 `requireApproval`；hosted 模式读 bypass 当 confirmWrites（`app_state.dart:453-456`）。
- 宿主污损：`requiresConfirmation => taintState != clean`（`host_authorization_facts.dart:45`）；缺任务 → `unknown`（`:265`）→ 需确认。
- SN-1 测试夹具：`apps/muyon/test/sn1_dynamic_confirm_external_test.dart`（在 SN-1 分支）。
- 组件测试：`confirmation_test.dart`「batch and warn banner external-content restrictions」。

### 结论

**有缺口**（本 develop：动态卡未接污损；Folio 询问页外部标志与宿主污损不同源）。SN-1 合入后动态卡缺口可降为「已守住」；Folio 不同源问题仍在。

### 建议的拒绝路径测试

（1）任务已 `tainted`、未调 web：Folio bypass 下尝试写，必须仍要确认；（2）SN-1 合入后：probe 抛错或缺失时 Batch 不得出现「全部允许」。

---

## 不变量 4

> 校验不过的节点不渲染；流中断不产生半截的动作。

### 反例或疑点

1. **流编译器与契约对齐（协议层）**  
   - 单节点失败 → placeholder，父失败则子 `blocked_by_parent`（`stream_compiler.dart:317-326`）。  
   - 预览在非 `complete` 时 **清空 events**（`:344`）→ 动作不可点。  
   - `interrupt()` → `incomplete`，`finalPlan == null`（`:281-283`、`:360`）。  
   - 坏行 → 最终 `malformed_stream` / `rejected`，预览节点清空（`:231-236`、`:337-338`）。

2. **生产助手路径当前不跑 `UiStreamCompiler`**  
   本基线 `UiStreamCompiler` 引用集中在 module_api / muyon_ui **测试**；助手规划走一次性 `validateUiPlan`（`ui_planning.dart:135`、`:241`）。  
   **后果**：中断/半截动作的契约保障在生产**尚未**挂上流编译器（PR42 OOS）。一次性路径下只有整份 ValidatedUiPlan 或退回文字。

3. **候选计划保留坏节点 vs 预览不渲染**  
   契约 §4：坏节点留在 candidate，预览用 lastGood/占位。实现与契约一致。若某宿主误渲染 `candidatePlan` 而非 `previewPlan`，会漏出坏节点——**未能静态确认**所有 UI 调用方（当前生产几乎不消费 stream view）。

4. **导入/清单页自建 UIPlan**  
   `import_review_projection.dart:47+`、`inquiry_list_review.dart:66+` 宿主拼节点后 `validateUiPlan`；失败则无 ValidatedUiPlan。属固定页，非模型流。

### 现有拦截

- `validateUiNode` / `validateUiPlan`（`validation.dart`）；ValidatedUiPlan 私有构造。
- 流上限与坏行终止（`stream_compiler.dart:302-309`）。
- 测试：`ui_stream_test.dart`「node validation isolates placeholders…」「interrupted action remains disabled after complete action line」及 malformed / 上限类。

### 结论

**协议/测试层已守住**；**生产流式接线未能静态确认为已守住**（本基线未接编译器；完整结论依赖 PR42，本次不评）。对「一次性规划」：校验失败不渲染 Validated 树 — **已守住**。

### 建议的拒绝路径测试

在**实际生产入口**（非仅 unit）喂：校验失败节点、断流前已完整 action 行；断言预览无动作可点且无最终 plan（合入流式接线后执行；PR42 范围外可单独立项）。

---

## 不变量 5

> 「只用文字」档下，所有功能都仍然可以通过文字和固定页面完成。

### 反例或疑点

1. **三档设置未实现**  
   无「界面与可视化：自动 / 少用 / 只用文字」设置项。`textOnly` 仅为 `DynamicWorkspace` / `ConversationWorkspacePane` 构造参数（`dynamic_workspace.dart:34`，默认 `false`）；`platform_shell.dart:64` 有 `allowInteractiveWorkspace`（默认 true），不是用户三档。

2. **textOnly 行为**  
   `conversation_workspace_pane.dart:382-394`：只展示文字与原回答提示，隐藏 `UiDraftRecoveryActions`。固定页仍可从「资料」等入口打开（壳层导航仍在）。

3. **目前偏「只能靠动态界面」的能力（静态清单）**  
   | 能力 | 说明 |
   |---|---|
   | 回答内交互页 / 草稿恢复 | 依赖 DynamicWorkspace；textOnly 关掉交互与草稿恢复按钮 |
   | 库目录图表/比价组件 | 仅 library 目录+测试可达；生产规划仍是 `dynamicUiCatalog` |
   | 本体只读卡 | 测试/适配器为主；提交本就不可用，固定 Folio 页仍可编辑 |
   | 确认卡→写工具 | 生产 businessActions 空，本身未闭环 |

   **未能静态确认**「业务功能全集」在关掉动态界面后是否 100% 可经文字工具+固定页完成（需产品对照表）；就代码可见面，**核心台账 CRUD / 导入审阅 / 授权查看 / 设备交换**仍在固定页或助手工具确认门，不唯一依赖动态 UI。

### 现有拦截

- 规划失败退路 `UiDisplayDecision.textOnly`（`ui_planning.dart:65`）。
- textOnly / `!allowInteractive` 禁止交互编辑（`conversation_workspace_pane.dart:115`、`:320`）。

### 结论

**有缺口**（三档与默认策略未落地；无法宣称不变量 5 已验收）。固定页兜底大致仍在。

### 建议的拒绝路径测试

在强制 textOnly（或未来设置「只用文字」）下跑询价新建/改删、导入确认、助手写工具确认；断言无动态页也能完成，且动态入口不可发起写入。

---

## 「有缺口」条目（按严重程度）

1. **不变量 3（高）**：本 develop 动态确认卡未接宿主污损 → 污损任务回答里仍可能出现「全部允许」；Folio 询问页外部标志与 `HostAuthorizationFacts` 不同源，bypass 下可能对已污损任务免确认写。  
2. **不变量 2（高）**：生产回答确认卡未接 `businessActions`，确认→执行未闭合（同时避免了假成功，但是功能与验收缺口）。  
3. **不变量 1（中）**：助手气泡与 Heading 未标「模型所述」；裸数字可出现在非数据组件文字位。  
4. **不变量 5（中）**：可视化三档未实现，不变量无法验收。  
5. **不变量 4（低·范围外依赖）**：流式拒绝路径在测试中成立；生产流编译器未接（PR42 OOS）。一次性校验路径可用。

## 已守住（附条件）

- **不变量 2（已接线子集）**：ConfirmCard 成功态←回执；空 businessActions 不会假成功；本体卡无提交。  
- **不变量 4（协议/单测）**：占位、断流清 events、坏行否决。  
- **不变量 3（组件库）**：`externalContent==true` 时行为正确；缺的是**生产把标志接上**（SN-1）以及 Folio 同源。  
- **不变量 1（数据组件模式）**：Metric/Chart 等拒绝裸数值属性、只绑 fact/computed（在库目录+测试路径）。

