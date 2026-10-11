# SN-3 生产流式规划的失败退路（接在 SN-2 之后）

分支：在 PR42（`task/aiui-6-conversation-card-wiring-20261010`）CI 修好并经 leader A 审过之后，从它的最新提交开 `task/sn-3-stream-fallback` · 执行：Claude Sonnet 5.5 · 审查：leader A

## 依据
[CR-1 审查](../reviews/2026-10-11-pr42-design-review.md) 第 1 项：动作门禁成立，但**失败呈现不成立**。[流式契约](../design/aiui-stream-contract.md) §4、§6 要求：
- 最终校验不通过 → 回答退回「文字加宿主模板卡片」，诊断写进执行记录；
- 流在 `end` 前关闭 → 预览保留并标「未完成」，任何动作都不可点，走退路；
- 达到上限 → `limit_exceeded`，走退路；
- `end` 之后的行 → 忽略并记 `after_end`，以第一个 `end` 为准（共享编译器已如此，`stream_ui_planning.dart:41-46` 的 provider 却直接抛错让整次降级——若 SN-2 未顺手修，本任务修）。

现在的失败路径是 provider 抛错 → harness 清掉进度、返回无计划的 `textOnly` → `UiStreamTaskView` 返回 `SizedBox.shrink()`，用户什么也看不到。库里已有 `snapshotFallback(snapshot, intent)`（`packages/muyon_ui/lib/src/dynamic/fallback.dart:4-35`），生产入口没调用。

## 要求
1. 失败时用 `snapshotFallback` 基于**本次宿主快照**生成模板卡片，只读、无业务动作；诊断（`malformed_stream` / `incomplete` / `limit_exceeded` / 校验错误）写进执行记录。
2. 中断时保留最后的预览，明确标「未完成」，所有动作禁用。
3. 不放宽任何门禁：动作只在 `end` + 整份校验通过后安装；外部内容标记、三档策略不变；「只用文字」档下不显示模板卡片（只保留文字），「仅明确要求」档按冻结请求判断。
4. 测试先行，至少覆盖：坏行、缺 `end`、超限、`end` 后多余行、校验失败五种流各自的呈现与执行记录；模板卡片里没有任何可点的业务动作；三档下的显示差异。每条做一次变异（例如失败时改回 `SizedBox.shrink()`），确认测试失败。
5. 跑 `apps/muyon`、`packages/muyon_ui`、`packages/muyon_module_api` 的 analyze 与全量测试。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不导出 `MUYON_EVAL_REAL`。

## 回报
分支与提交哈希；五种失败流的实际呈现；新增测试与变异结果；三个包 analyze 与全量测试数字。
