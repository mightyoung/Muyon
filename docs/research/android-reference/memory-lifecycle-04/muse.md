# MEMORY-LIFECYCLE-04 · Muse (Meta) 11.0.0.8.164

样本：com.facebook.aura 11.0.0.8.164 / versionCode 1061601403；base APK SHA256 `c7e788b5…cefa`；签名 SHA256 `a16bbe02…7e99`（Meta，APKMirror 参照一致）；jadx 1.5.3（138 方法未反编译，含 `saveContent` 主体 → 以 jadx 回退的寄存器伪码阅读）。仅静态。官方资料访问日期 2026-10-13。

## 1. 一页结论
- **客户端代码直接证据**：MEMORY.md / IDENTITY.md 的手动编辑都是**整文件覆盖**（`overwrite=true, append=false`），请求里没有版本、ETag、预期修改时间；客户端成功后把 `lastUpdated` 设为**本机时钟**而非服务端 mtime。并发控制在客户端不存在；服务端是否有锁 = 未知。
- **客户端代码直接证据**：“导入记忆 / 汇总进记忆”不直接写文件，而是给 agent 发一条聊天消息，让 agent “用记忆工具”自行提取和写入 —— 写什么、是否标“(inferred)”由模型决定。
- **官方当前规则**：删除消息/文件/侧聊后“Muse 可能仍记得”；Forget 技能“尽力而为”；断开连接器后此前数据“可能留在记忆与对话历史”；Muse 维护 VM **备份**；Reset 永久删除全部。→ 删除不传播到派生记忆，是产品明示的设计。
- **未发现**：暂停记忆、无痕会话、关闭历史检索的开关（只有分析事件名 `incognito_toggle`，无调用链）；整理/合并提案与回滚；墓碑；压缩摘要的客户端结构。

## 2. 对象与生命周期表
| 对象 | 谁产生 | 存在哪 | 何时进上下文 | 证据 |
|---|---|---|---|---|
| 用户手填记忆 | 用户在 Identity→Memory 编辑 | 云 VM 工作区 `MEMORY.md`（整文件） | 未知（服务端注入方式不可见） | 客户端代码直接证据 M1/M2 |
| 模型推断/事实记忆 | agent 经“memory tooling” | 同上或“supporting files” | 未知 | 官方当前规则（customize 页列出“观察到的偏好和模式”“连接器上下文”）；导入提示词 M4 |
| 导入记忆 | 用户上传 zip / 粘贴 → agent 提取 | agent 自行写入；zip 存 `imports/` 目录 | 未知 | M4（`IMPORTS_DIR="imports"`, `sendChatMessage`） |
| 身份/人格 | 用户编辑 IDENTITY.md；SOUL.md 只 stat/读 | VM 工作区 | 写入成功后 `gateway.refreshIdentity()`；模型侧注入未知 | M3 |
| USER.md / 目标 | 未追到写入者 | VM 工作区 | 未知 | 字符串（HatchGoalsTabDataSourceKt:50），线索 |
| 聊天历史 | 系统 | 服务端，`fetchChatHistory(beforeSeq)` 分页 | 未知 | 字符串线索 |
| 聊天摘要/压缩摘要 | 未发现 | — | — | 未知 |
| 经验/整理提案 | 未发现 | — | — | 未知 |

## 3. 关键调用链
### 3.1 记忆编辑（M1、M2）
`MemoryViewModel.saveContent` → `MemoryDataSource.saveContent(content)`（MemoryDataSource.java:243）
1. L8b–L90：CAS 更新本地 StateFlow `isSaving=true`（`_data.A6F(old,new)` 是**内存 StateFlow 的 compareAndSet 重试循环**，不是服务端 CAS）。
2. 行 339–342：`HatchFileOperations.writeFile("MEMORY.md", content, session, overwrite=true, append=false, createParent=true, expectedGatewayUrl=null)`；multipart 字段 `path / create_parent / overwrite`（HatchFileOperations.java:4776-4778）。
3. 返回分支：`WriteResult.Success` → `copy(content, …, lastUpdated=System.currentTimeMillis())`（行 277-283）；`WriteResult.Failed` → `message` 等于某常量则 `StatusError.MissingCredentials`，否则 `StatusError.SaveError(message)`，保留旧 `content` 不回滚编辑框（行 290-317）；其他 → `NoWhenBranchMatchedException`。
- 结论：没有“冲突/409/版本过期”分支。客户端代码只能证明**此路径**没有并发控制；服务端未知。
### 3.2 身份编辑（M3）
`IdentityViewModel` 保存协程（IdentityViewModel.java:565-596）：读 `_uiState.content` → `writeFile(IDENTITY_FILE_PATH, content, session, true, false, true, null)` → 成功则 `originalContent = content` 并 `gateway.refreshIdentity()`。`originalContent` 只用于本地 `discardChanges()`/脏检查，**不随请求发送**，所以不是 CAS 基线。SOUL.md / MEMORY.md 只做 `statFile` 取 `modifiedAt` 显示“修改日期”（行 678-734）。
### 3.3 导入（M4）
`HatchImportMemoryToHatchViewModel.addMemory(text)`（行 418）：空文本或 `isSending` 直接返回（防重复点击，仅本地）→ 协程 `sendChatMessage`；异常 → 日志 `addMemory: sendChatMessage failed` 并显示“Couldn't send memory”。提示词要求 agent “Skip anything ephemeral or sensitive. Confirm what you stored.”，UI 文案“This is not a verbatim copy”。→ 用户看到的确认来自**模型回复**，不是存储回执。

## 4. 七个问题逐条
1. 分类：见表。服务端注入时机全部未知。
2. 暂停/不保存/无痕/关闭检索：**未找到**客户端字段和过滤点（仅 analytics 名 `incognito_toggle`）。`HatchPauseEnrollment*` 是 agent 暂停相关的入组流程，不是记忆暂停（推断，基于类名与 `clearTemporaryData(hatchlingId)` 调用）。读/写分离：未发现。
3. 编辑：整文件覆盖，无版本字段，错误分支只有 MissingCredentials / SaveError。
4. 删除：客户端有 `deleteFile` 与“删除消息”文案；派生记忆不随之删除 = **官方当前规则**明说“可能仍记得”；断开连接器同理。索引/缓存/通知/导出副本/排队请求的处理 = 未知。Reset = 官方“永久删除…无法撤销”，客户端未追到后端处理。
5. 整理/回滚：未发现。官方提到“Ask your Muse to revert any change”——由模型执行，不是版本化回滚（官方当前规则 + 推断）。**备份**：官方说 Muse 维护 VM 备份；备份恢复是否会复活已删记忆 = 未知（风险点）。
6. 压缩：未发现客户端结构 → 未知。
7. 用户可见解释：MEMORY.md 全文、SOUL/MEMORY 修改日期（`modifiedAt`）、头像状态“Is updating memory”（官方）、Activity log（官方）。没有每条来源、是否推断（除导入提示词要求模型写“(inferred)”）、使用范围、“本次回答是否用了”的字段 = 未发现。

## 5. 可借鉴 / 不宜采用
- 借鉴：记忆可直接以全文查看编辑；身份与记忆分文件；删除文案**诚实**地说明派生信息可能残留。
- 不宜：整文件覆盖无 CAS；“导入→模型自行记”把存储回执换成模型自述；Forget 尽力而为。

## 6. 局限
`saveContent`/`loadContent`/`writeFile$2.invokeSuspend` 均为 jadx 未完全反编译；未做 smali 逐条核对 writeFile 的 HTTP 错误码处理。服务端一切不可见。
