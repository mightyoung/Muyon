# REG-3c 合入后静态复审（CR-13，ChatGPT）

基准 develop `9172e21`。云端只读，追踪了领域存储、结果导入、宿主事务、回执与变更日志；未运行测试或变异。原稿由用户转交，leader A 整理入库，代码位置以原稿为准。

**结论：需补修。** 2 项 Important、3 项 Minor；无已证实 Critical；保留级联删除快照修复，不建议回退。

| 编号 | 级别 | 问题 | 位置 | 处理 |
|---|---|---|---|---|
| I-1 | Important | `cite` 执行时只传裸 `evidence.objectId`，领域层在 entries/notes/已接受 runs 间 `UNION ALL` 查找，outline 只存裸 ID。结果导入允许 `runId` 与同项目 entry 同号（`exchange.dart:1028-1049,1074-1109`），`requireCurrent(run)` 不要求 `accepted=1`（`research_module.dart:543-553`）→ 用户批准引用 `run:x`，实际写入并展示 `entry:x`。只补「运行须已接受」不够 | `module_tools.dart:443-454`、`outline_store.dart:106-135`、展示 `research_module.dart:731-755`、导出 `exchange.dart:1150-1157` | REG-3c-F |
| I-2 | Important | `_outlineWrite` 事务提交后，`_report` 才重新 `resolve` 不带摘要的 `ObjectRef` 取最新状态；其间排队的合法写入 B 可让 A 的回执携带 B 的 `contentDigest`；B 若删除对象，`resolve(...)!` 抛错使已提交的 A 报 interrupted。违背 ADR-0004 陈旧状态保护（`0004:328-329`）；宿主写结果校验只查模块与项目 | `module_tools.dart:558-588`、`storage_manager.dart:31-54`、`host_tool_registrar.dart:28-45` | REG-3c-F |
| N-1 | Minor | 首段上移 / 末段下移 / 单段落移动时领域直接返回，工具仍报「已移动提纲段落」 | `outline_store.dart:69-84`、`module_tools.dart:389-400,573-574` | REG-3c-F |
| N-2 | Minor | 删除确认绑定了级联摘要，但 `read_object(section)` / `outline_sections` 只返回 `deleteDigest`，确认卡不能逐项核对待删关联 | `module_tools.dart:101-120,194-201`、`agent_dispatch.dart:250-257` | 排队，随确认界面改进 |
| N-3 | Minor（既有债务） | 持久回执 `toJson` 不含逐项 `ChangeOp`，重读后删除语义丢失 | `muyon_module_api/lib/src/tools.dart:75-120`、`tool_registry.dart:1047-1084` | 排队，回执契约版本化 |

## 核查通过
- 摘要未漏 `position` 或级联引用：add/move 用含七字段的顺序摘要；update/cite 用 `SELECT *` 整行；remove 用链接整行；delete 用段落整行＋同一 `WHERE section_id=?` 集合的链接整行，摘要核对、写前检查与删除在同一同步事务回调内。`level` 不是父子关系，不算漏删。
- 同名标题、范围与项目一致性在事务内检查；未发现正常数据下跨项目写入。
- 防重放（invocationId / idempotencyKey）与 sections、outline 变更日志触发器都在；科研 `change_log(project_id, operation_id)` 是导入记录，不要求具名工具伪装导入（GB-3 已区分）。
- 现有测试不只正路径：已含批准后 / 排队中引用增删换改，及无关 / 重复引用不误失效（`reg3c_outline_tools_test.dart:655-848`）。四类「重放」测试目前以旧范围 `throwsStateError` 结束，未真正走到回执重放分支。

## 建议补测（M2–M4 之外）
必补：同项目 `entry.id == run.id` 只选 section+run（已接受 / 未接受各一）；A 提交后、回执形成前 B 更新或删除同一对象；无重号未接受 run 拒绝、已接受 run 与 note 正对照。应补：只改邻段 `position` 或内容使旧顺序摘要拒绝；update 多链接 / move 交换两行时 `changes` 精确；边界移动与重复 cite 无变化时 `changes` 与日志增量为空；多行更新 / 级联删除中途失败整体回滚；成功删除后重读持久回执。
