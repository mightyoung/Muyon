# MEMORY-LIFECYCLE-04 · Muyon 改进建议（S06 记忆与偏好 / S07 助手身份 / 经验整理 / 压缩）

依据：muse.md、claude.md、chatgpt.md。每条标出来源：**竞品证据**（引用对方编号）或**工程建议**（无竞品证据，来自通用工程实践）。不修改 Muyon 代码或两册设计原件；落点按已选路线：Rust 内核 / Compose / Electron / 平台适配层。保留现有：记忆、待核实经验、整理提案、整理运行记录、回滚、墓碑。

## 1. 对象分离（不合并为一份 MEMORY.md）
| 对象 | 生产者 | 存储（Rust 内核，本机库） | 进上下文 | 来源 |
|---|---|---|---|---|
| preference（显式偏好） | 用户 | `memory_item(kind=preference, origin=user)` | 按 scope 注入 | 竞品：Claude user_instructions / ChatGPT user_instructions 分类 |
| fact（事实记忆） | 用户或模型提案 | `memory_item(kind=fact, origin=user|inferred)` | 已确认才注入 | 竞品：Muse 导入要求“(inferred)”标注（M4）；工程建议：推断项默认不注入 |
| experience（待核实经验） | 模型/执行回执 | `experience(status=pending|verified|rejected)` | 仅 verified | Muyon 现有能力 |
| project memory | 同上 + project_id | 同表 scope=project | 仅该项目；跨项目共享需显式开关 | 竞品：Claude project_uuid + “Use account memory” |
| identity（S07） | 用户 | `identity_doc`（名称、语气、行为约束）独立表/文件 | 每轮注入，**不作为授权来源** | 竞品：Muse IDENTITY.md 分离（M3） |
| chat summary | 内核 | `derived_summary(kind=chat)` | 检索时 | 工程建议 |
| compaction summary | 内核 | `derived_summary(kind=compaction, run_id, covers_seq_range)` | 仅本会话 | 竞品：Claude CompactionStatus（C5）；结构=工程建议 |

每条 `memory_item` 必须有：`id, version(u64), content_hash, kind, origin, scope, source_refs[]（chat_id/msg_seq/file/connector_grant_id）, purpose_tags, created_at, updated_at(宿主时钟), state(active|disabled|tombstoned)`。来源：Claude `MemoryFsMeta{memory_id, updated_at, category_id}` 部分支持；source_refs/purpose 为工程建议（竞品均未见每条来源字段）。

## 2. 关键合同
1. **编辑 CAS（工程建议，竞品为反例）**：`edit_memory(id, expected_version, patch)`→`Ok{new_version}` | `Conflict{current_version, current}`。禁止整文件覆盖（Muse M1/M2 `overwrite=true` 无版本；Claude `melange/edit` 无 If-Match）。模型发起的修改走“提案”，用户确认时绑定 expected_version。
2. **读写分离开关**（竞品证据：Claude enabled_saffron / saffron_search / chat_memory_mode；ChatGPT 两路 reference 开关）：`memory.read`、`memory.write`、`history.search` 三个独立门；会话级 `memory_mode` 在**首个请求前**固定并写入会话记录（Claude 官方）；中途更改只影响新回合，已排队请求按其入队时的快照 + 当前撤权取**更严**者。
3. **临时会话**：用户在 t7u 决定 S06 **不加临时会话**——本建议不新增该页面能力；仅保留会话级“本会话不写记忆”标志作为内部合同（若用户不同意可删）。
4. **删除传播（工程建议；竞品均明说不传播——Muse/ChatGPT/Claude 官方“删聊天不删记忆”）**：删除或撤权写 `tombstone{target_kind, target_id, source_ref?, grant_id?, epoch, reason}`；所有派生对象（summary、embedding 索引、缓存、通知草稿、导出包清单、排队任务的上下文快照）记录 `derived_from[]`；内核在**读取点**（注入上下文、检索、导出、发通知）过滤 tombstoned 来源，不依赖异步清理完成。
5. **删除回执如实**（竞品证据：Claude SensitiveCleanup `state/cleanup_id` 与“Deletion didn’t finish”）：删除返回 `{tombstoned:true, purge:pending|done|partial, remaining_derivatives:n}`，UI 不得在 purge 未完成时写“已彻底删除”。
6. **整理与回滚（Muyon 现有，竞品未见）**：`consolidation_run{run_id, base_versions{item_id:version}, proposal, applied_versions}`；回滚 = 生成新版本（version+1），且仅当 `current_version == applied_version` 才自动回滚；否则冲突，交用户逐条决定。回滚**不得**复活此后被 tombstone 的条目。
7. **备份/旧设备（工程建议；Muse 官方有 VM 备份，复活处理未知）**：每设备独立库；恢复备份时先导入 tombstone 集合，再导入条目，条目 `id` 命中 tombstone 或 `version <= tombstone.epoch` 一律丢弃；跨设备不承诺同步（与路线一致）。
8. **压缩（Claude 证据部分支持）**：压缩产物绑定 `{session_id, covers_seq_range, input_hash, policy_epoch(授权/记忆模式版本)}`；工具调用与结果**成对保留或成对折叠**并保留 receipt_id；压缩失败保持原历史（Claude `failed` 状态）；迟到摘要若 `policy_epoch` 或 tombstone 集变化则丢弃；压缩摘要永不作为授权或记忆来源（不得被提升为 memory_item 除非走提案）。参考 Claude `lost_to_compaction`：压缩期间未送达的用户输入必须显式标出，不得静默丢弃。

## 3. 页面
- **S06 记忆与偏好**（Compose / Electron）：列表按 kind 分组；每条显示来源（可跳转原消息；源已删则显示“来源已删除”）、更新时间、是否推断、作用范围（全局/项目）、用途标签、启用开关；“本次回答使用了”入口（竞品：ChatGPT jbm 来源分类，推断用途）；编辑冲突对话框；删除确认显示“影响范围：X 条派生摘要、Y 个索引，清理进度”。三开关：使用记忆 / 生成记忆 / 检索历史聊天。按 t7u **不加记忆容量上限、不加临时会话**。
- **S07 助手身份**：名称、语气、长期偏好；预览→保存/放弃（Muse M3 流程）+ CAS；固定说明“身份设定不授予任何权限”（必须保留的语义）。修改记录可查看、可还原到某版本（工程建议）。
- **经验整理**：提案卡显示 base 版本与差异；“应用/拒绝/部分应用”；运行记录页显示每次 run 的输入版本、产出、是否已回滚。

## 4. 验收用例（负例为主）
| # | 场景 | 步骤 | 期望 |
|---|---|---|---|
| A1 | 并发编辑 | 桌面与手机（或两个窗口）同时以 v3 编辑同一条 | 先到者 v4；后到者收到 Conflict{v4}，不覆盖；UI 展示三方对比 |
| A2 | 模型提案与用户编辑竞争 | 提案基于 v3，用户已改到 v4 后点“应用提案” | 拒绝应用，提示重新生成/手动合并 |
| B1 | 删除源聊天 | 删除含事实来源的聊天 | 派生 fact 标记“来源已删除”或按策略 tombstone；下一回合注入前过滤；索引命中 0；回执显示 purge 进度 |
| B2 | 删除源聊天时有排队任务 | 排队任务快照含该聊天片段 | 任务执行前重新过滤，不带入被删内容；若无法剔除则任务进入“需重新确认” |
| C1 | 整理后再编辑 | run R1 合并 a,b→c(v1)；用户改 c→v2；回滚 R1 | 不自动回滚；冲突提示；绝不恢复已 tombstone 的 a |
| C2 | 回滚后的重复点击 | 连点两次回滚 | 只产生一个新版本（幂等 key = run_id+applied_version） |
| D1 | 恢复旧备份 | 删除条目 m 后恢复删除前备份 | m 不复活；导入日志列出“因墓碑跳过 1 条” |
| D2 | 旧设备离线后重新上线（若未来启用同步） | 旧设备持有 m | m 被墓碑拒绝；不承诺跨设备一致直至同步方案落地 |
| E1 | 撤权后旧摘要迟到 | 连接器 G 撤权；之前发起的压缩/摘要任务在撤权后返回且含 G 数据 | 摘要因 policy_epoch 不匹配被丢弃；不注入、不入记忆；记录“已丢弃迟到摘要” |
| E2 | 压缩失败 | 模拟压缩出错 | 保留原历史，提示失败；未送达输入标出（参考 lost_to_compaction） |
| E3 | 记忆模式中途切换 | 会话中关闭“生成记忆” | 在途回合产生的写入提案被拒绝或转为待确认 |
正常/空态/离线/取消/重复点击：S06 空态说明“尚无记忆”；离线时编辑排队但带 expected_version，上线冲突即提示；取消编辑不写版本。

## 5. 残余风险与无法保证
- 模型可能在回答中“记得”未入库内容（上下文内残留）；本机方案只能保证**库与注入**层面过滤，不能保证模型输出不复述本会话已见文本。
- 删除派生 embedding 的物理清除是异步的，保证的是读取过滤而非即时物理删除。
- 不承诺跨设备全局顺序或 exactly-once。
