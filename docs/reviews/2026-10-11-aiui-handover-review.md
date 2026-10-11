# AIUI 修复交接点独立复审（CR-12，ChatGPT）

对象：`task/pr42-sn2-sn3-repair-20261011` @ `b6e185611a81853c99548d4528cd91cc8be36172`，对比 develop `e7af6ab`，旧 PR42 对照 `c7bbc94`。云端只读静态审查，未运行测试。原稿由用户转交，leader A 整理入库，代码位置以原稿为准（链接均固定到 b6e1856）。

**结论：需修改。** 5 项 Important、1 项 Minor；无已证实 Critical；未发现删减旧负例或放宽业务断言来变绿。

| 编号 | 级别 | 问题 | 位置 | 处理 |
|---|---|---|---|---|
| I1 | Important | `PersonalAgent.cancel()` 先 `await uiCancellation`；UI 子请求清理或 `ui_stream_diagnostics` 写入抛错时，原任务取消逻辑不执行 → 呈现已撤、原任务未取消 | `personal_agent.dart:655-683`、`ui_planning.dart:125-149` | SN-4（grok-build） |
| I2 | Important | 真实询价 source 在任务 cancelled 时返回 null；Harness 先处理 source-null 删 `_latest/_streamProgress` 再查取消终态；`ui_stream_task_view.dart:85-112` 读到 null 也拒绝展示 | `inquiry_ui_planning_source.dart:19-41`、`ui_planning.dart:191-210` | SN-4（原范围，须贯通 source、Harness、renderer） |
| I3 | Important | 事实仍可读、仅允许动作收窄时，最终 source 复核失败会删 `_requestIdentities/_activeRequests`，fallback 不再保存，视图要求 current 请求 → 整块只读退路消失；`ui_planning.dart:420-427` 的 fallback 也丢最后流式预览 | `ui_planning.dart:245-295`（279-287）、`ui_stream_task_view.dart:163-184` | SN-4 |
| I4 | Important | `UiWorkspaceController.adoptExtracted()` 与 `surface.adoptExtracted()` 只看普通 `readOnly`，不看实时 `readOnlyProbe`；新身份已建立、仓库通知未到时旧「采用提取值」回调可删人工覆盖并进 `flush()`；`resolveDraft()` 恢复/丢弃同样不查宿主呈现身份 | `muyon_ui/.../workspace.dart:325-379`、`surface.dart:319-326`、`conversation_workspace_pane.dart:388-394`、`state.dart:391-398` | SN-5（Sonnet） |
| I5 | Important | `_carry()` 恢复时复制旧 `hostUiPlanningContext` 系统消息但不复制 `uiPlanningContext` 标记，也不传 `uiPlanningAvailable`；`_withoutUiPlanning()` 因 prior 为 null 删不掉 → 恢复后提示邀请调用目录里已没有的 `assistant.plan_ui`，并带旧快照引用（JSON/native 都受影响） | `agent_resume.dart:353-376`、`agent_model_turn.dart:260-310`、`personal_agent.dart:713-717` | SN-5 |
| M1 | Minor | 自定义 `onEvent` 包装缺标准 router 的 cancelled/interrupted 终态检查；默认入口未接自定义 sink | `dynamic_workspace.dart:175-194` 对照 `ui_planning_events.dart:48-54,82-90` | SN-5 |

## 其他核验
- GB6 closing-during-prepare：单任务先序已恢复（`personal_agent.dart:737-775`，仓库拒绝覆盖终态）；逐任务 `for/await` 在 develop 已存在，不算新增回归。
- OC-11 与污染确认：未放宽；标准业务路由在参数映射前后都拒绝 unknown。
- 旧测试迁移：HK-2 textOnly 为已声明的语义迁移（非逐字保留）；aiui6_stream_production 负例保留，after-end 拆出符合合同；external-content 夹具补 automatic 实际影响四个共用场景；设置失败例只把 tap 放进 real async zone；六个审批 widget 例只改 import。均未削弱。
- 候选 CI 38120486232 审查时仍 in_progress，不能记作通过；差异未改 CI、`scripts/ci.sh` 或门禁。

放行条件：I1–I5 修完并有回归测试，新组合 SHA 终态 CI 通过。只关 SN-4 不足以放行。
