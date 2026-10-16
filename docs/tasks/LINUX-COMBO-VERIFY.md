# LINUX-COMBO-VERIFY：UI 与存储组合的 Linux Flutter 复验

执行：grokbot（路线 1）。派发：leader A，2026-10-12。只验证、只报告，不改生产代码、不合入。基线：组合 `326ca138`（LE06-RACE 修复出新 SHA 后改在该 SHA 上重跑并分别报告）；分支 `task/linux-combo-verify-20261012`。

## 要做
1. 精确 SHA 上跑 `scripts/ci.sh` 等价的 analyze 与八个测试套件，记录计数；与 CI 38210369162 对照。
2. 窄屏：PR #61 RED（`2a3201b8`）与修复 `65171dee` 在组合中——在 390px、100% / 200% 文本缩放下 automatic 档位的布局与语义（widget 测试）；若环境允许，**构建并启动 Linux desktop**，截图记录同样场景；明确区分 widget 通过与原生 desktop 实跑。
3. 存储通知隔离 `fad3a001`、N2 无障碍 `4956803e`：相关测试重复运行 ≥10 次的稳定性。
4. 不得跳过或放宽测试；失败按「develop 基线也失败 / 时序相关单独重跑通过 / 本组合导致」分类。

## 回报
环境（OS、Flutter 3.47.5 是否一致、是否有 desktop 依赖）；各套件计数；窄屏 widget 与原生 desktop 结果分开列（未实跑写未实跑）；重复运行结果；失败分类；产物（截图）放分支 `evidence/` 目录，原始日志不进仓库。
