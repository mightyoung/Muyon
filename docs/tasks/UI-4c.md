# UI-4c 一层子对话与任务现场

## 目标、依赖与边界

依赖 UI-2a、UI-4b、UI-3b。主对话加一层子对话浮层，关闭保存现场，明确引用时读取最新子成果。复用现有 TaskRecords/AgentResume/FoundationRepository，不能新建平行 Agent/事件/设备聊天内核；没有无限嵌套或强制后台常驻。

## 文件、接口与复用

新增 `platform/assistant_subconversations.dart`、`screens/assistant_subconversation_panel.dart`、host `test/assistant_subconversation_test.dart`；扩展当前 assistant_page 和个人会话关联。FoundationRepository现有conversations/messages/tasks为权威；如缺父子关系只增必要关联字段/表，先核开工版本。复用UI-3b浮层位置/输入持久。

`Future<SubconversationRef> openSubconversation(String parentTaskId, String goal)`；`Future<SubconversationSummary> readLatestSubconversation(SubconversationRef ref)`返回实际子task/message/event版本和摘要，不复制授权。关闭仅保存UI，不取消task。用户明确引用/查询才readLatest；卡可见不自动吸收结论，读取时版本变化重新核对。

## 验收与步骤

- [ ] `closing_panel_preserves_child_work`、`parent_reads_latest_only_when_requested`先失败：关闭/重开同输入和位置；子更新v2后主明确查询读v2，没引用主task不变。
- [ ] `child_summary_does_not_copy_authority`：子允许动作不因概要进入父授权；事件表仅存已有允许ID/摘要，不塞原文。
- [ ] 最小关系/结果ref接既有任务恢复与共享planning port，两模式不各建子会话实现。
- [ ] 云浏览器一层浮层/关闭/查询最新操作；云 host重开库与实际task恢复测试。进程终止/锁屏依最终设备能力清单，云未测的真实后台持续运行不写通过。
- [ ] 跑新增测试与 agent_resume、task_events_test.dart既有回归，独立审查/提交；关浮层功能保留子消息/任务可读。

## 通用门禁

本任务为待 leader 复核的派发草案，尚未开工；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。
