# GROK-10 拆分三个低风险超限文件（纯搬运）

分支 `task/grok-10-low-risk-splits` · 基线 `task/grok-9-large-file-split-plan` @ `3562557`（含拆分方案；合入顺序在 GROK-9 之后）· 执行：grok-build · 审查：leader A

## 依据
[拆分方案](../reviews/2026-10-10-large-file-split-plan.md) 第 6、16、17 节，和你在 GROK-9 拆 `agent_eval.dart` 的做法一样：纯搬运、公开 API 与导入路径不变、每个文件单独一个提交。

## 顺序（每个文件一个提交，提交说明以「纯搬运，无逻辑改动」开头）
1. `packages/supplier_core/lib/src/spec_parse.dart`（第 16 节）：草稿、切分和私有小类搬进 `part`，`_ClauseReader` 不切。
2. `packages/supplier_core/lib/src/spec_dictionary.dart`（第 6 节）：属性表分两段搬出，父文件用展开按原顺序拼回 `specProperties`（`const [..._a, ..._b]`）。**这是唯一允许的非搬运行**；每一项文本原样搬。
3. `packages/research_module/lib/src/reader/reader_page.dart`（第 17 节）：方案写的是 mixin。Dart 里 State 的私有字段、`setState` 在 mixin / extension 里使用可能触发 analyzer 提示（如 `invalid_use_of_protected_member`）或需要改写调用方式。规则：**只要需要改任何一行逻辑或引入新的 analyzer 提示，就不拆这个文件**，改为在方案文档末尾写明原因和可行的替代办法，然后跳过。

## 每个文件的核对（结果写进方案文档末尾「执行记录」，仿照 agent_eval 一节）
- **搬运核对**：拆分前后去掉空行与 `import/export/part/part of` 行后排序比对，差异只能是第 2 步的展开拼接那几行；把差异原文贴进记录。
- **顺序核对（仅 spec_dictionary）**：写一个**不提交**的临时 Dart 脚本或测试，拆分前后各输出一次 `specProperties` 的 `code` 列表（以及 `specClasses` 的 `code` 列表），两份逐行相同；记录两份的条数和 SHA-256。
- `flutter analyze`（所在包；info 也算失败）无问题。
- 测试：`packages/supplier_core` 全量 `flutter test`；`packages/research_module` 全量 `flutter test`。记录通过/失败/跳过数。
- `dart format` 只格式化改动过的文件；拆后每个文件不超过 800 行，记录 `wc -l`。

## 约束
- 不改任何逻辑、名字、可见性；不改测试、`analysis_options.yaml`、`pubspec`；不碰其他文件。
- 跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不导出 `MUYON_EVAL_REAL`；原始日志不进仓库。
- 发现疑似缺陷：写进方案文档「疑似缺陷」，不顺手修。

## 回报
分支与各提交哈希（`git ls-remote` 确认已推）；每个文件拆后的文件与行数；搬运核对和顺序核对结论；analyze 与两个包的测试数字；`reader_page.dart` 是否拆了，没拆的原因。
