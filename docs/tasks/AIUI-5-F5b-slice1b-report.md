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

## GREEN 实现（已写，NOT RUN；待调用者验证，不声称通过）

仅 `packages/muyon_module_api`。
- `edit_spec.dart`：scaffold 与 `uiEditSpecNotReady` 已移除。五类 spec 的 `rejectPayload`/`rejectInContext`/`validateSpec` 实现：null 仅 nullable；number 有限、integer 为安全整数(|v|≤2^53−1)、闭区间、step 网格 1e-9，不 round/clamp/truncate；date 严格 YYYY-MM-DD 公历往返、闭区间字典序；String 按 UTF-8 字节，host maxLength 须在 1..4096，谓词失败即拒绝；itemIds 去重拒绝、成员须在集合、上限 `UiCollectionLimits.rows`(200)、单选 ≤1、`normalize` 排序去重不可变。`usesTypedEdits(catalog)`＝仅 `library-2`。
- `plan.dart`：`UiComponentSchema` 构造运行时对 properties 中的 number/stringList 抛 `ArgumentError`（非 assert）。
- `validation.dart`：editField 在 library-2 走 spec（`edit_spec:<key>` 元数据、`edit_input` 事件类型/初值 payload+context、itemIds 键不得在 initialUiState、`view_business_input`）；uiState 绑定对 itemIds 键放行 `unknown_state`；其它目录与 sortRows 逐字旧规则。
- `state.dart`：library-2 editField 派发先核 spec.payloadType 与事件类型，nullable 且 payload==null 时才跳过粗类型，再 `spec.reject`，任一失败返回 invalid 且不动 state/override/rev；view 只写 viewValues/viewSelections 不增 rev；新增静态 getter `selections`/`selectionOverrides`/`viewSelections`；直接 `edit`/`selectView` 仅在当前 accepted plan 为 library-2 时受 spec 约束（view 键不可 edit），否则维持旧行为；`adoptExtracted` 对 itemIds override 恢复 `spec.initial` 并 rev++，标量层不变。
- 未做：collection validator/resolve（collection 绑定仍恒拒绝）、codec/restore/rebase、`rowObject`、Slider step 可表示性、任何 UI/apps。`workspace.dart` 未动。
- 测试：`ui_edit_spec_test.dart` 改为静态 getter、字面量 `'not_ready'` 负例；`rejectAll` 增加 selections/viewSelections/selectionOverrides 不变断言；新增 contract guards 组（properties 运行时拒绝、matchesUiValue、类型不符/坏初值/坏元数据、直接 edit/selectView 不绕过、无 library-2 plan 的直接 edit 保旧行为、nullable 不放行其它事件、adoptExtracted）。
- 穷尽性检查：`UiValueType` 仅 `matchesUiValue` 一处 switch；`BindingKind` 已在 1a 处理。
- 待调用者：`flutter analyze`、专项与全 API 测试、旧 UI 边界；若编译/断言失败请回传。

## 审查回归修复（已写，NOT RUN）

`ui_edit_spec_test.dart` 末尾 `review regressions: typed entry gates` 三例由 Codex 审查者新增（非 Claude 原测试），原断言未改；调用者先前实测 24PASS/3FAIL。仅 `packages/muyon_module_api`，未碰 collection/UI/restore/旧测试。
1. `UiNumberEdit.rejectPayload`：step 比值 `cells` 非有限（如 min0/max1e308/step1e-308、payload 1e308）先判 `off_grid` 拒绝，不转换。
2. `state.dart`：`selectView` 在 library-2 当前 plan 下，登记 spec 必须 `view==true` 且通过 `_specReject` 才写；未登记键保留旧默认 sort 映射（默认 String 规则）；`sortRows` 在 library-2 写不成功返回 `invalid`（旧目录保持原 always-applied）。`_setValue/_applyTyped` 现返回是否写入。validator：library-2 的 sortRows 若登记 spec 必须是 `UiStringEdit(view:true)`（否则 `edit_input`），并复用 `_typedEditErrors`（业务 draft 键报 `view_business_input`）；无 spec 保旧兼容。
3. `state.dart`：library-2 当前 plan 下 `edit` 对未登记键用默认 `const UiStringEdit()`（4096 字节上限），`_specReject` 先含 `validateSpec`；view 键不可 edit；未知键不写。无当前 library-2 plan 的直接 edit 仍走旧规则。
- 测试调整：nullable 其它事件用例改为两个独立键（`k` nullable 编辑键、`s` 的 `UiStringEdit(view:true)` 做 sortRows），保 sort null→invalid、sort `value`→applied(viewValues、rev 不变)、change null→applied；另断言非 view 登记 sort 键计划被拒、未登记键兼容。补 view 直接选择正例（bool/itemIds）与非 view itemIds 不可 selectView、4096 字节边界与未知键。
- 说明：`UiSessionState` 构造时对 itemIds 初值的去重规整发生在宿主快照尚未校验时，不代表初值合法；只有真实 validated plan 才能 dispatch。
- 未运行任何 flutter/analyze/test，待调用者跑全套。

## 调用者最终GREEN/审查/变异证据
真实Claude GREEN回合 result success/end_turn/exit0，29turns/217132ms；初稿24专项PASS。Codex审查者新增末尾3个回归（有限step比值溢出、注册non-view key直接selectView绕过、缺spec directedit越过默认4096B）实际24PASS/3FAIL/exit1，无编译错误；首次测试文件相对路径错误未写入的运行不计RED。三回归由Codex编写，修复和相关正例由同真实Claude完成，修复回合17turns/104617ms/result success/end_turn/exit0。Codex仅格式化/验证/报告/提交。

最终API105PASS/0FAIL（含typed29专项）、fatal-infos analyze无问题、旧UI边界与F5a21PASS/0FAIL。M1真实临时移除dispatch的typed spec payload拒绝门：20PASS/9FAIL/exit1，均行为断言失败；源码逐字恢复后typed29PASS/exit0。原始日志/tmp/aiui-f5b-logs，不入仓。协议f29819b CI run38022616528 success；本typed提交CI尚待推送后核验。

收敛边界：library2注册的sortRows spec必须view String，不注册保旧sort映射；default String的直接编辑仍受4096B约束；typed direct selectView不能改注册non-view业务输入；步长ratio非有限拒绝。旧catalog string-only不变。collection绑定仍全部被validator拒绝，metadata只用于itemIds membership；F5c存取/恢复/publication未实现，library2尚未加入renderer或应用目录。不得据本GREEN宣称F5b33组件完成。
