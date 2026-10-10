# Real Claude cross review

Requested immutable scope: b0bb71702b775be42c7837e251d6c5dbf9b7d17e. Actual model claude-sonnet-5-5; CLI 2.1.295; effort low; output cap 24000; acceptEdits permissions preserved; independent session ae231cfe-5f1e-4517-81e9-edd767fb5c57. result subtype success, is_error false, stop_reason end_turn, 17 turns, duration 99626ms; shell exit recorded separately. Raw logs remain outside Git.

Important limitation: three read-only Bash permission denials prevented Claude from verifying Git SHA/diff. It read current source files and grep excerpts; it did not read the final proposal or full tests, and did not run tests. Its no-blocker result is a limited source review, not full acceptance. The requested source files were unchanged from b0bb717 during this call; concurrent capture work changed only surface.dart and its new test outside review scope. Capture and later edits remain unreviewed.

## Raw completed report

**审查结论:固定 HEAD b0bb71702b775be42c7837e251d6c5dbf9b7d17e 上没有发现阻断问题。** 我只读了文件,没有运行测试,所以不声称 PASS。

**HEAD 核对的局限:** 我没能执行 `git rev-parse` 和 `git diff`,所以没有确认 worktree 的 HEAD 就是上面的 SHA,也没有读 98af2a4..b0bb717 的 diff。结论基于该 worktree 当前文件内容。

**实际读过的文件**
- `muyon_module_api/lib/src/ui/` 下:`validation.dart`、`collection.dart`、`edit_spec.dart`、`state.dart`、`snapshot.dart`
- `muyon_ui/lib/src/ui_components/` 下:`inputs.dart`、`layout.dart`(只读 Tabs 和 Disclosure)
- 对 `ui_collection_test.dart`、`ui_business_view_guard_test.dart`、`aiui5_controlled_inputs_test.dart` 和 slice1c 报告只做了 grep,没有通读。
- 没读 `docs/design/aiui-f5-contract-proposed.md`、`slice2a-report.md`、`business-view-review.md`。

**你点名的几项,逐条结果**

| 检查项 | 结果 |
|---|---|
| business-only 按钮引用 view spec 且在 `actionContext.draft` 中 | `validation.dart:258-265` 在事件循环里拒绝 `view_business_input`。这段在 `validateUiNode` 里,`validateUiPlan` 调用它,两条路径共享,不止 `editField`。 |
| 旧 v1 和 legacy 行为被放宽 | 没有。该检查受 `usesTypedEdits` 约束,collection 在非 typed catalog 下仍整体拒绝(`collection_catalog`)。 |
| collection 非法 shape/source 覆盖 required fact | 不会。`validation.dart:129-130` 要求 `nodeErrors.isEmpty` 且 `_collectionErrors` 为空,才把 cell 算作 shown。shape 错误计入 nodeErrors,过期 source 计入 collection 错误。 |
| 64KiB 元数据 | `_metaBytes` 只含 id、label、cell 的 kind 和 id、`row.object`,不含值。注释已写明"执行层澄清待父任务审查",没有冒称冻结原文。 |
| computed 的 state/unit/sourceRefs 与来源 digest | 校验要求 `computedEvidence` 存在,其 `sourceRefs` 逐个过 `_sourceInvalid`(含 digest 比对)。 |
| `rowObject` 同 plan、exact node、registry ID、稳定 itemId | 已核对 `state.dart:78-122`。plan 取自 `_currentPlan`,node 用 `identical` 比较,要求 typed catalog、恰有一个 collection 绑定、itemId 唯一匹配、object 与某个 fact cell 的 object 一致、所有 source 的 digest 与当前一致。没有新 router,`openRow` 只走 `dispatch`。 |
| 受控 widget 不自己改 host 值 | Choice 的 ID 模式、MuyonTabs 受控模式、Disclosure 受控模式都只回调,不写本地状态。 |
| disabled / readOnly | `state != ready` 或缺回调时全部禁用。 |
| Choice 同标签重排 | 用 optionIds 作 `ValueKey`,同标签不同 ID 的测试在 `aiui5_controlled_inputs_test.dart:11`。我没看到"重排"专项测试。 |
| 排序 | `UiItemIdsEdit.normalize` 用 `toSet().toList()..sort()`,即 `String.compareTo` 升序,与父任务裁决一致。`ui_business_view_guard_test.dart:84` 已用 BMP 与补充平面字符锁住该行为。没有改成 UTF-8 排序。 |

**真实发现:只有低优先级,没有 CRITICAL/HIGH。** 已通过 ReportFindings 提交 4 条:
1. **低,`inputs.dart:66`**
   - Choice 多选 ID 模式下 `toggle` 原样带上 `optionIds` 里不存在的已选 ID。
   - 触发例:`selectedIds={'a','gone'}`、`optionIds=['a','b']`,点 'b' 会发出 `{'a','gone','b'}`。host 的 `rejectInContext` 返回 `unknown_item`,整次编辑被拒,用户选不动。
   - `selectedLabels` 已有"已失效选项"文案,说明这种状态是预期会出现的。
   - 建议:ID 模式下过滤掉不在 `optionIds` 的 ID,或明确由 host 先清理,并补测试。
2. **低,`inputs.dart:36`**
   - Choice 没有 `optionIds` 与 `options` 等长、`optionIds` 唯一的断言。
   - 触发例:`optionIds` 比 `options` 短会在 build 时抛 `RangeError`;重复 ID 会得到重复 `ValueKey` 并联动选中。
   - 只影响直接用 widget 的调用方,也就是后续 adapter。
3. **文档,`snapshot.dart:71` 和 `:150`**
   - "NOT READY / 尚未被任何东西读取"的注释已过期,`UiComputedEvidence` 和 `editSpecs` 现在都被校验器和 `rowObject` 读取。
4. **nit,`layout.dart:235`**
   - `didUpdateWidget` 用 `oldWidget.selectedIndex` 而不是新值。没发现会产生错误显示。

**这次审查没覆盖的**
- 通读完整 `ui_collection_test.dart` 和 `aiui5_controlled_inputs_test.dart`;
- 对"disabled 状态下点击不触发回调"逐用例核对。

按报告,当前没有 33 目录 adapter、capture 和 F5c 生产切换,这部分我没有评价,也没有把它当作已完成。

## Native triage

Unknown selected IDs remain a whole-payload rejection as specified; silently filtering them in the Widget would change the frozen contract. The host owns stale-selection recovery; adapter must not pass unvalidated initial selections. Choice length/uniqueness defense and obsolete scaffold comments are actionable low-priority follow-ups. The old selectedIndex assignment preserves the last displayed controlled index if transitioning to uncontrolled; current rendering reads the new controlled value and old uncontrolled shrink behavior stays tested.
