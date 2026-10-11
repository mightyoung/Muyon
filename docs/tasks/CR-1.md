# CR-1 PR42 设计与安全审查（ChatGPT 6 Pro，线上只读）

执行：ChatGPT 线上（6 Pro）· 只读：通过 GitHub 链接看代码，不连本机、不跑测试 · 结果交回：把审查报告全文贴给用户，由 leader A 入库为 `docs/reviews/2026-10-11-pr42-design-review.md`

## 审什么
[PR42](https://github.com/mightyoung/Muyon/pull/42)（分支 `task/aiui-6-conversation-card-wiring-20261010`）：生产规划接入 stream/2 编译器与 library-2 目录；三档呈现偏好（自动 / 仅用户明确要求 / 只用文字，默认只用文字）持久保存；动态确认卡带宿主外部内容标记。原作者 Codex 未跑测试，CI 有 analyze 与 6 例测试失败，Claude Sonnet 正在修（SN-2）。**本审查只看设计与安全，不管格式和那几处编译错误。**

依据（都在仓库里）：
- [AIUI 流式界面契约](https://github.com/mightyoung/Muyon/blob/develop/docs/design/aiui-stream-contract.md)（§1 宿主给什么、§4 预览与最终计划分开、§6 中断与上限）
- [AI 原生方案](https://github.com/mightyoung/Muyon/blob/develop/docs/design/ai-native-ui-redesign-2026-10-09.md) §6 五条不变量
- [ADR-0002 分级授权](https://github.com/mightyoung/Muyon/blob/develop/docs/adr/0002-graded-assistant-authorization.md)
- [ADR-0001](https://github.com/mightyoung/Muyon/blob/develop/docs/adr/0001-leadership-and-scope-freeze.md) 末尾 10-10 几条（三档只管呈现、不能关掉授权；少用策略 A：只有用户在宿主入口明确要求才出卡片，模型自报不算）

## 重点问题（逐条给结论：成立 / 不成立 / 无法判断，附 `文件:行`）
1. 预览期间有没有任何动作可点；只有收到 `end` 且整份候选计划通过 `validateUiPlan` 后才安装动作吗？流中断、超限、坏行时是否一律走退路？
2. `surfaceId`、`revision`、`catalog`、`expectedDraftRevision`、动作路由是否全部来自宿主，模型能否通过流内容影响它们？
3. 三档：「只用文字」和「仅明确要求」是否真的阻止自动出卡；「明确要求」的来源是否只能是用户在宿主入口的操作并冻结到本次请求，模型输出能不能把它打开？三档是否碰了任何授权或确认（不应碰）？
4. 外部内容标记：来源是否只来自宿主污染事实；未知或查不到是否按外部内容处理；渲染后状态变化时，业务动作是否被拒绝（`surface.dart` 的 `capture.externalContent != hasExternalContent`）？有没有绕过的路径？
5. 已保存询价事实的读取：范围、钉住版本、敏感字段遮盖是否完整；有没有把未核验内容当事实展示？
6. 失败的既有测试（`assistant_production_policy_model_test`、`assistant_production_policy_order_test`、`assistant_subconversation_widget_test`）从代码看最可能是 PR42 改坏了哪条行为？给出你的判断，供 SN-2 参考。

## 输出格式
- 第一行结论：可以在修好 CI 后合入 / 需要改设计 / 有阻断。
- 然后按上面 1～6 逐条；最后列「建议 SN-2 顺手处理的问题」和「范围外问题」。
- 只写你在代码里确认过的结论，推测要标「推测」。不贴大段源码。
