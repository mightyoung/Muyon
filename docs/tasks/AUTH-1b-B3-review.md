# AUTH-1b B3 optional/manual 独立复审

非作者 reviewer 固定 `d022c5e0c4377a22813875ab85cd04b6085ca64b`，相对已审 B12 d4 的完整 9 文件（含 6c05bdf optional/manual consumer），没有只看取消4文件。原报告只在 `/tmp/AUTH-1b-B3-independent-review-d022c5e.md`；本文件为摘要，不提交原始 logs/driver。

## d022 独立结论：BLOCK

原 6c05bdf 取消 BLOCK 已关闭：公开 PersonalAgent.cancel 的 mixed native read/send 审查 barrier 与 review INSERT 失败均 cancelled，零 effect/approval，最终 owner write canCommit 检查 token/flag/terminal。人工确认 body stale 与完整 endpoint mismatch 的额外真实 Agent 探针也零执行。亲跑 strict `No issues found! (ran in 10.5s)`，重点61与边界23共84通过；未跑作者 full/变异，也未冒称真实模型/实机。

新 BLOCK：native arguments.destination 的完整 query 被保存到 preview.parameters、step.calls 与 step.assistant.tool_calls arguments；顶层 masked destination 不能闭合此通道。实际有效纯 query driver 编译通过，到真实 waitingConfirmation，effect=0，顶层 mask 正确，preview 包含 synthetic unique-private-query，行为断言失败。早期临时driver的编译及非法endpoint诊断不计有效证据。

Optional WATCH：invocationTasks/invocationRequests/toolReviews/_premarked 生命周期未清理，可后续完成终态清理。本轮不将其风格扩成阻断。

## 修复策略与作者证据

实时 immutable invocationRequests 继续持有完整 actual parameters/destination，全部 identity/prepare/review/invoke 仍以该值复核。仅持久展示副本的参数 destination、native assistant arguments、手动 startTool 用户消息改为 masked destination。丢失完整私有绑定的重建 Agent 不能从 masked 值重构凭据，实际 intent 不符则失败闭合；没有降低 endpoint equality。

新增4条真实公共 API 回归：native/manual start × live/recreated Agent。live 手动执行 handler 读到完整实际 URI/参数，approval manual/null grantId/real review ID；recreated Agent 零 effect/approval、failed。全过程 task/card/assistant arguments/用户消息不含 query。SQLite + loopback scripted model fixture，不是实际 provider 或真机。

作者先运行独立探针形成全持久task泄露 RED 后最小修；基础52项回归与隐私4条通过。独立/tmp副本三个编译有效行为 mutants（card parameters/native arguments/manual user message）全部杀死，逐字节恢复，strict `No issues found! (ran in 7.2s)`；恢复后 full `+1021 ~3: All tests passed!`（1:50），四个被测源/测试文件与作者工作树逐字节相同。原始 logs/driver 全在/tmp。

`d022c5e` CI [37733757699](https://github.com/mightyoung/Muyon/actions/runs/37733757699) exact head completed/success 不覆盖上述独立 BLOCK，旧提交仍不建议接纳。新修复精确提交须再独立复审与CI；B3/C、生产 clean proof/自动 grant path 未由此 partial 交付，也未合 develop。

## 2f795fd 修复独立复审：checkpoint CLEAR

非作者固定 `2f795fdf16a2fbf73dcb33399d2c953943b28af4`，独立 `review/auth-1b-b3-privacy` 工作树检查相对 develop `08722e8`／B12 d4 的完整 B3 11 文件 +667/-29。原始报告仅在 `/tmp/AUTH-1b-B3-privacy-independent-review-2f795fd.md`，旧 d022 BLOCK 报告保留。

亲跑 strict `No issues found! (ran in 9.6s)`；隐私4组合及取消、manual、batch、events、resume、personal 共65通过；原有效 query 泄露探针、body stale、完整实际 endpoint mismatch 三项只改fixture路径后共3通过，总68。真实 live handler仍读到完整actual URI/参数，人工审批manual/null grantId/实际review；重建consumer缺私有绑定则零approval/effect failed。取消及review INSERT失败均取消，两个原BLOCK关闭，无新阻断，建议父接纳 optional/manual checkpoint，仍须精确HEAD CI。

限界：只处理协议顶层 string destination 的持久展示副本，不声称任意自由文本／nested数据／handler返回值通用脱敏；当前native目的地提议同为顶层字段，未找到实际nested绕过。私有 invocation/task/request/review 与 premarked 映射终态清理保留 WATCH。Reviewer 未亲跑full、mutants、CI、真实provider或真机；作者恢复全量及变异证据独立列在上文。未启用生产自动授权、未完成B3/C、未合develop。
