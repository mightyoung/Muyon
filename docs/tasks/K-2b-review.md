# K-2b 审查

任务分支 `task/k-2b-probe-stream-ui` · 交付 `16d41e4`、`9ecaf5c`、`5ffc44c`，修订 `15ae865`，合入 develop（含 K-4）`5a9dbc7`，`1c443f3`（F2）· 核实：Sonnet 5.5 子代理（非作者，K-2a 审查者），两轮 · 2026-10-07

## 范围
新增 `services/models/capability_probe.dart`、`model_presets.dart`、`assistant/agent_drafts.dart`、`protocol_stream_view.dart`、`screens/model_profile_tile.dart`、`draft_view.dart`；改 `model_gateway.dart`（`detectedCapabilities` 只进 `toStoredJson`，任务载荷、摘要、预览字节不变）、`model_provider.dart`、`profile_repository.dart`、`bootstrap.dart`、`agent_model_turn.dart`、`personal_agent.dart`、`platform_shell_personal.dart`、`assistant_page.dart`。5 个新测试文件。ADR-0005 §8.4 守护测试与 `north_star_chain.dart` 0 行 diff。

## 第一轮（`5ffc44c`）
| 项 | 结论 |
|---|---|
| 测试连接 | P1 单请求；P2 只在勾选且 P1 有答复时发；取消 / 闸门拒绝 0 请求；均入账（`caller = capability_probe`）；无应答约 0.6 s 记 `timeout`；载荷与摘要为常量，不含用户数据；`probe_echo` 不注册不执行；结果只进 `detectedCapabilities`，点“采用”才生效 |
| 密钥 | 164 字符密钥经 400 / 401 / 500 响应体、SSE 错误、坏 SSE、断流、工具名与参数回显：检测结果、profile、账本、工作区文件 0 命中 |
| 草稿 | 12 种对抗流（answer 先于 type、嵌套键、转义、未终止、散文中的 `{`、代码围栏、DSML、超长键名等）均不泄露协议 JSON / 工具名 / 参数；丢弃不引用模型原文；只在内存 |
| 与 K-4 合并 | 无文本冲突 |

应改：F1 草稿对大流二次方开销（200 万字符兼容 36.5 s、原生 11.6 s）；F2 与 K-4 合并后一个新测试读 `payload['events']`；F3 `testConnection` 接线无测试（变异存活）。可选 F4：400 / 422 直接判“不支持原生工具”过强。

## 第二轮（`1c443f3`）
F1：80 ms 节流 + 结束时 flush、显示上限 2 万字符且不劈开代理对、事件长度与摘要仍覆盖全文；同探针兼容 155 ms、原生 1 ms，发布 3～4 次。F3：接线抽出并加 widget 测试，变异被杀。F4：P1 / P2 遇 400 / 422 均记“未能判定”并提示手动确认（审查认为合理）。F2：改读事件表，“草稿不出现在任何地方”的检查加扫事件表；K-2b 事件经 `ctx.event` / `ctx.commit`。`flutter analyze` 无问题；宿主全量 `+758 ~3`。

## 结论
**合入。** K-2 全部完成。
