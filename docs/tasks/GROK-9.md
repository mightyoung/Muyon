# GROK-9 超限文件拆分方案与首个低风险拆分

分支 `task/grok-9-large-file-split-plan` · 基线 develop `a68ba43` · 执行：grok-build（本机，可构建、跑测试）· 审查：leader A 抽查 · 给谁用：之后的拆分实现任务。除第二部分的 `agent_eval.dart` 外，其余文件在 AIUI-9 生产接线合入后再单独成片拆，不与功能 PR 混合

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

## 第二部分：拆 `agent_eval.dart`（方案提交后再做）
评测工具不在 AIUI 接线和授权路径上，冲突风险最低，先拿它验证方案的做法。
1. 按方案里这一节拆分，**纯搬运**：不改逻辑、不改公开 API、不改测试断言；需要时用 `export` 保持旧导入路径可用。单独一个提交，提交说明写「纯搬运，无逻辑改动」。
2. 只格式化改动过的文件（`dart format <这些文件>`）。
3. 验证：`apps/muyon` 下 `flutter analyze`（info 也算失败）；跑评测相关测试（`grep -l agent_eval apps/muyon/test` 找到的文件）和 `scripts/ci.sh` 里 host 套件。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；**不导出 `MUYON_EVAL_REAL`**，不调用真实模型。
4. 搬运核对：拆分前后把所有非空、非 import 行排序后比对，差异只能是新增的 `import`/`export`/`part` 行；结果写进方案文档末尾。
5. 原始日志不进仓库。

## 不做
不改其他文件；不提出功能或逻辑改动（发现疑似缺陷单列，附 `文件:行`）；不合并 develop；不确定就写「未能静态确认」。

## 回报
分支与提交哈希（方案、拆分各一个）；文档路径；汇总表；`agent_eval.dart` 拆分后的文件与行数；analyze 与测试结果（通过/失败/跳过数）；搬运核对结论。
