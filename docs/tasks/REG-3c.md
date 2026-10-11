# REG-3c 科研写作大纲的具名工具（REG-3a 后续第一片）

分支 `task/reg-3c-research-outline-tools` · 基线 develop `cf75546` · 执行：grok-build · 审查：leader A（写入路径，审查会做变异）

## 背景
REG-3a 已开放 `research.save_note` / `add_outline` / `assess_run` / `accept_run`；其余操作在 `packages/research_module/lib/src/module_declarations.dart:119-142` 标为 `deferred`（`REG-3a-followup`）。科研没有统一的 save/delete/restore，多数对象没有统一版本号，**不能照搬询价的通用 CRUD**（[REG-3a 复审](REG-3a-review.md)第 21 行、[GROK-6 本体盘点](../reviews/2026-10-09-research-ontology-draft.md) §5）。本片只做写作大纲这一族。

## 范围（只这些）
- 读：`research.query.outline_rows`（`WorkbenchStore.outline`）、`research.outline.sections`（`OutlineStore.sections`）。
- 写：`research.outline.add_section`、`update_section`、`move_section`、`delete_section`、`cite`、`remove`（对应 `OutlineStore` 同名方法）。
- 每个开放的操作把 `module_declarations.dart` 里对应 `Operation` 从 `notExposed` 改成登记的工具，`ActionSpec` 照 `save_note` 那几行的写法补齐。

## 要求
1. **先读现有做法**：完整读 `research.add_outline` 从声明、registrar 登记、宿主 prepare / 一次审批 / invoke / 回执到测试的整条链路（`apps/muyon/test/reg3a_module_v2_test.dart`），新工具一律照这条链路做，不另造审批或回执。
2. **防并发覆盖**：写之前读 `OutlineStore` 的实际实现，找出能表示「用户确认时看到的状态」的字段（行版本、更新时间、内容摘要等）。工具参数要求带上这个期望值，执行时在同一事务里核对，不一致就拒绝并要求重新确认。如果某个方法既没有可用的版本信息、也无法在不改领域逻辑的前提下做到这一点，**这个方法不开放**，保持 `deferred` 并把理由写清，交回审查决定。
3. 范围：只接受选定范围内的项目和对象，越界拒绝；`delete_section`、`remove` 之后的引用完整性按 `OutlineStore` 现有规则，不新增规则。
4. 写入类 `ToolEffect.write`，走现有确认；敏感度按 ADR-0004 §12.1 注记（研究内容 `none`）。不碰导出（Q10 门面另做）、交换、设备收发。
5. 测试先行（每个工具至少：正常一次确认后写入并有回执；无确认不写；越界拒绝；期望值不符拒绝；重复操作 ID 不重复执行），再实现。

## 验证
- `packages/research_module` 与 `apps/muyon` 的 `flutter analyze`（info 也算失败）。
- `packages/research_module` 全量测试、`apps/muyon` 全量测试。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不导出 `MUYON_EVAL_REAL`。
- 自做变异：至少把「期望值核对」和「范围核对」各删一次，确认对应测试失败，恢复后 `git diff` 只剩你的正式改动。
- 只格式化改动过的文件；原始日志不进仓库；不改 `analysis_options.yaml`。

## 回报
分支与提交哈希（`git ls-remote` 确认）；开放了哪些工具、各用什么作为期望值；没开放的及理由；新增测试名与结果；变异结果；两个包的 analyze 与全量测试数字。
