# Muyon 分角色并行开发计划

日期：2026-10-04。依据：用户最新《Muyon 总体需求》（12 节）、`docs/implementation/miyono-foundation-acceptance.md`、`tool-platform-contract.md`、`2026-10-04-muspace-requirements-backcheck.md` 及当前代码核对。本文是计划，不代表任何项已实现或验收。

---

## 0. 现状快照（代码核对结论）

| 领域 | 现状 | 与新需求差距 |
|---|---|---|
| 命名/目录 | 仓库 `muspace`、包 `muspace_module_api`、界面显示 Miyono | 需求要求 `apps/muyon`、`packages/muyon_module_api`、`muyon.sqlite` |
| 代码量 | 宿主 10.2k 行 / 38 文件；inquiry 24k；supplier_core 22k；research 8.9k；module_api 0.8k | `screens/platform_shell.dart` 1183 行，超 800 行上限 |
| 版本控制 | main 上 40 个已改文件 + 约 25 个未跟踪文件（OCR、知识、传输、助手、屏幕），仅 4 个提交 | 并行开发前必须先形成基线 |
| 模块契约 | BusinessModule/ModuleSchema/ManagedDatabase/ToolRegistry/AssistantScope/ImportIntent+Receipt 已有 | 缺：业务事件与变更记录（投影用）、对象跳转注册、通知/进度声明、依赖校验、WebView 桥接契约 |
| 存储 | StorageManager 统一建库、结构/定义/迁移历史漂移检测；研究模块声明 ModuleSchema | 询价模块仍自行打开 `ai-jobs.sqlite`、自带 backups/settings.json/lan-inbox（`inquiry_module/.../app_state.dart:75,208,324,408`）；`supplier_core/store.dart:282` 自开库；备份为复制 SQLite 文件 |
| 投影/检索 | KnowledgeService：FTS5/BM25、中文双字、真实 embedding + 离线向量 | 无业务变更记录驱动的幂等投影；无混合检索；无中文短词/中英混合评测 |
| Agent | 多轮工具循环、审批收据防重放、执行记录、取消/中断解释、可替换工具选择 | 询价写操作未注册为工具；Jev/Laya 未评估；Dream 未做 |
| 记忆 | 来源/范围/版本/过期、只读重复候选 | 无矛盾回查、无经验验证流程、无撤回向派生数据传递 |
| OCR | PP-OCRv5 mobile ONNX，Python ORT 参考推理通过 | Flutter 原生三端未实机验证；macOS 被抬到 14+ |
| 设备通信 | LAN 一对一文字/链接/附件、进度、回执、待核收件 | **明文、无设备身份认证**，直接违反第十节 |
| 原型业务 | 无模块、无 WebView 依赖 | 整体缺失（`~/Downloads/dev/mes-security-model` 存在） |
| 科研 | 阅读/关系/提纲/卡/研究包/任务包已迁入（历史 95 项） | 跨设备不同本地 ID 往返、并发分叉、引用锚（摘要+页码+引句）验收未做；完整科研链未跑 |
| 平台验证 | Android release APK 构建过（开发签名） | 无完整 Xcode、无 Windows 工具链、无连接的 Android 设备 |

---

## 1. 需要用户决策的问题（阻塞项标 ★）

> **2026-10-04 决策**：用户确认全部按建议执行；追加要求全部页面沿用 software-cost-calculator `DESIGN.md`（Folio）风格。问题 4（实机设备）与问题 8（验收素材、模型端点）仍待用户提供，不阻塞 W0/W1，阻塞 W3。

1. ★ **命名统一**：采用 Muyon 并重命名目录/包/Bundle ID/主库文件名？当前无旧用户数据，现在改成本最低。建议：W0 一次性改完，界面、包名、库名统一为 Muyon。
2. ★ **基线提交**：main 上 65 个未提交变更能否整体提交为 `feat: foundation baseline`？不提交无法开 worktree 并行。
3. ★ **设备安全方案**：在线通信改为「配对时交换 Ed25519 身份公钥（二维码/短码人工比对）+ TLS 1.3 自签证书钉扎」，还是 Noise_XX？建议 TLS 钉扎（Dart `SecureSocket` 原生可用，不加依赖）。
4. ★ **实机资源**：谁提供完整 Xcode 的 macOS、Windows 机器、Android 真机？没有这些，第十二节的三端验收无法声明通过。macOS 最低 14 是否接受？
5. **询价模块存储适配深度**：需求允许“已有实现通过适配接入”。建议：宿主持有 supplier 库与 ai-jobs 库的路径和唯一连接、登记目录；保留 supplier 原迁移代码但由宿主触发；备份改由宿主协调。是否接受“不重写 supplier 存储层”？
6. **原型模块范围**：V0.1 只做 mes-security-model 的受限 WebView 展示 + 页面/版本/反馈管理，还是要“搭建”能力？建议前者，搭建后置。
7. **发布切面**：需求是完整产品。建议 V0.1 = 第 2 节五项业务的最小完整链 + 科研完整验收链 + 三端构建；Dream 自动经验推广、在线任务调度、中继穿透后置。是否同意？
8. **真实验收素材**：需要用户提供真实论文 PDF（含扫描件）、research-workflow 产出、真实询价单，以及用于验证的模型端点（本机 Ollama？远程？）。
9. **Agent 协作方式**：四个 Agent 是否共享同一 git remote 各开分支 + PR，由 Opus 合并？还是全部本地 worktree？建议前者，便于 Codex/Grok 在各自环境工作。

---

## 2. 角色分工

按“谁最擅长”与“文件所有权不重叠”分配。每个角色独占目录，跨目录修改必须走集成者。

| 角色 | 模型 | 定位 | 独占目录 |
|---|---|---|---|
| **A 架构/集成者** | Claude Code Opus 5.5 Medium | 契约冻结、存储与事务、权限路径、代码审查、合并门禁、验收账本 | `packages/muyon_module_api/`、`apps/muyon/lib/platform/`、`docs/` |
| **B 前端/体验** | Claude Code Sonnet 5.5 Medium | 设计系统、桌面/手机外壳、科研阅读批注 UI、原型模块与受限 WebView | `apps/muyon/lib/screens/`、`apps/muyon/lib/app/`（除 plugin 接线）、`packages/prototype_module/` |
| **C 业务模块迁入** | Codex gpt6.1 sol Medium | 询价/科研存储适配、研究包往返、引用锚、业务工具注册，测试密集型实现 | `packages/inquiry_module/`、`packages/supplier_core/`、`packages/research_module/`、`apps/muyon/lib/app/*_plugin.dart` |
| **D 难题攻坚** | grok-build Grok 4.7 xhigh | 设备身份与加密传输、跨设备任务归属、检索评测与混合检索、Dream/记忆一致性 | `apps/muyon/lib/services/transfer/`、`services/knowledge/`、`services/search/`、`apps/muyon/lib/assistant/memory*`、`platform/memory_review.dart` |
| **E 支援开发** | opencode DeepSeek v4.1 flash | 范围明确、接口现成、可测试验收的任务：数据去向页、MCP 配置页、平台层测试覆盖率 | `apps/muyon/lib/screens/data_flow_page.dart`、`mcp_servers_page.dart` 及其测试；覆盖率报告 |

理由：Grok xhigh 推理深但慢，只给边界清晰、需深推敲的协议与算法；Codex 擅长按明确规格大批量改造并补测试；Sonnet 做 UI 迭代快；Opus 守契约与一致性，不承担大块实现。

---

## 3. 阶段与并行任务

### W0 基线与契约冻结（A 主导，其他人只读，约 1–2 天）

- W0-1 提交基线；建 `develop` 分支；每角色一个 worktree/分支：`feat/a-*`、`feat/b-*`、`feat/c-*`、`feat/d-*`。
- W0-2 重命名 MuSpace/Miyono → Muyon（目录、包、Bundle ID、`muyon.sqlite`、文档引用）。全量测试通过后才放行 W1。
- W0-3 契约 v1 冻结（`muyon_module_api`）新增：
  - `ModuleManifest.optionalDependencies`；宿主 `ModuleRegistry` 对 API 版本不符、缺失/不可用必要依赖、依赖环只标记该模块不可用（`unavailable` 附原因），不再让整个应用启动失败；
  - `ModuleChangeLog`：模块在自己的迁移里建表，在业务写事务内 `record`；宿主用游标 `since` 幂等更新投影；
  - `ModuleSession.objectPage(context, ref)`：对象跳转到业务页面；
  - `RestrictedWebViewSpec`：允许根（https/file、路径边界、拒绝 `..`/javascript/data）、桥接频道白名单。
  - 不进契约：设备身份（D 在宿主 `services/transfer` 内实现）；通知/进度声明（出现第二个真实使用者时再加）。
- W0-4 拆分 `platform_shell.dart`：已由 A 完成（纯搬移，part + 扩展，388/193/248/372 行）。
- W0-5 建立需求→证据验收账本（`docs/implementation/muyon-acceptance-ledger.md`），每条需求标注：文档审查 / 自动测试 / 平台构建 / 真实模型 / 真机业务 五类证据。

**门禁**：契约 v1 合并、全量测试绿、`flutter analyze` 无问题。

### W1 核心能力并行（约 2 周）

| 编号 | 负责 | 任务 | 完成判据（自动测试） |
|---|---|---|---|
| A1 | A | 存储统一：每物理库单写队列；结构目录启动对账；高版本/漂移/失败阻止模块启用不清库 | 漂移、高版本、升级中断三类测试 |
| A2 | A | 变更记录→对象目录/检索投影幂等更新；删除/撤回使投影失效；取材前回领域服务核对 | 重复事件、删除后取材被拒 |
| A3 | A | 宿主备份/恢复协调器（SQLite backup API + 文件仓清单一致快照） | 写入中备份可恢复且一致 |
| A4 | A | 首次导入通用化：主库意图 + 业务库回执 + 绑定对账（科研、询价共用） | 每个中断点恢复不重复创建 |
| B1 | B | **统一 Folio 设计风格**（用户指定，基准 [docs/design/DESIGN.md](../../design/DESIGN.md)）：以 `inquiry_module/lib/src/app/theme.dart` 为唯一实现，抽成共享主题（Tokens + 明暗 ThemeData），宿主 `app_shell.dart` 自建 ThemeData 与科研 `theme.dart` 副本改为引用它，原型模块同样使用；桌面导航+可收起助手；手机独立页面与返回关系；模块不可用原因展示 | 320/390/1280 宽、200% 字号 golden；三处主题 token 一致性测试 |
| B2 | B | 科研阅读：批注/摘录/精读 UI，页级回跳与文字高亮分开呈现 | widget 测试 |
| B3 | B | 原型模块 `prototype_module`：受限 WebView（资源根、导航拦截、桥接白名单），页面/版本/反馈管理；接入 mes-security-model 构建产物 | 导航越界、未注册桥接消息被拒 |
| C1 | C | 询价存储适配：supplier 库与 ai-jobs 库由宿主打开/登记/升级；backups/settings/lan-inbox 改走宿主服务；原 465/309 回归重跑 | 原回归 + 宿主目录登记测试 |
| C2 | C | 科研：确认运行路径只用注入的 ManagedDatabase；`WorkbenchStore.open` 降为测试专用 | 宿主路径无自开库（grep 断言测试） |
| C3 | C | 引用锚：原文件摘要 + 物理页码 + 原文引句 + 上下文；换版保留旧引用；无法唯一定位明确提示 | 改标题不变身份、换版、歧义定位 |
| C4 | C | 完整研究包往返：来源项目键 + 对象 UUID，不同本地 ID、重复导入、继承修改、并发分叉不覆盖 | 往返与分叉矩阵测试 |
| D1 | D | 设备信任：配对（短码/二维码比对公钥）、TLS 钉扎、未配对拒连；替换明文 LAN（含 inquiry 自带 LAN） | 中间人/伪造设备/重放测试 |
| D2 | D | 消息状态机：送达 / 附件持久接收 / 业务导入 / 已读 / 人工接纳 五态独立；流式 + 长度 + 摘要；重试去重 | 状态转换与断线重试测试 |
| D3 | D | 检索评测台：固定中文/中英混合语料（含短词）+ 标注；比较 FTS、向量、混合；依据收益与成本给出策略结论 | 评测脚本可复跑、输出报告 |

**W1 门禁**：A 审查全部 PR；全量测试绿；验收账本更新。

### W2 Agent、记忆与跨设备任务（约 2 周）

| 编号 | 负责 | 任务 |
|---|---|---|
| A5 | A | 统一调用路径审计：UI 与模型都只能走 识别→筛选→提出→核对→确认→执行→核验→记录；外部写结果不确定时先查询再重试 |
| A6 | A | 第三方/MCP 适配层：权限、目的地、结果状态记录 |
| B4 | B | 助手执行面板：目标/进度/设备/等待原因/错误/产物；按工具能力显示暂停/取消/恢复；结果回跳对象页 |
| B5 | B | 记忆与经验管理页：查看/修改/停用/删除/过期、矛盾依据回查、Dream 变更审阅与撤回 |
| C5 | C | 询价工具注册：受控查询/解释/比较/确定性计算（只读）；写操作经宿主确认；金额规则留在模块 |
| C6 | C | 科研任务包/结果包：任务身份、输入版本、执行设备、权限范围；导入不授予执行权，接收方本机授权后执行 |
| D4 | D | Dream：增量归纳、去重、摘要更新、冲突识别、经验候选；记录资源消耗；撤回/删除向派生数据传播；不扩权 |
| D5 | D | 在线任务调度：执行归属、状态查询、重复执行控制（幂等键 + 归属租约） |
| D6 | D | 工具选择评估：规则 / 大模型 / Jev / Laya 候选在同一任务集上比较，产出选型建议（不定生产模型） |

### W3 集成与验收（全员，约 1–2 周）

- 科研完整链 E2E：导入成果与论文 → 阅读检索 → 批注与研究卡 → 限定资料问答 → 创建并导出任务 → 另一设备执行 → 导回 → 人工接纳 → 关联提纲 → 导出报告 → 退出重开仍在。（C 写测试，B 修 UI，A 验收）
- 失败矩阵：离线、重复导入、两项目隔离、首次导入中断、库升级、索引过期、原文换版、取消、错误态。（A 统筹，各自负责本域）
- OCR 原生三端：Android/macOS/Windows 真机识别扫描论文与报价单。（D，需实机）
- 平台：Android/macOS/Windows 构建 + 真实业务流程 + 文件操作 + 体验。（需用户提供设备，见问题 4）
- 限定资料问答真实模型评测：定位、关键断言支持、应答/拒答质量。（D 出评测，A 审）

---

## 4. 协作规则

0. **禁止共用工作目录**（W0 实际发生过冲突）：每个 Agent 必须在自己的 `git worktree` + 分支中工作，构建产物也各在各的 worktree；主目录只由 A 用于合并。
1. **设计风格**：所有新页面遵循 [docs/design/DESIGN.md](../../design/DESIGN.md)（Folio），只用共享主题 token，不在页面内硬编码颜色/字号。
2. **契约先行**：`muyon_module_api` 只有 A 能改；其他人需要新接口时提 issue，A 在 24h 内合入或拒绝。契约变更后各分支 rebase。
3. **文件所有权**：按第 2 节独占目录；`bootstrap.dart`、`pubspec.yaml` 由 A 合并时统一修改。
4. **分支/PR**：小 PR（< 400 行），每个 PR 附测试与证据类别；A 审查后合入 `develop`，W 阶段门禁通过后合 `main`。
5. **测试**：TDD；每 PR 必须 `flutter analyze` 无问题 + 本包测试绿；不得为通过而改测试。
6. **证据诚实**：构建成功 ≠ 业务验收；合成测试 ≠ 真机；固定语料通过 ≠ 普遍正确。账本中未验证项保持“未验证”。
7. **并行冲突热点**：`bootstrap.dart`（模块注册）、`app_shell/platform_shell`（导航）、`tool_registry.dart`（工具注册）。规避：模块与工具通过各自 plugin 文件注册，宿主只加一行接线，由 A 合并。

---

## 5. 关键风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| supplier_core 存储深度耦合（exchange/share/backup 直接复制 SQLite） | C1 可能超期 | 先做“宿主持有连接 + 适配”，不重写；备份改走 SQLite backup API |
| 无实机 | 第十二节无法验收 | 问题 4 尽早落实；无设备时账本明确标“未验证” |
| Windows WebView2 / ONNX 原生包分发 | 原型与 OCR 在 Windows 不可用 | W1 内先做 Windows 构建冒烟 |
| 设备安全协议自研出错 | 安全漏洞 | 只用 TLS 1.3 + 公钥钉扎，不自研密码学；A 安全审查 |
| 重命名与并行开发冲突 | 大面积合并冲突 | 重命名在 W0 完成后才开分支 |
