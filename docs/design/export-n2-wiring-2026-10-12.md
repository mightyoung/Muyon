# 导出生产接线与 N2 删除确认执行设计（DESIGN-EXPORT-N2，ChatGPT）

基线 develop `ab5506c3`。云端只读，未运行测试。原稿由用户转交，leader A 整理入库（原稿另有 31 份任务草稿正文，本文保留清单与依赖）。Sonnet 先前的调研笔记与本稿结论一致。

**结论：** LE01、02、03、05、06 组件已进基线，但导出生产调用链未接通；LE04 仍有集成阻断；N2 继续使用现有 `delete_section` 与 `sectionDeleteDigest`，补齐受控确认、共同范围守卫、事务内业务回执与恢复查询。

## 1. LE01–14 状态（develop ab5506c3）
| 分片 | 状态 |
|---|---|
| LE01 契约 | 已入基线（`202e44af` + 冻结修复 `bf63985a`）；宿主未启用 `local_exports` |
| LE02 报告准备器 | 已入基线；生产仍走旧 `exportReport` IO 包装 |
| LE03 草稿准备器 | 已入基线；无生产调用方，受控 reader 未实现 |
| LE04 生成与清理 | **未入基线**：`task/le-04-export-staging@58c46f85`、修复分支 `task/le04-independent-blocker-fix-20261011@b4bc0588`（PR #56 integration hold）；Linux 原生适配的目录身份检查与最终 `linkat` 分离，`research/exports` 包含性未证明 |
| LE05 意图与审批 | 已入基线；`ModuleHost` 未注入 provider，确认事实与真实 writer 绑定不完整 |
| LE06 账本 | 有界实现已入基线（与 `d104986d` 逐字相同）；无生产实例 |
| LE07–14 | 未见实现；`research.export.report` / `claim_drafts` 仍 deferred；页面仍走旧 `exportReport` / `exportClaimDrafts`（后者仍取首条非歧义绑定，未用 LE03） |

## 2. 导出生产接线要点
- 补齐：宿主 `hostCapabilityIds` 加 `local_exports` → 科研 manifest 可选声明 → `ModuleHost` 注入 LE05 provider → 宿主整次导出接口（如 `ResearchExportUiPort` → `LocalExportCoordinator`）→ 平台可用性 → 工具与页面调用。不能只删 deferred。
- 身份两层：`parent/exportId`（整次业务关联与防重）；A、每次 B 各自独立 Registry `invocationId/replayKey`。模型来源的 A/B 子调用必须登记进真实宿主调用归属（`AgentContext.factsFor`、`PersonalAgent.hostGrantContext`），父任务取消 / 关闭 / 事实变化后子调用失效。
- 异步准备：在 `ToolRegistry._prepare` 门禁之后、读 `effectIntent` 前加仅宿主可注册的 `ensureFrozen` hook（基线 `tool_registry.dart` 463/464 行间），只冻结一次；approve / invoke 再 prepare 只取回同一冻结对象。三个摘要：`contentDigest`（字节）、拟新增 `preparationDigest`（内容、manifest、字节数、来源、格式、时点、计数、纳入 / 排除、警示）、拟新增 `presentationDigest`（固定卡、准备摘要、审查结果、阶段、目标、覆盖决定）。
- 受控 reader：按笔记实际 document 固定版本读取（不能复用只取 `currentVersions` 的搜索 reader），检查项目归属、托管根、文件身份、预算、实际 SHA，异步边界前后验活。
- 执行链：受理 → 准备 → 固定卡 / review / 人工 A → generate pending → 生成落账 → **先持久化 selectionAttempt 再启动 picker** → 真实回调绑定冻结内容 / 范围 / nonce / epoch / 期限形成 B（交接凭据有期限且单次消费）→ save pending → effect 前验活（**open / truncate 之前**）→ 复制同一字节 → 落账 → 聚合。unknown 不自动重放，迟到取消不覆盖已持久成功。
- 旧入口收口：保留报告与草稿按钮，改走宿主整次门面；`saveGenerated / saveExportFile` 不能作为新门面接入点；缺 port 或平台适配时明确不可用，不回退旧 IO。`exportTask / exportResult / exportSkillExperiment` 本次不扩（注意 `exportSkillExperiment` 会写 `runs.data._skill_export`）。

## 3. LE06 七项遗留
| 遗留 | 处理 |
|---|---|
| target 与实际 writer 强绑定 | 生产只接收宿主构造的 `BoundExportEffect`（审批、scope / epoch、冻结内容、root / target、writer 一次绑定），pending 后、open / truncate 前再守卫 |
| 只读 check 活性 | 保持只读，补取消、期限（推荐 10 秒）、迟到隔离；历史 unknown 由用户显式「从同一冻结内容新建副本操作」（新 exportId、新 A/B） |
| content BLOB 大小与保留 | 摘要与 payload 查询分离；推荐单份 16 MiB、总 256 MiB，可核验终态 payload 7 天后释放，元数据保留，不删用户文件，active / unknown 不清理 |
| rawError 脱敏 | 持久化前改白名单结构化错误；现有「host audit 保留 raw canary」断言按新设计替换 |
| partial_export 呈现 | 部分笔记可导出 = `subsetExport`；已生成未另存 = 聚合 `partial_export` 并同时显示 save 状态与清理 / 未知 |
| 独立 save 投影 | 共用安全 DTO（exportId、phase、saveAttemptId、状态、cleanup、安全错误码、摘要 / 字节数、durable / observation）；`artifactRefs` 仍空 |
| 多实例并发 | 每物理 DB 一个生产协调器，DB 决胜；他实例返回既有事实或 busy / unknown，不接管、不重放 |

## 4. N2：与 REG-3c 共用一条删除语义
- 预览已调用 `sectionDeleteDigest`；但预览 UI 只能刷新 / 关闭，`WritingPage._delete` 仍直接 `store.deleteSection`；科研无删除 `BusinessReceiptLookup`。
- 唯一执行：`research.delete_section(section_id, expected_digest=预览的 sectionDeleteDigest)`；摘要覆盖完整 section 行 + 全部 `outline WHERE section_id=?`（不得加 project 过滤）；语义 = 删章节及其全部关联，证据实体保留。
- 链路：受控预览（不创建批准）→ 冻结 ticket（参数、deleteDigest、request / scope / domain 身份、invocation / replay、展示内容、生命周期）→ `ToolRegistry.prepare → 可信宿主确认 → approve → invoke`（不能照搬导出的 `HostToolAuthorization.review/confirm`，无 intent 时无法签发）→ 同一事务：当前性、预算与写范围守卫、CAS、`checkBeforeEffect`、删除、冻结 changes、插入 applied 业务回执 → 按持久结果展示 → 中断后以原身份只读查核（不重 invoke）。
- **新增收紧（D3）**：实际会删的 outline 行属本次写范围外项目 → 整次拒绝（REG-3c 与 N2 共用守卫）；本项目内但证据不可读 → 可删关联；超预算整次拒绝。
- 助手：`AgentDispatch.executeCard` 由控制器接管，保留原 invocation / replay，避免一次确认执行两次。
- 回执复用 `BusinessReceiptQuery / BusinessOperationReceipt / BusinessReceiptLookupResult` 五态；`notFound` 不证明未执行、不自动重试。

## 5. 实施任务（每项 ≤1 天，测试先行，必须变异）
导出共同组件：E01 LE04 状态机有界集成（未证明适配保持 unavailable）；E02 完整冻结事实与身份；E03 受保护异步准备 hook；E04 宿主能力 / 声明 / provider / 窄接口接线；E05 精确旧文档受控 reader；E06 人工审批 + root/target + writer 一次绑定；E07 分阶段投影与持久异常脱敏；E08 payload 配额与保留（D1）；E09 check 期限与新副本动作（D2）；E10 固定确认卡；E11 selectionAttempt 与 B 可信交接。
平台与入口：E12 / E13 macOS 生成目录与保存面板；E14 / E15 / E16 Android SAF 选择、生成目录、ContentResolver 写入；E17 整次协调器；E18 report 工具 / 页面；E19 claims 工具 / 页面；E20-R / C macOS 验收；E21-R / C Android 验收。E18 / E19 可先以不可用状态合入，验收后按「平台 × 工具」开放。
N2：N01 共同写范围守卫（D3）→ N02 受控预览与执行资格；N01 → N03 删除业务回执与五态查询 → N04 原子删除与回执；N02 + N04 → N05 确认控制器与 ticket → N06 写作页接唯一工具 / N06-A 助手删除卡接线 → N07 提交窗口恢复、取消、迟到隔离。
建议首批并行：E01、E02、N01。

## 6. 未决产品问题（推荐）
D1 payload 单份 16 MiB、总 256 MiB、终态 7 天释放；D2 check 10 秒、只读，允许显式新建副本操作；D3 删除集合含 foreign 行整次拒绝；D4 无宿主门面的 standalone 明确不可用；D5 按平台与工具分别验收开放，report 先行。
