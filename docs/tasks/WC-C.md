# WC-C：询价写工具结构化冲突

执行：Codex。派发：leader A，2026-10-11。集成：Leader B。基线：PR #50 head（`task/wcd-receipt-integrity-20261011` @ `01fbed45`，= WC-D + 回执完整性补修）；分支 `task/wc-c-structured-conflicts`。WC-D/PR #50 合入后改为基于最新 develop。

## 依据
`docs/reviews/2026-10-11-record-tools-gap-audit.md`（CR-11）第 1 节「片 C」与第 5 节「C 冲突」；ADR-0001 W3（冲突不加新状态，保持 `ToolCallStatus.failed` + 受信 `data`）；WC-A 已有 `WriteConflict`（`packages/muyon_module_api/lib/src/write_conflict.dart`）。

## 范围（只改 `apps/muyon/lib/platform/inquiry_record_tools.dart` 的出口与诊断，WC-D 的回执查核代码不动）
四类冲突各返回稳定错误码的 `WriteConflict`，放进 `failed` 结果的 `data`：
1. 选中快照或工作区变化（约 218-230 行）；
2. 同操作 ID 换参数或范围 → 明确身份冲突，不混为「未查到」（约 400-414 行）；
3. 目标状态或 `expected_version` 不符 → 附允许披露的当前版本（约 417-424 行）；无读取资格时不返回当前对象详情；
4. 删除引用预览不完整或引用对象版本已变化（约 469-488 行）——**真正构造「引用对象版本已变化」的用例**（CR-11 指出现测试名含 stale 实际只传空列表）。
错误转换在最外层事务之外（`Store.transaction` 正常返回即 COMMIT）：事务内以异常中止，外层转 `failed + data`。

## 测试先行
每类冲突：稳定错误码（改摘要文字不影响宿主分支）；冲突后 payload、版本、删除状态、变更日志、业务回执都不增加；结构化包装不让旧审批重新生效。保留 WC-D 与现有 generic write 测试全部通过。

## 变异（必须做）
把一类冲突改回纯文本失败；在事务内而不是事务外转换错误（构造提交后才报失败的情形）。测试必须失败。

## 约束
不改 `ToolCallStatus`；不碰 WC-D 回执查核与 Store 领域规则（候选准备抽取是 WC-B，以后再派）；strict analyze 零 info；`muyon_module_api`、`inquiry_module`、`apps/muyon` 全量；不合 develop。

## 回报（固定 6 行）
1. RED 提交哈希与失败第一行　2. 实现提交哈希（远端与本地一致）　3. 改动文件与行数　4. 变异结果　5. analyze 与三包全量（pass/skip/fail）　6. 未做或有疑问
