# MuSpace 规格修订处置记录

2026-10-03 · 修订2 · 范围为书面规格、自审及本地提交；未运行产品测试、改兄弟仓、装工具链或创建外部CI。对应[主规格](../superpowers/specs/2026-10-03-muspace-v0.1-design.md)、[PRD](../superpowers/specs/2026-10-03-muspace-v0.1-prd.md)、[复用矩阵](../superpowers/specs/2026-10-03-muspace-reuse-matrix.md)。

“采纳”指已写入规格；“调整”指按实际证据/用户既定需求收敛建议，不代表取消需求已获批准。P2原意见包含多项相关建议，下表合为9组并逐项说明，避免遗漏。

## 审查处置：2 P0、10 P1、9 P2

| 编号 | 处理 | 修订与证据/理由 |
|---|---|---|
| P0-1 现有资产与选型 | 采纳 | 推荐A外壳＋现模块；独立app/DB，namespace引用与typedadapter。实际读取科研两规格一计划、主dirty分支/worktree、询价Drift DAG及hubfix sqlite3/siq_mcp。复用矩阵列实现/规划/测试分层，不重写乘法，不搬lib/freeze计划。E01/E02/E03；ResearchCase只有首测试，未称全部升级 |
| P0-2 PRD/规模/发布范围 | 调整 | 一页PRD R01–R11，规模/性能为待测目标；建议Mac+Android首发、Windows构建兼容。完整IM/OCR/Dream/Laya/加密等后续独立规格待审，用户路线保留。传包先复用与系统分享，TLS未过则关闭网络入口，不让IM阻塞科研；主§1/6/8 |
| P1-1 需求追溯与已有阅读器 | 采纳 | PRD逐项到断言/章节；pdfrx2.6.5/engine0.6.1来自pubspec/lock且PdfViewer.file源码存在，默认复用。metadata人工离线、DOI/Crossref显式网络；BibTeX/RIS/Zotero后置理由与格式范围明确；主§5，矩阵E01/E02 |
| P1-2 基础设施过多 | 采纳 | 领域事实/修订为主，外壳不双重revision；本地事务operationId，不泛化unknown；5公开科研工具、固定检索生成核验保存；MCP注解仅描述，E03有真实只读openReadOnly；Dream/Laya后置；主§2/4/8 |
| P1-3 内容锚点 | 采纳 | PDF digest＋物理page＋exact/prefix/suffix＋可选bbox/position/parser；标题作者独立。W3C借结构不保证重复引句/OCR自动唯一重锚，多候选需确认；主§3 |
| P1-4 包与手机定位 | 采纳 | 原PDF、锚点、必要解析快照和parser版本进manifest；兼容手机直接使用快照；不兼容降级原页，旧offset不套新解析；无原文包预告缺定位；主§6 |
| P1-5 修订谱系与去重 | 采纳 | 新交换卡/笔记全局revisionId+parents，本地整数展示；旧领域native ID不重编号；去重键不含digest，同revision异digest冲突，ancestor快进/divergent保留；询价DAG为已核验开发基线参考，非成熟发布声明；主§3/矩阵E03 |
| P1-6 授权粒度 | 采纳 | endpoint identity×论文ID/content digest×期限×数据类别的出站授权；每次复查并记录contentHash。覆盖/删除/导出/发送精确动作inputDigest另审；主§5 |
| P1-7 schema/删除缺口 | 采纳 | 工作区创建切换与模块绑定、阅读进度、chunks/modelprofiles、卡Markdown+结构citationRefs明确责任；软删即时过滤到显式purge、无引用blob回收及晚到结果阻断；无首版memory表；主§3 |
| P1-8 状态不一致 | 采纳 | 只保留导入/索引queued/running/succeeded/failed/cancelled；写入校验→事务提交→读回，commit后失败不虚称撤回；无模型即时不可用，用户重试而非默认等待；外部unknown先核对；主§4 |
| P1-9 LAN/聊天概念 | 采纳 | 本人设备互传与双方在线1对1分开，排除群聊不推断只可与自己会话。IM保留后续规格；文本/链接传输不冒充IM；发现开关与前台已确认连接生命周期区分，后台无常驻承诺；主§6 |
| P1-10 gateway可实施边界 | 调整 | 仅验证OpenAI-compatible chat/completions非流式文本子集，Ollama/LMStudio按版本验证。回环默认不开放LAN；Ollama本地API无鉴权且可使用云模型，需检查实际执行模式，不能以localhost证明离线。跨设备认证TLS受控adapter、Android本地LLM后置；主§5/官方认证来源 |
| P2-1 询价DTO与规则 | 调整 | 去掉无实际领域依据的cost.calculate乘法工具。询价已有物料单位快照、十进制价格、税/日期/预算与修订，按选定模块规则复用，不用新DTO替换；完整接入后续；矩阵E03 |
| P2-2 FTS/生成退路 | 采纳 | bigram/英文数字词、有限OR候选、BM25前scope过滤、短语/覆盖率筛选、长句噪声回归；FTS/可选向量不达标退关键词引用，缺证据不生成有依据回答；主§5/PRD R04–05 |
| P2-3 向量引擎与性能 | 调整 | 小语料Dart精确cosine可对照，E5仍候选，不写毫秒事实、不强制sqlite-vec。索引/model/tokenizer/pooling/normalization版本需固定；后续收益验证再启用；主§5/8 |
| P2-4 OCR性能与分期 | 调整 | Paddle家族保持v6_small/tiny/v5_mobile方向，OCR独立增量；移除Android5秒p95硬承诺，不从Mac/M4均值推手机，仍要求质量/几何/冷热分位/RSS/许可证据；主§8 |
| P2-5 TLS身份/网络权限 | 采纳 | 普通CA链/hostname/SAN＋pin；自签专用peer验证绑定票据/identity/地址服务且禁global ignore，未验证不开放网络传包。列MulticastLock释放、mac entitlements/本地隐私、Win防火墙门槛；主§6/8，当前HTTP源码E01 |
| P2-6 加密与数据风险 | 调整 | 建议应用级加密后置，但私有目录、系统文件权限、secretstore必需。明确明文DB/附件/备份与同用户进程风险，个人有权存储资料边界待审；若高机密保护需独立加密规格后再发布，不用泛称“敏感资料”门槛；主§8 |
| P2-7 术语/视觉 | 采纳 | Dream/Laya/shadow含简短定义与后置界限；DeepSeek Harness仅原助手交互参考，不是依赖；移除archify流程名和品牌拼贴，改页面线框与视觉token，保留既有科研关系入口；主§7/8 |
| P2-8 长期规格与自含证据 | 采纳 | 会话授权流水/自审移本记录，主spec保长期产品约束；精选复制合成Android记录、Vue未验边界及分层verification摘录至docs/evidence，原文sha256与日期/来源在manifest，不复制个人截图；E01–E04 |
| P2-9 可测体验/助手空选择 | 采纳 | 320/390/430px、200%字号、返回栈、键盘焦点、语义标签、减少动效有断言；未选论文先选择或显式普通解释，不擅用全库/联网；PRD R10，主§7 |

## 事实核对与不采纳的推断

- 不采纳“科研PDF与原生文件路径全部未验收”的笼统判断：旧verification与2026-10-03单Android合成记录分层，后者覆盖PDF打开/页码笔记、任务导入、结果与Markdown保存，但不覆盖跨设备网络、精确回跳或桌面。
- 不采纳“全部Case升级已完成”或“旧同机冲突已经正式消失”：worktree有Task1修复提交，Task2首测试未实现依赖；本轮没有新的release真机回归证据。interrupted来自任务交接而非一份执行通过报告。
- 不采纳“supplier_core/siq_mcp/DAG已是一份稳定接口”：实际两份仓/基线分别是Drift和sqlite3；原源码/验收矩阵仍有平台与规模缺口。
- 不采纳“现有HTTP或pinning单独即安全”“桌面平均可代表手机p95”“localhost即本机推理”推断；均以实际运行/验证门槛约束。

## 自审结果与待审决策

自审覆盖21项编号、PRD R01–R11追溯、相对链接、引用/谱系/删除/状态与权限一致性。已将论文元数据修订与内容锚点分开；将旧领域revisionRef与新增全局卡修订分开；将范围授权与单动作确认分开；ACK、导入与已读不混用。本轮只读核验历史，不新增产品测试通过声明。性能均为待测目标，OCR没有无依据硬承诺。

待用户决定：A接入方向及Mac/Android首发建议；Windows构建兼容等级；完整IM/Paddle/Dream/Laya/加密等独立分期；首版明文个人单用户资料边界；规模和性能目标。领域分支候选及任务协同将在获批后的计划审阅中明确，不在当前文档擅自合并或停止原任务。

Git边界：提交前以`git -C /Users/muyi/Downloads/dev/muspace rev-parse --show-toplevel`核对本仓，只暂存本轮具体文档/证据；已有.DS_Store留原状。本轮不修改、清理、暂存或提交`/Users/muyi`父Git，不推送。
