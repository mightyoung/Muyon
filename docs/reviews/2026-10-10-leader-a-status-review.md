# leader A 开发情况审查（2026-10-10）

范围：交接点 `01404ae` → develop `c265eb1`（246 个提交）。只读审查：读 diff、抽查关键代码、核对 PR 与 CI 状态；未运行测试。合入仍由 Leader B（唯一 integrator）负责。

## 结论

工程纪律好，交接遗留基本处理完；但用户可见的「对话中心」体验尚未打开，文档负担已经影响看清现状。**无代码阻断**，下列问题均为后续安排。

## 进展核对

| 项 | 状态 |
|---|---|
| 规模 | 产品代码 +11.5k 行，测试 +16.2k 行，文档 +11.6k 行；develop 最近 8 次 CI 全部成功 |
| 交接 A 节（AIUI-1、AIUI-2、GROK-7） | 已集成；REG-3a 已合 |
| REG-4c（PR31） | 已合。抽查 `apps/muyon/lib/platform/inquiry_record_tools.dart`：`ToolEffect.write`、仅 `selectedObjects` 范围、`expected_version` 校验、`operation_id` 回执绑定参数与范围（换参重放拒绝）、报价价格字段不开放、结果越界拒绝。未发现问题 |
| `cc05fa3` 补审 | 已完成（`docs/tasks/AGENT-DISPATCH-VERIFY-1.md`、`docs/reviews/2026-10-09-agent-dispatch-safety-verification.md`） |
| PR16 manual hold 身份 P1 | 已由 PR20 修复合入（`5e7c303`） |
| Mac 截图失败 | 根因收窄到 2026-10-06 升级 macOS 27.0.1 后的字体光栅化（时间证据强，字体平滑开关已排除）；无低风险修复，本机 `verify.sh` 仍红 |
| 质量门禁 | 四包严格 lint 已合；覆盖率基线已冻结（已加载行口径：module_api 94.9%、muyon_ui 94.2%、supplier_core 92.9%、host 86.2%、research 85.0%、inquiry 77.2%；整包分母未知） |

## 问题（按重要程度）

1. **AI 原生界面默认关闭。** `apps/muyon/lib/app/bootstrap.dart:328` 为 `uiPlanningEnabled: false`；用户需手动打开开关并逐条点「规划此回答」。AIUI-9 本体卡片（PR37）、AIUI-8 授权控制中心（PR36）、AIUI-6 只读快照（PR40）仍是草稿 PR。2026-10-09 用户决定的「以对话为中心」目前不可见。
2. **当前状态入口过期。** HANDOVER 指向的 `docs/tasks/CURRENT-STATUS-2026-10-10-v1.md` 固定在 `8debfd2`，仍写 PR18/19/20 未合、修复进行中，与现状不符。`INTEGRATION-2026-10-09.md`（293 行）以 head、CI 编号、组合门禁为主，难以读出「完成了什么、还差什么」。
3. **分支与 PR 堆积。** 远端 163 个分支，130 个已并入 develop，其中 `review/*` 51 个。PR23（覆盖率旧版，CI 失败，已被 coverage-current 取代）与 PR4（设计文档旧分支，内容已保留或被取代）已按用户 2026-10-10 同意关闭。**已合并分支的清理仍需用户另行同意。**
4. **验收账本无 AIUI 验收项**（10-09 交接 D 节遗留）。
5. **真实环境验证未做。** E-1 真实模型基线、R-1 Android 重跑、首字延迟测量均缺；当前证据全部是 CI 离线测试。
6. **文件超限且仍在增长。** `apps/muyon/lib/platform/tool_registry.dart` 1313 行、`foundation_repository.dart` 1209 行，超过 800 行上限。

## 给 Leader B 的建议

1. 写明 AIUI 默认开启的条件和时间，优先于剩余质量任务；先合 AIUI-9/8/6，让对话里直接出现本体卡片。
2. 用一页「已完成 / 进行中 / 阻塞」替换 CURRENT-STATUS，只写结论和链接，HANDOVER 指向它；逐条证据留在集成交接备查。
3. 在验收账本补 AIUI 验收项。
4. 派 engineer 做一次真实模型与 Android 冒烟，同时测首字延迟。
5. 拆分 `tool_registry.dart`、`foundation_repository.dart` 单独成片，在 AIUI-9 合入后做，不与功能 PR 混合。
