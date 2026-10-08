# Muyon 个人 Agent 平台能力实施计划

> 文档发布说明（2026-10-08）：本计划保持草案／建议基线属性，原内容保留，不修改已采纳 ADR、不派发实施任务。模型线的教师目标仍在后续细化中，相关选择不是最终定案。

日期：2026年10月8日 · 状态：建议基线，待评审及正式任务派发 · 本文不改代码、不修改已采纳ADR、不宣布任务已完成

## 1 目标与顺序

按[整体设计方案](Muyon_AI_Agent与智能交互整体设计方案.md)推进个人Agent与插件共用能力：先核对现状和真实业务评测，再补“项目需求驱动的信息检索与候选对比”，接上动态UI的最小契约与渲染，然后完成“上下文感知文件解析与业务导入”、草稿和返回，最后按实际需要补任务及子会话。

设备选型只是信息检索与候选对比的第一个验收例，不新增专用选型产品，也不把Muyon改成采购软件。科研、询价、原型等插件复用平台语义和交互能力；业务字段与规则由各插件提供。

模型研究与开发并行。规则渲染、真实工具、来源、草稿和恢复不等待训练；C1工具调用可验证共用管线，不能替代用户要求的C4智能UI规划目标。保持Flutter、本地优先、可选远端、现有领域服务和SQLite，不新增微服务。

## 2 已核基线与旧任务映射

本计划只读核对公开仓库 `mightyoung/Muyon`，锁定 `develop` 提交 `dbc19fbe6020dea761539353feecea82f4de654d`。后续派发先重取最新提交，比较是否已有人完成对应切片。

| 现有任务 | 锁定基线可确认的状态 | 新计划如何使用 |
|---|---|---|
| K-1至K-4及ADR-0005 | 模型适配、预算循环、压缩、事件与回执恢复已合入 | 复用；不重建Agent内核、事件表或模型网关 |
| REG-1、REG-2a、REG-2b及ADR-0004 | 契约v2、出站账本、模块宿主与范围解析已合入 | 以REG-3/4继续迁移和补能力 |
| UI-1a | v6设计系统已合入 | 复用组件与token；不等于动态UI已经完成 |
| E-1、R-1、UI-0 | E-1框架已合入；真实模型基线和取证仍有未完成项 | 续原任务，夹具与真实模型分别记录 |
| AUTH-1b | A、B12、B3等已合入；C段和类别策略在途 | 收尾独立推进；`7c1dd63`仅为在途回报，未据此认定已在develop |
| JR-1 | 已合入 | 不再派同一清理任务 |
| 模型优化与蒸馏框架 | `21b3fbc`入库的是提案，文档仍标“提议” | 采用可验证部分，不能把建议替换成已采纳决定 |

**现行参数继续有效。** ADR-0005已有经确认的初值：压缩触发比例0.8；最近2个用户回合且至少6条消息；每张确认卡最多5个调用；摘要上限2000 token。旧路线图的确认次数与首字时延指标仍是现行基线，先对齐测量口径，再讨论变更；本文不静默重置数字。

**授权范围协调。** ADR-0003明确把“Laya专门化”排在第二阶段之外，并非统一禁止所有训练。本轮用户已批准免费资源下模型训练与开发并行，可记录为对应研究任务的窄例外，不重新询问相同授权。由负责人把原话、范围与日期补入决策记录；本文不自行把ADR改为新政策，不顺带提前iOS、常驻节点、全量数据中心或业务整页换壳。

## 3 派发与验证规则

下列 `E-1/01` 等是现有任务下的建议切片引用，不是另一套正式编号；创建任务前查重并由现有负责人归入 `docs/tasks/`。沿用一个任务分支、独立审查、合入后更新索引的工作方式；当前设计和计划先进入独立docs分支。

- 文件路径分为“现有且已查到”“既有ADR规定新增”“具体落点待查”。待查项必须在该切片开工时定位，不能凭本计划伪造当前文件或行号
- 每片先补会失败的回归，验证失败原因，再做最小改动、运行针对性测试和仓库门禁，最后交审；不削弱旧断言来过关
- 外部模型和真实数据测试须使用已允许的配置；普通CI不设置 `MUYON_EVAL_REAL`，不打印密钥，不把夹具结果写成真实模型能力
- 需要AUTH接口的生产副作用在接口核验后接线；只读调查、契约、fixture、UI和数据准备可先行
- 新模型、协议适配和动态界面分别有开关；回滚关闭新路径，保留原页面、业务记录、证据、草稿与回执

优先复核五种容易伤害用户工作的情况：来源冲突、搜索中变更条件、人工编辑后刷新、提交超时但已经成功、返回或重开时插件/schema已经变化。分别由下面对应切片承担测试。

## 4 主线小切片

### E-1/01 现状与真实业务基线

- **依赖与改造**：现在可做；复用E-1/R-1，不再另造评测器。先核AUTH在途提交和既有任务状态，再固定两个平台场景及真实用户操作步骤
- **已验证目标**：`apps/muyon/lib/assistant/agent_eval/agent_eval.dart`、同目录 `agent_task_set.json`；`apps/muyon/test/agent_eval_test.dart`；`docs/tasks/E-1.md`、`R-1.md`
- **交付**：现状覆盖矩阵、失败归因和固定样本。检索例检查条件确认、实际读取、逐项证据；导入例检查用途选择、直接编辑、部分提交、返回恢复
- **验收**：记录运行提交、平台、模型、配置、工具与事实结果；夹具测试验证评分，真实运行单列；覆盖AC-01至30的当前“通过/失败/未测”，不把缺少工具归罪模型
- **回滚**：仅加评测和证据，不改变产品行为；保留旧样本与评分口径

### REG-4a/01 复用询价能力的无行为迁移

- **依赖与改造**：REG-2已合入；沿ADR-0004的REG-4a纯适配，不掺功能或UI重写
- **目标**：现有 `apps/muyon/lib/app/inquiry_plugin.dart`、`platform/business_tools.dart`、`platform/inquiry_write_tools.dart`；ADR已规定新增 `apps/muyon/lib/app/adapters/inquiry_module.dart`，当前树未见该文件
- **交付**：已有对象、本体、读写工具经BusinessModuleV2统一注册；旧入口保留薄委托，其他插件后续沿REG-3迁移
- **验收**：旧工具ID、顺序、模式和行为不变，范围摘要差分一致；`north_star_inquiry_test.dart`、`inquiry_*`与模块契约测试保持通过
- **回滚**：适配器开关退回原激活路径，不做破坏性迁移

### REG-4c/01 项目需求驱动的信息检索与候选对比

- **依赖与改造**：E-1/01和REG-4a。建议先拆只读检索，但旧ADR把整体REG-4c放在REG-4b之后；正式派发须明确窄切片的前置差异。未完成衔接就遵守原依赖，契约、fixture和UI仍可并行
- **目标**：已查到 `packages/supplier_core/lib/src/assistant_procurement.dart`、`assistant_web_tools.dart`、`assistant_evidence.dart`、`spec_constraint.dart`、`spec_match.dart`；宿主 `app/inquiry_web_authority.dart`。各文件具体接线需开工时阅读确认
- **交付**：先确认条件版本；持续搜索并区分线索、去重后成功读取、失败；产出带来源和unknown/conflict的候选。设备为首例，平台输出避免写死设备字段
- **验收**：AC-01至10；更换条件先确认，旧在途结果归旧版本；来源冲突不拼型号；不能读PDF/动态页时诚实标缺；技术可用但非关键字段缺失仍交付
- **回滚**：关闭新工作流，保留来源与候选；不撤销已经确认并写入的业务记录，不删除旧工具

### UI-3/01 加入最小语义契约适配

- **依赖与改造**：E-1/01与现有REG契约；可与检索接线并行。复用ModuleOntology、ToolSpec.resultSchema、ObjectRef、ArtifactRef和ResultRenderers
- **目标**：现有 `packages/muyon_module_api/lib/src/{ontology,tool_registrar,references,optional_capabilities}.dart`。Envelope、Intent、UIPlan适配文件的具体落点待查，先确认是否已有等价结构再新增
- **交付**：两类场景的事实快照、必显信息、可用动作、版本与最小UIPlan；数据画像由代码计算，模型只组织表达
- **验收**：字段值、单位、来源和unknown/conflict不丢；失效引用、未知动作、旧revision均拒绝；schema合法不能替代业务正确
- **回滚**：停用新投影，旧ToolCallResult及ResultRenderers继续工作

### UI-4/01 确定性动态工作区

- **依赖与改造**：UI-3/01和已合入UI-1a；使用当前Shell做局部工作区，不等完整换壳或小模型
- **目标**：现有 `packages/muyon_ui/lib/src/{catalog,confirmation,primitives}.dart`、`apps/muyon/lib/screens/{assistant_page,execution_panel,draft_view}.dart`；新增渲染器文件名待定位。注意现有 `catalog.dart`是组件目录，不能假定已有生成式Catalog
- **交付**：条件选择/编辑、候选比较、来源折叠三个最小组合；本地展开排序不走模型；业务Action仍进统一执行链
- **验收**：AC-21，窄/宽屏及大字号可操作；半条流不执行动作；乱序/重复Patch不重复生效；生成失败退回确定性布局
- **回滚**：关闭动态surface，原消息视图和业务页面仍可用

### REG-4b/01 与 REG-3/01 上下文感知文件解析与业务导入

- **依赖与改造**：REG-4a、UI-3/01；按插件分开小批次。优先把既有plan/apply、ImportCapable能力接通，不重建导入服务
- **目标**：已查到 `packages/muyon_module_api/lib/src/optional_capabilities.dart` 的 `prepareImport`、`commitImport`、`receipt`；宿主 `services/documents/document_parser.dart`、`app/accepted_research_imports.dart`；领域具体plan/apply实现定位后列进正式任务，勿仅凭ADR中的方法名认定全部已接
- **交付**：先推荐相关插件再选功能，混合用途分组、字段与单位来源、可编辑预览、确定重复跳过和不确定冲突对照。OCR/格式解析复用现有能力，不顺带承诺原生三端OCR改造
- **验收**：AC-11至18；五类输入的可用/部分可用/不可用准确；用户确认后只提交有效集合；超时先查回执，补齐只续未完成记录
- **回滚**：回退插件原导入页；新草稿和已成功回执保留，不重放已成功写入

### UI-3/02 人工编辑持久化与版本合并

- **依赖与改造**：导入预览契约和UI-4/01；新增必要持久草稿，复用现有数据层
- **目标**：现有 `platform/foundation_repository.dart`、`screens/draft_view.dart`；持久业务草稿表/迁移及字段合并文件待定位。**不得把 `assistant/agent_drafts.dart` 的内存流式回复草稿改成业务草稿库**
- **交付**：提取值与人工覆盖层分离；保存步骤、归属、记录集合和确认版本；模型重试仅更新未冲突字段
- **验收**：AC-15至18；直接修改后刷新、重试、切页、重开均保留；schema或业务版本变化给差异；确认失效不静默提交
- **回滚**：关闭新编辑面；草稿可只读查看/继续原预览，不降级覆盖人工值

### UI-2/01 返回导航与文件预览

- **依赖与改造**：UI-3/02；现壳增量适配，不等同提前UI-8/9整页换壳
- **目标**：已查到 `app/app_shell.dart`、`platform/object_pages.dart`、`screens/chat/chat_thread_page.dart`；文件预览的具体入口和返回锚点文件待查
- **交付**：真实对象路由、逐层返回锚点、MD/HTML/PDF渲染预览；插件停用或对象失效可回原对话
- **验收**：AC-20/22，返回后聊天位置、草稿和任务保留；PDF无伪源码；来源文件变更不假称原定位；引用与发送/已读/执行状态分开
- **回滚**：保留原路由入口；锚点失效给显式退路，不清空会话

### UI-4/02 任务现场与一层子会话

- **依赖与改造**：前述两闭环可完成后，依据实际失败补缺口。复用K-4 TaskRecords与AgentResume，不创建平行任务内核
- **目标**：已查到 `platform/task_records.dart`、`assistant/agent_resume.dart`、`screens/execution_panel.dart`、`screens/chat/chat_models.dart`；子会话存储与浮层实现待定位
- **交付**：离页执行/真实暂停、独立任务入口、一层子会话、最新版本概要引用；业务成功回执在恢复时不重放
- **验收**：AC-23至29；关闭浮层不取消；未引用子成果不改主任务；查询时核最新版本；进程终止与锁屏分别测；事件只存允许的ID/摘要，不把正文塞入K-4事件表
- **回滚**：关闭子会话或新列表呈现，已有主任务和事件继续可读；平台无法后台时显示暂停

### E-1/02 与 R-1 端到端复验

- **依赖与改造**：随每个能力切片运行，最后覆盖完整闭环；复用E-1和现有真机流程
- **验收**：原30条AC按样本、平台、提交与配置记录；追加来源冲突、旧确认、重复提交、恢复及降级；不以某次全绿fixture宣称三端实际通过
- **门禁**：执行者在核对现行脚本后运行 `flutter analyze`、切片测试、宿主全量、`bash scripts/ci.sh`。已知golden环境漂移与真实回归分别报告，不能删断言或笼统标全绿
- **回滚**：发现事实改写、无确认副作用、重复写入或人工编辑覆盖，阻止启用对应新路径；不回滚用户已经正确保存的数据

## 5 并行模型线

| 建议切片映射 | 现在做什么 | 接入条件与回退 |
|---|---|---|
| E-1/03 对应框架F1/F2 | 导出真实工具/schema与目录快照；固定样本做“空/真实schema × 原/修正提示”2×2对照；保持其它参数一致 | 69次弃权是历史统计，schema/提示的因果尚未通过消融证明；不得先改标签让成绩变好 |
| UI-4/C4-01 智能UI样本与Bench | 与UI-3/01并行定义Envelope/Intent/Catalog样本、多个合格布局、交互与恢复判据；按场景族分train/dev/calibration/test | 目录版本锁定后小批生成与用户复核；真实业务数据不上传；C1可复用工具，但不成为C4必须先完成的产品门槛 |
| UI-4/C4-02 端侧可行性与已授权训练 | 先小样本导出数值对照与目标端冒烟，再扩大合成数据训练；Laya仅有限Selector候选，生成式Planner另比现成模型 | 免费Kaggle配额实际核对，无新增付费；接口/许可/导出不成立就保留规则或强模型，AUTH与主线照常推进 |

优化阶梯是契约→提示→约束→现成模型→必要时训练，并不撤回用户已批准的并行研究。教师优先按用户选择参与现有ChatGPT/Claude对话生成与导出；每类来源记录适用训练/发布用途，未明样本隔离，不能将订阅、手工复制或“非商业”当成普遍许可。训练、代码、数据、权重发布分别核验。

模型交接包包含协议/目录/模型/数据版本、许可记录、分割清单、校准、权重校验值、导出配置、设备结果及fallback开关；模型接入通过ADR-0005现有适配和闸门，不增加第二个网关。新方案里的A2UI/GenUI仍是候选，先做适配实验，不因框架提案出现它们就锁为生产依赖。

## 6 第一批实际安排与停止点

**先派的建议**：E-1/01续现状和真实基线；REG-4a/01纯适配；UI-3/01用fixture形成最小契约；模型线目录快照与C4样本准备。AUTH收尾继续，不扩大范围。

**随后**：REG-4c/01检索来源闭环与UI-4/01联调；再接文件导入、持久编辑和返回；最后按证据补任务与子会话。REG-3科研/原型迁移，以及T-3、S-1、REG-5按原路线独立推进，不因本计划未展开而取消；复用其范围和能力覆盖约束，用户案例不成为其他插件的硬编码前提。

**本稿完成条件**：负责人确认任务归属、差异与依赖，补齐每片的真实文件清单、测试名和动作接口，再进入正式任务分支。本文的“待查”是派发前定位工作，不授权任意选目录实现。未通过模型门槛不停止平台闭环；涉及额外付费、新外发范围或发布权限时停在该动作，不阻断独立工作。

## 7 已核仓库依据

以下链接固定到本计划基线，避免把移动分支上的新内容误作当时事实：

- [任务索引](https://github.com/mightyoung/Muyon/blob/dbc19fbe6020dea761539353feecea82f4de654d/docs/tasks/README.md)
- [现行第二至第四阶段路线图](https://github.com/mightyoung/Muyon/blob/dbc19fbe6020dea761539353feecea82f4de654d/docs/superpowers/plans/2026-10-07-roadmap-phase2-4.md)
- [ADR-0003范围](https://github.com/mightyoung/Muyon/blob/dbc19fbe6020dea761539353feecea82f4de654d/docs/adr/0003-phase2-scope.md)
- [ADR-0004模块契约及REG-3/4拆分](https://github.com/mightyoung/Muyon/blob/dbc19fbe6020dea761539353feecea82f4de654d/docs/adr/0004-module-contract-v2.md)
- [ADR-0005模型适配与Agent循环](https://github.com/mightyoung/Muyon/blob/dbc19fbe6020dea761539353feecea82f4de654d/docs/adr/0005-model-adapter-and-agent-loop.md)
- [E-1任务定义](https://github.com/mightyoung/Muyon/blob/dbc19fbe6020dea761539353feecea82f4de654d/docs/tasks/E-1.md)与[R-1取证](https://github.com/mightyoung/Muyon/blob/dbc19fbe6020dea761539353feecea82f4de654d/docs/tasks/R-1.md)
- [Leader B批次复核](https://github.com/mightyoung/Muyon/blob/dbc19fbe6020dea761539353feecea82f4de654d/docs/reviews/2026-10-08-leader-b-batch-review.md)
- [模型框架提案](https://github.com/mightyoung/Muyon/blob/dbc19fbe6020dea761539353feecea82f4de654d/docs/superpowers/specs/2026-10-08-model-distillation-framework.md)，保持提案属性；本计划采用最新用户并行研究方向，不整包追认其排期和许可结论
