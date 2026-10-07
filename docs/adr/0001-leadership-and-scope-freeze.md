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
- 2026-10-06：接任 leader（本机会话）在用户确认后删除了上述 6 个远端分支，`git ls-remote` 复查均已不存在。删除前核对：`review/b-ui`、`review/c-modules` 各只多一个合并提交，两个父提交都已在 `develop` 中，没有独有内容。
- 2026-10-06：用户决定第一阶段**不安装 Xcode**，macOS 设备集成测试写「未验证」；退出标准第 1 项的真机证据以 Android（vivo V2324A）为准。
- 2026-10-06：PR #3 把 UI 重设计稿（`docs/design/ui-redesign-brief-2026-10-06.md`）和任务说明 UI-0、UI-1 合入 `develop`。用户决定 **UI-0、UI-1 放到第一阶段之后**，冻结期内不派发、不建任务分支。
- 2026-10-06：新增成员 **engineer2 = grokbot**（Grok，**云端环境**，没有 Flutter）。**不派构建与验证类工作**（analyze、测试、变异、真机、取证）；适合静态核对、文档与证据审阅、脚本类任务；它的复核只作预审，涉及 analyze、测试、变异、真机的结论仍由 leader 派有 Flutter 的子代理重跑后给出。
- 2026-10-06：Xcode 27 已安装，用户已执行 `xcodebuild -runFirstLaunch`。**修订上面的 Xcode 决定**：macOS 设备证据纳入 P0-4，但**不阻塞**第一阶段退出；退出标准第 1 项仍以 Android（vivo V2324A）为准。
- 2026-10-07：设计稿 v4 入库 `docs/design/v4/`，定为第一阶段之后 UI 重做的目标稿（[审阅](../reviews/2026-10-07-design-v4-review.md)）。用户决定：底栏顺序与记忆入口以设计稿为准（AI 助手 · 业务插件 · 工作台 · 数据交换 · 设置；记忆在助手设置）；新增独立 `warn` 色；助手确认改为分级授权（[ADR-0002](0002-graded-assistant-authorization.md)，提议，§5 两问待确认）。均属第一阶段之后的工作，冻结期内只改文档。
- 2026-10-07：用户确认 ADR-0002 §5：写入可设“始终允许”；外传可按已授权端点“本次对话”放行；先不做内容审查，留审查插件 / 服务接口。ADR-0002 改为已采纳，实施仍在第一阶段之后。
- 2026-10-07：用户决定**退出标准第 1 项接受 macOS 设备 R+M 证据**，不再等 Android（Android 重跑改为第二阶段取证项 R-1）。第二至第四阶段的划分按[路线图](../superpowers/plans/2026-10-07-roadmap-phase2-4.md)，第二阶段范围见 [ADR-0003](0003-phase2-scope.md)。
- 2026-10-07：senior 未开始 P0-S2 修复；用户指示由**云端 Sonnet 代理**修复 F1、F2、F4（本条是对“云端不运行开发任务”的一次性例外，由用户明确要求）。F3 仍待用户决定。
- 2026-10-07：**第一阶段退出**。§5 五条标准均已达成，记录见[验收账本](../implementation/muyon-acceptance-ledger.md)末尾「第一阶段退出记录」；P0-S2 作为安全修复继续收尾。第二阶段按 [ADR-0003](0003-phase2-scope.md) 开始。用户同日指示：开发任务由 leader 派生 Sonnet 5.5 子代理执行，leader 只做派发、审查与合入。
