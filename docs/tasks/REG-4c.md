# REG-4c 询价按本体通用的写工具；宿主模式隐藏 Folio 自带助手

分支 `task/reg-4c-inquiry-record-tools` · 规格依据：[GROK-5 盘点](../reviews/2026-10-09-inquiry-ontology-cards.md) §2、§5；[ADR-0004](../adr/0004-module-contract-v2.md) §10.4、§12.1 Q3、Q7、Q8；[AI 原生界面方案](../design/ai-native-ui-redesign-2026-10-09.md) §4.4 · 执行：Codex（排在 AIUI-1 之后，并在 REG-4b 合入之后开始）· 审查：leader A（安全相关，另开一个审查子代理）

## 只做这些
1. 在宿主注册 4 个通用写工具：`inquiry.create_record`、`inquiry.update_record`、`inquiry.delete_record`、`inquiry.restore_record`。
   - 输入模式**按本体生成**：`type` 只允许首批 7 类（`supplier`、`contact`、`product`、`project`、`project_item`、`inquiry`、`quotation`）；`values` 的键必须是该类型的字段。
   - 修改、删除、恢复必须带 `expected_version`，版本不符就拒绝（乐观锁）；修改只提交改动的字段。
   - 写入前调用 `validatePayload`，执行时由 `Store.save` 再校验一次；`delete` 预览里列出引用这条记录的对象（`referencesTo`）。
   - 受保护字段与 Folio 一致（`merged_into`、`attachment_ids`、`source_attachment_ids`、`capture_mode`），出现就拒绝。
   - `quotation` 只开放字段白名单：报价日期、交期、质保、备注等非价格字段。价格、成交价、定标仍走 `record_quote` 和以后的 `award`。
   - 全部经过 ADR-0002 的确认卡或授权执行，写回执；效应为 `write`。
2. 覆盖清单（`coverage.dart`，按 ADR-0004 §8.2；GROK-2 初稿）：登记这 4 个工具承载的操作。`product_param`、`spec_*`、合并、定标、刷新记为 `deferred(<任务号>)`，并写明理由。
3. 宿主模式下隐藏 Folio 自带的对话助手（Q3），并彻底禁用 `bypass` 档。FOLIO-BYPASS 只是让它读作 `confirmWrites`，这里要从界面和代码路径上都去掉。
4. 实测并回报 GROK-5「未能静态确认」的前两项：撤回定标后是否恢复旧值；删除仍被报价引用的联系人会不会被拦截。如果发现会产生悬空引用，`delete_record` 要拒绝这种删除。

## 不做
- 不做卡片界面（AIUI-9）；不新增 `set_param`、`award`、`merge_into`；不改 Folio 的固定页面（页面冻结）。
- 已有测试不放宽；原始日志不进仓库。

## 验证
- 变异（每个都要让对应测试失败）：
  - (a) 去掉版本检查；
  - (b) 允许受保护字段；
  - (c) `quotation` 允许改价格字段；
  - (d) 宿主模式下仍显示 Folio 助手入口；
  - (e) 绕过确认卡直接写。
- `north_star_inquiry_test`、`inquiry_*`、`inquiry_write_tools_test` 原样通过；`flutter analyze`；宿主全量；`ci.sh` 的 inquiry 部分（Mac 截图例外按验证备忘录如实写明）。

## 回报
分支与提交哈希、4 个工具的输入模式、覆盖清单登记、Q3 的改动点、两项实测结论、验证摘要行、变异结果。
