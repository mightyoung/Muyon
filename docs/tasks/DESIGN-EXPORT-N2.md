# DESIGN-EXPORT-N2：导出生产接线与 N2 删除确认执行设计

执行：ChatGPT（只读设计；原派 Sonnet，Sonnet 改做 C6-REDO）。派发：leader A，2026-10-12。设计任务，不写实现；任务说明草稿以文字回报，由 leader A 入库。基线：develop `ab5506c3`；分支 `task/export-n2-wiring-design-20261012`。

## 背景
- 导出：CR-17 设计（`docs/design/research-local-export-facade-2026-10-11.md`，若不在 develop 则在 `task/cr-15-17-chatgpt`）拆为 LE-01～14。develop 已含 LE03 准备器、LE06 账本与只读恢复的有界实现，但**缺生产调用方**，旧手工 export 路径仍在。需走通：受控 reader → 准备 → 宿主审批 → 生成 → 另存为 → 账本 → 回执，含恢复与取消。
- N2：删除预览（PR #60 `864fdb74`、PR #66 `dcf79f3b`，已进组合 `326ca138`）只证明预览与零写入；预览本身不授权删除。需接 digest / CAS、宿主审批、确认执行、可追溯回执。

## 要回答
1. 导出：现状盘点——LE-01～14 每片在 develop 的实际状态（已合 / 在哪个分支 / 未开工），每个阶段的实际调用入口、数据与权限绑定、失败状态；旧手工 export 路径如何收口（保留 / 改走门面 / 删除）。LE06 遗留：target 能力与实际写入回调强绑定、只读恢复 check 活性、content BLOB 大小与保留、rawError 脱敏、partial_export 呈现、独立 save 模型投影、多实例并发。
2. N2：预览 → 确认执行的完整链：预览后数据变化、跨 scope、重复请求、取消、迟到结果怎么处理；与 REG-3c 删除工具（deleteDigest）的关系，避免两套删除语义。
3. 产出：剩余实施任务的 `docs/tasks/*.md` 草稿（每项 ≤1 天、测试先行、文件边界、依赖、必须的变异），提交到本分支。

## 回报
现状盘点表；设计要点；任务草稿清单与依赖图；未决产品问题（给推荐）。
