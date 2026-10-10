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
