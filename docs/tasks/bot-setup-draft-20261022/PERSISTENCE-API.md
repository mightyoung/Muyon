# Bot 草稿显式导出/恢复接口 v1

2026-10-22 UTC；在原任务分支继续。新增的是 reducer 的安全编辑数据边界，不实现第二套持久 store，不接 Runtime/Service/UI，不修改 main/develop。

## Host 可调用接口

```kotlin
// 同一 UI owner 上取得导出快照；expectedRevision 是当前内存 revision。
val exportedMemoryRevision = draft.snapshot().revision
val bytes: ByteArray = draft.exportDraft(
    storedRevision = nextStoredRevision,
    expectedRevision = exportedMemoryRevision,
)
// bytes 交现有 host app-private store 做原子写入 + expectedStoredRevision CAS。
// 导出成功不代表已保存，存储成功回调也只能确认 exportedMemoryRevision，不能确认后来的编辑。

val restored: RestoredBotSetupDraft = BotSetupDraft.restoreDraft(
    bytes = privateRecordBytes,
    newHostScope = trustedCurrentAccountProjectScope,
    newDraftId = freshHostDraftId, // 可省略，默认新 UUID
)
val storedVersion: Long = restored.storedRevision // 仅供 host 存储版本处理
val reducer: BotSetupDraft = restored.draft       // 内存 revision 固定从 0 开始
```

参数/格式/语义无效均抛 `IllegalArgumentException`；拒绝整条记录，不返回部分恢复结果，不降级猜测未知版本。导出检查当前内存 revision；不具有文件写入、存储 CAS 或 durability 能力。host 必须先验证来源 namespace/account/project，不能让文件内容决定当前 scope。

导出允许未请求创建、明确拒绝后的编辑数据，也允许已取消但仍留存的本地草稿。PENDING、UNKNOWN、CREATED 一律拒绝导出。历史上已导出的纯编辑快照本身不知道随后发生的创建；**host 必须先查自己的未决创建/停止台账并阻止相应记录恢复**，不能用旧纯编辑快照清除 unknown 或重新创建。这里没有真实创建调用。

## 最小固定二进制格式

最大32768字节（包含32字节校验和）；所有数值大端，schema固定1，不支持扩展尾随字段。

| 顺序 | 编码与约束 |
| --- | --- |
| magic | 4字节 `0x4D594244`（MYBD） |
| schemaVersion | int32，必须1 |
| storedRevision | int64，非负；host 自己负责 CAS、回滚拒绝与版本耗尽，绝不装成内存 revision |
| name | field：origin byte（0=user）、userLocked byte（严格0/1）、UTF8字节长度int32、字节；UTF16≤60 |
| purpose | 同上，origin只能user，UTF16≤8000 |
| role | 同上，origin可0=user/1=template，UTF16≤160 |
| templatePresent | byte，严格0/1 |
| template（如有） | UTF8字节长度int32+模板id字节（UTF16≤64）、version int32；label不存，恢复使用本地常量 |
| checksum | 之前全部字节的SHA256，固定32字节；必须匹配 |

字段不保存revision。空字段只允许origin=user、unlocked；非空user字段必须locked。template角色必须unlocked，且role与template id/version精确匹配现有已审本地模板；无模板角色不能夹带模板出处。按固定顺序读取，不使用任意 JSON key 或反射。UTF8严格解码，不用替换字符容忍畸形输入；逐字段复用现有长度/可见性/控制格式字符/UTF16校验。所有长度先有界再分配，截断、未知flag、未知schema/magic、负版本号、额外内容或hash损坏拒绝。

SHA256是**完整性/损坏校验，非认证或加密**。能改写内容并重算hash的攻击者仍可构造一条语义有效的编辑记录；不宣称这里能识别这种恶意改写。app-private隔离、来源认证（如现有host合同需要）、备份/回滚控制由 host 负责；不增加凭据/密钥或权限。

## 保存与恢复的语义

仅保存 name/purpose/role 的文字、origin/userLocked，以及已采纳role的必要模板出处和独立storedRevision。没有credentials、scope、旧draft_id、步骤、字段/内存revision、capability/material候选与选择、失效提示、执行grant、权限、费用、budget、creation intent/receipt/agent_id、suggestion request/token或建议候选。

恢复构造新 reducer；从 NAME、memory revision0、字段revision0、未取消开始，creation=NOT_REQUESTED、suggestion=null、所有候选和选项为空。新scope和draft ID由可信host决定。name/purpose/role编辑值与锁保留；步骤需重新走，host重新提供当前允许能力/资料，旧授权和复核不会恢复。既有 `restoreScope` 仍只是内存归属检查，正式字节恢复走此显式API，禁止反射私有字段。

## 测试先行、独审与证据

- 测试先行提交：`5e41b625fd05d14c41a76f649ce39a735da3a0c4`；接口不存在时编译 RED，原始诊断见 `persistence-evidence/red.stderr.log`。
- 首个实现提交：`49ad2a8dfe7fe65bad600d985f9e1631252191da`。
- 17组离线检查：原11组 + 6组新接口检查，涵盖编辑/锁/模板、部分输入、全新scope/revision、旧suggestion失效、能力/创建状态不恢复、导出CAS/未决创建拒绝、所有截断长度、尾随、坏校验、未知schema、超限、锁flag/origin/坏UTF8和不完整模板。
- 命令：`KOTLINC=/tmp/bot-setup-tools/kotlinc/bin/kotlinc apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/run-offline-checks.sh`。
- 作者带时间/命令/环境/hash的新日志见 `persistence-evidence/author/`，非作者独立日志见 `persistence-evidence/independent/`。initial-green日志来自首次实现检查，不补造未保存的精确起止时间；RED原诊断同样保留。
- 新负向变异：放开schema版本、绕过checksum、放开未决创建导出、绕过导出内存CAS、把storedRevision装入内存、删除用户锁校验。要求每项先编译成功，再被行为断言检出；规则与原始输出见作者metadata和逐项日志。

这批未落地host磁盘存储、进程恢复设备测试或正式Agent创建；17组检查不能替代上述验收。旧两个真实请求unknown/¥0.002620预占与费用未知保持原状，无真实模型/搜索、凭据、付费、部署或历史拒绝重试。

## 本批最终独审结论

测试先行完整SHA：`5e41b625fd05d14c41a76f649ce39a735da3a0c4`。固定接口源码SHA：`49ad2a8dfe7fe65bad600d985f9e1631252191da`，其后只追加报告与证据，未改复审代码。

作者最终新复验UTC：05:05:04.682664–05:05:56.932420；17/17 PASS，六项变异全部compile exit0、run exit1。
非作者独立新复验UTC：05:05:00.125060–05:05:07.288581；17/17 PASS、exit0。
非作者额外在/tmp构造重新计算SHA后的10类非法语义及94个payload截断，全部拒绝；有效对照通过（05:05:47–05:05:56）。其helper完整源码、命令和原始输出保存在negative metadata/logs中，未改仓库测试。

独审结论：无阻断/应改，可交付固定host编辑归档接口；不构成host存储/创建安全闭环或合入批准。主运行metadata SHA256：`88e506abc5eb5c2fb0a06a0c45367622307132a7512cba33e5ee03802e6fd098`；额外负例metadata SHA256：`5ccef743d70a5d67de1cea15fabf221f840ec71b3dd2ddfc4cc96460f24d1c0d`。

证据校验：从 `persistence-evidence/` 运行 `sha256sum -c SHA256SUMS`。父侧接收时应保留测试先行及接口提交的先后关系；若按提交选取，应先应用测试提交再应用接口提交，而不是只取新增codec文件。
