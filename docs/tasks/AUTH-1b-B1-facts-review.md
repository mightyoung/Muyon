# AUTH-1b B1 来源事实子片审查摘要

基线 develop `e473b9c205a215b440b56e465b5e357b21c8eff4`。审查者为独立静态 reviewer；执行者另运行测试。没有把静态审查说成独立运行验证，没有 B 合入许可。

范围：host_authorization_facts、FoundationRepository task 初始化、ImportCoordinator、KnowledgeService/PublicServices 与 AgentDispatch 外部接纳钩子及两份专项测试。trusted scope authority、clean 证明、review/final signing、自动调度和 C 尚未覆盖。

三次静态复查：首轮发现已存在 sibling 重开后的 conversation taint 和 workspace/global 失败来源门闩未继承；第二轮发现 previousAttempt 只读任务行漏掉旧对话间接 taint。每项新增行为 RED 后修复。末次 CLEAR：完整宿主事实继承、接纳前 durable marker 和稳定返回引用标记、after-await cancellation/status、owner 事务边界未发现剩余具体缺陷。

执行者证据：两份专项最终 +26 All tests passed；strict analyze No issues found；宿主全量 +964 ~3 All tests passed，三个既有跳过。六项变异分别移入 revision 身份、漏读持久 conversation、移除 invoke 前 marker、移除稳定返回源 marker、移除 domain import 前 marker、移除 indirect attempt 继承；全部 exit1 且 Expected/Actual 行为失败，编译失败不计，源码逐字节恢复。恢复后的 strict analyze No issues found，最终 research/L2 分类补充后宿主全量 +964 ~3 All tests passed；exact SHA CI 见后续执行回报。

限界：所有新增宿主测试为真实磁盘 DB/Registry/Agent 的本机 harness；LoopFixture 仅协议 fixture，无真实模型证据。source 标记失败的内存拒绝限同 ManagedDatabase owner 当前进程，无法声称失败写跨进程持久；known external 内容仅在 marker 提交后接纳。global 采用保守全部来源规则，可能过度污染，不将其说成 clean 证明。本子片没有授予或扩大任何自动许可。
