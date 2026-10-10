# AIUI-5 F5b 切片 1b 报告：typed edits RED（NOT RUN）

状态：**测试与 not-ready scaffold 已写，未运行任何 flutter/analyze/test**。以下“预期失败”由读码推得，须调用者实跑确认；编译失败不算 RED。技术依据为 leader 技术采纳记录（非用户逐条审定）。

## 文件
新增：`packages/muyon_module_api/test/ui_edit_spec_test.dart`、`lib/src/ui/edit_spec.dart`、`lib/src/ui/collection.dart`、本报告。
修改：`plan.dart`（`UiValueType.number/stringList`）、`validation.dart`（`matchesUiValue` 两分支，number=有限 num，stringList=全 String 的 List）、`snapshot.dart`（`DataSnapshot.editSpecs/collections` 可选字段，构造与 `copyWith` 透传）、`ui_contract.dart`（export 两新文件）。
未改：`state.dart`、validator 的 editField gate、旧测试/fixture/checker、apps、muyon_ui。

## Scaffold（显式 NOT READY）
- `UiEditSpec` 五类（String/Bool/Number/Date/ItemIds）、`UiEditContext`、`UiColumn/UiRow/UiCollection/UiCollectionLimits` 仅声明且不可变。
- `rejectPayload/rejectInContext/validateSpec` 一律返回 `'not_ready'`（常量 `uiEditSpecNotReady`）。无任何生产路径读取 editSpecs/collections。

## 测试覆盖（真实 `validateUiPlan` + `UiSessionState.dispatch`，无 fake）
bool；number（step 网格、非整数 finite 接受、越界、NaN/±Inf、off-grid 不 round、integer 的 2^53−1 与 2^53 边界）；nullable（仅声明时 null 通过）；date（边界含、2026-02-30、格式、非 String）；decimal String 谓词（'3' 通过，'oops' '' '.' '3.' 拒绝，不写 state/override/rev）；String maxLength 按 UTF-8 字节 N−1/N/N+1；view（只写 viewValues、不增 rev、与 actionContext.draft 冲突报 `view_business_input`）；itemIds（独立存储、去序规范化、重复/未知/类型错整体拒绝、单选 ≤1、view 选择）；初值须满足自身 spec；五类 `validateSpec` 有效/无效元数据；纯 `rejectPayload/rejectInContext`；旧目录（minimal-1/dynamic-1/library-1）即使登记 spec 仍 string-only（对照，应当现在即过）。
每个 reject 断言都与同一测试内的 accept 配对，防止在 scaffold 上空过。

## 预期真实 RED（行为断言）
- 所有 library-2 typed 用例在 `expectPlanValid()` 失败：旧 gate 因 `schema.events != string` 报 `edit_input`（itemIds 另因 `unknown_state`）。
- 字符串谓词/maxLength 用例：plan 虽 valid，但 `accept('3')` 之后 `rejectAll(['oops',…])` 现在会被 *接受*（旧 gate 无 spec），断言 `invalid` 失败。
- `validateSpec` 有效用例失败（`not_ready` 非 null）；无效用例因返回 `not_ready` 触发 `isNot(uiEditSpecNotReady)` 失败。纯 `rejectPayload` 用例同理。
- `view_business_input` 用例：错误列表不含该码。
- 预期通过的对照：legacy 目录 3 例；`Obs`/拒绝不变性辅助无副作用。

## 待 GREEN 的精确接口差异（测试已按此命名，经 `dynamic` 访问）
- `UiSessionState.selections` : `Map<String,List<String>>`（当前值，字典序）
- `UiSessionState.selectionOverrides` : 含被用户改动键的集合/列表（`contains(key)`）
- `UiSessionState.viewSelections` : `Map<String,List<String>>`
- itemIds 的键不在 `initialUiState`；validator 的 `unknown_state` 需认 `editSpecs[id] is UiItemIdsEdit`；`resolve(uiState k)` 对 itemIds 返回 null。
- 未实现：`rowObject`、collection validator、`allowedValues`、`UiCollectionLimits` 字节上限、Slider/step 可表示性（`slider_step_unrepresentable`，属组件绑定）、codec/restore/rebase。

## GREEN 顺序建议
1. 实现各 spec 的 `rejectPayload/rejectInContext/validateSpec`（纯函数，先过纯测试）。
2. validator editField 分支（仅 library-2 走 spec；旧目录逐字不变）与 `view_business_input`。
3. `UiSessionState.dispatch` library-2 的 nullable 前置顺序与 spec 派发、itemIds 存储 getters。

## 调用者待补
实跑 `flutter test test/ui_edit_spec_test.dart`，记录失败分布；并跑全 API 套件与 analyze，确认 scaffold 未破坏旧 76/76（尤其 `UiValueType` 新值、`copyWith`）。

## 调用者实际RED
真实Claude CLI2.1.295/claude-sonnet-5-5，effort low/24000，同session c440f713-f643-41ac-861c-98d2fa72fe0b，result success/end_turn/exit0，25 turns/154960ms。调用者用缓存SDK/no-pub专项测试实际3PASS/14FAIL，exit1；无编译错误或NoSuchMethod，typed计划接受断言、日期/decimal/maxLength非法文本被现有dispatch接受等真实行为失败；3个旧目录对照通过。not_ready脚手架正例失败单列，不据此虚构14个独立缺陷。原始日志/tmp/aiui-f5b-logs不入仓，GREEN后完整API/旧UI边界/analyze再验证。
