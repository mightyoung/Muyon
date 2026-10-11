# HK-1 拆分 `assistant_procurement.dart`（搬运 + 扩展包装）

分支 `task/hk-1-procurement-split` · 基线 develop `cf75546` · 执行：**Claude Haiku 5.5** · 审查：leader A

## 依据
[拆分方案](../reviews/2026-10-10-large-file-split-plan.md) 第 10 节。`packages/supplier_core/lib/src/assistant_procurement.dart` 1104 行，目标每个文件不超过 800 行。
方案写的是 mixin，但 GROK-10 已证明「mixin on 本类」会循环继承。本任务改用**同库私有扩展**：私有方法搬进 `part` 文件里的 `extension _Xxx on AssistantProcurementTools { ... }`。同一个库里，扩展能访问类的私有成员，类里原来的 `_compare(...)` 这类调用不用改写就会解析到扩展方法。

## 怎么拆
1. 读懂文件：`AssistantProcurementTools`（第 54 行起）是唯一的大类。构造函数、字段、`_load`、`_save`、`_check`、`execute`（约 762～857 行）**留在原文件**。
2. 新建三个 `part` 文件（第一行 `part of 'assistant_procurement.dart';`），父文件加三条 `part '...';`：
   - `assistant_procurement_schema.dart`：约 118～216 行的工具清单与记录投影方法（`_tool`、`_args`、`_live`、`_record` 等）→ `extension _ProcurementSchema on AssistantProcurementTools { ... }`
   - `assistant_procurement_compare.dart`：约 217～761 行（候选、资质、数字、价格问题、对比、项目差异）→ `extension _ProcurementCompare on AssistantProcurementTools { ... }`
   - `assistant_procurement_import.dart`：约 858 行到文件尾的 `_import` 与 `renderReport` 相关**私有**方法 → `extension _ProcurementImport on AssistantProcurementTools { ... }`
3. **只能搬私有实例方法**（名字以 `_` 开头）。以下一律留在类里，不搬：字段、构造函数、getter / setter、`@override` 方法、公开方法、`static` 成员。如果某段里夹着这类成员，就把它留在原处，只搬周围的私有方法。
4. 方法体逐字不变：不改名、不改参数、不改顺序、不改注释。唯一新增的是 `part` / `part of` 行、三个 `extension ... {` 开头行和它们的 `}`。
5. 顶层函数或常量如果在原文件里，就留在原文件（同库可见）。

## 停止条件（遇到就停下回报，不要硬改）
- analyze 报任何新的错误或提示（info 也算），且只靠搬运和包装解决不了；
- 需要改任何方法体、调用方式或可见性才能编译；
- 拆完仍有文件超过 800 行。

## 核对（结果写进回报）
1. **搬运核对**：拆分前后各取所有文件，去掉空行和 `import/export/part/part of` 行后排序，用 `diff` 比较。差异只能是 3 行 `extension _... on AssistantProcurementTools {` 和 3 行 `}`。把 diff 原样贴进回报。
2. `cd packages/supplier_core && flutter analyze`：0 个问题。
3. `cd packages/supplier_core && flutter test`：全量通过（原有跳过数不变，基线是 499 通过、3 跳过左右）。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不导出 `MUYON_EVAL_REAL`。
4. `dart format` 只格式化这 4 个文件；`wc -l` 记录各文件行数。
5. `git status` 里不能有别的改动（`pub get` 生成的 `analysis_options.yaml`、`xcconfig`、`Podfile` 改动要还原，不提交）。

## 提交与回报
一个提交，说明以「纯搬运，无逻辑改动（私有方法包入同库扩展）」开头。推到 `task/hk-1-procurement-split`，`git ls-remote` 确认远端与本地一致。
回报逐项写：提交哈希；4 个文件及行数；搬运核对 diff 原文；analyze 结果；测试通过/失败/跳过数；有没有触发停止条件。
