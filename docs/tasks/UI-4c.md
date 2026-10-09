# UI-4c 一层子对话与任务现场

## 目标、依赖与边界

依赖 UI-2a、UI-4b、UI-3b。主对话加一层子对话浮层，关闭保存现场，明确引用时读取最新子成果。复用现有 TaskRecords/AgentResume/FoundationRepository，不能新建平行 Agent/事件/设备聊天内核；没有无限嵌套或强制后台常驻。

## 文件、接口与复用

新增 `platform/assistant_subconversations.dart`、`screens/assistant_subconversation_panel.dart`、host `test/assistant_subconversation_test.dart`；扩展当前 assistant_page 和个人会话关联。FoundationRepository现有conversations/messages/tasks为权威；如缺父子关系只增必要关联字段/表，先核开工版本。复用UI-3b浮层位置/输入持久。

`Future<SubconversationRef> openSubconversation(String parentTaskId, String goal)`；`Future<SubconversationSummary> readLatestSubconversation(SubconversationRef ref)`返回实际子task/message/event版本和摘要，不复制授权。关闭仅保存UI，不取消task。用户明确引用/查询才readLatest；卡可见不自动吸收结论，读取时版本变化重新核对。

## 验收与步骤

- [x] `closing_panel_preserves_child_work`、`parent_reads_latest_only_when_requested`先失败：关闭/重开同输入和位置；子更新v2后主明确查询读v2，没引用主task不变。
- [x] `child_summary_does_not_copy_authority`：子允许动作不因概要进入父授权；事件表仅存已有允许ID/摘要，不塞原文。
- [x] 最小关系/结果ref接既有任务恢复与共享planning port，两模式不各建子会话实现。
- [ ] 云浏览器一层浮层/关闭/查询最新操作；云 host重开库与实际task恢复测试。进程终止/锁屏依最终设备能力清单，云未测的真实后台持续运行不写通过。
- [x] 跑新增测试与 agent_resume、task_events_test.dart既有回归，独立审查/提交；关浮层功能保留子消息/任务可读。

## 通用门禁

本任务已按用户确认语义实施；交付验收状态见下方，未覆盖能力保留待验；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。


## 2026-10-09 实施边界与证据（交付验证中）

- 独立分支 `task/ui-4c-subconversations`，依赖 UI-2a `0b64cfa`；准备文档独审修正已发布 `2a4e781`。不合 develop/main。
- 子任务只提供 read 效应工具；宿主持久关系在 factory/model send/actual invoke 重新核对。子会话不复制父任务 authorization/review/receipt；主任务既有权限流程保留。
- 单层子会话复用既有 FoundationRepository/PersonalAgent。settings 仅保存关系、UI CAS 和不可变显式 read-history；正文与事实来源仍为 conversations/messages/tasks/events。
- 显式查询保存 message ID、内容 digest、task payload digest、event seq/digest、ObjectRef revision/digest/readAt。历史版本不会被新查询覆盖；结果只读展示，不自动注入父模型。历史对象引用标明需重新核对。
- 关闭先保存输入/执行方式/滚动位置和 openState；CAS 冲突保留窗口和输入，不静默关闭。关闭/卸载不 cancel；取消仍使用原 task 控制。
- 公开模拟入口 `?subconversation=1`，不连接产品数据库、模型或工具；浏览器真实执行与部署仍待验，不将 widget/build 视为 browser 证据。
- 完成判定、恢复预算、跨尝试幂等和视频仅保留准备草案；未改终态/预算/modelcaps/默认 planning/网页授权/REG-4b 导入与领域幂等。

验证：目标回归145项、最终host专项19项（含原确认摘要回归）、公开模拟2项通过，host/preview分析干净；有效RED覆盖缺失入口、子写入拒绝、失效键盘提交、损坏投影和旧子聊不可达。独立全分支审查发现的问题均修复并复核，无剩余Critical/Important。真实SQLite与新Agent恢复测试证明只读、重新确认、零模型发送；回环流式任务关闭后继续并保存输入/滚动。精确提交的完整Mac门禁、184截图比较、Linux CI和Web包以交付记录/任务分支CI为准；Mac历史46截图失败仍须本片重跑核对，不作为通过。云/实机/进程终止和prepare/invoke期间注册效应变化的直接专项保持未验。原始日志不提交。
