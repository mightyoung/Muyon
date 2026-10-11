# HK-3 审查（leader A，2026-10-11）

提交 `79b03e8` · 结论：**通过，可合入**（数据库迁移）。

- 新增第 3 版迁移，只给 `contact`、`product` 装 INSERT / UPDATE / DELETE 触发器并补种已有行；第 1、2 版未动；schema 版本与摘要同步更新。两表数据没有 `project_id`（`supplier_core` entities），`native_project_id` 写 `NULL` 对应全局项目语义，符合 GB-3。
- 复跑：analyze 无问题；新测试 5 例通过。
- 变异：删掉第 3 版的 INSERT 触发器 → `creating a contact writes an upsert change record`、`a new contact reaches the host object catalogue` 失败；删掉补种语句 → 1 例失败。均被检出。
- 修复了 GB-3 缺口 G1：助手经通用写工具新建或修改的联系人、物料现在能进入投影目录。

HK-2 补记（执行者更正）：`planning_disabled` 变异未被检出的原因不是界面更早拦截，而是两条路径的界面结果相同（锁定、显示同一失败提示）；该检查作为兜底保留，结论不变。
