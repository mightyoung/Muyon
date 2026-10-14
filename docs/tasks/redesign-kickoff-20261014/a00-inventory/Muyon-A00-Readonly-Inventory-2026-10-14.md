# A00 Muyon 只读清点报告

接收人：Leader B。用途：派发首批独立任务前的生产模块、bin、旧页面与23迁移单元核对。结论：清点材料具备文档追踪，尚未冻结文件所有权，不能据此称A00工程门禁已过。

产品固定 SHA：`01e56cc2d729dab70e1b1def05c3aa93b28f421a`。设计固定 SHA：`58fe9c62612d74a973614c41677e62a54332e6d6`。报告生成：2026-10-13T23:31:07.834367+00:00。

## 最新职责与历史证据

Oct14用户最新两条决定是“Leader A额度用完，所有职责交给Leader B”“开始改造开发”。由父任务转交的唯一集成线程为 `01a12a9b-e1ca-760e-89af-fa274c469012`；本清点线程只交只读材料，不成为第二合入人。仓库ADR-0001:123的Oct12 Leader A记录及HANDOVER页首Oct11 A→B均保留历史含义，最新用户决定尚未由本线程回写。

[历史ADR记录](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/adr/0001-leadership-and-scope-freeze.md#L123) · [旧交接页首](https://github.com/mightyoung/Muyon/blob/01e56cc2d729dab70e1b1def05c3aa93b28f421a/docs/tasks/HANDOVER-LEADER.md#L1)

## 沿用上轮版本和占用核查

上轮盘点结束于2026-10-13T23:19:56Z，已核167个远端提交树、16个开放PR，没有发现已建立的ADR0006/0007或M01/A00任务文件。此次按要求复用结果，没有再扫远端。此覆盖不包含其他会话未推送文件或私人工作树，不能证明没有人正在工作。

design相对develop ahead 6/behind 0，95新增文件均在设计包。产品代码未因此迁移；独立源码链接仍固定01e56cc。

[develop CI 38279219941](https://github.com/mightyoung/Muyon/actions/runs/38279219941)及[设计CI 38439338859](https://github.com/mightyoung/Muyon/actions/runs/38439338859)已按准确SHA核为success。它们不证明新Rust/双端路线或52项设计验收已实现。

## 生产入口核对

| 对象 | 已核静态入口 | 分类 |
| --- | --- | --- |
| inquiry | bootstrap→InquiryBusinessModule；legacy inquiry Section→Folio shell | 默认注册v2模块，11个旧Section |
| research | moduleCatalog→ResearchModule；WorkspacePage桥接科研工作台 | 默认注册v2模块，旧工作台6个数字切换项 |
| prototype | moduleCatalog→PrototypeModule；独立ModuleSection | 默认注册v2模块，showInModuleMenu=false不是不存在 |
| muyon main | apps/muyon/lib/main.dart→MuyonHost.open | 生产宿主，不是第四个BusinessModule |
| siq_mcp | supplier_core/bin/siq_mcp.dart→openReadOnly→McpServer.serve stdin/stdout | 独立只读CLI，与应用HTTP MCP分开 |
| ui_preview main | apps/muyon_ui_preview/lib/main.dart | fixture/预览应用，不算生产业务模块 |

## 23单元映射

以下页面是设计责任对应，不表示已存在新路由。Rust栏是设计职责，不是仓库中已实现crate。完整固定SHA/路径/行号/源blob与原目标条款见JSON。

| 单元 | 当前组件/模块 | 旧入口或Section | 目标页面 | Rust责任摘要 |
| --- | --- | --- | --- | --- |
| U01 宿主启动、模块注册与关闭 | inquiry,research,prototype /  | Host boot/module activation/close | W01,S05 | Rust RuntimeOwner负责启动状态机、唯一服务/数据库寿命、ShutdownBarrier |
| U02 存储所有权、事务队列与schema迁移 | inquiry,research,prototype / muyon_module_api | All module database lifetimes/schema/restore | D01,S05 | Rust storage crate拥有连接池/单writer、短事务与migration registry |
| U03 module_api合同与插件边界 | inquiry,research,prototype / muyon_module_api | ModuleSection inquiry/research/prototype and typed contracts | W01,D01,S03 | 拆为Rust domain contracts、版本化wire DTO/IDL、端侧screen registry三层 |
| U04 supplier_core商业域：记录、价格、预算、比价 | inquiry / supplier_core | inquiry suppliers/products/quotes/projects | Q01,Q04,Q05,Q06,D01.1,D01.2 | Rust supplier-domain + storage repositories |
| U05 Folio询价应用状态、导入与业务页面 | inquiry / inquiry_module,supplier_core | All 11 inquiry Section values including remote Hub | W01,Q01,Q02,Q03,Q04,Q05,Q06,D01,D01.1,D01.2,D01.3,S03,S05 | 把Store读写、导入流程、job协调和settings domain移到Rust |
| U06 科研对象、卡片、大纲、人工运行 | research / research_module | Research workbench overview/library/tasks/runs/writing/relations | R01,R05,R06,R07,R08 | Rust research-domain统一版本、关系、删除影响与保存 |
| U07 PDF阅读、来源锚点与引用定位 | research / research_module | Research reader/source citation navigation | R02,R03,R04,R05 | Rust保留SourceRef、digest/revision检查、消歧和归一化几何DTO |
| U08 PersonalAgent执行、模型回合与工具调度 | inquiry,research,prototype /  | Host assistant/task execution shared across modules | A01,A01.1,A03,T01,T02,T03 | Rust AgentRuntime + durable task/event store拥有执行和恢复 |
| U09 语义UI合同、流编译、session与publication | inquiry,research,prototype / muyon_module_api | Shared semantic cards/session/publication | A01,W01,T03,R05,Q05 | Rust ui-semantics/plan-validator/session-owner统一验证、dispatch准入、publication与draft revision |
| U10 动态UI renderer、controller与公式重算接线 | inquiry,research,prototype / muyon_ui | Shared renderers/visualization preference and formula adapters | A01,W01,S01.1,R05,Q05,Q06 | React renderer与Compose renderer各自实现组件、布局、焦点、可访问性与本地输入 |
| U11 权限、scope、taint与实时撤销 | inquiry,research,prototype /  | Host access/grant/scope/revocation; old authorization distinct from presentation | S04,A03,T02,T03 | Rust AuthorityService形成唯一policy/grant owner |
| U12 业务写入、CAS、幂等与回执完整性 | inquiry,research / muyon_module_api | Business write commands/CAS/receipt; module write surfaces remain declared | D01.1,R07,R08,Q04,T02,T03 | Rust CommandExecutor以expected revision+idempotency key为入口，在同事务完成业务、change log与receipt |
| U13 模型gateway、SSE、超时与外发账本 | inquiry,research /  | Host/model configuration and optional business model paths | S02,A01,T02 | Rust model-runtime负责HTTP、SSE parser、payload-finalization、ledger和取消 |
| U14 模型披露与本机展示分层 | inquiry,research,prototype / research_module | Purpose-limited model/native/audit projections | A03,S04,R05,T02 | Rust强类型NativeView、ModelView、AuditView与DisclosureContext |
| U15 文档解析、知识索引、OCR与搜索 | research,inquiry /  | Knowledge/search/OCR; libraries/capability ports, not a new BusinessModule | A02,R01,R02,A03 | Rust knowledge-domain负责索引身份、chunk/metadata、digest、query/ranking与失效 |
| U16 导入冻结、工作区激活与备份恢复 | inquiry,research,prototype /  | Import/file freeze, workspace activation and restore | S05,S05.1,R01,D01,Q01,W01 | 平台PickerPort返回短寿命FileGrant |
| U17 LAN传输、任务信封、聊天与文件夹同步 | inquiry,research / supplier_core | inquiry exchange plus host DevicesPage and ResearchTaskBridge | S05.1,T01.1,T02,R01 | Rust transport/sync/runtime + PlatformSecretPort、NetworkAvailabilityPort |
| U18 凭据与平台安全存储 | inquiry,research / inquiry_module | Host/Folio/LAN credential namespaces and platform ports | S02,S03,S03.1,S05.1 | Rust只持有SecretRef并在受控IO发送阶段调用SecretPort |
| U19 本机导出：冻结准备、分阶段授权、账本与保存适配 | research / muyon_module_api,research_module | Research export prepare/claim-draft/ledger; production full-chain wiring not proved | R07,S05,T02,T03 | Rust ExportCoordinator拥有frozen preparation、identity、审批revision、ledger |
| U20 持久通知、任务事件与后台作业 | inquiry,research,prototype / supplier_core | Host task events/notifications and supplier jobs | T01,T01.1,T02,A01 | Rust JobScheduler/EventLog/NotificationInbox统一持久化 |
| U21 记忆 经验与整理 | inquiry,research,prototype /  | Host MemoryPage/Dream and scope-limited shared memory; D11 separate target | S06,A02,A03 | Rust memory-domain/memory-application负责记录、核实、范围收窄、lineage、提案、回滚及用途投影 |
| U22 受限原型 页面版本与反馈 | prototype / prototype_module | Declared prototype ModuleSection; hidden module-menu entry does not imply unused | W01.1 | Rust拥有原型身份/版本/资源manifest/反馈 |
| U23 MCP客户端与本机只读服务 | inquiry,research,prototype / inquiry_module,supplier_core | Host HTTP MCP client; separate supplier_core standalone stdio MCP service | S03.1,D01 | HTTP客户端归Rust agent/platform的受控网络适配，工具映射进入统一registry、目的地/凭据引用、content_review与outbound账本 |

## 易漏范围

Hub是已有远端公司资料服务客户端，含配置、搜索、详情/历史、预览/发布/reconcile和显式导入。迁移归U05，联合U04/11/14/16/17，目标D01.3/S03、W3/W5；不能缩成一张本地公司基础表。外部Hub后台源码不在本仓库树，服务owner尚需登记。

设备消息和研究任务交接已有bootstrap生产构造及回调绑定。accept、说明导入、用户实际研究、结果提交与导入分别追踪；ResearchTaskBridge.start不会自动完成科研。U17联U06/16/20，对应S05.1/T01.1/T02；不新增跨设备自动执行或审批同步。

既有messages保存、范围内memories/experiences上下文、memory_tombstones、dream_runs、dream_proposals和手工MemoryPage/Dream均保留。D11自动对话提取与跨会话助手检索为新增生产者/检索路径，默认关闭、独立开关及预算；CAS、域外遗忘凭据和S07新身份控制也是目标合同。旧revision递增不等于新版expectedRevision CAS。

Sensitivity五类别和字段默认unreviewed已有源码；可信载荷分类、用途投影及全出站验证是新合同，不能由枚举存在推成已实施。源头/敏感度分轴，credential正文与合法认证通道分开，FullAllow遵守既定personal/commercial和新端点语义。

HTTP MCP客户端归宿主受控网络，stdio只读CLI独立生命周期/DB schema；Android不因此默认托管桌面子进程。

## 冲突候选和未归属项

以下为上轮已见提交/任务声明，不证明活跃writer。E01/E02任务曾登记grokbot与当时Leader A；最新集成职责现转Leader B。

- C01：E01 task/e01-le04-bounded-20261012@923e556d78a98dfe8ce696a9c1244cbb3011e6df and PR56；read candidate and retained containment hold; coordinate writer before any shared-file implementation。
- C02：E02 task/e02-export-frozen-facts-20261012@285c107e3973e84d911719e6de1356fcdd9e09b4 and PR59/63；inventory frozen identity and ledger variants; no duplicate execution/ledger owner。
- C03：PR30; task/lib2-postreview-fix-20261012@9bf7eb109f7ff5a4fd1819107625f040bb800f82；typed session/publication contract and source fixtures reviewed together before M03。
- C04：PR65/57/58, model disclosure/provenance test candidates；keep original negatives, distinguish same blob/integrated paths from new tests。
- C05：PR67/68/62 platform/packaging evidence；read platform evidence; no automatic duplicate packaging/real device work。
- C06：legacy feat/p0-ci-llm-baseline and task/p0-j1-env-doctor README variants；historical branches far behind develop; not evidence of a current entry-switch writer。

- O01：all 23 unit writers and reviewer assignments。Leader B fixes task branch, paths, dependencies and author/non-author review; this inventory does not assign them。
- O02：remote Hub backend source/service owner。register external service/contract responsibility; no inference from client methods。
- O03：D11 extraction/history retrieval and S07 identity profile。separate existing persistence/manual management from new producers and independent budget; name writer。
- O04：standalone MCP CLI platform lifecycle and DB-schema compatibility。keep HTTP client and stdio service matrices separate。
- O05：existing device exchange rollout/legacy retention。do not drop existing messages/research exchange or add global task synchronization。
- O06：V132-I01 and S01–S03 follow-up fixtures。carry into A00/M04–M05; not a request to rewrite the two design books。

## 实际完成度与可开工范围

已完成23单元主要源码锚点/责任对应、3注册模块、1独立CLI、11询价Section、6科研切换项、4宿主导航及29主页面/9子页ID核对。源码存在和静态接线不等于运行通过；本次没有运行真实库、模型、设备或产品测试。

可以据此继续M01/A00资料补齐、D01a/D03a合同草案和合成fixture设计。由Leader B把上述跨单元点、文件集合、任务分支和非作者审查者逐项冻结，再派实际实现；共享文件不由多个新writer并行修改。V132-I01/S01–S03放入A00/fixtures跟踪，不重写两册。

本报告只能称A00清点文档材料齐备，不能自称所有权已冻结或工程G0已过。后续真实历史迁移、服务外发、模型/设备及合入按对应门禁和唯一集成人执行。

## 机器清单

[JSON清单](Muyon-A00-Readonly-Inventory-2026-10-14.json)包含所有单位、固定源码证据、旧Section对应、重点链路、冲突候选和null writer。所有new_page_ids与第二册标题校验；任何null writer不得解释成文件空闲。
