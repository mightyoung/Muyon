# UI-4c 开工设计核对（待复核，未实施）

## 授权、基线与现状

本轮只准备任务/设计，不改产品代码或需要另行裁定的语义。独立分支 docs/ui4c-agent-repair-preparation-20261009；依赖基线0b64cfa528041081e1df0f4314c8125c883f5245（task/ui-2a-reference-return，Linux CI37912802381成功），develop仍20c30888d048b8fdd2db7a83e8d79c3c2d8a8268。UI-2a尚未合develop；本准备不合develop/main。

正式依据 docs/tasks/UI-4c.md、UI-2a.md、UI-4b.md、UI-3b.md；v6 README/tokens/components/frontend-memo；架构方案§8/20。原任务要求：一层子对话、关闭保现场不取消、只有明确引用/查询才读取最新子成果、不复制授权、不造第二Agent/会话/事件/设备聊天系统。

已核：FoundationRepository真实conversations/messages/execution_records/task_events，host schema12；没有父子关系。AssistantPage.dispose仅退订/释放控件，不cancel任务；输入草稿仍内存。UiWorkspaceStore使用settings中的CAS投影，不新增schema。PersonalAgent.start每次通过现有scope/model/tool授权；默认planning关闭，本地Intelligent provider未接。UI-2a actual对象/文件入口、NavigationAnchor可直接复用，云browser/PDF/HTML原生定位仍待验。

## 建议下一片范围

选“既有个人会话 + settings最小关联/现场投影”，暂不加schema13；不修改v2模块、预算、授权策略、REG4b导入/domain applyOffers或设备聊天。

父task下可有多个平级子会话，但子会话不得再创建孙会话。首次开子入口创建真实conversation及持久关联；重开使用已有SubconversationRef，不按goal文本全局去重。重复同一次创建手势复用host生成creationToken，原子事务唯一落一个conversation/link，避免UI双击与重开创建两份。交易写入由FoundationRepository提供一个host-only创建关联方法，不从widget直写SQL；所有权仍是现有FoundationRepository。助手数据归属不通过previousAttemptId表示，后者仍表示续跑。

最小关联值：parentTaskId/parentConversationId/childConversationId/creationToken/scopeKey/revision/createdAt；现场值draftText/scrollOffset/selectedProfileId/openState/lastReadVersion。settings键按host IDs编码，类型化解码；旧损坏值显示只读错误，不删历史。关联必须在写事务内重核父task/conversation一致、父不是子、scope仍当前；snapshot scope不能由模型扩大。

提议接口（formal两接口保留，新增命名参数是host防重创建令牌，不对模型开放）：
- Future<SubconversationRef> openSubconversation(String parentTaskId, String goal, {required String creationToken})
- Future<SubconversationSummary> readLatestSubconversation(SubconversationRef ref)
- Future<bool> saveSubconversationWorkspace(SubconversationRef ref, SubconversationWorkspace value, {required int expectedRevision})

open只创建/打开会话，用户在子输入明确发送后才调用现有PersonalAgent.start；不因点击对象就自动发模型。profile仅是选择，不复制review、grant、digest、authority或parent task payload。范围由host复核后沿用父范围或收窄，保持新任务原有授权链。

readLatest从同一DB读事务取实际最后message/task/event ID+顺序及内容版本，返回task状态、摘要、ObjectRef/ArtifactRef、readAt。对正在更新的子结果标“读取截至版本”，显式重新读取才刷新引用；不声称一次读取可永久保持最新。结果卡只展示状态/读取版本，未引用不改父消息/任务。事件仅允许ID/固定状态/摘要长度等，正文仍messages，不将内容塞入task_events。

引用建议：默认只读概要；“引用到主对话”需用户明确操作，引用进入父输入草稿/下一次发送，经已有模型外发review。真实来源与外部内容provenance必须随引用保留；没有host provenance证明时保守停在只读概要，不把子摘要洗成可信本机数据。不得以子授权复制、scope相同或摘要文本作为新的自动放行依据。这个接线具体范围应leader复核，不能靠普通appendMessage绕过来源证明。

## 页面与v6

AssistantPage增加有明确childConversationId的子模式，隐藏“新建子对话”入口及主会话切换，不自动_ensureConversation挑同scope主会话。新增panel复用现有消息/Task/ConfirmCard，不复制一套问答循环。关闭先持久草稿/滚动/选profile再dispose，只关闭UI；显式取消才走agent.cancel。Host关闭/进程中断遵现有recoverInterrupted，不保证锁屏常驻。

320与390宽用单层sheet；桌面1440宽用约360宽助手侧panel（安全宽度限制），采用token canvas/surface/ruleStrong/acc/warn，≥48点击区；200%字号按内容撑开/可滚动；浅深色、键盘/焦点环、减少动态效果覆盖。外部内容确认卡保持现有“仅这一次/拒绝”，不出现更多/全部允许/对话授权新选项；未知进度不显示百分比。这里是交互提议，不声称v6已有子对话完整设计稿。

## 文件所有权与排期

UI-4c独占新增platform/assistant_subconversations.dart、screens/assistant_subconversation_panel.dart、test/assistant_subconversation_test.dart；修改screens/assistant_page.dart、platform/foundation_repository.dart（仅关联创建入口），公开preview独立子对话夹具/测试。UI-2a已完成，没有并发编辑；若它重开修复assistant_page，UI-4c排队。foundation_repository/schema为共享热点，和任何迁移或任务完成状态修复互斥。

AGENT-COMPLETE-1草案涉及agent_model_turn/agent_context；AGENT-RECOVERY-BUDGET-1涉及agent_model_turn/agent_budget，因此先各写测试/只读评估，生产文件串行。AGENT-IDEMPOTENCY-1涉及agent_dispatch/personal_agent、business_tools/inquiry_write_tools、supplier_core assistant_procurement、AskPage；与未来REG4c及C/A/B复修同文件互斥。三草案不得借UI4c合成一个大PR，均先锁边界。

## 当前可实施与待决定

在既有授权下可立即继续：准备行为RED、类型化关联/CAS/现场存储及仅人类操作的单层面板；复用现有任务与确认卡，不改预算/授权。开编码前leader复核本设计具体接线及formal任务云门禁；当前UI2a云browser尚未验，允许依赖分支准备，不能把云门禁当完成。

需具体裁定：子成果是否允许直接送入父下一次模型请求（建议默认只读，显式引用且保留provenance后才可）；更严格Agent完成判定采用何种完成合同；预算恢复是否仅人工明确“继续”增加1步；旧导入同一intent重试与新intent再次导入如何划分。后面三项独立草案，未批准前不改语义。


## 独审修正与明确用户语义（2026-10-09）

独审无Critical，指出两项Important，现已补入约束：子task默认只读，不仅概要只读；每次显式读持久不可变引用版本，旧读不被v2覆盖。

host真实父子关系持久readonly标记；factory只提供effect=read候选，dispatch/实际invoke与model发送前重核关系、scope及非read拒绝。startTool、resume/retry、planning business入口均依据host关系，不信模型payload标记，不复制父grant/review。新增文件边界agent_task_factory.dart/agent_dispatch.dart/agent_model_turn.dart仅做子会话收窄守护，与其他循环修复互斥；不变预算或完成终态。子UI不显示主会话切换、新子入口或共享planning开关；原主会话不受影响。

每次显式查询生成不可变readRef：child/message/task/event边界、digest/readAt、ObjectRef修订及读取摘要快照。read history写现有settings投影，正文权威仍messages，事件只存ID。新读v2另存，重开可追溯v1/v2。关闭时CAS失败保持窗口/输入并提示冲突，不静默dismiss。

新增行为RED：forged_child_write_has_no_side_effect；readonly_survives_restart_and_resume；same_scope_parent_remains_writable；read_v1_v2_history_survives_reopen；close_cas_conflict_preserves_panel_input。独审发现已落实到设计，尚不是产品已修复声明。
