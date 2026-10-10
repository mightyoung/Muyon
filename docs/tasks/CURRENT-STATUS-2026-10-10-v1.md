# 当前交接状态 v1 — 2026-10-10

本快照固定远端 develop [8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d](https://github.com/mightyoung/Muyon/commit/8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d)，不是持续更新的完成证明。新进展须核精确 head、审查及门禁后另记版本。任务分支 `task/quality-handover-index` 仅整理文档；父任务统一 review、唯一 integrator 顺序合 develop。本片不改产品路线、代码、CI 或 PR16 详细报告，不操作其他 PR 的关闭/合入。

## 阅读顺序与决定优先级

1. 本快照 → [任务索引](README.md) → [集成交接最新轮次](INTEGRATION-2026-10-09.md) → [验证备忘录](VERIFICATION-MEMO.md)。[旧 leader 交接](HANDOVER-LEADER.md)保留历史，不能以旧待审清单重复派发。
2. [ADR-0001 后续记录](../adr/0001-leadership-and-scope-freeze.md)、[ADR-0003 的 10-09 修订](../adr/0003-phase2-scope.md)、[已采纳 AI 原生方案](../design/ai-native-ui-redesign-2026-10-09.md)与[正式 stream/1 契约](../design/aiui-stream-contract.md)。[ADR-0002](../adr/0002-graded-assistant-authorization.md)、[ADR-0004](../adr/0004-module-contract-v2.md)、[ADR-0005](../adr/0005-model-adapter-and-agent-loop.md)继续约束权限、模块与循环。
3. 最新已采纳决定优先于旧稿。AI 原生方案由 [49a03ec8bd62044e26431a257246f9da191fdd70](https://github.com/mightyoung/Muyon/commit/49a03ec8bd62044e26431a257246f9da191fdd70)采纳；当前四导航为助手/任务/资料/设置，v6 仅保留视觉层，旧 v4 五导航只作历史。[f3b4732c50d47fb67661ec613975f6ad9d4ae85a](https://github.com/mightyoung/Muyon/commit/f3b4732c50d47fb67661ec613975f6ad9d4ae85a)取消 UI-0，取代 10-07 并入 R-1 第三件的安排；[R-1](R-1.md) §3 已标取消。

## 已集成与未闭环分别记录

| 项目 | 此基线可核状态 | 仍需处理 |
|---|---|---|
| AIUI-1/2、GROK-7、REG-3a | 源 `276b29146d3eb902380cceac708209cc6ef344c0` / `4e45836efcb85c86f5c8de57e6b07795aab6166a` / `18ae5127474d6841ad331ca2251076ecca431a81` / `48b36375c2ea8ebf3c10281e7f6372a9aa52e5b7` 均在 develop 祖先；[集成交接](INTEGRATION-2026-10-09.md)有固定源/组合/发布证据 | 不再按旧 HANDOVER A～C 重复审合；REG-3a 只是有界片，[REG-3a 任务](REG-3a.md)及[复审](REG-3a-review.md)保留 REG-3b、剩余科研写入与 Q10 门面等缺口 |
| doctor | [JR-1 合入 a1c4111a073cbb52e0779bd8746948a49bf5f10c](https://github.com/mightyoung/Muyon/commit/a1c4111a073cbb52e0779bd8746948a49bf5f10c)，`scripts/ci.sh` 已执行 `test_doctor.sh`，[审查](JR-1-review.md) | 旧「CI 不跑 doctor」已失效；doctor 不能替代业务/设备/golden 验证 |
| AIUI-3/F3a、AIUI-4/F4a/F4b、AIUI-5/F5a | 基础片已集成，见[索引](README.md)和[集成交接](INTEGRATION-2026-10-09.md)第三/四轮 | 纯计算/外壳/草案归档不等于 runtime 接线或新契约闭环完成 |
| T-3 / PR14 | metadata scope 机制源 `2f7cdee41a428bd02257de990e2e54242a01ddc1` 已集成，[复审](T-3-metadata-scope-review.md) | 生产登记 OFF，完整 T-3 未完成；LAN400 仍未重现、原因未明 |
| Harness / PR15、PR16 | [PR16 实际合入 38f2040bbdb7b7d0f766891c94c3440d208a7f6c](https://github.com/mightyoung/Muyon/commit/38f2040bbdb7b7d0f766891c94c3440d208a7f6c)，组合/发布 CI 成功 | **manual hold 重复 pause/resume 丢历史 invocationId/digest 的合后 P1 未关闭**；[8debfd2 暂停整体接受](https://github.com/mightyoung/Muyon/commit/8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d)。`task/harness-manual-hold-identity` 已有远端 `80aae66cd67472e6fc8f46412f1a76085fdbb2af`，仅记独立修复进行中，需真实 Claude 评审、精确源/组合门禁和新 head 意见裁定；CI 绿不等于无阻断 |
| R-1 | 已取消 UI-0；任务分支交付 E-1 真实模型基线见集成交接的排除项 | Android 重跑仍待本机条件；不得记 R-1 全完成或以分支交付冒称已集成 |

## AIUI 当前未合切片

- [PR18](https://github.com/mightyoung/Muyon/pull/18)：`67a5f57691244fbbfb71d62d8854dec369171fcc` 为真实 test-first RED，[38021008473](https://github.com/mightyoung/Muyon/actions/runs/38021008473) completed/failure。qty=3/4 预期 total=30/40，实际均20；两例到达指定行为断言，非 SDK/loader 失败。禁止合入；14 项未来场景不能写通过，GREEN adapter 尚待实现。
- [PR19](https://github.com/mightyoung/Muyon/pull/19)：远端 head `3f9841aa14018429cbb19f705ff1ae3422fad50a`。父任务已技术采纳此前 `36d0ba` 六项接口（本轮委派/PR18 状态同步），PR19 正文仍保留 proposed/未采纳的历史口径；技术采纳不代表正式生产 schema 已切换或已合。F5b adapter 与 F5c 核心契约仍在进行，`task/aiui-5-f5c-core-contract` 已有远端 `40b121a99e019a2e1fc1c6f19dc517328fdb11d1`。精确可消费 head、独立验收/组合门禁另核，不能标完成。
- 当前树的 [F5a binding draft](../design/aiui-binding-adapter-contract.md)是历史归档；后续技术采纳与实现材料在独立分支，不改旧 draft 为已上线。业务 mapping 尚缺时确认保持 disabled；不以新资料放宽授权。

当前并行修复的 owner、依赖与验收见 [QUALITY-REPAIR-PLAN-2026-10-10-v1](QUALITY-REPAIR-PLAN-2026-10-10-v1.md)，包含 PR17/20/21 与 CI 查询时点。F5b 由真实 Claude 实现中，F5c 核心接口已有 PR21；均不记完成。

## 本轮质量任务清单

| 任务 | 实际状态 | 完成证据与约束 |
|---|---|---|
| 四包推荐 lint 补齐 | `task/quality-lint-baseline` 进行中；固定远端 `5fbc6ce83d569614cd9fd8497f68acc60c495201`，[任务书](https://github.com/mightyoung/Muyon/blob/5fbc6ce83d569614cd9fd8497f68acc60c495201/docs/tasks/QUALITY-LINT-BASELINE.md) | module_api、supplier_core、muyon_ui、prototype_module 补推荐规则；首轮诊断及最小修复仍待核，不能以配置提交标通过；不 ignore/exclude 或放宽 fatal infos |
| coverage 基线门禁 | `task/quality-coverage-baseline` 已推框架 `efe75a1f723b5261416f9cc9d402e7efa98173b3`；真实测量/冻结基线待核，未完成 | [任务书](https://github.com/mightyoung/Muyon/blob/efe75a1f723b5261416f9cc9d402e7efa98173b3/docs/tasks/QUALITY-COVERAGE.md)规定八套 LCOV 和逐步门禁；先采固定工具链基线与排除口径，再审冻结基线；不编造覆盖百分比，也不把 ADR 的能力覆盖门槛混作测试覆盖率已实施 |
| Mac golden 固定版本复验 | 待本机取证；历史46失败保留，不报全绿 | 按[备忘录](VERIFICATION-MEMO.md)固定 macOS27.0.1/Flutter3.47.5/Dart3.13.4、SDK/engine/字体，比较完整失败集合、像素与四类PNG哈希；禁止更新 golden/加skip/增容差换绿 |
| 性能测量后决策 | 待测量，无新数字/结论 | 按 ADR-0003 退出标准与 E-1 口径测量首字等指标，再决定优化；本索引不改架构或产品路线 |
| 文档漂移收口 | 本分支交付待父任务 review，未合 develop | 当前入口、历史日期/替代关系、PR4 保留建议与链接逐项读回；仅文档 |

协调记录：integrator 另有尚未推送提交 `0721d6e1da02dacb51561bdc140fb8039ddedba8`，包含 `docs/tasks/QUALITY-BACKLOG-2026-10-10.md` 与集成交接补记。该信息来自父任务协调，当前远端基线没有此对象/文件；属于**待带入资料**，不设失效相对链接、不冒称已发布。本片不创建同名文件或编辑集成交接；最终由 integrator 按顺序整合。

## PR4：先保留独有内容，再建议关闭（不执行）

固定 [PR4 head 503fd57f94dea11f2854af8d5e4923ce1b34bd1b](https://github.com/mightyoung/Muyon/commit/503fd57f94dea11f2854af8d5e4923ce1b34bd1b)，PR 当前仍 open；不能说四文件已合。

| 原四文件 | 读回结果 | 建议保留/关闭理由 |
|---|---|---|
| `docs/design/claude-design-review-2026-10-06.md` | 当前已存在，正文与 PR4 相同，仅多历史注记 | 保留当前历史注记；不回退成现行五导航规格 |
| `docs/design/claude-design-prompt-round2.md` | **原路径不存在**；[当前 v4/prompts 同名文件](../design/v4/prompts/claude-design-prompt-round2.md)与 PR4 内容逐字相同 | 保留迁移后的历史提示词，不重建旧路径为权威入口；不能宣称原四文件已合 |
| `docs/design/ui-redesign-brief-2026-10-06.md` | 当前含后续 §8 决定和 AI 原生方向；不能整份回盖 | PR4 旧底栏/颜色/逐次确认口径已由 ADR-0002、v6视觉与10-09 AI原生决定取代；逐条核后续决定，不静默丢用户编辑 |
| `docs/tasks/UI-0.md` | 当前标取消；PR4 只澄清阶段后派发 | 保留取消及日期；不恢复派发 |

两份设计原文的内容保留方式已核；PR4 并非当前产品方案。建议父任务在确认无未保存的独有用户决定后，以“后续决定取代、审阅/提示词正文已保留（提示词迁移路径），不再整分支合入”说明关闭理由。当前快照只提出建议，未 close/merge。

## 本片手工核对与限制

- fetch 精确 develop 完整 SHA；仓库与 `/workspace` 未发现 AGENTS.md，已读任务 README/HANDOVER/VERIFICATION/INTEGRATION/REVIEW、ADR 最新决定及 AI 原生设计；空 `.agents`/`.codex` 无补充规则。
- 逐项核上述已集成四源、JR-1、PR16、设计采纳/取消提交都是固定基线祖先；查看 `scripts/ci.sh` doctor 调用。未为索引新增框架。
- PR4 四文件按上述路径逐项读回；review 正文仅历史注记差异，round2 两路径 diff 为零；PR18/19 用 GitHub 只读 API 读取 head/正文，远端任务 heads 以 ls-remote 核实。gh GraphQL Forbidden 已改用连接器，不视为没有 PR。
- 本片提交前对所有新增/修改 Markdown 本地链接、固定 commit 链接与范围逐项检查；原有 README 规则/表格保留，无原始日志入库。只核文档，不运行或冒称 Flutter、Mac/设备/模型验收通过。

本片读回结果：5份交付文档中的200个本地Markdown链接目标全部存在；6个固定commit链接对象可读，PR4 head明确不在develop祖先、其余5个在基线祖先；另核4个已集成源祖先全部通过。PR4原round2与迁移后文件diff零行，review正文仅当前历史注记增量。`git diff --check`通过；最终范围仅本片5份文档，集成交接与PR16详细报告未改。
