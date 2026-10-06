# E11 研究对象页与统一打开入口 审查结论

审查对象：`feat/e-support` @ `35d622f` · 审查：leader（代码核实由 Opus 子代理执行）· 日期：2026-10-06 · 验收口径：原说明（`2026-10-04-w1-agent-prompts.md`「追加 · E（opencode）· E11」）+ [HANDOVER-A 报告](HANDOVER-A-report.md) 第 2 节

**结论：修复后合并。** 没有阻断项。F1、F2、F3、F5 本轮修复，F7、F8、F10 顺手修。S6（原型对象跳转）由 leader 决定在第一阶段**明确搁置**。

## 范围
共 8 个文件（+1084/−68），全部在说明允许的范围内。没有改动 `prototype_module/**` 和 `workbench_app.dart`，也没有新增写库操作。与当前的 `develop` 合并没有冲突。

`research_module.dart` 增加的约 217 行包括：`objectPage`、两个辅助函数，以及 `_resolve` 中新增的 entry 摘要计算。这项计算是必需的：宿主目录给 entry 的摘要是 `sha256(jsonEncode(entry.data))`，没有它，从外壳打开 entry 会一律退回 JSON 页。✅

## 已有测试 `research_runtime_test.dart`
只改了第 499～520 行。原有的 `null` 断言全部保留：其他项目、错误模块、id 不存在、修订无效、摘要无效。改动前后都是 24 个 isNull、5 个 isNotNull、16 个用例。唯一改变的是：6 种类型现在断言返回各自的页面类型，不再断言返回 null。✅

## 核实结果
- **详情页只读**：没有按钮、点击回调或写库操作，数据只来自 SELECT。
- **旧修订**：显示该修订自己的内容，并标注「不是最新修订」；未评价的 run 不显示评价区。
- **重新校验**：所有类型在修订错误、摘要错误、项目不对时都返回 null。
- **外壳**：
  - 删除了写死的 document 分支，研究对象统一走 `openModuleObjectPage`；
  - 阅读器加右侧助手的布局保留；
  - 知识库和询价分支没有改动；
  - 页面关闭后在 `finally` 中 dispose 会话；
  - 查找绑定时要求 `nativeProjectId` 一致，不会自造绑定。
- **测试**：
  - analyze：research_module、apps/muyon 均无问题；
  - research_module：+208；`research_object_open_test`：+4；宿主全量：+400 ~1；
  - 格式化只涉及改动过的文件。

各页显示的字段：

| 对象 | 显示内容 |
|---|---|
| entry | 标题、类型、正文、来源 |
| outline | 标题、所属提纲、正文 |
| section | 标题、所属提纲、论证 |
| task | 标题、修订号、状态、说明 |
| run | 所属任务、修订号、状态、评价与结论（仅在已评价时显示） |
| card | 正文、修订号、引用列表 |

## 本轮必须修复

**F1（应改）任务页的「状态」没有按修订过滤**（`research_module.dart:601-603`）
查询语句是 `SELECT status FROM runs WHERE task_id=? ORDER BY rowid DESC`。探针显示，r1 页面显示的是 r2 运行的状态 `succeeded`，而 r1 自己的运行状态是 `failed`。这违反了「显示该修订的内容」。
**修复**：查询加上 `AND task_revision=?`，绑定 `task.revision`，并补一个测试。

**F2（应改，leader 决定）task、run、card、outline、section 无法从 `openObject` 打开**
`openObject` 会先调用 `host.tools.resolveScope(selectedObjects([ref]))`（`platform_shell.dart:143`），而宿主目录只收录 project、document、entry 三类，其他类型的引用会抛出 `Selected object is missing…`，页面什么也打不开。改动前也是这样，所以任务说明中「点开显示 JSON」的前提不成立。
**leader 决定**：对研究模块的引用，先调用 `openModuleObjectPage`（它会通过绑定和 `_resolve` 重新校验）；返回 null 时，再走原来的目录检查和 JSON 页。不要把这些类型加进宿主目录，因为那会改变助手的取材范围，属于设计变更。
**补测试**：从外壳打开 task 引用，显示的是任务详情页，不是 JSON 页，也不抛异常。

**F3（应改）外壳测试没有证明关闭页面后会话已 dispose**（`research_object_open_test.dart:187, 214`）
代码是正确的，但测试只在辅助函数上手动 dispose。在外壳测试中，关闭页面后要断言会话已经 dispose（例如调用会抛出 `Session disposed`）。

**F5（应改）`objectPage` 抛异常时会话泄漏**（`apps/muyon/lib/platform/object_pages.dart:56-58`）
catch-all 吞掉了异常，`openSession` 之后如果 `objectPage` 抛出异常，会话不会被 dispose。
**修复**：用 try/finally 保证 dispose。可以顺手用 `workspaces.ownerWorkspace()` 代替循环。

## 顺手修复
- **F7**：outline 页的标题和「所属提纲」总是相同；section 页把项目标题标成了「所属提纲」；run 页的「研究结论」标签和任务标题重复。改正标签。
- **F8**：`research_runtime_test.dart:500-501` 的新注释写错了，same-doc 并不属于另一个项目。恢复原来的理由：没有规范包文档的阅读器适配。
- **F10**：卡片 AppBar 的标题最长可达 240 个字符。截断到 60 个字符左右，并加省略号。

## 只记录
- **F4（行为变化）**：`sha256` 为 NULL 的旧文档（v5 新增该列时没有回填），以及快照文件缺失的文档，现在会打开 JSON 页，不再打开阅读器。这符合重新校验的规则。项目没有旧用户数据库，所以影响很小。
- **F6**：`locator` 是 Map，或者有 `doi`、`url` 时，entry 页不显示来源。工作台本身有显示。冻结期之后再补。
- **F9**：旧修订标签只用直接传参的方式测过，真实的修订路径已经由探针确认。被删除对象的外壳退回路径只有竞态才会走到，没有测试。

## S6 原型对象从助手回答跳回原型页：第一阶段明确搁置
核实结论：原型对象**没有工作区绑定**。
- 所有创建绑定的地方都只针对研究模块；
- 绑定表对每个模块、每个工作区只允许一条记录；
- 原型引用以 `page.id` 作为 `nativeProjectId`，按页面持久化绑定的方式行不通。

最小的接法要构造一个临时的内存绑定，这与「不要自造绑定」的约束冲突；另一种做法是给运行时加一个不依赖绑定的 `objectPage` 接口，改动更大。

**leader 决定**：第一阶段明确搁置（ADR-0001 的退出标准是「合入或明确搁置」）。验收账本如实写明：原型对象只能从原型模块页面打开，助手回答中点开显示 JSON 页。两个方案在第一阶段之后排期。

## 修复方式
执行者（junior）检出 `review/E11`，按上文修复，提交并推送到 `review/E11`。回报中附 analyze 结果、research_module 与宿主的测试数量，以及新增测试的名称。leader 派子代理定向复核后，合入 `develop`。
