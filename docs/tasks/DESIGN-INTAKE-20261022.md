# DESIGN-INTAKE-20261022：研究、规格与统一 UI 归档

分支 `task/design-intake-20261022`；固定候选 `f4781e16ddf4e542b983fbd77f266a0071148255`。本执行者仅写文档，不改生产代码、不合 develop/main。用户已授权远端归档及按计划并行推进；具体代码工作由父任务另行指定，本表登记计划不代替派发、实现或验收。

原件、已定/建议及图号入口见[完整归档](../design/2026-10-22/README.md)，来源与 SHA-256 见[清单](../design/2026-10-22/sources.json)，[证据修正](../design/2026-10-22/EVIDENCE-NOTES.md)区分历史和当前候选。原编号保留；下表是原总纲的阶段映射，不新建重复主任务。

| 阶段 | 原编号与交付 | 依赖与验收 | 本分支状态 |
|---|---|---|---|
| 0 证据对齐 | U08/U13；候选、CI、设备、费用版本 | 完整 SHA、同候选 build/device/回执；I04 拒绝边界保留 | 远端与 CI 只读快照已归档；设备/费用 HOLD 未闭合 |
| A 本地证据闭环 | U01–05、U07/08/13；PX01–07/09/10、MU01/02/04/05 | 先冻结 source/task/intent；固定 PDF 导入→真实阶段→本地检索→原文版本页→回执；反例含失权、乱序、unknown、重复提交 | 计划登记，代码另行指定；未声明开发完成 |
| B 原生互动与配置 | U06、U09轻反馈、U10–12、U15–17；MU03/06–08、GB01–07 | A 契约；本地表单/草稿、模板建议、报告版本；幂等/CAS/返回恢复；群组入口不得假可用 | 规格与 UI 示例已归档；未实施/未验收 |
| C 生产闭环 | 原模型/搜索/工具、Agent 编排与费用证明任务 | 独立范围授权、有效预算及 production cost proof；两次 unknown 不重发 | 本轮禁止真实请求，不派发、不付费 |
| GR 离线研究 A | GR01/02/04/05/08 fixture | owner/admin/coordinator 分离；宿主队列、scope、根预算、拒绝/恢复反例 | 研究及任务原文已归档；实现另派 |
| GR 后续 B | GR03/06/07 | 前批通过；移交 epoch、证据/分歧汇总、三模式设置 | 计划；三模式无预选，不自动启动协作 |
| 后置专题 | MU09/10、群组真实实验、HTML/地图/插件/桌面 | 各自安全/许可/费用与独立评审 | 不捆绑本地首批，不扩权限 |

阶段 A/B 与现有 [Android 重构任务](muyon-android-refactor/planning/muyon-android-refactor-tasks-20261020.md)、[测试计划](muyon-android-refactor/planning/muyon-android-refactor-tests-20261020.md)及任务台账查重后由 Leader B/父任务登记具体分支、writer、基线与验收。不得把本设计计划表记成已实现功能。科研 Rule2Region、StepTrace、pre-combination-governance 保留各自项目/实验/证据边界，不合并成新项目。

归档验证（仓库根目录）：`python3 docs/design/2026-10-22/verify_archive.py`、`(cd docs/design/2026-10-22 && sha256sum -c SHA256SUMS)`、`git diff --check`。独立复审和实际命令结果见[执行报告](../design/2026-10-22/REPORT.md)。Linear 由另一个唯一执行者同步，本线程不写 Linear。
