# AIUI-5 F5c 第一片：重算 / 发布接口交接

本片由用户明确授权；父任务统一审查，另行整合任务负责合入 develop。
六项接口方向已技术采纳，不代表运行验收或生产启用。

- 开工 fetch 的 develop：`8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d`。
- 固定读取的 PR19 设计提交：`36d0ba881b5e3e54d8a5e60867d869f168e00135`，仅阅读 `docs/design/aiui-f5-contract-proposed.md` §4 及 `docs/tasks/AIUI-5-F5c-proposed.md`，未 cherry-pick。
- 分支：`task/aiui-5-f5c-core-contract`；草稿 PR：[#21](https://github.com/mightyoung/Muyon/pull/21)。
- 唯一生产新增：`packages/muyon_module_api/lib/src/ui/recomputation.dart`。
- 独立纯测试：`packages/muyon_module_api/test/ui_recomputation_contract_test.dart`。
- 已读 HANDOVER-LEADER、ADR-0001 用户决定时间线、正式 aiui-stream-contract、REVIEW；仓库及工作区未发现 AGENTS.md，工作区 `.agents` / `.codex` 为空。使用 TDD 与完成前验证技能。

## 冻结接口（给 F3b）

所有数据承载类为 `final class`。构造器均为具名参数；下表除明确写默认值的参数外均 required。

| 类型 / 构造器 | 字段和语义 |
|---|---|
| `UiRecomputeInput(...)` | `DataSnapshot previousSnapshot`、`Map<String, Object?> currentUiState`、`UiPublishToken token`。状态表复制并不可修改；键集必须等于 snapshot.initialUiState，值限既有 `isUiScalar`（null/String/bool/有限 num），拒绝列表、Map、Set、自定义对象与非有限数。itemIds 属单独选择层，不进入此表。构造违规抛 `ArgumentError`。 |
| `UiRecomputeResult(...)` | `UiPublishToken token`；`DataSnapshot? nextSnapshot = null`、`InteractionIntent? nextIntent = null`、`List<String> errors = const []`。候选态：两个对象同时非 null 且 errors 空；失败态：两个对象同时 null 且 errors 非空。其他组合抛 `ArgumentError`。errors 复制并不可修改。合法 unavailable 输出可构造候选（nullable computed），不是 result 失败。 |
| `UiRecomputePort` | `Future<UiRecomputeResult> rebuild(UiRecomputeInput input)`。只有抽象接口，没有默认执行器、超时、调度或异常捕获。实现须原样携带 input.token；调用方负责捕获 Future 异常与降级。 |
| `const UiPublishToken(...)` | `SnapshotRef baseSnapshotRef`、`int draftRevision`、`int hostGeneration`、`int sourceGeneration`、`int permissionGeneration`、`String scopeKey`。六字段完整值相等 / hashCode；SnapshotRef 的 id 和 revision 均参与；scope 逐字比较，不规范化；不约束计数范围或授予权限。 |
| `const UiVersionBatch(...)` | `UiPublishToken token`、`DataSnapshot snapshot`、`InteractionIntent intent`、`UIPlan plan`。原始候选 batch，保留四者对象身份；不宣称已经通过 validateUiPlan / publish admission。 |
| `UiPublishOutcome` | `published`、`staleToken`、`invalid`、`disposed`，无额外状态。invalid diagnostics 将由后续 controller.publicationErrors 提供。 |
| `UiPublishTokenProbe` | `typedef UiPublishTokenProbe = UiPublishToken Function()`，同步读取宿主当前完整 token，不是 bool 授权探针。 |

仅 token 有值相等语义。input/result/batch 和引用的 snapshot/intent/plan 保持对象身份，不做副本或新增结构值相等。直接集合参数防御性复制；状态值仅允许不可变标量，因此不存在可变嵌套集合。引用对象沿用既有类型的冻结保证和 validator 责任，本片不重建快照/节点、不添加第二套 validator。

`currentUiState` 是全量当前标量值，并非仅 changed key。它与 extracted 分离：例如 previousSnapshot.initialUiState.qty 为 String `'2'`，输入 qty 可以为 String `'3'`；构造器不解析、规范化、转换 decimal，也不把人工值写回 snapshot。qty String / 公式 state 必须 String 且 `!view` 的检查归现有宿主与 F5b spec 校验，本接口不把所有非公式 bool/num 状态一概禁止。

## H2 patch（仅 F5b owner 应用）

本分支没有修改 `ui_contract.dart`；F5b 在审查通过后向该文件 export 列表新增一行：

```dart
export 'src/ui/recomputation.dart';
```

H2 前临时消费方式（同包测试允许 src 引用，本次 CI 会核验）：

```dart
import 'package:muyon_module_api/src/ui/recomputation.dart';
import 'package:muyon_module_api/ui_contract.dart';
```

## 下一阶段依赖与明确未实现项

F3b 独占 `apps/muyon/lib/platform/ui_recompute_adapter.dart` 和 PR18 测试。F5b 独占 snapshot/plan/validation/state/stream_protocol/stream_compiler、ui_contract.dart、surface、输入/布局、新 edit_spec/collection/catalog_library2/component_adapter，本片未改这些文件。

后续同步 `UiPublishOutcome publish(UiVersionBatch batch, UiPublishTokenProbe current)` 由另派任务实现。本片没有 publish/controller/rebase/workspace/store/planning/nav，没有模型、IO、权限提升、缓存或 DAG。以下是交接约束，**本片测试未证明这些运行行为**：

- published S8.initialUiState 保 extracted；人工值仅 currentUiState / userOverrides；恢复与 adopt 继续三层分离。
- 全部将显示的 computed（含 collection cell）必须真实重算，不得仅改旧值 inputVersion；qty 严格 decimal String，公式 state 必须 String 且 !view。
- 同 controller/session/mounted 身份原子发布，plan revision 严格递增，draftRevision 不降，完整 token 在发布前复核，旧渲染回调冻结 plan 身份，旧 capability 失效，pending 不重放。
- 导航 await 后及 push 前同步重核，final probe 与 push 之间无 await；失败释放已取得 lease。
- result/batch 的关联一致性、当前权限、computed evidence 和所有单调 revision 条件由 adapter / 现有 validator / 后续 publish 检查，本片构造器不假装提供 admission。

## 验证记录

本环境无 Dart/Flutter；遵循用户要求未下载 Flutter SDK，使用既有 GitHub Actions Linux ci（scripts/ci.sh：全 8 包 analyze / 全 8 套测试）。原始日志只保留 Actions artifact，不入仓库。纯测试使用宿主提供的计算值夹具，不是实际公式重算或模型证据。

- 最小 RED 提交：`40b121a99e019a2e1fc1c6f19dc517328fdb11d1`。scaffold 提供可编译声明，故检测 token 相等 / map 修改行为，不能把编译失败算作 RED。
- RED 与 GREEN CI 终态、完整实现 SHA 和远端读回将写入 PR body；如有失败如实列出，不以静态阅读代替执行。
- 未测：运行发布、重算 adapter、恢复、导航、模型、真机、macOS golden，以及 F5b/F3b 组合 CI / H2 应用后导出消费。
