# UI-3b 草稿、动态现场持久与返回

> 本次代码层实现与验证见 [UI-3b 实测摘要](../validation/ui-3b-code.md)。持久投影、人工覆盖、版本恢复与返回已实现；云部署/浏览器交互仍按用户要求暂缓，原生实机尚未验收，不能将整个任务标为完成。

## 目标、依赖与边界

依赖 UI-3a/4a；不必等待训练或 UI-4b 真实模型胜出。持久用户编辑、界面位置与可继续步骤，返回/刷新不丢；沿当前 Shell 增量实现，不提前整页换壳。不能把 agent_drafts 的内存流式回复草稿改成业务库，也不重建 K-4 任务系统。

## 文件、接口与复用

新增 `apps/muyon/lib/platform/ui_workspace_store.dart`、`screens/dynamic_workspace.dart`，复用 FoundationRepository、TaskRecords、现有 storage/bootstrap、assistant_page。纯契约中新增 `UiWorkspaceStore`：`Future<StoredUiWorkspace?> load(String surfaceId)`、`Future<bool> save(StoredUiWorkspace value, {required int expectedRevision})`。StoredUiWorkspace含task/surface、schema/catalog/snapshot版本、提取层、userOverrides、步骤、选中记录和返回/滚动锚点。预览采用同口浏览器夹具存储，不能借此宣称产品 SQLite 已迁 Web。

原生如需一张最小增量状态表，用开工时最新未占版本迁移；1～12历史事实不重写，不一口气新增设计文档的所有建议表。跨对象正文仍在领域库；这里只持久投影/用户覆盖/继续位置，恢复先核实际回执。

## 验收与测试

`edited_value_survives_patch_reload_and_back`：qty人工12，提取层刷新建议11，展示仍12；返回/浏览器刷新/SQLite重开保持12，选择采用或清除覆盖必须用户动作。`stale_schema_keeps_readable_draft`：schema或节点变化保存可读旧值并提示，不能静默删字段。`unknown_operation_is_not_replayed`：先查既有 receipt，再决定继续未完成集合。磁盘迁移/事务失败保旧数据；scope不因恢复变宽。

新增 host `test/ui_workspace_store_test.dart`、`dynamic_workspace_return_test.dart` 与 preview `test/workspace_restore_test.dart`/浏览器reload场景；复跑 agent_resume、import_recovery、task_events_test.dart既有测试。

## 实施顺序

- [ ] 先编辑→补丁→返回/重开、旧schema和未知回执的实际失败测试。
- [ ] 最小 Store及平台实现；原始提取与人工覆盖分层，原子保存稳定ID/版本。
- [ ] 同口浏览器夹具存储重开测试与云真实 SQLite host 回归分别记录，不能相互替代。
- [ ] 运行上述切片测试和云交互 smoke，通过后可推进文件导入。锁屏/进程被杀由最终原生清单验。
- [ ] 独立审查/提交；关闭动态页仍可读草稿及回执，不重放已成功写入。

## 通用门禁

本任务为待 leader 复核的派发草案，尚未开工；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。
