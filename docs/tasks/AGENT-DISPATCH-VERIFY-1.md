# AGENT-DISPATCH-VERIFY-1：调度安全独立补核

执行分支：`task/agent-dispatch-safety-verification`。基线：远端 develop `864d4317f8b8f923981dfc703860258b7cc062f4`（2026-10-09 实际 fetch）；交接 `b87a22b2` 之后仅两项文档提交。执行工作区 `/private/tmp/muyon-agent-dispatch-verification`，原工作区脏文件保留。

用户授权：独立复核 cc05fa3 读参数恢复及 UI-4c 只读子任务 prepare/invoke 边界；仅有效行为 RED 后最小修复、提交推送任务分支，不直接合入 develop/main。工具注册表只读；不改 REG3a、research/prototype、bootstrap、REG4b 导入文件。

交付：新增 `apps/muyon/test/agent_dispatch_safety_verification_test.dart`；独立复核记录在 [review](../reviews/2026-10-09-agent-dispatch-safety-verification.md)。本次生产改动只在 `agent_dispatch.dart` prepare 返回后再次检查子任务效应。

判据：撤销或效应变化不能执行非读 handler；只读明确 invalidArguments 可回模型；拒绝、取消、未知、混合失败不得恢复旧写入；正常读取、父任务独立批准写入、重启 resume 保持原合同。测试以真实 ToolRegistry、FoundationRepository 的任务/事件/回执表与 loopback 模型夹具执行，无真实模型或设备验收主张。

验证：在 `apps/muyon` 执行 `flutter analyze --no-pub`，及 `flutter test --no-pub` 对本专项、agent_read_argument_recovery、read_argument_recovery、assistant_subconversation、assistant_subconversation_running、assistant_subconversation_rejection、agent_batch_card、agent_resume、personal_agent_rejections、tool_registry、assistant_tool_grants_dispatch 测试文件。在 `packages/supplier_core` 执行 `dart test test/agent_tool_argument_result_test.dart`。最终任务提交应通过远端 Linux CI 后由父任务安排审查合入。

边界：registry 无公开同 ID 替换/效应更新 API，普通 ToolDescriptor.effect 是 final。变化效应测试用公开注册入口接纳的描述器子类覆写 getter；这是可控边界探针，不证明当前生产模块存在热替换路径。阶段版本、RED/GREEN、未测项及下一步见 review；原始日志不入库。
