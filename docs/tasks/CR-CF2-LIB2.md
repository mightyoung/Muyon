# CR-CF2-LIB2：CF2 与 library2 契约和反例独审

执行：Haiku（Claude 路线 1）。派发：leader A，2026-10-12。只审查、只写测试反例，不改生产代码；不与任何实现路双写。基线：develop `ab5506c3`；分支 `task/cr-cf2-library2-review-20261012`。

## 对象
- PR #57 library2 `8d96164c`（原作者 13 通过 / 1 跳过）。已知 GAP1：`verified` 为 null 加 `notDisclosed` 仍接受候选。
- PR #58 CF2 反例 `65b85d89`（原作者 11 通过 / 4 RED，CI failure）：end-only 工具及事件、中途 textOnly 原因码、complete 却显示 incomplete。
- 交接第 7 节「CF2 原因码与完成状态」「重算与过期恢复」（恢复方案 A 已获用户批准）。

## 要做
1. 在本分支基于 develop 复现：#57 GAP1 写成会失败的测试；#58 四个反例在当前 develop 上是否仍 RED（各给失败第一行）。
2. 逐条核对契约：原因码由宿主判定，模型 `reasonCode` 不透传；模型不出卡 / 用户档位限制 / 宿主校验失败三类区分；非法节点不统一归为模型不出卡；complete 与界面完成一致；整批重算失败 fail-closed，不把缺值当 notApplicable；FactState 与 freshness 分轴；过期后只允许受约束的本地 editField 触发重算、业务动作仍拒绝；旧值标「旧结果 / 上次计算」，semantics 同样标明。
3. 每个缺口给：文件:行、失败场景、可直接运行的反例测试（提交到本分支，预期 RED）。

## 回报
按 Critical / Important / Minor 列出（每条带反例测试名与失败第一行）；最后列建议的实现任务拆分（每项 ≤1 天、文件边界、依赖）。提交哈希远端与本地一致。
