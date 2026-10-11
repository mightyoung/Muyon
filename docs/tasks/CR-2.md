# CR-2 本体写卡设计：新建、编辑、关联、批量（ChatGPT 6 Pro，线上设计）

执行：ChatGPT 线上（6 Pro）· 只读 GitHub，不连本机 · 结果：设计稿全文贴给用户，由 leader A 入库为 `docs/design/ontology-write-cards-2026-10-11.md`，再拆成实现任务

## 背景
用户要求（[AI 原生方案](https://github.com/mightyoung/Muyon/blob/develop/docs/design/ai-native-ui-redesign-2026-10-09.md) §4.4）：业务卡片由本体驱动，插件不更新，助手也能随本体演进。现状：
- 只读本体卡已有：`apps/muyon/lib/assistant/ontology_cards/`（快照、适配器、`OntologyCard`，提交按钮恒为禁用）；询价本体在 `apps/muyon/lib/app/adapters/inquiry_module.dart`（字段、类型、敏感度、关系）。
- 通用写工具已有：`inquiry.create_record` / `update_record` / `delete_record` / `restore_record`（`apps/muyon/lib/platform/inquiry_record_tools.dart`：仅选定范围、`expected_version`、`operation_id` 回执、报价价格字段不开放、有活跃引用禁止删除）。
- 确认与授权：[ADR-0002](https://github.com/mightyoung/Muyon/blob/develop/docs/adr/0002-graded-assistant-authorization.md)；写入逐次确认，外部内容时不出现放行类按钮；成功只认回执。
- 动态界面：[流式契约](https://github.com/mightyoung/Muyon/blob/develop/docs/design/aiui-stream-contract.md)；生产接线在 [PR42](https://github.com/mightyoung/Muyon/pull/42)，[CR-1 审查](https://github.com/mightyoung/Muyon/blob/review/gb-1-invariant-audit/docs/reviews/2026-10-11-pr42-design-review.md)。
- 缺口清单：[GROK-8 追溯](https://github.com/mightyoung/Muyon/blob/develop/docs/reviews/2026-10-10-aiui-acceptance-trace.md) 第 4 节第 4～6 条。

## 要设计的东西
1. **四种卡**：新建、编辑、关联（选另一对象建立关系）、批量（多条同类变更一次确认）。每种写：从本体自动生成哪些部分（字段顺序、分组、折叠、必填、枚举、引用选择）、哪些由宿主固定、模型能填什么（只能填草稿值，不能改结构）。
2. **字段类型映射**：本体每种 `Kind`（文本、整数、布尔、枚举、日期、文本列表、引用、引用列表、对象……以代码实际为准）→ 输入控件 → 校验 → 显示；未知类型的安全退路（只读显示加「去原页面编辑」）。敏感度 `personal / commercial / credential / unreviewed` 在卡上的处理。
3. **状态机**：草稿 → 校验中 → 待确认 → 执行中 → 成功（有回执）/ 失败 / 冲突（`expected_version` 不符）/ 已撤销。每个状态下哪些按钮可点。冲突怎么让用户看到差异并重新确认。
4. **校验**：提交前宿主跑插件校验器（询价 `validatePayload`），非法字段就地标出且不发请求；执行时同一事务再校验一次。模型给出的值与用户改过的值如何区分显示。
5. **与流式契约的对接**：写卡在流里是什么组件、需要宿主在 `actionContext` 里提供什么（草稿、`draftRevision`、`operations`）、业务动作如何映射到四个通用工具，`operation_id` 谁生成。
6. **三档与外部内容**：「只用文字」档下同样的写操作如何用文字和固定页面完成；外部内容任务里四种卡分别少了哪些按钮。
7. **范围外**：报价的价格与授标走具名流程，不进通用写卡；说明边界。
8. **验收清单**：每条可测的要求一行，写成拒绝路径（例如「过期版本提交被拒且不写库」）。

## 输出要求
- 中文，先给一页结论，再分节。所有对现有代码的引用写 `文件:行`（固定到你读的提交）。
- 只设计，不写实现代码；可以用伪结构表示组件属性。
- 不确定的地方列入「待用户决定」，给出你的推荐。
