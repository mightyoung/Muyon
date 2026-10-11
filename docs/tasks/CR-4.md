# CR-4 科研场景（AIUI-7）的对话界面设计（ChatGPT 6 Pro，线上设计）

执行：ChatGPT 线上 · 只读 GitHub · 结果贴给用户，leader A 入库为 `docs/design/aiui-7-research-scenarios-2026-10-11.md`

## 依据
- [AI 原生方案](https://github.com/mightyoung/Muyon/blob/develop/docs/design/ai-native-ui-redesign-2026-10-09.md) §4、§8（AIUI-7：引用卡、阅读器工作区、结果对比）。
- [GROK-7 科研走查清单](https://github.com/mightyoung/Muyon/blob/develop/docs/reviews/2026-10-09-research-walkthrough.md)：常见目的、首批建议、公式表。
- [GROK-6 科研本体](https://github.com/mightyoung/Muyon/blob/develop/docs/reviews/2026-10-09-research-ontology-draft.md)；科研敏感度全部为 `none`（ADR-0004 §12.1 注记）。
- 已开放的科研工具见 `packages/research_module/lib/src/module_declarations.dart`；写作大纲工具 REG-3c 正在实现；其余写入在调研（GB-2）。
- 流式契约与组件库：[https://github.com/mightyoung/Muyon/blob/develop/docs/design/aiui-stream-contract.md](https://github.com/mightyoung/Muyon/blob/develop/docs/design/aiui-stream-contract.md)、`packages/muyon_ui/lib/src/dynamic/` 的 library-2 组件。

## 要设计的东西
1. 首批 5～8 个科研目的（以 GROK-7 首批为起点，按现在已有或即将有的工具重新排序），每个写：用户原话、回答形态、组件、宿主快照要提供的事实、需要的宿主公式、动作及路由、现在能否做。
2. 三张核心卡/工作区：引用卡（证据与主张的关系、来源展开）、阅读器工作区（哪些留在原页面）、结果对比（运行指标差值等公式交给宿主）。写清楚每张的结构、交互、只读与可写边界。
3. 「只用文字」档下同样目的如何完成。
4. 与询价写卡（CR-2 并行设计中）保持一致的地方，和必须不同的地方。
5. 验收清单（拒绝路径写法）；待用户决定的问题与推荐。

只设计，不写实现代码；引用写 `文件:行`。
