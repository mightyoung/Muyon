# GB-6 调度与模型回合的其余特征测试（G6～G14，云端开发）

分支 `task/gb-6-dispatch-turn-characterization-rest` · 基线 develop · 执行：grokbot（云端，无本机 Flutter；用 GitHub Actions 验证）· 审查：leader A（会在本机复跑并做变异）

## 依据
[GB-4 特征测试清单](../reviews/2026-10-11-dispatch-turn-characterization.md) 第 3 节缺口 G6～G14 与第 4 节对应的拟新增测试。G1～G5 由 Haiku 在 HK-4 做，**不要碰**。拆分口径按更正：同库私有扩展，不用 mixin（本任务不拆分，只加测试）。

## 要求
- 只加测试，不改 `lib/`。新建 `apps/muyon/test/gb6_dispatch_characterization_test.dart` 与 `apps/muyon/test/gb6_model_turn_characterization_test.dart`（不要改 HK-4 的文件）。
- 每个缺口按第 4 节条目写测试；复用 GB-4 写明的现有夹具，先读懂再照抄。
- 读代码发现某条前提或预期与实际不符：跳过这一条，在回报里写清实际行为与行号；不要为通过去改断言。
- **验证方式**：你没有本机 Flutter。推送分支后看该提交的 GitHub Actions 结果（`gh run list --branch task/gb-6-dispatch-turn-characterization-rest`、`gh run view <id> --log-failed`），按失败信息修测试再推，直到 CI 通过。每次推送前自己逐行核对 import、类型和夹具签名，减少来回。CI 只跑测试，不能代替变异——请在回报里为每条测试写明「它应该抓住的变异」（改 `lib/` 哪一行成什么），leader A 本机去做。
- 只格式化新文件（CI 有 analyze，info 也算失败）；原始日志不进仓库。

## 回报
最终提交哈希与对应 CI 链接及结论；每个缺口：测试名、是否实现、应抓住的变异；跳过的条目及原因。
