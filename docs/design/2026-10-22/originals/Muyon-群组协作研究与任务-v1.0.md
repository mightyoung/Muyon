# Muyon 群组协作研究与任务 v1.0

核查：2026-10-22 03:32 UTC（北京时间 11:32）。执行位置：云端。范围：公开官方文档阅读、现有项目核查记录复核、原创设计和待办编排；未安装框架、未实验、未调用付费模型、未改变仓库或账户。

## 1. 决策摘要

建议支持三种协作方式，但分阶段交付：①固定 AI 协调者；②每项任务选择协调者，允许受控移交；③不设 AI 协调者，由宿主按明确规则调度。三者共享同一套权限、预算、任务账本和回执，不提供“自由无限讨论”。这些是针对 Muyon 的设计建议，不是已经验证的效果或已经上线的能力。

人类群组管理者 owner/admin 管理成员、配置和其被授权管理的资源；AI coordinator/leader 只能提出计划、分工与汇总。两者不是同一身份。可以由某个 Bot 担任协调者，也可以不选 Bot；群主身份本身不授予模型外部执行权。单用户本地群组也保留用户身份作为权限主体，不因“不设群主”变成无归属资源。

第一开发批次应是无真实调用的治理与调度底座。当前真实聊天与自动编排尚未验收，不能先包装成成熟群聊。复杂任务是否更适合 leader、质量和成本是否改善，仍需未来同模型、同预算的对照验证。

## 2. 依据与证据边界

下列为此次已读原文。页面未提供可固定的本次发布/更新日及 commit，故文档版本记为“2026-10-22 所见在线版本，精确版本未知”，不能作为依赖锁定依据。

- S1 [OpenAI Agents SDK：Agent orchestration](https://openai.github.io/openai-agents-python/multi_agent/)：区分保留主控、将专家作为工具调用的 manager，与把当前轮交给专家的 handoff；也支持代码确定流程。它说明控制流选择，不证明多人/多 Bot 一定优于单 Agent。
- S2 [OpenAI Agents SDK：Handoffs](https://openai.github.io/openai-agents-python/handoffs/)：可过滤移交输入；参数相关授权须在副作用前检验。历史摘要不是脱敏，接收模型也是数据接收方，不能把可用性开关当作参数授权。
- S3 [LangChain：Multi-agent](https://docs.langchain.com/oss/python/langchain/multi-agent)：指出单 Agent 配合工具可能已足够；列出子代理、handoff、router 与 custom workflow，并强调每个 Agent 看见什么上下文。未采用网页星级作为实测收益。
- S4 [langgraph-swarm-py 官方仓库](https://github.com/langchain-ai/langgraph-swarm-py)：通过 handoff 切换活跃 Agent，checkpoint 保留多轮状态；默认传递共享历史可以定制。它不是“所有成员无限并发发言”，默认全历史也不适合直接成为 Muyon 数据策略。
- S5 [AutoGen：Selector Group Chat](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/selector-group-chat.html)：模型可选择下一发言者，也可用自定义选择函数；回应广播后检查终止条件。其示例有 mock 工具，不能作为真实搜索效果证据。
- S6 [AutoGen：Termination](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/termination.html)：支持消息、token、超时、外部停止等条件；token 终止依赖用量上报。因而缺失用量不能等同零成本。
- S7 [AutoGen：Magentic-One](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/magentic-one.html)：orchestrator 规划、委派、跟踪和调整；官方同时提示人工监督、访问限制和网页注入风险。此次没有复现其基准，不把报告表现移植为 Muyon 承诺。

项目依据：已读当前检查记录，其固定候选为 [f4781e16ddf4e542b983fbd77f266a0071148255](https://github.com/mightyoung/Muyon/commit/f4781e16ddf4e542b983fbd77f266a0071148255)。记录确认持久 root/child 账本、深度 1/活跃 2/累计 8 与取消重启防护；自动模型委派、真实并发推理及父任务综合尚未验收。此报告没有重新做全仓独立审查。现有 2 次真实请求 unknown、预占 ¥0.002620 与实际费用未知保持原状；不能由新群组模式绕过。

## 3. 模式取舍

| 模式 | 适合先考虑的场景 | 代价及失败点 | Muyon 建议 |
|---|---|---|---|
| 固定协调者 | 同一专业群长期做相似任务，希望统一答复 | 额外模型调用、单点误判、协调者可能遮蔽少数证据 | 可配置默认 Bot，但执行前显示；结果保留来源和分歧；不是默认群主 |
| 每任务协调者 | 专业主题变化，某次由研究 Bot、另一次由文档 Bot 主导 | 移交成本、旧状态/旧授权重放、双 leader | 任务创建时选择；运行中移交仅边界检查点，原子增 epoch，旧 leader 失效；不自动升权 |
| 无 AI 协调者 | 用户直接 @成员、固定顺序、独立结果并排、简单分类路由 | 不能假装自主拆复杂任务；结果不自动形成可靠共识 | 最小实现采用显式 @ 或预设有限工作流；宿主选下一个可运行节点；汇总可确定性并排，不强行调用隐藏 leader |

简单单 Bot 问答不启多 Agent；两项独立只读子任务可受容量限制并行；存在依赖、跨专业综合的任务才考虑受控协调者。高风险外部动作不因多 Agent 投票而自动获准。以上为工程推断，未作性能比较。

## 4. 运行协议

1. 用户创建任务，明确目标、允许的成员/模型提供商、材料 scope、输出要求、预算与停止条件。群默认只是模板，任务捕获不可变配置版本；改群设置不静默改变进行中任务。
2. Coordinator 输出结构化提案，不直接生成子孙树。宿主验证 DAG、成员允许列表、数据许可、预算和当前容量后才创建 root 的一级 child。嵌套提案必须展开为 root 下的合法依赖节点或拒绝，不能突破深度 1。
3. 所有模式由宿主调度器决定执行：显式 @ 优先；否则有限预设路由或已通过验证的计划。2 个 active slot 和累计 8 个 child 是硬上限，不由提示词覆盖。重试/替换不得重置累计数量或预算。新运行轮数、移交次数、超时阈值必须显式配置并有限，不能用“直到成功”。
4. 工作节点只返回结果、证据引用、失败/unknown、所需动作提案。多个节点输出分开发送还是统一呈现是 UI 决策，不让每个模型直接向用户重复通知。每条展示有真实 speaker_id、run_id、状态与材料来源。
5. 交接包包含目标、已完成节点、未决项、最小必要材料引用及版本、剩余额度和未决回执。新协调者只获得 scope 交集；切换模型提供商涉及新数据接收方时必须重走相关数据授权。旧 epoch 的指令不能调度或提交动作，结果可归档为迟到证据。
6. 争议先按 claim_id 并列证据、日期、资料版本与不确定性。同一来源转述不能算独立投票。有限只读复核可消解事实差异；无证据或超预算则展示分歧/请用户决定，不以多数模型数当真值。
7. 超时/失联先进入 interrupted/reconciling，查询原 request_id/action_id 回执，再决定是否可恢复。未发送的队列可取消；已发送请求的“停止”仅停止后续派发，不证明未收费。unknown 保留预占，不自动重发，不启动替代 leader 重复执行同一动作。
8. 外部副作用只经宿主单一动作网关。有效权限 = 用户授权 ∩ 群策略 ∩ 任务策略 ∩ 成员能力 ∩ 当前工具策略；leader 无权扩大任一项。确认绑定 canonical payload digest、scope、版本、接收方与费用边界，改参数或过期后重确认；group owner 和 AI 不能代替必要的人类批准。
9. action_id、意图、请求摘要在派发前持久化；回执/重放去重。对于不支持幂等键的外部系统，不声称网络下 exactly-once：不确定时查询/人工核实，禁止盲重试。唯一执行者是降低双发的设计边界，不是远端成功保证。
10. 观测只展示可验证事件：queued、running、awaiting_approval、interrupted、reconciling、unknown、failed、completed；不得用模型说“完成”替代产物与宿主回执。总花费需区分已知实际/预占/unknown，所有 Agent、协调调用、搜索与工具都纳入同一根预算。

## 5. 原创 schema 草案（不是现有 API）

```text
GroupConfig { group_id, revision, owner_user_id, admin_user_ids,
  members:[{agent_id, capability_profile_id, provider_id}],
  coordination:{mode:fixed|per_task|host_only, default_coordinator_id?},
  allowed_material_scope_ids, policy_revision }
Run { run_id, group_id, config_revision, initiating_user_id,
  mode, coordinator_id?, coordinator_epoch, state, root_task_id,
  limits:{max_depth:1,max_active_children:2,max_total_children:8,
          max_dispatches,max_handoffs,deadline},
  budget:{currency,ceiling,reserved,known_actual,unknown_request_ids},
  grant_refs, material_scope_snapshot, plan_revision }
Node { node_id, run_id, parent:root_task_id, dependencies,
  agent_id, input_scope, status, request_id?, attempt, output_refs }
ActionProposal { action_id, run_id, node_id, coordinator_epoch,
  scope, payload_digest, expected_revision, recipient,
  approval_id?, status, receipt_ref? }
Evidence { evidence_id, claim_id, source_ref, source_version?,
  observed_at, origin:primary|derived, supports|contradicts|unknown }
Event { event_id, sequence, run_id, node_id?, timestamp,
  actor_id, kind, cause_id, receipt_ref?, redacted_payload }
```

```text
dispatch(proposal):
  load persisted run; verify config/epoch and live host authority
  reject stale, cyclic, cross-scope or above depth/capacity/lifetime caps
  if unresolved unknown affects reserve or duplicate risk: pause + reconcile
  if paid transport lacks valid cost proof: block, do not send
  validate payload-specific authority and required human approval
  transactionally reserve budget, append intent and acquire dispatch lease
  execute through host gateway using stable request/action ID
  persist receipt or unknown; never convert missing usage into zero
  release compute lease separately from accounting reserve
```

配置字段名称仍需对照现有 Rust 类型与迁移协议；上面不是复制竞品代码，不要求引入 Python/TypeScript 框架。采用现有 Rust/SQLite 账本优先。

## 6. 群组 UI

入口：群组详情 → 协作方式。三个选项文案：“固定协调者”“每项任务选择”“不设协调者（按规则协作）”。管理成员与权限是另一分区，避免同一“群主”开关混合两种含义。

任务开始卡展示本次协调者或宿主规则、参与者、资料范围、预算、停止边界。“无协调者”显示“由你指定成员或按预设顺序执行”，不能暗示无成本自动群聊。运行中切换放高级项，显示交接预览及已执行/未决操作，不能把切换当重启。

聊天顶部保留用户已定“主 Agent + 置顶对话/群组”逻辑；群组可用轻量成员头像集合，协调角色徽标限任务级，不能永远画皇冠绑定群主。展开任务卡可看分工、依赖、队列、产物、来源、分歧、unknown 与停止回执。保持柔黑/柔白背景、低饱和功能色及克制吉祥物；不新增独立炫技风格。

## 7. 已列入待办的稳定任务

状态均为“设计完成，待开发/验收”，不等于已派发执行。归入现有 Agent 编排闭环任务，避免创建平行重复主任务。

| ID | 交付 | 依赖 | 正向验收 | 反向验收 |
|---|---|---|---|---|
| GR-01 | owner/admin/coordinator 分离类型、三模式、版本迁移 | 现有 root/child 数据模型 | 旧群迁移后权限不增，三模式可保存读回 | 空 leader 不丢资源 owner；未知枚举 fail closed |
| GR-02 | 宿主确定性队列、DAG、容量与停止条件 | GR-01 | @成员和依赖任务顺序可重放，最多2活跃 | 第9 child、深度2、环、自派无限任务拒绝；重启不清计数 |
| GR-03 | 结构化计划与受控 leader 移交 | GR-02/04/05 | 安全检查点转移，剩余任务/预算连续 | 旧 epoch 拒绝；双 leader/无权限接管/循环交接不执行 |
| GR-04 | scope 交集、最小交接包、唯一动作网关 | GR-01 | 已批准且摘要匹配动作有唯一宿主回执 | 越权工具、跨项目材料、换接收方、旧确认、注入文本升权拒绝 |
| GR-05 | 根预算聚合、未知账务与恢复 | GR-02/04 | 可核回执后正确结算，取消只停后续 | 真实费用缺失不填0；unknown不释放预占或重发；无cost proof不请求 |
| GR-06 | claim证据/分歧/产物汇总 | GR-02/04 | 汇总能定位来源版本，保留失败子任务 | 同源转述不计独立佐证，缺产物不completed，禁止多数投票当事实 |
| GR-07 | 模式设置、开始预览、任务状态/移交卡 | GR-01/05；真实态接入依赖02/03/06 | 黑白主风格、可访问标签、无leader说明正确 | UI乐观更新不能显示已执行；停止不显示已退款；未实现模式不可伪装可用 |
| GR-08 | 离线故障注入和恢复验收矩阵 | GR-01～07分阶段 | 重启、迟到、重复回执、拒绝、取消路径可复测 | 崩溃派发窗口、并发批准、陈旧scope/lease、预算缺口均fail closed |

最小批次 A：GR-01 + GR-02 + GR-04 + GR-05 + GR-08 的离线 fixture 部分，先完成 host_only，不使用真实供应商、自动推理或外部写入。复用 MU typed组件/回执与 PX scope/来源任务，不重复造两个状态系统。
批次 B：GR-03 + GR-06 + GR-07，先固定协调者，再每任务选择/受控移交；模型结果仍用离线fixture，全部示例标注。接入现有 UI 统一任务，不另开群聊视觉语言。
批次 C：独立授权后的有限真实验收，前置是当前候选审查、生产费用证明、供应商边界与双请求 unknown 的账务处理策略；本次不执行。对照同任务单 Agent/固定leader/无leader宿主流程，观察质量、延迟、token、实际费用、失败与恢复，而非只看回答长度。样本、预算、人工评分及阈值另定，不宣称此处已取得收益。

## 8. 未决项与停止边界

- 默认面向用户开放哪种模式尚未最终产品定稿；建议先以 host_only 离线底座验证，UI 不先承诺固定 leader。
- 人类多用户共享群目前是否在产品范围内未验证；本设计字段预留不代表已支持成员间资源共享。
- 真实模型多 Bot 自动协作、provider计费/幂等行为、取消后费用、外部receipt覆盖均未实测。
- 第三方框架文档是模式参考，不是安全保证，也不证明 Muyon 已实现同等功能。
- 本次只把研究与任务加入总任务文档，不创建 GitHub Issues/PR、不启动新实现线程、不改 main/develop、不部署、不绕过既有 gate。
