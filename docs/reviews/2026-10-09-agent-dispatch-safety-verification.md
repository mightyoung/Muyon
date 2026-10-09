# AGENT-DISPATCH-VERIFY-1 独立执行记录

基线：`864d4317f8b8f923981dfc703860258b7cc062f4`；对 cc05fa3 与 UI-4c 本次执行者为非原作者。读取批次审查、HANDOVER-LEADER、REVIEW、任务索引，以及原任务保存的 next-task-handoff。当前仓库无 `.agents/skills`，用户目录 `.agents` 仅有归档；归档技能无本次调度专项。使用 verification-before-completion 和 code-review 技能执行验证及独立补丁审查。

## 先交审查结果

- 未发现非读 handler 被越权执行。真实撤销测试在三处等待边界都拒绝；效应变化在 registry 内依靠批准/身份复核阻止执行。
- **应改：首次 prepare 等待期间 read→write 后，子任务会生成写确认卡；本探针明确批准卡后产生 issued、未消费的写批准，随后 _invokeOne 才拒绝。** 原代码在 prepare 前检查子任务只读，返回后直接按 access 分流，未重新校验。源码 `agent_dispatch.dart:146-158`，调用前已有守护在 `_invokeOne`；这不是已发生写入/外传。
- 最小修复：prepare 返回后、分流前再次 `checkTool(task.conversationId, prepared.info.descriptor.effect)`，共六行。未改 `tool_registry.dart`，未改恢复策略、预算、终态、授权或模块包。
- cc05fa3 调度恢复核对：`_correctableRead` 同时要求原调用 access/effect 为 read 与明确 invalidArguments（现 `agent_dispatch.dart:823`）；`_runReads` 丢弃同一步旧写入，`_complete` 仍使其他失败终止。`supplier_core/agent_tools.dart:303-326` 仅显式校验异常转为 invalidArguments，运行/存储异常保持 failed。真实 inquiry 无效字段回执测试也已重跑。

## 可复现证据

新增专项 17 项：三处 prepare 等待点 × 撤销/write/export/network，共 12 项；正常子任务 read 与独立批准父任务 write 控制 1 项；invalidArguments 与 failed/blocked/cancelled/interrupted 混合读且携带旧 write 共 4 项。等待用 Completer，先确认冻结 candidate 包含 read，再在 scope resolve 暂停时改变状态；不使用 sleep、私有字段或注册表伪实现。断言 handler 次数、终态、模型请求数、批准/回执以及混合步 round=1。

1. 未修改的 develop 实现首次 9 项：`+8 -1`，退出 1。编译枚举拼写错误已先纠正，其失败不算行为 RED。
2. 最终 17 项回到原 develop（只临时移除本次六行 guard，源 diff 为零）：`+16 -1`，退出 1；唯一失败 `child write at prepare boundary 1 has no effect`，`Expected: empty / Actual: [tool_approvals state=issued, authorization_source=manual, consumed_at=null]`。handler 次数零，任务 failed；有效缺口是子任务可以提案并领取非读批准。
3. 恢复最小补丁后同 17 项：`+17: All tests passed!`，退出 0。
4. 相关宿主回归 11 文件：`+106: All tests passed!`，退出 0。
5. 宿主 `flutter analyze --no-pub`：`No issues found!`，退出 0。
6. supplier_core 实际存储分类回归：`+7: All tests passed!`，退出 0（显式参数错误、snapshot 变更、SqliteException、未知工具/缺失业务记录均核查）。

本机原始日志仅 `/tmp/agent-dispatch-{probe,final-red,final-green,regression,analyze}.log` 与 `/tmp/agent-arguments-supplier.log`；不提交日志。Flutter 自动生成的 macOS 配置与 Podfile 已在本独立树清理，不动原脏树。

## 限制与下一步

效应更新探针用 ChangingDescriptor 覆写公开 getter；普通生产描述器 effect 为 final，registry 拒绝重复 ID 且无替换 API（`tool_registry.dart:200-237`）。不得把这项边界收紧称为当前生产热替换漏洞。撤销使用真实 setAvailability（`tool_registry.dart:272-284`）。registry.invoke 内第二次 prepare 与 dispatch 前再次 prepare 为测试边界 2/3（`tool_registry.dart:702,896`）。

本次未重跑无关 UI 矩阵、浏览器、原生设备、真实模型、全宿主截图；针对回归已充分通过，远端精确提交 CI 承担全包门禁。本记录不表示合入批准；独立补丁审查及精确远端 CI 结果在后续阶段记录，父任务决定合入，不改 main/develop。

## 独立补丁审查

- `/root/dispatch_patch_review`：非补丁作者，只读；APPROVE，仅本六行复核及新测试。亲自重跑专项 17 项全部通过、退出 0，diff --check 通过。首次 localhost WebSocket 代理失败没有算作测试通过，清除代理并设置 NO_PROXY/no_proxy 后重跑成功。未独立重跑全量或 CI。
- `/root/dispatch_boundary_review`：非补丁作者，只读；Architectural Status CLEAR，无架构阻断。亲读源码与 RED/GREEN/106 项/analyze 原始日志，未声称独立执行测试。指出 issued 来自 executeCard/registry.approve，而非 prepare；现有 _invokeOne 阻止 handler。确认不扩大父任务权限或读参数恢复语义。
- 两个独立 lane 都回报证据；最终补丁审查 APPROVE，精确远端 CI 尚须核实，父任务仍负责合入。
