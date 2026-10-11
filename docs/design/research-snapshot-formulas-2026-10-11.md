# 科研快照、科研公式与来源导航（CR-7，ChatGPT 6 Pro）

状态：**设计稿，Q1～Q4 待用户决定** · 依据：`task/decisions-20261011b` @ `b521591` · 只读静态设计 · 原稿由用户转交，leader A 整理入库，保留全部契约、公式口径、任务片与待决事项，代码位置以原稿为准。D2（统一关系投影）、D3（首版同任务同修订对比）、D4（宿主 / 模块声明指标口径）为既定约束；AIUI-7 D1～D7 已由 ADR 采纳，原设计页的「待决」状态已过时。

## 结论
模块提供受范围约束的科研读模型，宿主组装科研快照、登记公式、控制来源导航。三份契约：科研事实、计算、来源与阅读器。
1. 快照读完整对象外壳并附完整性证据；执行状态、接纳状态、任务修订、原始结论、研究评估分开。宿主 `ResearchSnapshotEnvelope` 包裹现有 `DataSnapshot` 及字段可用性、统计总体、对象版本、指标定义、来源映射。
2. 「范围内已读完」与「整个项目已读完」分开；显示窗口截断与统计输入不完整分开（显示前 200 行不妨碍对完整总体精确统计；只拿到 200 行则不能反推总数）。
3. 关系页与引用卡共用纯关系投影器；引用论文、声明冲突、笔记关联、提纲挂接各有独立语义，不统一解释为「证据支持」。
4. 九个公式按固定版本化口径登记；缺失、未读取、零值分开；换基线时 A/B 原值、差值、来源、计算状态成套更新，等待期不显示错配旧差值。
5. 来源解析成功与阅读器展示成功分别验收；`SourceRef` 不能直接改名成 `SourceSpanRef`；阅读器实际展示同一份字节、到页并绘制后才显示「已高亮」；canonical package 无阅读器适配时明确返回「不支持打开」。
顺序：范围与快照基础 → 统一关系投影 → 公式与来源映射并行 → 重算与阅读器。

## 1. ResearchUiPlanningSource
- 现状：`research.read_object` 对 entry/run 返回 `.data`、task 返回 `.spec` 再包进 `data.object`，run 表列的 `status`、`accepted`、`task_revision` 与部分外壳信息没进读取结果；`TaskReceiptUiPlanningSource` 只提取单对象成功回执的顶层标量，嵌套 `object` 不会成为事实。
- 分工：模块 `ResearchSnapshotReader`（或 `ResearchServices` 只读扩展）读真实表与外壳、按已登记格式解析、返回不可变读批次与完整性证据；模块共享关系投影器只做纯投影；宿主 `ResearchUiPlanningSource` 选字段组装 `DataSnapshot`、界面 ID、必显状态、允许动作、科研元数据；宿主公式与来源适配器用同一快照元数据并在发布时复核范围、版本、请求代次。`ResearchServices` 有 scoped store 与 `ensureActive`，但需补助手对象白名单校验。
- 按用途白名单读取：`projects`（标题、问题、下一步，建议与基本信息分开）；`entries`（本地 ID、项目、kind、title、来源 ID、明确修订、主张正文；本地对象身份与 `.data.id/.rev` 研究身份分开）；`tasks` 与按需 `task_imports`（`tasks.current` 为已证明最新修订，`taskRevisions` 为明确授权的历史修订；命令与路径只是数据）；`runs` 经 `task_id + task_revision` 关联（表列 / 外壳为状态与归属依据，`.data` 同名值不一致保留冲突诊断；metrics、产物清单、原始 conclusion、`workbench_assessment` 独立）；`sections`、`outline`（精确段落 ID、标题、层级、顺序、论点、支持程度；标题与「第几节」不是身份；挂接存在 / 目标可解析 / 证据支持论点是不同事实）；`documents`、`notes`、`paper_bindings`（普通批注不自动升级结构化证据，已存的 `hash_ok` 不代替本次字节复核）；`canonical_object_map`、`rk_cards`、`rk_revisions`、`rk_documents`（canonical 与普通导入文档各用真实存储，一个查询没返回不能判定另一类不存在）。`FactState.verified` = 宿主确认该版本记录保存了这个值，不代表主张科学上已验证。
- `ResearchSnapshotEnvelope` 组成：`DataSnapshot`、`factAvailability`、`collectionCoverage`、`statisticInputs`（完整统计输入，与展示窗口分开）、`objectManifests`、`metricDefinitions`、`relationProjection`、`sourceBindings`；与 `DataSnapshot` 绑定同一 `SnapshotRef`，公式、导航、当前 UI bundle 取同一份 envelope，禁止按相似 ID 拼接。模型需要看到的缺失、截断、定位状态由宿主派生为标量状态 fact 并加入 `requiredBindings`。没有真实文档片段时不制造 `SourceSpanRef`（数据库记录来源用「完整 `ObjectRef` + 字段路径」证明）。
- 字段可用性（现 `FactState` 无 missing / notRead，`UiCollection` 无总体与截断，需新增契约并接入校验）：`present`（含 0、false、空串）、显式 `null`、`missing`（不补零）、`notRead`（不推断缺失）、`readFailed` / `invalidValue`（不当空集合）、`notApplicable` / `conflict`。集合记录授权总体（所选对象还是某项目 / 类型 / 过滤 / 修订策略下的完整 inventory，附范围身份与成员 / 查询依据摘要）、读取完成度（complete / partial / notRead / readFailed；中途失效属发布拒绝）、展示窗口（行数、是否截断、稳定排序、游标）。示例：完整读 512 条显示 200 条可精确统计；只取得截断的 200 条只能显示「已加载 200 条，尚未完整读取」。
- 范围：科研 `scopeCandidates()` 只列 project / document / entry，task、run、outline、section、card 为 `inGlobalScope:false`，工作区范围只在已有枚举中按项目过滤。首版保持现默认范围，由宿主显式选择所需科研对象；项目总量需范围 owner 提供有覆盖证明的 inventory 能力，`ResearchUiPlanningSource` 不得拿到 projectId 自行查整个项目。`requireCurrent` 只复核可解析，不等于属于助手白名单。
- 版本：task = 修订 + 实际投影的规格；run = 任务修订 + 运行内容摘要（`revisionRef` 不是运行修订号）；entry / project = 原摘要 + 新增外壳字段的投影摘要（现 entry digest 只覆盖 `.data`，project digest 只覆盖标题问题下一步）；section / outline = 真实行摘要；document = 原始字节摘要；canonical card = 明确 card revision + 内容摘要；计算 / 关系 / 来源 = 公式、指标定义、关系规则、解析版本与完整性元数据。相同语义输入返回稳定 `SnapshotRef`（规划流程会二次读取比较版本，时间戳与随机 lease ID 不应造成换版）；影响事实或计算的变化产生新版本；版本相同不代表权限仍有效。数据库与文件系统不是共同原子事务，文件异步读取解析后重查身份、摘要、范围。
- 与询价共用：活跃模块与 workspace authority 前后复核、`ObjectRef` 身份版本摘要核验、事实与建议分开、显示预算与只读降级、必显状态与绑定校验、发布代次控制（参考询价只读快照与本体卡适配器；CR-7 提到的 `inquiry_ui_planning_source.dart` 在该提交未合）。科研保留自己的版本策略、研究语义、指标声明，不照搬询价「revision 与 digest 同时存在」的要求。

## 2. D2 统一关系投影
- 现关系页登记平铺引用（`claims.paper_id + paper_rev`、`papers.source_id + source_rev`）与嵌套引用（`claims.conflicts`、机会的 supports / refutes、实验 plan_ref 等），并处理运行到任务修订、笔记到条目、提纲到证据。抽成模块内纯投影器，由关系页、`research.relations` 和快照共用；输入为已授权已固定版本的不可变记录、格式与规则版本、带完整性证明的身份索引、已知未读 / 失败 / 范围排除状态；不持有数据库、文件、搜索或模型回调。身份索引：研究记录 `项目 + kind + sourceId + revision`；本地对象 `项目 + objectType + localObjectId`；canonical 用经真实映射确认的 `ObjectKey`，不与本地 ID 混用。
- 输出：已解析边（`edgeId`、完整 `fromRef/toRef`、`relationKind`、原始指定目标、字段路径与位置、快照版本、规则版本）；未解析引用（`referenceId`、来源对象、关系类型、可展示的原始目标描述、字段位置、结构化 `reason`、快照版本）；重复声明保留 `occurrences`；更新提示仅在确知存在更新修订时显示，目标仍固定原修订。类型分开：`claimCitesPaper`、`claimDeclaresConflict`、`paperUsesSource`、`noteLinksEntry`、`outlineCitesEvidence` 等。引用不证明支持；声明冲突不等于系统判定互斥；笔记关联与提纲挂接不升级为支持 / 反驳；解析成功的冲突主张关系不是 `FactState.conflict`；canonical `CardRelation`（无目标修订）与 `rk_conflicts`（卡片版本冲突表）不混入 `claims.conflicts` 或论文引用计数。
- 未解析原因：`missing_target_id` / `missing_target_revision`（不取最新、不按标题补）；`invalid_reference_shape` / `invalid_revision` / `unsupported_target_kind`；`duplicate_target_identity`（不选第一条或最新）；`ambiguous_local_identity`；`target_inventory_incomplete`（窗口里只有一个候选也不能证明唯一）；`target_not_read` / `target_read_failed`；`target_missing_in_scope`（只有完整授权目标域读完仍无精确目标才用）；`unavailable_in_scope`（不为区分无权与未导入而向范围外探查）；`target_changed` / `scope_changed`（不发布旧边）。
- 抽取时须修正：坏引用被 `whereType<Map>()` 静默丢弃，应给形态诊断；未解析文案合并了不同原因，应分别编码，不能把窗口没出现的对象称为未导入；运行节点键 `run:${run.id}` 与提纲裸 `evidence_id` 匹配不一致，共享投影按真实本地身份解析。

## 3. 九个公式与 D4
- 共用合同：`formulaVersion = 1`，只接受宿主登记的输入绑定；模型只能选已有 computed ID，不能提交表达式、结果、总体或单位。计算绑定当前 `SnapshotRef`、输入对象完整引用、总体与完整性证据、公式版本、指标定义版本、A/B 选择与参数代次。业务数据不足或数学不可算 → `null` 计算值 + 必显原因 + 保留原值；未知绑定、篡改、范围或版本错配 → 拒绝候选。computed 须为标量，多分组统计拆成多个标量实例。

| 公式 | 输入与计算 | 输出、单位、去重 | 缺失与零值 |
|---|---|---|---|
| `entry_count_by_kind` | 完整授权 entries + 宿主登记 kind | 每 kind 一个整数，按本地 entry 去重，「条记录」；含独立导入的历史修订，不按标题或研究 ID 合并 | 完整总体中确无才为 0；未知 kind、读取失败、总体不完整不吞 |
| `task_count` | 已证明最新修订的 `tasks.current` | 按项目 + 逻辑 taskId 计一次，「个任务」 | 无 latest 证明不称当前任务数；选中历史修订不补 0 |
| `artifact_count` | 某固定运行的完整 artifacts 清单 | 按模块路径规则规范化后 `runId + path` 去重，「项清单产物」（清单项数） | 明确 `[]` 为 0；缺清单、未读、畸形不可算；文件是否存在另列（现工作区把缺 artifacts 显示成 0，不继承） |
| `run_metric_delta` | A、B 完整运行引用与 metric fact，同项目同 taskId 同 taskRevision 同指标定义；A−B | 有符号有限数，单位为指标声明的差值单位 | 两侧有效零得 0；任一侧缺失、未读、非数值、非有限、口径不齐或溢出 → 不可用，保留原值 |
| `run_metric_pct_change` | 同上，B 为基线；(A−B)/B | 无量纲 ratio（单位 `1`），百分比由宿主 formatter 转一次 | B 为 0 或 −0.0 不可算（含 A=B=0）；负基线仅在口径允许时用，仍除以 B，不改 `abs(B)` |
| `evidence_count_for_section` | 精确 section 引用 + 该段完整持久 outline 挂接 | 按 `(sectionId, evidenceId)` 去重，「条挂接」（不是有效支持证据数） | 完整读取无挂接才为 0；目标未读、歧义、失效另列 |
| `section_support_counts` | 完整授权 sections + 已登记 support 枚举（unassessed / supported / partial / weak / contested） | 每枚举一个整数，按 sectionId 去重，「个段落」 | 确认无成员才为 0；缺 support 或未知枚举不放进 unassessed，明示未知分类 |
| `accepted_run_count` | 完整授权 runs 的表列 / 外壳 accepted | `accepted == true` 的 distinct runId，「次已接纳运行」；不加 completed / supporting / 最新修订过滤 | 全部明确读取且无 true 才为 0；未知不当 false |
| `claim_link_count` | D2 投影 + 宿主固定 relationKind、方向、焦点范围 | 已解析有向边，按关系类型与两端完整身份去重；论文引用与主张冲突分别实例化，默认展示论文引用 | 投影完整后可为 0，同时显示未解析状态；投影未读或不完整不补零 |
另：「所选修订中的最大值」不能替代「该任务最新修订」证明；目标未读不影响「持久挂接存在」，只有完整授权目标域确认不存在才称悬空；已解析关系为 0 不表示没有引用或冲突声明。
- D4 指标口径：由科研模块登记代码 / 受信模块元数据声明，宿主采纳、固定版本、绑定到任务修订；导入包的单位字符串、模型解释、同名 metric key 都不能单独构成可比性依据。声明包含：身份（metricDefinitionId、版本、摘要、原 key、显示名）；数值表达（类型、单位、尺度编码如 0～1 比例或 0～100 百分数）；可比性（定义、数据集或评估分割、聚合与归一化、分母或窗口）；允许运算（差值、相对变化率、差值单位）；显示（有效精度、舍入、ratio→% 规则）；适用范围（来源、项目、任务、修订）。数值策略独立版本化：支持整数与有符号有限数；数字字符串只在声明了严格编码时解析，不普遍强转 `"82%"`；运算前后检查有限性；显示舍入不改原值；差值不叫「提升」，不据正负判断优劣、显著性或假设成立。`Metric` 适配器现只转文本附单位，ratio 0.25 须经宿主 formatter 显示为 25%。
- library-2 重算最小接入七项（现注册器只有 5 类公式，slot 仅 fact / uiState，输出固定 string，输入要求 String 且用供应链无符号十进制政策；adapter 拒绝 library-2 且只枚举节点直接绑定的 computed）：① 增科研固定公式与输入类型（整数计数、有符号有限数、统计输入引用、受限选择器），不放宽询价字段；② 重算输入增加独立冻结的 `currentSelections`（library-2 Choice 发 stringList 在独立 selections 层），校验键集合、类型、单选多选与候选 membership，不把 List 塞进 `initialUiState`；③ 换 A/B 时先按合法选择重建 A、B 原值 fact 再算差值，不出现「新差值配旧原值」，新指标只来自宿主已登记集合；④ 枚举 collection cell 中的 computed 一并重算，禁止复制旧值只改 `inputVersion`；⑤ 每次重新生成 computed evidence 与状态（单位、来源、未核验依赖、不可算原因、coverage）；⑥ 读取并发布同一 accepted bundle，完整比较 `baseSnapshotRef、draftRevision、hostGeneration、sourceGeneration、permissionGeneration、scopeKey`，快照、intent、plan 一起推进，不扩大动作权限；⑦ 修改基线后立即显示「等待重算」，不在新选择下摆旧差值（现 computed 解析只比版本，识别不了「选择已改、快照未发布」窗口）；旧结果保留时连同旧 A/B 标签作为旧快照，取消、失败、失效后不恢复成当前结果。

## 4. 来源导航
- 三层证明分开：持久引用（引用了哪个文档版本、页、文字；不代表原句一定存在或材料支持结论）；来源解析（同字节版本中的匹配与位置；不代表阅读器已打开、到页、高亮）；阅读器回执（实际展示了哪份字节、到哪页、是否绘制；不代表科学主张已验证）。`SourceRef` 含 canonical 文档身份、字节摘要、0 起 pageIndex、quote、前后文、parserVersion、可选坐标，无文本 offsets；`SourceSpanRef` 要 originalText、start/end——不能直接改名转换。
- `sourceBindings` 以 `SnapshotRef + sourceBindingId` 为键：引用拥有者（完整来源记录 ObjectRef、citationId、card revision）；文档身份（完整 ObjectRef，canonical 保留 ObjectKey 与真实 local mapping，标明 canonical / legacy）；持久锚点（完整 SourceRef；legacy 用独立真实本地锚点）；版本（字节摘要、实际解析版本、来源记录版本）；片段证据（可选 sourceSpanId、同次解析原文片段、页内 offsets 与片段 offsets 映射）；状态（解析状态、reason、matchCount；阅读器能力与展示状态另列）；范围（workspace、任务范围、模块与权限代次、请求 ID）。canonical 文档须经 `canonical_object_map` 确认本地归属再按对象键与摘要读 bytes 复核 SHA-256（originProjectKey 不是本地 projectId）；legacy 无映射时不拼造 ObjectKey，只读导航中不自动登记或迁移；`sourceDigests` 按 artifactId 索引，宿主登记的 artifactId 在整份快照内唯一并映射回真实模块身份。
- 生成 SourceSpan（首版有界原文片段 + 页内 offsets 映射）：核验来源记录与文档在当前范围 → 取固定摘要的原始 bytes → 模块已有 resolver 解析同一份 bytes → 从该次解析的未修改文本截片段 → 记录引用在片段中的半开区间与片段到原页文本的映射 → `SourceSpan.page = pageIndex + 1`。offsets 用 UTF-16 code unit；无段落定位能力时 paragraph 为 null。**不能把保存的 quote 直接放进 originalText 并填 `0..quote.length` 冒充原文证明。** `exact`、`uniqueText` 可物化 span（uniqueText 不承诺几何高亮）；`pageOnly` 不造区间；零 / 多匹配不造确定片段；缺失、换版、范围失效不补造、不用新版代入。现 `CitationResolution` 不返回实际解析文本与版本，需模块补与本次 resolution 绑定的片段投影，宿主不能另读「当前路径」拼接。
- 两种阅读器入口（拟定）：「打开文档」输入 snapshotRef、宿主 documentBindingId、NavigationAnchor、请求 ID，阅读器实际就绪后显示「已打开文档」；「核对这处引用」输入 snapshotRef、sourceBindingId、NavigationAnchor、请求 ID，调用方不能覆盖页、quote、contexts、digest，分别报告引用解析、实际到页、实际绘制。`NavigationAnchor` 只负责恢复会话、卡片、滚动，不携带授权。结构化结果：请求 ID、快照版本、实际文档身份与摘要、`resolution` 与 reason、`presentation`（未打开 / 打开中 / 已打开 / 已到页 / 已绘制 / 不可用 / 取消）、实际物理页。每次异步返回、保存返回现场后、进入阅读器前、发布回执前复核范围与请求代次；返回原对话恢复位置与草稿，不重放批注保存或写作挂接。
- 必须补齐：文档版本策略不兼容（通用导航要求 revisionRef 与 contentDigest 同时存在，科研文档 pin 要求 revisionRef 为 null、digest 非空；由模块类型声明正确策略或用明确科研入口，不填 `"latest"`、0 或摘要充当伪修订）；解析字节与展示字节一致（resolver 用核验过的 bytes，ReaderPage 经文件路径打开 PDF，需同字节输入或不可变文档 lease，展示回执绑定摘要）；exact 文案要等到页与绘制回执（现 banner 根据 `ExactMatch` 直接显示「已精确定位并高亮原文」）；canonical package 无阅读器适配（模块返回 null，ArtifactPreview 只处理 knowledge），应返回 `reader_adapter_unavailable`：「来源记录已保留；当前阅读器尚不支持打开这类导入文档」，与来源缺失区分。
- 定位状态：exact（实际绘制后才「已高亮」）、uniqueText（文本唯一，无高亮位置）、pageOnly（保留无文本层、空引句、版本不符、上下文不符等原因，实际到页后才「已到页」）、零匹配（「在该物理页未找到原句」）、多匹配（「找到 N 处，无法唯一定位」，不选第一处）、pageUnavailable（不夹到首页末页报成功）、missingSource、staleVersion（不换新版继续显示旧高亮）、范围或会话失效、readerUnsupported。现 resolver 先数出现次数，不等于 1 即 ambiguous，再查上下文——不能声称能用上下文从多匹配中消歧；`uniqueText` 在现 QuoteLocator 适配中被折成 PageOnly，宿主须保留原始解析结果。

## 5. 任务片（拟定，未实现）
| 片 | 范围 | 依赖 | 主要拒绝路径验收 |
|---|---|---|---|
| CR7-S01 范围与快照基础 | 科研对象选择、总体证明、envelope、字段可用性、稳定版本、预算；保持 global 默认 | 无 | 选中项目不能扩出运行 / 段落；所选完整不能报项目总数；同内容重读版本稳定；范围撤销使旧 lease 失效 |
| CR7-S02 科研只读模型 | 读完整外壳与必要表，输出类型化记录、状态、字段 manifest | S01 | `.data` 与表列不一致不静默覆盖；缺 / 未读 / 零分开；历史任务不冒充最新；canonical 与 legacy 不互相冒充缺失 |
| CR7-S03 共享关系投影 | 纯投影器，关系页、relations 工具、快照共用 | S01、S02 | 缺修订、重复身份、坏引用、目标域截断分别给原因；不探查范围外邻居；修正 run 与 outline 身份匹配；引用不升级为支持 |
| CR7-S04 指标声明与九公式 | 固定公式、统计口径、有符号数值策略、版本化指标定义与 formatter | S01、S02；关系公式依赖 S03 | 非有限、单位或定义不一致、零基线不可算；完整空集合才真零；挂接与清单路径按合同去重；未知 support 不归未评估 |
| CR7-S05 来源映射与片段投影 | sourceBindings、canonical/local 映射、同次解析原文与 offsets | S01、S02 | 伪 source ID、身份错配、错摘要、无区间、越界页码拒绝；无 span 仍有正确状态；只读导航不隐式登记 |
| CR7-S06 library-2 重算 | 冻结 scalar 与 selections、重建 A/B 原值集合、递归收集计算单元格、更新 evidence、完整发布 | S04（用 S01 envelope） | Choice 非法 ID 或多选形态拒绝；集合中的 computed 也重算；第二次编辑、迟到回调、权限代次变化不发布旧结果 |
| CR7-S07 两个科研导航入口 | 文档 pin 策略、打开文档 / 核对引用、返回现场、结构化结果 | S05 | 不伪造修订；不接任意路径；来源记录与目标文档都复核范围；取消后不继续打开；缺适配器明确降级 |
| CR7-S08 阅读器同字节输入与回执 | 文档输入 lease、就绪 / 到页 / 绘制回执、请求代次 | S07 | 解析 A 字节而阅读器读 B 字节时拒绝高亮成功；exact 但未到页或未绘制不报成功；中途撤销使回执失效 |
| CR7-S09 canonical package 阅读适配 | 阅读器消费已核验 canonical bytes，接同一回执合同 | S08 | 固定版本打不开不换新版；不以项目概览或卡片详情冒充原文；可独立排期 |
| CR7-S10 三种呈现一致性 | 交互卡、只用文字、固定页面共用事实、公式、来源合同 | S02～S08（S09 未完成验降级） | 同输入边、状态、计算一致；切换呈现不丢未知状态；返回与恢复不重放写入；等待期间无新基线配旧差值 |
端到端合成案例：负值与零基线（A=−5、B=−10 → 差值 5、ratio −0.5；A=B=0 → 差值 0、变化率不可算）；显示截断（完整 512 显示 200 vs 只取得截断 200）；全部引用未解析时「已解析 0 条」同时显示未解析声明；换基线竞态（B1 未完成切 B2，B1 迟到结果不发布、不出现在 B2 标签下）；来源展示竞态（解析 exact 后换版、撤权、阅读器失败或未绘制均不显示「已高亮」）。

## 6. 待用户决定（附推荐）
| 编号 | 事项 | 推荐 |
|---|---|---|
| Q1 | 项目级完整科研 inventory 是否进首批 | 先做显式科研对象选择与范围内统计；项目级 inventory 作为独立范围 owner 能力接入，未覆盖时显示「项目总量未读取」 |
| Q2 | 是否采用九公式的具体计数口径 | 采用 v1：entry 计本地记录；task 计已证明最新修订的逻辑任务；artifact 计去重清单项；evidence 计持久挂接；claim 按关系类型分别计已解析有向边；以后改口径升版本 |
| Q3 | canonical package 阅读器适配是否进首批 | 独立安排 S09，前面的快照、公式、来源状态与 legacy 导航先交付；S09 完成前明示「不支持打开」 |
| Q4 | 来源正文默认进规划输入的粒度 | 只给有界、核验后的原文片段与必要上下文；整页正文留在阅读器按需读取，宿主保留完整 offsets 映射，片段预算统一配置，超限显示截断 |
