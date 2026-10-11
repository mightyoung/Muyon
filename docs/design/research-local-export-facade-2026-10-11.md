# 科研本机导出门面设计（CR-17，ChatGPT）

基线 `task/cr-15-17-chatgpt` @ `1a964df`。云端只读，未运行测试；除「现状」外均为实施建议。原稿由用户转交，leader A 整理入库，代码位置以原稿为准。用户已定（ADR-0001 科研 7 问题 (1)(2)）：模型不传路径；宿主先写 `<科研目录>/exports`，再经系统另存为选位置；允许根每次导出选一次，不持久。

**结论：** 冻结导出内容 → 确认并写入科研 `exports` → 系统另存为选择本次目标 → 独立审批并保存。两项工具归 `external / outbound`，`ToolEffect.export`，人工一次性审批；模型只提交业务对象 ID。回执分开记录「本机文件已生成」与「已保存到用户所选位置」，取消另存为、目标写入失败、结果未知不得混成一次成功。只有冻结内容、两阶段一次性审批、本次目标能力、回执与失败恢复都闭合后，才开放 REG-3e-b 两项导出。

## 1. 接口
- 现状可复用：`workbench_app.dart:191-208` 已用 `<rootPath>/exports` + `FilePicker.saveFile`，取消保留本机文件。需拆开的是 `exchange.dart:564-660,1128-1195`：领域导出器把生成内容与写文件放在一起；新门面只提取内容生成，文件写入归宿主。
- 模型参数：`research.export_report` 只有 `project_id`；`research.export_claim_drafts` 只有 `project_id` + 非空 `note_ids`。`additionalProperties: false`；拒绝路径、目录、URI、文件名、允许根、覆盖开关等任何额外字段；`note_ids` 空项 / 重复整次拒绝（受限 schema 不支持 `uniqueItems`，在运行时检查，`tool_registry.dart:1113-1131`）；格式固定（报告 Markdown、草稿 JSONL）。
- 宿主内部：`prepareExport`（只读，冻结字节、SHA-256、来源清单与修订、实际包含的去重对象计数、草稿排除项与原因、警示）→ `stageExport`（审批 A，写入 exports）→ `selectSaveTarget`（系统另存为，得到本次 `SaveTargetCapability` 或取消）→ `saveStagedExport`（审批 B，只复制同一份字节）→ `readExportReceipt`（只读查核）/ `cancelExport`。确认后不得重新生成另一份内容；不能只绑项目 `contentDigest`（它只覆盖标题、问题、下一步，`research_module.dart:522-535`）。
- 文件名：宿主生成 `report-<exportId>.md`、`workbench-claims-<exportId>.jsonl`，不拼项目标题或原始 ID（现草稿名精确到秒会碰撞）。用户可在系统面板改最终名，回执记录平台返回的实际名。
- 「允许根每次选一次」落实为：本次能力只允许写用户在系统另存为中选中的这个文件，不扩展为整个目录；每次新导出 / 重新另存都重新打开面板。macOS 以保存面板返回的文件 URL 与访问能力为准、不存书签；Android 用 SAF 文档 URI 经 `ContentResolver` 写入，不转路径、不持久授权。`PickDirectory` 只返回字符串，不能证明写权限。

## 2. 授权与确认卡
- `OpKind.external`、`ToolEffect.export`、`ToolAccessLevel.external`、outbound、人工一次性审批；不提供目录持久授权、「本次对话允许」「始终允许此目录」；只读模式或 outbound 关闭时不提出不执行。人工审批走 `HostToolAuthorization.confirm → ToolRegistry.approve`，不得借 `AssistantGrant.once`、清污损或伪装 `pureLocalWrite` 绕过（污损任务不能匹配 write/outbound grant，`grant.dart:77-110`）。
- 新增 `DestinationRule.localExport`（不含路径）与模块能力 `local_exports`；新增受信 `HostEffectIntent.localExport`，绑定调用身份、阶段、范围、准备版本、文件名与格式、内容摘要、目标能力身份、创建或覆盖方式、策略版本。目标能力宿主私有构造，无 JSON 解码入口。仅加 `file:` 字符串或放宽网络检查不够（`tool_registrar.dart:9-16`、`host_tool_registrar.dart:194-237`、`tool_registry.dart:442-453`）。
- 两阶段审批：A 只允许生成到科研 exports，B 只允许写本次所选目标，A 不能当 B 用。用户侧可以一张卡：按钮「确认本次生成并另存为」，系统选择回调 + 已确认内容由宿主签发 B，须验证属当前活跃操作、同一摘要、同一范围、未取消未过期——这是**新增的可信交接能力**，现 `HostUiGrantToken` 不绑定保存面板结果；无法证明交接或出现新确认理由时，在同一张卡补入真实目标后再确认。不得在目标未知时先签「任意位置」审批。
- 确认卡：操作与后续会打开另存为；项目与快照时间（草稿列所选笔记）；宿主文件名、格式、实际字节数；从实际载荷统计的分类对象数（报告里 entry/run 只在被提纲引用时进入正文，重复引用不重复计）；是否含引文、笔记正文、记录数据、运行指标与产物描述；排除项与警示；敏感度分开写「字段声明：未标记 personal/commercial」与「内容审查：未执行」；先生成于科研导出目录、取消另存为后保留完整本机副本；摘要与来源清单可折叠。卡由宿主固定构建，成功状态绑定回执，文字模式保留固定确认 / 拒绝。

## 3. 失败、取消、重复、回执
- exports 内：排他创建临时文件 → 写入、关闭、核对长度与摘要 → 提交为完整文件并登记 → 失败或取消清理本次未完成文件；越根检查不能只靠 `startsWith` 或一次 `resolveSymbolicLinks`。已完整生成的本机副本可保留。
- 分阶段：确认前取消零文件；准备失败零写入；生成中失败 / 取消清理临时文件、不开另存为；取消另存为 = 生成成功 + 保存取消；复制前失效不写；复制中失败区分未写入 / 部分写入 / 已清理 / 未知；写完但回执失败为 interrupted / 未知，不显示成功、不自动重试；成功落账后收到取消保留已完成事实。
- Android `ACTION_CREATE_DOCUMENT` 可能已建空文档或返回既有文档：只有能证明本次创建且身份未变且支持删除才清理，否则记录残留 / 未知；永远不删用户原有文件。
- 重复：同调用身份同内容查原回执不重复生成、不重复弹面板；同防重键换内容 / 范围 / 目标为身份冲突；用户主动再导出新建 `exportId` 重新确认选位置；对已生成文件再次另存复用同字节、新保存尝试；历史结果未知先只读查核。同名：生成区唯一名、排他创建；目标默认保存副本，替换须真实用户决定并纳入审批。
- 新增宿主 `LocalExportLedger`（现 `OutboundToolLedger` 通道只有 MCP / 网页 / Hub / 传输，且无 interrupted 状态），每阶段记录身份、内容摘要与字节数、范围、目标类型与身份摘要、实际显示名、审批、审查状态、结果与清理、时间、安全错误码；**每次实际写入前先成功记 pending，记账失败则零写入**。完整路径、原生句柄、URI 授权、正文不进模型回执；首版 `artifactRefs` 为空，用 `data.exportId` 关联。

## 4. claim_drafts 额外限制（全部在写文件前）
项目须明确选中且为 `research-skill-v2`（`isSkill` 只是前缀判断，V1 只读；工具显式检查，不靠 UI 挡）；每个 note 在已解析选中范围内且属该项目；空、重复、合法与越界混合整次拒绝；用笔记实际所属 document 版本，不换最新；该 document 有效绑定**恰一条**且 `ambiguous=false`（现导出器取第一条非歧义并跳过缺项，`exchange.dart:585-610`，不能照搬）；`paperId + paperRev` 唯一可解析、不自动升修订；来源只经受控解析器读取；输出始终待审草稿，不顺带确认绑定或写正式 claims。
越界 / 伪造整次拒绝；范围内但条件不足的进「不可导出及原因」清单；部分可导出时确认卡提供「仅导出这 N 条」并形成新冻结清单；全部不可导出不生成空文件；消歧走独立绑定确认。不加「必须最新文档 / 修订」限制（`research_skill_test.dart:303-325` 保留旧文档导出）。`binding.hashOk=false` 保留为显著警示；本次读取文件与绑定摘要不一致属来源核验失败，排除或重新准备。草稿保持 `review_status=needs_review`。

## 5. 测试清单（验收）
参数封闭；ID 与范围；名称安全；生成根约束（符号链接、并发替换）；单次目标能力（伪造、他任务、旧回调、重放）；内容冻结；统计真实性（UTF-8 字节数、去重计数）；分级授权（readOnly、outbound 关、撤销、过期、策略变化）；污损与审查（不自动 grant、不清污损、block 不可绕过）；账本失败（pending 失败零写入、完成记录失败为未知）；取消矩阵（确认前、生成中、选择中、首字节前、复制中、提交后）；崩溃与恢复（只读查核，旧目标能力不复活）；同名与重复；草稿类型与绑定；草稿兼容（旧文档、哈希警示、PDF、缺引句）；清理权限；模型回执脱敏；确认 UI（无回执不成功、旧卡不能执行）；业务表只读。平台验收含 macOS 沙盒构建与 Android 真实 `content://` 目标；纯 Dart 替身不能代替。

## 6. 实施任务（每项 ≤1 天）
| 任务 | 内容 | 依赖 |
|---|---|---|
| LE-01 本机导出声明契约 | module_api：local-export 目标规则、能力声明、准备/结果类型；网络行为兼容 | 无 |
| LE-02 报告内容准备器 | 提取报告只读序列化，冻结字节、来源、计数；旧方法保留包装 | LE-01 |
| LE-03 草稿内容准备器 | 提取草稿生成，补唯一绑定、V2、范围与来源核验，固定草稿 ID 与排除清单 | LE-01 |
| LE-04 宿主生成与清理状态机 | 排他命名、临时文件提交与清理（文件适配器可先用受控替身） | LE-01 |
| LE-05 本机导出意图与审批绑定 | `HostEffectIntent.localExport`、注册器适配、manual approval 校验、两阶段身份 | LE-01 |
| LE-06 导出账本、回执与只读查核 | `LocalExportLedger`、阶段记录、恢复查核、出站审计投影 | LE-01、05 |
| LE-07 宿主导出确认卡 | 固定内容、计数、敏感度 / 未审查、排除项确认、文字模式 | LE-01、06 |
| LE-08 系统选择与人工审批交接 | 本次选择凭据、回调关联、超时 / 取消失效、同卡补确认退路 | LE-05、07 |
| LE-09 macOS 文件能力适配 | 生成根操作、选中文件访问、创建 / 替换 | LE-04、08 |
| LE-10 Android SAF 选择适配 | 保留文档 URI 与本次能力，记录空目标状态，不持久授权 | LE-08 |
| LE-11 Android 写入及清理适配 | ContentResolver 复制、关闭与清理结果 | LE-04、06、10 |
| LE-12 接通 report 工具与页面 | 两阶段执行与回执；移除 report 的 deferred | LE-02、04-09（Android 加 11） |
| LE-13 接通 claim_drafts 工具与页面 | 笔记选择、排除项确认、回执；移除 deferred | LE-03、12 |
| LE-14 平台组合验收与证据 | 两平台场景与故障验证 | 对应平台全部实现片 |
report 可先于 claim_drafts 开放；平台能力未就绪时该平台明确不可用；本次不扩展 `exportTask` / `exportResult` / `exportSkillExperiment`。
