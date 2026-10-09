# GROK-5 本体驱动业务卡片的静态盘点（询价）

分支 `task/grok-5-ontology-cards` · 执行：grokbot（只做静态核对，不运行 Flutter，不改代码）· 审查：leader A 抽查 · 给谁用：REG-4c、AIUI-9

## 只做这些
产出 `docs/reviews/2026-10-09-inquiry-ontology-cards.md`：
1. 询价每个对象类型（`supplier_core/lib/src/ontology.dart` 和 `apps/muyon/lib/app/adapters/inquiry_module.dart:308`）逐个列出：
   - 字段：名称、类型、是否必填、枚举值、关联目标、敏感度；
   - 新建与修改时的校验规则，附 `supplier_core` 里 validate 的代码位置；
   - 现在由哪个 `Store` 写成员完成新建、修改、删除，以及有没有级联效果，例如合并、回收站、修订号；
   - 建议的卡片类型（新建 / 编辑 / 关联 / 批量），以及「不适合做卡片、应留在原页面」的理由。
2. 草拟 REG-4c 需要的通用写工具：
   - 工具 ID、输入模式（按本体生成）、效应、要调用的 Store 成员、要做的校验；
   - 与 Folio 现有助手工具（`supplier_core/lib/src/agent_tools.dart` 里的 create、update、delete 等）的对应关系。
3. 列出风险：哪些字段的写入会影响比价、定标、预算口径；哪些操作不可逆。

## 不做
不改代码与已有文档；不确定就写「未能静态确认」。

## 回报
分支与提交哈希、文档路径、各对象类型一句话结论、建议的工具清单。
