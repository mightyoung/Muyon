# CR-1 PR42 设计与安全审查（ChatGPT 6 Pro，线上只读）

审查对象：PR #42 @ `c7bbc9497107984e4ef665ca8a2ea9b2568aa721`，对照基线 `6c821d6e4ea642cf60cad64cbe90083d48964231`；依据文档固定在 develop `cf7554648d7dcd61e0136d496f29022ea94edb9a`。仅通过 GitHub 静态阅读，未连接本机、未改代码、未运行测试。「成立」表示所核对源码路径满足要求，不代表动态验收通过。报告由用户转交，leader A 入库，文字按原报告整理，行号均指 PR head。

**总结论：需要改设计。** 第 1 项的完整失败退路不成立；第 2～5 项在当前生产接线范围内成立，未发现已证实、模型可触达的授权绕过；第 6 项只能部分定位。

## 1. 预览、最终动作安装，以及中断／超限／坏行退路 —— 不成立（动作门禁成立，呈现退路没有接上）

已成立：
- 编译器只有收到 `end` 才对完整候选调用 `validateUiPlan`；出现坏行记 `malformed_stream`，零坏行且整份校验通过才 `complete`（`stream_compiler.dart:224-236`）。
- 非完成状态的预览节点没有事件，`finalPlan` 只在 `complete` 时提供；生产预览只有一段状态文字，没有 controller、router 或业务按钮；正式界面要取得 `validated`、流结果并经宿主状态复核才安装 controller/router（`stream_compiler.dart:335-360`、`ui_stream_task_view.dart:58-89`、`115-127`）。
- provider 等模型请求返回并确认 `complete` 与 `finalPlan` 才交付；harness 再整体验证（`stream_ui_planning.dart:73-85`、`ui_planning.dart:286-307`）。

不成立：契约要求校验失败回到「文字加宿主模板卡片」、中断时保留预览并标「未完成」（契约 §4、§6）。当前失败路径是：provider 对缺 `end`、编译拒绝或异常抛错 → harness 清除 `_streamProgress`，返回只有 `textOnly` 决策、没有 validated plan 的 fallback → `UiStreamTaskView` 无 progress 时返回 `SizedBox.shrink()`（`stream_ui_planning.dart:74-85`、`ui_planning.dart:90-97`、`308-315`、`ui_stream_task_view.dart:122-123`）。原回答文字与任务状态卡保留，但状态卡不投影宿主事实，不等于模板退路（`assistant_page.dart:662-711`）。库里已有 `snapshotFallback(snapshot, intent)`（`fallback.dart:4-35`），新生产入口没有调用。

## 2. 宿主元信息、草稿修订与动作路由 —— 成立（限生产流式路径）

- `surfaceId`、`revision` 取宿主 `currentView`（`stream_ui_planning.dart:30-32`）。
- `catalog` 固定 `library2UiCatalog`，由 session 写入 `catalogVersion`（`inquiry_ui_planning_source.dart:55-63`、`stream_protocol.dart:61-68`）。
- `expectedDraftRevision` 仅业务动作从 `snapshot.actionContext.draftRevision` 注入（`stream_compiler.dart:205-218`）。
- 路由取当前 validated plan 的 catalog，业务 `toolId` 与参数映射来自宿主 `businessActions`（`ui_planning_events.dart:40-65`）。
- 解析器按 op 用字段白名单，流里出现 `route`、`expectedDraftRevision` 等字段被拒；validator 再查 intent 允许、业务 operation、输入与草稿修订（`stream_protocol.dart:170-173`、`208-242`，`validation.dart:245-257`、`339-356`）。
- 边界：生产事实源只开放 `detail`、`back`，不能据此推出生产业务写卡已完成。

## 3. 三档呈现与授权分离 —— 成立（目录回归见第 6 项）

- 策略：`automatic` 允许；`few` 只允许本次冻结请求的 `_explicit`；`textOnly` 拒绝。普通聊天与手动工具任务在首次保存前冻结为 `ordinary()`（`ui_presentation_preference.dart:35-41`、`personal_agent.dart:435-443`、`469-476`）。
- 明确请求来自宿主「规划此回答」按钮 → `planUiFromUserControl()` → `explicitControl()`，按请求对象同一性、owner、generation 绑定；模型没有设置 `_explicit` 的入口；保存新偏好使旧策略失效（`assistant_page.dart:723-730`、`personal_agent.dart:129-142`、`ui_presentation_preference.dart:84-105`）。
- 规划入口、流进行中、最终呈现分别复核；模型调用 `assistant.plan_ui` 打不开普通 `few` 或 `textOnly`（`ui_planning.dart:102-114`、`personal_agent.dart:236-253`、`306-308`）。
- 授权与确认未被三档关闭：内部规划任务的「查看并确认」「暂停」「取消」不受档位影响；内部规划模型请求仍经原模型 gate（`assistant_page.dart:538-543`、`771-793`、`agent_model_turn.dart:128-146`）。

## 4. 外部内容标记 —— 成立（现有生产渲染链未见模型可触达的绕过）

- 标记来自 `authorizationFacts.readTask(taskId).requiresConfirmation`；无 probe 或抛错按 `true`；查不到任务为 `unknown`，同样要求确认（`ui_stream_task_view.dart:83-87`、`surface.dart:98-108`、`host_authorization_facts.dart:262-267`）。
- `dispatchCaptured()` 在派发前核对 owner、plan、catalog、surface、revision、节点；业务动作 `capture.externalContent != hasExternalContent` 返回 `stale`；router 创建业务子任务前再拒 `unknown` 并比对捕获值（`surface.dart:312-336`、`ui_planning_events.dart:47-66`）。
- 确认卡传宿主标记；单卡无持久放行，批量卡 external 时不给「全部允许」；业务子任务继承父任务污染；`requiresConfirmation` 时工具授权不提供自动授权（`surface.dart:891-924`、`host_authorization_facts.dart:342-347`、`host_tool_authorization.dart:209-219`）。
- 限定：公开方法 `dispatch(event)` 不要求 capture，但现有 renderer 与 library-2 adapter 都走 `dispatchCaptured()`，未找到流内容直接调用它的路径（`surface.dart:415-449`、`686-690`、`component_adapter.dart:53-54`），不单独判为模型可利用漏洞。

## 5. 已保存询价事实 —— 成立（限当前选择中的一条记录投影）

- 范围：按任务 id 重读，核对与对话 scope 一致，只接受非空、最多五个对象的 `selectedObjects`；引用需非空 revision、digest 且在选择范围内（`inquiry_ui_planning_source.dart:19-42`、`inquiry_readonly_snapshot.dart:38-60`）。
- 版本：同步读实际记录的 `data/version/deleted`，拒缺失或已删除，比对 revision、原始 data 的 SHA-256、项目 id，核验与投影之间无 `await`（`inquiry_ontology_card_adapter.dart:45-63`）。
- 遮盖：`credential` 排除，其余 `sensitivity != none` 替换为「已遮盖」，未核验事实替换为提示文字；只复制投影后的 `field.value`，不带 `suggestion`，不把模型回答当事实（`ontology_card_snapshot.dart:79-84`、`110-134`、`inquiry_ui_planning_source.dart:43-54`）。
- 说明：`FactState.verified` 指「核验到该版本已保存记录的显示投影」，不代表报价内容的现实真实性；没有多记录汇总、比价计算或写入映射；历史 `displayValues` 作为 `initialUiState/currentView` 保留，未经过本体遮盖（`inquiry_ui_planning_source.dart:51-63`）。

## 6. 三组既有失败测试 —— 部分定位

- `assistant_production_policy_model_test`（`readonly-json`、`readonly-native`）：**已确认目录回归**。PR42 在有三档偏好时把 harness `enabled` 无条件设为 `true`（`personal_agent.dart:77-94`）；工具目录仍按 `ctx.uiPlanning?.enabled == true` 暴露 `assistant.plan_ui`（`agent_task_factory.dart:43-65`）；默认 `textOnly` 时 `uiPlanningEnabled` 为 `false`，既有测试据此要求目录不含该工具（`personal_agent.dart:280-282`、测试 `114-123`）。高置信推测：失败原因是实际目录多出 `assistant.plan_ui`。基线 harness 直接用传入值，所以应修产品目录筛选，不是迁移旧断言。
- `assistant_production_policy_order_test`：只知是加载失败，无法判断，不应据此改安全断言。
- `assistant_subconversation_widget_test`：无法判断；推测优先查新增设置控件、任务卡筛选与内联组件对父列表布局的影响（`assistant_page.dart:538-546`、`603-607`、`694-712`）。

## 建议 SN-2 顺手处理
1. 工具目录筛选与有效呈现策略统一（修 `assistant.plan_ui` 暴露），并检查 `few` 普通请求；保留既有安全与目录断言。
2. 第 1 项失败退路缺口交回 leader 纳入交付：保留动作门禁，补失败状态、宿主事实模板与中断「未完成」标记。
3. `end` 之后的行：provider 现在直接抛错让整次降级；契约要求忽略并记 `after_end`，共享编译器已这么做（`stream_ui_planning.dart:41-46`、`stream_compiler.dart:91-98`）。
4. 任务列表可能重复同一任务：前段「过滤内部任务后 `take(8)`」，尾段仍对未过滤的 `tasks.skip(8)` 补带子对话的任务，可能重复并产生相同 `ValueKey`（`assistant_page.dart:538-546`、`694-696`）。条件可由代码确认，但不能写成子对话用例的已确认根因。

## 范围外
- 格式、缺 import、编译与加载错误不作本次结论依据。
- 生产 source 只开放 `detail/back`，内联 router 未提供业务映射；完整写卡、真实模型与 Android 冒烟、默认开启不在本次确认范围。
- 外部标记持久化失败、恢复后的旧 capture／重放、存在匹配持久 grant 时的「不消费」动态验收，PR 自身列为后续，本报告不写成已通过（`AIUI-production-stream-wiring.md:40-41`）。
