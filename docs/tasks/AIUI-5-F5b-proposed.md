# AIUI-5 F5b 任务书：核心契约 + 33 组件适配（proposed / 未采纳）

状态：**proposed / 未采纳**。仅在父任务采纳 [aiui-f5-contract-proposed.md](../design/aiui-f5-contract-proposed.md) §9 的 6 项后、且另行授权实现时才可开工。基线 `cf672164e4f6c3e7beea8029c8be735e33c3bf19`；开工时重取 develop 完整 SHA。分支建议 `task/aiui-5-f5b-contract-adapters`。

## 1. 范围

交付：`UiEditSpec`、`BindingKind.collection` 与 registry、`UiValueType.number/stringList`、`UiLocalAction.openRow`、library-2 目录、stream v2 门槛、33 组件适配表、行详情的 session 侧与 `onOpenObject` 回调。**不含**：重算/发布、workspace、planning/stream provider、屏接线（属 F5c）。不得新建 runtime/validator/router；不放宽 `isUiScalar`；不改 library-1 目录。

## 2. 文件所有权（F5b 独占，同一时间唯一 owner）

修改：`packages/muyon_module_api/lib/src/ui/{snapshot,plan,validation,state,stream_protocol,stream_compiler}.dart`、`packages/muyon_module_api/lib/ui_contract.dart`、`packages/muyon_ui/lib/src/dynamic/surface.dart`。
新增：`.../ui/edit_spec.dart`、`.../ui/collection.dart`、`packages/muyon_ui/lib/src/dynamic/catalog_library2.dart`、`.../dynamic/component_adapter.dart`；测试见 §4。
冻结不改：`catalog.dart`（library-1）、`workspace.dart`（F5c）、旧 F5a 产物与 `scripts/aiui5/check_artifacts.py`。
旧断言文件 `library_contract_boundary_test.dart`、`aiui5_f5a_contract_fixture_test.dart` **不改且应继续通过**（design §7：library-1/dynamic-1/stream v1 仍拒绝；library-2 行为只写新测试文件）。若 `BindingKind` 新增导致其编译或断言失败，视为实现缺陷。
**补充接口（design §2–§7）**：F5b 另独占 `ui_components/inputs.dart`、`layout.dart`（Choice `optionIds`、MuyonTabs/Disclosure 受控接口，加性）；`snapshot.dart` 增 `UiComputedEvidence`/`computedEvidence`；`UiComponentSchema.allowedValues`；`UiEditSpec` 的 `rejectPayload/rejectInContext/validateSpec`；`UiCollectionLimits` 增 id/label/集合字节；新测试补 `typed-edits.json`/`collection-stable-row.json` 的 round2 全部 case。

**F5b 负责（四项最小缺口，design §2 规则 4/6/10、§4.1/§4.2）**：(1) library-2 `editField` 的 dispatch 前置顺序与 nullable 绕过粗类型；(2) 渲染捕获身份：`UiRenderCapture` + 加性 `UiEvent eventForCapture(UiRenderCapture capture, UiNode node, String kind, [Object? payload])` 与 `Future<UiDispatchOutcome> dispatchCaptured(UiRenderCapture capture, UiNode node, String kind, [Object? payload])`（`UiEvent` 不携带 capture、不改 wire）；`surface.dart:90/311` 渲染路径禁止使用现场读 current 的 `eventFor`，所有回调（Field/Choice/Toggle/NumberStepper/Slider/DateField/Checklist/Tabs/Disclosure change、各 tap、ConfirmCard/BatchConfirmCard、Form submit）都在 build 时捕获并只调用 `dispatchCaptured`；该方法在第一个 `await` 前同步核 capture.plan/catalog 与 current identical、surface/revision、node 属于 capture.plan，不符直接 stale（零进入底层 dispatch/sink），符合才生成事件并转既有 `dispatch(UiEvent)`，business operation 来自该已核 plan；(3) qty 等 `UiStringEdit` 严格 payload 拒绝（不写 state/override、不增 revision）。F5c 负责严格 publish（revision 单调、surfaceId/snapshot/intent 一致）与全部显示 computed 重算（design §4）。新增测试：`nullableDispatch`、`strictQtyString`、`staleWidgetCapture` 三组 fixture；stale Widget 测试必须捕获真实 `onChanged/onPressed` 闭包，在 publish 后、重建前直接调用，断言零状态变化、零 sink/router/tool，不得只重放构造的旧 `UiEvent`；并以测试守住渲染器不调用旧 `eventFor`。

## 3. 实施切片（RED 先行）

1. 契约类型 + 校验：`edit_spec.dart`、`collection.dart`；`validateBindingRef` 从 `validateUiNode` 抽取；`editField` 分支改用 spec；`validateUiCollection`；`shown` 覆盖 collection cell；`Tabs.childComponents` 整树规则。
2. 状态：`UiSessionState` 的 spec 派发、`_selections`、`currentValues` getter、`rowObject`、`restoreWorkspace` 对 spec 一致（只提供 getter/纯方法，不含 carryOver，属 F5c H1）。
3. 流：`UiStreamSession` 接受 `aiui-stream/2`；v1 显式拒绝 `collection`；`library-2` + v1 构造抛 `catalog_requires_stream_2`。
4. library-2 目录 + 33 组件适配表 + 渲染门禁 `supportedUiCatalogs`；`UiSurfaceController(onOpenObject:)`。
5. 4 个变异（M1、M2；M3/M4 属 F5c）。

## 4. 验收（真实入口；未运行）

| 文件 | 内容 |
|---|---|
| 新 `packages/muyon_module_api/test/ui_edit_spec_test.dart` | 见 fixture `typed-edits.json` 全部 case；无 spec 的 String 编辑不变；`UiValueType.number/stringList` 不得用于 properties |
| 新 `.../ui_collection_test.dart` | `collection-stable-row.json` 的缺失来源、集合负例、rows/columns/itemIds/maxLength 的 N−1/N/N+1（同一常量） |
| 新 `.../ui_stream_v2_test.dart` | `stream-version.json` matrix；既有 `ui_stream_test.dart` 不改且保持通过 |
| 新 `packages/muyon_ui/test/component_plan_mapping_test.dart` | 枚举 `libraryUiCatalog2.components.keys` 与 manifest 33 名对等；每项合法 plan 经 validator 后真实 `DynamicUiSurface` 渲染，断言值/语义/四态；Tabs 用 `tabs_update_test.dart` 回归；Form 只读封锁后代输入 |
| 新 `.../ui_row_detail_session_test.dart`（可并入上一文件） | itemId 重排稳定、未知/伪造/无 object 行零回调 |

命令（SDK 就绪后）：`cd packages/muyon_module_api && flutter analyze --fatal-infos && flutter test`；`cd packages/muyon_ui && flutter analyze --fatal-infos && flutter test`；最终 `bash scripts/ci.sh`。

## 5. 4 变异中归 F5b 的两项
M1（跳过 `spec.reject`）→ `ui_edit_spec_test.dart`；M2（v1 放行 collection）→ `ui_stream_v2_test.dart`。必须记录实际失败断言，不得以编译错误当检出。

## 6. 交接
H1/H2/H3 见 design §7。F5b 合入后向 F5c 交付：`currentValues`、`rowObject`、`onOpenObject`、F5c `UiRecomputeInput` 所需的 `DataSnapshot.editSpecs/collections`。
