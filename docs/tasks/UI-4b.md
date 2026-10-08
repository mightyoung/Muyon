# UI-4b Harness 共用 UI planning 能力与两种 Provider

## 目标、依赖与边界

依赖 UI-3a/4a；把 UI planning 接入实际 harness，在线大模型知道何时/如何调用。Intelligent UI 是本地小模型理解问答并参考指南规划；Motivation UI 是在线大模型直接参考指南及组件契约生成 UIPlan。Motivation UI 为项目定义，不声称行业术语。两者共用全部运行框架，不预设在线功能较少。先现有大模型/夹具实现，后续小模型插入同一接口，不以训练或双模型选型阻塞。

## 文件与复用

新增 `packages/muyon_module_api/lib/src/ui/planning.dart` 及 `lib/src/ui/guides.dart`（由纯 ui_contract 入口导出）、`apps/muyon/lib/assistant/ui_planning.dart`、`platform/ui_planning_tool.dart`；修改现有 agent_context/agent_model_turn/personal_agent 以及 assistant_page 的收尾呈现钩子。复用 ModelGateway、实际 HostModelAuthorization、消息库和任务记录，不建第二网关。测试新增 `apps/muyon/test/ui_planning_harness_test.dart`、`ui_planning_events_test.dart`，预览同口 fixture Provider。

## 固定接口与在线模型说明

`abstract interface class UiPlanningPort { Future<UiPlanningResult> plan(UiPlanningRequest request); }`。request 包含完整本次 question+answer、实际 conversationMessages（版本/覆盖范围）、task/turn、DataSnapshot、InteractionIntent、currentView(surfaceId/revision)、UiCatalog、实际 allowedActionRefs、mode、可选 guideEntries。不得只送最后一句回答或让模型传入的文字冒充宿主事实；仍受既有上下文预算和外发审查。

公开模型可见能力 `assistant.plan_ui`：输入 schema 只指 snapshotId/expectedSnapshotRevision/surfaceId/expectedSurfaceRevision，完整问答和目录由 host 取真实值。description 明示「规划已有事实展示；不能执行业务或授予权限」。自动回答后规划与模型显式请求均调同一 port；同 task/turn/snapshot+surface+catalog revision/mode 的请求共用在途 Future/结果，避免自动和显式重复一次调用。

结果遵循 UI-3a decision 联合输出。校验→渲染→事件回传闭环：local 留本地；business 走现有 ToolRegistry prepare/确认或真实 grant/invoke/receipt；semantic 回 actual harness 解释或重规划。组件选择/动作目录可见性不是写入授权。Provider 不可用、超时、无效计划保留完整文字和可继续对话，不静默改线上/本地模式或扩大外发。

Guide 只读 `Future<List<UiGuideEntry>> UiGuideSource.lookup(UiGuideQuery query)` 返回软建议；本任务定义最小纯metadata接口和空实现，无指南不阻塞。C4-GUIDE随后交数据稿/检索适配，不另造同名接口；条目元数据按该任务约定。硬约束仍是组件/动作实际能力、事实绑定、Intent 必显项与既有授权。

## 验收与测试

- `auto_and_explicit_share_one_plan`：同一版本自动/显式并发调用，Provider实际调用1，返回相同计划，不吞完整问答。
- `both_modes_share_validator_renderer_and_features`：相同夹具两模式能编辑/比较/导航/来源，逐功能比较；分别记录延迟、联网、成本和任务效果，缺本地模型标未接入不编成绩。
- `planner_failure_keeps_conversation`：超时/无效/缺Provider仍显示完整文字，可下一问。
- `three_event_routes_preserve_authority`：展开/排序不调模型；选组件不写 Store；确认后 actual host Store qty10→12、receipt成功；语义解释调用 harness 一次且新计划版本校验。
- `mode_switch_does_not_expand_outbound`：远端未授权时原 AUTH 门禁生效；指南建议隐藏conflict被 validator 拒。

## 实施顺序

- [ ] 先真实 harness/loopback 测上述失败，完整记录 request 问答/目录/currentView，不只测 fake 调用次数。
- [ ] 实现单一 port、模型可见 schema/说明、host组包及同版本去重；Motivation Provider复用当前授权模型路径。
- [ ] 接共享渲染和三路事件，浏览器端用明确标识的 fixture；云 CI 跑真实宿主动作/回执测试。
- [ ] `flutter test test/ui_planning_harness_test.dart test/ui_planning_events_test.dart`（apps/muyon），云 smoke复验；已有可用授权模型可另跑在线样例，缺凭据标未测真实模型效果，不拖住接口闭环。
- [ ] 小模型可用后仅替换 Provider，重跑同组测试并报告两模式效果；不另起渲染器。
- [ ] 独立审查后交付。关 UI planning 时保留文字/旧页，已成功业务动作不撤销。

## 通用门禁

本任务为待 leader 复核的派发草案，尚未开工；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。
