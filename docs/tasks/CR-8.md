# CR-8 对话事实卡接入与保存恢复设计（ChatGPT 6 Pro，线上设计）

执行：ChatGPT 线上 · 只读 GitHub · 结果贴给用户，leader A 入库为 `docs/design/conversation-fact-card-wiring-2026-10-11.md`

## 背景
用户已决定（ADR-0001 末尾 CR-3 决定）：**对话卡的保存与恢复由卡片接线任务负责**。现状（见 [冒烟测试规格](https://github.com/mightyoung/Muyon/blob/develop/docs/design/aiui-smoke-test-spec-2026-10-11.md) 第 5 节）：固定询价本体卡与适配器已有（`apps/muyon/lib/assistant/ontology_cards/`、`inquiry_snapshots/`），但没有接进对话与建议区；[PR42](https://github.com/mightyoung/Muyon/pull/42) 的内联呈现只在内存里（`ui_planning.dart` 的 presentation Map、`ui_stream_task_view.dart`），没接 `HostUiWorkspaceStore`（`apps/muyon/lib/platform/ui_workspace_store.dart`）；失败退路由 SN-3 在补。默认开启计划：[https://github.com/mightyoung/Muyon/blob/develop/docs/tasks/AIUI-DEFAULT-ENABLE-PLAN.md](https://github.com/mightyoung/Muyon/blob/develop/docs/tasks/AIUI-DEFAULT-ENABLE-PLAN.md)。

## 要设计
1. 固定事实卡何时、由谁、以什么身份插进回答（与 PR42 动态卡、SN-3 模板退路的关系；同一回答里三者如何不重复）。
2. 建议区：模型建议从哪里来、如何与事实分开、如何标「尚未写入」。
3. 保存：保存什么（卡片身份、来源 pin、呈现计划、草稿、视图状态）、何时保存、复用 `HostUiWorkspaceStore` 的哪些接口；不保存什么（敏感原值、模型原文）。
4. 恢复：重启后从哪里恢复、恢复时如何重核 scope / pin / revision / 污染、核不过时显示什么；恢复绝不自动执行任何动作或重发模型请求。
5. 持续失效：范围撤销、对象版本变化、模块停用后，已显示的卡如何撤下旧值。
6. 与三档的关系（只用文字不显示卡；少用只认冻结的明确请求）。
7. 拆成任务片与拒绝路径验收；待用户决定的问题与推荐。
只设计，不写实现代码；引用写 `文件:行`。
