# 记忆、经验与后台整理接口

给管理界面用。界面不在这里做。入口都在已经打开的 `MuyonHost` 上：`host.foundation` 管存储，`host.dream` 管一次整理，`host.memoryReview` 只做只读预览。

`MuyonHost.open` 会构造 `DreamService`，不会调用 `run()`。整理只能由用户在界面上发起。不要在启动、定时器或打开页面时自动跑。

概率、提案和经验都不是工具授权。这组接口没有工具参数，也不会批准写入或外发。

## 从哪里拿

| 对象 | 来源 | 界面怎么用 |
|---|---|---|
| `FoundationRepository` | `host.foundation` | 记忆和经验的增删改查 |
| `DreamService` | `host.dream` | 用户按下整理、接受提案、回滚 |
| `MemoryReviewService` | `host.memoryReview` | 只读预览。`current` 在仓库通知约 200 毫秒后刷新 |
| `OpenAiModelGateway` | `host.services.gateway` | 已交给 `host.dream`。界面不要自己再包一层去调模型 |

`MemoryReview` 只分组，不写库。重复和冲突要让用户接受时，走 `DreamService.accept`，不要按 `MemoryReview` 的分组直接改记忆。

## 范围

`AssistantScope`（`package:muyon_module_api`）：

- `AssistantScope.global()`
- `AssistantScope.workspace(workspaceId)`
- `AssistantScope.selectedObjects(refs, {workspaceId})`

可见性：条目范围是 global，或编码后的范围与请求完全相同。没有“工作区包含其下对象”这种放宽。

收窄等级：global = 2，workspace = 1，selectedObjects = 0。相同范围不算收窄。workspace 只能收到同一 `workspaceId` 的 selectedObjects。selectedObjects 只能收到同一工作区里的非空真子集。

## 记忆

类型 `PersonalMemory`。字段：`id`，`content`，`source`，`createdAt`，`updatedAt`，`expiresAt`，`scope`，`sourceRef`，`verified`，`revision`，`disabled`，`kind`，`inference`，`lineage`。`toJson()` 可直接给界面。

`kind` 只允许 `source`、`fact`、`topic`、`summary`。`isExpired`：`expiresAt` 非空，且当前时间不早于它。

| 方法 | 行为 |
|---|---|
| `memories({includeExpired = false, includeDisabled = false})` | 管理列表要看停用和过期时，两个参数都传 true。默认隐藏停用和过期 |
| `memoriesFor(scope)` | 助手上下文。只要未停用、未过期、已核实、且对 `scope` 可见的记忆 |
| `saveMemory({id, content, source, expiresAt, scope = global, sourceRef, verified = true, disabled = false, kind = 'fact', inference = false, lineage = const []})` | 返回 id。空正文或空来源、未知 kind 会抛 `ArgumentError`。同一 id 再次调用就是修改：更新各列并把 `revision` 加 1。没有单独的 `updateMemory`。新 id 即使正文相同也允许。若该 id 最新一条 memory 墓碑的原因是 `deleted`，抛 `StateError('已删除的记忆不会被重新写入')`。换一个新 id 仍可写入相同正文 |
| `setMemoryDisabled(id, disabled)` | 改行上的停用标记并加 revision，同时写 disabled 或 enabled 墓碑。隐藏靠行标记，不靠墓碑。不存在则 `记忆不存在` |
| `narrowMemoryScope(id, scope)` | 范围必须变窄，否则 `ArgumentError('新范围没有变窄')`。不存在则 `记忆不存在`。这条记忆，以及 lineage 引用它的派生记忆、evidence 引用它的经验，都改成新范围并加 revision |
| `deleteMemory(id)` | 给这条记忆和所有 lineage 引用它的记忆写 deleted 墓碑并删除行。evidence 引用它的经验改为 `retired`，并按经验正文哈希写 deleted 墓碑，使同样正文不能再 `saveExperience` |
| `deletedContent(content)` | 正文哈希是否已被 deleted 墓碑挡住。整理在写入摘要或经验前会查它 |
| `contentHash(content)` | 静态方法。先 trim，再把连续空白收成一个空格，再 sha256 |

修改一条记忆：用原 id 调用 `saveMemory`。

## 经验

类型 `ExperienceEntry`。字段：`id`，`content`，`source`，`scope`，`status`，`evidence`，`revision`，`createdAt`，`updatedAt`。`toJson()` 可直接给界面。

`status`：`candidate`、`verified`、`retired`。

| 方法 | 行为 |
|---|---|
| `experiences({includeUnverified = false, includeRetired = false})` | 默认只返回 `verified` 且未退役。管理列表要看候选时传 `includeUnverified: true`；要看退役时再传 `includeRetired: true` |
| `experiencesFor(scope)` | 在默认列表上再按范围过滤。助手只带已核实经验 |
| `experience(id)` | 没有则 null |
| `saveExperience({id, content, source, scope = global, evidence})` | 永远插入 `candidate`。id 已存在则 `经验已存在`，不能靠它修改。正文已被删除墓碑挡住则 `已删除的内容不会被重新写入` |
| `verifyExperience(id)` | 只有 `candidate` 能确认，否则 `只有候选经验可以确认`。确认后助手才看得见 |
| `retireExperience(id)` | 已是 retired 则什么都不做。否则写 retired 墓碑并把状态改为 retired。不存在则 `经验不存在` |

一次成功的任务不会自动把经验变成通用规则。`DreamService.observeSuccess(experienceId)` 只检查经验存在（否则 `经验不存在`），不改状态。

## 只读预览

`MemoryReviewService.current` 是 `MemoryReview`：

- `duplicates`：同一范围、空白归一后正文相同、且多于一条的组
- `conflicts`：同一范围、键值形式 `键：值` 或 `键:值`（键最长 40 字）下，正文不完全相同的组
- `expired`、`disabled`：过期和停用的记忆
- `summary`：给人看的短行

停用记忆不进入重复和冲突分组。这个对象不能接受、不能回滚。

## 后台整理

`DreamService(repository, {gateway})`。宿主已经建好。

### 运行状态

`DreamRun.status`：`running`、`done`、`interrupted`、`reverted`、`failed`。

`DreamProposal.status`：`proposed`、`accepted`、`reverted`。

`DreamProposal.kind`：`duplicate`、`conflict`、`summary`、`experience`。

`DreamRun` 字段：`id`，`status`，`inputs`，`seen`，`outputs`，`snapshotJson`，`modelProfileId`，`outboundIds`，`tokenCost`，`tokenCostEstimated`，`elapsedMs`。

`DreamProposal` 字段：`id`，`runId`，`kind`，`status`，`evidence`，`payload`。

| 方法 | 行为 |
|---|---|
| `runs()` | 按开始时间列出全部运行 |
| `runRecord(id)` | 没有则 null |
| `proposals({runId})` | 不传则全部提案 |
| `run({ModelProfile? profile, bool leaveRunning = false})` | 见下文 |
| `accept(proposalId)` | 见下文 |
| `revert(runId)` | 见下文 |
| `observeSuccess(experienceId)` | 不改状态 |

### `run`

1. 先把仍是 `running` 的行标成 `interrupted`。
2. 水位是最近一次 `done` 的 `seen`。令牌形如 `m:id:revision:disabled:scopeJson` 和 `e:id:revision:status`。seen 没变就直接返回那次运行，不再调用模型。
3. 否则插入 `running`，并在这一刻拍下 `organizationSnapshot()`。
4. `leaveRunning: true` 在生成提案前返回，只给测试用。界面不要传。
5. 离线提案来自 `MemoryReview(repository.memories())`，也就是默认隐藏停用和过期。只有和本次变化 id 相交的组才会生成提案。
6. 只有 `profile != null` 且确有变化时才调模型，经 `OpenAiModelGateway.chat`，`caller` 为 `dream`。不传 profile 就没有模型调用，也没有隐式远端地址。`profile != null` 但 dream 没有网关时抛 `整理用的模型需要显式的网关`。宿主构造时已经把网关传进去了。
7. 模型只能返回摘要、冲突展示和经验候选。失败则这次运行标 `failed` 并重新抛出。
8. 费用是估算：`(prompt.length + response.length) ~/ 4`，`tokenCostEstimated` 为 true。`outboundIds` 是这次调用前后、`caller=dream` 的出站记录之差。

接受一次重复提案会停用记忆，seen 就变了，下一次 `run` 不会被当成同一次。

### 提案载荷

- `duplicate`：`keepId` 是 revision 最高者，revision 相同则 id 较小者。`disableIds` 是其余 id。`accept` 对 `disableIds` 调用 `setMemoryDisabled(id, true)`。
- `conflict`：`sources` 为 `{id, revision, source, content}`。模型来的冲突另有 `summary`。`accept` 抛 `冲突只展示来源，不能自动消解`。界面只展示来源，让人自己改记忆。
- `summary`：`content`。`accept` 调用 `saveMemory(source: 'dream', kind: 'summary', inference: true, verified: false, lineage: evidence)`。范围必须和全部证据相同，否则 `证据范围不一致，不能合并成更宽的范围`。证据停用、过期、revision 变了或不存在则 `证据已变化、停用或删除`。没有证据则 `提案没有证据`。不会放宽成 global。正文已被删除则 `已删除的内容不会被重新写入`。
- `experience`：`content`。`accept` 调用 `saveExperience`，状态永远是 `candidate`，界面还要人再 `verifyExperience` 才会进入助手上下文。
- 其他 kind：`未知提案`。
- 提案不是 `proposed`：`提案已处理`。成功后提案变为 `accepted`。

### `revert` 恢复什么

只能回滚最近一次 `done`。否则 `只能回滚最近一次已完成的整理`。

它调用 `restoreOrganizationSnapshot`：按运行开始时的快照，删除并重写全部记忆、经验和墓碑。然后把该次运行的提案和运行本身标为 `reverted`。

这会撤销快照之后对记忆、经验和墓碑的修改，包括用户在整理之后亲手做的修改。界面在回滚前要把这句话告诉用户。

`organizationSnapshot()` 返回 `{memories, experiences, tombstones}`。界面用 `revert`，不要自己拼快照再 `restoreOrganizationSnapshot`，除非是在做和回滚等价的恢复。

## 界面不要做的事

- 不要在启动时调用 `dream.run()`。
- 不要把 `MemoryReview` 的分组直接写成停用或删除。
- 不要因为一次 `observeSuccess` 就把经验标成 verified。
- 不要给整理传工具，也不要把它的提案当成已经批准的工具调用。
- 用户没有选定模型档案时，调用 `run()` 且不传 `profile`。选定之后才把该 `ModelProfile` 传进去。
- 远程档案仍要走现有网关规则：https 加凭证。本地回环档案不要求凭证。不要在界面里另开出口。
