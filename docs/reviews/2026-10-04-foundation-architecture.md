# 基础平台原生架构复核

2026-10-04，architect 只读代码复核，状态 WATCH。没有运行 OMX 共识运行时或新测试。以下为复核结论与主执行者采用的修复；不能据此声称平台已完成。

1. **全局 scope**：原 ContextRef/PermissionDecision 强制单模块单项目。新增 AssistantScope(global/workspace/selectedObjects)，provider 身份与数据对象所有者分开，执行前解析明确 refs 并冻结版本。原科研契约保留，不使用空字符串伪项目。
2. **审批**：模型仅提出 toolId+参数。宿主参数校验与展示后签发一次令牌，绑定工具/参数/范围/端点摘要和时效；持久调用/消费账本。重启未执行审批失效，不自动恢复批准。复合效应（写入与外传）全部展示。
3. **任务**：执行器归 MuSpaceHost，页面只订阅。聊天关闭不删记录。恢复采用新 attemptId 与再次确认，不将取消/中断等同于回滚业务提交；原有 receipt/intent 恢复模式保持。
4. **唯一权威**：FoundationRepository 在现宿主主库增加会话、消息、来源记忆、通知；workspace/settings/device/model identity 继续用现表。个人助手与科研执行记录共用 execution_records 物理表，类型化 payload 以 kind 区分，统一任务中心聚合。原 Folio jobs 通过适配读取，不另存第二份业务状态。
5. **实际复用**：公共 provider 由宿主创建、注册并供 UI、Agent 与模块适配器使用。不能以能力列表页或接口定义代替实际调用。未改的原 Folio AI 通路须明确列为迁移缺口。
6. **知识来源**：原业务库和文件是事实源。统一文档引用包含模块、对象、版本/摘要、文件引用与页码/区域；全文/OCR/向量是派生结果，绑定解析/分块/embedding 模型版本和维度。无 embedding provider 时不假造语义向量。
7. **平台证据**：OCR 必须有真实预处理/推理/后处理与固定模型，单独记录运行时、系统最低版本、模型与设备测试。文字 PDF 提取不是 OCR。离线构建、loopback、实机、真实模型与跨设备验收分别记录。

原代码证据：`packages/muspace_module_api/lib/src/context.dart`；`apps/muspace/lib/assistant/action_gate.dart`、`execution_store.dart`；`apps/muspace/lib/workspace/workspace_repository.dart`、`import_coordinator.dart`；`apps/muspace/lib/app/bootstrap.dart`、`research_tools_page.dart`；`apps/muspace/lib/services/search/search_service.dart`、`models/model_gateway.dart`；`packages/inquiry_module/lib/src/app/app_state.dart`。

采用“宿主统一服务 + 模块适配器”。保留原业务规则可减少回归，过渡期双通路必须逐项验证。只加页面无法完成复用；一次性重写所有业务数据会扩大风险。

停止条件：持久会话与引用可打开、无模型时可查文件/资料/业务数据和计算、错scope/伪造/陈旧/重复审批拒绝、页面关闭不丢任务、取消/提交竞态验证、同一provider实际多入口调用、源变更使派生结果失效。外部平台或模型缺口不得伪造通过。
