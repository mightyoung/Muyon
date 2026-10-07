# K-3 审查

任务分支 `task/k-3-budget-loop` · 交付 `5ba5c80`…`d3f7595`，修订 `dccbb6e` · 核实：Sonnet 5.5 子代理（非作者，高强度），两轮 · 2026-10-07

## 范围
`apps/muyon/lib`：新增 `agent_budget.dart`、`agent_event_sink.dart`、`context_compactor.dart`；改 `personal_agent.dart`、`request_view.dart`、`foundation_repository.dart`（`appendTaskEvent`、`updateTask` 保留 `events`）、`agent_eval.dart`、`screens/assistant_page.dart`（按阶段区分确认标题）、`model_gateway.dart`（`mask(profile, text)`）。新增 6 个测试文件与 `test/support/agent_loop_fixture.dart`；非守护测试 `personal_agent_streaming_test.dart` 改 2 行（多调用放开后改测重复 call id）。ADR-0005 §8.4 守护文件与 `north_star_chain.dart` 0 行 diff。ADR-0005 §6.3、§6.5 增“K-3 实现注记”。

## 第一轮（`d3f7595`）
| 项 | 结论 |
|---|---|
| 交付 1～6 | 全部满足；载荷键名称与含义不变，`AlwaysConfirmGate` 下每步回到 `waitingConfirmation`，单调用 `requestDigest == identityDigest` |
| 批量确认卡 | 每调用独立 prepare → 比对 → approve → invoke 与回执；重放不再执行；每卡 5 个上限 |
| 压缩 | 实发请求与预览、账本摘要逐字节一致；注入文本只作引用数据，摘要中的 `approve` 被丢弃；同暴露面其他端点 0 请求 |
| 密钥探针 | 摘要请求错误、SSE 错误、非 JSON 回复、工具异常均 0 命中；摘要合法 JSON 回显密钥会入载荷（O-3） |
| 自述偏离 12 项 | 11 项可接受；M2b 并非等价变异（测试缺口） |

应改：S-1 “失败即停”缺测（M2b）；S-2 `exposureAllowed` 未比较 `modelId` / `credentialRef` / `cloudProxy`；S-3 压缩确认框标题误导、评测在压缩阶段会报错；S-4 偏离未入 ADR；S-5 `personal_agent.dart` 由 1,195 行增至 2,404 行，须在 K-4 前拆分（另立 K-3b）。

## 第二轮（`dccbb6e`）
S-1～S-4 与 O-2（原生提示放开多调用）、O-3（摘要字段经 `gateway.mask` 打码）、O-4（失败的摘要请求计入预算）、O-6（后续阶段错误经脱敏如实报告）均已在提交中。M2b、变异 C 被杀；暴露面与密钥探针通过。`flutter analyze` 无问题；宿主全量 `+657 ~3`；E-1 夹具 22/22。

## 遗留（可选）
事件与状态不在同一事务、长任务每事件重写载荷（K-4 换表时解决）；卡内不逐个检查预算、卡过期只在确认起点检查（ADR 注记已写）；已签发未用的审批留到 TTL；`agent_budget_test` 关闭用例有短等待。

## 结论
**合入。** 下一步 K-3b 拆分 `personal_agent.dart`，然后 K-2b、K-4。
