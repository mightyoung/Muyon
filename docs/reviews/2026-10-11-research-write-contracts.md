# 科研剩余写入契约调研（GB-2）

日期：2026-10-11 · 任务：[GB-2](../tasks/GB-2.md) · 执行：工程师2号（grokbot）· 分支：`review/gb-2-research-write-contracts`
方法：只读 `packages/research_module/lib/src/core/store.dart`、`exchange.dart`、`models.dart`、`module_declarations.dart`、`module_tools.dart`、`research_module.dart`、`research_services.dart`、`app/workbench_app.dart`；对照宿主 `ToolRegistrar` / `DestinationRule`、`FilePicker.getDirectoryPath`、`data_storage_page.dart` 的 `PickDirectory`；对照 [GROK-6](2026-10-09-research-ontology-draft.md) §5、[REG-3a 复审](../tasks/REG-3a-review.md)（本机导出门面未完成）、已开放写工具模式（`save_note` / `accept_run` / `assess_run` / `add_outline`）。**未**改代码、**未**运行 Flutter。
给谁用：grok-build 的 REG-3d 及以后。

范围操作（覆盖声明 deferred）：`research.query.notes`、`research.query.bindings`、`research.binding.insert`、`research.binding.confirm`、`research.note.set_entry`、`research.project.save`、`research.task.save`、`research.run.manual_start`、`research.run.manual_update`，以及 Q10 已批准的 `research.export.report`、`research.export.claim_drafts`。

已开放对照（不在本任务实现范围，仅作契约模板）：`research.save_note`、`research.accept_run`、`research.assess_run`、`research.add_outline` 均经 `store.scoped` + `requireCurrent` + `checkBeforeEffect` + `ManagedDatabase.write`（`module_tools.dart:162–265`）。

---

## 0. 读前摘要

| 操作 | 结论（一句话） | 建议批次 |
|---|---|---|
| `research.query.notes` | 可直接开放为读工具；文档须在选定范围 | REG-3d |
| `research.query.bindings` | 可直接开放为读工具；项目须在选定范围 | REG-3d |
| `research.project.save` | 可开放写工具；用选中 `project` 的 `contentDigest` 作期望值，领域层无需改表 | REG-3d |
| `research.note.set_entry` | 可开放写工具；用选中 `note` 的 digest + 同项目 entry 校验（Store 已有） | REG-3d |
| `research.task.save` | 可开放，但须拆「新建」与「新修订」并强制 `expected_revision`；禁止静默盖写最新修订意图 | REG-3d |
| `research.binding.confirm` | 可开放专用写工具（消歧）；目标挂 `document`，期望「仍 ambiguous 的 (doc,paper)」快照 | REG-3d |
| `research.run.manual_start` | 可开放；钉 `task.revisionRef`；创建后回执 run | REG-3e |
| `research.run.manual_update` | 可开放；仅 `_localManual`；须带 run `contentDigest` 期望值 | REG-3e |
| `research.binding.insert` | **不建议**对助手直接开放；生产写入仅导入路径 `computeBindings`→`insertBinding`；盲插缺 scope 与校验 | 后置 / 保持 deferred |
| `research.export.report` | Q10 开放；**须先补**本机目标/允许根门面后再登记 external | REG-3e（依赖门面） |
| `research.export.claim_drafts` | 同上；另限 skill 项目与非歧义绑定 | REG-3e（依赖门面） |

**共性**：科研无询价式统一 `save/delete/restore` 与统一行版本号（GROK-6 §0 / §5）；并发主要靠会话层 `ObjectRef.contentDigest` / `revisionRef` + `requireCurrent`（`research_module.dart:110–118,444–575`），不是表上的 `updated_at`。`paper_binding` **不是**本体 `ObjectTypeSpec`，`_resolve` 的 `default` 返回 null——绑定相关工具必须以 `document`/`project` 为选中目标。

---

## 1. `research.query.notes`

### 1.1 领域实现
- 成员：`WorkbenchStore.notes` · `store.dart:299–316`
- 行为：`SELECT * FROM notes WHERE document_id=? ORDER BY rowid`；先 `checkedObject('documents', documentId)`（有 `projectScope` 时校验文档属本项目）。
- 返回字段：`id, documentId, locator, text, pageNumber, quote, evidenceKind, doesNotSupport, entryId`（映射自 `notes` 表列）。
- 事务：无（只读）。校验：仅文档存在/范围；无额外 FormatException。

### 1.2 并发保护
只读。结果可附带每条 note 的 digest（与 `_resolve` note 分支一致：`sha256(jsonEncode(row))`，`research_module.dart:494–497`），供后续写工具钉期望值。无需改领域代码。

### 1.3 范围
参数 `document_id` → 必须落在 `resolvedScope` 的 `research/document`；工具内 `store.scoped(nativeProjectId)` + `_selected`。笔记本身默认不在 `inGlobalScope`（`note` 未设 true，`module_declarations.dart:5–9`），但可通过选定对象进入范围（与已开放 `read_object` type=`note` 一致）。

### 1.4 建议工具契约
| 项 | 建议 |
|---|---|
| 工具 ID | `research.list_notes`（或保留语义名 `research.query_notes`；与现有 `objects`/`read_object` 风格对齐建议 `list_notes`） |
| 效应 | 读 |
| 参数 | `document_id: string`（required） |
| 结果 | `{ notes: [...] }`；`objectRefs` 含各 note（带 contentDigest） |
| 拒绝 | 文档不在选定范围；`checkedObject` 越界 |

### 1.5 风险与结论
**可以直接开放**（REG-3d）。无领域补丁。敏感内容：`text`/`quoted_text` 可能含摘录（GROK-6 建议 commercial）——结果敏感度登记随 REG-3 本体片，本调研不裁定。

---

## 2. `research.query.bindings`

### 2.1 领域实现
- 成员：`WorkbenchStore.bindings` · `store.dart:317–332`
- 行为：`paper_bindings ⋈ documents`，按 `project_id` 过滤；`checkedProject(projectId)`。
- 字段：`documentId, paperId, paperRev, method, hashOk, ambiguous`。
- 事务：无。校验：仅项目范围。

### 2.2 并发保护
只读。无行级版本；确认写可用「选中时的 `(documentId,paperId,ambiguous,method,paperRev)` 元组摘要」作期望值（见 §4）。

### 2.3 范围
参数可用选中 `project` 的 id，或从选中 `document` 推导项目后过滤该文档绑定。`paper_binding` 非可解析 ObjectType——不要发明 `type=paper_binding` 选中，除非先补本体与 `_resolve`（超出本操作最小面）。

### 2.4 建议工具契约
| 项 | 建议 |
|---|---|
| 工具 ID | `research.list_bindings` |
| 效应 | 读 |
| 参数 | `project_id: string`（required）；可选 `document_id` 过滤 |
| 结果 | `{ bindings: [...] }` |
| 拒绝 | 项目/文档不在选定范围 |

### 2.5 风险与结论
**可以直接开放**（REG-3d）。

---

## 3. `research.binding.insert`

### 3.1 领域实现
- 成员：`WorkbenchStore.insertBinding` · `store.dart:333–341`
- 写入：`INSERT OR REPLACE INTO paper_bindings VALUES(documentId, paperId, paperRev, method, hashOk, ambiguous)`。
- 事务：无自管事务；**不**调用 `checkedObject('documents', …)`，**不**校验 `paperId`/`paperRev` 是否对应本项目 `entries`（papers）。
- 生产调用点：导入刷新 `ResearchExchange` 内 `computeBindings(...).forEach(store.insertBinding)`（`exchange.dart:511–515`）；UI 未见直接插入；测试直接调用。

### 3.2 并发保护
无版本字段；`INSERT OR REPLACE` 按主键 `(document_id, paper_id)` 覆盖。最小可行：工具层禁止开放，或（若坚持）要求先读 `list_bindings` 并对目标键做「不存在或期望摘要」检查——**仍无法**在领域层阻止与导入并发互相覆盖，除非改为条件更新。

### 3.3 范围
当前领域 API **本身不强制**文档属 `projectScope`。若仅靠工具 `_selected(document)` 包装可补范围；裸 Store 调用存在越界写入窗口（静态可见）。

### 3.4 建议工具契约
不建议登记助手可调用工具。若未来内部需要，应先改领域：`checkedObject('documents')`、校验 paper 属同项目、禁止无差别 REPLACE 已确认（`ambiguous=0`）行。

### 3.5 风险与结论
**不建议开放**。理由：生产语义是导入算法产物；盲插可伪造绑定、覆盖已确认行、且缺领域校验。保持 `deferred` / 后置；消歧用 `confirm`（§4）。

---

## 4. `research.binding.confirm`

### 4.1 领域实现
- 成员：`WorkbenchStore.confirmBinding` · `store.dart:345–355`；内核 `applyBindingChoice` · `359–368`
- 写入：
  1. `DELETE` 同项目内、同 `document_id` 或同 `paper_id` 的**其他** `ambiguous=1` 候选；
  2. `UPDATE` 目标行 `ambiguous=0`，`method` 追加 `+manual`（若尚未含）。
- 事务：`confirmBinding` 在非 `_inWrite` 时自管 `BEGIN/COMMIT/ROLLBACK`；已在 `store.write` 内则复用外层事务。
- 校验：`checkedObject('documents', documentId)`；**不**校验目标 `(documentId,paperId)` 行是否存在或仍为 ambiguous（若行不存在，UPDATE 影响 0 行，静默成功——**静态可见**）。

### 4.2 并发保护
表无版本号。最小可行（**工具层即可，可不改表**）：
- 选中目标为 `document`（带 contentDigest 可选，防文档换文件）；
- 参数带 `paper_id` + `expected_ambiguous: true`（或绑定行摘要：`method/paperRev/hashOk/ambiguous`）；
- 执行前 `SELECT` 该行，不满足则拒绝「绑定已变化」。
若要领域强制：在 `applyBindingChoice` 增加「目标行必须存在且 ambiguous=1」——**建议补**，否则助手确认空操作。

### 4.3 范围
文档经 `checkedObject`；删除候选限制在同 `project_id`（SQL 子查询，`store.dart:361–363`）。工具须 `_selected(document)` + `scoped(project)`。

### 4.4 建议工具契约
| 项 | 建议 |
|---|---|
| 工具 ID | `research.confirm_binding` |
| 效应 | 写 |
| 参数 | `document_id`, `paper_id`, `expected_ambiguous`（bool，建议 required true）或 `expected_binding_digest` |
| 结果 | 成功摘要；可选返回更新后 binding；`changes` 影响 document 侧展示（bindings 非 ObjectType，可不发 ObjectChange，或仅 document upsert） |
| 拒绝 | 文档不在范围；行不存在/已非 ambiguous；与期望不符；取消 |

### 4.5 风险与结论
**需要先补领域能力（建议）**：确认时目标行必须存在且仍 ambiguous，否则拒绝。补齐后 **可开放**（REG-3d）。不补则工具层可做 SELECT 预检，但 Store 仍静默空更新——审查上弱于领域拒绝。

---

## 5. `research.note.set_entry`

### 5.1 领域实现
- 成员：`WorkbenchStore.setNoteEntry` · `store.dart:373–385`；会话封装 `ResearchServices.setNoteEntry` · `research_services.dart:90–91`（走 `_write`）
- 写入：`UPDATE notes SET entry_id=? WHERE id=?`（`entryId` 可为 null 清除）。
- 事务：单语句；Services 路径包在 `store.write`。
- 校验：`checkedObject('notes')`；若 entry 非空则 `checkedObject('entries')` + 同项目 JOIN，失败 `StateError('Note or research record not found in this project')`。

### 5.2 并发保护
notes 表无版本列。会话层 note digest 覆盖整行（含 `entry_id`）——`requireCurrent(noteRef)` 即可表达「确认时所见笔记」。**无需改领域**即可最小可行。可选：参数再带 `expected_entry_id` 显式化意图。

### 5.3 范围
笔记→文档→项目；entry 必须同项目（Store 已强制）。工具：`_selected(note)`；若 `entry_id` 非空则 entry 也须在选定范围（与 `add_outline` 对 evidence 的要求一致）。

### 5.4 建议工具契约
| 项 | 建议 |
|---|---|
| 工具 ID | `research.set_note_entry` |
| 效应 | 写 |
| 参数 | `note_id`, `entry_id`（string \| null）；可选依赖选中 note 的 contentDigest（由 scope 携带） |
| 结果 | 更新后 note ref；`ObjectChange` upsert note |
| 拒绝 | note/entry 不在范围或不同项目；`requireCurrent` 失败 |

### 5.5 风险与结论
**可以直接开放**（REG-3d）。UI 已有阅读器挂接（`reader_page.dart:492`）。change_log 当前未跟踪 note（GROK-6 §0）——开放后投影是否补触发器为 REG-3 本体片问题，标「未能静态确认是否必须本片一并做」。

---

## 6. `research.project.save`

### 6.1 领域实现
- 成员：`WorkbenchStore.saveProject` · `store.dart:387–395`
- 写入：`UPDATE projects SET question=?, next_step=? WHERE id=?`（**不**改 `title`/`layout`/`skill_root`）。
- 事务：单语句。校验：`checkedProject(id)`；无长度/空串 FormatException。

### 6.2 并发保护
表无版本号。`_resolve(project)` digest = `sha256(jsonEncode([title, question, nextStep]))`（`research_module.dart:467–469`）。选中 project 若带 contentDigest，`requireCurrent` 可拦截确认后被改。**无需改领域**。若希望参数显式：可增加 `expected_content_digest` 与选中 ref 交叉校验（工具层）。

### 6.3 范围
`project_id` 必须为选定 `research/project`；`scoped` 后 `checkedProject` 防跨项目。

### 6.4 建议工具契约
| 项 | 建议 |
|---|---|
| 工具 ID | `research.update_project`（对齐 GROK-6 §5.2；勿叫通用 save） |
| 效应 | 写 |
| 参数 | `project_id`, `question`, `next_step`（建议 maxLength，数值待产品定） |
| 结果 | 更新后 project ref（新 digest） |
| 拒绝 | 不在范围；digest 变化；取消 |

### 6.5 风险与结论
**可以直接开放**（REG-3d）。不开放改 title/layout（无 Store API；layout 由导入写入）。

---

## 7. `research.task.save`

### 7.1 领域实现
- 成员：`WorkbenchStore.saveTask` · `store.dart:437–470`
- 写入：每次 **INSERT** 新行 `(id, revision+1, projectId, title, goal, jsonEncode(spec))`；主键 `(id, revision)`。新建时 `id ??= Uuid().v4()`，`revision` 从 0→1。
- 事务：单 INSERT。校验：`checkedProject`；若 id 已存在且 `project_id` 不同 → `StateError`；**不**校验「调用方期望的当前最大 revision」；**不**校验 spec schema。

### 7.2 并发保护
有天然 `revision`，但 API **不**接受 `expected_revision`：两路并发读到 r=N 后都会插入 N+1（SQLite 串行化下实际一个 N+1、一个 N+2），内容分叉且均保留——「用户确认时所见修订」未钉死。  
最小可行：
- **工具契约**强制：更新路径 required `expected_revision` == 当前 `MAX(revision)`，否则拒绝；新建路径禁止传已存在 id（或 `mode: create|revise`）。
- **领域补丁（建议）**：`saveTask` 增加可选 `int? expectedRevision`；当 id 已存在时要求 `expectedRevision == MAX(revision)`，否则抛错。否则仅工具层 TOCTOU 弱于事务内检查。

### 7.3 范围
`project_id` 选定；更新时现有 task 须能 `_resolve`（`revisionRef`）。`task` 的 `inGlobalScope: false`，靠选定对象进入范围（与 `accept_run` 同类）。

### 7.4 建议工具契约
| 项 | 建议 |
|---|---|
| 工具 ID | 拆分：`research.create_task` / `research.revise_task`（或单工具 + `mode`） |
| 效应 | 写 |
| 参数 | 共用：`project_id`, `title`, `goal`, `spec`（object；建议白名单或 max 体积）；`revise_task` 另需 `task_id`, `expected_revision` |
| 结果 | `{ task_id, revision }` + objectRef（含 revisionRef） |
| 拒绝 | 范围外；expected_revision 不匹配；跨项目 id；取消 |

### 7.5 风险与结论
**需要先补领域能力（建议 expectedRevision）后开放**（REG-3d）。`spec` 结构复杂——首期可只允许 UI 已用字段子集；整包盲写风险高（GROK-6）。不建议询价式「覆盖同 revision」。

---

## 8. `research.run.manual_start`

### 8.1 领域实现
- 成员：`WorkbenchStore.startManualRun` · `store.dart:505–539`
- 写入：`INSERT INTO runs`；`status='running'`, `accepted=0`；`data` 固定骨架含 `format: research-result-v1`、`_localManual: true`、空 metrics/logs/artifacts、`conclusion: ''`。
- 事务：单 INSERT。校验：`checkedProject(task.projectId)`；`taskRevision(task.id, task.revision)` 必须存在，否则 `Unknown task revision`。注释明确：**不**启动 task 命令。

### 8.2 并发保护
钉的是 **任务修订**（参数里的 `task.revision`），不是「最新任务」。若用户确认时选中 task 的 `revisionRef`，`requireCurrent(task)` 保证该修订仍存在；即使随后有更新修订，手工 run 仍合法挂旧修订（领域有意）。无需改表。可选拒绝「非最新修订」——产品决策，见文末问题清单。

### 8.3 范围
选中 `task`（带 revisionRef）；`scoped(project)`。创建 `run`（`inGlobalScope: false`）。

### 8.4 建议工具契约
| 项 | 建议 |
|---|---|
| 工具 ID | `research.start_manual_run` |
| 效应 | 写 · `createsTypes: {run}` |
| 参数 | `task_id`（revision 取自选中 ref.revisionRef，**不要**让模型另传可漂移的 revision，除非与 ref 交叉校验） |
| 结果 | 新 run ref + digest |
| 拒绝 | task 不在范围/修订消失；取消 |

### 8.5 风险与结论
**可以直接开放**（REG-3e，紧随 task 工具之后便于联调）。禁止与「执行远端命令」混淆——描述须写明仅建本机手工记录。

---

## 9. `research.run.manual_update`

### 9.1 领域实现
- 成员：`WorkbenchStore.updateManualRun` · `store.dart:541–592`
- 写入：`UPDATE runs SET status=?, data=?`；合并 metrics；非空 log **追加**到 `logs`；结论覆盖；若 status/metrics/conclusion 相对旧值变化则 `remove workbench_assessment`；进入 completed/failed 时写 `finishedAt`。
- 校验：`status ∈ {running,completed,failed,blocked}`；run 存在；`data['_localManual']==true`，否则 `Only local manual runs can be edited`。**不**调用 `checkedObject('runs')`（依赖外层 scoped/工具选中）。

### 9.2 并发保护
run 有 contentDigest（status+accepted+data，`research_module.dart:550–553`）。`requireCurrent(run)` 可表达确认所见。日志追加语义下，digest 变化频繁——确认卡应展示将写入的 status/conclusion/metrics，而非要求用户理解整段 data。领域可选：`expected_status` 或 expected digest 参数——工具层足够则可不改 Store。

### 9.3 范围
选中 `run`；须属当前项目（通过 resolve JOIN tasks）。非手工 run 领域已拒。

### 9.4 建议工具契约
| 项 | 建议 |
|---|---|
| 工具 ID | `research.update_manual_run` |
| 效应 | 写 |
| 参数 | `run_id`, `status`, `metrics`（object）, `log`（string，可空）, `conclusion` |
| 结果 | 更新后 run ref |
| 拒绝 | 非手工 run；非法 status；digest 变化；不在范围 |

### 9.5 风险与结论
**可以直接开放**（REG-3e）。与已开放 `assess_run`/`accept_run` 互补：手工编辑会清评估；接纳仍走 `accept_run`。建议批次放在 start 之后。

---

## 10. `research.export.report`

### 10.1 领域实现
- 成员：`ResearchExchange.exportReport` · `exchange.dart:1128–1196`
- 行为：聚合项目标题/问题/下一步、sections+outline 证据（entry/accepted run/note）、全部精读笔记 → Markdown；`Directory(destinationDirectory).create`；写 `report-$projectId-$uuid.md`；返回文件路径。
- 事务：无 DB 写。校验：`projects().firstWhere`（项目必须存在）；无路径沙箱——**任意** `destinationDirectory` 字符串均可写（调用方责任）。

### 10.2 并发保护
导出是快照外传，无乐观锁需求。确认时应展示将导出的项目身份（title + contentDigest）。

### 10.3 范围
选中 `project`。证据/笔记随项目读出；不扩展到项目外。

### 10.4 建议工具契约（依赖门面，见 §12）
| 项 | 建议 |
|---|---|
| 工具 ID | `research.export_report` |
| 效应 | **外传 / export**（勿登记为 write） |
| 参数 | `project_id`；**不**接受模型任意文件系统路径 |
| 结果 | 生成文件的展示名、字节数、（可选）模块内相对路径；最终「另存为」由宿主门面完成 |
| 拒绝 | 项目不在范围；用户取消目录/保存；门面判定路径越出允许根 |

### 10.5 风险与结论
**需要先补宿主本机导出门面**后再开放（REG-3e）。领域 API 可复用；缺的是 registrar 侧「目标选择 + 允许根」而非 `exportReport` 本身。

---

## 11. `research.export.claim_drafts`

### 11.1 领域实现
- 成员：`ResearchExchange.exportClaimDrafts` · `exchange.dart:564–660`
- 行为：仅 `project.isSkill`；按 noteIds 组装 claim draft 行；跳过无绑定/歧义绑定/缺论文修订等；写 `workbench-claims-$stamp.jsonl`；若目标文件已存在则抛错。
- 校验：非 skill → `StateError`；全部跳过 → `StateError`；路径同样无沙箱。

### 11.2 并发保护
导出前可用 note/document digest；绑定歧义以导出时刻为准（与 UI「先确认绑定」一致）。

### 11.3 范围
选中 project（skill）+ 选定 note ids 均须在范围；建议工具要求 notes⊆scope。

### 11.4 建议工具契约
| 项 | 建议 |
|---|---|
| 工具 ID | `research.export_claim_drafts` |
| 效应 | 外传 / export |
| 参数 | `project_id`, `note_ids: string[]`（非空）；无任意路径 |
| 结果 | path 展示、`rows` 计数、`skipped` 原因列表、`hashMismatches`（若回传需敏感度标注） |
| 拒绝 | 非 skill；无可用笔记；范围外；门面拒绝；取消 |

### 11.5 风险与结论
同报告：**门面就绪后开放**（REG-3e）。依赖绑定质量——可与 `confirm_binding` 同批或稍后。

---

## 12. 本机导出门面（两则导出共用）

### 12.1 现状（静态）
| 能力 | 位置 | 能否复用 |
|---|---|---|
| UI 默认导出目录 | `workbench_app.dart:191` → `join(store.rootPath, 'exports')` | 可作**模块内暂存根** |
| 另存为 | `saveGenerated` → `FilePicker.saveFile`（`:193–208`） | 用户选最终位置；助手工具无等价包装 |
| 选目录 | `FilePicker.getDirectoryPath`（workbench 导入、`file_gateway.dart:16`、`pickDirectoryWithDialog` @ `data_storage_page.dart:12–13`） | 宿主已有 `PickDirectory` 注入（`app_shell` / `platform_shell`） |
| 备份选目录 | `data_storage_page` 备份/恢复流 | 交互可参考；**不是**科研导出允许根 |
| `DestinationRule` | 仅 `fixedHosts` / `publicWeb`（`tool_registrar.dart:12–16`） | **网络导向**；空规则在 `host_tool_registrar.dart:195–208` 被拒绝 |
| 路径守卫先例 | `standalone_access` / `document_search_source` 的 `p.isWithin(root, path)`；原型允许根文档 | 可借鉴「允许根内写入」 |

REG-3a 复审与 REG-3b 任务书均写明：registrar **仍缺**本机目标选择与允许根目录门面；不能把本机导出伪装成 write 或网络 external。

### 12.2 最小门面设计（建议）
1. **Host API（名称待定）**，例如 `LocalExportFacade`：
   - `Future<Uri?> pickSaveLocation({required String suggestedName, required String mimeType})` — 复用 `FilePicker.saveFile` / 测试注入；
   - 或 `Future<Directory?> pickDirectory(String title)` — 复用现有 `PickDirectory`；
   - `bool allowWrite(String absolutePath)` — 路径必须在**用户当次挑选的目录**或**预先批准的允许根**之内（`isWithin` + 解析符号链接，对齐原型方案）。
2. **工具执行顺序**：审批通过 → 在 `moduleRoot/exports/`（或 staging）调用现有 `exportReport` / `exportClaimDrafts` → 门面 `pickSave` 把字节另存到用户目标 → （可选）删除/保留暂存。**模型参数不得包含绝对路径。**
3. **ExternalToolSpec**：当前 `DestinationRule` 无法表达 `file:` 本机根。选项（需用户决定，见下）：
   - **A.** 扩展 `DestinationRule` / 宿主策略支持 `localRoots`（或 `ToolEffect.export` + 专用 local 检查，绕开网络 `_checkRule`）；
   - **B.** 用 `HostChannel`（export effect）由模块发起、宿主审 destination 字符串约定（如 `local-export:`），仍不把任意 path 交给模型；
   - **C.** 暂用 write 工具只写模块 `exports/` 内相对名——**违背** Q10「外传」语义与覆盖声明 `OpKind.external`，**不推荐**。

### 12.3 需要用户决定的点
见文末「需要用户决定的问题」。

---

## 13. 汇总表

| 操作 | 结论 | 建议批次 | 依赖 |
|---|---|---|---|
| `research.query.notes` | 可直接开放读工具 | REG-3d | 无 |
| `research.query.bindings` | 可直接开放读工具 | REG-3d | 无 |
| `research.project.save` | 可直接开放写；digest 作期望 | REG-3d | 沿用 `requireCurrent` |
| `research.note.set_entry` | 可直接开放写 | REG-3d | note/entry 入选范围 |
| `research.task.save` | 需补 `expectedRevision`（建议）后开放；拆 create/revise | REG-3d | 领域小补丁；spec 白名单策略 |
| `research.binding.confirm` | 建议领域拒空确认后开放 | REG-3d | 可选 Store 补丁；document 选中 |
| `research.run.manual_start` | 可直接开放 | REG-3e | task 选定+revisionRef |
| `research.run.manual_update` | 可直接开放 | REG-3e | run digest；仅 `_localManual` |
| `research.binding.insert` | **不建议**开放 | 后置 | 保持导入专用 |
| `research.export.report` | 门面后开放 | REG-3e | §12 本机导出门面；Q10 |
| `research.export.claim_drafts` | 门面后开放 | REG-3e | §12；skill；绑定质量 |

大纲一族（`outline.*`）属 REG-3c，不在本表。

---

## 14. 需要用户决定的问题清单

1. **本机导出 Destination 模型**：采用 §12.2 选项 A（扩展 DestinationRule/localRoots）、B（HostChannel + 约定 destination）、还是其他宿主设计？是否禁止模型传路径（本调研建议禁止）？
2. **导出暂存根**：是否固定为 `<researchRoot>/exports`（与 UI 一致），另存为再走 `FilePicker.saveFile`？是否允许用户改「允许根」到任意目录（一次挑选 vs 持久设置）？
3. **`confirm_binding` 空更新**：是否要求领域层在目标行不存在或已非 ambiguous 时抛错（建议是）？
4. **`saveTask`**：是否批准领域增加 `expectedRevision`？`spec` 首期是否全量 object 还是字段白名单？
5. **`start_manual_run`**：是否允许对非最新 task revision 建手工 run（领域当前允许）？
6. **`binding.insert`**：确认保持不对助手开放（本调研建议）？
7. **change_log / 投影**：开放 `set_note_entry` / `update_project` 时是否必须同批补 note/project 的 ModuleChangeLog（当前未跟踪）？

---

## 15. 未能静态确认

1. 助手选定范围 UI 如何把 `task`/`run`/`note`（`inGlobalScope: false`）加入 `resolvedScope` 的完整产品路径（测试与 `read_object`/`accept_run` 证明机制存在，真机操作路径未验证）。
2. 是否已有未合入的 local-export DestinationRule 草案（本树 `DestinationRule` 仅网络字段）。
3. `exportClaimDrafts` 返回的 draft 行是否含需标 `Sensitivity.commercial` 的字段全集（依赖 claimDraft 构造细节，未逐字段展开）。
4. REG-3c 完成后 outline 工具与本批写工具共享的 registrar 辅助函数是否会抽取（不影响本契约结论）。

---

## 16. 回报用元数据

- 分支：`review/gb-2-research-write-contracts`
- 交付物：`docs/reviews/2026-10-11-research-write-contracts.md`
- 执行：工程师2号 · 只读代码与写文档 · 未跑 Flutter
