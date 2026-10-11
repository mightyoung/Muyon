# WC-D 询价的只读业务回执查核（GB-5 片 D）

分支 `task/wc-d-inquiry-receipt-lookup` · 基线：WC-A 合入后的 develop（含 `muyon_module_api` 的 `BusinessReceiptLookup`、`BusinessReceiptQuery`、`BusinessReceiptLookupResult`）· 执行：Claude Haiku 5.5 · 审查：leader A（恢复路径，会做变异）

## 依据
- [CR-11 差距审计](../reviews/2026-10-11-record-tools-gap-audit.md) 第 1 节片 D、第 3 节恢复顺序、第 4 节 `changes`、第 5 节 D 的特征测试。
- [GB-5](../reviews/2026-10-11-write-card-contract.md) 片 D；ADR-0004 §4.5 修订（`BusinessReceiptLookup` 为独立 `ModuleFeature`）。
- 现有实现：`apps/muyon/lib/platform/inquiry_record_tools.dart` 约 380～414 行（`reg4c:` 身份构造、查询、匹配）与 501～524 行（写入回执）；`apps/muyon/lib/app/adapters/inquiry_module.dart`（现有 `receipt(operationId)` 属导入流程，**不能拿来代替**）。

## 要做的
1. **先补特征测试**（在动任何生产代码之前，钉住现有行为）：同 operation ID 同参数重试返回原结果且版本不再增加；同 ID 换参数被拒；无匹配回执时旧 `expected_version` 仍拒绝（现有测试 `apps/muyon/test/inquiry_general_write_tools_test.dart` 约 140～180、245～258 行已覆盖的不要重复，没覆盖的补上）。
2. 从 `inquiry_record_tools.dart` 抽出 `reg4c:` 的身份构造与读取为共享函数，单条工具继续用它，**行为不变**（第 1 步的测试必须照旧通过）。
3. 询价 runtime 实现 `BusinessReceiptLookup`，声明对应 `ModuleFeature`：输入 `BusinessReceiptQuery`，只读查询 `reg4c:{operationId}`；按 `BusinessReceiptLookupResult.verify` 比对身份；旧单条回执按审计第 4 节做兼容恢复（核验身份与完整性后用 `data.type/id/version/deleted` 与 `objectRefs`，不把任意 `objectRefs` 当已修改对象）；读取异常返回 `unreadable`，不当 `notFound`。
4. **严格只读**：不激活模块以外的副作用，不写任何表，不调用 `state.write`，不发通知。
5. 不改单条工具的执行顺序（那是后续片的事），不接宿主恢复调度（片 E）。

## 测试（审计第 5 节 D）
- 更新已提交后，用原 operation ID、原摘要、**旧基线**查到提交时的历史结果；对象随后又被修改，仍返回原回执版本。
- 同 ID 换参数 / 范围 / 工具 / 领域库 → `identityConflict`。
- 回执行损坏 → `unreadable`；不存在 → `notFound`。
- 查核前后：业务库、`muyon_change_log`、审批、调用回执行数、通知计数都不增加。
- 变异自检（结果写进回报）：去掉身份比对中的任一项、把损坏当 `notFound`、查核时写入一行，对应测试必须失败。

## 验证
`packages/muyon_module_api`、`packages/inquiry_module`、`apps/muyon` 的 analyze（info 也算失败）与全量测试（**三个包都要跑**，HK-3 曾因漏跑 `inquiry_module` 被组合 CI 抓到）。保留代理设置，`NO_PROXY` 加 localhost；不导出 `MUYON_EVAL_REAL`；只格式化改动文件；还原 `pub get` 生成的配置。全量测试若被外部 SIGTERM 打断，单独重跑受影响文件并如实说明。

## 回报
提交哈希；抽取的共享函数位置；新增测试名与结果；变异结果；三个包 analyze 与全量测试数字。
