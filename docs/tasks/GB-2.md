# GB-2 科研剩余写入的契约调研（grokbot，Opus 5.5）

分支 `review/gb-2-research-write-contracts` · 基线 develop（取最新）· 执行：grokbot（云端，只读代码与写文档；不运行 Flutter）· 审查：leader A · 给谁用：grok-build 的 REG-3d 及以后

## 背景
科研模块的操作在 `packages/research_module/lib/src/module_declarations.dart:119-142` 有一批标为 `deferred`。REG-3c（grok-build 正在做）只覆盖写作大纲一族。剩下的不能照搬询价通用 CRUD：科研没有统一的 save/delete/restore，多数对象没有统一版本号（[REG-3a 复审](../tasks/REG-3a-review.md) 第 21 行、[GROK-6](2026-10-09-research-ontology-draft.md) §5）。实现前需要逐个摸清「能不能安全地开放成工具」。

## 范围
`research.query.notes`、`research.query.bindings`、`research.binding.insert`、`research.binding.confirm`、`research.note.set_entry`、`research.project.save`、`research.task.save`、`research.run.manual_start`、`research.run.manual_update`，以及 Q10 已批准的 `research.export.report`、`research.export.claim_drafts`（本机导出）。

## 只做这些
产出 `docs/reviews/2026-10-11-research-write-contracts.md`，每个操作一节：
1. **领域实现**：对应的 `WorkbenchStore` / `OutlineStore` / `ResearchExchange` 方法 `文件:行`；做了什么写入（哪些表、哪些字段）；是否在事务里；有没有现成校验。
2. **并发保护**：有没有能代表「用户确认时看到的状态」的字段（版本号、修订号、更新时间、内容摘要）；没有的话，最小可行方案是什么（例如对读取结果取摘要作为期望值），以及它是否需要改领域代码。
3. **范围**：参数里的对象如何归属到项目，能否用现有选定范围解析器校验越界。
4. **建议的工具契约**：工具 ID、效应（读 / 写 / 外传）、参数（含期望值字段）、结果、拒绝条件。
5. **风险与结论**：可以直接开放 / 需要先补领域能力（写清补什么）/ 不建议开放（理由）。
6. 对两个导出：现有 registrar 缺「本机目标选择与允许根目录」门面（REG-3a 第 19、21 行），调研宿主现有的文件选择、备份目录或 `pickDirectory` 能力能否复用，给出最小门面设计和需要用户决定的点。

末尾汇总表：操作、结论、建议批次（REG-3d / 3e / 后置）、依赖。

## 不做
不改代码；不运行 Flutter；推测标「推测」；不确定写「未能静态确认」。

## 回报
分支与提交哈希；汇总表；需要用户决定的问题清单。
