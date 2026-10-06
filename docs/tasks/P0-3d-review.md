# P0-3d 审查

审查分支 `review/P0-3d` @ `32ed849`（基于 `review/P0-S1` 的 `3b237d7`，与 develop 无冲突）· 审查 leader · 核实子代理 `reviewer-sonnet-high` · 2026-10-07

**结论：通过，合入。** 两条应改都是测试缺口，实现经探针确认正确；按收口原则先合入（第一阶段关键路径），缺口转 [P0-3e](P0-3e.md)。

## 范围
6 个文件：`personal_agent.dart`、`model_gateway.dart`、`north_star_chain.dart`、新增 `assistant_protocol_correction_test.dart`、`credential_redaction_callers_test.dart`、`P0-3d.md`。
`credential_redaction_callers_test.dart` 不在允许清单，但改动必要：新代码下长密钥用例在第一轮确认后进入纠正轮，旧测试会停在 `waitingConfirmation`。改动只加了「确认两轮」的循环，`failed`、`model_reply_not_json`、通知、四处无片段断言原样未动。**认可。**

## 核对

| # | 约束 | 结论 | 依据 |
|---|---|---|---|
| 1 | 不合规回复不变成提议或写入；不提取、不剥离、不解析 DSML | 满足 | `_protocolReply`（`personal_agent.dart` 约 484-503）整段 `jsonDecode`，类型与字段严格校验，否则 null → `_correctOrFail`。探针 11 例（围栏 JSON、前缀/后缀文字、两个 JSON 拼接、DSML、顶层数组、字段类型错、未知 type 等）：每例 2 次请求、2 次确认、0 次工具调用、任务 failed |
| 2 | 纠正上限 1，计入 `maxRounds`，经网关、确认、进账本；丢弃的回复不保存不回传 | 满足 | `maxProtocolCorrections = 1`；纠正只追加固定常量消息；第二次请求消息数恰为第一次 +1，不含模型文本 |
| 3 | 失败原因固定，不引用原文 | 满足 | `personal_agent.dart:515-519`；164 字符密钥两轮回显，task/payload/通知/会话/账本无 12 字符片段 |
| 4 | `response_format` 范围与 400/422 回退 | 部分满足 | 只对 `assistant` 加；其余 6 个 caller 不加不重发。401/403/404/413/429/500 只发 1 次；持续 400/422 恰好 2 次、两行进账本、重发 body 与首发去掉参数后逐字相同、`beforeSend` 每次都调；记忆键 `endpoint|modelId`，仅在内存。不足见 O1 |
| 5 | P0-S1 不被削弱 | 满足 | R1 固定错误文本原样保留；400 回退抛 `model_http_NNN`，不含响应体（含密钥的 400 体探针无泄漏） |
| 6 | O1 链路预览 | 满足 | `north_star_chain.dart:459-464`：仅成功时取 summary；记录 `protocolCorrections` |

- **变异**：关闭纠正（6 例失败）、去掉 `response_format`（2）、去掉 400 回退（1）、上限改 2（4）、纠正消息带上丢弃回复（3），都被抓到。**未被抓到**：从文本中用正则提取 JSON（M6）、任何 HttpException 都重发（M8）。
- **重跑**：`flutter analyze` `No issues found!`；目标三个文件 `+21`；宿主全量 `+441 ~2 -2`，2 个失败只是 `research_object_open_test.dart` 两例（develop 已知，P0-F2）。
- **开发验证**（执行者）：真实 deepseek-chat 无头链路 3/3 `passed: true`，均未触发纠正。不计为 P0-4 证据。

## 转 P0-3e（应改，测试缺口）
- **T1**：守住「不提取、不剥离」：代码围栏 JSON、前缀文字 JSON、后缀文字 JSON 都被纠正或失败，`toolCalls == 0`（M6 必须失败）。
- **T2**：守住重发范围：401 或 429 只发 1 次请求；持续 400 恰好 2 次请求（M8 必须失败）。

## 可选（并入 P0-3e）
- **O1** `model_gateway.dart` 约 165 行：`_noJsonObject.add(key)` 在重发之前执行，别的原因导致的 400（上下文超长、参数错误）也会把该端点+模型永久标记为不支持 JSON 模式，悄悄削弱 D1 的主要修复。改为重发成功后才记住，并补测试。

## 只记录
- 执行者本机 `ci.sh` 中 inquiry 有 46 张截图像素差异（0.x～1.x%），本分支没有改 inquiry；本机已升级 macOS 27 / Xcode 27，判断为渲染漂移，另行处理。
