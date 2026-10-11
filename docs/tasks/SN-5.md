# SN-5：AIUI 交接点 CR-12 修复（I4、I5、M1）

执行：Sonnet（senior engineer）。派发：leader A，2026-10-11。基线：`task/pr42-sn2-sn3-repair-20261011` @ `b6e1856`；分支 `task/sn-5-aiui-handover-fixes`。依据：`docs/reviews/2026-10-11-aiui-handover-review.md`。I1–I3 由 grok-build 在 SN-4 做，本任务不碰 `ui_planning.dart` 的取消 / fallback 段与 `inquiry_ui_planning_source.dart`。

## I4 直接草稿操作绕过实时身份检查
- `packages/muyon_ui/lib/src/dynamic/workspace.dart:325-379` 的 `adoptExtracted()`、`resolveDraft()`（恢复 / 丢弃）及 `surface.dart:319-326` 都要检查宿主实时撤销（`readOnlyProbe`），不只看普通 `readOnly` 字段；区分「恢复流程内部只读」与「宿主已撤销资格」。
- 负例：人工覆盖 12→20；`planUiFromUserControl()` 同步换新身份、新规划等 source、仓库通知未到时调旧「采用提取值」回调 → 内存值、草稿修订、保存值都不变；旧「恢复 / 丢弃」回调同理，不得走到 `store.save()`。
## I5 恢复后旧规划系统提示残留
- `agent_resume.dart:353-376` 的 `_carry()`：按当前宿主条件重建呈现身份和目录，明确移除旧请求的 `hostUiPlanningContext` 系统消息；`personal_agent.dart:713-717` 恢复成功分支冻结新呈现身份。
- JSON、native 各一例：automatic 普通任务首轮真实 read → pause → resume → 候选 ID、工具目录、全部系统消息一致（无 `assistant.plan_ui` 广告或旧快照引用）；保留「不重放已完成工具」检查。
## M1 自定义事件端口终态检查
- `apps/muyon/lib/screens/dynamic_workspace.dart:175-194` 复用标准 router（`ui_planning_events.dart:48-54,82-90`）的 cancelled/interrupted 检查；测试：真实取消后自定义 sink 收到 0 个事件。

## 要求
- 每项先推 RED 测试提交（或本机跑出 RED 并写失败第一行），再修；每项至少一处变异被抓到。
- 不删减、不放宽已有断言；strict analyze 零 info；`apps/muyon`、`muyon_ui`、`muyon_module_api` 全量测试；不提交 pub get 改的 xcconfig/Podfile/analysis_options；不跑真实模型。
- 你本地 PR42 分支上的 5 个提交不要推、不要合进来；需要参考可以对照，但以 b6e1856 为准。

## 回报（固定 6 行）
1. RED 提交哈希与 I4/I5/M1 各自失败第一行
2. 修复提交哈希（远端与本地一致）
3. 改动文件与行数
4. 各项变异结果
5. analyze 与三个包全量测试（pass/skip/fail）
6. 未做或有疑问的地方
