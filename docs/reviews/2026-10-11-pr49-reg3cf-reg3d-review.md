# PR #49（REG-3c-F + REG-3d）独立复审（CR-15，ChatGPT）

固定 head `ee831084`；云端只读，未运行测试或变异；核对了远端 push CI 38138476277 与 PR CI 38138500685 均 success。原稿由用户转交，leader A 整理入库。

**结论：可合入。** 无 Critical / Important；1 项 Minor。CR-13 的 I-1、I-2、N-1 按 REG-3c-F 约定范围可关闭；N-2、N-3 仍按任务书延期。

- **I-1 关闭**：`cite` 带 `evidence.objectType` 进领域；`requireOutlineEvidence` 分查 entries/notes/runs，实际存在类型须恰一种且匹配，run 查数据库 `accepted=1`；检查在事务内、`checkBeforeEffect` 前；旧 `add_outline` 也验证类型。测试经真实 `importResult` 造 entry/run 同号。**关闭边界**：outline 仍存裸 ID（带类型持久身份按任务书延期），例如先引用 `note:n` 后导入并接受 `run:n`，导出与详情的取证顺序不同仍可能不一致——不判本次未修。
- **I-2 关闭**：事务回调内同步 `_report` / `resolveCurrent` 生成本次引用与摘要，事务外不再替换；删除保留已捕获引用。测试在 A 提交（`autocommit == true`）后插入 B 更新 / 删除再放行 A。
- **N-1 关闭**：按移动前后 `position` 差异生成 `moved`，无变化时摘要「已在首位 / 末位，位置未变化」、空 changes；四个边界用例。
- **REG-3d 五个写分支**均为：同步事务 → `requireCurrent` → 业务前置与期望值 → `checkBeforeEffect` → 领域写入 → 回执快照。`update_project`（摘要覆盖 title/question/nextStep）、`set_note_entry`（note 整行摘要，清除须显式 null）、`create_task`（领域生成 ID、`expectedRevision: 0`）、`revise_task`（`expected_revision` 须等于选定 revisionRef 与当前 MAX）、`confirm_binding`（六字段目标摘要）。两个读工具不扩大写范围。
- 领域补丁只限 `applyBindingChoice` 与 `saveTask`（另有 REG-3c-F 必要的 `outline_store` 类型验证）；schema v10 补 project / note 日志触发器与种子；`binding.insert` 仍 deferred；任务规格白名单五字段。未发现删减或放宽测试（两处版本号迁移有理由）。

## Minor
- **M-1**：`reg3d_receipt_snapshot_test.dart:265-268`、`reg3cf_receipt_snapshot_test.dart:154-158` 重读 `receiptFor(invocationId)` 后只断言 `succeeded`，精确比较用的是当次返回 `result`；持久回执的 `objectRefs`（`contentDigest`、`revisionRef`）未精确核对。建议补：`receiptFor(...).result.objectRefs` 与 `committedA` 完整 JSON 相等。→ 派 opencode OC-18。

## 记录的非阻塞边界
`confirm_binding` 的竞争候选集合不冻结：批准确认 (D,P) 后刷新导入新增候选 R、D 字节与 P 六字段不变，旧审批仍可确认 P 并删除 Q/R（`ambiguous` 只记是否 >1）。符合 GB-2「选择目标后删除竞争候选」语义，工具说明已告知；建议以后用一条刷新导入测试锁定，若产品要求候选集合变化也需重确认，再加集合摘要。
