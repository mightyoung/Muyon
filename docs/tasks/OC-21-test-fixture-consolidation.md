# OC-21：科研测试夹具整理

派发：Leader B，2026-10-11；执行：本机既有 opencode 会话（已配置 deepseek flash）。仅第 6 交接排队第 1 条。交接来源 `task/handover-a-to-b-20261011` @ `ae4fff1b47967a4ceb5ca8935df180d521370d80`。

基线：远端最新 develop `330020c07af3431047ceefc05f76b1b5abc332ba`（派发前 fetch/ls-remote 核实）。唯一任务分支 `task/oc-21-test-fixture-consolidation`；干净独立工作树 `/Users/muyi/Documents/Codex/2026-10-11/task-6/oc21`。只在该工作树工作、提交、推该分支；不得合 develop、删分支、触碰其他工作树。Sonnet LE05、Haiku LE04、Codex LE02/REG3e-a、grok SN6 都在途。

## 范围与不变量

只允许修改以下测试与 `apps/muyon/test/support/` 中为本任务新增的共用辅助：

- `apps/muyon/test/oc15_reg3c_order_digest_test.dart`
- `apps/muyon/test/oc16_reg3c_changes_exact_test.dart`
- `apps/muyon/test/oc17_reg3c_rollback_test.dart`
- `apps/muyon/test/oc19_binding_candidate_refresh_test.dart`
- `apps/muyon/test/oc20_receipt_changes_boundary_test.dart`
- `apps/muyon/test/reg3c_outline_tools_test.dart`

抽取重复科研建库、建链、确认/引用构造辅助到 test/support；保持调用顺序、参数默认值、ID、修订、摘要、确认状态、事务与清理时序完全等价。不要为了复用强行统一有语义差异的辅助。所有原断言表达式、测试/组名称、skip 状态、用例数量、覆盖边界保持；辅助中的原断言若移动，必须逐项保持原表达式并记录映射。

注意 OC-18 已合入，但没有 oc18_* 文件；它修改 reg3d_receipt_snapshot_test.dart 与 reg3cf_receipt_snapshot_test.dart，这两个文件本轮不在范围内，不扩范围。

禁止产品代码、依赖/锁文件、golden、平台生成文件变更；禁止删 skip、放宽/删断言、改测试名、增删用例、更新依赖或新配凭证/付费/改模型配置。仅使用会话已有 deepseek flash 额度做这件机械测试任务，不调用真实业务模型，不读/打印 .env。

## 执行与验收

1. 核对 branch、HEAD 与工作树干净（任务说明提交除外），先读本地适用技能。保留原测试文件副本/哈希。任何需要语义选择的地方先停，不自行扩大任务。
2. **抽取前先运行上述全部 6 文件基线测试**，用 Flutter JSON reporter 保存每个文件完整测试名称/组路径、总数、passed/failed/skipped 分类及实际命令、退出码；原始日志与清单放工作树外的 `/tmp/oc21-evidence/`。过滤框架内部隐藏 suite 事件的规则在前后保持一致，保留原 JSON 以供复核。没有稳定全绿基线立即停止回报，不带病抽取，不通过删 skip 或重命名掩盖失败。
3. 只抽取可证明等价的重复辅助，只格式化修改的 Dart 文件。对照原副本核验所有 expect/expectLater/assert/matcher 与测试注册/skip 原样保留；提交回报逐文件断言数量与映射摘要，源码 diff 能追溯任何辅助移动。
4. 抽取后以相同命令运行同一 6 文件；测试完整名称清单、总数、skip 分类与基线一致且全过。运行受影响测试/辅助的 strict analyze（fatal infos），记录结果。pub get 如不可避免，仅恢复自己工作树生成文件，不更新依赖且不提交生成文件；若必须更新依赖，停。
5. **至少一个可逆变异**：仅临时修改新共用辅助的确认或引用构造，例如给审批候选的对象引用 contentDigest/revisionRef 换成明显错误值（选择确实被原有边界测试覆盖的字段）。重跑原有相关测试，必须由原断言失败或原成功路径检测失败，记录变异 diff、原测试名、失败第一行与退出码；不能新增断言来检出变异。不得为变异改产品代码。若原回归抓不到，停止回报，不削弱测试也不改生产语义。
6. 恢复变异后核对 diff，重新跑同清单全部测试全过；确认无残留变异、无范围外文件。提交并推唯一任务分支，核远端完整 SHA 一致，回报基线至最终 diffstat（区分任务说明与实现）。不要合 develop、开集成分支或删分支。

Mac 测试按既有环境取消代理并设 `NO_PROXY=localhost,127.0.0.1,::1`；不可导出 MUYON_EVAL_REAL。日志不提交仓库。基线不稳、超范围、helper 需要改变语义、原断言/名称/数量无法保持、任何失败或权限阻塞时，立即停止并给证据与未完成项，不尝试修产品代码。

## 固定 5 行回报

1. 基线完整 SHA；最终本地/远端完整 SHA；diffstat（文档/实现分别列）。
2. baseline/posttests：命令、每文件数量及 passed/failed/skipped、退出码与外部证据路径。
3. 原断言与完整名称/数量/skip 清单不变核验：逐文件计数、移动映射、前后清单 diff 结果。
4. 变异：helper/字段、原回归测试名、失败第一行/退出码；恢复核验及恢复后同清单全过。
5. 未测/失败/阻塞与停止原因（无则明确无）；不得把尚未运行写成通过。
