# C6-FIX-2：真实工具结果与桥接出站的字段披露（CR-C6 I-2）

执行：待派（下一个能做安全路径的开发者）。派发：leader A，2026-10-12。集成：leader A。基线：C6 `2ce7c96f`（C6-FIX-1 合并后以其为基线）；分支 `task/c6-fix-2-20261012`。依据：`docs/reviews/2026-10-12-c6-opaque-reference-review.md`（在 `task/docs-20261012a`）I-2。

## 要做
把 `inquiryModelDisclosedFields` 字段登记规则（`notes`、`award_note`、`requirement` 等自由文本默认不出站，未登记 / 未知字段默认遮盖）接到所有模型侧出站组成，**本机保留完整结果**：
1. `inquiry.object` 返回的 `record.data`；global `inquiry.get/query/related` 的 `legacyValue`；底层 `supplier_core` `get`（`agent_tools.dart:567-588`）对模型侧的投影。
2. 工具结果历史（`agent_dispatch.dart:864-887` 的 `result.toJson()` 进模型消息）。
3. manual 恢复历史（`agent_resume.dart:155-190` 拼成「摘要 + JSON」文本）：改为结构化后再投影，或在拼接前投影。
4. Folio 模型桥（`supplier_core/assistant.dart:363-392` → `inquiry_plugin.dart:436-471` 直接发 `preview.body`）：发送前经同一字段门禁；逐次发送审批保留，确认卡展示的是过滤后的实际字节。
5. `projectMessages` 补 native `tool_calls.arguments` 与字符串内嵌 JSON 的投影（至少不让句柄外的原始摘要与自由文本漏出）。

## 测试先行
已保存报价 `notes: "CANARY-NOTES"`、`award_note`、`project_item.requirement`、存储中的未知字段：分别经 `inquiry.object`、global 查询、manual 恢复后再聊天、Folio 第二轮请求，断言**实际 HTTP body** 不含 canary；正例：已登记字段照常出站，本机 UI 仍显示完整值。

## 变异（必须做）
工具结果历史不过滤；Folio 桥绕过门禁；未知字段默认放行。都必须被测试抓到。

## 回报（固定 6 行）
1. RED 与失败首行　2. 修复提交（远端与本地一致）　3. 改动文件与行数；每条出站路径「已测 / 未测」　4. 变异结果　5. analyze 与相关包全量（pass/skip/fail 及分类）　6. 未做或有疑问
