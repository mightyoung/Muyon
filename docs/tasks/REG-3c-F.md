# REG-3c-F：REG-3c 合入后补修（I-1、I-2、N-1）

执行：Codex（**在 REG-3d 之前做**：REG-3d 的新写工具会复用 `_outlineWrite` / `_report`，先修好再接）。派发：leader A，2026-10-11。基线：最新 develop（batch m 合入后，含 REG-3c-T）。分支 `task/reg-3c-fixes`。依据：`docs/reviews/2026-10-11-reg3c-postmerge-review.md`。

## I-1 cite 证据类型绑定
- 在同一写事务内、`checkBeforeEffect` 之前，按选中引用的**类型**验证具体证据：entry 查 entries、note 查 notes、run 查 runs 且 `accepted=1`；领域层不再用裸 ID 跨表 `UNION ALL` 猜。
- outline 仍只存裸 ID：同项目存在**其他类型**同 ID 对象时，工具边界拒绝（歧义），不静默写入。不改存储结构（带类型证据身份留作后续，回报里写明）。
- 测试：同项目 `entry:x` 与 `run:x`（经结果导入产生），只选 section+run，run 未接受 / 已接受各一例 → 都拒绝、零写入、零日志增量；无重号的未接受 run 拒绝；无重号的已接受 run、note 正对照可写。
## I-2 回执在事务内固定
- 在同一同步写事务内生成本次返回的引用、内容摘要与变更集合；事务外只组装回执，不再 `resolve` 最新状态替换。
- 测试：A 提交后、回执形成前插入 B（更新同一段落 / 删除同一段落）→ A 的回执摘要等于 A 写入后的状态，B 删除时 A 仍报 succeeded。
## N-1 边界移动
- 首段上移、末段下移、单段落移动：仍 succeeded，摘要写明「已在首位 / 末位，位置未变化」，`changes` 为空、日志无增量。

## 要求
- 每项先 RED 后修；每项至少一处变异被抓到（I-1：恢复跨表查找；I-2：恢复事务外 resolve；N-1：恢复原摘要）。
- 不改授权、确认、回执身份与防重放；N-2、N-3 不做。
- strict analyze 零 info；research_module 与 `apps/muyon` 全量测试；不提交 pub get 改的平台文件。

## 回报（固定 6 行）
1. RED 提交哈希与 I-1/I-2/N-1 各自失败第一行　2. 修复提交哈希（远端与本地一致）　3. 改动文件与行数　4. 变异结果　5. analyze 与两包全量测试（pass/skip/fail）　6. 未做或有疑问
