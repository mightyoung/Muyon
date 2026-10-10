# AIUI 流式界面契约 v1

日期：2026-10-09 · 状态：已采纳（作为 AIUI-1 的验收依据）· 上位文档：[AI 原生界面方案](ai-native-ui-redesign-2026-10-09.md) §5.1
代码依据：`packages/muyon_module_api/lib/src/ui/plan.dart`（`UIPlan`、`UiNode`、`ActionBinding`、`UiCatalog`）、`snapshot.dart`（`DataSnapshot`、`BindingRef`、`UiActionContext`）、`validation.dart`（`validateUiPlan`）。

本契约只**补清**现有类型怎样以流的形式产生，不改变 `UIPlan` 的语义，也不放宽现有校验器的任何规则。

## 1. 谁提供什么

| 信息 | 来源 | 模型能否在流里写 |
|---|---|---|
| `surfaceId`、`revision`、`catalogVersion`、`snapshotRef`、`intentRef` | 宿主在开流时建立 `UiStreamSession` 时给定，取自本次规划请求 | **不能**。流里出现这些字段的行按「坏行」处理 |
| 根节点 id | 宿主在会话里给定（默认 `root`） | 模型必须用这个 id 发出第一个节点 |
| 组件、属性、绑定、子节点 | 模型 | 能，受组件模式约束 |
| 动作的路由（本地 / 业务 / 语义） | 目录 `catalog.actions[actionRef].route` | **不能**。流里出现 `route` 字段的行按坏行处理 |
| `actionRef` | 模型从目录和 `intent.allowedActionRefs` 里选 | 能，只能选已登记的 |
| `inputRefs` | 模型引用宿主已声明的键：业务动作引用 `actionContext.draft` 或 `confirmedRecordRefs`；本地编辑引用 `initialUiState` | 只能引用，不能新建 |
| `operationKeyRef` | 模型引用宿主 `actionContext.operations` 里已有的键 | 只能引用；操作的内容由宿主定义 |
| `expectedDraftRevision` | **宿主**仅为业务动作填入本会话快照的 `actionContext.draftRevision`；本地/语义动作保持 `null` | **不能** |
| 事实、计算值、来源片段、界面状态的值 | 宿主快照 | 只能按 id 引用 |

**缺字段一律拒绝，不猜默认值。** 例如业务动作缺 `operation` 或 `inputs`，这一行按坏行处理，不会拿某个「常用操作」来补。

## 2. 行格式（JSON Lines）

每行一个 JSON 对象，必须含 `op`。首版只有 5 种操作：

```
{"op":"text","md":"三家报价里，云川含税最低。"}
{"op":"node","id":"root","component":"Section","props":{"title":"报价对比"}}
{"op":"node","id":"t1","parent":"root","component":"CompareTable","bind":{"rows":{"kind":"fact","id":"quotes"}}}
{"op":"patch","id":"t1","props":{"highlight":"min"}}
{"op":"action","node":"t1","event":"select","action":"inquiry.award","inputs":["draft.quote_id"],"operation":"award"}
{"op":"end"}
```

### 2.1 映射到现有类型
| 行 | 映射 |
|---|---|
| `node` | `UiNode(id, component, properties: props, bindings: bind)`；按到达顺序追加到父节点的 `children` |
| `bind` 的每一项 | `BindingRef(kind, id)`，`kind` 只能是 `fact` / `computed` / `uiState` / `sourceSpan` |
| `action` | `UiNode.events[event] = ActionBinding(actionRef: action, inputRefs: inputs, operationKeyRef: operation, expectedDraftRevision: <仅业务由宿主填，本地/语义为 null>)` |
| `text` | 不进 `UIPlan`；作为回答的文字段落按顺序保存，计入文字上限 |
| `end` | 触发最终校验（§4） |

## 3. 树与 patch 的行为（首版）

| 情况 | 结果 |
|---|---|
| 第一个 `node` 不是宿主给定的根 id，或根节点带 `parent` | 坏行 |
| 非根节点缺 `parent`，或 `parent` 还没出现 | 坏行（父必须先到） |
| 父节点的组件不允许子节点（`allowsChildren == false`） | 节点进入候选计划，预览里不渲染（交给最终校验报 `children:`） |
| 重复 `id` | 后到的那行是坏行，先到的保留 |
| `patch` 目标不存在 | 坏行 |
| `patch` 的合并方式 | **只改 `props`**，逐键合并；值为 `null` 表示删掉这个键（删掉必填属性会在最终校验时报错） |
| `patch` 后这个节点单独校验不通过 | 候选计划保留 patch 后的值（最终校验会看到并拒绝）；预览里**回到该节点上一次通过时的样子**，并标出诊断 |
| 删除节点、调整顺序、换父节点、修改 `bind` 或 `component` | 首版不支持，按坏行处理 |
| 同一个节点的同一个 `event` 出现第二次 `action` | 坏行 |

## 4. 增量预览与最终计划分开

- **候选计划**：所有能表示成 `UiNode` 或 `ActionBinding` 的行，原样累积成一个候选 `UIPlan`。单节点校验不通过的节点**仍留在候选计划里**，不删除。
- **增量预览**：每到一行，就用从 `validateUiPlan` 里抽出来的**单节点规则**校验这个节点：组件存在、属性类型、必填属性、绑定种类与存在性、事件与动作是否兼容、本地或业务动作的输入要求。通过的节点渲染；不通过的显示为占位。**占位是编译状态（`placeholder(reason)`），不是目录里的组件**，不会出现在候选计划里。父节点是占位时，它的子孙都不渲染（`blocked_by_parent`）。
- **最终计划**：收到 `end` 后，对**完整的候选计划**跑现有的 `validateUiPlan`。这一步才检查整树规则：可达性、环、多父、节点上限、意图要求的必显绑定（`required_binding`）、必显状态（`mandatory_state`）。
  - 通过：得到 `ValidatedUiPlan`，回答定稿，动作才可以点。
  - 不通过：整份界面作废，回答退回「文字加宿主模板卡片」（方案 §5.1 的退路），诊断写进执行记录。
- **只要出现过坏行，最终计划就一定不通过**（`malformed_stream`）。不能先删掉坏行或坏节点，再宣布「其余部分合法」。
- 单节点规则必须从 `validation.dart` **抽取复用**（重构成可以单独调用的函数，`validateUiPlan` 改为调用它们），不能另写一套。

**差分要求**：对同一份原始候选计划，流式编译到 `end` 的**计划校验结果**（通过与否、错误集合）必须与一次性交给 `validateUiPlan` 完全一致，包括带坏节点的候选。协议错误独立保留在 `streamErrors` 中；整体成功还要求无协议错误、未中断且未超限。坏行不能表示为 `UIPlan`，因此 `malformed_stream` 是协议层的最终否决，不伪装成批量校验器产生的错误；也不能清除坏行后宣布流成功。

## 5. 绑定的范围（AIUI-1）

- `fact`：只能是 `snapshot.facts` 里已有的 id。
- `computed`：只能是 `snapshot.computations` 里**宿主已经算好**、并且 `inputVersion` 等于本次快照的结果。流里不接受公式、表达式或模型给出的结果；出现 `formula`、`expr`、`value` 这类字段的绑定按坏行处理。公式登记与宿主计算归 AIUI-3。
- `uiState`：只能是宿主在 `initialUiState` 里声明过的键。模型不能新建界面状态；本地编辑、排序的输入仍按现有规则，必须是 `uiState` 绑定。
- `sourceSpan`：只能是 `snapshot.sources` 里已有、且摘要与 `sourceDigests` 一致的片段，来源卡和「展开来源」不受影响。

## 6. 中断、重复与上限

| 情况 | 结果 |
|---|---|
| 流在 `end` 之前关闭（不论最后一行是否完整） | 状态 `incomplete`；预览保留但标「未完成」；**任何动作都不可点**；最终计划不成立，走退路 |
| 半截的行（不能解析为 JSON） | 坏行 |
| 已收到完整的 `action` 行，但没有 `end` | 动作不生效。动作只有在最终计划通过之后才可点，预览期间所有动作按钮都是禁用状态 |
| 第二个 `end`，或 `end` 之后的任何行 | 忽略，记一条 `after_end` 诊断；结果以第一个 `end` 为准 |
| 超过任一接收上限 | 状态 `limit_exceeded`，**停止接收**，之后的行（包括 `end`）只计数不处理；最终计划不成立 |

上限采用包含边界：≤N 允许，N+1 越界终止。因此恰好200节点后的 `end` 可以完成。保存诊断条数仅限制存储，达到100后只计数，不停止流；其它接收上限超出后终止。

上限（首版取值，放在一个常量对象里，测试按常量取值；字节按 UTF-8 计）：

| 项 | 上限 |
|---|---|
| 节点数 | 200（与现有校验器一致） |
| 树深度 | 12 |
| 单行字节 | 16 KB |
| 文字总量（`text` 加所有字符串属性） | 64 KB |
| 总行数（防止无穷 patch） | 2000 |
| 坏行数 | 20 |
| 每个节点的 patch 次数 | 20 |
| 保存的诊断条数 | 100，之后只计数 |

## 7. 测试要求
- 上面每一行规则至少有一个**拒绝路径**的测试，不能只测正常流程。
- 四个规定变异，各自要被**指定的测试**检出：
  - (a) 跳过单节点校验 → 预览渲染了不合法节点的测试失败；
  - (b) 允许绑定快照里不存在的事实 → 绑定范围测试失败；
  - (c) 中断时让动作可点 → 中断测试失败；
  - (d) 去掉节点上限 → 上限测试失败。
- 差分测试（§4）。

## 8. 版本
本契约记为 `aiui-stream/1`，由宿主在会话里声明。以后增加删除、重排、换父等操作时，升到 `aiui-stream/2`；对旧版本的流按 v1 规则处理，不认识的 `op` 一律是坏行。

## 历史实现版本补记（2026-10-10，固定7773b7d，不改写v1规则）

固定develop `7773b7d96bc99f173b57a723d61526fba0df49ff` 已合PR26源 `f29819b24187654642a36685592a4c02abfac854`，`stream_protocol.dart` 同时接受/1与/2，library-2要求/2；v1显式拒绝collection绑定。该片仅协商与防误用门槛，不代表collection值校验/typed编辑/33组件渲染全部可用。此前§8“以后升到/2”是v1定稿时的计划，不能据此否认当前已有协商；也不能据/2存在宣称删除、重排、换父等操作已支持。

F5六项细化的[leader技术采纳记录](../tasks/AIUI-5-leader-contract-decision.md)及proposed历史均保留；PR21/28/30等尚未合的接口/接线按[交付队列](../tasks/NEXT-DELIVERIES-2026-10-10-v1.md)记录。流式/一次性计划仍复用同一validator与renderer，模型只引用宿主事实/状态/来源/动作，不提供计算结果、权限或执行代码。预测胶囊/视频属需求已确认、设计待审，不新增v1 op或受信媒体路径；需要公共契约变化时单独版本化提案。

## 2026-10-10 PR36～39 实施范围

上述“尚未合”仅指7773历史快照，当前来源与验收以[本批集成审查](../tasks/AIUI-36-39-integration-review.md)
及既有各片审查记录为准。本批不修改操作集、上限、目录、共享校验、路由或模型权限。
F4c只从当前已验证计划绑定的collection提取宿主fact引用；collection cell仍只准入
fact/computed。原导航仅复核snapshot身份和task scope；独立审查确认末窗口缺口，
aaa175修复复用现成模块authority、同步整来源proof及真实pinned解析，最终核验至push
无await，尚待旧fixture精确迁移授权及新完整CI。它不是完整H3。没有接受模型生成的值、页面授权
或行tap业务mapping。
AIUI-9为宿主固定只读KeyValue模板，不接模型UIPlan、模型组件/动作或可执行回调，
保存事实与建议分开、凭据排除、显示预算复用；它不代表动态编辑卡或写工具流程已完成。
控制页的只读授权查询不等于授权签发入口；新的完整组合与发布CI单独核验。
