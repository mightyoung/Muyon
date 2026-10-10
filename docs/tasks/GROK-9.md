# GROK-9 超限文件拆分方案（只出方案）

分支 `task/grok-9-large-file-split-plan` · 基线 develop `a68ba43` · 执行：grokbot（只做静态核对与写文档；不运行 Flutter，不改代码）· 审查：leader A 抽查 · 给谁用：之后的拆分实现任务（在 AIUI-9 生产接线合入后、单独成片执行，不与功能 PR 混合）

## 背景
仓库约定单文件不超过 800 行。leader A 的[状态审查](../reviews/2026-10-10-leader-a-status-review.md)第 6 条指出以下文件已超限并仍在增长。拆分会碰安全路径（工具注册、授权、调度），所以先出一份逐行有据的方案，再派实现。

## 范围
按行数从大到小：
- `apps/muyon/lib/services/transfer/transfer_service.dart`
- `apps/muyon/lib/platform/tool_registry.dart`
- `apps/muyon/lib/assistant/agent_eval/agent_eval.dart`
- `apps/muyon/lib/platform/foundation_repository.dart`
- `apps/muyon/lib/assistant/agent_dispatch.dart`
- `apps/muyon/lib/screens/assistant_page.dart`
- `apps/muyon/lib/assistant/agent_model_turn.dart`

另外用 `wc -l` 扫一遍 `apps/*/lib` 和 `packages/*/lib`，补上其他超过 800 行的 `.dart` 文件（`.json` 数据文件不算）。

## 只做这些
产出 `docs/reviews/2026-10-10-large-file-split-plan.md`，每个文件一节：
1. **职责分块**：按行号区间列出各块做什么（如「L17-28 数据库表结构」「L133-… 注册与调用」）。
2. **拆分建议**：新文件名、各自包含哪些区间、预计行数；公开 API（类名、方法签名、导入路径）保持不变，如需要用导出（`export`）保持旧导入可用。
3. **耦合点**：被拆开后仍需共享的私有成员（`_` 开头）、`part`/`part of`、扩展方法、顶层常量；给出处理办法（保留在原文件 / 改为库内可见 / 合并到同一新文件）。
4. **安全相关行**：涉及授权、确认、外传账本、取消、事务的行号，标注拆分时**必须原样搬运、不得改逻辑**。
5. **调用方与测试**：`lib/` 内导入该文件的文件列表；直接覆盖它的测试文件列表。
6. **顺序与风险**：建议的拆分顺序（先低风险），每个文件一句风险说明。

末尾汇总表：文件、现行数、拆后最大文件行数、新增文件数、风险等级（低/中/高）。

## 不做
不改代码与已有文档；不运行 Flutter；不提出功能或逻辑改动（发现疑似缺陷单列，附 `文件:行`）；不确定就写「未能静态确认」。

## 回报
分支与提交哈希；文档路径；涉及文件数；汇总表。
