# 失败矩阵（需求第十二节）

日期：2026-10-04，`feat/a-acceptance`。每一行把需求里的一个失败场景对应到自动测试；"实机"列只有在真机执行后才能填写。自动测试通过不代表实机通过。

运行：`scripts/verify.sh`（全部包静态分析 + 全部测试；唯一允许的失败是已记录的 inquiry `desktop settings` golden 差异）。

| 场景 | 要求 | 自动测试（文件：用例） | 状态 | 实机 |
|---|---|---|---|---|
| 离线 | 模型不可用时仍能阅读、编辑、检索、管理本地资料；无数据外发 | `acceptance_failure_matrix_test`：offline；`search_test`：offline Chinese bigrams…；`personal_agent_test`：default missing-model fallback… | ✅ T | 未验证 |
| 重复导入 | 不重复创建、不显示虚假成功 | `storage_recovery_test`：domain commit interrupted… repairs once；`import_recovery_test`：recover binds once；`public_services_test`：inbox restart… excludes accepted duplicates | ✅ T（研究包重复导入待 C4） | 未验证 |
| 两项目隔离 | 范围不扩张、不串项目 | `foundation_scope_test`：empty workspace cannot inherit…；`workspace_binding_test`；`qa_scope_test`：citation outside frozen evidence… | ✅ T | 未验证 |
| 首次导入中断 | 意图＋回执＋对账，中断后据回执恢复 | `storage_recovery_test`；`import_recovery_test`（冲突隔离、放弃前核对回执） | ✅ T | 未验证 |
| 数据库升级 | 受管理迁移；高版本/漂移/失败阻止模块，不清库 | `storage_manager_test`；`schema_catalog_test`；`foundation_integration_test`：host v1 upgrades in place…；`acceptance_failure_matrix_test`：drifted research database… | ✅ T | 未验证 |
| 索引过期 | 失效即不可取材，明确显示 | `search_test`：…stale input and reindex；`public_services_test`：…stale source detection；`foundation_scope_test`：changed knowledge source is absent… | ✅ T（模块对象删除→索引失效待 D3b） | 未验证 |
| 原文换版 | 保留旧引用，缺原文/无法唯一定位明确提示 | — | ❌ 待 C3 | 未验证 |
| 取消 | 说明已发生与未继续部分；本地取消不冒称远端撤销 | `tool_registry_test`：effect point…（4 项）；`personal_agent_test`：cancel while model running…；`qa_scope_test`：cancel during HTTP…；`outbound_ledger_test`：HTTP failure and cancellation… | ✅ T | 未验证 |
| 错误状态 | 失败与中断明确显示；"已开始/局部完成"不显示为成功 | `execution_recovery_test`：restart interrupts unfinished records…；`outbound_ledger_test`：…becomes interrupted；`module_registry_test`；`projection_service_test`（errors 可见） | ✅ T（界面呈现待 B） | 未验证 |
| 备份/恢复 | 一致状态，不复制写入中的裸库；文件缺失不显示完整成功 | `backup_service_test`；`acceptance_failure_matrix_test`：backup, later changes, restore, reopen… | ✅ T | 未验证 |
| 跨库提交 | 不假定多库原子提交；投影可重建 | `projection_service_test`；`import_recovery_test` | ✅ T | — |
| 文件传输 | 传输校验通过≠业务导入；五态独立 | `public_services_test`：transfer manifest…/forged member claims… | 🟡 T（五态与加密待 D1/D2） | 未验证 |
| 远端执行 | 任务包不授予执行权；不重复执行 | — | ❌ 待 C6/D5 | 未验证 |
| 完整研究包 | 不同本地 ID 往返、来源身份不变、引用闭合、重复导入、并发分叉 | `research_package_test`（部分） | 🟡 待 C4 | 未验证 |
