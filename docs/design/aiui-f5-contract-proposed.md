# AIUI F5 最小技术决策包（proposed / 未采纳）

状态：**proposed / 未采纳**。本文件是对旧草稿 [aiui-binding-adapter-contract.md](aiui-binding-adapter-contract.md)（保留不改）的收敛，供父任务决定是否采纳。不修改正式 schema、runtime、目录、存储或 `aiui-stream/1`；没有实现任何生产代码。本文所有「拟新增」都是尚不存在的东西，不得当作现有接口引用。

基线：`git rev-parse HEAD` = `origin/develop` = `cf672164e4f6c3e7beea8029c8be735e33c3bf19`（委派时记录的 `b8a9a523` 已被 PR #15 合并推进，本次按新值核对）。分支 `task/aiui-f5-contract-close`，工作区开工时干净。基线树无 AGENTS.md / CLAUDE.md / 仓库 skills，已自行核查。

执行归属：正文、接口与未来夹具由真实 Claude Code 两轮产出；调用者 Codex 做初审、整合第二轮修订、PR18 对照和机械验证。本文是单一 proposed 提案，无用户采纳记录。

## 0. 最小取舍

| 项 | 裁决 |
|---|---|
| cell 值副本、`cellStateRefs` 双重索引 | 仍删 |
| 内部 `codecVersion`、`collectionRevision` | 仍删（快照 ref 即版本，见 §3） |
| 跨 kind 全局 ID 冲突检查 | 仍删（`BindingRef` 含 kind） |
| **computed 来源/状态** | **恢复**：见 §3（`ComputedValue` 无 state/sourceRefs） |
| **限额** | **补回**最小字节上限：见 §2 |
| Heading level / Chart kind 渲染错误态 | **改回** validator 拒绝：见 §2 |

## 1. 精确版本与兼容门槛


核对现有值：目录 `minimal-1` / `dynamic-1` / `library-1`（`catalog.dart:7/83/174`）；流协议 `aiui-stream/1`（`stream_protocol.dart:39,41`）；workspace `schemaVersion` 是 **int**，生产调用默认 `1`（`dynamic/workspace.dart:43`）。命名风格一致的新值：

| 维度 | 现值 | **新值（精确）** | 说明 |
|---|---|---|---|
| 目录 `UiCatalog.version` / `UIPlan.catalogVersion` | `library-1` | **`library-2`** | 新建 `libraryUiCatalog2`；`libraryUiCatalog`（library-1）原样保留，旧 plan 仍按旧目录校验 |
| 流 `UiStreamSession.protocolVersion` | `aiui-stream/1` | **`aiui-stream/2`** | v2 与 v1 的唯一语法差别：`bind` 里 `kind` 额外允许 `"collection"`。其余 op/限额/规则逐字不变（与流契约 §8 一致） |
| `StoredUiWorkspace.schemaVersion`（int） | `1` | **`2`** | 所有 `library-2` checkpoint 一律使用；`UiWorkspaceController.open(schemaVersion: 2)`。保留既有「版本不等 → readOnly」规则，**不写多版本兼容矩阵、不做自动迁移** |

不新增 `collection` 内部 codec 版本、不新增「能力 revision」字符串：能力由「目录版本 × 流版本」决定，恢复由「schemaVersion × catalogVersion」决定。

### 1.1 能力矩阵与双门槛

门槛 A = 流版本（语法）；门槛 B = 目录版本（槽位是否声明 collection / 编辑规格）。**一个 collection 绑定有效 ⟺ 流 v2 ∧ 目录槽位声明 collection。**

| 目录 \ 流 | `aiui-stream/1` | `aiui-stream/2` |
|---|---|---|
| `minimal-1` / `dynamic-1` / `library-1` | 现行行为不变（`bind.kind` 仅四种；`collection` → 坏行 `invalid_fields`） | 语法放行，但这些目录没有任何槽位含 collection，节点校验报 `binding_kind:`（不是语法层放行就生效） |
| `library-2` | **构造 `UiStreamSession` 即抛 `ArgumentError`（`catalog_requires_stream_2`）**：library-2 的必填集合槽位在 v1 下根本无法满足，提前失败比到 `end` 才失败可诊断 | 全部能力 |

要点：
- v1 解析器必须**显式**拒绝 `collection`，因为 `BindingKind` 增加枚举值后，`stream_protocol.dart:181` 的 `BindingKind.values.byName` 会让 v1 悄悄解析成功。门槛在 `UiStreamSession.protocolVersion` 上做：v1 session 里出现 `kind:"collection"` 按坏行，计入 `badLines`，最终 `malformed_stream`。
- 反向：旧版本二进制读到含 `"kind":"collection"` 的 workspace，`decodeUiPresentation` 会在 `byName` 抛 `ArgumentError`。**不支持降级读取**；这由 §7 的「不可读 → 只读 + 保原 bytes」兜底，而不是靠版本回退。
- 生产今天用的是 `dynamicUiCatalog`（`ui_planning_source.dart:77`），`surface.dart:562` 对其它目录整棵 `snapshotFallback`。library-2 在 F5b 把自己加进渲染门禁前不会被生产采用。

## 2. 编辑规格与 Widget 接口
（拟新增 `packages/muyon_module_api/lib/src/ui/edit_spec.dart`）

宿主在 `DataSnapshot` 上声明，模型只能引用 state key。最小数据形状（Dart 签名即拟定形状）：

```dart
/// 由宿主声明。reject 返回 null 表示接受；否则返回稳定错误码。绝不转换、不截断、不 clamp。
sealed class UiEditSpec {
  const UiEditSpec({this.nullable = false, this.view = false});
  final bool nullable;   // payload 为 null 是否合法（清空）
  final bool view;       // true: 只写 viewValues，不递增 draftRevision，且不得是公式/业务输入
  UiValueType get payloadType; // 事件载荷的粗类型，须与 schema.events[kind] 相等
  String? rejectPayload(Object? payload);
  String? rejectInContext(Object? payload, UiEditContext context);
  String? validateSpec();
}
final class UiStringEdit extends UiEditSpec { const UiStringEdit({this.maxLength = 4096, this.accepts, super.nullable, super.view}); final int maxLength; final bool Function(String)? accepts; }
final class UiBoolEdit   extends UiEditSpec { const UiBoolEdit({super.nullable, super.view}); }
final class UiNumberEdit extends UiEditSpec { const UiNumberEdit({required this.min, required this.max, this.step, this.integer = false, super.nullable, super.view}); final double min, max; final double? step; final bool integer; }
final class UiDateEdit   extends UiEditSpec { const UiDateEdit({required this.first, required this.last, super.nullable, super.view}); final String first, last; } // 'YYYY-MM-DD'
final class UiItemIdsEdit extends UiEditSpec { const UiItemIdsEdit({required this.collectionId, this.multiple = false, this.initial = const [], super.view}); final String collectionId; final bool multiple; final List<String> initial; }
```

`DataSnapshot` 新增可选字段（拟）：`Map<String, UiEditSpec> editSpecs`（键 = `initialUiState` 的键，itemIds 例外，见下）与 `Map<String, UiCollection> collections`。`copyWith` 与构造器同步增加；现有构造调用点不变（默认空 map）。

规则：

1. **向后兼容**：typed specs 的新编辑语义只在 library-2 生效；minimal/dynamic/library-1 的编辑 gate 和 dispatch 继续逐字保持 string-only，不能因宿主登记 spec 而绕过旧拒绝。`initialUiState` 的键没有 spec 时等价于 `const UiStringEdit()`，即今天的行为（初值必须是 String）。旧 plan/旧测试不变。
2. **payloadType 映射**：string→`string`，bool→`boolean`，number→`number`，date→`string`，itemIds→`stringList`。`UiValueType` 需新增 `number`、`stringList` 两个值（`plan.dart:16`；`matchesUiValue` 增加两分支：`number` = `value is num && value.isFinite`，`stringList` = `value is List && every String`）。**这两个值只允许用在 `events`，不允许用在 `properties`**（`UiComponentSchema` 构造断言），模型因此不能用 props 夹带数字或列表。
3. **validator 变更**（`validateUiNode` 的 `editField` 分支，`validation.dart:219-227`）：把 `schema.events[kind] != UiValueType.string || initialUiState[key] is! String` 换成：`spec = snapshot.editSpecs[key] ?? const UiStringEdit()`；`spec.payloadType != schema.events[kind]` → `edit_input`；初值须满足 `spec.rejectPayload(initial) == null`（itemIds 的 key 不在 `initialUiState`，由 `spec.initial` 决定，`unknown_state` 判断改为「在 `initialUiState` 或 `editSpecs[id] is UiItemIdsEdit`」）。`spec.view` 为真的 key 若同时出现在 `actionContext.draft` → `view_business_input`（沿用 `sortRows` 的既有规则）。
4. **dispatch 变更**（`UiSessionState.dispatch`，`state.dart:127`）。现行顺序是：身份/revision/目录核对 → **粗类型 `matchesUiValue(payloadType, payload)`（`:151-155`，此处 null 一律 invalid）** → route 分支 → `localAction` switch。library-2 的前置判断顺序（仅 library-2 的 `editField`，其余事件与旧目录原样保持原 gate）：
   1. 身份/revision/目录核对（不变）。
   2. 确认 `localAction == editField`，取 `key = binding.inputRefs.single`，`spec = snapshot.editSpecs[key]`（library-2 必有；无 spec 的键走默认 `UiStringEdit` 且 `nullable=false`），且 `spec.payloadType == schema.events[event.kind]`（与目录事件类型一致）；任一不成立 → `invalid`，不改值。
   3. 粗类型：`payload == null && spec.nullable` 时**跳过**粗类型检查；其余情形（非 null、或 null 但 spec 不 nullable）仍执行 `matchesUiValue`，失败 → `invalid`。
   4. `spec.rejectPayload(payload)` 与 `spec.rejectInContext(payload, context)`（null 仅在 nullable 时通过）；非 null → `invalid`。
   5. 通过才写状态。
   无 state key/无 spec、被拒 null：值、`userOverrides`/`viewValues`/`_selections`、`draftRevision` 均不变。旧目录（minimal/dynamic/library-1）与所有非 `editField` 事件完全沿用原粗类型 gate（null 对有载荷的事件仍 invalid）。

   `editField` 被拒绝时 `UiEventOutcome.invalid`；通过后 `spec.view ? selectView : edit`。`_setValue` 里写死的「`_values[field] is String && value is! String` 才拒」改为以 spec 为准；`isUiScalar` **不放宽**，itemIds 另存 `Map<String, List<String>> _selections`（规范化为字典序去重数组），不进 `_values`/`userOverrides`。`restoreWorkspace` 同理走 spec。
5. **number**：wire 为 JSON number；`value is num && isFinite`。`integer=true`：数学整数且 `|v| ≤ 2^53−1`。范围为闭区间，`min ≤ max`；`step` 给定则要求 `abs((v−min)/step − round(..)) ≤ 1e-9`，**off-grid 直接拒绝，不 round、不 clamp、不 `toInt`**。`min == max` 渲染只读常量。Slider 有 step 时要求 `(max−min)/step` 为整数且 ∈ [1,10000]；否则拒绝该组件绑定，不允许用 continuous 绕过 step。无 step 时才可 continuous。目录 `NumberStepper`/`Slider` 的 `min/max/step` integer 属性在 library-2 **删除**（规格只有宿主一个来源，不存在两处冲突）。
6. **金额与定点**：金额、单价、税率一律是 `String` 小数（F3a `ExactDecimal` 规则），编辑用 `UiStringEdit(accepts: <apps 侧用 ExactDecimal 实现的谓词>)`——谓词由 `apps/muyon` 注入，`muyon_module_api` 不依赖 supplier_core。**首片采用严格 payload 拒绝**：`'oops'`、未完成的 `''`、`'.'` 等不满足谓词的输入 → `invalid`，**不写 state/override、不递增 `draftRevision`、不触发重算**；首版不实现单独持久的编辑 buffer。Widget 可短暂显示用户键入，但那不是已提交状态：被拒后恢复最后已接受文本，可提示原因。领域层的 `invalid`（如 `unit_mismatch`）只针对**合法 decimal String**（如 `qty='3'`）的计算，合法人工 qty 保留；非法文本永不进入 evaluator。最大精度、零数量等业务规则沿用 F3a。**`UiNumberEdit` 禁止绑定金额**；Chart 只在画图几何时把规范小数串解析成 double，数据表与读屏文字仍用原字符串。
7. **date**：严格 `YYYY-MM-DD`，年 0001–9999，必须 `DateTime.utc(y,m,d)` 往返字段一致（排除 `2026-02-30`），无时间/时区；`first/last` 由宿主必填且为同格式字符串，字典序比较即日期序。`DateField` 适配器只用 year/month/day 构造本地 `DateTime(y,m,d)` 与读回，不 `toUtc`/`toIso8601String`。`""` 不是 null。
8. **itemIds**：payload 是 `List<String>`；重复 ID **整体拒绝**（不去重后放行）；每个 ID 必须是 `collections[spec.collectionId].rows` 的 `itemId`；`multiple=false` 时 ≤ 1；总数 ≤ `UiCollectionLimits.rows`。存储规范化为 `String.compareTo` 升序。`Choice` 的显示文字不是 ID，**自填首版 disabled**。
9. **Checklist 的 fact 模式只读**：没有 `checked` 绑定即只读；有绑定时 Widget 的 `(index, bool)` 回调由适配器按**本次渲染冻结的行序**映射成 itemId，再发 `change` 载荷（新的完整 itemId 列表）。位置不是持久身份。
10. **渲染捕获身份（F5b，防旧 Widget 冒充新 revision）**：现状 `eventFor`（`surface.dart:90`）在调用时读取 `current.plan.revision` 生成 `UiEvent`，`_render` 的 `dispatch` 闭包（`:311`）每次回调都调它，所以 publish 之后仍被持有的旧 `onChanged/onPressed` 会被重标成新 revision，并可能取到新 operation。最小加性方案：
    - 新增 `class UiRenderCapture { final String surfaceId; final int revision; final UiCatalog catalog; final ValidatedUiPlan plan; }`，在**每次 build/render 开头**从 `controller.current` 冻结一次（含该次渲染所见 plan 的各节点 events/operation 引用）。
    - 普通 `UiEvent` **不携带** capture（不改 `UiEvent` wire，不维护 `eventId→capture` 第二索引）。capture 只经 controller 的加性入口传递，两个精确签名：
      ```dart
      UiEvent eventForCapture(UiRenderCapture capture, UiNode node, String kind, [Object? payload]);
      Future<UiDispatchOutcome> dispatchCaptured(UiRenderCapture capture, UiNode node, String kind, [Object? payload]);
      ```
      `eventForCapture` 仅为 `dispatchCaptured` 内部使用的生成器：`surfaceId`/`observedRevision` 取自 capture，`eventId` 仍由 controller 计数。
    - `dispatchCaptured` 在**第一个 `await` 之前、同一同步片段**内依次完成：(a) `capture.plan`、`capture.catalog` 与 `current`/`current.catalog` `identical`，`capture.surfaceId == current.plan.surfaceId`、`capture.revision == current.plan.revision`；(b) `node` 属于 `capture.plan.nodes`，且 `node.events[kind]` 来自该节点（不从 current 重新查）；(c) 任一不成立 → 直接返回 `UiDispatchOutcome.stale`，**零进入底层 `dispatch`、零 event sink/router/tool**；(d) 全部成立才 `eventForCapture` 并转既有 `dispatch(UiEvent)`。此时 capture 与 current identical，因此 business 的 `operationKeyRef`/`expectedDraftRevision`/inputs 来自已核身份的同一 plan，不从新 current 补旧 operation。严格 publish（revision 单调递增，见 §4.2）保证旧 revision 不可复用。既有 `dispatch(UiEvent)` 的 `observedRevision` 检查保持不变。
    - 渲染器（`component_adapter.dart` 与 `_render`）**只许调用 `dispatchCaptured`**，所有回调——Field/Choice/Toggle/NumberStepper/Slider/DateField/Checklist/Tabs/Disclosure 的 change，CompareTable/SourceCard/ObjectChip 的 tap，ConfirmCard/BatchConfirmCard 的 confirm/cancel，Form submit——都在闭包里使用该 build 捕获的 `capture`。旧 `eventFor(UiNode, kind, payload)` 可保留给现有调用/测试，但**渲染路径禁止使用现场读 current 的 eventFor**（以 grep/测试守住）。
    - 结果：publish 后、下一帧重建前直接调用旧闭包 → `stale`，零状态变化、零 event sink/router/tool。
11. **事件 → state 全链路（typed）**：Widget 回调 → 适配器生成 payload → `UiSurfaceController.dispatchCaptured(capture, node, kind, payload)` → 既有 `dispatch(UiEvent)`（签名不变，`surface.dart:164`）→ `UiSessionState.dispatch` 的 spec 校验 → `userOverrides`/`viewValues`/`_selections` 与 `draftRevision`（非 view 才 +1）→ `notifyListeners`。业务 draft 值与 fact 永不被该路径写入。

**Tabs / Checklist / Choice 的稳定身份**：身份 = 节点 id（Tabs 子节点）或 `itemId`（Choice/Checklist 行），不是位置、不是标题。Tabs 的 `labels` 取自**子 `Section` 节点的 `title` 属性**，因此 library-2 给 `UiComponentSchema` 新增 `childComponents`（可选 `Set<String>`），`Tabs` 声明 `{'Section'}`，该规则在 `validateUiPlan` 的整树阶段检查（节点单独校验时看不到子节点组件，与现有 `children:` 规则同层，预览阶段不报、`end` 时报）。选中项为可选 `selected` uiState 绑定（`UiStringEdit(view:true)`，值 = 子节点 id；不在子节点内则回落第一页）。`Disclosure` 的展开态为可选 `expanded` uiState 绑定（`UiBoolEdit(view:true)`）。两者都进 `viewValues`，因此随 workspace 保存/恢复。



`UiSessionState` 现有 `extracted(initialUiState) / userOverrides / viewValues` 分层不变，itemIds 对应增加（均持久化，F5c `workspace.dart`）：`selections`（当前值）、`selectionOverrides: List<String>`（用户改过的键，对应 userOverrides 语义）、`viewSelections`（`spec.view` 的键，对应 viewValues 语义）。extracted 初值取自 `UiItemIdsEdit.initial`。不兼容的已存 selection 不丢弃：保留在 readableDraft 并令 workspace 只读。



- `UiEditSpec` 拆成两层：`String? rejectPayload(Object? payload)`（纯，类型/范围/格式）与 `String? rejectInContext(Object? payload, UiEditContext ctx)`；`UiEditContext{ Map<String,UiCollection> collections }`。`UiItemIdsEdit` 的 membership 只在 `rejectInContext` 检查；session 与 validator 两处都调用两层。
- spec 自身合法性 `String? validateSpec()`（宿主构建 snapshot 时调用，失败整份快照不可构建）：`UiNumberEdit` 要求 `min`/`max` 有限且 `min ≤ max`，`step` 若给则有限且 `> 0`；**Slider 绑定的 spec 若有 `step`，必须 `(max−min)/step` 为整数且 divisions ∈ [1,10000]，否则 `slider_step_unrepresentable`，不允许退化为 continuous**；初始值须通过 `rejectPayload`。`UiDateEdit` 的 `first`/`last` **必填**且合法、`first ≤ last`，无 `DateTime.now` 默认。
- **组件契约进 validator**：`UiComponentSchema` 新增 `Map<String, Set<Object>> allowedValues`；`validateUiNode` 对属性值不在集合内报 `property_value:<node>:<key>`。library-2：`Heading.level ∈ {1,2,3}`，`Chart.kind ∈ {'bar','line','pie'}`。非法 plan 不再「渲染成错误」。
- 限额（沿用旧数值，单一常量对象 `UiCollectionLimits`）：rows 200、columns 32、**id ≤ 128 UTF-8 字节、label ≤ 256 字节、单集合 id+label 总编码 ≤ 64 KiB**；`UiStringEdit.maxLength` 4096 字节；workspace 单条编码 ≤ 256 KiB。超限保存：`save` 拒绝（`workspace_too_large`），**旧 bytes 不动**，当前人工稿保留在内存 controller（只读 + `saveError`），可复制。边界 N−1/N/N+1 用同一常量。


### 2.1 Widget 加性接口（F5b 独占 inputs.dart/layout.dart）
- `Choice`：新增可选 `List<String>? optionIds`（与 `options` 等长、唯一）、`Set<String>? selectedIds`、`ValueChanged<Set<String>>? onChangedIds`。提供 `optionIds` 时以 ID 为身份（同 label 不同 ID 可区分），`selected`/`onChanged` 不再使用；不提供则旧行为。`allowCustom` 在 id 模式恒 false。
- `MuyonTabs`：新增可选受控 `int? selectedIndex` 与 `ValueChanged<int>? onChanged`；受控时不读 `initial`、不靠重建恢复；适配器把 index↔子 Section 节点 id 互转并写 `selected` 视图状态。旧 `initial` 构造行为保持，保留 shrink 回归。
- `Disclosure`：新增可选受控 `bool? expanded` 与 `ValueChanged<bool>? onChanged`，同理。
- `Checklist`：保持 `(index, bool)` 回调，适配器用**本次渲染冻结的 registry 行序**映射 itemId；行序即 registry 顺序，重排后重新冻结。
Choice/Tabs/Disclosure 的 renderer 必须消费这些受控接口。

## 3. Collection 与可信行导航


### 3.1 registry 数据形状（拟新增 `packages/muyon_module_api/lib/src/ui/collection.dart`）

```dart
class UiColumn { const UiColumn(this.id, this.label); final String id, label; }          // label 是宿主文字
class UiRow {
  UiRow({required this.itemId, required Map<String, BindingRef> cells, this.object});
  final String itemId;                  // 宿主分配，集合内唯一，跨快照稳定，不复用
  final Map<String, BindingRef> cells;  // columnId -> fact | computed（只有这两种）
  final ObjectRef? object;              // 可选；若给出，必须 == 某个 cell 所指 fact 的 object
}
class UiCollection {
  UiCollection({required this.id, required List<UiColumn> columns, required List<UiRow> rows});
  final String id; final List<UiColumn> columns; final List<UiRow> rows;
}
class UiCollectionLimits { static const rows = 200, columns = 32; }   // 另有 §2 字节上限；统一常量造 N±1
```

- `BindingKind` 增加 `collection`；`BindingRef.collection(id)` 构造。`DataSnapshot.collections` 是该 kind 唯一的解析目标，`fact/computed/uiState` 三个 kind 永不查它（kind 独立命名空间，无跨 kind 全局冲突检查）。
- **值、状态、来源零复制**：cell 的值走 `session.resolve(BindingRef)`（fact→`facts[id].value`，computed→仅当 `inputVersion == snapshot.ref`）；fact 状态/来源/单位走 `SnapshotFact`；computed 走下文 `computedEvidence`。缺值 = 宿主为该 cell 建一个 `value: null` 的 fact 并设 `FactState.notDisclosed / notApplicable / readFailed`（`isUiScalar(null)` 现已为真，validator 不用改）。空字符串仍是真实字符串，不是缺值；数字 null 不得转 0。
- **集合级校验**（`validateUiCollection`，在 `validateUiNode` 遇到 `BindingKind.collection` 时调用，并沿用其内联 fact/computed/source 检查；先把 `validation.dart:158-198` 的 `switch` 抽成 `validateBindingRef(ref, snapshot)` 复用，与流契约 §4「抽取复用」同一原则）：id 非空且 `columnId`/`itemId` 在各自集合内唯一；每行 cell 集合 == 列集合（缺列/多列整体拒绝，不补默认值）；cell 的 kind ∈ {fact, computed} 且各自按既有规则解析（含 computed 的 `inputVersion`）；`rows ≤ 200`、`columns ≤ 32`；`UiRow.object` 与 cell fact 的 `object` 一致。**任何一项失败整个集合拒绝**（`collection:<id>:<code>`），不丢坏行后放行。
- **必显状态覆盖**：`validateUiPlan` 的 `shown` 集合在遇到 collection 绑定时，把该集合所有 cell 的 `BindingRef` 加入 `shown`，否则 `mandatory_state:` 会对已展示但只经集合出现的 fact 误报，或反过来漏报。

### 3.2 槽位形状（在 `UiComponentSchema` 新增 `Map<String, UiCollectionShape> collections`）

`UiCollectionShape` 是一个枚举，`accepts(UiCollection)` 为纯函数：

| 形状 | 列要求 | 组件.槽位（library-2） | 适配结果 |
|---|---|---|---|
| `table` | ≥ 1 列，任意 | `CompareTable.rows` | `columns` = 列 label；`rows` = 每行按列取格式化后的文字；mark 仅由 `FactState` 推出 |
| `series` | 恰 2 列：`label`、`value` | `Chart.data` | `ChartPoint(label,double)`；合法缺值不画几何但数据表保状态；非法数值/非有限/pie 负值整集合拒绝 |
| `timeline` | `time`、`title`，可选 `detail` | `Timeline.events` | `TimelineEvent`，**按 registry 行序**（宿主排序），不解析时间 |
| `options` | 恰 1 列 `label` | `Choice.options` | `options` 文字；选中集合来自 `selected` 的 itemIds 状态 |
| `items` | 恰 1 列 `label` | `Checklist.items` | `ChecklistItem(label, checked)`；checked = 该 itemId ∈ `checked` 绑定的 itemIds 状态 |

各槽位的 `bindings` 声明里把 `BindingKind.collection` 作为该槽位唯一允许的 kind（`Chart.data` 在 library-2 去掉 fact/computed，因为 library-1 的单值 `Chart.data` 画不出图，见 §6 第 22 项）。

### 3.3 行详情（零 tool 的可信导航）

- 新增 `UiLocalAction.openRow`（`plan.dart:7`）与目录动作 `'openRow'`（route: local）。library-2 的 `CompareTable.tap` 登记为 `{'openRow'}`（替代 library-1 里无法通过的 `detail`：`validation.dart:238` 要求 `value` 绑定，而 CompareTable 只有 `rows`）。
- 校验：节点必须有 `collection` 类型绑定；`inputRefs` 为空；载荷类型 `string`（= itemId）。
- 分派：`UiSessionState.dispatch` 中 `openRow`：`itemId` 必须在该集合 `rows` 中恰一行，且该行 `object != null`，否则 `invalid`（未知/删除/伪造 ID 零效果）。`dispatch` 保持纯同步；`UiSessionState` 新增纯方法 `ObjectRef? rowObject(UiNode node, Object? payload)`。`UiSurfaceController` 新增可选构造参数 `Future<void> Function(String nodeId, ObjectRef object)? onOpenObject`，`dispatch` 在 `applied` 且动作为 `openRow` 后调用它。
- 宿主屏（`apps/muyon/lib/screens/dynamic_workspace.dart`，AIUI-4 外壳文件）把 `onOpenObject` 接到既有 `openReference(object:, nodeId:)`，从而走 `UiReferenceNavigation.openReference` 现成的 `ref ∈ snapshot.facts 的 object` 校验、`_checkpoint` 返回锚点与租约。**该文件改动按交接 patch 交 AIUI-4 owner 应用（见 §8）。**
- `UiPlanningEventRouter.dispatch` 对 local 路由 `return`（`ui_planning_events.dart:44`），行详情不调用任何 tool、不 `startTool`、不 `startUiSemantic`。
- 排序仍是 `sortRows`（view，不递增 draftRevision，不改 fact）。行身份是 itemId，重排不改变指向。


### 3.4 computed 证据

`ComputedValue`（`snapshot.dart:57`）不变。新增（F5b，`snapshot.dart`）：
```dart
class UiComputedEvidence {
  const UiComputedEvidence({required this.state, this.unit, this.sourceRefs = const []});
  final FactState state;            // 不得缺省；宿主按依赖评估给出，绝不默认 verified
  final String? unit;
  final List<String> sourceRefs;    // ⊆ snapshot.sources，digest 与 sourceDigests 一致
}
// DataSnapshot.computedEvidence: Map<String, UiComputedEvidence>   键 = computations 的键
```
规则：collection 的 computed cell（及任何新目录里绑定 computed 的槽位）要求存在 evidence，否则 `computed_evidence_missing`；evidence 的来源逐项按现有 `unknown_or_stale_source` 规则核对；`ComputedValue.inputVersion == snapshot.ref` 仍是必要条件。**不新增 missingReason 枚举**：缺值原因就是 `FactState`（notDisclosed / notApplicable / readFailed / conflict / unverified）。合法 `null`（`notApplicable`、显式空值 = `verified` 且 value null）渲染为状态文字（「不适用」「空」），**不是错误态**；金额 null 不得显示 0。conflict/unverified 保留标记，文字、图表数据表、读屏同源同文案。
Chart：合法缺值点不画几何，但**同源数据表保留并显示状态**；结构错误——`series` 的 value 列出现非有限数、非数值/非规范小数串（且状态非缺值）、`pie` 出现负值——在 `validateUiCollection`/槽位形状校验处**整集合拒绝**，不丢点后宣称有效。


### 3.5 当前宿主重核

前提：`DataSnapshot.collections` 构造后不可变；事件绑定链唯一为 `UiEvent.observedRevision → current plan → plan.snapshotRef → snapshot.collections`。`onOpenObject` 回调的宿主处理（H3，异步重核后导航，事件dispatch等待回调；重核失败零导航）在既有 `openReference`（仅查 fact object 成员关系）之外**必须再核**：当前 task scope（`scopeKey`）、`ObjectRef` 的 `revisionRef`/`contentDigest` 与宿主当前值一致、行引用的 source digest 未被撤销（`sourceDigests` 与宿主当前）。任一失败 → 不导航、零 tool，界面提示「对象/来源已变化」。该重核函数由宿主注入，F5b 的 `rowObject` 不替代它。

**await 期间撤权的封堵（H3，沿用 `ui_navigation_anchors.dart:67–81` 既有流程，不新建导航栈）**：既有 `openReference` 是 membership → `await _checkpoint` → `await openModuleObjectPage` → `Navigator.push`，中途只有 `mounted/canPresent`，入口重核不足以覆盖 await 期间的撤权。最小冻结：
```dart
class UiNavigationToken {   // 入口冻结（宿主）
  final String surfaceId; final int planRevision; final SnapshotRef snapshotRef; final String scopeKey;
  final int hostGeneration, sourceGeneration, permissionGeneration;
  final ObjectRef object;   // 含 revisionRef / contentDigest
}
typedef UiNavigationProbe = bool Function(UiNavigationToken frozen); // 宿主当前 probe：同步，true = 仍当前且 scope/source/object revision-digest/权限仍合法
```
流程：(1) 入口捕获 `frozen` 并先 probe；(2) `await _checkpoint` 返回后 probe；(3) `await openModuleObjectPage` 取得 page/lease 后 probe；(4) **final check 与 `Navigator.push` 之间不得再 `await`**。任一 probe 失败 → 零 push；若已取得 page/lease，必须 `dispose`/释放（`opened?.dispose()`，沿用既有 `finally`），未取得则不虚报 dispose；不遗留租约、零 tool。`mounted/canPresent` 只是附加条件，不能替代授权 probe。`UiNavigationProbe` 的当前值由宿主维护（与 §4.2 `UiPublishTokenProbe` 同源的 generation）。H3 由 AIUI-4 owner 应用；PR18 owner 需同步此最终 admission 契约，本任务不改 PR18。

## 4. 同 session 原子发布与 F3a 输入


现状（真实代码）：`UiSessionState.snapshot` 是 `final`（`state.dart:14`）；`accept` 要求 `identical(plan.snapshot, snapshot)`（`:116`）；`UiSurfaceController.acceptPlan` 要求 snapshot/intent/catalog 全部 `identical`（`surface.dart:103`）。因此**今天没有任何热替换路径**，编辑后 computed 不会变（计算值只读原快照）。

### 4.1 拟新增形状（F5c 接口；`packages/muyon_module_api/lib/src/ui/recomputation.dart`）

```dart
class UiRecomputeInput {
  UiRecomputeInput({required this.previousSnapshot, required Map<String, Object?> currentUiState,
                    required this.token});
  final DataSnapshot previousSnapshot;
  final Map<String, Object?> currentUiState;  // 键集 == previousSnapshot.initialUiState 的键（F3a 要求）；不含 itemIds
  final UiPublishToken token;
}
class UiRecomputeResult {              // 宿主构造；不接受公式/表达式/工具名/路由/新权限
  final UiPublishToken token;   // 从 input 原样携带，不能重标 generation
  final DataSnapshot? nextSnapshot;    // S8；其 ref 先分配，computations 用 S8 实际输入算出
  final InteractionIntent? nextIntent; // I8：id 与 I7 相同（否则 workspace 的 intentRef 比对会判只读）、snapshotRef=S8、allowedActionRefs ⊆ I7 ∩ 当前权限
  final List<String> errors;
}
abstract interface class UiRecomputePort { Future<UiRecomputeResult> rebuild(UiRecomputeInput input); }
```

宿主实现（拟新增 `apps/muyon/lib/platform/ui_recompute_adapter.dart`）只做：冻结输入 → 分配 S8（同 `id`，`revision` 取 max(base+1, 宿主计数)）→ 构造 `S8_in`（仅作「ref=S8 的计算输入」：旧 facts/sources + `ref=S8`，`initialUiState` **保持宿主 extracted 值**，键集不变）；**当前人工值（如 qty='3'）只通过单独的 `currentUiState` 参数传给 F3a**（`evaluate` 只要求其键集与 `S8_in.initialUiState` 相等，值取自 `currentUiState`，不读 `initialUiState` 的值），**不得把人工值写入 `S8_in` 或最终 published `S8.initialUiState`**。published S8 的 `initialUiState` 仍是宿主 extracted（qty='2'），`userOverrides.qty='3'` 与之同时存在、不矛盾，`session.resolve(uiState qty)` 得 '3'，`computed total` 为 '30'。输入指纹随真实 `currentUiState` 变化。→ **候选 plan 中（含 collection cell 展开后）所有将被显示的 computed 实例，全部**以 S8 的真实输入重新 evaluate，不论是否依赖当前被编辑 key；任何一个未能真实重算（unavailable 按 §4.3 表、invalid/stale/抛错则整批不发布、只读降级），**不得把未受影响的旧 value 仅改 `inputVersion` 带入 S8**；不新增缓存/DAG。对每个这样的 `UiFormulaDefinition`，用 `UiFormulaInvocation.forDefinition(definition, S8.ref)` 调 `UiFormulaRegistry.evaluate(invocation, S8_in, currentUiState)`（真实签名，`ui_formula_registry.dart:204`）。F3a 守卫保持有效：`inputVersion != snapshot.ref` → `stale`；`currentUiState` 键集必须与 `S8_in.initialUiState` 一致；公式状态输入必须是 `String`。因此**公式依赖的 state 键必须是 `UiStringEdit` 且 `view == false`**（宿主构建 snapshot 时检查：非 String spec → `formula_state_dep_kind`；String 但 `view:true` → `formula_view_state_dep`；均整份快照不可构建）。`UiStringEdit(view:true)` 绝不能成为公式输入，不能只检查 String 类型。

**extracted / override / view 分层与 rebase、restore、adopt**：三层永不合并——`extracted` = 当前 snapshot 的 `initialUiState`（宿主提取值），`userOverrides` = 人工覆盖，`viewValues` = 视图选择；`resolve` 取覆盖优先。发布（`rebase`）与恢复（`restoreWorkspace`）都不得用 override 值覆写 `snapshot.initialUiState`，也不得丢弃 override 标记；workspace `_capture` 的 `extracted` 恒取 published `snapshot.initialUiState`（保 '2'）。`adoptExtracted(key)` 保持现行语义——清除该键 override 并**递增 draftRevision**，值回到 extracted '2'，随后触发重算，总价回 '20'，旧 confirm 因 revision/operation 变化失效；不允许「删 override 标记回 2 而不递增」。

首片冻结验收链：编辑 qty 2→3 → publish，总价 30（extracted 2、override 3、resolve 3）→ checkpoint / SQLite 重开，extracted 仍 2、override 仍 3 → `adoptExtracted('qty')` 回 2，`draftRevision` 递增，重算后总价 20，旧 confirm stale。（fixture：`snapshot-race.json` `extractedOverrideLayers`、`restore-overrides.json` `extractedOverrideLayers`。）


### 4.2 原子接口

```dart
class UiPublishToken {   // 创建：宿主在冻结输入时（F3b 薄 adapter）
  final SnapshotRef baseSnapshotRef; final int draftRevision;
  final int hostGeneration, sourceGeneration, permissionGeneration; final String scopeKey;
}
class UiVersionBatch {   // 唯一创建者：宿主 adapter（F3b）；模型不可构造
  final UiPublishToken token; final DataSnapshot snapshot; final InteractionIntent intent; final UIPlan plan;
}
enum UiPublishOutcome { published, staleToken, invalid, disposed }   // invalid 的 errors 通过 controller.publicationErrors 只读 getter 给出
typedef UiPublishTokenProbe = UiPublishToken Function();
UiPublishOutcome publish(UiVersionBatch batch, UiPublishTokenProbe current);  // 同步；内部无 await
```
`UiPublishTokenProbe` 是宿主提供的同步读取器（当前 baseSnapshotRef/draftRevision/三种 generation/scopeKey）。**异步只发生在宿主 rebuild/候选准备期间，commit 本身是同步原子**，不用 Future 包。发布拒绝条件：**`batch.plan.revision <= current.plan.revision`（严格单调，含相等）**、`batch.plan.surfaceId != current.plan.surfaceId`、`batch.plan.snapshotRef != batch.snapshot.ref`、`batch.intent.snapshotRef != batch.snapshot.ref`、`batch.plan.intentRef != batch.intent.id`、`batch.intent.id != current.intent.id`、`batch.plan.catalogVersion != current.catalog.version`（任一 → `invalid`）；token 任一分量与 probe 不等（含 sourceGeneration 变化而当前快照未换）、controller 已 dispose 或宿主换代（`hostGeneration`）、`validateUiPlan(plan, snapshot, intent, catalog)` 失败。
**Identity**：`UiSurfaceController`、`DynamicUiSurface` 的 mounted 状态与 `UiSessionState` 对象**保持同一实例**；`UiSessionState.snapshot` 改为非 final，经内部 `rebase(batch)` 替换（H1，F5c）。迁移规则：`draftRevision = max(旧, 批次 actionContext.draftRevision)`，**绝不下降**；`userOverrides`、`viewValues`、`_selections` 及其标志逐项按新 spec/membership 重核后保留，不合规者留在 `readableDraft` 并标原因；`_pending`/`_lockedOperations`/回执继续按原 `eventId` 结算；旧版本 plan 上的 capability（确认/动作）一律失效，不可重放，新版确认使用宿主新分配的 operation key。F4c 测试以「同一 controller / 同一 mounted widget」为断言边界。


### 4.3 输出与失败


P12 = `P11.copyWith(revision: +1, snapshotRef: S8.ref, intentRef: I8.id, nodes: <业务事件 expectedDraftRevision 换成新 draftRevision>)`（`UIPlan.copyWith` 已有这些字段，`plan.dart:127`）。节点树、绑定 id 保持不变，**不调用模型**。业务确认的 `operationKeyRef` 换成宿主新分配的键（`surface.dart:75` 注释已规定「宿主给新的 operation reference」），`S8.actionContext` 的 `draftRevision`/`operations` 同步重建。

| 公式结果（F3a 状态） | 发布到 S8 | 界面 |
|---|---|---|
| `ready` | `ComputedValue(value, inputVersion: S8.ref, computationId: <同一实例 id>)` | 新值；动作仍须整树校验 |
| `unavailable` | `ComputedValue(null, S8.ref, 同实例 id)`（仅已登记可空输出）；否则按 invalid | 显示「暂无/不可计算」，不显示 0；依赖该值的确认保持 disabled |
| `invalid` | 目标槽从 `computations` 移除，**不从旧 computations 回填** | 对 P12 的整树校验报 `unknown_or_stale_computation` → 整批不发布，走只读/文字退路，保留人工输入，明确标「已过期」 |
| `stale` | 整批丢弃 | 不改任何状态；由最新状态重新排一次重算（latest-wins 合并） |


重算开始即封住确认；完成前/发布前复核完整 token，异常/超时标 outdated，保人工稿及旧界面只读，撤销旧 capability。ready 与 unavailable 输出同时构建 computedEvidence，不默认 verified。历史 pending/receipt 继续结算，但恢复和重算不重放业务。宿主 adapter 须实际重算所有仍要展示的 computations（或显式只读失败），不得把未受影响的旧值只改 inputVersion。formulaId/version、稳定 computationId、实际输入指纹分开；指纹为 host-only 诊断元数据，当前不扩展缓存/DAG语义。
## 5. workspace 恢复

所有 library-2 checkpoint 用 `schemaVersion: 2`，旧 minimal/dynamic/library-1 + schema1 继续走原路径。schema/catalog 不匹配、未知 kind、类型/shape/绑定变化、旧权限/来源失效：保原始 bytes、旧人工稿与 checkpoint，只读并给具体原因；首版不自动迁移。`HostUiWorkspaceStore.load` 拟抛 `UiWorkspaceUnreadable(reason, rawJson)`，`UiWorkspaceController.open` 捕获并尽力提取标量与合法 selections 数组到 readableDraft，绝不自动 save。scope 变化不恢复旧授权，原记录留存；不能用 load-null 后新空稿覆盖旧记录。

存储 selections、selectionOverrides、viewSelections（定义见§2），collections内容不进workspace，由当前宿主重建registry；plan持久化只含集合binding引用。恢复按当前snapshot/intent/catalog与spec/membership重核；不兼容override保在readableDraft并只读，不能静默丢弃。CAS/保存失败/超过256KiB拒绝新checkpoint、保旧bytes与内存人工稿。恢复只查询真实receipt并锁旧operation，不重放business/semantic/model。未知未来codec不猜历史授权。

## 6. 33 组件适配


名单与真实目录对等：`minimalUiCatalog` 5 + `dynamicUiCatalog` 新增 7 + `libraryUiCatalog` 新增 21 = **33**（`Table` 在 dynamic 中覆盖 minimal，不重复计数）。源码现有渲染 case 仅 12 个（`surface.dart:336-538`）；`surface.dart:562` 对非 dynamic/minimal 目录整棵 `snapshotFallback`，所以**library-1 当前 0 个组件可由生产渲染**。「状态」列统一约定：所有适配器通过同一函数 `UiComponentState stateFor(node)` 得出 `ready / loading（recomputing 且绑定 computed）/ error（宿主读取/计算失败；合法缺值按FactState文字降级）/ readOnlyDegraded（controller.readOnly 或 outdated）`，并通过组件已有 `errorMessage` 参数呈现；文字等价物与读屏使用同一已解析的可信值。

| # | 组件 | library-2 目录变化 | 绑定 / 事件 → Widget 参数 | 责任 |
|---|---|---|---|---|
| 1 | PageScaffold | 不变 | `title` prop；children | F5b：已有 case，仅回归 |
| 2 | Field | 不变 | `value` fact、`draft` uiState；`change`(string)+`UiStringEdit`；金额用带 `accepts` 的 UiStringEdit | F5b：已有 case，接 spec 校验 |
| 3 | Table | 不变（标量） | `value`/`alternate`/`sort`；集合形态延后 | F5b：已有 case，回归 |
| 4 | SourceList | 不变 | `source` sourceSpan；`tap`→`source`（local 展开） | F5b：已有 case |
| 5 | ObjectChip | 不变 | `value` fact；`tap`→`detail`、`back` | F5b：已有 case |
| 6 | MasterDetail | 不变 | children | F5b：已有 case |
| 7 | StatusBadge | 不变 | `value` fact → 状态徽标 | F5b：已有 case |
| 8 | ScopeChip | 不变 | `label` + `value` fact | F5b：已有 case |
| 9 | WarnBanner | 不变 | `value` fact；`tap`→`explain`（semantic，经既有 router） | F5b：已有 case |
| 10 | SegmentedPill | 不变 | `selected` uiState；`change`→`sort`(view) | F5b：已有 case |
| 11 | ConfirmCard | 不变 | `confirm`/`cancel`；business 经既有 router + 回执 | F5b：已有 case；F5c：重算后重建 operation key |
| 12 | BatchConfirmCard | 不变 | 同上 | 同上 |
| 13 | Heading | 不变 | `text`、`level`：非 1..3 → validator 拒绝 | F5b：新 case |
| 14 | Prose | 不变 | `text` → `Prose`；模型文字加「模型所述」标记（方案 §6 不变量 1） | F5b：新 case |
| 15 | Section | 不变 | `title`；children | F5b：新 case |
| 16 | Columns | 不变 | children → `Columns` | F5b：新 case |
| 17 | Tabs | `childComponents:{'Section'}`；新增可选 `selected` uiState（string, view） | 标签 = 子 Section.title；选中 = 子节点 id；`MuyonTabs(selectedIndex:, onChanged:)`；保留已修 shrink 回归（`tabs_update_test.dart`） | F5b：新 case + 整树规则 |
| 18 | Disclosure | 新增可选 `expanded` uiState（bool, view） | 多 children 合成 `Column`；展开态进 viewValues | F5b：新 case |
| 19 | KeyValue | 不变（标量） | `value` fact\|computed → `items:[(fact.field, 文字)]`；集合形态延后 | F5b：新 case |
| 20 | Metric | 不变 | `label`/`unit`、`value`、`delta`(computed) | F5b：新 case |
| 21 | CompareTable | `rows`: collection(`table`)；`tap`→`openRow` | 列 label、行文字；mark 仅由 FactState；`tap` 载荷 itemId | F5b：新 case + `openRow`；F5c：屏接线 patch |
| 22 | Chart | `data`: collection(`series`)（library-1 的单值 fact\|computed 删除） | `kind`∈bar/line/pie 否则 validator 拒绝；`ChartPoint`；附同源数据表 | F5b：新 case |
| 23 | Choice | `options`: collection(`options`)；`selected` 为 itemIds spec；`allowCustom` 删除；`change`(stringList) | `Choice(optionIds:, selectedIds:, onChangedIds:, allowCustom:false)`；回调 Set→排序 itemIds | F5b：新 case |
| 24 | Form | 不变 | `submit` business；只读时后代输入与提交均不可用（沿用 `MuyonForm` 子树封锁） | F5b：新 case |
| 25 | NumberStepper | 删 `min/max/step` 属性；`change`(number) | 范围取自 `UiNumberEdit`；`value` 为 double；nullable 且 null → 未设置态 | F5b：新 case |
| 26 | Slider | 同上 | `divisions` 按 §2 第 5 条；小数不截断 | F5b：新 case |
| 27 | Toggle | `change`(boolean) 现已登记 | `UiBoolEdit`；`value` bool | F5b：新 case |
| 28 | DateField | 不变（string 载荷） | `UiDateEdit`；`first/last` 来自 spec；y/m/d 构造 | F5b：新 case |
| 29 | SourceCard | 不变 | `source` sourceSpan → title/excerpt/location；`tap`→`source` | F5b：新 case |
| 30 | FileCard | 不变 | `value` fact → 文件名（仅 fact 字符串，模型路径不成权限）；`tap`→`detail` | F5b：新 case |
| 31 | ProgressCard | 不变 | `value` 为 [0,1] 有限数 → `progress`，否则不定进度 + 文字 | F5b：新 case |
| 32 | Checklist | `items`: collection(`items`)；新增可选 `checked` 为 itemIds spec；`change`(stringList) | 无 `checked` 绑定 = 只读；index→itemId 用冻结行序 | F5b：新 case |
| 33 | Timeline | `events`: collection(`timeline`) | 行序即宿主序；缺 `detail` 列则无 detail | F5b：新 case |

目录适配器新增唯一一张表：`packages/muyon_ui/lib/src/dynamic/component_adapter.dart`（F5b），`surface.dart` 的 `_render` 按组件名查表，不再靠 12 个 `case`；`surface.dart:562` 的目录门禁改为「`supportedUiCatalogs` 集合」，包含 minimal、dynamic、library-2；`libraryUiCatalog`（library-1）仍整棵 fallback（旧草稿保留不变）。

## 7. 文件所有权与 PR18 对齐

- 首片真实切片：预算行 `qty` 为 **String 小数**（`UiStringEdit` + `accepts`），经 F3a 重算；`inquiry.set_item_qty` 已登记但 AIUI 业务 mapping 缺失，故确认/提交保持 disabled，不猜 tool id，不造回执。数值型（finiteNumber）→ ExactDecimal 首版明确禁止，不扩 evaluator。
- **`apps/muyon/lib/platform/ui_recompute_adapter.dart` 唯一 owner = F3b**（另一执行者，薄宿主 adapter），它**消费** F5c 冻结的 `UiRecomputePort`、`UiRecomputeInput/Result`、`UiPublishToken`、`UiVersionBatch`、`publish` 接口；F5c **只提供核心**（`recomputation.dart`、`publish`/`rebase`、workspace），不拥有也不修改该 adapter。F4c 拥有端到端屏/导航测试，F5c 与 F3b 不共享测试文件。
- **旧拒绝测试不必授权更新**：library-1/dynamic-1 保持原拒绝（Toggle 在 library-1 仍 `edit_input`——无 spec 默认 `UiStringEdit` 载荷 string≠boolean；CompareTable `detail_input`；v1 流下 collection 仍被拒），`library_contract_boundary_test.dart`、`aiui5_f5a_contract_fixture_test.dart` 原样保留；library-2 的新行为只写在新测试文件。旧 `component-mapping.json`/checker 仍描述 library-1，不改。




唯一 owner 原则：**一个文件在同一时间只有一个 owner**；非 owner 以最小 patch 交付，由 owner 顺序应用。

| 文件 | owner | 另一方需求 → 交接 |
|---|---|---|
| `muyon_module_api/lib/src/ui/{snapshot,plan,validation,state,stream_protocol,stream_compiler}.dart`、新增 `edit_spec.dart`、`collection.dart` | **F5b** | F5c 需要 `UiSessionState.currentValues` getter（全量 state 视图）：F5b 一并提供 |
| `muyon_module_api/lib/src/ui/workspace.dart`、新增 `recomputation.dart`（先交接口切片供F3b消费） | **F5c** | F5b 无需 |
| `muyon_module_api/lib/ui_contract.dart`（export） | **F5b**（唯一） | F5c 的 `recomputation.dart` 一行 export：patch **H2**，F5b 在 F5c 通过审查后应用 |
| `muyon_ui/lib/src/dynamic/catalog.dart`（library-1 原样） | 冻结，两方都不改 | library-2 写在新增 `catalog_library2.dart`（F5b 独占） |
| `muyon_ui/lib/src/dynamic/surface.dart` | **F5b** 先行（渲染表、typed dispatch、`onOpenObject`、目录门禁） | F5c 的 `publish`/`recomputing`/session.rebase 保同实例：**H1**，F5b 合入后 F5c 在其之上提交（同文件不并行写） |
| `muyon_ui/lib/src/dynamic/workspace.dart` | **F5c** | – |
| 新增 `muyon_ui/lib/src/dynamic/component_adapter.dart` | **F5b** | – |
| `apps/muyon/lib/assistant/ui_planning.dart`、新增 `ui_planning_stream.dart`、`platform/ui_workspace_store.dart` | **F5c** | – |
| `apps/muyon/lib/screens/dynamic_workspace.dart` | AIUI-4（外壳） | **H3**：F5c 提供最小导航与当前宿主重核 patch（把 `onOpenObject` 接到既有 `openReference`），AIUI-4 owner 应用 |

`inputs.dart`/`layout.dart` 的 Choice/Tabs/Disclosure 加性参数由 F5b 独占。F3b 独占 `apps/muyon/lib/platform/ui_recompute_adapter.dart` 与 PR18 独立验收测试；F4c 独占其独立屏/导航验收。F5c 接口切片先审查，F3b可在冻结接口之上写薄adapter，组合CI后才启用。H3不限定行数，必须包含当前可信宿主重核和既有checkpoint/lease导航。Dream/foundation、agent_resume/tool_registry、supplier_core LAN范围外。AIUI-4旧恢复测试只读。
## 8. 验收矩阵与未来金样


所有 Dart 测试**未运行**（本环境无 Flutter/Dart）；这是未来验收，不是已有结果。命令见 F5b/F5c 任务书。

| 能力 | 入口（真实） | 拟新增测试文件 | 关键断言 |
|---|---|---|---|
| typed 接受/拒绝 | `validateUiPlan` → `UiSessionState.dispatch` | `packages/muyon_module_api/test/ui_edit_spec_test.dart` | 正例四类；负例：错类型、NaN/Infinity（原生构造）、off-grid、越界、2026-02-30、重复 itemId、未知 itemId；拒绝后值与 `draftRevision` 不变；无 spec 的 String 编辑逐字不变 |
| collection | `validateUiPlan`、`session.resolve` | `.../ui_collection_test.dart` | 缺 cell 整体拒绝；null+`notDisclosed` 事实通过且状态可见；rows/columns N−1/N/N+1；`mandatory_state` 经集合覆盖 |
| stream v1/v2 | `UiStreamCompiler` | `.../ui_stream_v2_test.dart`（不改既有 `ui_stream_test.dart`） | v1 下 `collection` 为坏行→`malformed_stream`；v2 同一行通过；library-2 + v1 构造抛错 |
| 33 组件消费 | `DynamicUiSurface` | `packages/muyon_ui/test/component_plan_mapping_test.dart` | 枚举 `libraryUiCatalog2.components.keys` 与 §6 的 33 名对等；每项一份合法原始 plan 过 validator 后真实渲染，断言绑定值、语义、四态 |
| 行详情 | `UiSurfaceController(onOpenObject:)` + 宿主屏 | `apps/muyon/test/ui_row_detail_navigation_test.dart`（F5c） | 重排后同 itemId 同 ObjectRef；未知/伪造 ID 零回调；router 的 `startTool`/`startUiSemantic` 调用数 0 |
| 原子发布 | `UiSurfaceController.publish` + `UiFormulaRegistry` | `packages/muyon_ui/test/ui_recompute_integration_test.dart`（F5c） | S7→S8：qty 2→3，`total` '20'→'30'，`inputVersion==S8`；token 变化丢弃；invalid/stale 按 §4.2；旧 confirm `stale`；pending 不被重放 |
| 恢复 | `UiWorkspaceController.open` + `HostUiWorkspaceStore` | `apps/muyon/test/ui_bound_workspace_recovery_test.dart`（F5c）+ `packages/muyon_module_api/test/ui_workspace_unreadable_test.dart` | 未知 kind/未来版本/截断 JSON：只读、`save` 调用数 0、SQLite 中 bytes 逐字相同；override 不满足 spec → 只读 |
| 流规划（F5c） | `UiPlanningHarness` | `apps/muyon/test/ui_planning_stream_test.dart` | 预览期零动作；坏流/中断/超限走可信模板 |

**4 个有效变异**（各由指定测试检出，必须是行为断言失败而不是编译/启动失败）：

| # | 变异 | 应被检出的测试 |
|---|---|---|
| M1 | `UiSessionState.dispatch` 跳过 `spec.rejectPayload/rejectInContext`（接受任意 payload） | `ui_edit_spec_test.dart` 的类型/范围/日期拒绝用例 |
| M2 | v1 session 下放行 `kind:"collection"` | `ui_stream_v2_test.dart` 的 v1 坏行用例 |
| M3 | `publish` 完成后不重取 token（直接替换） | `ui_recompute_integration_test.dart` 的「token 变化整批丢弃」用例 |
| M4 | `save` 前不先解码旧值（或遇不可读旧值时覆盖） | `ui_bound_workspace_recovery_test.dart` 的「原 bytes 逐字保留」用例 |

## 9. 待父任务采纳（六项）

1. **版本与门槛**：`library-2` 必须配 `schemaVersion: 2` 与 `aiui-stream/2`；v1 显式字符串拒绝 `collection`；旧版本旧测试不变。
2. **编辑**：`UiEditSpec` 五类，`rejectPayload`+`rejectInContext`+`validateSpec`；金额/预算 qty 首片仅 String；`allowedValues` 进 validator；Date 范围必填；Slider 不得绕过 step。
3. **collection**：`BindingKind.collection`，cell 为 `BindingRef`，computed 必带 `UiComputedEvidence`；状态用 `FactState`，缺值显式降级、结构错整集合拒绝；rows200/cols32/id128B/label256B/集合64KiB/workspace256KiB。
4. **行详情**：`openRow` + `onOpenObject`，宿主重核 scope/object revision/source digest，零 tool。
5. **发布**：`UiPublishToken`（含 host/source/permission generation、scope）、`UiVersionBatch`、同步 `publish`→`UiPublishOutcome`，controller/session/mounted identity 不变，draftRevision 不降，itemIds 三层持久；Widget 稳定 ID 接口（Choice/Tabs/Disclosure）。
6. **边界**：F5b 核心契约+Widget；F5c 核心 publish/workspace/stream；`ui_recompute_adapter.dart` 归 F3b；F4c 独立测试；defer：Table/KeyValue 集合、最优高亮、数值状态进公式、迁移。blockers：接口未采纳/实现未授权、Dart未运行、业务mapping缺失、H3由AIUI-4 owner应用。PR18由调用者核对，机械验证见报告。
