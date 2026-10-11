# HK-4 审查（leader A，2026-10-11）

提交 `c431fd5` · 结论：**通过，可合入**（只加测试；5 个缺口完成 3 个）。

- 完成 G2（`_recordResults` 提交失败事件保留）、G3（`_external` 排除纯本地写）、G4（整卡预标记并集先于审查）。复跑 3 例通过；审查方变异：去掉 `!ctx.tools.isPureLocalWrite(request)` → 1 例失败，检出（执行者另报三条变异均检出）。
- G1（lateCancel 后不再 `model.advance`）：可达窗口位于注册表最后一次取消检查之后、执行器读取取消标记之前，现有测试接缝无法稳定命中；记为「当前不可测」，拆分时保持该分支原样搬运。
- G5（`_correctableRead` 双读）：access 由 effect 推导，`access=read 且 effect=write` 不可构造；按执行者建议改测「写工具返回 invalidArguments 时任务失败且不再发起模型请求」，已派 OC-10。
