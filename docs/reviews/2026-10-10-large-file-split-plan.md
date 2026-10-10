# 超限 Dart 文件拆分方案（2026-10-10）

给后续拆分实现用。本文只定边界和搬运方式，不改产品逻辑。除文末单独执行的 `agent_eval.dart` 外，其余文件等 AIUI-9 生产接线合入后再拆，不与功能 PR 混在一次提交里。

- 分支 `task/grok-9-large-file-split-plan`，基线 `7f49efe`（develop 祖先 `a68ba43`）。
- 环境：Flutter 3.47.5（stable，revision `6a19cca564`，2026-09-17）/ Dart 3.13.4 / Engine `ab59836859`。
- 行数是 `wc -l`。扫描范围是 `apps/*/lib` 与 `packages/*/lib` 的 `.dart`。`.json` 不算。超过 800 行的一共 18 个，下面按行数从大到小。
- 公开 API 指类名、方法签名和现有导入路径。调用方继续 import 原来的文件。
- 仓库里已有的拆法是 `part` / `part of`（`platform_shell.dart` 和 `import_pipeline.dart`）。Dart 的一个类体不能拆到两个文件。已经是独立类或顶层函数的，用 `part` 原样搬走。单个类仍然超过 800 行的，用同库 `mixin X on 原类`，方法体原样搬，类声明只加 `with`。私有 `_` 成员按库可见，不改名，不改成公开。
- 下面的「预计」是区间行数加上 `part of` 和 mixin 声明，不是格式化之后的精确行数。

## 1. `packages/research_module/lib/src/app/workbench_app.dart`（1557）

职责：

- L23–57 `ResearchHome`，把保存导出文件的回调交给内部页。
- L58–80 `_ScopedResearchHome`。
- L81–125 状态、刷新、忙闲和提示。
- L126–144 `confirm`。导入导出前的确认对话框。
- L145–293 选文件、导入研究包、导入任务、导入运行结果、局域网文件。
- L294–516 `build`、空态、分页和卡片壳。
- L517–708 概览与项目编辑。
- L723–1015 文库、条目、笔记和找来源。
- L1016–1194 研究任务页和编辑任务。
- L1195–1537 对比、运行结果、评估、从计划建任务、导出和关联证据。
- L1538 起论文写作页。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `workbench_app.dart` | 两个外壳类，加 `with` | 约 180 |
| `workbench_overview.dart` | L517–708 | 约 200 |
| `workbench_library.dart` | L723–1015 | 约 300 |
| `workbench_tasks.dart` | L1016–1194 | 约 190 |
| `workbench_runs.dart` | L1195–1537 | 约 350 |
| `workbench_writing.dart` | L1538 至文件尾 | 约 80 |

`part of 'workbench_app.dart'`。四个页面块做成 `mixin ... on _ScopedResearchHomeState`。`build` 仍留在原 State 里，因为它是覆盖方法。

耦合：`section`、`projectId`、`busy`、`confirm`、`action` 留在 State。mixin 通过 `on` 使用它们。没有现成的 `part`。

安全相关，必须原样搬：`confirm` L126；调用点 L163、L214、L234、L1066、L1324。这里的确认是界面对话框，不是工具授权。

调用方：`packages/research_module/lib/research_module.dart`。

直接测试：`hosted_lan_hidden_test.dart`、`workbench_harness.dart`。

顺序与风险：放在中段。风险中：一个 State 上的 mixin 容易漏字段；确认文案不能改。

## 2. `apps/muyon/lib/services/transfer/transfer_service.dart`（1368）

职责：

- L22–31 `FlutterLanSecretStore`。
- L32–64 `TransferReceipt`、`TransferItem`。`grantsExecution` 固定为 false。
- L65–175 构造、出站账本、串行生命周期、监听和配对在线列表。
- L177–216 任务信封发送与补投。
- L218–395 收到的推送、条目、已读、接纳、标记已导入。
- L397–625 研究包判断、导出文件、导入包、解码。
- L626–671 端口、短码、探测、确认对端、撤销、启动。
- L672–875 冻结发送、准备发送意图、发送。
- L876–1217 聊天线程、已读、接纳、拒绝、重试、删除、关闭。
- L1219–1368 顶层 zip 清单读取和 CRC。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `transfer_types.dart` | L22–64 | 约 50 |
| `transfer_service.dart` | 构造、生命周期、信封、条目 | 约 400 |
| `transfer_package.dart` | L397–625 | 约 240 |
| `transfer_send.dart` | L626–875 | 约 260 |
| `transfer_chat.dart` | L876–1217 | 约 350 |
| `transfer_zip.dart` | L1219–1368 顶层函数 | 约 160 |

类型和 zip 函数是 `part` 原样搬。`TransferService` 的三段用 mixin。

耦合：`_node`、`_serialize`、`outboundLedger`、`database` 留在主类。zip 函数不碰这些字段，单独成 part 最安全。

安全相关，必须原样搬：L22–31 密钥读写；L59 `grantsExecution`；L69–71 出站账本；L485、L526、L533、L540 `checkCancelled`；L637–651 `confirmPeer` 与 `revoke`；L653–671 `start` 的密钥参数；L716–875 `prepareSendIntent`、`authorization.check`、`HostTransferLedger`；L882 `ChatLog.insertOutbound`。

调用方：`accepted_research_imports.dart`、`platform_tools.dart`、`transfer_chat_backend.dart`、`devices_page.dart`、`public_services.dart`。

直接测试：`assistant_transfer_authorization_test.dart`、`assistant_transfer_capability_boundary_test.dart`、`assistant_transfer_peer_identity_test.dart`、`assistant_transfer_progress_boundary_test.dart`、`chat_backend_test.dart`、`outbound_tool_ledger_test.dart`、`public_services_test.dart`、`transfer_chat_backend_test.dart`、`transfer_states_test.dart`。

顺序与风险：靠后。风险高：授权、账本、取消和密钥在同一类里。

## 3. `apps/muyon/lib/platform/tool_registry.dart`（1313）

职责：

- L17–28 `installToolRegistrySchema`，回执表和批准表。
- L30–130 `ToolReceipt`、`ToolPlatformException`、`HostScopeResolution`、`PreparedToolCall`、`_Tool`。
- L133–326 构造、策略、授权链接、取消、关闭、注册、列举。
- L327–489 `prepare`。
- L490–787 `approve`、`authorizationRequest`、`approveWithGrant`。
- L788–1100 `invoke`、`_dispatch`、回执和历史。
- L1102–1114 `_digest`、`_canonical`。
- L1115 至文件尾 `_Schema`。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `tool_registry_types.dart` | L17–130 | 约 120 |
| `tool_registry.dart` | 构造、注册、取消、关闭 | 约 220 |
| `tool_registry_prepare.dart` | L327–489 | 约 170 |
| `tool_registry_approve.dart` | L490–787 | 约 310 |
| `tool_registry_invoke.dart` | L788–1100 | 约 320 |
| `tool_registry_schema.dart` | L1102 至文件尾 | 约 220 |

类型、摘要函数和 `_Schema` 用 `part` 原样搬。`ToolRegistry` 的准备、批准、调用用 mixin。

耦合：`_tools`、`_active`、`grants`、`grantContext` 留在主类。`_digest` 被批准路径使用，和 `_Schema` 放在同一 part，或留在主文件。不要把 `_Schema` 改成公开类。

安全相关，必须原样搬：L17–28 表结构；L200–216 `cancelProvider` 与关闭时的 `cancel`；L488–493 批准注释和 `approve`；L552–593 `authorizationRequest`；L651–652 `approveWithGrant`（消费、审计、签名同一次事务）；L788 起 `invoke`。

调用方：`bootstrap.dart`、`host_tool_registrar.dart`、`inquiry_hub_authority.dart`、`inquiry_plugin.dart`、`inquiry_web_authority.dart`、`module_host.dart`、`agent_context.dart`、`agent_dispatch.dart`、`personal_agent.dart`、`foundation_repository.dart`、`host_tool_authorization.dart`、`inquiry_record_tools.dart`、`inquiry_write_tools.dart`、`mcp_adapter.dart`、`platform_tools.dart`、`ui_planning_source.dart`、`dynamic_workspace.dart`、`public_tools.dart`、`public_services.dart`、`transfer_service.dart`。

直接测试 35 个：`agent_dispatch_safety_verification_test.dart`、`agent_eval_stream_capture_test.dart`、`assistant_cancel_test.dart`、`assistant_grant_integration_test.dart`、`assistant_loaded_input_scope_boundaries_test.dart`、`assistant_outbound_authorization_test.dart`、`assistant_production_auto_order_test.dart`、`assistant_production_policy_order_test.dart`、`assistant_protocol_correction_test.dart`、`assistant_subconversation_test.dart`、`assistant_transfer_authorization_test.dart`、`assistant_transfer_capability_boundary_test.dart`、`assistant_transfer_peer_identity_test.dart`、`assistant_transfer_progress_boundary_test.dart`、`credential_redaction_callers_test.dart`、`dream_test.dart`、`host_tool_registrar_test.dart`、`inquiry_general_write_tools_test.dart`、`inquiry_hub_authority_test.dart`、`inquiry_module_adapter_test.dart`、`inquiry_scope_catalog_test.dart`、`inquiry_web_authority_test.dart`、`inquiry_web_task_stop_test.dart`、`inquiry_write_tools_test.dart`、`manual_resume_hold_test.dart`、`mcp_adapter_test.dart`、`mcp_token_redaction_test.dart`、`outbound_tool_ledger_test.dart`、`personal_agent_rejections_test.dart`、`personal_agent_streaming_test.dart`、`personal_agent_test.dart`、`platform_metadata_scope_test.dart`、`platform_tools_test.dart`、`support/agent_loop_fixture.dart`、`tool_registry_test.dart`。

顺序与风险：最后一批。风险高：这是工具授权和回执的本体。

## 4. `packages/research_module/lib/src/core/exchange.dart`（1263）

职责：

- L14–210 `ResearchExchange` 的路径、引用 SQL、规范化键。
- L212–547 导入、准备和提交研究快照。事务在 L306、L532、L542。
- L548–722 主张草稿导出、zip、清单校验。
- L723–837 准备和提交任务。事务在 L793、L817、L820。
- L838–1005 导出任务、运行结果、技能实验。
- L1006–1198 导入运行结果、导出报告。
- L1200 至文件尾 `ClaimDraftExport`、`PreparedResearchSnapshot`、`PreparedTaskSnapshot`。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `exchange.dart` | 构造和 L21–210 的键 | 约 220 |
| `exchange_research.dart` | L212–547 | 约 350 |
| `exchange_task.dart` | L548–837 | 约 300 |
| `exchange_result.dart` | L838–1198 | 约 370 |
| `exchange_snapshots.dart` | L1200 至文件尾 | 约 70 |

快照三个类用 `part` 原样搬。`ResearchExchange` 的三段用 mixin。

耦合：`_safe`、`_canonical`、`_entryKey`、`store` 留在主类。`_citedSql` 只被研究导入使用，可以跟那一段走，也可以留在主类。

安全相关，必须原样搬：两段 `BEGIN` / `COMMIT` / `ROLLBACK`（L306、L532、L542、L793、L817、L820），以及 `ownTransaction` 的判断。不能把提交拆成两次写。

调用方：`research_module.dart`（桶和 `src/research_module.dart`）、`skill_panels.dart`、`workbench_app.dart`。

直接测试：`core_test.dart`、`outline_notes_test.dart`、`research_skill_test.dart`、`skill_bridge_test.dart`、`skill_ui_test.dart`、`workbench_test.dart`。

顺序与风险：事务文件靠后。风险高。

## 5. `apps/muyon/lib/assistant/agent_eval/agent_eval.dart`（1246）

这一节按本方案执行，纯 `part` 搬运，不用 mixin。文件由多个顶层类和函数组成，不是一个巨型类。

职责：

- L1–58 库注释、`library;`、import，以及 `export '../selection_eval/llm_selection_eval.dart' show llmReportSlug, reportEndpoint`。
- L60–275 任务模型：`agentTaskCategories`、`AgentFailure`、`AgentFact`、`AgentExpectedWrite`、`AgentTask`、`fillPlaceholders`、`AgentTaskSet`、加载和解析、`_task`。
- L277–518 评分：`AgentObservation`、`AgentVerdict`、`judgeTask`、`_minus`、`_isSubsequence`、`numbersIn`、`answerStates`、`snapshotStore`、`checkWriteState`。
- L520–646 网关记录：`confirmsAsModelRequest`、`GatewayCall`、`RecordingGateway`。
- L648–1008 跑任务：`AgentTaskResult`、`AgentEvalModel`、`AgentSeeder`、`AgentTaskHook`、`AgentEvalRun`、`runAgentTask`、`runAgentEval`。
- L1010–1171 汇总和 `agentEvalReport`。
- L1173 至文件尾 `EnvironmentSecretStore`、`agentEvalSkipReason`、`agentEvalProfileFromEnvironment`、`agentEvalTimeoutFromEnvironment`。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `agent_eval.dart` | L1–58，加 6 条 `part` | 约 70 |
| `agent_eval_tasks.dart` | L60–275 | 约 220 |
| `agent_eval_judge.dart` | L277–518 | 约 250 |
| `agent_eval_gateway.dart` | L520–646 | 约 130 |
| `agent_eval_run.dart` | L648–1008 | 约 370 |
| `agent_eval_report.dart` | L1010–1171 | 约 170 |
| `agent_eval_environment.dart` | L1173 至文件尾 | 约 80 |

每个新文件首行 `part of 'agent_eval.dart';`。import 和那条 `export` 留在父文件。公开名字和 `package:muyon/assistant/agent_eval/agent_eval.dart` 不变。

耦合：

- `_minus` 定义在评分段（L329），`runAgentTask`（L806）调用。两边都是同一库的 part，名字保持私有。
- `_selected` 在运行段内部先使用后定义（L764 与 L940）。整段一起搬。
- `_task`、`_isSubsequence`、`_snapshotTypes`、`_count`、`_short`、`_proposedTools`、`_tryJson`、`_esc`、`_ms`、`_num`、`_usage`、`_row`、`_environment`、`_visibleAscii` 都只在自己那一段里使用。
- 没有现成 `part`。没有扩展方法。顶层常量 `agentTaskCategories` 跟任务段走。

安全相关，必须原样搬：L522–525 `confirmsAsModelRequest`；L553–621 `RecordingGateway` 的账本参数和 `ModelCancellation`；L772–815 里的 `agent.confirm` / `agent.cancel`；L817 `redactCredentials`；L1176–1186 密钥只从传入的环境映射读取；L1186 `agentEvalKeyVariable`；L1195 起跳过原因、配置和超时。不导出 `MUYON_EVAL_REAL`，不调用真实模型。

调用方：`lib/` 内没有文件 import 它。

直接测试：`agent_eval_test.dart`、`agent_eval_stream_capture_test.dart`、`confirm_title_test.dart`。

顺序与风险：第一个拆。风险低：不在 AIUI 接线和工具授权的生产入口上。父文件继续 export 原来的两个符号。

## 6. `packages/supplier_core/lib/src/spec_dictionary.dart`（1238）

职责：

- L1–117 版本、`ParamType`、`Order`、`EnumValue`、`SpecProperty`、`ClassParam`、`ParamBlock`、`SpecClass`。
- L118–198 来源、信号、协议、视频口、电源、屏蔽、绝缘的私有枚举表。
- L200–950 `specProperties`。注释分段：通用 L201、处理器 L262、计算机其余 L339、显示 L521、传感器 L605、信号 L660、气体 L676、网关 L756、PLC L788、报警 L828、电缆 L866、软件 L934。
- L952–1199 `_environment` 与 `specClasses`。
- L1201–1238 按代码查找、`classParams`、`classBlocks`。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `spec_dictionary.dart` | L1–198，加上把两段属性表拼回去的 `specProperties`，以及 L1201–1238 | 约 280 |
| `spec_dictionary_properties_a.dart` | L201–520 的属性，做成私有列表 | 约 330 |
| `spec_dictionary_properties_b.dart` | L521–950 的属性，做成私有列表 | 约 440 |
| `spec_dictionary_classes.dart` | L952–1199 | 约 260 |

属性清单今天是一个常量列表。拆开后父文件用展开运算按原顺序拼回 `specProperties`。每一项的文本原样搬。编码一旦发布不能改，这是数据，不是逻辑。

耦合：`_origin` 等私有表留在父文件，属性 part 仍能看见。`_propertyByCode` 依赖拼好的 `specProperties`，留在父文件。没有 `part`。

安全相关：没有授权、确认、账本、取消或事务。L519 的「正版授权」只是一条参数名。

调用方：`supplier_core.dart`、`agent_tools.dart`、`assistant_procurement.dart`、`product_params.dart`、`spec_ai.dart`、`spec_compare.dart`、`spec_constraint.dart`、`spec_extract.dart`、`spec_match.dart`、`spec_migration.dart`、`spec_parse.dart`、`spec_request.dart`、`spec_response.dart`、`spec_values.dart`。

直接测试：没有文件 import `src/spec_dictionary.dart`。`spec_test.dart`、`spec_security_test.dart`、`spec_match_test.dart`、`data_quality_scale_test.dart` 通过 `supplier_core.dart` 用到这张表。

顺序与风险：靠前。风险低。展开运算是唯一新增的非搬运行，顺序必须和现在的清单一致。

## 7. `apps/muyon/lib/platform/foundation_repository.dart`（1209）

职责：

- L14–236 记录类型：`AssistantConversation`、`AssistantMessage`、`PersonalMemory`、`ExperienceEntry`、`FoundationNotification`、`PersonalTaskState`、`HostLoadedInputProof`、`PersonalTask`。
- L238–391 仓库构造、刷新、加载输入绑定、迁移、会话和消息。
- L392–643 记忆的查询、保存、禁用、收窄范围、删除。
- L652–789 经验的查询、保存、核实、退役。
- L790–973 `writeOrganization`、快照、指纹、墓碑。
- L975–1011 通知。
- L1012 至文件尾任务的创建、更新、事件、对象链接、中断恢复。L1038 与 L1067 写明任务和事件同一次事务。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `foundation_records.dart` | L14–236 | 约 230 |
| `foundation_repository.dart` | 构造、会话、消息 | 约 180 |
| `foundation_memory.dart` | L392–643 | 约 260 |
| `foundation_experience.dart` | L652–789 | 约 150 |
| `foundation_organization.dart` | L790–973 | 约 190 |
| `foundation_tasks.dart` | L975 至文件尾 | 约 250 |

记录类型用 `part` 原样搬。仓库方法用 mixin。

耦合：`database`、`_id`、`_now`、`writeOrganization` 留在主类。记忆和经验的 `*InTransaction` 方法必须和 `writeOrganization` 同库，不能复制事务入口。

安全相关，必须原样搬：L141–169 `HostLoadedInputProof`（只有本事务能读冻结输入的来源）；L790 `writeOrganization`；L808 与 Dream 状态同事务的恢复；L1038–1137 任务创建、更新和事件的单次事务。

调用方（`lib/`）：`bootstrap.dart`、`agent_compaction_flow.dart`、`agent_context.dart`、`agent_dispatch.dart`、`agent_eval.dart`、`agent_event_sink.dart`、`agent_model_turn.dart`、`agent_resume.dart`、`agent_task_factory.dart`、`dream_service.dart`、`personal_agent.dart`、`ui_planning.dart`、`ui_planning_events.dart`、`assistant_subconversations.dart`、`host_authorization_facts.dart`、`host_model_authorization.dart`、`memory_review.dart`、`platform_tools.dart`、`ui_planning_source.dart`、`ui_workspace_store.dart`、`assistant_page.dart`、`dream_section.dart`、`dynamic_workspace.dart`、`execution_panel.dart`、`experience_section.dart`、`memory_page.dart`、`platform_shell.dart`、`workspace_repository.dart`。

另外 `integration_test/platform_device_test.dart` 和 `integration_test/support/north_star_chain.dart`、`north_star_checks.dart`、`north_star_records.dart` 也直接 import。

直接测试 57 个，都在 `apps/muyon/test/`：`agent_batch_card_test.dart`、`agent_budget_test.dart`、`agent_dispatch_safety_verification_test.dart`、`agent_drafts_test.dart`、`agent_eval_stream_capture_test.dart`、`agent_event_sink_test.dart`、`agent_read_argument_recovery_test.dart`、`agent_resume_test.dart`、`aiui_draft_recovery_page_test.dart`、`assistant_authorization_facts_test.dart`、`assistant_cancel_test.dart`、`assistant_loaded_input_authority_test.dart`、`assistant_loaded_input_scope_boundaries_test.dart`、`assistant_native_destination_privacy_test.dart`、`assistant_production_auto_order_test.dart`、`assistant_production_auto_write_test.dart`、`assistant_production_catalog_input_test.dart`、`assistant_production_model_binding_test.dart`、`assistant_production_model_credentials_test.dart`、`assistant_production_model_grant_test.dart`、`assistant_production_model_permission_test.dart`、`assistant_production_model_precredential_test.dart`、`assistant_production_model_protocol_test.dart`、`assistant_production_model_restore_test.dart`、`assistant_production_model_review_test.dart`、`assistant_production_policy_model_test.dart`、`assistant_production_policy_order_test.dart`、`assistant_production_policy_test.dart`、`assistant_production_usable_flow_test.dart`、`assistant_protocol_correction_test.dart`、`assistant_readable_tool_answer_test.dart`、`assistant_review_cancellation_test.dart`、`assistant_subconversation_running_test.dart`、`assistant_subconversation_test.dart`、`assistant_tool_grants_dispatch_test.dart`、`assistant_tool_provenance_test.dart`、`context_compaction_test.dart`、`conversation_shell_return_test.dart`、`credential_redaction_callers_test.dart`、`credential_redaction_test.dart`、`dream_test.dart`、`dynamic_workspace_return_test.dart`、`execution_panel_test.dart`、`foundation_integration_test.dart`、`inquiry_scope_catalog_test.dart`、`manual_resume_hold_test.dart`、`memory_page_test.dart`、`memory_review_test.dart`、`personal_agent_rejections_test.dart`、`personal_agent_streaming_test.dart`、`personal_agent_test.dart`、`platform_tools_test.dart`、`support/agent_loop_fixture.dart`、`task_events_test.dart`、`ui_planning_events_test.dart`、`ui_planning_harness_test.dart`、`ui_workspace_store_test.dart`。

顺序与风险：靠后。风险高：任务事务和加载输入证明不能拆成两次写。

## 8. `packages/inquiry_module/lib/src/features/ai/ask_page.dart`（1155）

职责：

- L31–45 `AskPage`。
- L46–149 状态、历史、取消令牌、释放。
- L150–418 `_send`。
- L419–438 滚动。
- L439–674 `build`。
- L676–936 示例、气泡、证据、打开来源。
- L937–1038 `_AppNavigationTools`。
- L1040–1126 `_ReviewedWebTools`。
- L1128 至文件尾 `_RecordChip`。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `ask_page.dart` | 外壳、状态字段、`build` | 约 320 |
| `ask_page_send.dart` | L150–418 | 约 280 |
| `ask_page_bubbles.dart` | L676–936 | 约 270 |
| `ask_page_tools.dart` | L937 至文件尾 | 约 230 |

后三个工具类和芯片是独立类，`part` 原样搬。`_send` 用 mixin。`build` 留在 State。

耦合：`_cancellation`、`_savedMessages`、`_historyKey` 留在 State。`externalContent` 的赋值在 `_send` 路径里，跟发送段一起走。

安全相关，必须原样搬：L52 `AssistantCancellation`；L150 起发送和取消；L1040–1126 网页工具的人工复核包装。

调用方：`shell.dart`、`ai_tasks_page.dart`。

直接测试：`inquiry_general_write_tools_test.dart`、`inquiry_web_task_stop_test.dart`、`ai_answer_resume_test.dart`、`ai_design_audit_test.dart`、`ask_history_lifecycle_test.dart`、`ask_page_test.dart`、`assistant_permission_hosted_test.dart`、`assistant_permissions_test.dart`、`assistant_procurement_ui_test.dart`。

顺序与风险：中段。风险中：取消和网页复核要原样留在发送段。

## 9. `packages/supplier_core/lib/src/lan.dart`（1152）

职责：

- L1–116 节点配置、`LanPeer`、`LanPush`、`LanException` 和发送签名。
- L117–333 `LanNode` 的启动、身份、信任、确认对端、撤销。
- L339–569 绑定、发现、hello、过期。
- L570–940 HTTP 服务、已见推送、`_authorizePush`、接收。
- L941 至文件尾探测、`push`、出站客户端。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `lan_types.dart` | 文件头至 `LanNode` 之前 | 约 120 |
| `lan.dart` | 启动、身份、信任、发现 | 约 400 |
| `lan_http.dart` | L570–940 | 约 380 |
| `lan_push.dart` | L941 至文件尾 | 约 220 |

类型用 `part`。`LanNode` 的 HTTP 和 push 用 mixin。`package:supplier_core/lan.dart` 是 4 行桶文件，继续 export `src/lan.dart`，调用方不用改。

耦合：`_ledger`、`_audit`、`_digest`、身份和信任存储留在主类。HTTP mixin 通过 `on LanNode` 使用。

安全相关，必须原样搬：L317 `confirmPeer`；L333 `revoke`；L346 `_loadIdentity`；L364 信任加载；L693 `_authorizePush`；L1011 `push` 以及出站账本参数。

调用方：`lib/lan.dart`、`supplier_core.dart`。宿主通过桶文件 `package:supplier_core/lan.dart` 使用，不直接 import `src/lan.dart`。

直接测试：`lan_security_test.dart`、`lan_trust_test.dart`、`lan_upload_reliability_test.dart`。宿主里的 transfer 测试 import 的是桶文件。

顺序与风险：靠后。风险高：身份、信任和推送授权。

## 10. `packages/supplier_core/lib/src/assistant_procurement.dart`（1104）

职责：

- L55–117 工具集构造、会话状态、已应用动作。
- L118–216 工具清单和记录投影。
- L217–761 候选、资质、数字、价格问题、对比、项目差异。
- L762–857 `execute`。
- L858–1049 `_import`。
- L1050 起 `renderReport`。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `assistant_procurement.dart` | 构造、状态、`execute` | 约 220 |
| `assistant_procurement_schema.dart` | L118–216 | 约 110 |
| `assistant_procurement_compare.dart` | L217–761 | 约 550 |
| `assistant_procurement_import.dart` | L858 至文件尾 | 约 210 |

`execute` 留在主类，它是接口实现。对比和导入用 mixin。对比段仍然是最大块；若实现时还要再切，按 `_qualification`、`_compare`、`_projectDifference` 三个方法切开，不要改方法体。

耦合：`_key`、`_load`、`_save`、`_check` 留在主类。取消检查在 `_check`。

安全相关，必须原样搬：L110 `_check` 的取消和写保护；`execute` 在写之前调用它。没有单独的授权事务。

调用方：`supplier_core.dart`。

直接测试：没有文件 import 这个 src 路径。`assistant_procurement_test.dart` import `package:supplier_core/supplier_core.dart`。

顺序与风险：中段。风险中：对比段大，但没有授权事务。

## 11. `packages/supplier_core/lib/src/assistant_web_tools.dart`（961）

职责：

- L11–76 解析器、传输、预览、复核回调、`AssistantWebAuthority`、`AssistantWebResponse`。
- L77–646 `AssistantWebTools`：快照、工具清单、`execute`、加载、请求、公网地址判断。
- L647–706 `_WebBudget` 和参数工具。
- L708 至文件尾 HTML 文本、解码、`_WebError`、`_Loaded`、`_Page`。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `assistant_web_tools.dart` | L1–646 | 约 650 |
| `assistant_web_text.dart` | L647 至文件尾 | 约 320 |

`AssistantWebTools` 本身约 570 行，低于 800。先把后面的独立类和顶层函数用 `part` 原样搬走，不切这个类。若以后还要切类，再按 `execute` 与 `_request` 做 mixin，本次方案不把类切开。

耦合：`_WebBudget` 使用 `AiCancellation`，和工具类同库即可。顶层 `_tool`、`_keys`、`_string` 若被类内调用，必须留在同一 part 库。

安全相关，必须原样搬：L38 复核回调；L646 起「未消费的等待仍可取消」；L655 超时 `cancellation.cancel`；公网地址判断 `_public`。这些如果留在主文件，就不要为了再缩短而去改它们。

调用方：`assistant_procurement.dart`、`supplier_core.dart`。

直接测试：`assistant_web_tools_test.dart`、`assistant_web_catalog_test.dart`。

顺序与风险：可以早做这一刀，因为不切类。风险高的是文件里的出站和取消，所以不要顺手改请求逻辑。风险记高。

## 12. `packages/muyon_ui/lib/src/dynamic/surface.dart`（957）

职责：

- L15–73 事件回调、`UiDispatchOutcome`、`UiReceiptStatus`、`UiBusinessReceipt`、`UiPendingAction`、`UiRenderCapture`。
- L75–554 `UiSurfaceController`：重算、发布、确认、派发、回执。
- L556–574 `renderUiPlan` 和 `DynamicUiSurface`。
- L576 至文件尾 `_DynamicUiSurfaceState` 的渲染。确认卡在 L843–910。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `surface.dart` | L1–554 控制器和前面的类型 | 约 560 |
| `surface_view.dart` | L556 至文件尾 | 约 410 |

两个类用 `part` 原样搬，不用 mixin。`dynamic_ui.dart` 继续 export 原路径。

耦合：State 使用控制器的公开方法。控制器的私有字段留在控制器文件；同库 part 仍可见。`renderUiPlan` 跟视图走，它只是一行包装。

安全相关，必须原样搬：L368 `canConfirm`；L400 取消；L465 过期派发；L532 `acceptReceipt`；L843–910 `ConfirmCard` / `BatchConfirmCard` 的允许、拒绝和取消。L871 不传 `externalContent`，拆分时保持原样，不在这次补上。

调用方：`dynamic_ui.dart`、`component_adapter.dart`、`workspace.dart`、`workspace_view.dart`、`dynamic_ui/surface.dart`。

直接测试：没有文件 import `src/dynamic/surface.dart`。`dynamic_surface_test.dart` 等通过 `package:muyon_ui/dynamic_ui.dart`。

顺序与风险：类边界清楚，可以较早搬。风险高，因为确认和回执在视图文件里，必须整段原样搬。

## 13. `apps/muyon/lib/assistant/agent_dispatch.dart`（940）

职责：整个文件是一个 `AgentDispatch`（L21 起）。

- L26–114 请求、展示参数、未执行文案、计划视图。
- L116–273 `dispatch` 和阶段写入。
- L274–450 确认卡是否允许、打开卡、记录结果。
- L452–628 外部标记、单次调用、并行读、取消。
- L629 至文件尾 `executeCard`、`completeStep`、协议纠正后的完成。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `agent_dispatch.dart` | 构造、展示辅助、`dispatch` | 约 280 |
| `agent_dispatch_card.dart` | L274–450 | 约 180 |
| `agent_dispatch_reads.dart` | L452–628 | 约 180 |
| `agent_dispatch_complete.dart` | L629 至文件尾 | 约 320 |

后三段是 mixin。`dispatch` 留在主类。

耦合：`ctx` 留在主类。`_stage`、`_cardAllowed`、`_record` 被多段使用，留在主类，mixin 调用它们。

安全相关，必须原样搬：L272 起确认卡；L301–357 `authorization.review` 和自动放行的连续前缀；L424 附近「回执和任务同一次事务」；L450–559 取消路径；L629 `executeCard`。

调用方：`agent_model_turn.dart`、`agent_resume.dart`、`personal_agent.dart`。

直接测试：无。覆盖来自 import `personal_agent.dart` 的助手测试，而不是本文件。

顺序与风险：最后。风险高：确认卡、授权复核和取消。没有直接测试，拆完要跑助手相关套件。

## 14. `apps/muyon/lib/screens/assistant_page.dart`（937）

职责：

- L23–50 `AssistantPage`。
- L52–78 顶层 `confirmTitle`、`_confirmationSummary`。
- L80–217 状态、会话、工作区打开、发送前准备。
- L217–516 发送、确认、工具、新会话、子对话。
- L518–901 `build` 和状态标签。
- L904 至文件尾子对话目标对话框。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `assistant_page.dart` | 外壳、字段、`build` | 约 450 |
| `assistant_page_actions.dart` | L217–516 | 约 310 |
| `assistant_page_dialog.dart` | L904 至文件尾 | 约 40 |

`confirmTitle` 是公开顶层函数，测试直接用它。放在父文件或 part 都可以，导入路径仍是 `assistant_page.dart`。对话框是独立类，`part` 原样搬。发送和确认用 mixin。`build` 留在 State。

耦合：`_conversationId`、`_busy`、`_confirm` 用到的 `widget.agent` 留在 State。

安全相关，必须原样搬：L52 `confirmTitle`；L59 摘要；L248–291 `_confirm` 里的摘要核对和 `agent.confirm`。

调用方：`platform_shell.dart`、`assistant_subconversation_panel.dart`。`integration_test/platform_device_test.dart` 也直接 import。

直接测试：`aiui4c_settings_entry_test.dart`、`assistant_draft_ui_test.dart`、`assistant_readable_confirmation_test.dart`、`assistant_subconversation_rejection_test.dart`、`assistant_subconversation_widget_test.dart`、`confirm_title_test.dart`、`conversation_shell_accessibility_test.dart`、`conversation_shell_navigation_test.dart`、`conversation_shell_recovery_test.dart`、`personal_agent_test.dart`、`research_object_open_test.dart`、`responsive_shell_test.dart`、`widget_test.dart`。

顺序与风险：中段。风险中：确认对话框的文案和摘要核对不能改。

## 15. `apps/muyon/lib/assistant/agent_model_turn.dart`（890）

职责：整个文件是一个 `AgentModelTurn`（L27 起）。

- L35–72 `advance` 和预算耗尽。
- L73–296 `waitForModel`、发送前检查、权限任务、`preparePermission`。
- L297–707 `runModel`、流式收集、记账、失败。
- L708 至文件尾原生协议回合和一次纠正。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `agent_model_turn.dart` | 构造、`advance`、`waitForModel` | 约 300 |
| `agent_model_turn_stream.dart` | L297–707 | 约 420 |
| `agent_model_turn_native.dart` | L708 至文件尾 | 约 190 |

后两段是 mixin。`waitForModel` 留在主类，因为权限门在这里。

耦合：`ctx` 留在主类。`checkPermissionTask`、`preparePermission` 被运行段调用，留在主类。

安全相关，必须原样搬：L139–166 确认卡和 `modelAuthorization`；L220–309 发送前政策、过期确认、`preparePermission`、`authority.take`；L313 `ModelCancellation`；L509 附近账本行出现才算请求已发出；L708 起原生回合仍走同一确认。

调用方：`agent_compaction_flow.dart`、`agent_dispatch.dart`、`agent_resume.dart`、`personal_agent.dart`。

直接测试：无。和调度一样，靠助手套件间接覆盖。

顺序与风险：和 `agent_dispatch.dart` 一起放在最后，两者互相 import。风险高。

## 16. `packages/supplier_core/lib/src/spec_parse.dart`（879）

职责：

- L21–105 `SpecItemDraft`、从表格和文本得到草稿。
- L106–209 条款切分和编号正则。
- L210–254 `_Hit`、`_Number`。
- L255 至文件尾 `_ClauseReader`：固定词、选择、数字、布尔和剩余文本。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `spec_parse.dart` | L255 至文件尾的 `_ClauseReader` | 约 640 |
| `spec_parse_draft.dart` | L21–254 | 约 240 |

`_ClauseReader` 约 625 行，低于 800。前面的草稿、切分和私有小类用 `part` 原样搬。不切阅读器类。

耦合：`_numbering`、`_inlineNumber` 被切分和阅读器共用，跟草稿 part 走，阅读器同库可见。`extension on List<SpecItemDraft>` 跟草稿走。

安全相关：无。

调用方：`supplier_core.dart`、`agent_tools.dart`、`spec_ai.dart`、`spec_extract.dart`、`spec_request.dart`。

直接测试：没有文件 import 这个 src 路径。规格测试通过桶文件。

顺序与风险：靠前。风险低。

## 17. `packages/research_module/lib/src/reader/reader_page.dart`（861）

职责：

- L22–51 `ReaderPage`。
- L52–204 状态、定位引文、选择、高亮。
- L205–426 链接、记录卡片、图片。
- L427–688 笔记的保存和关联。
- L689 至文件尾阅读布局和 `build`。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `reader_page.dart` | 外壳、字段、选择、`build` | 约 360 |
| `reader_page_links.dart` | L205–426 | 约 230 |
| `reader_page_notes.dart` | L427–688 | 约 270 |

链接和笔记用 mixin。`build` 留在 State。

耦合：`_selection`、`_page`、`_entryId`、`_location` 留在 State。

安全相关：L326 附近是已确认的论文绑定展示，不是授权门。原样搬。

调用方：`research_module.dart`（桶和 src）、`workbench_app.dart`。

直接测试：`reader_annotation_entry_test.dart`、`reader_evidence_test.dart`。

顺序与风险：靠前。风险低。

## 18. `packages/research_module/lib/src/research_module.dart`（801）

职责：

- L23–92 `ResearchModule`：清单、schema、本体、工具注册、激活。
- L94–420 `ResearchRuntime`：范围、准备导入、回执、`commitImport`。
- L422–773 `ResearchSession`：解析对象、页面、证据摘要。
- L775 至文件尾 `_ResearchScopeSession`。

拆分：

| 新文件 | 区间 | 预计行数 |
|---|---|---|
| `research_module.dart` | L23–92 的模块类，加 `part` | 约 100 |
| `research_runtime.dart` | L94–420 | 约 340 |
| `research_session.dart` | L422 至文件尾 | 约 390 |

三个类都是完整类，`part` 原样搬，不用 mixin。桶文件 `packages/research_module/lib/research_module.dart` 继续 export `src/research_module.dart`。

耦合：`ResearchRuntime` 的 `_digest`、`_identity` 只在运行时类里。会话的 `_resolve` 留在会话类。没有跨类的私有顶层函数需要合并。

安全相关，必须原样搬：L104 附近模块写入的事务边界复查；L286 `commitImport`；L379 `commitTask(..., ownTransaction: false)`，它嵌在外层事务里，不能改成独立提交。

调用方：桶文件 `research_module.dart`、`module_tools.dart`。宿主 import 的是桶，不是这个 src 文件。

直接测试：没有文件 import `src/research_module.dart`。经桶文件的测试有 `object_pages_test.dart`、`change_log_test.dart`、`research_runtime_test.dart`，以及宿主的 `research_task_flow_test.dart`、`reg3a_upgrade_read_guard_test.dart`、`reg3a_module_v2_test.dart`、`aiui4c_navigation_test.dart`、`platform_metadata_scope_test.dart`、`research_object_open_test.dart`、`accepted_research_import_test.dart`。

顺序与风险：类边界清楚，但提交导入含事务，放在中后段。风险高。

## 汇总

预计行数是拆分目标，不是测量值。新增文件数不含被拆的原文件。

| 文件 | 现行数 | 拆后最大文件 | 新增文件数 | 风险 |
|---|---:|---:|---:|---|
| `workbench_app.dart` | 1557 | 约 350 | 5 | 中 |
| `transfer_service.dart` | 1368 | 约 400 | 5 | 高 |
| `tool_registry.dart` | 1313 | 约 320 | 5 | 高 |
| `exchange.dart` | 1263 | 约 370 | 4 | 高 |
| `agent_eval.dart` | 1246 | 约 370 | 6 | 低 |
| `spec_dictionary.dart` | 1238 | 约 440 | 3 | 低 |
| `foundation_repository.dart` | 1209 | 约 260 | 5 | 高 |
| `ask_page.dart` | 1155 | 约 320 | 3 | 中 |
| `lan.dart` | 1152 | 约 400 | 3 | 高 |
| `assistant_procurement.dart` | 1104 | 约 550 | 3 | 中 |
| `assistant_web_tools.dart` | 961 | 约 650 | 1 | 高 |
| `surface.dart` | 957 | 约 560 | 1 | 高 |
| `agent_dispatch.dart` | 940 | 约 320 | 3 | 高 |
| `assistant_page.dart` | 937 | 约 450 | 2 | 中 |
| `agent_model_turn.dart` | 890 | 约 420 | 2 | 高 |
| `spec_parse.dart` | 879 | 约 640 | 1 | 低 |
| `reader_page.dart` | 861 | 约 360 | 2 | 低 |
| `research_module.dart` | 801 | 约 390 | 2 | 高 |

建议顺序：先 `agent_eval.dart`（本任务第二节）。然后低风险的 `spec_dictionary.dart`、`spec_parse.dart`、`reader_page.dart`。再是界面：`assistant_page.dart`、`workbench_app.dart`、`ask_page.dart`、`assistant_procurement.dart`。然后虽然是整类搬运、但含确认或事务的 `surface.dart`、`assistant_web_tools.dart`、`research_module.dart`。最后是授权和事务：`exchange.dart`、`foundation_repository.dart`、`lan.dart`、`transfer_service.dart`、`tool_registry.dart`、`agent_model_turn.dart`、`agent_dispatch.dart`。后两个互相 import，同一次拆。

## 未能静态确认

- 同库 `mixin on 原类` 能否看见原类私有字段：Dart 的私有是库级的，本仓库的 `part` 先例（`platform_shell.dart`）没有 mixin。实现那一类文件时以 `flutter analyze` 为准。`agent_eval.dart` 不需要 mixin。
- `spec_dictionary.dart` 的属性清单切开后再展开，顺序要和 L200–950 逐项相同。本方案没有把 751 行再抄一遍。
- `agent_dispatch.dart` 和 `agent_model_turn.dart` 没有直接测试。不能从测试名对应到每一个私有方法。

## 疑似缺陷

本次不评价行为。拆分时保持原样、不要顺手改的位置：`surface.dart:871` 动态确认卡不传 `externalContent`。
