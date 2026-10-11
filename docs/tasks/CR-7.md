# CR-7 科研快照、科研公式与来源导航的宿主设计（ChatGPT 6 Pro，线上设计）

执行：ChatGPT 线上 · 只读 GitHub · 结果贴给用户，leader A 入库为 `docs/design/research-snapshot-formulas-2026-10-11.md`

## 背景
[AIUI-7 科研场景设计](https://github.com/mightyoung/Muyon/blob/develop/docs/design/aiui-7-research-scenarios-2026-10-11.md) 第 7 节列出实现前置：(1) 科研快照适配（完整运行信息、来源、领域关系、段落候选、集合完整性，不能用嵌套 `.data` 充当全部事实）；(2) 科研公式登记并接通 library-2 重算（现公式注册器只有 5 类，重算适配器拒绝 library-2：`apps/muyon/lib/platform/ui_formula_registry.dart`、`ui_recompute_adapter.dart`）；(3) `SourceRef` → 快照来源 → 阅读器定位器的可信路径。用户已决定 D2（宿主提供统一、受范围约束的显式论文—主张关系投影）、D3（首版同任务同修订对比）、D4（指标口径由宿主 / 模块声明，缺失 / 未读取 / 零值分开）。询价侧的对应实现可参考 `apps/muyon/lib/platform/inquiry_ui_planning_source.dart` 与 `apps/muyon/lib/assistant/ontology_cards/`。

## 要设计
1. `ResearchUiPlanningSource`（或等价物）：读哪些表、产出哪些 fact / collection / sourceSpan、如何表示集合完整性与截断、范围与版本钉住、与询价 source 的共用部分。
2. 关系投影（D2）：从 `relations_page.dart` 的解析逻辑抽出共享投影的接口；已解析边与未解析原因的数据形态。
3. 9 个拟登记科研公式（AIUI-7 设计 1.9 节）：每个的输入绑定、输出、单位、缺失与零值策略、版本；指标口径声明（D4）放在哪里、谁声明；重算适配器支持 library-2 所需的最小改动。
4. 来源导航：`SourceRef` 与 `SourceSpanRef` 的映射与核验；阅读器入口两种（打开文档 / 核对引用）的参数与失效处理；canonical package 文档没有 ReaderPage 适配器时的处理。
5. 拆成可独立实现与审查的任务片（范围、依赖、拒绝路径验收）。
6. 待用户决定的问题与推荐。
只设计，不写实现代码；引用写 `文件:行`。
