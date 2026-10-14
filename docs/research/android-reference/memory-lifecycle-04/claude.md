# MEMORY-LIFECYCLE-04 · Claude Android 1.261009.20

样本：com.anthropic.claude 1.261009.20 / versionCode 26100920；base APK SHA256 `9807d321…122a`；签名 SHA256 `305a1e8a…64a0`（Play App Signing 形态，用户已接受中等可信）；缺 base__abi / base__density split；jadx 1.5.3（23311 类，162 错误）。代码混淆（defpackage 短类名），但 kotlinx.serialization 描述符保留**完整 API 类名和 JSON 字段名**。仅静态。官方资料访问 2026-10-13。
范围：本文只写 **Claude 手机 App 聊天**。`SessionContext.memory_mode`、`ContextUsagePayload.memory_files`（含示例 `/Users/dev/repo/CLAUDE.md`）属于遥控 Claude Code 会话，单列，不套用到 App 聊天。

## 1. 一页结论
1. **记忆编辑不是写内容，是发指令**（客户端代码直接证据）：`x0n.b` → `POST organizations/{org}/melange/edit`，body `MemoryFsEditRequest{path, instruction}`，`Accept: text/event-stream`。请求无 If-Match/版本/内容哈希；改成什么由服务端（推断：模型）决定。对比：同一 App 里 Claude Code 的 `user_settings` PUT **带 If-Match**（o29.java:19-21），说明 App 有 ETag 能力但记忆编辑没用。
2. **三种记忆模式由三枚布尔组合**（客户端代码直接证据 + 推断映射）：`MemorySettingsGesture{user_initiated, enabled_melange, enabled_saffron, enabled_saffron_search, clear_data}`；`nen.a(u7l)`：MEMORY_FILES→`melange=true`；CLASSIC→`melange=false,saffron=true`；OFF→`melange=false,saffron=false, clear_data=z?true:null`。`clear_data=true` 对应“Reset”，null 对应“Pause/关闭”= 推断（依据参数形态与文案“keeps existing memory” vs “permanently delete”）。
3. **每会话的记忆读写开关在创建会话时定**（客户端代码直接证据）：`CreateChatRequest{…, is_temporary, include_conversation_preferences, chat_memory_mode}`；官方当前规则：“+”菜单关 Memory 须在**发第一条消息前**，无痕“不使用现有记忆、不进入未来记忆、不被历史检索”。
4. **删除/重置为服务端操作，客户端只有请求/响应**：`MemoryFsDeleteRequest{path}`→`{deleted}`；敏感话题清除是**异步任务** `SensitiveCleanupStatusResponse{state, cleanup_id, consent_recorded}`，并有文案“Deletion didn’t finish. Some memories … may still be saved.” → 客户端会如实呈现“未完成”。官方当前规则：删除聊天**不会**删除由其产生的记忆。
5. **写入回执绑定 tool_use_id**（客户端代码直接证据）：`MemoryWriteStatusEntry{tool_use_id, display_reason}`；`tqs` 把 `kind=activity, tool=update_memory` 的块渲染为“Updated memory / removed …”；失败文案“Memory couldn’t be saved”“Claude can’t save that to memory”。
6. **压缩**：`stop_reason="compaction"` 不是终止原因（stw.a 返回 false，回合继续）；`CompactionStatus{status: compacting|complete|failed, message}`；未发送消息原因含 `lost_to_compaction`；`l130.k` 在上下文清除时置 `CompactionCleared`。压缩摘要内容、保留结构、tool_use/result 配对规则在客户端不可见 = 未知；API 文档的 server-side compaction 属 **官方当前规则（API 产品）**，不能直接当 App 实现。

## 2. 对象与生命周期表
| 对象 | 谁产生 | 存在哪 | 何时进上下文 | 等级 |
|---|---|---|---|---|
| 记忆文件（topics，新版） | 模型在聊天中写（`update_memory` 工具活动）；用户经 `melange/edit` 指令 | 服务端 memoryfs：`MemoryFsMeta{path,size_bytes,updated_at,display_name,category_id,memory_id}`、`MemoryFsDoc{…content,parsed}`、`ParsedContent{name,description,body}` | 未知（服务端）；官方：“边聊边加入，不再结束后汇总” | 客户端代码 + 官方当前规则 |
| 项目记忆 | 同上，`GET memory?project_uuid=` | 服务端，按项目隔离；“Use account memory”允许项目与项目外共享 | 未知 | 客户端代码(s2l.a) + 字符串 |
| Classic/legacy 记忆摘要 | 服务端合成 | `MemorySynthesisResponse{memory, user_instructions, updated_at}` | 未知 | 客户端代码；“24 小时合成”= **官方旧版规则**，不作为现行通则 |
| 用户手填偏好 | 用户（`user_instructions`、`include_conversation_preferences`） | 服务端 | 建会话时由标志控制是否带入 | 客户端代码 |
| 敏感话题记忆 | 模型写，需 consent | 服务端；`sensitive_consent_recorded` | 未知 | 客户端代码 + 官方当前规则 |
| 历史检索（saffron_search，推断） | 服务端检索 | 服务端 | 未知 | 推断 |
| 聊天摘要 `summary` | 服务端 | Conversation 字段 | 未知 | 客户端代码（字段存在） |
| 压缩摘要 | 服务端 | 未知 | 压缩后替代早期上下文（API 官方） | 未知/官方API |
| 身份/人格 | 未发现用户可编辑的 App 人格文件 | — | — | 未发现 |
| 经验/整理提案 | 未发现 | — | — | 未发现 |

## 3. 关键调用链（文件见 evidence/）
- **设置**：开关 lambda `qt4.b` case0（qt4.java:24-31）：on→`o7l.e()`（saffron=true）；off→`o7l.c(false)`；**先 `gu20.h(ben, gesture)` 写入本地设置流**（推断：乐观更新），再由 `nen.f` → `s2l.b` `POST memory/settings`。失败分析事件 `memory_toggle_failure`（字符串）；回滚本地值的分支未追到 = 未知。
- **编辑**：`x0n.b(path, instruction)`（x0n.java:26-62）：先从 `rcz.b().a` 取当前可用工具状态，过滤 `k8l.w|k8l.y` → 构造 `e5l`（推断：允许的权限/连接器集合随指令下发）；SSE 回调 `q6e(e5l, …)`；`x0n.a(str)` 生成 `500` 错误对象。没有冲突分支。
- **列/读/删**：`MemoryFsListRequest{path_prefix}` / `MemoryFsReadRequest{path, resolve_wikilinks}` / `MemoryFsDeleteRequest{path}`；`h4l.java:120` 本地按路径过滤列表（删除后本地移除，推断）。
- **会话**：`m1b`(CreateChatRequest) 带 `is_temporary`、`chat_memory_mode`；`gy5`(ChatConversationSettings) 带 `chat_memory_mode`。服务端如何按此过滤读写 = 未知；官方规则见上。
- **失效原因枚举** `ksu`：`dismissed/expired/superseded/raced/inputs_changed/unreconcilable/…/memory_mode_mismatch/create_replay` —— 客户端存在“记忆模式不一致”作为失效原因（调用者未追全，线索）。

## 4. 七个问题逐条
1. 见表。注入时机全部服务端 = 未知。
2. **Pause**：官方当前规则——保留、既不使用也不新建，暂停期间对话恢复后也不入记忆 → 读写同时关。**每会话关 Memory**：`chat_memory_mode`，须首条消息前（官方）。**Incognito**：`is_temporary`，不读不写、不入历史检索、组织仍可见（字符串 + 官方）。**历史检索**：`enabled_saffron_search` 单独布尔 → 检索与生成记忆在**字段层**可分（客户端代码），实际过滤点 = 未知。
3. **指令式补丁**（`instruction`），非整文件、非条目 diff；无版本；`MemoryFsMeta.updated_at` 只用于显示（推断）。
4. 删记忆：`{deleted}` 布尔回执；删源聊天：官方说不删派生记忆；Reset：`clear_data=true`（推断）+ 官方“含项目记忆，永久”；敏感清除：异步+可能未完成；撤连接器：AUTH-TRACE-02 已证“移除后停止调用”，对已入记忆内容的影响 = 未知；索引/缓存/导出 = 未知（官方：legacy 记忆可导出至 2026-09-09）。
5. 整理/合并/回滚：未发现客户端证据。`Updated memory, removed %s` 表示模型写入时可同时删条目（字符串），不等于可回滚的整理提案。
6. 见结论 6。`lost_to_compaction` 说明压缩可导致**未送达的用户输入被判丢失**并呈现给用户（客户端代码）；切项目/撤权后旧摘要失效 = 未知。
7. 可见：每个文件 `display_name/category/updated_at/size`；“View memory”全文；写入活动行（含 tool_use_id 绑定的 display_reason）；“%1$d%% of context window used”；Code 会话的 ContextUsage 分类含 memory_files。未发现：每条“是否推断”“本次回答是否使用了哪条记忆”。

## 5. 局限
缺 split；混淆代码中 SSE 回调 `q6e` 内部、`memory_toggle_failure` 回滚、h4l 的删除乐观更新未逐条 smali 核对；服务端全部未知。
