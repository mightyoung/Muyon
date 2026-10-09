# AGENT-COMPLETE-1 任务完成证据判定（拟编号，待派发）

这是可审任务草案，不是已批准实现。基线0b64cfa；不重做K-3/K-4。当前AgentContext.finish收到非空回答可将task写succeeded；compat答案检查引用ID，native去掉无效引用并提示；这证明回答保存，不普遍证明任意业务目标达成。手动工具结果基于真实回执；实际failed/blocked/interrupted仍停止。此差异不是“所有答案都错误”的结论。

目标分两段：第一段只生成可审完成证据评估（不改终态），清楚区分answerSaved、verifiedToolEffects、unverifiedGoal及unknownOutcome；第二段仅对host明确登记的完成合同实施门禁，是否改变succeeded语义须用户决定。不能模型自由声称“完成”或新增一轮LLM judge代替业务事实。

Files拟：新增assistant/agent_completion_assessment.dart、test/agent_completion_assessment_test.dart；实际接finish时改agent_context.dart/agent_model_turn.dart，和预算任务互斥；仅必要UI标签展示，和UI4c assistant_page互斥。

输入为实际任务、现有ToolReceipt、ObjectRef/ArtifactRef与host完成条件（有则核，缺则unknown）；评估不授权限、不扩大范围、不执行工具。显式领域合同如“原确认recordIds均有实际提交回执且未知集合为空”；不能从任意用户自然语言偷偷推导强制写目标。

TDD拟：nonempty_answer_is_not_verified_business_completion；registered_receipts_satisfy_explicit_contract；unknown_or_failed_receipt_cannot_verify_goal；answer_only_chat_keeps_saved_answer；stale_object_revision_requires_recheck；cancel_or_block_never_restart。RED必须是行为断言，未运行。完整回归personal_agent/native streaming/rejections/agent_resume/task_events/REG4b。

安全保持：拒绝、cancel、未知不续跑，不新写工具，不改预算/modelcaps/grant/policy；事件只存判定代码与ID，不存敏感正文。用户决定：A建议保留当前task状态并增加“回答已保存/目标已核实”证据标记；B对明确host合同才将未满足判为未完成/需人工；不选“全部回答强制判失败”。终态枚举、原历史兼容及显示方式在B选择后另作设计。

完成门槛：合同和判定口径获确认，实际RED→GREEN、恢复/旧任务兼容、独审/完整门禁/任务分支CI。当前只有草案，无产品改变。
