# agent_dispatch / agent_model_turn 拆分前特征测试清单（GB-4）

日期：2026-10-11 · 任务：[GB-4](../tasks/GB-4.md) · 执行：工程师2号（grokbot）· 分支：`review/gb-2-research-write-contracts`（接在 [GB-3](2026-10-11-change-log-coverage.md) 后）
方法：只读 `apps/muyon/lib/assistant/agent_dispatch.dart`（940）与 `agent_model_turn.dart`（890），对照 [拆分方案](2026-10-10-large-file-split-plan.md) §13、§15，以及经 `PersonalAgent` / `LoopFixture` 间接覆盖的宿主测试。**未**改代码、**未**运行 Flutter。行号以本分支 HEAD 为准。
给谁用：拆分实现者；拆前补特征测试的 PR；审查对照「行为被改坏时是否有测试会失败」。

---

## 0. 读前摘要

- 两文件**没有**直接 `import` 自身的单元测试；覆盖几乎全部经由 `PersonalAgent` + `support/agent_loop_fixture.dart`（及生产宿主 `MuyonHost` 套件）。
- 安全敏感路径（确认卡、子任务效应闸、无效读参数恢复、自动授权连续前缀、目标脱敏、取消/interrupted、协议纠正、预算耗尽）**多数已有间接测试**；真正的拆分缺口集中在：**私有辅助的精确契约**、**晚取消收尾**、**回执与任务同事务的失败回退**、**`_external` 分类边界**、**无效 destination 展示**。
- 拆分建议：方案 §13/§15 的「part + `mixin … on` 原类」**可以纯搬运**；两文件均无 `@override`；阻碍主要是互相 `late` 引用与跨 mixin 的共享私有辅助，不是语言层面的硬阻断。

**回报摘要**：缺口 **14**（按风险排序）；拟新增特征测试 **18** 条；前 5 高风险缺口见 §3。

---

## 1. 方法清单

### 1.1 `AgentDispatch`（`agent_dispatch.dart`）

| 方法 | 可见性 | 职责（一句话） | 持久状态 | 安全不变量 |
|---|---|---|---|---|
| `_requestOf` | 私有 | 从 live binding 或 step 快照重建 `ToolCallRequest` | 读 `invocationRequests` | 凭证型 destination 只在 live binding，不靠卡上脱敏串重建 |
| `_displayDestination` | 私有 static | URI 去 query/fragment；非法则 `[invalid destination]` | 无（展示/快照） | 卡片/消息不得带 credential query |
| `displayParameters` | **公开** static | 对 `destination` 键套 `_displayDestination` | 无 | 同上；native assistant `tool_calls` 参数亦走此路 |
| `_planned` | 私有 | 一步内单次调用的准备快照（含 disposition/脱敏参数） | 写入 task `step.calls` 前的结构 | 展示参数已脱敏；`identityDigest`/scope/effect 来自 prepare |
| `_cardView` | 私有 static | 确认卡上单次调用的可见字段子集 | 无 | 不含 outcome；digest 不含人选 |
| `dispatch` | **公开** | S4：冻结候选校验 → 逐个 prepare（含子任务效应复核）→ 并行读 / 开卡 | task `stage=tool`、`step`、`stepFolded=false`；事件 `toolProposed`；invocation 映射 | 候选外拒绝；`maxCallsPerStep`/`maxCardCalls`；子任务非读闸；prepare 后再次 `checkTool` |
| `_stage` | 私有 | 写入 running / waitingConfirmation 的 payload 键 | `state`、`toolCall(s)`、`toolSelection`、`requestDigest`、`preview`、`expiresAt`、`approvalNonce` | 多人 digest=digest(identity 列表)；人选不进 digest；5 分钟过期 |
| `_cardAllowed` | 私有 | 开卡/提交前任务是否仍可改 | 读 closing/cancel/token/terminal | 关闭或已终态不得再变 waiting |
| `_stopBeforeCard` | 私有 | 开卡前若取消则 settle cancelled | task → cancelled | 取消优先于开卡 |
| `_openCard` | 私有 | 外部预标记 → review → 自动授权连续前缀或等待确认 | `toolReviews`；可能直接 `executeCard(automatic:true)`；或 commit waitingConfirmation + wait 事件 | 整卡 pending 外部并集先持久化再 review；`ReviewAction.block` 失败；自动仅**连续**授权前缀；`stale_scope`/审查异常 → `review_stale` |
| `toggleSelection` | **公开** static | 切换卡上勾选：关掉则关掉其后所有 | 无（纯函数） | 后写可能依赖前写；未知 id 抛错 |
| `_record` | 私有 | 给 step.calls[index] 写 outcome | task `step` 内存副本 | 固定 `not_run_*` 文案键，不用模型话 |
| `_recordResults` | 私有 | 同事务写 task + `tool_result` 事件；commit 失败则仍补事件 | task + 事件流 | 「回执与任务同事务」；任务已非 running 时事件仍保留 |
| `_chargeActive` | 私有 | 累加活动时长预算 | `BudgetUsage` payload | 不计等人确认的时间（调用方只在 invoke 前后计） |
| `_external` | 私有 | 是否视为外部/需预标记 | 无 | 非 pure-local-write，且 external access / `mcp:` / inquiry|knowledge|research |
| `_markExternal` | 私有 | 对 invocation（及返回 objectRefs）写 `authorizationFacts.markExternal` | 授权事实表；`_premarked` 去重 | 审查前预标记；invoke 后真实 ref 再标；失败后预标记仍在 |
| `_invokeOne` | 私有 | 单次 prepare 后的 invoke；abandoned/cancelled/ran | 可能 markExternal；registry 回执 | 非 running/closing → abandoned；子任务 `checkTool`；取消 → cancelled；拒绝/验收失败按 cancel 标志分流 |
| `_runReads` | 私有 | 并行读；取消丢弃结果；失败则折叠卡上写为 `not_run_invalid_arguments` 并 `_complete`，成功则 `_openCard` | toolTokens/toolActive；step outcomes；终态或开卡 | 读无外效可丢弃；`interrupted` 停；失败读不得执行计划写 |
| `executeCard` | **公开** | 确认后按模型顺序逐个 prepare→digest 比对→approve→invoke；失败/取消停后续 | approvals、receipts、step outcomes、预算；可能再开卡或 `_complete` | 一用一批；`stale_scope` 不执行；自动路径用 `sign`；自动跑完若仍有剩余则 `allowAutomatic:false` 再开卡；interrupted≠cancelled |
| `completeStep` | **公开** | 恢复路径入口 → `_complete` | 同 `_complete` | 与在线收尾同一套折叠规则 |
| `_correctableRead` | 私有 | 仅当 access+effect 均为 read 且 status=`invalidArguments` | 无 | 效应写不得借「参数错」继续模型轮 |
| `_complete` | 私有 | S5：折叠 messages/toolLog/refs；失败则 fail；否则 `model.advance` 或 `finish` | messages、`stepFolded`、references、summary；可能终态 | 固定 `notExecuted` 文案；`lateCancel` 或无 profile → `finish` 不再请模型；成功才进下一轮 |
| `_logEntry` | 私有 static | 预算摘要用的短 toolLog 行 | toolLog | summary 截断 120；不引密钥原文（依赖上游 redact） |

### 1.2 `AgentModelTurn`（`agent_model_turn.dart`）

| 方法 | 可见性 | 职责（一句话） | 持久状态 | 安全不变量 |
|---|---|---|---|---|
| `advance` | **公开** | S0：预算耗尽则结束，否则压缩后 `waitForModel` | 可能 fail；或进入模型确认 | 耗尽不发请求 |
| `_exhausted` | 私有 | 用回执摘要写 fail（宿主文案，非模型） | task failed + code `budget_*` | 不把模型原文当失败原因 |
| `waitForModel` | **公开** | 组 preview/digest → gate → 模型确认卡；可自动 `runModel` | waitingConfirmation 或 running；wait 事件；可选 `authorizationPolicyRevision` | 非 `GateConfirm` 不发；审查 block 停；超大上下文拒；native 把 tools/mode 纳入 digest |
| `_beforeSend` | 私有 | 每次真正发送前的闸 | 无（抛错） | 会话有效；策略修订；未过期；memoryDigest；scope 一致；planning 会话未过期 |
| `checkPermissionTask` | **公开** | prepare 期间任务/档案/scope/记忆是否仍一致 | 无 | `model_source_changed` |
| `preparePermission` | **公开** | 组 wire/compatible payload 调 `modelAuthorization.prepare` | 审查/授权侧状态 | 与 preview digest 绑定；`checkCurrent` 回调 |
| `runModel` | **公开** | take 权限后 `_runPermittedModel` | 权限消费 | 非 automatic 须已有 review；manual/automatic 分流 |
| `_runPermittedModel` | 私有 | 兼容/流式/非流式路径；协议解析后 dispatch 或 finish | modelTokens；drafts；round/messages；计费 | 取消/关闭中途退出；坏协议纠正而非执行；引用校验 |
| `_modelRequest` | 私有 | 构造 `ModelRequest`（native tools / jsonObject） | 无 | 能力冻结于 task profile |
| `_collect` | 私有 | drain + 400/422 → 固定 `FixedFailure` | 无 | 拒流式/拒工具不换协议、不重发 |
| `drain` | **公开** | 流式收集；首事件后才记 `modelRequest`；draft 只记长度/digest | 事件；内存 draft | 账本行出现才算已发出；draft 文本不进事件 |
| `_streamCompat` | 私有 | 兼容模式流：整段后再严格 JSON；意外 tool_calls 清空 | 无 | 非 JSON 不当工具执行 |
| `_compacted` | 私有 static | preview 中上次压缩前后 token | 无 | 人确认看到压缩事实 |
| `_outputCap` | 私有 | 预算将尽时限制 maxOutputTokens | preview | 仅流式/native 路径带 cap |
| `_bill` | 私有 | 累加 active 时间与 tokens（估或报） | BudgetUsage | 不计等人时间 |
| `_responded` | 私有 | `modelResponse` 事件（用量/draft 元数据，无正文） | 事件 | 不落模型正文 |
| `_failure` / `_throwIfFailed` | 私有 static | 流错误/截断/不可用 → 固定失败 | 无 | 不引模型原文 |
| `_runNative` | 私有 | 原生工具回合：校验 call → `dispatch`；坏呼叫整包丢弃纠正 | drafts；dispatch 全套 | 候选外/非法参数整包丢；destination 仍不信任，靠 registry；assistant 参数经 `displayParameters` |
| `_answerNative` | 私有 | 纯文本答案；坏 `[rN]` 剥掉并注明 | finish | 兼容模式坏引用是 fail；native 降级保留答案 |
| `_protocolReply` | 私有 static | 严格整段 JSON → tool/answer | 无 | 无 fence/抽取 |
| `_notJson` | 私有 static | 是否根本不是 JSON | 无 | 纠正文案分支 |
| `_correctOrFail` | 私有 | 至多一次协议纠正后 `advance` | `protocolCorrections`、messages | 丢弃坏回复；纠正也算一步并再确认 |

---

## 2. 现有间接覆盖

夹具主入口：`apps/muyon/test/support/agent_loop_fixture.dart`（`LoopFixture`）。公开 API 多经 `PersonalAgent`（`executeCard`/`runModel`/`toggleSelection`/`displayParameters`/`advance`）。

### 2.1 主要落到 `AgentDispatch` 的测试

| 测试文件 | 代表测试名（节选） | 覆盖到的方法/分支（静态推断） |
|---|---|---|
| `agent_dispatch_safety_verification_test.dart` | `child … at prepare boundary … has no effect`；`invalid read alongside … never recovers or runs old write` | `dispatch` prepare 后二次 `checkTool`；`_runReads` 失败折叠写；`_correctableRead`；`_complete` |
| `agent_batch_card_test.dart` | 并行读；读+写开卡；超限 `notExecuted`；勾选/取消勾选；失败停后续；`stale_scope`；过期卡；取消整卡/并行读 | `dispatch`、`_runReads`、`_openCard`、`executeCard`、`toggleSelection`、`_stage`、`_complete`、`_record` |
| `agent_read_argument_recovery_test.dart` | invalidArguments 继续；非 read/非 invalid 永不继续 | `_correctableRead`、`_complete`、`_runReads` 失败路径 |
| `assistant_tool_grants_dispatch_test.dart` | review block 无卡无效应；Noop + knowledge 预标记先于 review | `_openCard` review/`_markExternal`；destination 脱敏快照 |
| `assistant_production_auto_order_test.dart` | `actual host ordered automatic / prefix` 等 | `_openCard` 连续自动前缀；`executeCard(automatic:true)`；剩余再开卡（`allowAutomatic:false`） |
| `assistant_production_auto_write_test.dart` / `assistant_production_policy_order_test.dart` | 自动写/策略边界 | `_openCard` + `executeCard` 授权 sign/confirm |
| `assistant_cancel_test.dart` | 等人确认时取消；效应前/后取消；读中取消 | `_stopBeforeCard`、`executeCard` cancel/interrupted、`_runReads` 丢弃 |
| `assistant_native_destination_privacy_test.dart` | native complete destination snapshots remain private | `displayParameters` / `_displayDestination`（合法 URI 去 query） |
| `agent_resume_test.dart` / `manual_resume_hold_test.dart` | 接管后 `completeStep`、未知回执 hold | `completeStep` → `_complete`（经 `AgentResume`） |
| `personal_agent_streaming_test.dart` | native 写仍等人；候选外违规 | 经由 `_runNative` → `dispatch` |

### 2.2 主要落到 `AgentModelTurn` 的测试

| 测试文件 | 代表测试名（节选） | 覆盖到的方法/分支（静态推断） |
|---|---|---|
| `agent_budget_test.dart` | 步数/时长/token 耗尽；等人不计时；closing 中断流 | `advance`、`_exhausted`、`_bill`、`_chargeActive`（经 dispatch）、`_outputCap` |
| `personal_agent_streaming_test.dart` | 流式 JSON；截断；拒 stream；native 多分支；ledger 记不住则不发；gate 非确认则停；引用未通过校验 | `drain`、`_streamCompat`、`_throwIfFailed`、`_runNative`、`_answerNative`、`waitForModel` gate、`_correctOrFail` |
| `assistant_protocol_correction_test.dart` | 纠正一轮；markup 不执行；错误 shape；`maxProtocolCorrections` | `_protocolReply`、`_correctOrFail`、`_notJson` |
| `personal_agent_rejections_test.dart` | 过期确认、scope 变、预览变、超大上下文、坏 citation（兼容） | `_beforeSend`、`waitForModel` 大小检查、兼容答案引用 fail |
| `assistant_production_model_*`（permission/grant/review/protocol/…） | mode_auto、wire review、grant 消费 | `waitForModel`、`preparePermission`、`runModel`、自动/人工权限 |
| `context_compaction_test.dart` | 压缩后继续 | `advance` → compaction → `waitForModel`；preview `compacted`（推测） |
| `agent_drafts_test.dart` | draft 与协议纠正交互 | `_runPermittedModel` finally `interrupt`；discard/commit |

### 2.3 明确**没有**「按方法名直达」的覆盖

- 无测试文件 `import` `agent_dispatch.dart` / `agent_model_turn.dart` 后直接 `AgentDispatch(...)` / `AgentModelTurn(...)`（静态检索：生产调用方为 `personal_agent` / `agent_resume` / `agent_compaction_flow`）。
- 因此私有方法只能靠行为断言间接钉住；拆分时若只改「看起来等价」的内部顺序，现有测试可能仍绿。

---

## 3. 缺口（按风险排序）

凡「没有任何测试能在该行为被改坏时稳定失败」或「仅弱覆盖、断言不钉契约」者列入。已有强覆盖的（如 prepare 二次 checkTool、连续自动前缀 `prefix`、invalidArguments 恢复、destination query 脱敏）不重复列为缺口。

| # | 风险 | 缺口 | 为何现有测试不够 |
|---|---|---|---|
| G1 | **高** | `executeCard` → `_complete(..., lateCancel: true)`：取消请求晚于成功完成后的收尾须 `finish`（summary 含「取消请求晚于完成」），**不得**再 `model.advance` | 取消套件主钉 cancelled/interrupted；静态未见「晚于完成」文案或 `lateCancel` 断言 |
| G2 | **高** | `_recordResults`：`commit` 因任务已非 `running` 失败时，仍须把 `tool_result` 事件补上（「回执与任务同事务 / 否则事件仍保留」） | 未见专门制造 commit 失败仍保留事件的用例 |
| G3 | **高** | `_external` 分类：`mcp:` provider、`inquiry`/`research` module、以及 `isPureLocalWrite` **排除**预标记 | 仅有 `knowledge` + Noop 预标记路径；pure-local 只在 registry 测，未钉 dispatch 预标记跳过 |
| G4 | **高** | `_openCard`：审查前须对**整卡**调用 `_markExternal`（并集先持久化）；中途 `_stopBeforeCard` 须能打断后续 review | grants 测钉「先于 review」，未钉多调用并集与中途取消打断审查循环 |
| G5 | **中高** | `_correctableRead` 与 `_complete`：access/effect **双** read 才可把 invalidArguments 当可纠正内容发给模型；缺一则走 fail | recovery 测覆盖正向；缺「access=read 但 effect=write」伪组合的反向钉（生产 descriptor 难伪造，但拆分时易改条件） |
| G6 | **中高** | `dispatch`：`Assistant is closing` / 准备阶段异常统一 `fail('工具参数、可用性或范围校验未通过')` vs 执行期 redact 失败文案 | closing 有流中断测；未见 prepare 环内 closing 与两阶段错误文案分界 |
| G7 | **中** | `_displayDestination`：非法 URI → 字面 `[invalid destination]`；合法 URI 保留 scheme/host/port/path、剥 query | 隐私测只覆盖合法带 query；非法串未见 |
| G8 | **中** | `_stage`：单调用 vs 多调用的 `requestDigest`/`preview` 形状；`toolSelection` 仅 waitingConfirmation；人选变化不改 digest | batch 测有 digest 形状，但对「只改 selection、digest 不变」断言弱（推测） |
| G9 | **中** | `executeCard` 自动路径：`authorization==null` 或无 `effectIntent` 时 `automatic_authority_unavailable`；`sign` vs `confirm` | 生产自动测走完整 host grants；缺「automatic 但无 authority」拒绝 |
| G10 | **中** | `_invokeOne`：external 路径 mark 后、invoke 前再次检查 closing/running → abandoned，且不把 abandoned 当失败回执乱写 | 取消/关闭测未精确区分 abandoned 与 cancelled |
| G11 | **中** | `waitForModel`：`HostModelWireReviewRequired` 只 commit 卡并 return（等人）；block / FixedFailure / 其它异常分支文案 | production review 有覆盖（部分）；WireReviewRequired「停在卡上不发」与 block 文案宜各有一条特征名 |
| G12 | **中** | `_beforeSend` / `checkPermissionTask`：`planning_session_expired`、`model_source_changed`（profile/memory/scope） | rejections 覆盖过期确认与 scope；planning 过期与 prepare 中途 profile 变较弱 |
| G13 | **低中** | `_outputCap` / preview：仅流式或 native 写入 `maxOutputTokens`；非流兼容为 null | budget 测有「所剩即上限」；非流兼容不加 cap 的反向断言弱 |
| G14 | **低** | `_logEntry` summary 120 字截断；`_notRunText` 键全集（含 `unknown_before_resume` / `not_run_resume`） | resume 有语义；文案键与截断长度未见钉死 |

---

## 4. 特征测试清单（拟新增）

目标：拆分后若有人改坏行为，下列测试失败。尽量复用 `support/agent_loop_fixture.dart`；生产授权边界可复用 `MuyonHost` + `ConfirmModelReviewer`（同 `assistant_production_auto_order_test.dart`）。**不在本任务实现。**

### 4.1 调度（`AgentDispatch`）

1. **`late_cancel_after_successful_write_finishes_without_model_advance`**
   - 构造：`LoopFixture`；模型先提 write；人确认后 handler 在效应后暂停；`cancel`；再放行成功回执。
   - 断言：终态 `succeeded`（或 finish 路径）；summary 含「取消请求晚于完成」；**无**第二次模型请求（`f.bodies` 不增加）；消息已折叠 `stepFolded==true`。
   - 抓住变异：`lateCancel` 被忽略导致再次 `model.advance`；或误标 `cancelled`/`interrupted`。

2. **`tool_result_events_kept_when_task_commit_loses_race`**
   - 构造：并行读或写返回成功瞬间把任务打成终态（竞态：另一路径 `settle`），迫使 `_recordResults` 的 `commit(..., expected: running)` 失败。
   - 断言：`tool_result`（或等价事件表）仍有对应 invocation；回执存在。
   - 抓住变异：删掉 commit 失败后的事件回退循环。

3. **`external_premark_skips_pure_local_write_but_marks_research_module`**
   - 构造：注册 `moduleId=research` 的非 pure-local 工具，与 `isPureLocalWrite==true` 的本地写工具各一；开卡前检查 `authorizationFacts`。
   - 断言：research 调用有 external 预标记；pure-local 无预标记；均在 review/确认前完成判定。
   - 抓住变异：`_external` 漏 module 或忘 `!isPureLocalWrite`。

4. **`mcp_provider_is_treated_external_for_premark`**
   - 构造：`providerId` 以 `mcp:` 开头的工具上卡。
   - 断言：确认前已 `markExternal`（invocation ObjectRef）。
   - 抓住变异：去掉 `mcp:` 分支。

5. **`card_marks_entire_pending_external_union_before_any_review`**
   - 构造：两调用卡；reviewer 计数；facts 表在第一次 `review` 进入时已有 **2** 条预标记。
   - 断言：`reviewer.calls` 增前 facts 已齐；取消若插在两 review 之间则第二次 review 不发生且无效应。
   - 抓住变异：边 review 边标记；或取消不打断循环。

6. **`correctable_read_requires_both_access_and_effect_read`**
   - 构造：用测试 descriptor 覆写（仿 `ChangingDescriptor`）做出 access/effect 不一致且回执 `invalidArguments`；同步仍带 write 候选。
   - 断言：任务 fail 或不再进模型；write 调用次数 0。
   - 抓住变异：只判 `access` 或只判 status。

7. **`invalid_destination_snapshot_is_literal_placeholder`**
   - 构造：参数/destination 为 `not a uri`；经 native 或 startTool 上卡/入消息。
   - 断言：持久化 payload / assistant tool_calls 参数含 `[invalid destination]`，不含原串可执行形式。
   - 抓住变异：原样写入或改成 empty/null。

8. **`selection_change_does_not_change_tool_card_digest`**
   - 构造：三写开卡；记录 `requestDigest`；`toggleSelection` 后只改 `toolSelection` 再读任务（或经 UI API）。
   - 断言：digest 不变；确认仍用原 digest。
   - 抓住变异：把 selection 打进 `_stage` digest。

9. **`automatic_execute_without_authority_fails_closed`**
   - 构造：迫使 `_openCard` 走 automatic 集合但 `toolAuthorization==null`（或 effectIntent 空）——若夹具难以构造，标「未能静态确认可测性」，改为注入 Fake authorization 在 `sign` 返回 null。
   - 断言：该调用 `failed`/`approve_failed` 类 outcome，后续不执行；无 handler 效应。
   - 抓住变异：automatic 回退到无批准 `invoke`。

10. **`invoke_abandoned_when_closing_after_external_premark`**
    - 构造：external 工具；mark 后、handler 前 `agent.close()`。
    - 断言：无成功回执落地为 succeeded；任务不因 abandoned 误写假 failed 回执（与 close/interrupt 现语义一致）。
    - 抓住变异：abandoned 当 failed 并折叠进模型。

11. **`closing_during_prepare_uses_check_failure_message`**
    - 构造：在 `prepare`/`resolveScope` 等待中 close（仿 safety 边界 Completer）。
    - 断言：失败文案为校验类（「工具参数、可用性或范围校验未通过」）或关闭导致的安全终态；**不是**执行期「执行失败（…）」模板（若关闭表现为 closing 抛错进第一段 catch）。
    - 抓住变异：两段 catch 合并导致错误归类。

### 4.2 模型回合（`AgentModelTurn`）

12. **`wire_review_required_leaves_model_card_without_send`**
    - 构造：model authorization 抛 `HostModelWireReviewRequired`（或 production review 模式）。
    - 断言：task `waitingConfirmation`/`stage=model`；`loop.bodies` 为空。
    - 抓住变异：当成 automatic 直接 `runModel`。

13. **`model_content_block_fails_with_fixed_reason`**
    - 构造：`preparePermission` → `ReviewAction.block`。
    - 断言：fail 文案含「模型内容审查阻止发送」；无出站请求。
    - 抓住变异：block 仍发送。

14. **`planning_session_expired_before_send`**
    - 构造：`uiPlanningInternal==true` 且清掉 `uiModelChecks[taskId]` 后确认发送。
    - 断言：不发送；任务失败/拒绝（`planning_session_expired`）。
    - 抓住变异：删掉 `_beforeSend` 该检查。

15. **`check_permission_task_detects_profile_change_mid_prepare`**
    - 构造：`preparePermission` 的 `checkCurrent` 触发前改 task profile 快照。
    - 断言：`model_source_changed`；无发送。
    - 抓住变异：`checkPermissionTask` 漏比 profile。

16. **`nonstreaming_compat_preview_omits_max_output_tokens`**
    - 构造：capabilities 非 stream 非 native；预算所剩很少。
    - 断言：确认卡 `preview.maxOutputTokens` 为 null（或键不存在）；流式对照任务则有值。
    - 抓住变异：`_outputCap` 丢掉 early return。

17. **`drain_announces_model_request_only_after_first_stream_event`**
    - 构造：gateway 先阻塞，确认后尚无事件时检查事件表；再放行首事件。
    - 断言：首事件前无 `modelRequest`；之后恰有一条；与「账本行出现才算已发出」一致。
    - 抓住变异：发送前抢先写事件。

18. **`native_bad_citation_strips_but_compat_bad_citation_fails`**（若 streaming 已钉 native，本条作对照强化）
    - 构造：同坏 `[r99]` 分别走 native 与兼容。
    - 断言：native summary 含「引用未通过校验」且 succeeded；兼容 fail 无答案。
    - 抓住变异：两模式行为对调。

---

## 5. 拆分建议（相对方案 §13、§15）

### 5.1 方案回顾（仍适用）

- **dispatch**：主文件保留构造、展示辅助、`dispatch`；`agent_dispatch_card.dart` / `_reads.dart` / `_complete.dart` 为 `part of` + `mixin … on AgentDispatch`。
- **model_turn**：主文件保留构造、`advance`、`waitForModel`；`_stream` / `_native` 为 mixin。
- 共享：`ctx`、以及被多段使用的 `_stage`、`_cardAllowed`、`_record`、`checkPermissionTask`、`preparePermission` 留主类。

### 5.2 「part + 同库私有扩展」能否纯搬运？

**可以。** 静态依据：

- 两文件**没有** `@override` 方法，不是 State/`extends` 体系；不存在「覆盖方法不能进 mixin」的阻碍（对比方案里 `workbench_app` 的 `build`）。
- 私有 `_` 成员仅库内可见；`part of` 后 mixin 与主类同库，**不必**改名或改公开。
- 库外只依赖**公开** API：`dispatch` / `executeCard` / `completeStep` / `displayParameters` / `toggleSelection`，以及 `advance` / `waitForModel` / `runModel` / `preparePermission` / `checkPermissionTask` / `drain` / `maxProtocolCorrections`。调用方：`personal_agent.dart`、`agent_resume.dart`、`agent_compaction_flow.dart`（及互相 `late` 字段）。迁到 mixin 后实例 API 不变。

### 5.3 非阻断但必须写清的耦合

1. **互相 `late` 引用**：`AgentDispatch.model` ↔ `AgentModelTurn.dispatch`（另 compaction 也挂 model）。拆分不改初始化顺序（仍在 `PersonalAgent` 里互指）；**禁止**在库顶层初始化时读对方。
2. **跨建议文件边界的私有辅助**：`_requestOf`、`_record`、`_recordResults`、`_chargeActive`、`_invokeOne`、`_markExternal` 被 reads 与 complete 两侧使用 → 留主类或单侧 mixin 被另一 mixin 调用（`on AgentDispatch` 可互调）。方案已要求 `_stage`/`_cardAllowed`/`_record` 留主类；建议把 `_invokeOne`/`_recordResults`/`_markExternal` 也留主类或放入 reads mixin 并文档化依赖。
3. **static 成员**：`displayParameters`、`toggleSelection`、`_displayDestination`、`_cardView`、`_protocolReply` 等宜留在**主类声明**（或主 part），避免审查时找不到「公开静态入口」。
4. **循环 import**：`agent_dispatch.dart` ↔ `agent_model_turn.dart` 今日已互相 import；part 拆分不消除循环，须与方案一样「同一次 PR 拆两者」。
5. **无障碍点**：未见其他文件以 `part of` 依附这两文件；也未见他库读取其私有成员。

### 5.4 拆分门禁（建议）

- 先合入 §4 特征测试（至少 G1–G5 对应条）。
- 再纯搬运；跑既有助手套件：`agent_batch_card_test`、`agent_dispatch_safety_verification_test`、`agent_read_argument_recovery_test`、`assistant_cancel_test`、`assistant_tool_grants_dispatch_test`、`assistant_production_auto_order_test`、`personal_agent_streaming_test`、`assistant_protocol_correction_test`、`agent_budget_test`、`agent_resume_test`（**本任务未跑**，仅点名）。
- diff 应为「移动 + `part`/`with`」，行为字节级尽量不变。

---

## 6. 局限

- 未运行任何测试；「覆盖到的方法」均为静态追踪公开 API / 断言语义的推断，标「静态推断」。
- 生产宿主测试（`assistant_production_*`）路径长，可能覆盖部分缺口的表面行为但**未**以特征测试命名钉契约；仍建议按 §4 补短测试，避免拆分回归时只绿长大测。
- `lateCancel` 竞态构造难度中等；若夹具难以稳定复现，可退化为对 `_complete` 的同库测试（需暂时 `@visibleForTesting` 或通过 `completeStep` + 手工 payload）——实施时再定，本文不改代码。

---

## 7. 回报（给 leader）

- 提交：见 git（工程师2号按 GB-4 交付）。
- **缺口数**：14（G1–G14）。
- **前 5 高风险缺口**：G1 lateCancel 收尾；G2 `_recordResults` 事件回退；G3 `_external` 分类；G4 整卡预标记并集；G5 `_correctableRead` 双字段。
- **拟新增特征测试条数**：18。
