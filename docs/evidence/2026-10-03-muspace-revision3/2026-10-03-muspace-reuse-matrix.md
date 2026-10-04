# MuSpace 代码复用与业务迁入矩阵（修订 3）

2026-10-03。关联[设计](2026-10-03-muspace-v0.1-design.md)与[实施计划](../plans/2026-10-03-muspace-v0.1-implementation.md)。代码存在、自动测试、构建、实机通过是不同证据；本表不声称迁入已发生。

## 版本与所有权

科研当前核验 `3e981a5002a604dfb6e28a7e3bf361962c34c09e`；询价 `7d6cb789fe191a726981518c7b1ce87de7ad926f`；MES没有独立固定Git版本。执行前重核 HEAD/dirty，不沿用旧规格里的 a56c10b/ac51b4b 作为当前事实，也不把其他 worktree 的未合入能力混入。

MuSpace 同仓受控提取源码和测试，记录来源/许可，移除旧 app 独立运行前提。没有旧用户数据需转换，但保留导入包语义。领域缺陷修复纳入本次迁入；FTS/ResearchCase等尚未实现项是后续新增，不构成外部 D0–D3 阻塞。

| 来源资源 | 保留的业务 | 目标资源 | 必须变化/验证 | 交付 |
|---|---|---|---|---|
| research `lib/main.dart`、`app/workbench_app.dart` | 六区完整导航和操作 | app组合根 + research模块页面 | 去嵌套MaterialApp/全局项目选择；无首project fallback | M1 |
| `core/store.dart`、`models.dart`、`outline_store.dart` | projects/documents/entries/notes/tasks/runs/sections/outline | packages/research_module/lib/src/core | Store.attach；单owner事务队列；旧BEGIN拆外层与内部；String projectID保留 | M1/M2 |
| `core/exchange.dart`、`research_skill.dart`、`research_kinds.dart` | 目录/ZIP/skill导入、来源/版本/重导入 | packages/research_module/lib/src/core | 无绑定prepare/commit create/refresh；文件准备在事务外；项目/receipt同事务；坏包拒绝 | M1/M2 |
| `reader/reader_page.dart` | PDF/Markdown、页码/引句笔记 | 模块reader | 按scope读取/保存；原文保留；只声称当前定位级别 | M1 |
| `app/workbench_app.dart`任务/结果、`run_assessment_dialog.dart` | 任务导出、手工run、结果返入、评估、接纳 | 模块任务/结果服务及原UI | 任务四分支归属；结果taskId+revision解析项目；未知修订不建task；接纳与完成分离 | M1/M2 |
| `app/writing_page.dart`、`outline_link_dialog.dart`、`exchange.exportReport` | 分节、证据关联、Markdown报告 | 模块写作 | 报告含真实已接纳证据，重开/再导入关联保留 | M1/M2 |
| `relations/relations_page.dart`、`app/skill_panels.dart` | 关系跳转、skill查看及人工绑定 | 原模块页面 | 多项目过滤，未实现Case三视图不伪称存在 | M2 |
| `core/skill_bridge.dart`、claim/experiment导出 | 研究草稿、实验记录回传 | 模块codec | 现有来源ID/rev/字段保真，未知字段不乱删 | M2 |
| LAN transfer代码/测试 | 历史单文件传输机制 | 保留迁入资产、后续transport适配 | 明文listener不直接作为正式能力开放；首版文件往返独立可用 | 后续通信 |
| 原科研12个test文件 | 领域和UI既有回归 | research_module/test | 调整import/fixture路径，保留行为断言 | M1/M2 |
| supplier `packages/supplier_core` + `apps/supplier_app/lib/app` + `lib/platform` | 供应商/联系人/物料/报价、交换/备份/恢复；预算按选定源码核实 | 后续inquiry_module | 不能只搬core丢UI/workspace/platform；宿主接管路径和建库 | M3 |
| MES `prototype-vue/src`及legacy assets | 当前单页试点 | 后续prototype_module/WebView | localStorage适配为受控持久化是新工作；先找齐完整资源 | M4 |

## 首交付后的新能力

全文索引/reading_index、精确文字锚点、ResearchCase、研究卡、限定问答和OCR均不属于当前科研已完成源码。增量应在迁入后的科研模块维护，复用公共模型/解析机制；不另外创建第二套研究事实库。现有笔记和提纲不因新卡设计被删除或降级。

## 逐行完成记录要求

实施时为每行补目标commit、自动测试、macOS/Android实测状态、未决缺陷。功能存在但当前测试失败应修复或明确阻塞，不用旧历史通过遮盖。M1允许未走到的现有流程仍待M2；M2必须关闭所有本地业务行，网络通信单独报告边界。首真闭环成功不等于所有平台/所有功能已交付。
