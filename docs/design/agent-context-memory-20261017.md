# Agent 上下文与可审计补充记忆增量设计

版本：CTX-MEMORY-DESIGN-1，2026-10-17（北京时间）。
状态：用户已批准落地借鉴设计；本文是待集成的目标合同，未实现、未运行新增验收。文档采纳不表示模型实验通过。
代码核查基线：0ab2c4f667681b9aacb017f8cd2eea6f576cf78e。唯一合入执行者：LeaderB。
范围：补充 v1.3.2 第一册上下文压缩、记忆、插件与恢复章节；页面以[页面增量](agent-context-memory-pages-20261017.md)为准；开发安排见[任务与验收](../tasks/CTX-MEMORY-20261017.md)。
v1.3.2 两册、PNG、SHA256SUMS 作为已审归档不修改。其余既定范围、默认 Auto、FullAllow 语义、Rust 内核、Kotlin/Compose Android、Electron 桌面及 Android 独立进程适配要求保持不变。本补充只替代“压缩只需四字段摘要”的新架构目标理解，不撤销历史实现记录。
归档入口：[第一册](redesign-v1.3.2-20261014/Muyon-Redesign-Plan-v1.3.2-2026-10-14.md)、[第二册](redesign-v1.3.2-20261014/Muyon-Page-Design-Handbook-v1.3.2-2026-10-14.md)。

## 1. 依据与证据上限

REMORY v2（2026-10-11）通过冻结 actor、训练连续记忆补充摘要，并保留原始记录检索。本文采用“主线摘要、补充决策信息、精确来源查询”的分工，**可审计文本对象是 Muyon 的工程推导，不等于 REMORY 软 token，不继承其效果数字**。
原始资料：[论文](https://arxiv.org/html/2610.11287v2)、[官方仓库](https://github.com/fudan-generative-vision/Remory)、[部署说明](https://github.com/fudan-generative-vision/Remory/blob/main/docs/deployment.md)、[训练说明](https://github.com/fudan-generative-vision/Remory/blob/main/training/README.md)。核查日期为 2026-10-17；仓库 main 是可变来源，实际实验前必须固定完整 commit、权重 revision 和运行配方。
公开 GLM 1.24B encoder 不读取摘要，本地评测 128K；论文 1.502B 与摘要条件机制/1M 的对应关系仍需作者澄清。公开训练说明的 CPU 检查不等于完整 GPU 训练复现。本轮未复现、未安装、未下载权重，不宣称神经记忆已准入。
近邻依据：[Anthropic 上下文工程](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)的结构化笔记和按需检索。该材料不证明本设计已有效。

## 2. 当前源码与迁移边界

| 当前事实 | 目标动作 | 不得推断 |
|---|---|---|
| [Rust agent State/drive](https://github.com/mightyoung/Muyon/blob/0ab2c4f667681b9aacb017f8cd2eea6f576cf78e/experiments/redesign/core-agent-lab/core/src/agent.rs#L215-L231)保存完整历史，遇 unresolved/evidence_hold 或预算限制停下 | 在受控请求投影前增加压缩候选与发布接口 | 实验 lab 已是生产记忆系统；压缩能解除 unknown |
| [原生消息类型](https://github.com/mightyoung/Muyon/blob/0ab2c4f667681b9aacb017f8cd2eea6f576cf78e/experiments/redesign/core-agent-lab/core/src/model.rs#L72-L79)区分调用与结果 | 从结构化事实提取，不从摘要重造调用 ID | 摘要可充当执行账本 |
| [宿主复核](https://github.com/mightyoung/Muyon/blob/0ab2c4f667681b9aacb017f8cd2eea6f576cf78e/experiments/redesign/rust-agent-host-lab/core/src/lib.rs#L245-L279)检查请求权限/投影/载荷 | 补充记忆走同一发送前复核链 | 独立拼 prompt 可绕过投影 |
| [旧压缩器](https://github.com/mightyoung/Muyon/blob/0ab2c4f667681b9aacb017f8cd2eea6f576cf78e/apps/muyon/lib/assistant/context_compactor.dart#L272-L348)清旧工具结果，再生成[四字段摘要](https://github.com/mightyoung/Muyon/blob/0ab2c4f667681b9aacb017f8cd2eea6f576cf78e/apps/muyon/lib/assistant/context_compactor.dart#L401-L440) | 提取测试样本与行为对照，Rust 重写 | 继续新增 Dart 实现；Rust 已迁移完成 |
| [v1.3.2 来源与版本合同](https://github.com/mightyoung/Muyon/blob/0ab2c4f667681b9aacb017f8cd2eea6f576cf78e/docs/design/redesign-v1.3.2-20261014/Muyon-Redesign-Plan-v1.3.2-2026-10-14.md#L698-L710)为目标态 | 复用字段和版本域，逐项实现 | task.db 的存在已证明跨对象原子提交 |

所有新能力落于公共内核；业务插件只提供声明与查询适配。

## 3. 分层与权威

1. 事实层：原始消息、工具调用、回执、用户决定及来源版本。保存受既有留存、用途及遗忘规则约束，不承诺无限保留。
2. 请求视图层：主线摘要、仍有效补充对象、近期原文、必要来源摘录。可重算，可降级；不得反向改写事实层。
3. 可选神经后端：默认不启用、后置研究。无权改变执行与授权判据。

原始事件/回执决定动作是否执行及结果；用户决定决定需求的修订；当前宿主 policy 决定权限。模型推断只作候选，不产生以上任何权威。
已有 unresolved/evidence_hold 在压缩前后保持。重要上下文装不进预算时暂停，不能把它删掉后继续。关闭记忆的具体读写路径沿既有 MemoryControlPolicy；不能把“任务状态”改名后绕过禁用范围。

## 4. 最小对象合同

三个对象共享：id、schema_version、conversation_ref、task_ref、scope_ref、source_refs、source_revision/digest、observed_at、record_revision、derivation_kind、evidence_state、policy_refs、失效原因。字段名为待冻结 schema 草案；不得与已有稳定标识重复铸造。
source_refs 指向现有受控对象/回执，不接受模型自由路径或 URL 作为已授权读取凭据。时间只辅助展示，不代替版本比较。模型推断与确定性提取必须可区分。

### 4.1 FailureObservation

记录 invocation_ref、tool_id、tool_contract_version、参数规范化摘要、失败类别、发生条件、证据引用、复查条件和适用范围。
- 仅表达“在这些条件下观察到失败”；版本、参数、权限或环境变化后允许重新评估。
- timeout/取消/断连后的外部效果不明记录为 outcome_unknown 引用，不得写成 failed-no-effect。
- 不凭模型描述建立永久禁重试规则；重试/另建意图继续遵守已有业务合同。
- 相同参数摘要并不代表相同业务意图；不可据此替代 action_id/intent_ref 的幂等处理。

### 4.2 DecisionSupersession

记录旧/新决定引用、用户原始依据、适用对象与范围、生效版本及替代边界。
- 可表示部分替代；其他范围继续保留旧约束。
- 只有可验证的真实决定来源能更新有效视图；模型建议不得自行使旧决定失效。
- 互相矛盾而无法确定范围时保留 conflict，不按时间粗暴全覆盖。
- 决定记录不是 ModeGrant，不能签发、扩大或恢复授权。

### 4.3 EvidenceLink

连接主张与源对象/消息/调用/回执，保留固定 revision/digest 和 verified/unknown/conflict。
- verified 需标明验证方法与范围，不因引用存在就判真。
- 当前账本才能把 outcome_unknown 转为已知；补充对象只展示账本的受控投影。
- 来源变更、删除、撤权或不可读时明确失效/缺口，不保留假装有效的断链。
- 原文保留仅在合法留存范围内；不存在时保持未知，不重建假来源。

## 5. 构建、检索与预算

先从事件和已核回执确定性提取，再由模型提出补充解释；后者需 schema、来源、范围及版本校验后才进入候选视图。外部内容和模型输出的 taint 与 Sensitivity 不能因摘要、重写或存入记忆而洗白。
优先保留当前用户要求、未决结果/阻塞引用、有效决定与调用配对；再按当前任务相关性装载补充对象。排序与预算规则版本化、可解释，具体 token 上限由离线对照确定，不硬写论文4096为文本预算。
保留来源目录和精确查询接口。预设三类对象无法覆盖全部未来信息；允许模型按需要查回原始记录，每次读取重查当前 scope、权限、用途与墓碑。
摘要生成本身的出站请求也必须经过内容投影、凭据排除与当前授权，不能只审最终答案。
源字段 credential 不进入请求；其余分类沿当前设计规则。新摘要或补充对象不自动提升信任。
原文/残差/检索的总 token 均计预算；重复输出率须区分合理轮询、状态已变和真正无效重复。

## 6. 事务式压缩与恢复

复用 conversation_ref、turn_refs、source_cursor_range、input_digest、context_generation、authority_revision、memory_policy_refs[]、forgetting_set_digest 和 CompactionReceipt。每个 policy_scope_ref 的 policy_generation 独立比较；不引入跨域全局 epoch。

流程：
1. 固定待压缩范围、源 digest、预期 context_generation、完整顺序域内的游标和策略引用。
2. 候选生成摘要、补充对象及覆盖清单。完整 call/result 保留成对关联，未发送用户输入、在途调用和未决事实不能被压缩成“已经完成”。
3. 重验来源版本、完整性、当前权限、记忆策略、遗忘集合与有效决定。
4. CAS 检查预期版本；摘要、补充对象、覆盖范围、压缩回执及当前 checkpoint 指针原子发布。崩溃只能观察完整旧版或完整新版。
5. 请求构建后再次经过现有 review_payload 和发送前版本检查。压缩成功不等于业务任务成功。

并发新消息、撤权、遗忘或策略变化使旧候选失效并记录原因；重建次数有界，不能在争用中无限循环。不同 store_id/stream_id 的序号不可比较大小。
迟到真实回执始终进入对应事实账本；旧 generation 只能阻止陈旧请求视图发布，不能删除效果证据。
压缩失败保留旧的仍有效上下文；若旧内容已撤权/删除则不能回退使用它。预算不能满足时暂停并说明，不静默截断。
压缩记录仅保存必要审计元数据；删除内容不能通过审计日志、旧摘要、导出或备份复活。恢复备份沿既有墓碑优先合同。

## 7. 插件注册扩展

新增可选 ContextContribution 声明（待 schema 冻结），至少定义：
- object_type/schema_version、稳定引用与版本提取规则；
- 可用于摘要/证据索引的字段，以及宿主认可的分类与用途约束；
- 错误分类和复查条件、结果未知的查询能力；
- 精确读取/核对的已有只读工具引用；
- 任务内保留条件及失效通知来源。

声明必须经过宿主注册校验；插件不能降低 Sensitivity、覆盖权限策略、把可写工具伪装为只读查询或自行声明 verified。
缺少扩展声明时退化到通用调用/回执引用，不使插件不可注册，也不自动放行未分类内容。
使用可信内置插件范围，保留 Android 子进程适配；本补充不授权任意第三方可执行插件。
科研、询价和一个合成第三域 fixture 都必须通过，以证明未把两类业务硬编码到公共组件。

## 8. 可选 REMORY 后端的准入边界

默认关闭，不是当前核心 Agent 或 Android 适配的前置。
绑定 actor revision、tokenizer revision、encoder/checkpoint revision、prefix/tool schema digest、scope、source lineage 和策略版本；软向量不能迁到不同模型。
普通远端文本 API 使用文本/检索路径；本次不接入 SGLang、不做训练、下载或付费。
软记忆包含被遗忘/撤权来源时，立即停止使用相应 checkpoint；从剩余获准来源重建。无法定位影响范围则整体失效。旧缓存、数据库及备份同步受遗忘合同约束，不能只隐藏界面。
跨用户/项目/分支隔离；模型升级回退到有效文本视图，不能复用旧 handle 假装兼容。以作者公开实现为研究起点，不宣称已有部署硬件或多模态兼容验收。

## 9. 设计完成与工程完成的区别

本文件定义设计目标。新增 fixture、Rust 实现、跨端接线、真实模型评测均未执行。
实现不得越过原有独立审查、CI、数据迁移和权限门禁。LeaderB 按依赖安排，不因本补充自动取消原队列或推迟当前 Android Service 修复。
验收与停止条件以[CTX-MEMORY 任务](../tasks/CTX-MEMORY-20261017.md)为准。
