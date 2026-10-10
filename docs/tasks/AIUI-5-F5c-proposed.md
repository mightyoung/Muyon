# AIUI-5 F5c 任务书：共享规划 / 重算 / workspace 集成（proposed / 未采纳）

状态：**proposed / 未采纳**。前置：F5b 已合入且父任务已另行授权。基线 `cf672164e4f6c3e7beea8029c8be735e33c3bf19`；开工重取 SHA。分支建议 `task/aiui-5-f5c-integration`。依据 [aiui-f5-contract-proposed.md](../design/aiui-f5-contract-proposed.md) §4、§5。

## 1. 范围
原子 S/I/P 发布与重算、workspace 不可读/只读策略、stream 规划 provider、行详情宿主接线 patch。调用 F3a `UiFormulaRegistry.evaluate`（已合入，纯计算），不改它。不含 Dream/foundation、`agent_resume`/`tool_registry`、`supplier_core` LAN；AIUI-4 旧恢复测试只读复跑不拥有。不调用付费模型/部署。

## 2. 文件所有权（F5c 独占）
修改：`muyon_module_api/lib/src/ui/workspace.dart`、`muyon_ui/lib/src/dynamic/workspace.dart`、`apps/muyon/lib/assistant/ui_planning.dart`、`apps/muyon/lib/platform/ui_workspace_store.dart`。
新增：`.../ui/recomputation.dart`（冻结 `UiRecomputePort`、`UiRecomputeInput/Result`、`UiPublishToken`、`UiVersionBatch`、`UiPublishOutcome`）、`apps/muyon/lib/assistant/ui_planning_stream.dart`。
**`apps/muyon/lib/platform/ui_recompute_adapter.dart` 不归 F5c**：唯一 owner = F3b（另一执行者，薄宿主 adapter，创建 token/batch、调用 F3a `evaluate`），消费 F5c 冻结接口；F5c 只提供核心（publish/rebase、workspace）。F4c 拥有端到端屏/导航测试；三方不共享测试文件。首片真实切片为预算行 qty String 小数；`inquiry.set_item_qty` 业务 mapping 缺失→确认 disabled。
**补充接口**：`publish` 为同步 `UiPublishOutcome publish(UiVersionBatch, UiPublishTokenProbe)`；controller/session/mounted identity 不变、draftRevision 不降；workspace 持久 `selections/selectionOverrides/viewSelections`，所有 library-2 checkpoint 用 `schemaVersion: 2`，workspace ≤256KiB 超限保旧 bytes。测试补 `snapshot-race.json`/`restore-overrides.json` 的 round2 case。
对 F5b 文件的最小 patch：**H1** `surface.dart`（`publish`、`recomputing`、session.rebase 保同实例、`canConfirm` 增 `!recomputing`）与 `state.dart` 的受控 `rebase`——F5b 合入后在其上提交，不并行；**H2** `ui_contract.dart` 一行 export，交 F5b owner 应用；**H3** `screens/dynamic_workspace.dart` 最小导航及可信状态重核 `onOpenObject → openReference`，交 AIUI-4 owner 应用。

## 3. 切片
1. 先交 `UiRecomputePort` 接口切片给 F3b；宿主 adapter 由 F3b实现：依赖键 = 含该 uiState 的 `UiFormulaDefinition.slots`；公式状态依赖限 `UiStringEdit`；`S8_in` 全量 `currentUiState`。
2. `publish`：token 复核（snapshot ref、draftRevision、host/source/permission generation、scope）、`validateUiPlan(P12,S8,I8,catalog)`、同步 rebase、状态表（ready/unavailable/invalid/stale）、新 operation key、pending 不重放。
3. workspace：`UiWorkspaceUnreadable`、`open` 捕获→只读+原因、override 不满足当前 spec→只读、`schemaVersion: 2` 与 `selections` 加性字段；不迁移。
4. planning：stream v2 provider 复用既有 harness/gateway/预算，预览零动作，坏流走可信模板；提示由实际 `request.catalog` 序列化。
5. 变异 M3、M4。

## 4. 验收（未运行）
| 文件 | 内容 |
|---|---|
| 新 `packages/muyon_ui/test/ui_recompute_integration_test.dart` | `snapshot-race.json` 全部 case；2→3 得 '30'、`inputVersion==S8`；重标旧 '20' 不发布；`formula_status_publish_policy_clears_prior_success` |
| 新 `packages/muyon_module_api/test/ui_workspace_unreadable_test.dart` | `restore-overrides.json` 的解析层 case |
| 新 `apps/muyon/test/ui_bound_workspace_recovery_test.dart` | 真实临时 SQLite：重开、CAS 冲突、不可读旧 bytes 逐字保留、回执 unknown 零 invoke/零模型 |
| 新 `apps/muyon/test/ui_row_detail_navigation_test.dart` | 重排同 ObjectRef；伪造/未知零导航；router `startTool`/`startUiSemantic` 调用 0 |
| 新 `apps/muyon/test/ui_planning_stream_test.dart` | 预览零动作；中断/坏行/超限回可信模板；自动+显式只一次 provider 调用 |

命令：各包 `flutter analyze --fatal-infos`、对应 `flutter test`、`bash scripts/ci.sh`；`apps/muyon_ui_preview` 的 web 构建按旧任务书 §7。不导出 `MUYON_EVAL_REAL`。

## 5. 变异
M3（`publish` 不复核 token）→ `ui_recompute_integration_test.dart` race 用例；M4（save 覆盖不可读 bytes）→ `ui_bound_workspace_recovery_test.dart`。记录实际失败断言。
