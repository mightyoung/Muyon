# MuSpace 现有项目复用、兼容与责任矩阵

2026-10-03 只读核验。本文区分代码存在、历史执行证据、设备验收和后续计划；不改变原仓、分支或实施计划。证据编号见[索引](../../evidence/2026-10-03-muspace/README.md)，本机源码位置仅作核验出处，不是交付依赖。

## 1. 分支与实际基线

| 基线 | 实际状态 | 接入结论 |
|---|---|---|
| research-workbench 主工作区 | `feat/research-skill-reimport`，HEAD `a56c10b`；lib/core与UI有未提交再导入改动及tests；pubspec/lock：pdfrx2.6.5、engine0.6.1、sqlite3 3.6.0；迁移已含v6 snapshots | 基础阅读/交换默认复用。dirty再导入能力不能当成已合并发布；先由原任务定候选与验证 |
| `.worktrees/research-case-reading` | `feat/research-case-reading`，HEAD `95ba6b9`；Task1修复提交`6e6dac8`和fixup；未跟踪`test/case_store_test.dart`仅首测试，case_models/store文件不存在；store仍为v5基线 | Task1代码存在不等于新真机回归通过；Task2最新执行interrupted由任务交接报告，磁盘无通过报告，不能宣称ResearchCase完成或恢复执行 |
| 科研两规格一计划 | 阅读升级、融合案例规格及研究案例阅读计划均实际读取；worktree同名计划规定不新建科研app，迁移前按实际分支重核 | 平台接入不得覆盖这些领域责任。主工作区v6和worktreev5有编号分歧，未来领域任务整合时处理，不在MuSpace重写/freeze计划 |
| software-cost-calculator | `snapshot/revision-dag-wip`，HEAD `7d6cb78`；supplier_core0.1.0/Drift2.35.0；RevisionEnvelope(protocol2)以canonical SHA-256为revisionId，parents列表；图验证/提交协调器源码与tests | 真实业务是供应商/联系人/物料/报价询价台账，非初始化README描述的空计算器。DAG可作兼容参考，不能把WIP视作正式三端成熟API |
| software-cost-calculator-hubfix | `fix/hub-source-attachment-ids`，HEAD `7ef960f`；supplier_core0.2.0/sqlite3 3.6.0；siq_mcp启动只读Store，具名工具/JSON schema，存在项目预算/询价服务 | siq_mcp在另一份基线，不在前一DAG分支。只能分别核验后选adapter，不假定二者可直接链接、schema兼容或共用数据库 |

询价旧README、应用README和验收表存在更新滞后：以具体代码/版本/场景证据为准。询价独立产品原首发Windows/Android/Web不因MuSpace macOS/Android建议而改变；MuSpace不接管其发布决策。

## 2. 研究功能复用与缺口

| 功能 | 当前实现/证据分层 | MuSpace复用 | 缺口与责任 |
|---|---|---|---|
| 目录/ZIP与skill导入 | ResearchExchange快照、路径/大小/hash校验，V6.5识别九类日志、论文绑定与claim草稿。2026-10-03 verification记录40项测试及合成严格校验；主workspace再导入dirty | 保留入口、源字段、方法版本、独立skill和旧包；不自动运行skill | V6.6提示/ResearchCase不是已完工；领域任务维护兼容，外壳只查来源引用 |
| PDF/Markdown | ReaderPage已用PdfViewer.file，pdfrx2.6.5/engine0.6.1。旧verification称原生未验；后续2026-10-03 native acceptance明确合成Markdown/单页PDF已开、页1笔记已存 | pdfrx作为默认复用实现，不重新标虚空候选；保留原PDF | 大论文/多栏/旋转/文字选区/精准锚点/macOS未因此通过；领域阅读升级承担 |
| 页码引句笔记 | notes含page_number/quoted_text；手填引用、独立存储、不改PDF；上述Android记录有限通过 | 原记录原样展示，兼容页级定位；选区锚点增量 | 保存页码不等于精确回跳；content digest/quote/context/parser需阅读任务补齐 |
| LAN单文件 | HttpServer绑定anyIPv4，代码150MiB、10分钟、随机18字节code；一次下载后stop。README仍30MiB；旧测试覆盖，后续native记录明确无网络传输 | 复用冻结文件/收件导入流程；系统分享先作发布通路 | HTTP明文不满足正式安全要求，缺TLS/persistentACK/两端实测；平台网络adapter独立审阅 |
| 任务/结果 | v1包、手工run、附件、manifest；2026-10-03单手机任务导入/手工记录/结果导出通过，同run回导失败、人工接纳受阻；worktree后来有语义修复代码 | 完整保留旧格式与流程，引用手工接纳结果 | 不能把单手机当双端回传；修复分支选择和对应测试/真机复验归原任务 |
| 关系图 | relations_page、relations_test已存在，可点击解析显式关系；2026-10-02验证记录源码测试，不以截图推全图语义 | 保留科研关系入口，初版助手用引用列表；不重建庞大图谱 | ResearchCase三视图为新计划，不是当前关系图已实现全部功能 |
| 提纲/报告 | outline表、来源关联、exportReport已实现；2026-10-03真机170字节合成Markdown导出通过，但无已接纳证据 | 保留提纲、Markdown报告与证据引用 | 不能把空报告导出当完整证据论文；文献格式/BibTeX/RIS/Zotero另设计 |
| ResearchCase | 两已批准规格/一计划明确MethodSpec、可选Workflow、Case/PlanVersion/Attempt和演进；worktreeTask2仅首测试 | 未来仅消费已交付领域readmodel，不建第二套库 | Case/时间线/搜索/证据卡/OCR仍在对应计划，任务interrupted不等完成 |
| 全文检索/进度/精确卡 | 现store/UI只有路径/条目搜索和手工笔记；没有reading_index/chunks/reading_progress实际实现文件 | 从阅读升级端口增量取得；新研究卡衔接旧note/outline | 这是真实V0.1缺口；计划整合时避免MuSpace与原任务各写一遍 |

## 3. 询价复用与领域责任

| 资产 | 事实与兼容处理 | 责任/发布边界 |
|---|---|---|
| supplier_core Drift分支 | Supplier/Contact/Product/Quotation强类型规则、单位快照/十进制金额/税与日期精度，Record/Exchange/Backup/Query服务，SQLite权威revision与派生projection | 保留原DB/服务/独立app。外壳不改金额、单位、规则版本，不新增虚构cost.calculate DTO |
| 现预算/询价工具基线 | hubfix源码提供describe/search/get/query等和比价/预算工具，siq_mcp只读启动并声明readOnlyHint；实际sqlite3实现不是前行Drift包 | V0.1仅设计adapter与功能保留；完整接入另审选定分支/数据库schema。MCP注解不等权限来源 |
| 修订DAG | canonical envelope ID、parents、冲突/删除/redirect图验证和分页工作区存在。2026-09-17纯图34项＋文件6项报告；2026-09-27核心534/应用116报告限定范围 | 参考ancestor/head处理，保留native ID，不复制为第二套通用历史库；核心总测试数不解除平台/规模门槛 |
| 性能与平台 | release matrix：10万正式导入989.7秒超过其600秒门、深链/内存等未齐；Android/Windows延期。9/30主分支UI报告仍待新APK安装/重启，临时插件兼容修复未提交；应用无macOS target | 不从主README或模拟器旧版本推定当前release通过，不向MuSpace承诺手机/三端性能；后续完整询价接入独立验收 |

## 4. 数据兼容、迁移与双线责任

| 对象/变更 | 设计处理 | 完成责任 / 当前动作 |
|---|---|---|
| 工作区与现project | 外壳workspace_modules绑定storeInstance/project，旧ID不变、目录只引用 | MuSpace未来外壳任务；本轮仅规格 |
| skill来源/整数修订 | NamespaceObjectRef引用原snapshot/kind/id/rev，方法版本与字段原样保留 | 原科研任务维护，不将旧行改写为新schema |
| 原笔记/提纲/run | 保留领域SQLite与files，typedadapter查询/更改；页码笔记可显式升级锚点 | 原科研模块负责迁移/结果幂等，MuSpace不直接SQL写其表 |
| 新卡/解析/包 | 在科研领域新增content digest与全球revisionId；旧包仍读；导出manifest与兼容parser快照 | 科研领域负责实现，平台只定调用/授权合同；启动前合并需求责任清单 |
| 询价Drift/sqlite3分歧 | 先选已核验候选，adapter适配真实服务；不同storeInstance和schema不共享DB路径 | 原询价任务决定候选；本轮不merge、checkout或迁移 |
| 大合库/包提取 | 无立即合库。以后如需提公共包，先备份、旧app可读、ID/修订和原文件hash对照、导入冲突与回退验收 | 新独立迁移规格需用户授权，不在本轮搬lib |
| 计划协调 | 原Case/阅读计划原样保留，MuSpace计划将来只列接口依赖和外壳差额 | 用户审阅本spec后再写MuSpace计划，不freeze/resume兄弟任务 |

## 5. 事实取舍

历史verification“未验PDF”已被后续合成单手机限定场景补充；新记录不解除多栏、精确锚点或桌面门槛。Task1修复代码晚于失败记录，但没有本次独立真机重跑，不能将失败永远等同现状，也不能直接改为已通过。Task2首测试磁盘可见，interrupted来自明确任务交接，未发现执行通过证据。上述日期按各报告声明，提交时间按仓库保留值（不同分支提交时间可能较早），不从时钟或总测试数推导完整产品能力。
