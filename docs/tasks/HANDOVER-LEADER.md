# leader 交接（第一阶段进行中）

交接时间：2026-10-06 · 交出：云端 leader（线上额度将尽）· 接收：接任 leader · `develop` 基线：本文件所在提交

**先读这三份：**
- [ADR-0001](../adr/0001-leadership-and-scope-freeze.md)：角色分工、派发方式、范围冻结、第一阶段退出标准
- [任务索引 README.md](README.md)
- [审查清单 REVIEW.md](REVIEW.md)

背景材料是[深度研究报告](../reviews/2026-10-05-muyon-deep-review-and-optimization.md)和[第一阶段计划](../superpowers/plans/2026-10-05-phase0-plan.md)。

## 0. 交接时刚到、尚未审查的推送（最先处理）

| 分支 | 提交 | 内容 | 下一步 |
|---|---|---|---|
| `review/P0-1` | `ad5cb70` | junior 的 P0-1 修复：去掉 screenshot tag 排除并整理门禁脚本，只改 `scripts/ci.sh`（+20/−13） | 派 Sonnet 轻量复核：确认按方案 A 修改、完成 F4～F6、Actions 在该分支的运行结果，以及本机 `ci.sh` 的摘要。通过后合入，退出标准第 3 项即达成 |
| `task/p0-4-evidence` | `f535db4` | engineer 的 P0-4 取证（第一批）：模型 `deepseek-chat`，包括 `verify.sh`、工具选择基线报告 `tool-selection-llm-baseline-deepseek-chat.md`、链路无头运行、证据汇总 `p0-evidence-2026-10.md`，共 4 个文件 | 建 `review/P0-4`，按第 5 节审查；Sonnet 足够，重点查密钥和证据字段。提交说明只提到无头运行，**macOS 设备和 Android 真机的链路证据可能还没完成**，需要向 engineer 确认是否还有后续提交 |

## 1. 工作方式（照此延续）

- **角色**：leader 负责拆解、派发、审查、合入 `develop`、维护验收账本。实现与真机取证全部交给用户本地的 agent：senior = Opus，engineer = Sonnet，junior = opencode。云端不做开发；用户已要求节省线上额度。
- **派发**：一个任务一个分支 `task/<编号>`，说明放在分支内固定位置 `docs/tasks/<编号>.md`。说明写好后，交给用户转发，并给出一句可以直接转发的话。
- **审查**：
  1. 从任务分支的最终提交建立 `review/<编号>`。
  2. **代码核实交给子代理**，leader 不在主线程里运行或通读代码。复杂或高风险的用 Opus，常规的用 Sonnet；子代理只回报，不提交。
  3. leader 把结论写进审查分支的 `docs/tasks/<编号>-review.md`，按「阻断 / 应改 / 可选」分级。
  4. 需要修改的交回执行者，在审查分支上修。修完做定向复核，不重做全量审查。
- **合入**：
  1. `git merge --no-ff origin/review/<编号>` 合入 `develop`。
  2. 合入后**核对任务自己改动的文件与审查版本逐字一致**（`git diff origin/review/<编号> HEAD -- <该任务的文件>` 应为 0 行）。
  3. 更新任务索引并推送。
- **收口原则**：同一任务已经审了两三轮，剩下的只是低概率问题或测试缺口时，先合入，另开小任务跟进，并写进审查文件，避免反复评审。
- **环境注意**：
  - 云端会话的 git 代理禁止删除远端分支（HTTP 403，不能重试或绕过），删除要请用户在本机执行。
  - Agent 工具的 `isolation: worktree` 曾经从初始提交（只有 LICENSE）建出工作区。请手动 `git worktree add` 建在 `.claude/worktrees/` 下，再把路径告诉子代理；`.claude/worktrees/` 已写进 `.git/info/exclude`。
  - 本容器装有 Flutter 3.47.5（`/opt/sdk/flutter/bin`）。重开会话后这套环境可能不在了，需要按原来的方法重新下载。
  - `flutter pub get` 需要代理；跑测试时要去掉代理，并设置 `NO_PROXY=localhost,127.0.0.1,::1`。
- **门禁**：GitHub Actions 可用（P0-1 分支上第 2 次运行在 Linux 通过，约 8 分钟）。`verify.sh` 和 `ci.sh` 都把 analyzer 的 info 当作失败。

## 2. 已合入 `develop`

| 任务 | 合入方式 | 审查 |
|---|---|---|
| HANDOVER-A 原 leader 交接 | `fd0676a` | [HANDOVER-A-review.md](HANDOVER-A-review.md) |
| P0-J1 自检脚本 | cherry-pick 148e031..abaf047（原分支基于停用的集成分支） | [P0-J1-review.md](P0-J1-review.md) |
| P0-J2 自检脚本加固 | merge | [P0-J2-review.md](P0-J2-review.md) |
| P0-2 LLM 原生工具调用基线（代码） | merge `5e72ac1` | [P0-2-review.md](P0-2-review.md) |
| P0-3 询价 North Star 链路 | merge | [P0-3-review.md](P0-3-review.md) |
| P0-3c 逐题判定 | merge | [P0-3c-review.md](P0-3c-review.md) |
| B 2.4 原型补齐 | merge `f870cb8` | [B-2.4-review.md](B-2.4-review.md) |
| E11 研究对象页 | merge | [E11-review.md](E11-review.md) |

## 3. 进行中的任务（按执行者）

| 任务 | 分支 / 最新提交 | 状态与下一步 |
|---|---|---|
| **P0-S1** 模型网关凭据脱敏 | `review/P0-S1` @ `ee9843d` | 修复已交付（F1、F2、N2）。**定向复核被中断，需要重做**，派 Opus。要点见审查文件末尾「修复方式」：重跑 M2、M4 变异；N2 探针，包括端点在 200 响应体中回显密钥、1 个字符的短凭据、含正则特殊字符的密钥；F2 的界面测试。通过后**先于 P0-S2 合入**。注意它改了 `platform_shell.dart`（+1 行 import），合入前用 `git merge-tree` 检查冲突。 |
| **P0-S2** MCP 令牌脱敏 | `task/p0-s2-mcp-token-redaction` @ `fccc318`（已合并 `review/P0-S1`） | 已交付，**核实被中断，需要重做**，派 Opus，说明见 [P0-S2.md](P0-S2.md)。中断前已知：55 个探针全部通过；变异测试还没跑。本任务的改动范围用 `git diff origin/review/P0-S1 HEAD -- apps` 查看，它**又改了一次** `credential_redaction.dart`，要确认没有削弱 P0-S1 的效果。另外要看 MCP 工具结果里如果回显了令牌，是否会进入助手、模型或账本。 |
| **P0-F1** 不稳定的局域网测试 | `task/p0-f1-lan-flaky-test` @ `8de0ca3`（只改测试，+22/−1） | 已交付，**核实被中断，需要重做**，派 Opus。要点：先在 develop 上测出基线失败率（云端沙箱曾 14 次失败 11 次）；判断根因结论对不对，**`stop()` 是否本身就有竞态**，如果有，只修测试就是掩盖问题；不能加 sleep、加长超时或重试；单测循环 50 次，加压再跑 20 次；把 `stop()` 改坏后，测试必须失败。 |
| **P0-1** 自动门禁 | `review/P0-1` | 等 **junior** 修复：按方案 A 去掉 tag 排除，另修 F4～F6，见 [P0-1-review.md](P0-1-review.md)，该文件在 `review/P0-1` 分支上。推送后 Actions 会自动运行，回报需附运行链接。改动小，用 Sonnet 轻量复核。 |
| **E11b** 研究对象页收尾 | `task/e11b-object-page-tests` | 待 junior 做（排在 P0-1 之后）：补辅助函数在返回 null 时 dispose 会话的测试，修卡片标题。见 [E11b.md](E11b.md)。 |
| **P0-J3** 自检脚本测试收尾 | `task/p0-j3-doctor-tests` | 待 junior 做（排在 E11b 之后）。做完后自检脚本不再开新任务。 |
| **P0-4** 真机与真实模型取证 | `task/p0-4-evidence` | **engineer 进行中。** 环境：macOS 加 Android 16（vivo V2324A），一个远程 OpenAI 兼容模型，没有 Windows，也没有本机模型。说明见 [P0-4.md](P0-4.md)。审查要点见第 5 节。 |

## 4. 第一阶段退出标准（ADR-0001 §5）

| # | 标准 | 状态 |
|---|---|---|
| 1 | 询价链路至少有一个真机、一个真实模型的证据入账 | 等 P0-4 |
| 2 | LLM 工具选择基线至少有一个真实模型的数字 | 等 P0-4（评测代码已合入） |
| 3 | 自动门禁可用 | Actions 已证明能跑；等 P0-1 合入 |
| 4 | B 2.4 与 E11 合入，或明确搁置 | **已达成**（S6 已搁置） |
| 5 | 验收账本按证据更新 | 等 P0-4 回报后由 leader 统一更新（见第 6 节） |

## 5. P0-4 回报后的审查要点

1. 证据中**不得出现密钥**。逐个文件 grep；端点只保留到路径。
2. **基线报告**：`docs/implementation/tool-selection-llm-baseline-<slug>.md`。每个模型只跑一次，不挑结果。核对 top-1、误选写入或外发、弃权质量、p50/p95、用量。
3. **链路证据**：`docs/evidence/2026-10-p0/north-star-<平台>-<slug>.json`。
   - `evidenceClass` 必须是 `real-model`，`passed: true`；
   - `readResultsChecked` 必须同时包含 `compare_quotes` 和 `project_budget`；
   - P0-3c 已合入，逐题判定由程序强制执行，只需确认证据里的 `tasks[].tools` 与此一致；
   - `write.repeatConfirmRefused` 为 true。
4. **真机与平台**：Android 与 macOS 分别记录；Windows 写「未验证」。
5. 执行 `verify.sh` 时**不得导出** `MUYON_EVAL_REAL`。
6. 核实同样交给子代理，例如让 Sonnet 校验 JSON 字段、检查有没有密钥、确认数字能由报告复现。leader 不在主线程读大文件。

## 6. 验收账本待更新（第一阶段退出时一次性完成）

文件：`docs/implementation/muyon-acceptance-ledger.md`，只由 leader 修改。

| 行 | 更新内容 |
|---|---|
| 2.3、7、9a | 按 P0-4 证据补 M、R 证据。9a 只能写「端点显式，本次运行没有写出密钥」，钥匙串没有经过实机验证。 |
| 2.4 | B 2.4 已合入；Android 16 真机结论见 `prototype-resource-policy.md`（`file:` 链接由 Chromium 自己拒绝，没有经过守卫）；macOS 渲染和 Windows 未验证（Windows 很可能打不开）。 |
| 3.1 | E11：研究对象经 `objectPage` 打开业务页。task、run、card、outline、section 页面上的助手，在调用工具时会报错（不在目录内，见 E11 审查 N3）。原型对象从助手回答跳转属于 S6，已搁置。 |
| 7 | P0-2 评测已有真实运行能力；工具选择真实基线的数字来自 P0-4。 |
| 12 | 把 P0-1 门禁、P0-4 真机结果补入「三端构建与实机」。 |
| 凭据 | P0-S1、P0-S2 合入后，补上凭据脱敏的证据。 |

## 7. 已记录、待第一阶段之后排期的事项

- **S6**：原型对象从助手回答跳回原型页。两个方案：临时绑定，或给运行时加不需要绑定的 `objectPage` 接口。
- **E11 N3**：研究详情页上的助手范围不在宿主目录内。要么扩充目录，要么让助手绕过目录关卡。这属于设计决定。
- **P0-3c 可选项**：只读题没调用工具时，`failure` 里缺题名；交叉工具测试在导出 `MUYON_EVAL_REAL=1` 时不再隔离。
- **P0-2、P0-S1 可选项**：脱敏只匹配关键词，`x-api-key`、`api_key=` 未覆盖；`addProfile` 中 controller 提前 dispose（原有缺陷）。
- **深度研究报告第 6 节**：Agent 内核 v2、分级授权、记忆、统一检索、外壳重构等，都是第一阶段之后的路线。

## 8. 需要用户处理或决定的事

- ~~本机删除 6 个远端分支~~：2026-10-06 用户已删除，leader 已用 `git ls-remote` 核实，远端不再存在。
- 本机执行 `chmod 600 .env`。
- `main` 在第一阶段退出前不动；PR #1 与 PR #2 保持开放。
- 停用但仍在远端的分支，可以在合适时机请用户删除：`feat/p0-ci-llm-baseline`，以及各 `task/*` 和 `review/*` 中已合入的分支。

## 9. 接任后的建议顺序

1. 重建环境（Flutter 3.47.5），`git fetch`，按本文件核对各分支哈希。
2. 重新派核实：P0-S1（定向）→ 通过则合入 → P0-S2 → 合入；P0-F1 可以并行核实。
3. 等 junior 交回 P0-1 → 轻量复核 → 合入，满足退出标准第 3 项；随后是 E11b、P0-J3。
4. 等 engineer 交回 P0-4 → 按第 5 节审查 → 合入证据 → 按第 6 节更新验收账本。
5. 对照第 4 节确认退出标准全部满足，向用户报告第一阶段结束；之后的路线和排期请用户决定。
