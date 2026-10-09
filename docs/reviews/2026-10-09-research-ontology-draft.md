# 科研本体初稿静态盘点（GROK-6）

日期：2026-10-09 · 任务：[GROK-6](../tasks/GROK-6.md) · 执行：工程师2号（grokbot）· 分支：`task/grok-6-research-ontology`
方法：只读 `packages/research_module/lib/src/core/`（`models.dart`、`store.dart`、`outline_store.dart`、`research_kinds.dart`、`skill_bridge.dart`、`change_log.dart`、`exchange.dart`）、`packages/research_module/lib/src/cards/card_store.dart`、`source_ref.dart`、`research_module.dart` schema；对照 [GROK-5 询价盘点](2026-10-09-inquiry-ontology-cards.md) 格式与 [GROK-2 科研覆盖清单](coverage-drafts/research.md)；**未**改代码、**未**运行 Flutter。
给谁用：REG-3（科研迁 v2 / `ModuleOntology`）、AIUI-7（科研场景）、AIUI-9（本体业务卡片）。

科研尚无宿主 `ModuleOntology` 适配器（`apps/muyon/lib/app/adapters/` 仅有 `inquiry_module.dart`）。本文件为**初稿**，敏感度均为建议值，拿不准项见 §0.2 / §6。

当前 Workbench schema：`WorkbenchStore.schemaVersion == 6`（`store.dart:129`，`_migrations.length`）。卡片知识库 schema 由 `installResearchKnowledgeSchema` 安装（`card_store.dart:12–21`），与 workbench `user_version` 分开。

---

## 0. 汇总（请先看这里）

| 项 | 结论 |
|---|---|
| 建议对象类型（业务） | **10**：`project`、`document`、`entry`、`task`、`run`、`note`、`paper_binding`、`section`、`outline`、`card` |
| 附属/映射（不建议首期本体实体） | `task_import`；`rk_project`（origin）；`canonical_object_map`；`rk_document`（卡片侧不可变原文字节，与 `document` 映射）；`rk_conflict`；`import_receipt` / `change_log` |
| 表（workbench v6） | `projects`、`documents`、`entries`、`tasks`、`runs`、`notes`、`paper_bindings`、`sections`、`outline`、`task_imports` |
| 表（卡片知识） | `rk_projects`、`canonical_object_map`、`rk_cards`、`rk_revisions`、`rk_documents`、`rk_conflicts`、`rk_import_receipts` |
| change_log 已跟踪类型 | `document`、`entry`、`section`、`outline`、`run`、`card`、`task`（`change_log.dart:49–125`）；**未**见 `project` / `note` / `paper_binding` 的 track |
| 字段合计（初稿可登记） | **约 68** 顶层业务字段（§1 各表合计）；另 `entry.data` / `task.spec` / `run.data` 为开放 `object`，内含按 kind 变化的判断字段（§1.3） |
| 带版本/乐观锁 | `task.revision`（复合主键）；`card` 的 `revisionId` + `expectedHead`；`run.task_revision`（钉任务修订） |
| 通用 CRUD | **无**询价式 `save/delete/restore`；多为具名 Store 写成员；项目/文档/条目新建主要走导入 `ResearchExchange` |
| 已登记写工具（宿主） | 未能静态确认本树有 `research.*` 写工具注册（GROK-2 多为「建议新增」） |
| Q10（已确认） | `exportReport` / `exportClaimDrafts` 本机导出可开放；其余导入/任务包/结果包/技能实验包 `deferred(REG-3)` |

### 0.1 各对象类型一句话结论

| 类型 | 一句话 |
|---|---|
| `project` | 适合编辑卡（问题/下一步）；新建主要靠导入或 UI 插行，无 `createProject` Store API；`layout`/`skill_root` 由导入刷新写入。 |
| `document` | 元数据可查询；新建/更新/删无笔记版主要在 `commitResearch`；阅读器与原文字节留原页；卡片侧另有 `rk_documents`。 |
| `entry` | 适合「按 kind 的窄编辑卡」展示 judgment 字段；整包 `data` 通用新建卡风险高；无独立 Store `saveEntry`。 |
| `task` | 适合新建/保存新修订卡（`saveTask` 每次 `revision+1`）；规格 `spec` 结构复杂，宜白名单字段。 |
| `run` | 手工运行用专用工具（`startManualRun`/`updateManualRun`/`assessRun`/`acceptRun`）；**不宜**整对象通用 CRUD。 |
| `note` | 适合「在文档上新建笔记」卡；`saveNote` **仅 INSERT**，无更新/删除 Store API。 |
| `paper_binding` | 适合确认绑定关联卡；插入/消歧有 Store；不宜批量盲写。 |
| `section` | 适合新建/编辑/排序卡；删除级联清 outline 链接（证据本身保留）。 |
| `outline` | 适合「引用证据到段落」关联卡；`cite`/`addOutline`/`removeOutline`。 |
| `card` | 适合 Markdown 编辑卡（已有 `expectedHead` 乐观锁）；引用与关系校验严，留阅读器/关系图的复杂操作。 |

### 0.2 建议敏感度汇总（均未落地适配器）

| 标记 | 建议字段 | 理由（静态） |
|---|---|---|
| `personal` | `rk_revisions.author`（若将来存真人名）；条目/来源 JSON 内可能出现的作者姓名（见 §6） | 当前默认 `'local-user'`/`'import'`（`card_store.dart:300,343`），真人名未能静态钉死 |
| `commercial` | `note.quoted_text` / `note.text`；`card.bodyMarkdown`；`entry.data` 中主张/实验/失败等判断；`project.question`/`next_step`；`task.goal`/`spec`；`run.data`（日志/指标/评估） | 未发表摘录、研究判断与实验细节属业务机密范畴的常见情形 |
| `none` | 路径、哈希、状态枚举、id/ref、layout、support、evidence_kind 枚举等元数据 | 无直接 PII；摘录类另标 |
| `credential` | **0**（模型/表无口令类字段） | — |

**请用户确认（拿不准）**：见 §6「敏感字段确认」。

---

## 1. 逐对象类型盘点

约定列：字段名 · 标签 · Kind · 必填 · 枚举/关联 · 建议敏感度 · 主要校验（代码位置）。
主键与版本单独写在类型头。

### 1.1 `project` 科研项目

**表** `projects`（`store.dart:90` + v5 `ALTER` `:107–108`）  
**主键** `id` TEXT · **版本字段** 无

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `id` | ID | text | 是 | uuid | none | PK |
| `title` | 标题 | text | 是* | — | none | 导入时由路径名推导（`exchange.dart:281–285`）；Store `saveProject` **不改** title |
| `question` | 研究问题 | text | 否 | — | **commercial** | `saveProject` 写入（`store.dart:387–395`） |
| `next_step` | 下一步 | text | 否 | — | **commercial** | 同上 |
| `layout` | 布局 | enumeration | 是（默认） | `generic` / `research-skill-v1` / `research-skill-v2`（`models.dart:12–17`） | none | 导入后 `UPDATE … layout,skill_root`（`exchange.dart:527`） |
| `skill_root` | 技能根路径前缀 | text | 否 | 快照相对路径 | none | 同上 |

\*表定义未标 `NOT NULL`，但业务 UI/导入均给 title。

**Store 写**：`saveProject(id, question:, nextStep:)` 仅改问题与下一步。新建：`ResearchExchange.commitResearch` / `commitTask` INSERT（`exchange.dart:319,799`）；无 `WorkbenchStore.createProject`。

**校验函数**：无独立 `validatePayload`；`saveProject` 仅 `checkedProject`。

**建议卡片**：编辑（question / next_step）。  
**不宜**：改 `layout`/`skill_root`（导入语义）；整库导入新建 → 留导入流 / 原页。

---

### 1.2 `document` 文档（工作台快照）

**表** `documents`（`:91` + v2 列改名 snapshot_path + v5 `sha256`）  
**主键** `id` · **版本** 无（同路径可多行保留旧版供笔记，`models.dart:46–49` `currentVersions`）

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `id` | ID | text | 是 | | none | PK |
| `project_id` | 项目 | ref → project | 是 | FK | none | |
| `relative_path` | 相对路径 | text | 是 | | none | 列表排序键 |
| `snapshot_path` | 快照路径（库内） | text | 是 | 相对 root | none | 模型暴露为 `absolutePath=resolvePath`（`store.dart:240`） |
| `sha256` | 内容哈希 | text | 否 | hex | none | v5 起；绑定/刷新用 |

**Store 写**：无 `saveDocument`；插入/更新/删除在 `commitResearch`（`exchange.dart:362–372,503`）。卡片侧 `CardStore.registerDocument` / `deleteDocument` 写 `rk_documents`（`card_store.dart:240–268`），`object_type='document'`。

**建议卡片**：只读元数据 / 打开阅读器。新建文件流、哈希绑定留原页与导入。  
**Q10**：整项目导入 deferred。

---

### 1.3 `entry` 研究记录（条目）

**表** `entries`（`:92`）  
**主键** `id` · **版本** 无（skill 记录内部可有 `id`/`rev` 在 `data` JSON）

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `id` | ID | text | 是 | | none | PK |
| `project_id` | 项目 | ref → project | 是 | | none | |
| `kind` | 种类 | enumeration | 是 | `recordKinds`：sources/papers/claims/opportunities/searches/tensions/experiments/failures/handoffs；其它为 `other`（`research_kinds.dart:5–15`） | none | |
| `title` | 标题 | text | 是 | | none | |
| `data` | 载荷 | object | 是 | JSON 文本列 | **commercial**（整体建议） | 无 Workbench 侧 schema 校验；导入时 UPDATE/INSERT/DELETE（`exchange.dart:454–488`） |

**按 kind 的判断字段展示键**（`judgmentFields`，`research_kinds.dart:19–63`；非独立表列，建议 REG-3 作 `object` 内文档化或展开为可选字段）：

| kind | 键（部分） | 值标签示例 |
|---|---|---|
| claims | evidence_kind, supports_statement, does_not_support, scope, … | evidence_kind ∈ paper_statement/inference/hypothesis（与 `evidenceKinds` 对齐，`research_skill.dart:22`） |
| opportunities | decision, novelty, importance, … | decision：continue/revise/park/abandon（`_valueLabels`） |
| searches | query, layer, status, coverage_claim | |
| tensions | tension_type, observation, … | |
| experiments | phase, actual.result, … | phase 含 planned/executed |
| failures | failure_type, cause, … | |
| handoffs | step, step_state, pending_questions | |

**Store 写**：无 `saveEntry`；写路径在 exchange 导入刷新。由实验计划生成任务：`taskFromExperiment`（`skill_bridge.dart:27–56`）只读 entry。

**建议卡片**：按 kind 的只读/窄编辑（若 REG-3 补写 API）；通用「整 JSON 新建」**不建议**。  
**不宜**：导入删除无笔记文档时顺带删 entry 的级联逻辑 → 留导入流。

---

### 1.4 `task` 任务规格

**表** `tasks`（`:93`）  
**主键** `(id, revision)` · **版本字段** `revision` INTEGER（每次 `saveTask` +1，`store.dart:453`）

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `id` | ID | text | 是 | | none | 新建可省略由 UUID |
| `revision` | 修订号 | integer | 是 | ≥1 | none | 不可原地改旧修订 |
| `project_id` | 项目 | ref → project | 是 | | none | 已存在任务不得换项目（`:450–451`） |
| `title` | 标题 | text | 是 | | none | |
| `goal` | 目标 | text | 是 | | **commercial** | |
| `spec` | 规格 | object | 是 | JSON；可含 source/experiment 计划字段、command 等（`skill_bridge.dart:45–55`） | **commercial** | `saveTask` 不校验内部键 |

**Store 写**：`saveTask`（`:437–470`）→ INSERT 新 revision。删除：未能静态确认公开 API（change_log 有 DELETE 触发器语义）。

**建议卡片**：新建任务；「保存新修订」编辑卡（展示当前 head revision）。  
**不宜**：直接改历史 revision；导出任务包（Q10 deferred）。

---

### 1.5 `run` 运行记录

**表** `runs`（`:94`）  
**主键** `id` · **版本** 无；钉 `task_revision`

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `id` | ID | text | 是 | | none | |
| `task_id` | 任务 | ref → task | 是 | 与 revision 复合 FK | none | |
| `task_revision` | 任务修订 | integer | 是 | | none | |
| `status` | 执行状态 | enumeration | 是 | 手工：`running`/`completed`/`failed`/`blocked`（`updateManualRun` `:548`） | none | |
| `accepted` | 已接纳为证据 | boolean | 是 | 0/1 | none | `acceptRun` 置 1（`:472–475`）；**不**改 status |
| `data` | 运行载荷 | object | 是 | 含 format、metrics、logs、conclusion、`workbench_assessment`、`_localManual`、`finishedAt` 等 | **commercial** | |

**级联/效应**：

- `acceptRun`：仅 `accepted=1`；被 `OutlineStore.cite` 接受为证据时要求 `accepted=1`（`outline_store.dart:109`）。
- `assessRun`：写入 `data.workbench_assessment`（`runAssessment` 规则，`skill_bridge.dart:61–91`）；不改 status/accepted。
- `updateManualRun`：仅 `_localManual==true`；状态/metrics/conclusion 变化会 **remove** `workbench_assessment`（`store.dart:569–572`）。

**Store 写**：`startManualRun`、`updateManualRun`、`acceptRun`、`assessRun`；导入结果另见 `importResult`（deferred）。

**建议卡片**：评估结论、接纳证据、更新手工运行——**专用工具卡**，非通用 CRUD。  
**不宜**：通用 `create_record` 拼 runs 行。

---

### 1.6 `note` 阅读笔记

**表** `notes`（`:95` + v4 page/quote + v5 evidence + v6 entry_id）  
**主键** `id` · **版本** 无

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `id` | ID | text | 是 | 新建时 UUID | none | `saveNote` 生成（`:413`） |
| `document_id` | 文档 | ref → document | 是 | | none | |
| `locator` | 定位 | text | 是 | | none | |
| `text` | 笔记正文 | text | 是 | | **commercial** | |
| `page_number` | 页码 | integer | 否 | ≥1 | none | `<1` → FormatException（`:407–408`） |
| `quoted_text` | 摘录 | text | 否 | 默认 `''` | **commercial** | trim 后写入 |
| `evidence_kind` | 证据性质 | enumeration | 否 | `paper_statement`/`inference`/`hypothesis`（`evidenceKinds`） | none | 非法 → FormatException（`:410–411`） |
| `does_not_support` | 不支持的结论 | text | 否 | 默认 `''` | **commercial** | |
| `entry_id` | 关联条目 | ref → entry | 否 | 须同项目（`:376–383`） | none | `setNoteEntry` |

**Store 写**：`saveNote`（仅 INSERT）；`setNoteEntry`（UPDATE）。**无** update text / delete note 公开成员（静态未见）。

**建议卡片**：新建笔记；关联条目。  
**不宜**：阅读器内划词定位细节 → 留阅读器页；无删除 API 则卡片勿承诺删除。

---

### 1.7 `paper_binding` 论文绑定

**表** `paper_bindings`（`:112`）  
**主键** `(document_id, paper_id)` · **版本** 无

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `document_id` | 文档 | ref → document | 是 | | none | |
| `paper_id` | 论文记录 ID | text | 是 | skill papers 侧 id | none | |
| `paper_rev` | 论文修订 | integer | 是 | | none | |
| `method` | 匹配方法 | text | 是 | 确认后可追加 `+manual`（`:366`） | none | |
| `hash_ok` | 哈希一致 | boolean | 是 | | none | |
| `ambiguous` | 歧义待确认 | boolean | 是 | | none | `confirmBinding` 清竞争项 |

**Store 写**：`insertBinding`；`confirmBinding` / `applyBindingChoice`（删同项目内其它 ambiguous 竞争，`:359–368`）。

**建议卡片**：确认绑定（关联卡）。  
**不宜**：盲 `INSERT OR REPLACE` 批量工具无确认。

---

### 1.8 `section` 提纲段落

**表** `sections`（`:119`）  
**主键** `id` · **版本** 无

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `id` | ID | text | 是 | | none | |
| `project_id` | 项目 | ref → project | 是 | | none | |
| `heading` | 标题 | text | 是 | 非空 trim | none | `_check`（`outline_store.dart:141–146`） |
| `level` | 层级 | integer | 是 | 1–3 | none | |
| `position` | 顺序 | integer | 是 | | none | `addSection` 取 MAX+1；`moveSection` 交换 |
| `argument` | 论点 | text | 否 | 默认 `''` | **commercial** | |
| `support` | 支持程度 | enumeration | 是 | `sectionSupport`：unassessed/supported/partial/weak/contested（`models.dart:118–124`） | none | |

**Store 写**：`addSection` / `updateSection`（并同步 outline.heading）/ `moveSection` / `deleteSection`（先 `DELETE outline` 再删 section，`:85–88`）。

**建议卡片**：新建、编辑、上移下移。删除需确认（丢掉证据链接，证据对象仍在）。

---

### 1.9 `outline` 提纲证据链接

**表** `outline`（`:96`/`117` + v6 `section_id`）  
**主键** `id` · **版本** 无

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `id` | ID | text | 是 | | none | |
| `project_id` | 项目 | ref → project | 是 | | none | |
| `heading` | 标题（冗余） | text | 是 | 与 section 同步 | none | |
| `evidence_id` | 证据 | ref（多态） | 是 | → entry **或** note **或** accepted run | none | `cite` 校验（`:106–115`） |
| `section_id` | 段落 | ref → section | 是* | FK | none | v6；`cite` 写入 |

\*迁移前旧行可能曾无 section；现行写入路径带 `section_id`。

**Store 写**：`addOutline`、`cite`（同 section+evidence 幂等）、`removeOutline`。

**建议卡片**：关联（把证据挂到段落）。多态 ref 在通用本体里可能需 **新 FieldKind 或约定 ref 联合**，见 §5 / §6。

---

### 1.10 `card` 知识卡片（Research Knowledge）

**表** `rk_cards` + `rk_revisions`（`card_store.dart:15–16`）；逻辑模型 `ResearchCard` / `CardRevision`  
**主键** 卡片：`object_key`（canonical）；修订：`revision_id` · **版本** `head_revision_id` / `revisionId`；保存需 `expectedHead`（`:296–308`）

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `cardId`（local） | 本地卡片 ID | text | 是 | map 到 object_key | none | `ensureKey(..., 'card', cardId)` |
| `revisionId` | 修订 ID | text | 是 | `^[A-Za-z0-9_-]{1,128}$` | none | `CardRevision` 构造（`:94–104`） |
| `bodyMarkdown` | 正文 | text | 是 | | **commercial** | |
| `parents` | 父修订 | object / refList | 否 | 同 objectKey 的 RevisionRef | none | |
| `citationRefs` | 引用 | object（列表） | 否 | → document SourceRef | **commercial**（含 quote） | 源版本须存在（`:311–318`） |
| `relations` | 关系 | object（列表） | 否 | target ObjectKey + kind | none | target 须在项目内（`:321–322`） |
| `created_at` | 创建时间 | instant | 是 | UTC ISO | none | insertRevision |
| `author` | 作者标记 | text | 是 | 默认 local-user/import | **personal**（若真人名）/ 默认 none | 见 §0.2 |

`SourceRef` 子结构（`source_ref.dart:50–84`）：`documentRef`、`contentDigest`（64 hex）、`pageIndex`、`quote`、可选 context/parser/coordinates —— `quote` 建议 **commercial**。

**Store 写**：`CardStore.save`、`insertRevision`；`registerDocument`/`deleteDocument` 服务引用原文。

**建议卡片**：新建/编辑 Markdown（带 expectedHead）；加引用宜阅读器辅助。  
**不宜**：冲突解决 UI、设备包交换（deferred）。

---

### 1.11 不建议首期登记为本体实体（附属）

| 名称 | 表 | 理由 |
|---|---|---|
| `task_import` | `task_imports`（`store.dart:100`） | 包路径/哈希账本，非用户编辑对象 |
| `rk_project` | `rk_projects` | origin_key 映射 |
| `canonical_object_map` | 同名 | 身份映射 |
| `rk_document` | `rk_documents` | 卡片引用字节；业务上挂在 document |
| `rk_conflict` / receipts / change_log | 各表 | 同步与审计；非业务卡片 |

---

## 2. 关系

| 从 → 到 | 字段 | 基数 | 说明 |
|---|---|---|---|
| document → project | `project_id` | N:1 | |
| entry → project | `project_id` | N:1 | |
| task → project | `project_id` | N:1 | 多 revision 同行 id |
| run → task | `task_id` + `task_revision` | N:1 | 复合 FK |
| note → document | `document_id` | N:1 | |
| note → entry | `entry_id` | N:0..1 | 同项目 |
| paper_binding → document | `document_id` | N:1 | |
| paper_binding → paper（entry） | `paper_id` + `paper_rev` | 逻辑关联 | 非 SQL FK 到 entries |
| section → project | `project_id` | N:1 | |
| outline → project | `project_id` | N:1 | |
| outline → section | `section_id` | N:1 | |
| outline → evidence | `evidence_id` | N:1 多态 | entry / note / accepted run |
| card → project | 经 `canonical_object_map.local_project_id` | N:1 | |
| card citation → document | `SourceRef.documentRef` | N:N | 经 rk_documents digest |
| card relation → card/document | `CardRelation.target` | N:N | |
| task.spec.source → entry | `spec.source.{kind,id,rev}` | 0..1 | 实验计划钉死（`skill_bridge.dart:46`） |

---

## 3. 写入方式（对照 GROK-2）

| 对象 | 新建 | 修改 | 删除 | 校验 | 级联/效应 | GROK-2 对照 |
|---|---|---|---|---|---|---|
| project | exchange INSERT；无 Store create | `saveProject`；layout 由 exchange UPDATE | 未见公开 delete | `checkedProject` | — | `research.project.save` |
| document | exchange / 测试 INSERT；卡片 `registerDocument` | exchange UPDATE 路径/哈希 | exchange 删无笔记版；`deleteDocument` 软删 rk | 范围检查 | 刷新时重算 bindings | `research.card.document.*`；缺 workbench save |
| entry | exchange INSERT | exchange UPDATE | exchange DELETE | 无 validatePayload | — | **缺口**：无 `save_entry` |
| task | `saveTask`（新 id） | `saveTask` 新 revision | 未见公开 API | 跨项目拒绝 | — | `research.task.save` |
| run | `startManualRun`；importResult | `updateManualRun`/`assessRun` | 未见 | status/assessment 规则 | accept 影响 cite；评估写 data | `research.run.*` |
| note | `saveNote` | 仅 `setNoteEntry` | 未见 | page/evidenceKind | — | `research.note.*`；**无 update/delete** |
| paper_binding | `insertBinding` | `confirmBinding` | confirm 删竞争 ambiguous | 项目范围 | 消歧 | `research.binding.*` |
| section | `addSection` | `updateSection`/`moveSection` | `deleteSection` | `_check` | 删 outline 链接 | `research.outline.*` |
| outline | `cite`/`addOutline` | — | `removeOutline` | 证据 scope/accepted | — | 同上 |
| card | `save`（expectedHead=null） | `save`（带 expectedHead） | 未见删卡 API | CardRevision/FormatException；引用存在 | CardConflict | `research.card.save` |

**GROK-2 已列、本盘点确认仍缺的通用能力**：entry 本机写；note 更新/删除；project 标题/新建 Store API；多数类型无 `version` 乐观锁（除 task/card）。

**导出（Q10）**：`exportReport`、`exportClaimDrafts` → 建议工具开放；其余 import/export* → deferred。

---

## 4. 卡片建议

| 对象 | 新建 | 编辑 | 关联 | 批量 | 留原页 |
|---|---|---|---|---|---|
| project | 否（导入/工作台） | 是（问题/下一步） | — | — | 导入、skill 布局 |
| document | 否 | 否（元数据只读） | — | 导入 deferred | 阅读器、文件版本 |
| entry | 慎（需先有写 API） | 按 kind 窄字段 | 笔记挂 entry | 导入 deferred | 关系图、原始 JSON |
| task | 是 | 是（新修订） | 从 experiment 生成 | 导出包 deferred | 命令/环境细节 |
| run | 专用 start | 专用 update/assess/accept | cite 到提纲 | 导入结果 deferred | 对比页 |
| note | 是（依赖 locator） | 仅关联 entry | 是 | — | 阅读器划词 |
| paper_binding | 少用盲插 | 确认卡 | 是 | — | 自动匹配 UI |
| section | 是 | 是 + 排序 | — | — | — |
| outline | — | — | 是（cite） | — | — |
| card | 是 | 是（expectedHead） | 引用/关系 | 包交换 deferred | 冲突解决、关系图 |

导出类：报告/主张草稿 → 导出确认卡；其余「请在原页面/导入流操作」。

---

## 5. REG-3 需要补的东西

### 5.1 本体与契约缺口

1. 宿主 `ModuleOntology` / adapter（对标 `inquiry_module.dart:308`）——现无。  
2. 多数类型缺少 **revision/version** 字段与 `expected_version` 写协议（task/card 已有可参考）。  
3. 无统一 `validatePayload(type, …)`；需按类型补校验或从现有 FormatException/`_check`/`runAssessment` 抽取。  
4. `outline.evidence_id` 多态 ref、 `entry.data` 开放 JSON —— FieldKind 可能不够；需约定或「需要新类型」。  
5. change_log 未跟踪 `project`/`note`/`paper_binding`——迁 v2 投影时是否补触发器待定。  
6. 软删/restore：科研多为硬删或仅 rk_documents 软删；与询价 `delete/restore` 不对齐。

### 5.2 建议写工具清单（命名对齐 GROK-5 §5：`research.*`）

**建议新增（通用/半通用）**

| 工具 ID | 效应 | 调用 | 校验 |
|---|---|---|---|
| `research.update_project` | 改 question/next_step | `saveProject` | checkedProject；建议补 expected 快照或 version |
| `research.create_task` / `research.update_task` | 新建或新修订 | `saveTask` | 返回 id+revision；禁止改历史行 |
| `research.create_note` | 新建笔记 | `saveNote` | page/evidenceKind |
| `research.set_note_entry` | 挂/摘条目 | `setNoteEntry` | 同项目 |
| `research.add_section` / `update_section` / `move_section` / `delete_section` | 提纲段落 | OutlineStore | `_check` |
| `research.cite` / `remove_outline` | 证据链接 | cite / removeOutline | accepted run 规则 |
| `research.card_save` | 卡片修订 | `CardStore.save` | expectedHead；引用存在 |
| `research.create_record` / `update_record` | **仅**当 REG-3 为 entry 等补齐 Store 写与 version 后 | 待定 | validatePayload 待建 |

**建议专用（勿并入裸 CRUD）**

| 工具 ID | 理由 |
|---|---|
| `research.start_manual_run` / `update_manual_run` | 状态机与 `_localManual` |
| `research.assess_run` | `runAssessment` 规则 |
| `research.accept_run` | 证据接纳；影响 cite |
| `research.confirm_binding` / `insert_binding` | 消歧级联 |
| `research.export_report` / `export_claim_drafts` | Q10 已开放本机导出 |
| （不开放）`import*` / `export_task` / `export_result` / `export_skill_experiment` | Q10 deferred |

**卡片首期建议开放类型**：`project`（编辑）、`task`、`note`（新建+关联）、`section`、`outline`（关联）、`card`（编辑）。  
**延后**：`entry` 通用写、`document` 文件写、`run` 通用 CRUD、`paper_binding` 盲写、全部导入导出除两则本机导出。

---

## 6. 未能静态确认

1. 宿主是否已有任何 `research.*` 写工具注册表（本任务未跑 Flutter；GROK-2 写为「建议新增」）。  
2. `entries.data` / `papers`/`sources` JSON 内作者、邮箱、机构等字段的稳定 schema（仅见 judgment 展示键，无完整 JSON Schema）。  
3. 是否存在 UI 路径更新/删除 `notes` 行（Store 层无对应 API）。  
4. `tasks`/`runs`/`projects` 的用户可见删除与级联策略。  
5. `paper_id` 是否总等于某 `entries` 行的 `data['id']`（逻辑约定 vs DB FK）。  
6. REG-3 最终把 `entry` 拆成多 `ObjectTypeSpec`（按 kind）还是单一 `entry`+kind 枚举。  
7. `outline.evidence_id` 在 ModuleOntology 中如何声明多态 ref。  
8. change_log 不跟踪 note/project/binding 是否为有意设计。  
9. **敏感字段请用户确认**：  
   - 将「未发表摘录与研究判断」（笔记摘录/正文、卡片正文、entry.data、task/run 载荷、project.question/next_step）标为 `commercial` 是否合适；  
   - 文献作者名若出现在 entry JSON，标 `personal` 还是 `none`；  
   - `author` 字段仅机器标记时是否保持 `none`。

---

## 7. 统计（回报用）

| 项 | 数 |
|---|---|
| 建议业务对象类型 | **10** |
| 顶层可登记字段（约） | **68**（project6+document5+entry5+task6+run6+note9+binding6+section7+outline5+card~8；含 id/fk） |
| entry 判断展示键（另册） | judgmentFields 各 kind 合计约 **30+** 路径（不计入 68，除非 REG-3 展开） |
| 建议 personal（待确认） | author 真人名；文献人名（若展开） |
| 建议 commercial（待确认） | 摘录/判断/问题/目标/运行载荷等（§0.2） |
| 建议 credential | 0 |
| 建议工具（写+导出） | 见 §5.2（约 20 个 id 量级，含专用与两则导出） |

