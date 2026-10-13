# Muyon v1.3.2 文档迁移与决定追踪

版本 1.3.2　2026年10月14日 北京时间

目的：补齐Claude v1.3采纳评审指出的旧合同来源与迁移落点，区分继承、部分替代、新增目标和实施待验证。与[第一册](Muyon-Redesign-Plan-v1.3.2-2026-10-14.md)、[第二册](Muyon-Page-Design-Handbook-v1.3.2-2026-10-14.md)配套使用。本文件是文档切换计划，未修改仓库旧文、未创建生效ADR、未推送或合并产品代码。

## 1 基线与状态含义

- 产品源码与旧文来源固定为[01e56cc2d729dab70e1b1def05c3aa93b28f421a](https://github.com/mightyoung/Muyon/tree/01e56cc2d729dab70e1b1def05c3aa93b28f421a)
- 被评审的v1.3文档固定为[e014b097be94b48a6744c5d5df41a764918b0afa](https://github.com/mightyoung/Muyon/commit/e014b097be94b48a6744c5d5df41a764918b0afa)。相对843bc791实际新增22文件，不沿用评审的32
- 新产品决定以本轮用户明确选择为准；旧文中后来已有采纳记录的“未决”不能再次当未决。新版目标未实现，不把静态生产接线称上线或验收通过
- “继承”表示不变量继续约束；“部分替代”必须列具体模式/条款；“新增”不代表已实现；“实施后置”不等于删除功能。文档采纳、首片开工、单项能力开放和生产切换分别验收
- 本表的owner是任务角色建议，唯一集成人在M01/A00落实际负责人及独立审查人；没有指派具体人员或抢占旧writer

## 2 本轮决定与旧规则差异

| 决定 | 目标合同 | 继续保留的边界 |
| --- | --- | --- |
| 四档与默认 | 只读、每次询问、Auto、全部允许；低风险并入Auto；新装默认Auto | 旧standard/readOnly/custom不能直接改名或升权；期限、兼容映射细则仍在D01b冻结 |
| FullAllow数据范围 | personal/commercial默认在当前任务、已选工作区、现有读取权与允许用途内可送模型/业务外发，含新目的地且不额外问 | 显式禁外发、撤权、来源/系统限制和合法业务合同仍有效，不能发无关任务数据 |
| 未分类数据 | unreviewed在可信分类完成前不进模型/业务外发；未知枚举不当none | 分类来自可信模块/宿主规则及授权配置，模型不能自行降级 |
| 凭据用途 | credential原始值禁模型上下文/业务正文/日志；认证经credentialRef至身份绑定服务通道 | 不把合法认证误禁，也不允许凭新业务目的地复用另一服务秘密 |
| 新记忆能力 | 自动对话记忆提取与跨会话助手检索纳入，首次默认off、分别开关；D11独立排期 | 基线已有消息保存、最近16条上下文及手工记忆/用户整理；可选留存控制与临时会话未定 |
| 未知效果的新意图 | 先查核、不自动重发；用户明确再做一次可建可信关联的新操作，内联可能重复，FullAllow不追加确认 | acknowledged_unknown_ref不替代真实用户指令/权限；原unknown不因新操作改变；模型、重连、普通重试不算用户新指令 |
| 本机导出新副本 | 继承export-N2 D2，同冻结内容、新exportId、新A/B身份、新建目标 | 不能自动重放原操作或覆盖原目标；不能丢失旧unknown与实际文件能力 |

以上是产品设计决定，不是执行者对真实账号、秘密、数据发送、付费服务或生产切换的行动许可。

## 3 八份遗漏来源逐项迁移

每项均已核固定文件存在并阅读相关全文；下表是修订建议，旧文件未改。所有工程证据状态为“新版待实现/未执行测试”。

| 来源与旧决定 | 继承与部分替代范围 | 迁移单元和页面 | 任务 依赖 责任建议 | 出口与证据状态 |
| --- | --- | --- | --- | --- |
| [ADR-0004 module-contract-v2](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/adr/0004-module-contract-v2.md)，§3、§4.3–4.5、§12.1 Q7最终注记690–702 | 继承声明、敏感度、宿主权限/回执所有权、引用真值、能力覆盖。Dart/Flutter类型改为同源schema；旧新端点/taint询问规则仅在明确兼容模式保留，FullAllow按新版部分替代 | 03/11/14；S04、D01.1–.3、生成卡 | M02/D01a/D01b/D04；C1合同、G1独审；真实外发前固定 | 五分类及未知枚举、Q7准确字段、最终wire投影fixture；仅设计已补 |
| [ADR-0005 model-adapter-and-agent-loop](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/adr/0005-model-adapter-and-agent-loop.md)，§2.2与§7.1 | 继承统一网关、先记账、工具候选冻结、预算、分层及摘要审计。L29每次waitingConfirmation是历史现状，L452–453本来已有AUTH-1按授权分支；不能把整份文件说成永久每次确认。新模式频率/恢复映射逐条替代 | 08/13/20；A01、T02/T03、S02/S04 | D01/D03/D04/W4；C1、G2独审 | model/tool两分支全枚举、Noop未审、错误/超时语义；未运行 |
| [ontology-write-cards 2026-10-11](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/design/ontology-write-cards-2026-10-11.md)，CR-2 D1–D11经ADR0001:107采纳 | 继承模型仅草稿、宿主固定事实、领域校验、CAS、敏感投影、回执、呈现三档；§6外部内容只单次确认/隐藏旧全部允许按钮按新模式部分替代，旧按钮改“允许本批”。本机遮盖不因FullAllow数据默认自动取消 | 09–12/14；业务生成卡、S01.1/S04 | D01/D02、W3/W4/W7；C1＋A1/A2，G1审 | taint仍追踪、FullAllow不重复问、草稿不自写；未实现 |
| [folio-parity-checklist](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/design/folio-parity-checklist.md)，L3–8用户业务语义基准 | 保留页面、字段口径、状态、流程、交换格式、确认/撤销的业务不变量；视觉/技术路线改为新版。Hub按远端共享原义迁移。Q04真实发送/Q06 FX单列新增设计候选，不写“已批准新增” | 04/05/17/19；Q01–Q06、D01.1–.3、S05.1 | A00/W3/W5；C2业务、A1/A2页面、G2审 | 每行Folio能力有去向；未迁项显式标，不能用图缺失删除业务 |
| [atomic-batch-write-contract 2026-10-11](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/design/atomic-batch-write-contract-2026-10-11.md)，CR-6 B1–B5经ADR0001:113采纳 | 继承单物理领域事务、唯一operation_id/digest、整批回执、同ID异载荷拒绝、批内依赖禁隐式执行、50条取更严预算；旧taint/人工频率按新模式部分替代，不能扩大跨库原子性。旧unknown恢复仍只读；新用户另作一次按D03新合同严格绑定，不用普通重试换ID | 12；业务批量卡、T02/T03 | D01/D02/D03、W3/W4；C2事务、G1独审 | 整批原子、回执优先查核、无伪造批成功，AB反例对应新实现；未运行 |
| [conversation-fact-card-wiring 2026-10-11](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/design/conversation-fact-card-wiring-2026-10-11.md)，CR-8 D1–D5经ADR0001:111采纳 | 继承同逻辑卡、事实/建议/草稿分区、单明确对象、安全保存、恢复先核验、失效撤值、历史显示不变执行权；恢复零自动模型/业务执行/导航。Flutter组件改写；taint按当前模式映射，不使旧展示恢复grant | 09/10/20；A01/A03、动态卡、S01.1 | D02/D03、W4/W7；C1＋A1/A2、G2审 | 旧卡/晚回调/撤权/保存CAS、恢复无新增派发；未运行 |
| [research-local-export-facade 2026-10-11](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/design/research-local-export-facade-2026-10-11.md)，CR-17四项经ADR0001:118采纳 | 继承冻结内容、生成/系统另存两阶段、单文件本次能力、不存目录/URI持续权限、精确论文版本/claims V2/needs_review、分阶段回执和半文件恢复；A/B授权身份保留，人工风险确认频率按当前模式部分替代，系统选择与真实文件能力不删除 | 06/19；R页导出、S05/T02 | SPIKE-02/M21/D03/W2/W5；C2、A1/A2、G2审 | 各平台真实目标能力与原摘要、取消/unknown、独立阶段回执；旧LE时间盒非新版完成证据 |
| [export-n2-wiring 2026-10-12](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/design/export-n2-wiring-2026-10-12.md)，D1–D5经ADR0001:124采纳 | 继承实际writer绑定、selectionAttempt先持久化、open/truncate前校验、只读查核、平台×工具逐项开放、N2同事务删除/回执与跨写范围整拒。保留D2用户同冻结内容新本机副本例外，旧unknown不变。旧ab5506c3状态仅为历史；文件末尾未决已被后续采纳，不回退 | 06/12/19；R页导出/章节删除、T02/S05 | D03、W2/W5、P3；C2、G2独审 | 新副本身份/目标完整，旧unknown不重放，N2五态回执；实现与开放按新SHA另核 |

后续采纳统一来源：[ADR0001固定全文](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/adr/0001-leadership-and-scope-freeze.md)。CR-2的personal/commercial旧“不自动外发”只在本轮FullAllow已定数据范围内部分替代；其分类、默认本机遮盖、模型不得自授用途仍继承。

## 4 原文档入口切换清单

此前已登记的旧15个文件继续保留，以下仅列将来集成人应做的标注。每个文件页首写适用版本、被替代章节、新版入口、生效范围，正文历史证据不删。旧任务逐项登记继续、关键修复回移、已完成或待核，不批量取消。

| 文件 | 后续文档动作 |
| --- | --- |
| docs/tasks/README.md | 指向新目标及最新交接，保留旧任务表与时间 |
| docs/tasks/HANDOVER-LEADER.md | 标10-11为历史快照，沿ADR0001保留Leader A唯一集成人规定 |
| docs/tasks/CURRENT-STATUS-2026-10-10.md | 保留旧提交状态，新增目标引用，不回写为已实现 |
| docs/tasks/NEXT-DELIVERIES-2026-10-10-v1.md | 逐项标继续/回移/已完成/待核，关联迁移单元 |
| docs/superpowers/plans/2026-10-07-roadmap-phase2-4.md | 标旧Flutter路线适用范围，新P/M/D/W接管范围明确 |
| docs/superpowers/specs/2026-10-08-ai-native-architecture/2026-10-08-agent-platform-implementation-plan.md | 标版本和新版入口，原任务与证据保留 |
| docs/superpowers/specs/2026-10-08-ai-native-architecture/Muyon_AI_Agent与智能交互整体设计方案.md | 替代技术路线，继续继承业务/身份/回执不变量 |
| docs/design/ai-native-ui-redesign-2026-10-09.md | 旧强制询问/污染不放行标适用旧模式，按新模式差异引用 |
| docs/design/DESIGN.md | 保留旧Flutter/v6视觉基准，新双端令牌引用第二册 |
| docs/design/muyon-design-system.md | 同上，避免同时自称新产品唯一视觉权威 |
| docs/adr/0001-leadership-and-scope-freeze.md | 将来只追加可核实的本轮决定及范围，不删除旧决定 |
| docs/adr/0002-graded-assistant-authorization.md | 逐条标FullAllow新目的地/taint及reviewer映射的部分替代，保留旧事实 |
| docs/adr/0003-phase2-scope.md | 标阶段关系，旧退出标准/风险不因新计划自动完成 |
| apps/muyon/README.md | 仅加新规划入口，保留实际Flutter启动与数据隔离说明 |
| docs/implementation/muyon-acceptance-ledger.md | 只记实际证据；文档采纳是文档事件，不写Rust/Compose验收通过 |

### 授权与动态呈现专项旧入口

以下18项准确前缀均为`docs/tasks/`，逐文件登记；连同下表3份AIUI来源，本次仅补21份旧文档追踪，不新增实施任务或预算。统一页首标注：“适用旧Dart/Flutter实现与表内固定SHA；业务、身份、回执、真实来源不变量继续继承；旧授权模式/人工频率仅按新版明确条款部分替代；新入口为当前两册相应章节及MIGRATION-TRACE；原审查与CI只证明其原范围，不当新版通过。”审查记录保留正文、历史失败及后续修补，不重新写成已通过。owner由M01/A00现有责任表确定，不重新派发。

| 精确文件名（前缀docs/tasks/） | 适用旧版/证据性质 | 继承与部分替代登记 | 新版入口 |
| --- | --- | --- | --- |
| [AUTH-1a.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1a.md) | 旧库层任务（未接线） | 授权库、解析、撤销/审计和复核接口继承；旧新端点/持久授权限制按新模式部分替代 | D01b/D04；单元11 |
| [AUTH-1a-review.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1a-review.md) | 固定旧库层审查证据 | 保留原SHA、范围和当时结论；不推导新模式或生产接线通过 | D01b旧机制fixture/证据索引 |
| [AUTH-1b.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b.md) | 旧A/B/C接线总任务 | 可信宿主、scope/目标/版本/回执继承；新端点逐问与旧taint频率部分替代 | D01a/D01b/D04；单元11/13/14 |
| [AUTH-1b-review.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-review.md) | 旧A阶段独立审查 | 保留迁移、原子授权消费/审计/审批证据；不扩大为B/C或新架构通过 | D01b/P3；证据索引 |
| [AUTH-1b-summary.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-summary.md) | 旧接线阶段性总结 | 按记录的SHA解释旧standard/readOnly/custom及model_auto；不等同新版Auto | D01b差异表；S04 |
| [AUTH-1b-B1-facts-review.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-B1-facts-review.md) | 旧来源事实审查 | 保留taint继承、durable marker、取消边界证据；taint风险后的新模式动作部分替代 | D01b/D04；单元11 |
| [AUTH-1b-B1-review.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-B1-review.md) | 旧B1 checkpoint审查 | 可信事实/范围证明保留；不得推导B2/B3/C完整通过 | D01b；证据索引 |
| [AUTH-1b-B2-foundation-review.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-B2-foundation-review.md) | 旧B2基础审查 | 实际wire、私有proof、排队重验、原子账本/审批、真实通道约束继承；旧risk block/confirm映射部分替代 | D01b/D04；单元11/13/14 |
| [AUTH-1b-TLS-review.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-TLS-review.md) | 旧TLS审查与修补 | 保留实际peer证书身份绑定和真实传输边界；身份校验不是风险询问，不被FullAllow取消 | W5/W7；单元17/18 |
| [AUTH-1b-B12-boundary-repair.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-B12-boundary-repair.md) | 旧B1/B2边界修补 | 保留chunk前重验、真实sent计数、受管路径/namespace证明与祖先换链反例 | D01b/W5；单元11/17 |
| [AUTH-1b-B12-review.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-B12-review.md) | 旧固定修补复审 | 保留原失败与修后结论的各自SHA；不追溯改旧失败、不声称B3/C通过 | D01b；证据索引 |
| [AUTH-1b-B12-leader-review.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-B12-leader-review.md) | 旧精确集成门禁证据 | 保留精确审查/CI及接纳边界；旧负责人安排按最新唯一集成人更新入口而不改历史 | M01/A00；证据索引 |
| [AUTH-1b-B3-cancellation-checkpoint.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-B3-cancellation-checkpoint.md) | 旧optional/manual阶段 | 保留取消、实际review绑定及当时尚未生产接线边界；旧人工频率部分替代 | D01b/D03/D04；W4 |
| [AUTH-1b-B3-review.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-B3-review.md) | 旧固定B3审查 | 保留BLOCK及后续修补所对应版本；无产品新模式放行证明 | D01b/D03；证据索引 |
| [AUTH-1b-production-inputs.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-production-inputs.md) | 旧真实输入事实接线 | 保留同次加载的memory/history及不可伪造HostLoadedInputProof；clean不能模型自报 | D01b/D04/D05；单元11/14/21 |
| [AUTH-1b-production-automatic.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-production-automatic.md) | 旧automatic local-write子片 | 保留真实owner/不可变request/nullable grant来源；旧自动授权不是新版Auto，taint旧门禁部分替代 | D01b；W4 |
| [AUTH-1b-model-policy.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-model-policy.md) | 旧类别策略及model wire任务 | 保留四效果轴、真实profile/endpoint/字节/凭据/账本、生命周期重验；旧三档与review故障confirm按新版部分替代 | D01b/D04；单元11/13/14 |
| [AUTH-1b-model-policy-review.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AUTH-1b-model-policy-review.md) | 旧C1/C2精确审查集成 | 保留精确实施SHA、原失败/修复与现有模式自动来源证据；不升级新架构验收 | D01b/D04；证据索引 |

另补以下3个准确路径：

| 路径 | 适用旧版/部分替代 | 新版入口与继续继承 |
| --- | --- | --- |
| [docs/tasks/AIUI-DEFAULT-ENABLE-PLAN.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/AIUI-DEFAULT-ENABLE-PLAN.md) | 2026-10-10旧Flutter默认开启条件计划，不是已经执行；旧时间窗口/负责人状态保留为历史。新端默认开启与授权Auto是两件事；外部内容旧逐次询问、旧“全部允许”按钮措辞按当前模式部分替代 | 单元09/10/11/20、D02/D03/D04、W4/W7及S01.1；继承生产编译器/目录先行、真实呈现三档与持久化、同候选审查、失败不冒通过、显式默认开放门禁 |
| [docs/design/aiui-smoke-test-spec-2026-10-11.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/design/aiui-smoke-test-spec-2026-10-11.md) | CR-3旧Flutter/Android验收规格；第6节已由ADR0001:108采纳，文件“未实现”是当时状态，不当当前实现事实。Dart测试文件/设备操作形式按新端替换，旧人工确认步骤只在相应模式保留 | 单元09/10/20、D10、M22–M28、W4/W8；继承同SHA真实生产链、自动1–4/7与重启5/6证据分开、真实上游与fixture分开、至少5原始样本/中位数、隐私白名单、恢复不重新播种/不自动执行。保留全部原用例映射，不重跑 |
| [docs/design/aiui-stream-contract.md](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/design/aiui-stream-contract.md) | 已采纳AIUI流合同的旧技术编码/版本依据；宿主身份与动作路由、严格坏行、候选/预览/final区分继续有效。Dart类型映射到M03同源schema；必须明确stream/2与library-2适配，不把历史标题v1当最终生产编码事实 | 单元09/10、M03/D02/D03、W4及公共卡片合同；继承完整end+全树验证、坏行不可丢弃后宣布成功、预览不带执行、迟到/取消不能复活、after_end与真实transport_error分开、旧版本拒绝/显式迁移；当前已登记确定性业务命令仍直Rust，不恢复模型绕路 |

补充依据：AUTH任务引用的 `docs/superpowers/plans/2026-10-08-auth-1b-b-minimal.md` 确实存在；若本轮只补任务入口，可作为AUTH-1b来源链接而非新增独立实施任务。不拓展本次盘点范围。

来源固定前缀：[产品基线目录](https://github.com/mightyoung/Muyon/tree/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs)。添加旧文件页首状态是后续实际文档切换动作，本补丁仅登记，未改变远端旧文件。


## 5 ADR唯一落点与首批链

建议唯一落点：ADR-AUTH-01对应`docs/adr/0006-fullallow-supersedes-endpoint-and-taint-asks.md`，ADR-AUTH-02对应`docs/adr/0007-content-review-contract.md`。在已核产品01e56cc2与文档e014b097中未占用；没有盘点全部在途分支预留。本次只登记建议，实际建立前由唯一集成人复核，不声称已经生效或占号。

AUTH-01应先写已定四档/默认Auto、FullAllow新目的地/taint不加问及Sensitivity用途默认的旧条款替代；legacy完整映射与期限仍留明确出口。AUTH-02写风险建议/可信硬限制/不可用类型及旧链映射，不把建议风险升级为FullAllow硬阻断。未知结果的新用户意图与本机新副本约束归D03执行合同，两个ADR引用它，不能各写一套事实来源。

首批依赖为M01 → A00 → M02 → D01a、D03a、SPIKE-01草案并行协调 → M03冻结。D03a不依赖M03最终生成物，D03完整实现后续依M10–M12。M04合成语义fixture与M05 Dart对照可以在M02后先行，最终编码fixture再依M03对齐。A00必须包含Hub、设备消息/研究任务与Sensitivity，漏归属不能进入M02。

D03a规划2–4人日从原恢复5–9中前移，后续恢复留3–5；重分配后首片52–79、D01–D10净增36–64、W300–575，小计388–718。新增D11自动记忆提取/跨会话检索18–34后，当前D合计54–98，整体406–752人日。均是低置信作者估计，非用户工期承诺、真实测量或正式生产切换全成本；新增能力不无成本塞入原预算。

## 6 文档与工程关闭的区别

DOCS-G0可在两册B01分类合同/本轮默认、B02 Hub映射、13项响应及本追踪表一致后评审关闭，不等待所有产品选项和实验完成。本包本身不宣称该集成门禁已由审查人通过。

受影响真实路径仍分别需要：D01b最终模型/业务wire投影与模式fixture；D03用户新意图可信绑定及回执未知恢复；D11新增生产者默认关闭、来源/策略/墓碑/版本验收；W3/W5 Hub和设备功能完整性；W7连接与秘密平台能力。准确实现SHA、fixture hash、包hash、命令、平台、pass/fail/not-run及非作者审查由实施任务回填。

本轮没有产品代码变更、CI新绿灯、真实Hub/模型发送、真机实验、旧库切换或生产发布。原25例和新增15例保留为待执行清单，本轮另列V131-T01至T12，不冒充52条已通过测试。
