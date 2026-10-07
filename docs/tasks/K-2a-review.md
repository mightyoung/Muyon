# K-2a 审查

任务分支 `task/k-2a-provider-streaming` · 交付 `1ed249a`、`aea0e0e`、`f2bcf98`、`c8d3879`，修订 `e9cdbd3`，合入 develop `e7442fc` · 核实：Sonnet 5.5 子代理（非作者，高强度），三轮 · 2026-10-07

## 范围
`apps/muyon/lib` 15 个文件（新增 `model_provider`、`openai_compat_provider`、`tool_names`、`token_estimate`、`model_request_gate`、`request_view`）、4 个新测试文件；修订时 `qa_service.dart` 两行（摘要剔除 `capabilities`）。ADR-0005 §8.4 的 12 个守护测试与 `integration_test/support/north_star_chain.dart` 均为 0 行 diff。

## 第一轮（`c8d3879`）
| 项 | 结论 |
|---|---|
| 交付 1～9 | 全部满足（3 有缺口，见 F1） |
| 唯一出口 | 变更中只有 `model_gateway.dart` 一处 `postUrl`，`ledger.begin` 在前，`begin` 失败不发送 |
| 无隐式回退 | 原生 400/422 只发 1 次、固定失败；兼容流式 400/422 发 2 次（F2） |
| 密钥探针 | 164 字符密钥，SSE 错误事件、坏 SSE JSON、400/500/302 响应体、违规回复、垃圾 200、chunk 中途 RST；任务、账本、会话、工作区全部文件 0 命中 |
| 授权 | `AlwaysConfirmGate` 非确认一律失败；模型输出与设置无法放行（ADR-0002 §3.1） |
| 自述偏离 | 全部可接受：无草稿界面（K-2b）、兼容预览 / 摘要逐字节不变（有测试）、`gateway.chat` 路径 `request_digest` 为空、原生单次回复一个调用、无 `destination`、`first_byte_ms` 口径、绝对上限待 K-3 传入、原生无效引用剥离并注明 |
| 变异 | 11 处，10 处被杀；M6b（只去掉 agent 层候选名检查）存活，provider 层兜底（F4） |

应改：**F1** 原生非流式在响应头阶段无超时（探针实测挂起）；**F2** 兼容流式 400/422 发 2 次请求。可选：F3 无数据时 `first_byte_ms` 记 0；F4 非候选工具名缺独立测试；F5 注释与报错文案；F6 QA 摘要含 `capabilities`；F7 K-3 接缝未标注。

## 第二轮（`e9cdbd3`）
F1～F7 全部修复。探针：原生非流式、原生流式、兼容流式对“接受连接不应答”均约 1 s 记 `timeout`；兼容流式 400/422 只发 1 次；兼容非流式 `chat` 保持原有重发。自加变异 F1、F2 均被杀。宿主全量 `+545 ~2`。

## 第三轮（合入 develop 后 `e7442fc`）
`flutter analyze`（apps/muyon 与仓库根）无问题；`agent_eval_test` + `mcp_token_redaction_test` `+61 ~1`；宿主全量 `+583 ~3`。E-1 的 `RecordingGateway` 覆写 `request()` 签名一致、经 `super.request` 走唯一出口并入账，计时与用量有效。

## 遗留（可选）
- E-1 评测的 profile 为兼容非流式；`chatStream`（流式 / 原生）不经 `request()`，`RecordingGateway` 捕获不到。评测改用流式或原生 profile 前须覆写 `chatStream` 记录首事件时间与 `Usage`（并入 K-3）。

## 结论
**合入。**
