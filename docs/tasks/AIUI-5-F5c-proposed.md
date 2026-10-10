# AIUI-5 F5c 任务书：共享规划 / 重算 / workspace 集成（proposed / 未采纳）

历史状态：**proposed / 未采纳**（保留）。父任务于2026-10-10技术采纳修订接口方向，范围/新基线见 [leader decision](AIUI-5-leader-contract-decision.md)；未授予本F5c实现授权。前置：F5b 已合入且父任务已另行授权。基线 `cf672164e4f6c3e7beea8029c8be735e33c3bf19`；开工重取 SHA。分支建议 `task/aiui-5-f5c-integration`。依据 [aiui-f5-contract-proposed.md](../design/aiui-f5-contract-proposed.md) §4、§5。

## 1. 范围
原子 S/I/P 发布与重算、workspace 不可读/只读策略、stream 规划 provider、行详情宿主接线 patch。调用 F3a `UiFormulaRegistry.evaluate`（已合入，纯计算），不改它。不含 Dream/foundation、`agent_resume`/`tool_registry`、`supplier_core` LAN；AIUI-4 旧恢复测试只读复跑不拥有。不调用付费模型/部署。

## 2. 文件所有权（F5c 独占）
修改：`muyon_module_api/lib/src/ui/workspace.dart`、`muyon_ui/lib/src/dynamic/workspace.dart`、`apps/muyon/lib/assistant/ui_planning.dart`、`apps/muyon/lib/platform/ui_workspace_store.dart`。
新增：`.../ui/recomputation.dart`（冻结 `UiRecomputePort`、`UiRecomputeInput/Result`、`UiPublishToken`、`UiVersionBatch`、`UiPublishOutcome`）、`apps/muyon/lib/assistant/ui_planning_stream.dart`。
**`apps/muyon/lib/platform/ui_recompute_adapter.dart` 不归 F5c**：唯一 owner = F3b（另一执行者，薄宿主 adapter，创建 token/batch、调用 F3a `evaluate`），消费 F5c 冻结接口；F5c 只提供核心（publish/rebase、workspace）。F4c 拥有端到端屏/导航测试；三方不共享测试文件。首片真实切片为预算行 qty String 小数；`inquiry.set_item_qty` 业务 mapping 缺失→确认 disabled。
**补充接口**：`publish` 为同步 `UiPublishOutcome publish(UiVersionBatch, UiPublishTokenProbe)`；controller/session/mounted identity 不变、draftRevision 不降；workspace 持久 `selections/selectionOverrides/viewSelections`，所有 library-2 checkpoint 用 `schemaVersion: 2`，workspace ≤256KiB 超限保旧 bytes。测试补 `snapshot-race.json`/`restore-overrides.json` 的 round2 case。
对 F5b 文件的最小 patch：**H1** `surface.dart`（`publish`、`recomputing`、session.rebase 保同实例、`canConfirm` 增 `!recomputing`）与 `state.dart` 的受控 `rebase`——F5b 合入后在其上提交，不并行；**H2** `ui_contract.dart` 一行 export，交 F5b owner 应用；**H3** `screens/dynamic_workspace.dart` 最小导航及可信状态重核 `onOpenObject → openReference`，交 AIUI-4 owner 应用。

**严格 publish（design §4.2）**：`batch.plan.revision <= current.plan.revision` → invalid；`surfaceId`、`plan.snapshotRef == snapshot.ref == intent.snapshotRef`、`plan.intentRef == intent.id == current.intent.id`、`catalogVersion` 任一不一致 → invalid。候选 plan 中所有将显示的 computed 实例（含 collection cell 展开）都须以 S8 真实输入重算，未受当前 key 影响的也不得仅重标 `inputVersion`（宿主 adapter 归 F3b；F5c 验收含「两显示实例、只一个依赖 qty」`recomputeAllDisplayed` fixture，第二实例必须真实 evaluate 或整批阻断）。F5b 提供的 capture 机制是 publish 后旧回调 stale 的前提，F5c 的集成测试在 `snapshot-race.json` 的 `staleWidgetCapture` 上复验。

**分层冻结（第 5 项，design §4.1）**：published S8 的 `initialUiState` 保宿主 extracted（qty='2'）；人工 qty='3' 仅经 `currentUiState` 传 F3a `evaluate`，`S8_in` 只表示 ref=S8 的计算输入，不得被人工值覆写、不得写入最终 S8。`rebase`/`restoreWorkspace`/`_capture` 保持 extracted、`userOverrides`、`viewValues` 分层，保 override 标记；`adoptExtracted` 保持「清 override 并递增 draftRevision」，之后重算 20、旧 confirm 失效。验收：2→3→publish 30→checkpoint/SQLite 重开保 extracted2+override3→adopt 回 2、revision 递增、总价 20（`snapshot-race.json`/`restore-overrides.json` 的 `extractedOverrideLayers`）。公式 state 依赖守卫：`UiStringEdit` 且 `view==false`，`view:true` 一律 `formula_view_state_dep`（F5b 宿主构建期检查，`typed-edits.json` `formulaDependency`）。

**H3 最终 admission（design §3.5）**：patch 由 F5c 提供、AIUI-4 owner 应用，沿用 `ui_navigation_anchors.dart:67–81` 既有流程，不新建导航栈。入口冻结 `UiNavigationToken`（surface/plan revision、snapshot ref、scope、host/source/permission generation、object revision/digest）；`await _checkpoint` 返回后、`await openModuleObjectPage` 取得 page/lease 后各用同步 `UiNavigationProbe` 重核；final check 与 `Navigator.push` 之间不得再 await；失败零 push，已取得 lease 则 dispose（`finally` 的 `opened?.dispose()`），未取得不虚报；`mounted/canPresent` 仅附加。测试用 `collection-stable-row.json` 的 `revoked-during-checkpoint-await`（push 0、leaseDispose 0）与 `revoked-during-page-lease-await`（push 0、leaseDispose 1），零 tool。PR18 owner 需同步该契约，本任务不改 PR18。

## 3. 切片
1. 先交 `UiRecomputePort` 接口切片给 F3b；宿主 adapter 由 F3b 实现：候选 plan 全部显示 computed 实例（含 collection cell）都以冻结 `currentUiState` 真实重算，不按被编辑 key 筛掉实例、不重标旧结果；`S8_in` 与 published snapshot 的 `initialUiState` 保宿主 extracted，人工值只经独立 `currentUiState` 传 evaluate；公式状态依赖须 `UiStringEdit` 且 `view == false`。
dispatch 内部 admission 必须检查 `readOnly`、`recomputing`、pending，不能只禁按钮：readOnly 禁状态改变及所有外发/导航；recomputing 禁 business confirm/submit（合法参数编辑仍可令旧批次失效并触发 latest-wins）；同节点 pending 禁新的 confirm/submit 与已在途取消，保既有操作锁/回执结算。拒绝必须零状态变化/零 sink/tool。直接调用 dispatch、旧回调与键盘/语义输入均受同一规则。F5b 先建立 readOnly guard，F5c 在所有权移交后加 recomputing/pending 整合。

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
