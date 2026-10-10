# 本轮质量修复计划 v1 — 2026-10-10

用户已授权“制定修复任务并并行开始执行修复”。固定 develop 为 [8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d](https://github.com/mightyoung/Muyon/commit/8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d)。本计划按父任务实际分派记录并行责任，不新增产品路线；执行者仅推任务分支/草稿 PR，父任务统一 review、唯一 integrator 顺序合 develop。完整现状及历史替代关系见[状态快照](CURRENT-STATUS-2026-10-10-v1.md)。

## P1 优先与并行责任

PR20 manual hold 身份连续优先；PR17 的故障一致性修复并行推进，但不能把历史 LAN400 宣称已确诊。lint、coverage、Mac复验和文档各自独占范围；AIUI owners 保持既定分派。触及别人独占文件的 diagnostic/依赖交父任务协调，不能抢改或因合入绿跳过新的 head 审查。

| 分支 / owner | 唯一写入范围 | 当前状态、依赖与验收 |
|---|---|---|
| `task/harness-manual-hold-identity` / PR20 原作者独立修复 owner | `agent_resume.dart` 身份连续路径、对应 resume 行为测试与任务摘要；不碰 LAN/AIUI/CI | P1：未确认 hold 在重复 pause/resume 与 DB 重开后保留 invocationId/digest/BudgetUsage，旧破损卡继续 hold；先实际 handler 计数的 RED，再最小 GREEN；late receipt 不可恢复可重复执行卡；真实 Claude 独立窄审、精确源与组合全门禁、新 head bot 意见裁定齐备才交 integrator |
| `task/lan-upload-reliability` / PR17 LAN owner | `packages/supplier_core/lib/src/lan.dart`、`lan_receive_diagnostics.dart`、`test/lan_security_test.dart`、`lan_upload_reliability_test.dart`、LAN 任务文档 | rename 故障已取得真实 RED；持久化失败污染后续内存/磁盘状态的故障测试由该 owner 分类并最小修复。保留 before-body 预留、150ms、合法200断言及 callback 已可能有副作用的 replay 拒绝；真文件冲突与模拟 cleanup 必须区分；Claude 窄审、故障矩阵/restart/安全及全门禁。历史400仍未知，不以新故障说明历史根因 |
| `task/quality-lint-baseline` / lint owner | **仅四包 config/deps**：module_api、supplier_core、muyon_ui、prototype_module 的 analysis_options，缺失直接依赖的 pubspec；语义修复若需别人文件先交父任务 | 已推 `5fbc6ce83d569614cd9fd8497f68acc60c495201`；保留首次真实 diagnostics，禁止 ignore/exclude/降规则。不得抢改 PR17 LAN、PR20 resume 或 F5b/c API/UI；最终八包 analyze/test 与组合门禁，首轮红不算完成 |
| `task/quality-coverage-baseline` / coverage owner | `scripts/ci.sh`、`scripts/coverage/`、门禁脚本测试、现有 `.github/workflows/ci.yml` 的派生摘要及 `.gitignore`；不改 Dart 业务或四包 lint | 已推 `efe75a1f723b5261416f9cc9d402e7efa98173b3`；八套测试各跑一次采 LCOV，缺/空报告失败，未加载源码分母未知；门禁记录源码/执行行身份漂移和 hit 退化。真实 Actions 基线测得后才冻结，不编百分比；离线故障测试、现有退出码回归和最终组合测量审查 |
| `task/quality-macos-golden` / 本机 Mac owner | 独立任务摘要、固定环境的少量派生证据；不直接改 golden、skip、容差、产品/CI | 已由父任务分派本机复验，当前未核到远端交付。先当前 Mac 最小1～3例诊断，固定 SDK/engine/OS/字体，保留实际差异和版本；再由父任务决定全量。不可直接换 golden，不将最小诊断当完整46例/verify通过；既有例外按[备忘录](VERIFICATION-MEMO.md)不自动延续 |
| `task/quality-handover-index` / 本片文档 owner | README/HANDOVER/VERIFICATION 入口及本轮版本化状态、修复计划 | 当前文档交付待审；保留历史/用户编辑与替代提交。链接读回、祖先核对、范围检查、PR4独有内容/关闭建议；不编辑 integrator 集成交接、QUALITY-BACKLOG 或 PR16 详细报告 |

## AIUI 依赖与交接

- PR19 契约六项已获父任务技术采纳，机械收尾进行中；远端 `3f9841aa14018429cbb19f705ff1ae3422fad50a` 文档仍保留 proposed 历史状态。采纳不等于生产切换、实现或合入。
- F5b 真实 Claude owner 正在实现契约/33组件 adapter，独占 snapshot/plan/validation/state/stream protocol/compiler、ui_contract 导出、surface、typed edit/collection、新目录/adapter、输入/layout 的既定接口。其他人不写这些文件；PR21 的 H2 export 由 F5b 应用。
- F5c 核心 owner / [PR21](https://github.com/mightyoung/Muyon/pull/21)首片仅 `packages/muyon_module_api/lib/src/ui/recomputation.dart`、`test/ui_recomputation_contract_test.dart` 与交接；固定 `40b121a99e019a2e1fc1c6f19dc517328fdb11d1`，处于 scaffold 行为 RED 验证，不声称完整 publish/controller/workspace/restore 接线。后续依赖 F5b 可消费接口与父任务精确文件分派。
- [PR18](https://github.com/mightyoung/Muyon/pull/18) owner 只持有 `apps/muyon/test/aiui_edit_recompute_acceptance_test.dart` 及验收任务设计；qty3/4→30/40 的真实 RED 已有，不是 GREEN 实现。F3b/adapter 待正式接口/文件分派，保持严格 payload、extracted/override/adoptExtracted、旧 Widget capture 与 H3 场景，不弱化原断言。
- 新切片须各自有效行为 RED/GREEN、正式旧契约回归、指定变异的真实断言检出、固定源/组合门禁；UI/golden/设备/真实模型仅在实际验收后记通过。

## CI 状态按查询时点区分

2026-10-10T03:57Z 用 GitHub Actions API 按以下精确 head 查询；这是当时的快照，运行中项合入前须重核终态，不写永久绿/红标签。

| PR / 精确 head | 查询结果 | 原因口径 |
|---|---|---|
| PR4 `503fd57f94dea11f2854af8d5e4923ce1b34bd1b` | [37488913406](https://github.com/mightyoung/Muyon/actions/runs/37488913406) completed/failure | 父任务已核旧超时；与当前 PR17 故障一致性、PR18 预期RED不同，不据旧失败推断当前产品根因 |
| PR17 `4480ab697018cb2f3dff74005b3ff562bce7e3b9` | [38021348919](https://github.com/mightyoung/Muyon/actions/runs/38021348919) / push38021346242 completed/failure | 故障矩阵红；此前1b46为 delegate 编译失败、故障未执行，不能混作有效RED；当前逐项失败由 LAN owner 汇总 |
| PR18 `67a5f57691244fbbfb71d62d8854dec369171fcc` | [38021008473](https://github.com/mightyoung/Muyon/actions/runs/38021008473) completed/failure | 有效预期RED，两个业务值发布断言失败，禁止合入 |
| PR19 `3f9841aa14018429cbb19f705ff1ae3422fad50a` | [38021954198](https://github.com/mightyoung/Muyon/actions/runs/38021954198) / push38021950872 in_progress | 未取得终态，不继承旧草案/基线 CI |
| PR20 `80aae66cd67472e6fc8f46412f1a76085fdbb2af` | [38022126443](https://github.com/mightyoung/Muyon/actions/runs/38022126443) / push38022123815 in_progress | tests-only RED 候选，生产尚未修；不能提前关闭PR16 P1 |
| PR21 `40b121a99e019a2e1fc1c6f19dc517328fdb11d1` | [38022185754](https://github.com/mightyoung/Muyon/actions/runs/38022185754) / push38022170050 in_progress | 新核心接口 scaffold，待实际行为验证 |

本计划不重跑挑绿，不提交原始 logs。CI绿与产品阻断/未来场景/平台跳过分开判定。

## 性能：先测量，待排

WAL、stream、JSON 优化只列测量计划，**未运行、未决策、未派实现**。后续由父任务定精确源和 owner：分别固定 SQLite journal/同步/数据规模与事务负载、流分片与取消/首字口径、JSON载荷大小/解析与序列化输入；记录工具链、warmup/样本口径、耗时/内存及未测范围，再决定是否优化。不能靠本索引选 WAL 或更改 stream/JSON 架构；不得把 E-1 旧基线当本轮性能实验。

## review / 集成顺序

P1 PR20 与 PR17 先完成独立源验收；其余 owner 可并行交付。父任务逐项裁定审查、RED证据与剩余问题后，唯一 integrator 选可合切片顺序组合，固定组合门禁通过再正常合 develop，并追踪发布CI与新 head bot 意见。AIUI新契约不能仅因为文档/接口片绿就连带采纳全部生产能力。main/强推/分支删除/部署不在本轮范围。integrator 未推 `0721d6e1...` 的 QUALITY-BACKLOG 是待带入资料，本文件不同名、不覆盖。
