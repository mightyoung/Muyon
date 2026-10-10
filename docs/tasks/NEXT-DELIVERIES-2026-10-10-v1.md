# 下一批交付执行队列 v1 — 2026-10-10

状态采样：2026-10-10T05:29Z。fetch 后固定 develop `7773b7d96bc99f173b57a723d61526fba0df49ff`；本分支 `task/plan-next-deliveries` 只交文档，尚待父任务审查。下表的“在途”不等于完成；未分派行的 owner 是共享文件协调角色，不是新开发授权。开工必须重新 fetch、固定依赖 SHA、确认 owner 和开放 PR，禁止重复开发。唯一 integrator 顺序合入，本文不合 develop/main、不部署、不改权限或凭据。

来源简称：[H](HANDOVER-LEADER.md) A–D（历史）；[S](CURRENT-STATUS-2026-10-10-v1.md)（固定8deb）；[I](INTEGRATION-2026-10-09.md)最新轮次；[D](../design/ai-native-ui-redesign-2026-10-09.md)；[C](AIUI-NEXT-BATCH-CONTRACTS.md)；[R](../superpowers/plans/2026-10-07-roadmap-phase2-4.md)。用户来源 U＝父线程 `01a0f1f6-9060-7550-a2f0-c9bdd66e6019` 本次委派及“新改动记得更新总体设计”补充，属于协调记录，未伪造仓库提交。

## 当前版本与历史冲突

| 旧记录 | 当前依据与准确结论 |
|---|---|
| H A–C：AIUI-1/2、GROK-7待审，REG-3未写；UI-2a/UI-4c/REG-4b待整合 | S/I/README已记录基础片合入，源祖先核对通过；旧UI任务不重复派发。REG-3a有界已合，剩余能力单列 |
| S：PR16 manual hold P1未关闭，PR20在途 | develop包含PR20源 `609e724874e5112152b06dfa7856f877cd2e413a`，合入 `5e7c3036f10f928665fea5f162ff3ad8052a4057`；I最新轮裁定P1/P2修复。专项剩余验证不改成已验证 |
| S：PR19未合、PR21 scaffold RED；F5b尚无typed机制 | PR19已合且有leader技术采纳记录；PR26源 `f29819b24187654642a36685592a4c02abfac854`已合，只落实stream/2协商、显式v1 collection拒绝与防误用门槛；完整typed机制仍在PR28，不等于collection/33组件/运行闭环。PR21/28/30仍open，不能写成develop能力 |
| S：Mac未交付，lint/coverage仅初始框架 | PR25源 `a44b1f0f438772c81e90f8def72c817a147d2465`已合；仅3例历史失败复现且哈希一致，全量数量和根因未知。lint/coverage已有下列交付，组合尚待收口 |
| H D：读参数恢复未补审、CI不跑doctor | AGENT-DISPATCH-VERIFY-1与JR-1已合；不能重复修。设备/Mac/模型仍须各自证据 |
| README：REG-4c“排队” | U明确另派云端专有任务，记“已启动（父任务协调），交付待核”，不另派、不写已完成 |

## 开放 PR 固定快照（正文报告不替代本片实测）

| PR / head | 当时状态与下游限制 |
|---|---|
| [18](https://github.com/mightyoung/Muyon/pull/18) `758fe718d66a1d4591d73e534c83b19332850e4b` | F3b真实候选测试已交，qty3/4 Widget仍有效RED；禁止整包合入 |
| [21](https://github.com/mightyoung/Muyon/pull/21) `97a2e8263a5f38b5659b4123b78fadea90eb35f9` | F5c不可变接口独立GREEN；H2/组合/运行接线待核 |
| [28](https://github.com/mightyoung/Muyon/pull/28) `505d0e806ac77b8295197de082351dd5ba68c26e` | typed片GREEN；collection仍RED；33 renderer与最终组合未完成 |
| [30](https://github.com/mightyoung/Muyon/pull/30) `ac0a0efa921236a765d7e9c56f3e2bf8a22acd0f` | 独立publication coordinator报告GREEN；依赖PR21；H1/H2b及跨session同步commit待owner，未启生产 |
| [22](https://github.com/mightyoung/Muyon/pull/22) `8d7af79ae90ddb0b4d9ab5fe942a2d0f93c50568` | lint基线和局部修复，保护文件诊断交owner |
| [29](https://github.com/mightyoung/Muyon/pull/29) `a77aec123dc986eb0c9f5e7a244d41c2729c84d4` | supplier 9诊断消除，配置组合仍有其他owner诊断，不称全绿 |
| [23](https://github.com/mightyoung/Muyon/pull/23) `d28c07fdeb9453dc7166e7d10162e11a96af9994` | 已测baseline与门禁；head在本片两次查询间从db9cde推进，最新head重新审查；集成分母漂移须审定重测，不能静默降基线 |
| [4](https://github.com/mightyoung/Muyon/pull/4) `503fd57f94dea11f2854af8d5e4923ce1b34bd1b` | 历史设计PR保持open；按S保存独有内容后由父任务裁定，不恢复五导航/UI-0 |

## 第二阶段执行顺序与文件 owner

共同验收 G＝独立审查＋固定源/组合门禁＋逐条实际行为与拒绝路径；工具效应只认真实回执，模型/设备/golden分别记。共享文件交唯一owner顺序应用补丁，不能以派发、接口采纳或纯测试GREEN替代G。阶段顺序是允许的偏序，独立泳道可并行，遇共享owner则串行。

| ID | 可审交付 | 前置/执行顺序 | 共享文件 owner | 验收 | 状态 / 来源 |
|---|---|---|---|---|---|
| QUALITY-LINT | 推荐配置、各owner诊断修复、完整组合 | PR22→API/UI/supplier owner修复→唯一整合 | lint owner配置/deps；F5b持有API/UI核心；supplier owner五文件 | 零diagnostics，无ignore/exclude/降规则，八包G | 在途 PR22/29、U、质量修复计划 |
| QUALITY-COVERAGE | 固定集成SHA测量与审核基线 | 随当前产品树重测；最终lint/AIUI组合变动再核分母 | coverage owner：ci.sh、scripts/coverage及门禁测试 | 八套报告；未知分母明确；身份漂移/退化必须失败 | 在途 PR23；禁止编造百分比 |
| QUALITY-GOLDEN-NEXT | 原基线机器指纹/受控文字探针；必要时修复与全量 | PR25三例诊断→定位原因→父任务批准具体修复→全量 | 本机Mac owner证据；renderer仍F5b | 不改golden/skip/容差换绿，固定环境及完整失败集合 | 父任务已启动诊断；后续待排，QUALITY-MACOS-GOLDEN |
| HARNESS-HOLD-VERIFY | rollback、acknowledged queued崩溃窗口、有效grant专项 | PR20已合之后，无重复P1实现 | 原harness owner agent_resume/相关测试 | 故障屏障/DB重开/实际handler计数，G | 待排剩余验证，I |
| LAN-VERIFY | 历史400定位及真实负载/重开回归 | PR17已合；避免与supplier lint抢文件 | LAN owner lan.dart/diagnostic/安全可靠性测试 | 合法200、deadline/停止、持久化/回放真实行为；未知根因诚实 | 修复片已合，剩余待排，LAN任务/I |
| AIUI-F5b | typed/collection、33组件与codec/renderer | 已合PR26协商→PR28 typed/collection GREEN→33组件消费 | F5b：plan/snapshot/validation/state/stream/workspace、surface/catalog/inputs/layout、ui_contract | 33项正式validator→renderer；旧版本拒绝/typed恢复/稳定行项；G | 已启动，PR28/U/C |
| AIUI-F5c | 重算接口、发布协调器、同session同步接线 | PR21→PR30→F5b owner H1/H2/H2b→共同组合 | F5c recomputation/publication新增文件；F5b持有state/surface/export | 不仅自身bundle：S/I/P及session一致、epoch/token/旧callback/pending/取消；G | 已启动，PR21/30/U；禁止双版本源 |
| AIUI-F3b | 本地编辑→全部展示computed真重算 | 消费固定PR21/30和F5b admission/rebase | F3b宿主ui_recompute_adapter及PR18测试；不写共享core | 同mounted controller qty3/4→30/40；extracted2/current3、adopt、invalid、旧callback、业务零写入；G | 已启动，PR18/U，Widget RED未闭 |
| AIUI-F4c | 新壳/新目录恢复、导航返回与CAS | F5b/c＋F3b接口就绪→最终组合 | F4 owner platform_shell/nav及既有return/store测试；codec归F5b | 手机/桌面、200%字号、焦点滚动、CAS、pending receipt、撤权/插件失效；G | 已启动（U），当前无独立开放PR可作完成证据 |
| REG-4c | 询价通用写工具、隐藏内置Folio助手 | REG-4b已合，无需等待重派旧UI | 云端专有REG owner：inquiry adapter/工具/本体/覆盖；不写AIUI core | 现有校验/版本/引用删除保护、审批/回执/变异，G | 已启动（U），交付head待核；REG-4c任务 |
| REG-3b | ExchangeCapable/searchSources搬迁 | REG-3a已合→接口边界任务书→独立实现 | REG owner research/prototype交换检索；共享module_api接口由契约owner | 旧交换/导入恢复不变，范围/撤销/来源证明；不补设备收发，G | 待排；REG-3a §52及复审 |
| REG-3-REST | 剩余科研具名写入、本体、Q10本机导出门面 | REG-3b可独立分片；先冻结领域校验/版本 | REG科研owner；不照搬inquiry通用CRUD | 约20具名能力逐项覆盖/明确不开放；仅报告/主张草稿本机导出，G | 待排；H C1、GROK-6、ADR-0004 |
| T-3-NEXT | 安全生产登记→有界仓储分页→正文/提议各片 | metadata机制已合；先明确宿主global身份与零业务恢复副作用，再登记；正文/提议另审 | T3 owner platform_tools/registry；仓储公共接口由各owner，不读raw SQL | metadata零写入；正文范围/敏感度/撤销；提议不自动接纳；真实扫描预算，G | 待排；T3两份任务/复审，生产仍OFF |
| REG-5 | testing套件、示例模块、脚手架、覆盖CI | REG-3b/REST＋REG-4c合同稳定→全三模块组合 | 契约owner module_api/testing与CI；coverage owner协调脚本 | 新模块只模块包＋一行登记，宿主零改动；源码枚举完整覆盖，不混作LCOV；G | 待排；ADR-0004/R/REG-3a |
| S-1-REMAINDER | 范围模型缺口盘点与最小收口 | 已有REG-2/AUTH范围单点→REG3/4/T3新路径复核 | AUTH/registry owner | 不重造范围层；撤权/跨对象/版本变化拒绝、G | 待核任务书；R/ADR-0004，已有实现不重复 |
| AIUI-8 | 可视化三档、权限入口、数据去向 | F4a/b已合；实现排在F4c共享外壳交接后 | 设置owner权限页；AUTH gate归授权owner | 只读/普通问答0确认，授权仅用户宿主给出；外部内容禁放行；三档功能可达、G | 待排；D §8/ADR-0002 |
| AIUI-9 | 询价先做本体业务卡 | F5b/c→REG-4c→AIUI-8权限入口协同 | 业务卡owner；目录/renderer归F5b | 本体唯一结构，suggested值非已写入、稳定对象/版本/真实回执，G | 待排；D §4.4/§8 |
| AIUI-6 | 比价、预算、导入审阅完整询价场景 | F3b/F4c/F5闭环＋REG-4c；写卡复用AIUI-9 | 询价场景owner，supplier规则归领域owner | 真业务mapping与公式、导入预览→审批→回执；完整North Star，G | 待排；D §8 |
| AIUI-7 | 引用/阅读工作区/结果对比 | F4c/F5＋GROK-7；开放写入须REG-3-REST | 科研场景owner；不写通用core | 首批目的/来源定位、科研公式、返回恢复；未开放能力禁用，G | 待排；D/GROK-7 |
| UX-PREDICT-1 | 输入预测胶囊设计包→获审实现 | 本文任务书审查→assistant输入owner窗口；模型接入需预算/隐私决定 | assistant输入owner；planning/core只交补丁 | 仅填入不发送，普通问答不确认，IME/陈旧结果/取消拒绝 | 需求已确认、设计待审；[任务书](UX-PREDICT-1.md)、U |
| UX-VIDEO-1 | 对话视频设计包→获审实现 | 本文任务书审查→媒体来源/依赖ADR提案关口 | 对话owner＋文件/媒体owner；目录扩展由F5b | 会话播放/全屏/下载；权限/重复取消/跨端/模型边界矩阵 | 需求已确认、设计待审；[任务书](UX-VIDEO-1.md)、U |
| MASCOT-ASSET | 统一几何2.5D或真3D资产选型→适配 | 用户资产选择→授权/来源/技术预算评审→跨端适配 | 资产owner；输入/对话外壳归UI owner | 二维双脸混合方案失败；需统一轮廓、表情/姿态、透明/主题/减少动效 | 资产待选择，未完成；U，不能自定路线或提前启实现 |
| PERF/E-1 | 固定版本首字/合法率/审批/成本测量 | UI/运行组合稳定，已有E1分支交付另核 | 评测owner；业务模型仅获准本机执行者 | 本机<1.5s/远端<3s的实测；只读审批中位0/写1；失败也记 | 待测量；ADR-0003/E-1/R-1 |
| R-1-FINAL | Android＋新壳真实模型/原生/golden/读屏 | 云流程先验收修复→AIUI6/7/8/9→集中末次 | 本机engineer，仅更新自己证据；账本归leader | 固定已审develop，全部证据类别/失败/skip明确 | Android及末次待排；R-1/R-1-AI-UI-final，UI-0已取消 |
| C4/MODEL | 指南接入复核、Selector/Planner/训练评估 | 稳定目录/协议后，独立于主线；C4稿不是生产接入 | 模型/指南owner | 固定train/dev与成本/失败报告，双模型方案不作默认定案 | 旁线待核，不阻塞上述主线；C4/R |
| PR4-ARCHIVE | 独有内容核对后关闭建议 | S保存/迁移证据→父任务裁定 | 文档owner，关闭操作父任务 | 保留旧决定及替代依据；无整包回盖 | 待裁定，PR4 open，不自动关闭 |

## 后阶段未完工作（不提前开工）

以下沿已采纳阶段边界排队，旧UI-8/9换壳已被AIUI路线替代；旧文中“REG1–5已完成”是目标假设，当前REG-5仍未完。

| ID / 交付 | 前置 | 共享 owner | 验收 | 状态 / 来源 |
|---|---|---|---|---|
| REG-6 声明式插件 | 第二阶段退出＋REG-5→MCP/OpenAPI只读本体 | 契约/registry owner | 声明/范围/未知版本拒绝，G | 第三阶段待排，R |
| DC-1→DC-2→DC-3 | 第二阶段退出→数据中心平台化/6检查/知识同步回滚→血缘→实例/敏感字段 | 数据/知识/AUTH owners分片 | 至少一插件完整检查同步、回滚与三端遮盖 | 第三阶段待排，R |
| AUTH-2 外传内容审查 | 第二阶段退出＋DC-3敏感范围 | AUTH owner | 真实审查各结果、超时/失败关闭、端点与账本 | 第三阶段待排，R/ADR-0002 |
| MEMORY-v1、AS-1、AS-2、KNOWLEDGE | 第二阶段退出→候选/收件箱→SOUL/规则；统一知识服务并行明确接口 | memory/context/知识owners，协调T3提议 | 候选非自动写入、引用定位≥95%、FTS/向量失败退路 | 第三阶段待排，R |
| EXCHANGE-UNIFY / iOS / LLM-DEDUPE | 第二阶段退出；统一交换依REG-3b；iOS采集阅读遥控；去supplier内LLM依场景迁入 | 传输/平台/模型owner | 双通道旧行为、iOS构建真机；不自动外发 | 第三阶段待排，R；旧UI-6为交换能力编号，不复活旧壳 |
| RESIDENT / SCHEDULE-DREAM / REMOTE-APPROVAL / MCP-SERVER / SKILLS | 第三阶段退出→常驻节点→定时/遥控审批→外部接入 | runtime/授权/通信owners | 手机发起桌面执行手机批准；外部Agent访问留痕 | 第四阶段待排，R；已有Dream机制不等于定时服务 |
| OCR-NATIVE / PROTOTYPE-BUILD | ADR-0003明确后置；阶段开始前重新写范围/依赖决定 | 原生解析/原型owner | 三端原生实测与实际构建闭环，未有证据不承诺可用 | 后阶段待定，不自动启动；ADR-0003排除项 |
| RESEARCH-NS-A / S6 / E11-N3 | Research NS依科研/知识/交换；S6按R第四阶段；E11-N3按R第三阶段 | 科研/原型/UI owners | 完整链、真实无绑定objectPage、研究详情助手目录 | 后阶段待排；R §7，不能重造临时绑定 |

## 调度与本片自查

放行下一任务须同时具备：依赖可消费固定SHA、共享owner空档/交接、任务书逐条验收、原有拒绝回归。F5b/c/F3b/F4c与REG-4c保持原派发；新产品任务只完成可审设计书，不启动开发。每次交付更新本队列新版本和总体设计的状态链接，保留历史版本。

已读实际develop的HANDOVER A–D、REVIEW、ADR1末尾/ADR2–5边界、总体设计、AI原生方案、stream契约、相关任务和开放PR。仓库及/workspace未发现AGENTS.md或.skills，空.agents/.codex无附加指令。只验证文档链接、固定源祖先、diff范围/空白；没有运行或声称本片Flutter/模型/设备验收。
