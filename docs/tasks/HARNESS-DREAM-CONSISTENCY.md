# Harness Dream consistency 最小补强

授权：用户「如果你们都觉得有对harness的改进意义就执行」。只开发、验证、提交、推送独立分支与草稿 PR，不合入。

基线：远端 develop `3b0adb9e5242dc4a598bf3be71a8252204a9a053`（2026-10-10 fetch）。分支 `task/harness-dream-consistency`；隔离工作树 `/workspace/harness-dream`。该基线无 AGENTS.md 或 .agents/skills。已读 HANDOVER-LEADER、REVIEW、ADR 用户决定、Dream 接口与产品要求。

## 短实施计划

1. 失败测试分别覆盖运行后的删除、停用、范围收窄、新增、经验修改；旧 duplicate 来源被改写；summary/experience 产物写入后状态持久化失败。
2. 接纳时在同一同步数据库事务内重读提案、重验全部修改类提案的证据、写产物与 accepted 状态。
3. 持久记录可回滚的组织状态指纹；存在后续修改即拒绝整库恢复。恢复和运行/提案状态同事务。不做补偿合并。
4. 回归、排队修改、并发重试、故障回滚与数据库重开边界；现有 Linux Actions 全门禁；固定提交 CI 终态与远端 SHA。
5. 窄包交父任务安排真实 Claude 独立复审；本环境不能以 Codex 替代 Claude。

原始日志不入库。静态风险、复现、修复、未测分开报告；单测不是设备验收。

## 已取得的失败证据

测试先行提交 `14595d247d49fece431fe2ae7a258657bbf723bd`；[Actions 38017666447](https://github.com/mightyoung/Muyon/actions/runs/38017666447) 终态 failure。analyze 8/8 通过；host `+1366 ~3 -8`，恰为新增 8 个预期失败：后续 delete/disable/narrow/add/experience 回滚均未拒绝；duplicate 改写后仍被接纳；summary/experience 在 accepted 状态触发 SQLite ABORT 后产物仍然保留。其他 7 个测试套件通过。Laya 因前一步失败而未运行。未出现其他失败。原始日志未入库。

## 实现范围与待审要点

- `DreamService.accept`：在数据库队列事务内重读提案/运行状态，所有修改类提案调用 `_scopeOf`，duplicate 也核对目标都属于证据；写入、accepted 和回滚指纹同事务。
- `FoundationRepository`：原有 SQL 抽取为同步事务体，公开异步 API 复用这些事务体；通知只在提交后发出。无新增迁移。
- `DreamService.revert`：事务内核对最新 done、持久守卫、全量组织状态指纹，恢复/运行/提案状态同事务。用户修改若发生在接纳前，revertBlocked 持续保留，后续接纳不清除。
- `outputs_json` 增加 organizationFingerprint/revertBlocked。旧运行缺少守卫拒绝回滚；不给旧来源恢复特权。界面与接口说明同步改正。
- 接纳新增同事务重读，重复调用保持原 API 的“提案已处理”拒绝语义，只提交一次产物。

待完成：修复提交的完整 Actions 回归终态、真实 Claude 交叉审查。边界测试含并发接纳、排队来源变更、数据库重开、旧运行无守卫、故障触发器回滚。故障注入代表 SQLite 写入失败边界，不是进程强杀/断电或真机验收；这些未测。
