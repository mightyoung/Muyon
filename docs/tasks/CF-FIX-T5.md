# CF-FIX-T5：旧结果标注与逐值 freshness

执行：Haiku。派发：leader A，2026-10-12。集成：leader A。基线：你的 CF-FIX-A `task/cf-fix-a-20261012` @ `76e4db71`（已在组合 batch 12b 跑 CI；合入 develop 后改为最新 develop）；分支 `task/cf-fix-t5-20261012`。依据：`docs/reviews/2026-10-12-cf2-library2-review.md`（在 `task/docs-20261012a`）C2；交接要求「旧值必须呈现为『旧结果 / 上次计算』，成功发布前不恢复有效状态；semantics 同样需要标明」；FactState（可信度）与 freshness（新鲜度）分轴。

## 关于 conflict（你的疑问）
确认：`conflict` 归入「声称有值」——现有渲染语义里 conflict 是带值并标冲突的（renderer 测试有 conflict-with-value 用例），计算结果为 conflict 时必须带值。T1 实现保持不变。

## 要做
1. 把你在 CR-CF2-LIB2 写的 `an outdated surface labels its previous values as an old result` 反例带进来作为 RED。
2. 引入逐值 freshness（与 FactState 分开的轴），至少区分「当前」与「上次计算（重算失败或进行中后的旧值）」；由发布协调器 / surface 在重算失败或 outdated 时设置，成功发布后恢复为当前。
3. `muyon_ui` 渲染：旧值显示「旧结果」或「上次计算」标注；semantics label 同样包含；不得把旧值显示成当前值；不影响 notDisclosed / notApplicable 的现有展示。
4. 方案 A 行为不变：outdated 时只放行本地 editField；业务动作仍拒绝。

## 变异（必须做）
outdated 时不设 freshness；渲染忽略 freshness；semantics 漏掉标注。都必须被测试抓到。

## 约束
只改 `muyon_module_api` 的 ui 层与 `muyon_ui` 的 dynamic 渲染；strict analyze 零 info；两包全量；覆盖率分母变化写进回报；不提交平台文件；不合 develop。

## 回报（固定 6 行）
1. RED 与失败首行　2. 实现提交（远端与本地一致）　3. 改动文件与行数　4. 变异结果　5. analyze 与两包全量（pass/skip/fail）　6. 未做或有疑问
