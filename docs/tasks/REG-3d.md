# REG-3d 科研剩余写入第二片（排在 REG-3c 之后）

分支：REG-3c 审过并合入后，从最新 develop 开 `task/reg-3d-research-writes` · 执行：grok-build · 审查：leader A（写入路径，会做变异）

## 依据
- [GB-2 科研写入契约调研](../reviews/2026-10-11-research-write-contracts.md)（汇总表 REG-3d 一行，及各操作小节的建议契约）。
- 用户 2026-10-11 决定（ADR-0001 末尾）：7 个问题全部按 GB-2 推荐。
- [GB-3 变更日志覆盖](../reviews/2026-10-11-change-log-coverage.md)（grokbot 进行中；开工前先读，若结论要求先补其它日志，按其结论排序）。
- 做法沿用 REG-3c：照 `research.add_outline` 的声明 → registrar → prepare / 一次审批 / invoke / 回执链路，不另造审批。

## 范围
1. 读：`research.query.notes`、`research.query.bindings`。
2. 写：
   - `research.project.save`：以项目内容摘要作期望值（GB-2 建议），同一事务核对；**同批补 project 的变更日志**（决定 7）。
   - `research.note.set_entry`：note 与 entry 都须在选定范围；**同批补 note 的变更日志**（决定 7）。
   - `research.task.save`：领域层 `saveTask` 增加期望修订号检查（决定 4），按 GB-2 拆成新建 / 修订两种；任务规格只开放字段白名单。
   - `research.binding.confirm`：领域层在目标行不存在或已非待确认时报错（决定 3），再开放。
3. 不做：`binding.insert`（决定 6，保持不开放）；手工运行与两个导出留给 REG-3e。

## 要求
- 测试先行：每个工具至少覆盖确认后写入有回执、无确认不写、越界拒绝、期望值不符拒绝、重复操作 ID 不重复执行；变更日志补丁要有「写入后日志里有对应记录」的测试；领域补丁要有拒绝路径测试。
- 领域改动只限上面两处（`saveTask` 期望修订号、`confirmBinding` 报错），其余不改领域逻辑。
- 自做变异：期望值核对、范围核对、日志写入各删一次，对应测试必须失败。
- `packages/research_module`、`apps/muyon` 的 analyze 与全量测试；跑测试保留代理设置，`NO_PROXY` 加 localhost；不导出 `MUYON_EVAL_REAL`；只格式化改动文件；原始日志不进仓库。

## 回报
分支与提交哈希；开放的工具与各自期望值；领域补丁与日志补丁的位置；新增测试与变异结果；analyze 与全量测试数字。
