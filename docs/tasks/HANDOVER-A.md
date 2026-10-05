# HANDOVER-A 原 leader 交接

分支 `task/handover-a` · 执行 A（原 leader）· 接收 leader · 依据 [ADR-0001](../adr/0001-leadership-and-scope-freeze.md)

用户已决定由云端 leader 接管整体的规划、派发、审查与合并。请按以下步骤交接。

## 1. 立即停止
- 不再向 `docs/superpowers/plans/2026-10-04-w1-agent-prompts.md` 追加任务。
- 不再合并任何分支到 `develop`，也不再修改验收账本。

## 2. 推送未推送的工作
把本机上所有尚未推送的提交推送到各自的分支（`feat/a-*` 或其他）。**不要**合并到 `develop`。逐一列出分支名和最后一个提交的哈希。

## 3. 写交接清单
在本分支新建 `docs/tasks/HANDOVER-A-report.md`，包括：
1. **在途任务**：B「2.4 原型补齐」、E「E11 研究对象页」，以及其他已派发但未完成的任务。每项写明：
   - 派发时间；
   - 已知进度；
   - 预期交付；
   - 已知风险；
   - 收到回报后你原本打算怎么验收。
2. **待合并或待审查的提交**：分支、哈希、你的判断。
3. **验收账本**：打算更新但还没更新的行，以及对应的证据位置。
4. **未决问题**：例如 `wip/g3-handoff`（Codex 未完成的供应商中心发布）、`ci/manual-verify` 等分支的去留建议。
5. **本机环境**：
   - 可用设备；
   - 模型端点类型：本机或远程，**不要写密钥和私有地址**；
   - `scripts/verify.sh` 在本机的最近一次结果。

## 4. 之后
如果你同时承担 senior engineer 角色，交接完成后按 `develop` 上的 [docs/tasks/README.md](README.md) 领取任务（P0-3，然后 P0-2）。

## 回报
本分支的提交哈希，以及第 2 步列出的分支清单。
