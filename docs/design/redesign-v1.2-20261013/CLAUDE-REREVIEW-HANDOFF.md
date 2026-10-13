# 给 Claude：Muyon v1.2 定向复审交接

请只读复审 v1.2 对你此前正式评审的处理是否真正修补了设计缺口，优先核 B1–B3/I1–I10/S1–S7、执行摘要专题与 AUTH-TRACE-02 增量。不要重新写一份泛泛的全量审查；新增问题应说明由本次修改触发的具体回归。请输出独立中文复审报告和待决定短清单。不得写代码、提交、开或合并 PR、部署、直接联系其他人，也不运行产品/模型实验或声称已运行。

## 1. 固定身份和证据顺序

- 文档分支：`task/redesign-v11-claude-review-20261013`；新目录：`docs/design/redesign-v1.2-20261013/`。先记录实际读取的文档提交完整 SHA，并核下面四原件 hash。
- **设计代码基线**：`01e56cc2d729dab70e1b1def05c3aa93b28f421a`。v1.2 继续沿用该基线，没有把 PR69 代码树或最新 develop 混进来。
- **研究参考证据**：[PR69](https://github.com/mightyoung/Muyon/pull/69)，固定 head `3c9ac395ac8424e9e43b58381fb5001bd1f30821`；发布准备读到 OPEN、未合并。只读其固定版本下的研究报告/片段，不能称已合入设计代码基线。
- **保留的 v1.1 文档提交**：`91dea2e66c340fe55c06421abdc9e3549fea1554`；[原审查包](https://github.com/mightyoung/Muyon/tree/91dea2e66c340fe55c06421abdc9e3549fea1554/docs/design/redesign-v1.1-20261013)。本次只追加新目录，不修改原文件或改写历史提交。
- 发布准备 develop SHA 为 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`。复审时另固定当时 develop 的完整 SHA，单列“后续变化影响”，不要静默替换任何上述角色。

| 原件 | 字节数 | SHA-256 | Library ID |
| --- | ---: | --- | --- |
| [Muyon-Redesign-Plan-v1.2-2026-10-13.docx](Muyon-Redesign-Plan-v1.2-2026-10-13.docx) | 341177 | `e71386564524352f57ce5fdc972d5c2b4665ee33a876ff86b888098df4bdde2b` | `libfile_5e8813b776fc819189fb16495b2bd559` |
| [Muyon-Redesign-Plan-v1.2-2026-10-13.md](Muyon-Redesign-Plan-v1.2-2026-10-13.md) | 240505 | `cef499d4d3b98e087ce8c50a0e3cee02e638815138ca390036a4b6f1ffb91308` | `libfile_dbab674285b48191b1f652ad3ba551ca` |
| [Muyon-Page-Design-Handbook-v1.2-2026-10-13.docx](Muyon-Page-Design-Handbook-v1.2-2026-10-13.docx) | 2927619 | `93aa68f30725757792a795d88e7cd2914f3d4f8f0ff0ed1e4883c4c9a1d1cb11` | `libfile_51864e6e58ac81918d5e3d25839d8edf` |
| [Muyon-Page-Design-Handbook-v1.2-2026-10-13.md](Muyon-Page-Design-Handbook-v1.2-2026-10-13.md) | 175489 | `0c0fa0be8c609f083175c29c15c5f8e9466a6fd0b948539c9e80647bf53a2ce4` | `libfile_257addabe5f48191b126626611cb09d4` |

[校验说明](VERIFICATION.md) 与 [SHA256SUMS](SHA256SUMS) 可复核文件身份。委托输入为 79/71 页，实际 Word 分页未重验；优先引用原 MD 的行号、章节、页面编号，DOCX 页码注明阅读器。两 HTML 浏览副本只用于阅读，原图/版式以 DOCX 为权威。第二册保持 29 主页面，新增/明确 9 子页面，15 组线框。

第一册 §12（MD 1518–1585 行）是本次导航入口，含正式评审 20 项处理、执行摘要专题处理和 AUTH 采纳限定。其“采纳/部分采纳/待决/不采纳”是作者的**文档处理声明**，不能直接算修复。请回到正文、基线代码及原评审逐项检验。该章引用用户转交的 258 行正式报告；本包没有额外 materialize 或发布该原报告。请使用你已持有的原评审核对原意；若无法取得，明确只能按 §12 转述核对，不能宣称逐字比对原报告。PR69 执行摘要/授权片段可通过下方固定链接读取。

## 2. 最新已定语义：覆盖过时研究摘要

1. Electron 桌面、Kotlin Compose Android、Rust 本地离线内核；生成卡本地交互直接，确定性业务动作经可信桥直 Rust。仅需新的理解、生成或规划时再模型；模型调用本身也走授权、投影与网络校验。
2. **全部允许包括此前未用过的新网站/API，免首次目的地和高风险额外询问。** 不要求预选所有端点，不把缺旧 manual 记录、单纯 taint 或 reviewer 风险意见重新变成人审。实际目标、用途、payload 摘要、执行账本仍固定并可审计。
3. 旧 CR-2 taint 强制单次确认和 ADR-0002 新端点逐次询问，必须由 ADR-AUTH-01 明确对新全部允许模式的替代范围/生效版本；旧兼容模式保留原行为，不随重命名放宽。taint/来源追踪、投影、CAS、撤权与账本继续保留。
4. **明确禁止外发、无读取/执行权、撤权、合同合法性及系统/第三方硬限制仍有效。** 真实授权/scope/账本前提无法验证可停止；来源可信度 unknown 与派发效果 unknown 不应混作一律询问。全部允许不恢复旧 grant、不清 capability_hold、不重发结果未知。
5. **Auto 独立**：确定性规则低风险自动、高风险询问、禁止拒绝。其他候选模式、旧配置最终映射、默认与期限仍待决。旧配置损坏不能当缺省，更不能默认升级为全部允许。
6. 用户选择广泛免问仍有提示注入诱导“范围内但不合真实意图”动作的残余风险。可提出收紧替代建议，但标“重新决策建议”，同时评判保留现有决定的最小方案；不能把新端点/高风险必问写成工程细节。

PR69 旧 [SUMMARY](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/SUMMARY.md) 曾写“四档、仅个人账号、不做临时会话/屏幕读取、不设容量、按钮一律新轮次”等“已决定”，与最新 v1.2 不一致。**以本次 v1.2 用户决定为准**；不从竞品附件继承产品授权。只允许指出该历史冲突，不得反向覆盖新版。研究 SQL 唯一键也不是 exactly-once 保证。

## 3. 定向阅读顺序

1. 核版本/hash → 第一册 §12 逐项处理表 → §1、§6 的最新模式与替代 ADR → 第二册“审查输入与修订口径”和 S04。
2. 按以下逐项矩阵读被修改的正文与对应基线源码；对比 v1.1，判断是实际补合同、仅改措辞，还是仍有矛盾。重点读 §5、§6、§8 前置 spike/依赖、§10 反例、第二册 T02/T03/S05/S06/S03.1/A01。
3. 读 PR69 固定版本执行摘要专题与 AUTH 片段，核是否只采能证明的事实、范围是否正确；最后核 9 子页/F11–F15 的映射、跨册一致性和新增回归。
4. 输出逐项结果和未关闭门禁；把文档层修补与工程实施退出条件分开。未做模型、产品或真机验证不得列成通过。

## 4. 正式评审逐项复核矩阵

定位行号对应本包原始第一册/第二册 MD；请给出你实际核实的更精确行号和代码符号，不能只引用本表。

| ID | 本版声称处理与定位 | 复审要回答 |
| --- | --- | --- |
| B1 | 第一册 §6，693–757；第二册 S04，796–837 | 旧 standard/readOnly/custom、read/model/write/outbound、五时长/目的地/消费/撤权盘点是否完整？新 ModeGrant、旧配置保留与新 taint/endpoint 例外能否同时明确，是否偷加首次确认？ |
| B2 | 单元21，353–361；§5，636–674；D05/D06；第二册 S05/S06 | memories/experiences/tombstones/dream_runs/dream_proposals 五类继承和迁移真值是否完整？不是把已有记忆入口当新增；CAS/两级删除/离线整理是增强 |
| B3 | §6，768–793；D04；第二册两类暂停/T02/T03 | capability_hold 与 content_review 的对象、状态、清除权是否真的分离？model 与 tool 两分支均覆盖；confirm/block/unavailable 解释是否遵守全允许而非改词后继续必问 |
| I1 | §5 同一合同、§8 SPIKE-01/M03 | schema 权威源、生成责任、类型/JSON bytes 候选和退出门槛是否足以避免双源漂移？候选不是已验证选型 |
| I2 | §5 稳定意图/摘要、§10 反例 | plan 创建前稳定 intent、Rust key issuer、同 ID 异 payload 冲突、合法再次执行新意图是否清楚？双击/重投递/重启不铸重复业务意图 |
| I3 | 单元22/23，362–377；第二册 W01.1/S03.1 | 原型生产路径、MCP module/bin 是否追踪齐？HTTP MCP 客户端与独立本机只读 stdio 服务分开，不把 Android 客户端说成必用 stdio |
| I4 | §8 919–988，M02→D01a→M03，M14/M18/M19 | 前置授权/合同/恢复依赖是否无环且完整？不能偷改首片只支持每次询问 |
| I5 | §5 记忆；第二册 S06 916–927 | 主题浏览与单条本机确定性编辑是否统一？离线编辑不请求模型，显式管理不被自动记忆关闭误禁 |
| I6 | §5 663–674；第二册 S05 854–863/S06 | 恢复域外单调遗忘凭据先重放后激活，旧备份/rollback、凭据失败、Dream 快照/提案/摘要清理能否防复活？仅写目标不算机制完整 |
| I7 | 第二册 D01.1/D01.2/D01.3，688–721 | name 首片与物料/公司资料/共享发布完整产品区分？首片不暗扩联系人；业务 UI 使用同一 Rust 命令与回执 |
| I8 | 第一册 §7 821–843；第二册 97–120 | 设备交换、消息、专题、呈现三档及知识等旧入口有准确归属？关闭视图不取消、策略真实持久化、不删既有功能 |
| I9 | 第一册 §8 964–988、§9 1068–1083 | 原时间盒、spike、分包区间及等待/返工是否分开？首片与全产品不同；估算不是实测事实 |
| I10 | 第一册 §6 758–767；第二册稳定意图/在途变更 | 自动刷新读集/写集/关联业务条件均无冲突才能重建；同字段与跨字段不变量冲突保留差异，不能靠“异字段”放行 |
| S1 | 原件固定源码锚点 | open/builder/freeze/load 修正是否指向实符号？完整 SHA、文件与行号均核，不复用别版本行号 |
| S2 | 第二册 F01–F15；两册目录 | 15 组线框、29 主页/9 子页是否一致，旧 F07/F09 更新是否匹配正文而非仅增图？ |
| S3 | 第一册 ADR-AUTH-01；第二册 S04 | “允许本批”与“全部允许模式”是否避免同名混用且保留旧消费合同？ |
| S4 | 第二册 S06 四控制 | 自动写入开关只控自动写，显式手动管理/读取/历史检索分别核权，不把三项混成一项 |
| S5 | 第一册双实例/目录锁合同 | Electron 实例协调＋OS 等价目录锁/单 writer，崩溃与旧 writer 互斥；隔离目录可并行，不制造全局禁用 |
| S6 | 新发送/FX 与第二册 S07 | 真实发送/FX 是新增合同；身份 styleText 实际披露与权限分离，不能因名字/风格授 grant |
| S7 | PDF/OCR 候选与验证门禁 | 同字节/坐标/Unicode/旋转 fixture 和许可预算充分吗？单引擎为优先候选，未实测前不能宣称已选或通过 |

## 5. 执行摘要与 AUTH 增量：不要扩大证据强度

第一册 §5 609–635、§12 1549–1580；第二册 A01 266–279、取消/事件重放 210–229、AUTH 1372 起。重点核：

- ExecRun/ExecStep/展示摘要是 Task/Attempt/ModelTurn/ToolInvocation/EffectReceipt 的受控投影，不是新权威账本。迟到摘要/summary_pending/模型失败不改效果事实；确定性计数与模型自由文本的重算/版本/授权 revision 分开。
- 摘要标题、计数、正文、引用、产物跳转均按当前权限投影，撤权清缓存/上下文/队列/订阅。Retracted 只撤展示，不抹效果与审计。
- Cancel requested 不等于 cancelled；派发后 Stop、回执缺失仍 unknown，核对没有证据就不能 StepVerified。scope 内 seq＋epoch＋cursor＋snapshot 和至少一次事件投递不等于全局 exactly-once；replay 不能再次派发业务效果。
- [CL-03 认领](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/auth-trace-02/evidence/CL-03-claim-before-execute.txt)：认领先于执行只支持特定路径、本地唯一键和同账本寿命内重复抑制；认领后执行前崩溃可能零次，重复文案不证明外部成功，更不证明跨设备 exactly-once。
- [GPT-02 参数绑定](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/auth-trace-02/evidence/GPT-02-params-digest-reuse-check.txt)：请求身份/paramsDigest/比较是 Orbit/Codex 系 app-server 审批路径线索，不外推普通聊天；片段不完整处说明未证明规范化与错误返回。
- [CL-04 Code 决定](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/auth-trace-02/evidence/CL-04-notification-approval-args.txt)：ccrNotifTraceId 等字段与日志不足以否定服务端不可变绑定，不能将“未见 digest”写成没有绑定。
- [GPT-04 DIL](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/auth-trace-02/evidence/GPT-04-dil-host-action-gate.txt)：四条字符串/偏移不是完整 URL 规范化与拦截覆盖证明。CL-06 可选 ui.domain 检查与工具列表/跳问分层也不证明所有新网站已授权或全部路径两层硬拒绝。
- [MU-01 决定结构](https://github.com/mightyoung/Muyon/blob/3c9ac395ac8424e9e43b58381fb5001bd1f30821/docs/research/android-reference/auth-trace-02/evidence/MU-01-approval-decide-chain.txt)：PartiallyApplied 是审批合并结果，不是业务部分成功。atomic 仍全成全败，independent 才按逐项真实回执结算。

建议反例：认领后未派发崩溃、重复但回执未形成、同 ID 异 payload、摘要不符拒绝复用、旧批准过期/撤权竞态、派发后 Stop/unknown、旧备份恢复/凭据失败、摘要迟到/replay。请评判这些验收是否完整可执行，不能把建议反例写成已通过。竞品均静态无动态验证，ChatGPT 的 8 动作非完整且 Apps 有 callTool；模型参与不是授权证明。

## 6. 结论分层与输出模板

每个 B/I/S ID 保持原编号，分别标：**设计层已修补、部分修补、未修补、合理不采纳、仍待决、证据不足**。再单列工程退出条件“未执行/需何种证据”；不能因文档写完把 B1/B2/B3 实施门禁关掉，也不能将它们扩大为所有离线盘点/合同工作停工。

新增问题按阻断/重要/建议，附准确册/章节/页面与 MD 行号；代码定位必须带完整 SHA、文件/符号/行。分开事实、推断、已有/新增/待决，写触发、影响、最小设计修改与验收。针对已定模式的替代建议单列“重新决策建议”，不可伪装未定或用户已授权。

```text
Muyon v1.2 定向复审报告
审阅日期/静态只读方式/实际已读与未读范围
文档提交完整 SHA；四原件 hash 核验
设计基线完整 SHA；PR69 固定证据 SHA/状态；复审时 develop 完整 SHA
原正式报告是否实际持有并逐项核对；无法获取时的限定

A. B1–B3/I1–I10/S1–S7 逐项结果
ID / 原问题 / v1.2 修改定位 / 设计层结论 / 事实与推断
剩余最小修改 / 验收建议 / 工程退出条件与未执行状态

B. 执行摘要与 AUTH 增量结果
采纳是否准确、是否超证据范围、新反例和残余风险

C. 新修改引入的阻断/重要/建议
准确定位 / 分类 / 触发 / 影响 / 最小修改 / 待执行验收

D. 可继续的设计或离线工作、仍禁止进入的实施范围及理由
E. 后续 develop 变化影响（与固定基线结论分开）
F. 重新决策建议（若有，保持当前决定方案同时列出）
限制：本次未写代码、提交、merge、部署、运行产品/模型或真机测试
```

另附短清单：其余模式/旧配置映射/默认与期限、屏幕读取、临时会话、记忆容量、个人账号限制等真正未定项，每项 2–3 选项、推荐影响与决策时点。schema 编码、PDF/OCR、遗忘凭据布局是技术 spike；review 理由/旧映射是实施合同冻结，不用这些未定细节重新询问已经批准的新端点免问语义。生产数据、模型费用、外传、设备和上线仍需未来具体任务授权。
