# leader 交接（第一阶段进行中，第 2 次交接）

交接时间：2026-10-06 晚 · 交出：本机 leader 会话（接任自云端 leader）· 接收：新的本机 leader 会话 · `develop` 基线：本文件所在提交

**先读：**
- [ADR-0001](../adr/0001-leadership-and-scope-freeze.md)：角色、派发、范围冻结、退出标准；末尾「后续记录」里有今天的所有用户决定
- [任务索引 README.md](README.md)
- [审查清单 REVIEW.md](REVIEW.md)：**审查模型分工今天改过**，见第 1 节

## 0. 交接时仍在途的核实（最先处理）

旧会话派出的两个 Opus 核实子代理在交接时**还没回报**。新会话收不到它们的结果，请**直接用 Sonnet 重做**，不要等：

| 任务 | 审查分支 @ 提交 | 重做方式 |
|---|---|---|
| **P0-S1** 第 3 轮定向复核 | `review/P0-S1` @ `3b237d7`（代码在 `2409e9a`，`3952783` 合并了 develop；`3b237d7` 只加了 grokbot 的静态预审） | `reviewer-sonnet-high`。要求见 `P0-S1-review.md`「复核（2026-10-06…）」一节 R1～R5：164 字符长密钥探针（含密钥在正文末尾、合法 JSON 非对象两个变体），撤回 R1、R2、科研页校验三处变异，`platform_shell.dart` 合并结果，`flutter analyze` 与宿主全量 |
| **E11b** 研究对象页收尾 | `review/E11b` @ `14db9dc`（3 个文件，+120/−5，范围已核对符合） | `reviewer-sonnet-medium`。N1 变异（删掉 `object_pages.dart` finally 中的 dispose）、N4 变异（截断改为按 UTF-16）、analyze、research_module 全量、`research_object_open_test.dart`（加 `--timeout 90s`） |

**已知背景，两份核实都会碰到：** `apps/muyon/test/research_object_open_test.dart` 中「an object without a binding falls back to the JSON page」「the helper returns null without a binding and disposes」两例，在干净 `develop` 上就是 10 分钟超时（Linux Actions [run 37420884434](https://github.com/mightyoung/Muyon/actions/runs/37420884434)，host `+420 ~2 -2`）。**`develop` 的 CI 门禁从 P0-1 合入起一直是红的**，根因是 E11 在门禁存在之前合入。所以：
- 只因这两例失败，不阻塞 P0-S1、E11b 合入（核实时确认失败的只有这两例、且与 develop 相同）；
- 要尽快另开一个小修复任务（建议编号 **P0-F2**，派 senior；它刚在 P0-S1 R3 修过同类问题：假时间里等真实 IO 导致挂到 10 分钟）。修复要排在任何再改这个测试文件的任务之前。先让核实子代理给出根因初诊，再写任务说明。

## 1. 工作方式（照此延续）

- **角色**（见 ADR-0001 与 README）：
  - senior = Opus（本机，有 Flutter）
  - engineer = Sonnet（本机，有 Flutter，负责真机取证；Android vivo V2324A，macOS 已装 Xcode 27）
  - **engineer2 = grokbot**（Grok，**云端，没有 Flutter**）：只派静态核对、文档与证据审阅；**不派任何构建与验证工作**（用户明确要求）。它的复核只算预审
  - junior = opencode（本机）
- **派发**：一个任务一个分支 `task/<编号>`，说明在 `docs/tasks/<编号>.md`（先提交到 `develop`，再从 `develop` 建任务分支）。给用户一句可直接转发的话。
- **审查**（REVIEW.md 已更新）：
  - 默认用 **Sonnet 5.5 子代理**：`reviewer-sonnet-high`（安全、并发、数据一致性、跨模块）、`reviewer-sonnet-medium`（单模块代码与测试）、`reviewer-sonnet-low`（脚本、文档、证据字段）。定义在本机 `~/.claude/agents/`，写死 `model: claude-sonnet-5-5`。**用户认为用 Opus 审查是浪费**，Opus 只在 Sonnet 结论有分歧或问题特别难时用。
  - 也可**交叉派给非作者成员**：engineer、junior 可做构建与测试类核实；grokbot 只做静态。
  - 不要用 `model: "sonnet"`/`"opus"` 别名：`~/.claude/settings.json` 把别名映射到 MiniMax，`sonnet` 会 404。
  - leader 不在主线程运行或通读代码；结论写入 `review/<编号>` 上的 `docs/tasks/<编号>-review.md`，按「阻断 / 应改 / 可选」分级。
- **合入**：`git merge --no-ff origin/review/<编号>` → 核对任务文件与审查版本逐字一致（diff 为 0 行）→ 更新索引 → 推送。收口原则照旧：审过两三轮只剩低概率问题时先合入、另开小任务。
- **本机环境要点**：
  - 本会话的钩子**不允许写其他工作树**。leader 的审查文档写在自己的工作树里（切到 `review/<编号>` 提交推送，再切回 `develop`）；子代理在 `/tmp` 下用 `git archive` 导出的副本里跑测试、变异和探针，用完删除。
  - 如果 `git` 报 Xcode 许可错误（exit 69），命令前加 `DEVELOPER_DIR=/Library/Developer/CommandLineTools`。许可目前已接受，`xcodebuild -runFirstLaunch` 也已完成。
  - 跑测试时取消代理，并设 `NO_PROXY=localhost,127.0.0.1,::1`。
  - 加压测试必须用 `trap` 回收 `yes` 进程。今天曾发现 32 个孤儿 `yes` 跑了约 3 小时（负载约 190），已清理。
  - `verify.sh`、`ci.sh` 都把 analyzer 的 info 当失败。

## 2. 已合入 `develop`

| 任务 | 审查 |
|---|---|
| HANDOVER-A、P0-J1、P0-J2、P0-2、P0-3、P0-3c、B 2.4、E11 | 见各自审查文件（第 1 次交接前合入） |
| **P0-1** 自动门禁（`ada9487`） | [P0-1-review.md](P0-1-review.md) |
| **P0-F1** 不稳定的局域网测试（`c20355b`） | [P0-F1-review.md](P0-F1-review.md)：根因成立，`stop()` 无竞态 |
| **P0-4 第一、二批证据**（`76c23b2`、`34ca1da`） | [P0-4-review.md](P0-4-review.md)：基线可入账；三次链路都因 D1 失败 |

## 3. 进行中的任务

| 任务 | 分支 / 提交 | 状态与下一步 |
|---|---|---|
| **P0-S1** 凭据脱敏 | `review/P0-S1` @ `3b237d7` | 第 3 轮复核待重做（第 0 节）。通过后合入，**合入后才能开始 P0-3d 和 P0-S2**。 |
| **P0-3d** 助手协议容错（D1） | `task/p0-3d-protocol-robustness` @ `ff9625a` | 说明见 [P0-3d.md](P0-3d.md)。**第一阶段关键路径**：不修就拿不到 `passed: true` 的链路证据。P0-S1 合入后转发给 senior：「检出 `task/p0-3d-protocol-robustness`，先 `git merge origin/develop`，阅读 `docs/tasks/P0-3d.md` 并按要求执行，提交并推送到该分支，不要合并 develop。」 |
| **P0-S2** MCP 令牌脱敏 | `task/p0-s2-mcp-token-redaction` @ `fccc318`（基于旧的 `review/P0-S1`） | P0-S1 合入后，让 senior 在该分支合并 `develop`，再派 `reviewer-sonnet-high` 核实。说明见 [P0-S2.md](P0-S2.md)；要点：用 `git diff origin/develop...HEAD -- apps` 看本任务改动，确认它对 `credential_redaction.dart` 的修改没有削弱 P0-S1（尤其 R1 的固定错误文本和 R4 的 8 字符下限）；MCP 工具结果回显令牌时是否会进入助手、模型或账本。 |
| **E11b** | `review/E11b` @ `14db9dc` | 核实待重做（第 0 节）。通过后合入，然后把 **P0-J3** 转给 junior。 |
| **P0-F2**（建议新开） | — | 修 `research_object_open_test.dart` 两个 10 分钟超时，让 `develop` 门禁变绿。见第 0 节。 |
| **P0-4** 真机与真实模型取证 | `review/P0-4`（engineer 现在推到这里） | engineer 正在跑 **macOS 设备链路**（预算题预计仍因 D1 失败，照常入库为负面证据）。P0-3d 合入后，在 Android 和 macOS 各重跑一次链路，加一次 `bash scripts/ci.sh`。 |
| **P0-J3** 自检脚本测试收尾 | `task/p0-j3-doctor-tests` | 排在 E11b 合入之后，junior。 |

## 4. 第一阶段退出标准（ADR-0001 §5）

| # | 标准 | 状态 |
|---|---|---|
| 1 | 询价链路至少有一个真机、一个真实模型的证据入账 | **未达成**：Android 真机已跑通流程，但预算题因 D1 失败。等 P0-3d 合入后在 Android 重跑。macOS 纳入但不阻塞。 |
| 2 | LLM 工具选择基线至少有一个真实模型的数字 | **已达成**：deepseek-chat top-1 66/140，误选写入/外发 0，弃权 26/26 |
| 3 | 自动门禁可用 | **已达成**（P0-1）；但门禁目前因 E11 两个超时是红的，见 P0-F2 |
| 4 | B 2.4 与 E11 合入，或明确搁置 | **已达成** |
| 5 | 验收账本按证据更新 | 第一阶段退出时由 leader 一次性完成（第 6 节） |

## 5. P0-4 之后批次的审查要点

1. 证据中不得出现密钥：用 `.env` 中密钥的完整值和首尾各 12 位逐文件 grep，只报命中数；端点只保留到路径；本机路径替换为 `<repo>`。
2. 链路证据 `docs/evidence/2026-10-p0/north-star-<平台>-<slug>.json`：`evidenceClass: real-model`、`passed: true`；`readResultsChecked` 同时含 `compare_quotes` 和 `project_budget`；`tasks[].tools` 与逐题判定一致；`write.repeatConfirmRefused` 为 true；运行代码必须是含 P0-3c、P0-3d 的 `develop`。
3. 每次运行都如实入库，不挑结果。Android、macOS 分开记录；Windows 写「未验证」。
4. 执行 `verify.sh` 时不得导出 `MUYON_EVAL_REAL`。Android 运行后要卸载测试包，因为 `--dart-define` 会把密钥编进构建。
5. 证据字段核对派 `reviewer-sonnet-low`，或交叉派给 grokbot 做静态部分。

## 6. 验收账本待更新（第一阶段退出时一次性完成）

文件：`docs/implementation/muyon-acceptance-ledger.md`，只由 leader 修改。可让 grokbot 起草初稿，leader 定稿。

| 行 | 更新内容 |
|---|---|
| 2.3、7、9a | 按 P0-4 证据补 M、R 证据。9a 只能写「端点显式，本次运行没有写出密钥」，钥匙串没有经过实机验证。 |
| 2.4 | B 2.4 已合入；Android 16 真机结论见 `prototype-resource-policy.md`（`file:` 链接由 Chromium 自己拒绝，没有经过守卫）；macOS 渲染和 Windows 未验证（Windows 很可能打不开）。 |
| 3.1 | E11：研究对象经 `objectPage` 打开业务页。task、run、card、outline、section 页面上的助手，在调用工具时会报错（不在目录内，见 E11 审查 N3）。原型对象从助手回答跳转属于 S6，已搁置。 |
| 7 | P0-2 评测已有真实运行能力；工具选择真实基线 deepseek-chat top-1 66/140（P0-4）。 |
| 12 | 把 P0-1 门禁、P0-4 真机结果（Android 必有，macOS 视结果）补入「三端构建与实机」。 |
| 凭据 | P0-S1、P0-S2 合入后，补上凭据脱敏的证据（含长密钥回显探针）。 |

## 7. 已记录、待第一阶段之后排期的事项

- **S6**：原型对象从助手回答跳回原型页。两个方案：临时绑定，或给运行时加不需要绑定的 `objectPage` 接口。
- **E11 N3**：研究详情页上的助手范围不在宿主目录内。要么扩充目录，要么让助手绕过目录关卡。这属于设计决定。
- **P0-3c 可选项**：只读题没调用工具时，`failure` 里缺题名；交叉工具测试在导出 `MUYON_EVAL_REAL=1` 时不再隔离。
- **P0-2、P0-S1 可选项**：脱敏只匹配关键词，`x-api-key`、`api_key=` 未覆盖；`addProfile` 中 controller 提前 dispose（原有缺陷）。
- **P0-F1 可选项**：测试注释可写明守的是「stop 返回前上传已结束并清理」；显式取消上传（lan.dart:326）对该测试是冗余的。
- **P0-1 可选项**：三个文件上的 `@Tags(['screenshot'])` 已无脚本使用。
- **深度研究报告第 6 节**：Agent 内核 v2、分级授权、记忆、统一检索、外壳重构等。
- **UI-0、UI-1**（UI 重设计，PR #3 合入的设计稿与任务说明）：用户决定放到第一阶段之后。

## 8. 需要用户处理或决定的事

- `main` 在第一阶段退出前不动；PR #1、#2 保持开放。
- 已完成：删除 6 个远端分支、`chmod 600 .env`、接受 Xcode 许可并完成 `-runFirstLaunch`。
- 可在合适时机请用户删除的停用分支：`feat/p0-ci-llm-baseline`，以及已合入的 `task/*`、`review/*`（P0-1、P0-2、P0-3、P0-3c、P0-F1、P0-J1、P0-J2、HANDOVER-A、B-2.4、E11 等）。leader 在本机可以直接删，但要先征得用户同意。
- 旧会话执行命令时，曾把 `~/.claude/settings.json` 里的 MiniMax `ANTHROPIC_AUTH_TOKEN` 打印进会话记录（只在本机）。是否轮换由用户决定。

## 9. 接任后的建议顺序

1. `git fetch`，按本文件核对各分支哈希；确认 `reviewer-sonnet-*` 子代理可用（试调一次）。
2. 用 Sonnet 重做第 0 节两份核实，并让 P0-S1 那份附上两个超时的根因初诊。
3. P0-S1 通过 → 合入 → 转发 P0-3d 给 senior（关键路径）→ 让 senior 把 `develop` 合进 P0-S2，再核实、合入。
4. E11b 通过 → 合入 → 转发 P0-J3 给 junior。
5. 按初诊写 P0-F2，派 senior，修好后 `develop` 门禁应变绿。
6. 收 engineer 的 macOS 设备批次 → 审查 → 合入。
7. P0-3d 合入 → engineer 在 Android（必需）和 macOS 重跑链路 → 审查 → 合入，退出标准第 1 项达成。
8. 更新验收账本（第 6 节）→ 对照第 4 节确认全部达成 → 向用户报告第一阶段结束，之后的路线（第 7 节、UI-0/UI-1）请用户排期。
