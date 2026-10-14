# MEMORY-LIFECYCLE-04 · ChatGPT Android 1.2026.272（对照）

样本：com.openai.chatgpt 1.2026.272 / 2627220；SHA256 `47d8350a…e40a`；签名 SHA256 `b24f4bfb…473c`（Play App Signing，中等可信）；缺 split；jadx 在约 66% 退出——**“没找到”一律按未知**。序列化名大面积哈希化（如 `_RGZIkS0uGg…`），所以 API 结构证据远弱于 Claude。

## 结论（短）
| 主题 | 发现 | 等级 |
|---|---|---|
| 上下文来源分类 | 枚举 `jbm`: `user_memory / general_memory / past_conversation / user_instructions / unknown`，被 `fl60`/`jk60` 的 when 映射使用（推断：用于“本回答参考了什么”的来源展示） | 客户端代码（枚举+映射）；UI 用途=推断 |
| 记忆容量 | `nm60{memories, memoryMaxTokens, memoryNumTokens}`；`show_persistent_memory_full/almost_full_upgrade_pill` | 客户端代码 |
| 设置项 | `settings_memory_reference_saved_memories`、`settings_memory_reference_chats_and_files`、`settings_memory_summary`、`settings_memory_manage_memories` —— “引用已存记忆”与“引用历史聊天/文件”是两个开关 | 字符串/路由 id |
| 语音中保存 | `z9r0.MemorySaved("memory_saved")` | 客户端枚举 |
| 压缩 | 流事件类型 `context_compaction`（fdq0） | 客户端代码；处理链未追 |
| 临时聊天 | `up30.Temporary("temporary")`；官方：开始前选是否个性化，开始后不能改；不创建/更新记忆；保存后转普通聊天 | 线索 + 官方当前规则 |
| 删除 | 官方：删聊天不删已存记忆；关“引用聊天历史”→派生信息 30 天内计划删除；删除的已存记忆日志可保留至 30 天；“Delete and turn off memory” 后再开可能从**仍在的旧聊天**重新生成记忆 | 官方当前规则 (help.openai.com/8590148, 访问 2026-10-13) |
| 编辑并发/版本/整理回滚 | 未找到（覆盖不完整） | 未知 |

**对 Muyon 最有价值的对照点**：(a) 读开关拆成“已存记忆”和“聊天历史”两路；(b) 官方明说“关掉再开会从旧聊天重新生成” —— 正是“旧来源复活”反例，Muyon 必须用墓碑阻断；(c) 回答来源分类枚举可作为“本次使用了哪些记忆”的 UI 依据。
