# HANDOVER-A 交接清单

交接人：A（原 leader）· 时间：2026-10-06 · 依据 [HANDOVER-A](HANDOVER-A.md)、[ADR-0001](../adr/0001-leadership-and-scope-freeze.md)

交接时 `develop` 是 `d20f8f4`（本机最后一次推送）。之后远端 `develop` 上的提交都不是 A 提交的。

## 0. 已停止

从收到交接任务起：
- 不再向 `2026-10-04-w1-agent-prompts.md` 追加任务。最后一节是 E11（`d20f8f4`）。
- 不再合并到 `develop`，不再修改验收账本。

## 1. 推送情况（第 2 步）

已逐个检查本机所有分支和工作区：用 `git rev-list <ref> --not --remotes=origin` 核对，每个工作区也跑了 `git status`。只有下面两个提交不在远端，已推送：

| 分支 | 最后提交 | 说明 |
|---|---|---|
| `review/b-ui` | `fc941b1` | A 审查 B1–B3 时做的本地试合并，没有新代码 |
| `review/c-modules` | `b70804b` | A 审查 Codex 第一批提交时做的本地试合并，没有新代码 |

这两个分支只是审查草稿，和 ADR 里约定的 `review/<编号>` 分支无关，建议删除。

其余本地分支都已在远端，没有领先的提交：`develop`、`feat/a-*`、`feat/b-ui`、`feat/c-modules`、`feat/d-transfer`、`feat/e-support`、`wip/g3-handoff`、`ci/manual-verify`、`task/p0-j1-env-doctor`，以及其它本地 `review/*`。`fix/a-global-catalog` 只在本机，它的提交都已在 `develop` 里。

**有未提交改动的工作区**：这些是其它 agent 正在做的工作，A 没有替它们提交。

| 工作区 | 分支 | 归属 | 内容 |
|---|---|---|---|
| `muyon-worktrees/b-ui` | `feat/b-ui` | Sonnet | 2.4 进行中，见下文 |
| `muyon-worktrees/e-support` | `feat/e-support` | opencode | E11 进行中，见下文 |
| `muyon-worktrees/p0-j1` | `task/p0-j1-env-doctor` | P0-J1 的执行者 | 新增 `scripts/doctor.sh` 和 `scripts/test_doctor.sh`，未提交 |
| `muyon-worktrees/c-modules` | `feat/c-modules` | Codex（额度已用完） | G3 半成品。已逐个文件核对，和 `wip/g3-handoff@e8aaebd` 完全一致，G3 已由 B 接手并合入。可以丢弃 |

## 2. 在途任务

### B（Sonnet）· 2.4 原型业务补齐
- **派发**：2026-10-05 23:26，`06f17a0`，提示词文件中「追加 · B（Sonnet）· 2.4 原型业务补齐」一节。
- **已知进度**：截至 10-06 00:17 未提交，有 13 个文件改动。
  - 新增助手只读工具 `apps/muyon/lib/platform/prototype_tools.dart` 及测试。
  - `PrototypeSession.objectPage` 和 `resolve` 都补上了 `feedback`。
  - 原型界面改为窄屏单列。
  - 新增 `scheme_loader.dart` 及测试：说明它在真机上确认了 `file://` 下的模块脚本走不通，改用了自定义 scheme 加载。
  - 已在 Android 真机上发现并修正一个问题：`IGNORE_PREVIOUS_RULES` 内容拦截规则只有苹果平台有，在 Android 上构造会抛异常，页面空白。现在只在 iOS 和 macOS 上加这些规则。
- **预期交付**：推送 `feat/b-ui`，报告里有各平台真机结论、截图说明、测试名。
- **风险**：
  - 自定义 scheme 读文件时可能放宽路径检查（`..`、编码后的点段、其它版本目录）。
  - 可能为了让页面能加载，打开了 `allowUniversalAccessFromFileURLs` 或 `allowFileAccessFromFileURLs`，或在本机起了服务。
  - Windows 没有设备，只能写"未验证"。
  - B 有重新格式化别人文件的习惯。
- **A 原本的验收方式**：
  1. 用 `git diff` 确认没有打开上面两个文件访问开关，也没有起本机服务。
  2. 自定义 scheme 的路径解析只以 `RestrictedWebViewSpec` 为准，单测覆盖 `..`、`%2e%2e`、其它版本目录、绝对路径、空路径。
  3. `prototype-resource-policy.md` 的平台表和"未验证"一节逐条有实机结论，没有删掉仍未验证的条目。
  4. 两个工具的 `effect` 都是 `read`，没有任何写入或外发的原型工具；没有改 `selection_eval/**` 和 `scripts/laya/**`。
  5. 文案不暗示"MES 已迁入"。
  6. 在本机跑 `scripts/verify.sh` 拿到退出码 0。
  7. 有条件的话在 Android 真机上打开 mes-security-model 原型，点一次越界链接确认被拦截。

### E（opencode）· E11 研究对象的业务页与统一打开入口
- **派发**：2026-10-05 23:54，`d20f8f4`，「追加 · E（opencode）· E11」一节。
- **已知进度**：截至 10-06 00:15 未提交，有 8 个文件改动。
  - 新增 `packages/research_module/lib/src/app/object_pages.dart` 和 `apps/muyon/lib/platform/object_pages.dart`。
  - 改了 `platform_shell.dart`、`research_module.dart` 和 `research_runtime_test.dart`。
  - 新增 `object_pages_test.dart` 和 `research_object_open_test.dart`。
- **预期交付**：推送 `feat/e-support`。报告列出每种对象页显示的字段，并给出"原型对象有没有工作区绑定"的结论。
- **风险**：
  - opencode 上次 E10 提交后没推送。
  - 改 `research_runtime_test` 时可能删掉原有的 `null` 断言（模块不对、另一个项目、id 不存在、修订或摘要无效），这些必须保留。
  - 统一入口改写后，阅读器加右侧助手的布局可能丢失。
  - 会话可能没在页面关闭后 `dispose`。
  - 原型对象可能没有工作区绑定，B 做的原型 `objectPage` 就无法从助手回答里打开，需要 leader 决定怎么补。
- **A 原本的验收方式**：
  1. 逐条对照上面的 `null` 断言是否还在。
  2. 详情页上没有编辑、删除、接纳按钮；旧修订标明"不是最新修订"。
  3. `openObject` 只删掉了写死的研究 `document` 分支，知识库和询价分支没动。
  4. 测试覆盖退回 JSON 页和会话 `dispose`。
  5. 跑 `scripts/verify.sh`。
  6. B、E 都合入后在真机上点一次助手回答里的研究条目。

### 其他已派发但未完成的任务
- **Codex（额度用完）**：
  - 推送失败的根本原因没查。它推送失败过 5 次，都是 A 经用户同意代推的；建议它推送后用 `git ls-remote` 核对。
  - 非文档对象页：研究部分已由 E11 接手，询价对象仍走 JSON 页加"在业务页面查看与编辑"按钮。
- **Grok（额度用完）**：没有未完成的派发。D-R8c 及以前都已合入，D-R10 转给 B 后已完成。
- **Laya**：用户已决定暂停专门化，`b1ab08a`。E10 确认没通过：`none` 49/60，只读 32/40，详见 `docs/implementation/tool-selection-eval-2026-10-05.md`。没有在途工作。
- **Jev**：只做了证据审查。要实测需要用户提供早期访问密钥，而且只能用合成题。

## 3. 待合并或待审查的提交

| 分支 | 哈希 | 判断 |
|---|---|---|
| `feat/b-ui` | 工作区未提交 | 等 B 推送 2.4 后按上文审查 |
| `feat/e-support` | 工作区未提交（分支头 `268fb08` 已在远端） | 等 E 推送 E11 后按上文审查。两人改的文件没有重叠：B 不改 `platform_shell.dart`，E 不改 `prototype_module` |
| `task/p0-j1-env-doctor` | `43c408c` 加工作区改动 | 不是 A 派发的，A 没审过 |
| `ci/manual-verify`（PR #2 → `main`） | `fe3e05e` | 只加一个手动触发的检查工作流，A 已审过，内容没问题。按 ADR，`main` 何时更新由用户决定 |
| `develop`（PR #1 → `main`） | 持续更新 | 同上，由用户决定 |

没有其它已推送、但还没审查或合并的 agent 提交。

## 4. 验收账本：原本要更新、还没更新的行

| 行 | 现状 | 打算改成 | 证据 |
|---|---|---|---|
| 2.4 原型业务 + 受限 WebView | ❌（已过时） | 🟡；B 交付并有实机证据后再评 | 已合入：B3 `a744d8a`、`bd97703`；B-R2 资源限制 `acf6b74`；`prototype_module` 测试 24 项；`docs/implementation/prototype-resource-policy.md`；B 的 2.4 交付报告（待收） |
| 3.1 双入口 | 🟡（objectPage → C/B） | E11 合入后，研究对象改为有业务页；询价仍是 JSON 页加业务页按钮；原型对象看 E11 的绑定结论 | E11 交付，`research_runtime_test`，`research_object_open_test` |
| 12 三端构建与实机 | ❌ | 加上 2.4 的 Android 真机结论，并照实写 Windows 没有设备 | B 的 2.4 报告；`docs/implementation/device-acceptance-runbook.md` 第四节"询价与原型" |

Laya 暂停、E9、E10 的记录已经写进账本（`b1ab08a`），不用再补。

## 5. 未决问题与分支去留建议

- `wip/g3-handoff`（`e8aaebd`）：已合入 `develop`（B 的 `7e1f395` 接手）。**建议删除**远端分支和本机工作区；`feat/c-modules` 工作区里同样的未提交改动一并丢弃。
- `ci/manual-verify` 和 PR #2：内容没问题。**建议保留**，等用户决定何时更新 `main`。
- `feat/a-acceptance`、`feat/a-agent`、`feat/a-storage`：都已合入 `develop`。**建议删除**。
- `review/b-ui`、`review/c-modules`：A 的审查草稿，见第 1 节。**建议删除**。本机其它 `review/*` 分支和 `muyon-worktrees/review` 工作区也是草稿，A 会自行清理本机部分。
- `feat/c-modules`、`feat/d-transfer`：都已合入。Codex 和 Grok 恢复额度前，建议保留以便它们继续，之后改用 `task/<编号>` 分支。
- 原型对象的工作区绑定：要等 E11 的结论（见第 2 节）。
- 中段置信度：如果以后重启 Laya，0.5–0.9 的置信度不可信（7 题只对了 2 题），只能信任高置信度的选择。

## 6. 本机环境

- **设备**：
  - macOS 主机，开发和构建都在这里。
  - 一台 Android 16 真机，USB 连接，`adb` 可见，B 正在用它做 2.4 取证。
  - 没有 Windows 设备，也没有第二台真实设备，所以双设备互传和聊天没有实机结果。
- **模型端点**：
  - 助手用的是远程模型提供方，OpenAI 兼容接口，用户已配好密钥，存放在设备本地设置和被 git 忽略的 `.env` 中。
  - Laya 评测在本机 CPU 上离线运行，Python 虚拟环境放在仓库外。
  - 训练用 Kaggle 私有内核，没有推送到任何公开模型仓库。
- **提醒**：仓库根目录 `.env` 的权限现在是 644，建议用户执行 `chmod 600 .env`。
- **`scripts/verify.sh` 最近一次结果**：2026-10-05 23:48，在 `1635557`（E10）上运行，退出码 0（`VERIFY_EXIT=0`）。部分结果：
  - supplier_core 482 通过、3 跳过；
  - host 396 通过、1 跳过；
  - inquiry 322 通过、1 跳过；
  - 其余包全部通过。

  之后 `develop` 上只有文档和 Python 脚本改动（`ace1f00`、`12f139f`、`b1ab08a`、`06f17a0`、`d20f8f4`）。Laya 单测在 `scripts/laya` 目录下运行通过。
