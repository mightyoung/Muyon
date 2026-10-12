# REG-3e-a：科研手工运行两个写工具

执行：Codex。派发：leader A，2026-10-11。集成：Leader B。基线：PR #49 head（`task/reg3f-reg3d-integration-repair-20261011` @ `ee831084`，含 REG-3c-F 与 REG-3d 的事务内固定回执）；分支 `task/reg-3e-manual-runs`。PR #49 合入 develop 后改为基于最新 develop。

## 依据
`docs/reviews/2026-10-11-research-write-contracts.md`（GB-2）第 8、9 节；ADR-0001 2026-10-11 用户决定 (5)「手工运行只能对任务最新修订建立」。两个导出（`export.report`、`export.claim_drafts`）依赖宿主本机导出门面，**不在本任务**，另由 CR-17 设计后再派。

## 范围
1. `research.start_manual_run`（覆盖操作 `research.run.manual_start`）：选中 task，参数带 task 修订；**按用户决定 (5)，只允许任务最新修订**，旧修订拒绝；领域 `WorkbenchStore.startManualRun`（`store.dart:505-539`）；创建后回执 run；描述写明「只建本机手工记录，不执行任何远端命令」。
2. `research.update_manual_run`（`research.run.manual_update`）：选中 run，带 run `contentDigest` 期望值；只允许 `_localManual` run；status ∈ {running, completed, failed, blocked}；领域 `updateManualRun`（`store.dart:541-592`）。
3. 照 PR #49 已修好的链路：声明 → registrar → 一次审批 → 同一事务内核对期望值、`requireCurrent`、`checkBeforeEffect`、写入，并**在事务内固定回执**（不得在事务外 resolve 最新状态）。

## 测试先行（每个工具）
确认后写入有回执；无确认不写；越界 / 跨项目拒绝；期望值不符拒绝；重复操作 ID 不重复执行；`checkBeforeEffect` 抛出零写入；事务内 `requireCurrent` 失败零写入；回执形成前另一写入改了同一 run，回执仍是本次结果。start：旧修订拒绝。update：非手工 run 拒绝、非法 status 拒绝。runs 表变更日志有对应记录。

## 变异（必须做）
删期望值核对；删范围核对；start 去掉「最新修订」检查；把回执改回事务外 resolve。对应测试都必须失败。

## 约束
不改领域逻辑以外的科研行为；不碰两个导出；strict analyze 零 info；research_module 与 `apps/muyon` 全量；不提交 pub get 改的平台文件；不合 develop。

## 回报（固定 6 行）
1. RED 提交哈希与失败第一行　2. 实现提交哈希（远端与本地一致）　3. 改动文件与行数　4. 变异结果　5. analyze 与两包全量（pass/skip/fail）　6. 未做或有疑问
