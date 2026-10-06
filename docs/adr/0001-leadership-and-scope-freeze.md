# ADR-0001 领导权移交与第一阶段范围冻结

日期：2026-10-05 · 状态：已采纳（用户决定）

## 背景

此前由 A（原 leader）规划整体工作，通过向 `docs/superpowers/plans/2026-10-04-w1-agent-prompts.md` 追加说明来派发任务。2026-10-05，用户在审阅[深度研究报告](../reviews/2026-10-05-muyon-deep-review-and-optimization.md)后做了三项决定：

- 按报告路线图执行第一阶段（稳定与取证）；
- 由云端 leader 接管整体的规划、派发、审查与合并，范围冻结按 leader 的建议执行；
- 开发任务一律由用户本地的 agent 执行，云端不运行开发任务，以节省线上额度。

## 决定

### 1. 角色

| 角色 | 承担者 | 职责 |
|---|---|---|
| leader | 云端会话 | 拆解与派发任务、审查全部提交、合入 `develop`、维护验收账本 |
| senior engineer | 本地 agent（Opus） | 难度较高的实现任务 |
| engineer | 本地 agent（Sonnet） | 实现、界面、真机取证 |
| junior engineer | 本地 agent（opencode） | 范围明确的小任务 |

### 2. 派发方式

- 每个任务一个分支 `task/<编号>`，任务说明放在该分支的固定位置 `docs/tasks/<编号>.md`。
- 索引是 `develop` 上的 [docs/tasks/README.md](../tasks/README.md)。
- `2026-10-04-w1-agent-prompts.md` 自本 ADR 起冻结，不再追加。已在执行的 B「2.4 原型补齐」和 E「E11 研究对象页」按原说明完成。

### 3. 审查与合并

- 所有提交由 leader 按 [docs/tasks/REVIEW.md](../tasks/REVIEW.md) 审查，审查结论写在 `review/<编号>` 分支上。
- 审查通过后由 leader 合入 `develop`。
- `main` 保持不动，何时更新由用户决定。用户 2026-10-06 决定：第一阶段退出前不更新 `main`，PR #1（`develop` → `main`）与 PR #2（`ci/manual-verify` → `main`）保持开放。

### 4. 范围冻结（至第一阶段退出为止）

**允许：**
- 第一阶段任务（P0-1～P0-4、P0-J1）；
- B 2.4 与 E11 收尾；
- 测试失败、回归与安全缺陷的修复；
- 审查提出的修复。

**不允许：**
- 新功能、新模块；
- 第一阶段不需要的重构；
- 重启 Laya 专门化；
- OCR 原生三端；
- 向量检索或 Dream 扩展；
- 原型搭建能力；
- 文档的大规模重命名或归档（第一阶段之后再做）。

例外需要用户确认。

### 5. 第一阶段退出标准

1. 询价 North Star 链路至少有一个真机平台、一个真实模型的证据记入验收账本。
2. LLM 工具选择基线至少有一个真实模型的数字。
3. 自动门禁可用：GitHub Actions 能运行时由 PR 触发；不能运行时，以本地 `scripts/ci.sh` 作为合并前门禁。
4. B 2.4 与 E11 已合入，或明确搁置。
5. 验收账本按以上证据更新。

## 后果

- 同一时间只有一个规划与合并的入口，验收账本只由 leader 修改。
- 云端不再产生开发用量。本地 agent 的产出必须推送到任务分支，leader 才能审查。
- 冻结期间新需求先记录，第一阶段退出后再排期。

## 后续记录

- 2026-10-06：A 的交接审查通过（[HANDOVER-A-review.md](../tasks/HANDOVER-A-review.md)）。
- 用户确认删除 6 个已合入或没有内容的远端分支：`review/b-ui`、`review/c-modules`、`wip/g3-handoff`、`feat/a-acceptance`、`feat/a-agent`、`feat/a-storage`。云端会话的代理禁止删除远端分支，由用户在本机执行。
- 保留 `feat/c-modules` 与 `feat/d-transfer`，等 Codex、Grok 恢复额度后继续使用；保留 `ci/manual-verify`（PR #2）。
- 2026-10-06：S6（原型对象从助手回答跳回原型页）在第一阶段**明确搁置**。原型对象没有工作区绑定；最小接法需要临时绑定，与「不自造绑定」冲突，另一种做法需要新接口。第一阶段之后排期。见 `review/E11` 上的 `docs/tasks/E11-review.md`。
- 2026-10-06：用户告知上述 6 个远端分支已删除；leader 复查发现仍在远端，尚未删除。
