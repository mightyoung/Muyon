# CF-FIX-A：计算证据一致性（T1）与方案 A 恢复（T4）

执行：Haiku。派发：leader A，2026-10-12。集成：leader A。基线：develop `9de4235a`；分支 `task/cf-fix-a-20261012`。依据：`docs/reviews/2026-10-12-cf2-library2-review.md`（在 `task/docs-20261012a`）C1、I4；你的反例在 `task/cr-cf2-library2-review-20261012` @ `6780a8aa`。先做 T1，再做 T4，两段分开提交。

## T1（C1，`packages/muyon_module_api/lib/src/ui/validation.dart` 约 494-512）
计算绑定的值与 `computedEvidence.state` 必须一致：`verified`（或其他声称有值的状态）却值为 null → 校验失败；`notDisclosed` 且值为 null 仍接受。把你的 GAP1 反例与 control 带进本分支作为 RED / 对照。

## T4（I4，`packages/muyon_module_api/lib/src/ui/publication.dart` 约 236、56）
按用户已批准的方案 A：重算失败进入 outdated 后，**只**允许受约束的本地 `editField` 触发重算；业务动作、确认、语义事件仍拒绝；撤权、只读、旧 token、迟到结果防护不变。
`ui_publication_coordinator_test.dart:494-502` 现把「失败后 edit 被拒」固化成断言——这是错误行为，按方案 A **精确改写这一条**（改为 editField 允许、业务动作仍拒），在提交说明与回报里写明理由；其余断言不动。

## 变异（必须做）
T1：去掉 state 与 null 的比较；把 notDisclosed 也一并拒绝（control 必须失败）。T4：outdated 时放行业务动作；outdated 时拒绝 editField。都必须被测试抓到。

## 约束
只改 `muyon_module_api`（及必要的 muyon_ui 测试）；strict analyze 零 info；`muyon_module_api`、`muyon_ui` 全量；不提交平台文件；不合 develop。

## 回报（固定 6 行）
1. RED 提交与 T1 / T4 各自失败首行　2. 修复提交（远端与本地一致）　3. 改动文件与行数；改写了哪条旧断言及理由　4. 变异结果　5. analyze 与两包全量（pass/skip/fail 及分类）　6. 未做或有疑问
