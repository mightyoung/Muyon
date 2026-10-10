# AIUI 验收追溯（2026-10-10）

给 [AIUI 默认开启计划](../tasks/AIUI-DEFAULT-ENABLE-PLAN.md)、验收账本 AIUI 补记和 Leader B 派工用。本文只读代码和测试，不改产品代码。

- 分支 `task/grok-8-aiui-acceptance-trace`，任务基线 `7f49efe`（develop 祖先 `a68ba43`）。
- 环境：Flutter 3.47.5（stable，revision `6a19cca564`）/ Dart 3.13.4 / Engine `ab59836859`。
- 要求来源：[AI 原生方案](../design/ai-native-ui-redesign-2026-10-09.md) §4.1–4.4、§5.1–5.5、§6、§8；[编辑重算验收](../tasks/AIUI-EDIT-RECOMPUTE-ACCEPTANCE.md) §3 的 14 个未来场景。
- 状态只取四字：已接线有测试 / 已实现仅测试可达 / 已实现无测试 / 未实现。
- 「已接线」指从 `bootstrap.dart` 或 `platform_shell.dart` 能沿 `lib/` 调用追到实现。默认开关为关，只要调用点在生产文件里，仍算接线，并在调用链里写明默认值。
- 行号对应该基线。设计稿里的 `inquiry_module.dart:308` 已过时，本体表现在从 `inquiry_module.dart:286` 起。

## 生产路径（下文用代号）

| 代号 | 路径 |
|---|---|
| P0 | `bootstrap.dart:318-328` 构造 `PersonalAgent`（`uiPlanningEnabled: false`，`UiPlanningMode.motivation`）；`:406` `host.modules.registerTools()` |
| P1 | `app_shell.dart:253` 打开 `PlatformShell`；`:213-219` 把已保存的 `reduceMotion` 并进 `MediaQuery.disableAnimations` |
| P2 | `platform_shell.dart:44-48` 四项目的地；`:80` 默认 `section = 0`（助手）；`:422-434` 用 `ConversationWorkspaceHost` 包住四个区 |
| P3 | `conversation_workspace_pane.dart:181-204` 宽度达到 1250 且已打开会话时，右侧放工作区；`:387` `DynamicUiSurface` |
| P4 | `assistant_page.dart:600-627` 内存里的规划开关；`:726-758` 成功任务上的「规划此回答 / 打开交互页面」，构造 `DynamicWorkspace` 时不传 `businessActions` |
| P5 | `dynamic_workspace.dart:156-179` 规划未开则事件抛 `planning_disabled`；否则交给 `UiPlanningEventRouter` |
| P6 | `ui_planning_source.dart:60-78` 生产目录是 `dynamicUiCatalog`，允许动作只有 `detail`、`back` |
| P7 | `inquiry_module.dart:59-65` → `inquiry_record_tools.dart:324` 登记四个通用写工具 |

`catalog.dart:164-167` 写明：规划器继续用 `dynamicUiCatalog`，要等 AIUI-1 / AIUI-5 才把流式编译和库组件接上。库组件的渲染分支在 `component_adapter.dart:115`，能从 P3 追到，但 P6 不会发出这些组件名。

## 1. 要求 → 代码 → 测试 → 生产入口

### 4.1 外壳

| 要求 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| 打开应用直接进入助手对话 | `platform_shell.dart:44`、`:80` | `responsive_shell_test.dart` `assistant_is_default_and_four_destinations_are_exact` | P1→P2 | 已接线有测试 |
| 手机回答以卡片和小工具呈现 | 默认消息是文字 `Card`：`assistant_page.dart:667-677`。交互页要先打开规划再进 P4 | 同上；交互页见 `conversation_workspace_pane_test.dart` `resize_moves_one_surface_without_duplicate_controller_or_dispatch` | P2→助手页。小工具还要 P4→P5→P3，且 P0 默认关 | 已接线有测试 |
| 桌面中间是对话，右侧是当前工作区 | `conversation_workspace_pane.dart:12-13`、`:181-204` | `conversation_workspace_pane_test.dart` `desktop_opening_another_surface_replaces_disposed_view_owner` | P2→P3。宽度不足 1250 时工作区走手机整页路由，不出现右栏 | 已接线有测试 |
| 底栏 / 图标轨四项：助手、任务、资料、设置 | `platform_shell.dart:44-48`、`:477-507` | `responsive_shell_test.dart` `four_destinations_320_390_430_900_1250_1280_at_200_percent` | P1→P2 | 已接线有测试 |
| 任务区放进行中和待确认任务、子对话、执行记录，不再用收件箱和工作台当底栏项 | `platform_shell_home.dart:4-31`、`:34-119`；子对话按钮 `assistant_page.dart:718-723` | `conversation_shell_navigation_test.dart` `legacy_entries_remain_reachable` | P2 第二项 → `taskHub()` | 已接线有测试 |
| 资料按对象检索，并可打开原来的固定业务页 | `platform_shell_knowledge.dart:17-37`、`:40-58`；`platform_shell.dart:220-258` | `conversation_shell_navigation_test.dart` `data_and_answer_open_same_registered_business_page` | P2 第三项 | 已接线有测试 |
| 设置里有模型 | 模型下拉从 `platform_shell_personal.dart:251` 起 | 无单独测试名对上这个下拉 | P2 第四项 → `settings()` | 已实现无测试 |
| 设置里有助手权限（ADR-0002） | 只读控制页 `assistant_control_page.dart:82-89`，入口 `platform_shell_personal.dart:221`。没有签发、撤销或改策略 | `aiui4c_settings_entry_test.dart` `settings reaches read-only assistant control and returns width=$width`；`aiui8_assistant_control_test.dart` `real SQLite grant detail and audit do not mutate records` | P2 → 设置卡 → `AssistantControlPage.host` | 已接线有测试 |
| 设置里有「界面与可视化」自动 / 少用 / 只用文字 | 未实现。现有开关是另一回事，见第 3 节 | 无 | 无 | 未实现 |
| 设置里有数据去向 | 控制页说明指向数据去向；`platform_shell_personal.dart:208-214` 把 `DataFlowPage` 放进数据与存储 | `aiui8_assistant_control_test.dart` `loading then empty records and existing ledger entry` | P2 → 设置 → 数据与存储，或控制页文案 | 已接线有测试 |
| 设置里有插件 | `platform_shell_personal.dart:226`「接口与工具」；同文件 `:215` `McpServersPage` | 无与本行对应的测试名 | P2 → 设置 | 已实现无测试 |
| 业务插件和数据交换不再单独占底栏 | 底栏只有四项。数据交换在任务区里：`platform_shell_home.dart:22-25` | `responsive_shell_test.dart` `assistant_is_default_and_four_destinations_are_exact` | P2 | 已接线有测试 |
| 业务页从回答或资料打开；收发并进任务 | 回答引用 `assistant_page.dart:679-691`；资料 `openObject`；任务区「数据交换」打开 `DevicesPage` | `conversation_shell_navigation_test.dart` `data_and_answer_open_same_registered_business_page` | P2 → 资料或回答 chip；任务区按钮 | 已接线有测试 |

### 4.2 回答的四种形态

| 要求 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| 文字形态 | `assistant_page.dart:677` `SelectableText` | `responsive_shell_test.dart` 打开默认助手。没有单独断言气泡文案的测试名 | P2 | 已接线有测试 |
| 文字加补充卡：对象 chip 和来源卡 | 回答引用是 `ActionChip`：`assistant_page.dart:684-690`。`SourceCard` 在 `ui_components/business.dart:25`，只在库组件计划里出现 | 引用打开见上一节导航测试。`SourceCard` 见 `ui_components_test.dart` `FileCard`/`SourceCard` 控件组（`controls`） | chip：P2。`SourceCard`：只有计划含该组件时才从 P3 进 `component_adapter.dart`；P6 不发这个名字 | 已接线有测试 |
| 交互小工具：改数量、含税，总价由宿主重算 | 公式有乘积和含税：`ui_formula_registry.dart:73`、`:86`。没有对话里的比价小工具去调用它们 | `ui_formula_registry_test.dart` `product_decimal_rounds_once`、`tax_price_matches_supplier_core` | 仅测试，以及只被测试引用的 `ui_recompute_adapter.dart`。P0–P6 不构造 `UiFormulaRegistry` | 已实现仅测试可达 |
| 交互小工具：拖动加价率看毛利 | 毛利额 `ui_formula_registry.dart:105`。`budgetUnitPrice`（`:119-125`）注释写明不是加价率预览。没有拖动控件接上 | `ui_formula_registry_test.dart` `margin_is_amount_not_percentage`、`markup_preview_matches_budget_unit_price` | 同上一行 | 已实现仅测试可达 |
| 工作区：导入审阅的分组表格 | `import_review_projection.dart:14`；任务菜单打开 `inquiry_import_context.dart`（`platform_shell_home.dart:58-64`） | `inquiry_import_pipeline_test.dart`（文件内多个 `ImportReviewView` 用例；本轮跑了该文件） | P2 任务项 →「从文件导入业务」 | 已接线有测试 |
| 工作区：论文阅读器；回答里只留摘要卡和「打开工作区」 | 资料检索可以打开已有 PDF 预览 `knowledge_preview.dart:17`，调用在 `platform_shell.dart:311`。没有回答摘要卡，也没有从回答打开的阅读器工作区 | 无 | 预览只从资料检索进入，不是本条要求的回答工作区 | 未实现 |
| 回答末尾的追问选择（单选、多选、可自填、条件表单） | `Choice` 控件 `inputs.dart:20`（`allowCustom` 默认 false）、`:213`。生产规划目录不含它 | `ui_components_test.dart` `every event action exists; inputs only edit; submit is business` 覆盖 Choice 的 `edit` 动作。没有对上「自填回传」的测试名 | 控件可从 P3 渲染；P6 不发出 Choice | 已实现仅测试可达 |
| 选择以结构化数据回传模型，不用再打字 | 语义路由把一段英文说明交给新任务：`ui_planning_events.dart:70-76`。不是结构化选项载荷 | `ui_planning_events_test.dart` `three_event_routes_preserve_authority with actual host Store and receipts` | P4→P5 会进路由器；P6 的允许动作没有语义动作，生产计划发不出这条 | 未实现 |

### 4.3 动作与确认

| 要求 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| 本地动作不经模型，立刻生效，只改界面状态 | `dynamic/catalog.dart:151-154` `sort` 为 `UiActionRoute.local`；路由器对 local 直接返回 `ui_planning_events.dart:44` | `ui_planning_events_test.dart` `three_event_routes_preserve_authority with actual host Store and receipts` | P4→P5。P6 允许的是 `detail`/`back`，不是 `sort` | 已接线有测试 |
| 业务动作出确认卡；批准或已有授权才执行；成功以回执为准 | 动态确认卡 `surface.dart:843-888`，回执改状态。`AssistantPage` 打开工作区时 `businessActions` 用默认空 map（`dynamic_workspace.dart:31`）。空映射在 `ui_planning_events.dart:48-51` 抛 `business_port_unavailable`。助手普通工具写入仍走原确认门，不走这张回答卡 | 组件：`confirmation_test.dart` `batch and warn banner external-content restrictions`。路由：`ui_planning_events_test.dart` 同上，测试自己传入映射 | 卡片渲染在 P3。从 P4 打开的工作区没有业务映射，确认不会执行工具 | 已实现仅测试可达 |
| 语义动作作为新意图交回模型 | `ui_planning_events.dart:70-76` `startUiSemantic`；目录动作 `explain` 在 `dynamic/catalog.dart:160` | `ui_planning_events_test.dart` 同上 | P5 有调用。P6 不允许 `explain`，这条生产计划到不了 | 已接线有测试 |

### 4.4 本体驱动的业务卡片

AIUI-9 任务书写明：只读切片，未接对话和对象导航，全部提交禁用。下面凡是「仅测试可达」，都是这个边界，不是漏登记。

| 要求 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| 插件在 v2 契约注册本体 | 询价 `inquiryOntology`：`inquiry_module.dart:286` | `inquiry_general_write_tools_test.dart` `registers four generic writes with the seven ontology types` | P0 `registerTools` → 模块 `registerTools` | 已接线有测试 |
| 对话里直接生成业务表单卡片 | `OntologyCard` 是固定只读模板，`ontology_card.dart:6-8`。`lib/` 里没有其他文件引用它 | `aiui9_ontology_card_test.dart` `real host read maps into component with disabled submit and no writes` | 仅测试可达 | 已实现仅测试可达 |
| 新建卡：字段类型决定输入组件，必填标出，敏感字段按 Q7 遮盖 | 只读投影把必填写进标签：`ontology_card.dart:22`。没有按字段类型生成输入组件。敏感遮盖在快照投影 | `aiui9_ontology_card_test.dart` `sensitive values and credentials never reach text or semantics` | 仅测试可达 | 已实现仅测试可达 |
| 新建卡提交走插件写工具，经确认或授权，成功以回执为准 | 提交按钮禁用：`ontology_card.dart:32`。写工具本身在 P7，卡片不调用 | 同上 `real host read maps into component with disabled submit and no writes` | 工具：P7。卡片：仅测试 | 未实现 |
| 编辑卡：快照加字段清单，只显示选中字段，其余可展开 | 未实现。现卡展示投影字段，不能按选中字段折叠 | 无 | 无 | 未实现 |
| 编辑只提交改动字段，带修订号，冲突则提示 | 工具层有 `expected_version`：`inquiry_record_tools.dart` 与 `inquiry_general_write_tools_test.dart` `explicit expected_version refuses a stale update even with fresh scope`。卡片没有提交 | 工具测试如上。卡片无 | 工具：P7。卡片未接 | 未实现 |
| 关联卡：选已有对象，或就地新建再关联 | 关联值保持未活化文字。任务书与 `aiui9` 测试 `references and opaque object values cannot activate a route` | 该测试 | 仅测试可达，且明确不导航 | 未实现 |
| 批量卡：Table 加逐行状态，走 BatchConfirmCard | 未实现 | 无 | 无 | 未实现 |
| 本体或工具更新后，对话卡片自动跟上，不用改插件页和宿主 | 未实现。没有生成器读本体来拼输入卡 | 无 | 无 | 未实现 |
| 固定页没有的新字段，在对话卡片和资料对象详情里可见可改 | 资料对象页对询价是 JSON 加「在业务页面查看与编辑」：`platform_shell.dart:360-372`。不是按本体字段生成的可编辑详情。对话卡不可编辑 | 无对上「新字段自动可改」的测试名 | P2 `openObject` 只到 JSON / 原页面 | 未实现 |
| 卡片结构由宿主按本体生成；模型只决定哪张卡、预填和先显示哪些字段 | 宿主模板固定。模型建议单独一行，不进组件名：`ontology_card.dart:23-24` | `aiui9_ontology_card_test.dart` `real host read maps into component with disabled submit and no writes` | 仅测试可达 | 已实现仅测试可达 |
| 模型预填标「建议」，确认前不算数 | `ontology_card.dart:24`「建议（尚未写入）」 | 同上 | 仅测试可达 | 已实现仅测试可达 |
| 用插件自己的校验器，提交前和执行时各校验一次；非法字段就地标红，不发请求 | 写工具执行路径会校验（P7）。卡片任务书写明不做领域校验，也没有就地标红 | 工具侧见 `inquiry_general_write_tools_test.dart`。卡片无 | 卡片未接 | 未实现 |
| 只有登记了写工具的类型才出新建或编辑卡 | 文案分流：`ontology_card.dart:27-29`。类型没有通用修改时提示原页面。仍然不是可提交的新建/编辑卡 | `aiui9_ontology_card_test.dart` 覆盖未开放类型文案（`unknown type and higher version safely retain read-only fallback` 及未开放提示） | 仅测试可达 | 已实现仅测试可达 |
| 覆盖清单里不开放的操作显示「请在原页面操作」并给出入口 | 卡片是文字，没有导航入口：`ontology_card.dart:29-31`。覆盖清单在 `coverage.dart:41-64` | `inquiry_general_write_tools_test.dart` `coverage registers CRUD and gives specialized writes explicit deferred reasons`；卡片测试见上 | 清单：P7。入口：仅测试，且未接 F4c 导航 | 已实现仅测试可达 |
| `personal` / `commercial` 默认遮盖；`credential` 不进卡片 | 快照投影在进控件前遮盖；`_sensitivity` 在 `inquiry_module.dart:257-283`，不返回 `credential` | `aiui9_ontology_card_test.dart` `sensitive values and credentials never reach text or semantics` | 仅测试可达 | 已实现仅测试可达 |
| 不认识的字段类型或更高契约版本：只读原值，提示「请在原页面编辑」，不猜输入、不提交 | `ontology_card.dart:19`；测试期望文案「不支持的本体版本或类型，请在原页面编辑」 | `aiui9_ontology_card_test.dart` `unknown type and higher version safely retain read-only fallback` | 仅测试可达 | 已实现仅测试可达 |
| 询价先做，本体已经注册 | `inquiry_module.dart:286` | 见本体注册那一行 | P7 | 已接线有测试 |
| 补按本体的新建、修改、删除（REG-4c）；宿主不再只有 4 个具体写工具 | `inquiry_record_tools.dart:329-334` 四个通用工具，另有既有具体写工具 | `inquiry_general_write_tools_test.dart` `registers four generic writes with the seven ontology types` | P7 | 已接线有测试 |
| 科研、原型等迁到 v2 后再做卡片 | 没有这些模块的本体卡 | 无 | 无 | 未实现 |

### 5.1 流式界面协议

编译器没有 `apps/muyon/lib` 调用点。`UiStreamCompiler(` 只出现在 `stream_compiler.dart:64` 和测试里。AIUI-1 的任务范围是协议层。下面除特别写明外，生产链都是「仅测试可达」。

| 要求 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| 模型输出 JSON Lines 界面片段 | `stream_protocol.dart:97` 起的操作类型；`stream_compiler.dart:91` `addLine` | `ui_stream_test.dart` `session metadata and protocol version are host owned` | 仅测试可达 | 已实现仅测试可达 |
| 逐节点校验，失败换占位并记下原因，不影响其他节点 | `stream_compiler.dart:261-277`、`:324` `placeholder` | `ui_stream_test.dart` `node validation isolates placeholders and blocked descendants` | 仅测试可达 | 已实现仅测试可达 |
| 绑定只能是快照事实或登记公式；动作只能是目录里的动作；编译时检查 | `ui_stream_test.dart` 与校验器同源。AIUI-1 不接受公式，见下 | `binding range rejects missing facts without rendering`；`action binding and allowlist rejection matrix matches batch` | 仅测试可达 | 已实现仅测试可达 |
| `op:end` 收尾；中断保留已渲染部分并标未完成 | `stream_compiler.dart:281-283` `interrupt()` 把阶段设为 `incomplete` | `interrupted action remains disabled after complete action line`；`every truncated action line is inert and malformed` | 仅测试可达 | 已实现仅测试可达 |
| 文字和界面交替，文字按段落流式出现 | 协议有 `UiStreamText`（`stream_protocol.dart:99`）。生产回答不是这条流，`protocol_stream_view.dart` 只扫描兼容模式文本，由 `agent_drafts.dart:12` 引用 | `ui_stream_test.dart` `pure text and empty end follow batch empty plan rejection`；`protocol_stream_view_test.dart` | 文本扫描从助手草稿追得到。界面片段编译器追不到 | 已实现仅测试可达 |
| 不能稳定输出该格式的模型，退回文字加固定卡片，宿主按任务阶段选模板 | 失败退回 `textOnly`：`ui_planning.dart:61-68`。没有按阶段选的固定卡片模板 | `ui_planning_harness_test.dart` `planner_failure_keeps_conversation for missing invalid timeout providers` | P0→`UiPlanningHarness`。退回的是纯文字，不是固定卡片 | 未实现 |
| 元信息和路由由宿主决定，模型不能自报 | `ui_stream_test.dart` 首条用例名即此意；实现于编译会话 | `session metadata and protocol version are host owned` | 仅测试可达 | 已实现仅测试可达 |
| `expectedDraftRevision` 由宿主填 | `ui_stream_test.dart` `business revision host filled; local refs remain null` | 该测试 | 仅测试可达 | 已实现仅测试可达 |
| 缺业务字段一律拒绝 | 同上文件 `duplicate events and missing business operation cannot finalize` | 该测试 | 仅测试可达 | 已实现仅测试可达 |
| 占位是编译状态；最终计划整树校验 | `batch coverage only applies at end and unknown component never satisfies it` | 该测试 | 仅测试可达 | 已实现仅测试可达 |
| AIUI-1 不接受公式，只引用宿主快照里已经算好的结果 | 流编译器不调用 `UiFormulaRegistry` | 无单独测试名把「编译器拒绝公式」写进标题。公式在另一套注册表 | 两条路都不从 P0 进入 | 已实现无测试 |

### 5.2 组件库 v1

21 个库组件名单在 `dynamic/catalog.dart:370-392`。安全类四件在 `dynamicUiCatalog`（`dynamic/catalog.dart:106-147`）和 `confirmation.dart` / `primitives.dart`。每个库组件的四态框在 `ui_components/state.dart` 的 `UiComponentFrame`。渲染开关在 `component_adapter.dart:115`，生产上要等计划里真有这个组件名。

| 要求 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| 版式：Heading、Prose、Section、Columns、Tabs、Disclosure | `ui_components/layout.dart`；名单 `catalog.dart:371-376` | `ui_components_test.dart` `every library component is registered with a schema`；golden：`component_library_goldens_test.dart` | P3→适配器。P6 不发这些名字 | 已接线有测试 |
| 数据：Table、CompareTable、KeyValue、Metric、Chart | Table 在 `dynamic/catalog.dart:87`。其余在 `ui_components/data.dart`。CompareTable 标记 `data.dart:141-148`（最优 / 不满足 / 未核验）。Chart 只有柱、折线、饼：`data.dart:315` | `chart and data components take numbers only from bindings`；对比度 `light pairs the library adds meet 4.5:1`（暗色同一循环） | Table 在 `dynamicUiCatalog` 里，P6 可以发出。其余同库组件 | 已接线有测试 |
| 输入：Choice、Form、NumberStepper、Slider、Toggle、DateField | `ui_components/inputs.dart`；Choice 可自填开关默认关：`:20`、`:213` | `every event action exists; inputs only edit; submit is business` | 同库组件。自填回传没有对上的测试名 | 已接线有测试 |
| 业务：ObjectChip、SourceCard、FileCard、ProgressCard、Checklist、Timeline | ObjectChip：`primitives.dart:114`。其余 `ui_components/business.dart` | `ui_components_test.dart` 控件组；ObjectChip 在更早的 primitives 测试里 | 同库组件。ObjectChip 也在旧动态目录路径上 | 已接线有测试 |
| 安全：ConfirmCard、BatchConfirmCard、WarnBanner、ScopeChip | `confirmation.dart:70`、`:286`、`:381`；`primitives.dart:180`；目录 `dynamic/catalog.dart:106-147` | `confirmation_test.dart`；`ui_components_test.dart` 只读批量卡不允许「全部允许」 | P3 的 `surface.dart:829-871` 会构造这四类。确认卡的业务执行见 4.3 | 已接线有测试 |
| 每个组件有属性模式、绑定、事件、只读 / 加载 / 错误 / 降级 | 模式在 `libraryUiCatalog`。四态在 `UiComponentState`，框在 `UiComponentFrame` | `every library component is registered with a schema`；`acts only when ready` | 同库组件 | 已接线有测试 |
| 固定样例可单独渲染 | `ui_components/samples.dart` | `component_library_goldens_test.dart` | 样例画廊不在 P2 里。组件控件从 P3 可达 | 已接线有测试 |
| golden 与对比度 | golden 文件由 `component_goldens_test.dart`、`component_library_goldens_test.dart` 比对。对比度在 `ui_components_test.dart:383` | 见测试结果一节 | 测试，不是运行时入口 | 已接线有测试 |
| 尺寸按内容自适应；Columns 宽屏并排、窄屏堆叠 | `layout.dart:159-176` | `ui_components_test.dart` 控件组含 200% 字号的 48 目标 | P3 | 已接线有测试 |
| 图表附数据表；数字只能来自绑定 | `data.dart:323-326`、`:392-418`；模式测试要求 Chart 的必填绑定是 `data` | `chart and data components take numbers only from bindings` | P3，且计划得含 Chart | 已接线有测试 |
| ScopeChip 沿用 UI-1a，并按备忘录收紧 | `primitives.dart:180`；动态目录 `dynamic/catalog.dart:106` | primitives / 组件测试。没有一条测试名写「备忘录收紧」 | P3 `surface.dart:829` | 已接线有测试 |

### 5.3 本地重算

| 要求 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| 小工具里的数字由宿主算，不由模型算 | `UiFormulaRegistry.evaluate`：`ui_formula_registry.dart:187` | `ui_formula_registry_test.dart` | 只被 `ui_recompute_adapter.dart:37` 使用，而该文件只有测试 import | 已实现仅测试可达 |
| 首批公式：求和、乘积、含税换算、加价率与毛利、按数量取阶梯价 | 求和 `:63`、乘积 `:73`、含税 `:86`、毛利额 `:105`。没有阶梯价公式。`budgetUnitPrice` 不是加价率预览 | 见 4.2。阶梯价：无 | 同上一行。阶梯价未实现 | 已实现仅测试可达 |
| 按数量取阶梯价 | 询价固定页有阶梯编辑器 `packages/inquiry_module/.../tiers_editor.dart`。UI 公式注册表没有对应项 | 无公式测试 | 固定页不是本条的小工具公式 | 未实现 |
| 公式按名称引用；参数只能是绑定或用户输入；不能是任意表达式 | `formulaId` 如 `ui.sum_decimal`、`ui.product_decimal`。槽位是 `UiFormulaSlot` | `evaluation_does_not_mutate_inputs_or_accept_new_literal_slots` | 仅测试可达 | 已实现仅测试可达 |
| 模型只选公式和参数 | 注册表不接受模型给的数字字面量当新槽。生产规划源不向模型提供公式目录 | 同上 | 仅测试可达 | 已实现仅测试可达 |

### 5.4 持久与恢复

| 要求 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| 每条回答保存最终 UIPlan、事实版本和本地界面状态 | `HostUiWorkspaceStore` 与 `UiWorkspaceController` 保存计划和草稿。工作区打开时会读：`dynamic_workspace.dart:130-150` | `ui_workspace_store_test.dart` | P4→P3。只在打开过交互页时发生，不是每条文字回答都存一份 UIPlan | 已接线有测试 |
| 重开时按当前事实重算 | 重算适配器 `ui_recompute_adapter.dart:61`。工作区恢复会标「数据版本已变化，人工覆盖仍保留」：`dynamic_workspace.dart:165-166`。那不是按当前事实重算 | `aiui_edit_recompute_acceptance_test.dart` `adapter_prepares_fixed_30_40_with_new_ref_and_extracted_2` | 重算适配器仅测试可达。恢复文案在 P5 | 已实现仅测试可达 |
| 版本变了显示「数据已更新」，点开看前后差异 | 仓库里没有「数据已更新」这句。现文案是版本变化或冲突后只读：`conversation_workspace_pane.dart:383`。没有前后差异 | 无 | 无 | 未实现 |
| 正在编辑的内容不被流式更新覆盖：稳定节点 id、焦点和滚动 | 焦点和滚动：`conversation_workspace_pane.dart:299-329`。流式编译器不在这条路上，所以「不被流式更新覆盖」没有生产实现 | `conversation_workspace_pane_test.dart` `resize_restores_measured_scroll_and_focused_field_selection` | P3 保存焦点和滚动。流式覆盖未实现 | 已接线有测试 |

焦点和滚动这一行是已接线的那一半。流式不覆盖单独算未实现，放在 5.1 的编译器行里，不重复计。

### 5.5 用户控制与无障碍

| 要求 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| 「界面与可视化」三档：自动（默认）、少用、只用文字 | 未实现。`textOnly` 只是工作区入参，默认 false：`dynamic_workspace.dart:34` | 无 | 无设置项 | 未实现 |
| 每个组件有读屏和复制用的文字等价；图表附数据表 | `UiComponentFrame` 的 `textEquivalent`；图表见 `data.dart:349-351` 和下面的逐点文字 | `ui_components_test.dart` 控件组用 `bySemanticsLabel` | P3 | 已接线有测试 |
| 减少动态效果时，流式出现改为整块出现 | 设置开关持久化：`platform_shell_personal.dart:237-243` `workspaces.setSetting('reduceMotion')`，重启后 P1 读回。没有流式渲染去改成整块 | 无 | P2 设置 → P1。流式整块未实现 | 已实现无测试 |

### 6. 不变量

| 要求 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| 界面上的数来自事实绑定或登记公式；模型裸数字只出现在文字里，并标「模型所述」 | 库组件 Prose 会加前缀：`component_adapter.dart:126-129`。数据组件模式拒绝裸数字属性。生产文字气泡 `assistant_page.dart:677` 不加「模型所述」 | `aiui5_revision2_review_test.dart` 断言「模型所述」；`chart and data components take numbers only from bindings` | Prose 要计划含 Prose，P6 不发。默认气泡不标 | 已实现仅测试可达 |
| 写入或外传只能经过确认卡或授权；按钮本身不是成功，成功以回执为准 | 动态确认卡成功态来自回执：`surface.dart:874-876`。执行映射默认是空的，见 4.3。助手工具链另有确认门，不在本行展开 | `ui_planning_events_test.dart` `three_event_routes_preserve_authority with actual host Store and receipts` | 回执渲染在 P3。从回答按钮执行工具：仅测试可达 | 已实现仅测试可达 |
| 外部内容进入任务后，回答里不出现放行类按钮 | 组件在 `externalContent` 时不画放行：`confirmation.dart:158-159`、`:369`。Folio 询问页会置位：`ask_page.dart:240`。动态确认卡 `surface.dart:871` 不传这个标志 | `confirmation_test.dart` `batch and warn banner external-content restrictions` | Folio 询问页接线。宿主动态回答不接线 | 已接线有测试 |
| 校验不过的节点不渲染；流中断不产生半截动作 | 编译器占位与 `interrupt()`，见 5.1 | `node validation isolates placeholders and blocked descendants`；`interrupted action remains disabled after complete action line` | 仅测试可达 | 已实现仅测试可达 |
| 「只用文字」档下，功能仍能用文字和固定页面完成 | 三档未做。固定页面仍可从资料打开。工作区 `textOnly` 只显示文字和原回答：`conversation_workspace_pane.dart:382-385`，没有设置去打开它 | 无三档测试 | 固定页：P2。只用文字档：无 | 未实现 |

### 8. 交付项

| 编号 | 交付项 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|---|
| AIUI-0 | 方案定稿 | 设计稿文首状态为已采纳 | 无 | 文档 | 已实现无测试 |
| AIUI-0 | 修订 ADR-0003 | `docs/adr/0003-phase2-scope.md:42` 写明 UI-2～UI-9 由 AIUI 取代，已完成的 UI-2a～4c 改称 AIUI-F1～F6 | 无 | 文档 | 已实现无测试 |
| AIUI-0 | 修订路线图文件并改任务名 | `docs/superpowers/plans/2026-10-07-roadmap-phase2-4.md` 没有 AIUI-0 或改名 | 无 | 无 | 未实现 |
| AIUI-1 | 流式协议与增量编译器（解析、逐节点校验、占位、中断），协议层加夹具 | `stream_compiler.dart:63`、`stream_protocol.dart` | `ui_stream_test.dart`、`ui_stream_v2_test.dart` | 仅测试可达。与任务书「只在协议层」一致 | 已实现仅测试可达 |
| AIUI-2 | 组件库 v1，含 golden 和对比度 | `libraryUiCatalog`、`ui_components/` | `ui_components_test.dart`、两份 golden 测试 | 渲染从 P3 可达；规划目录仍是 dynamic-1 | 已接线有测试 |
| AIUI-3 | 登记首批公式并接到 `ComputedValue` | 注册表算出字符串结果。没有生产调用把结果放进回答 | `ui_formula_registry_test.dart` | 仅测试可达 | 已实现仅测试可达 |
| AIUI-4 | 四项导航、对话主区、桌面工作区、固定页挂到资料 | 见 4.1 | `responsive_shell_test.dart`、`conversation_shell_navigation_test.dart`、`conversation_workspace_pane_test.dart` | P1→P2→P3 | 已接线有测试 |
| AIUI-5 | 模型输出界面片段；不能输出则走模板；接上 UI-4b harness | harness 在 P0：`ui_planning.dart:35`。模板退路未做。流式编译器未接。生产目录仍是 `dynamicUiCatalog` | `ui_planning_harness_test.dart` | P0→P6。编译器和模板未接 | 已接线有测试 |
| AIUI-6 | 询价比价小工具、预算小工具 | 未实现 | 无 | 无 | 未实现 |
| AIUI-6 | 导入审阅工作区 | `import_review_projection.dart` | `inquiry_import_pipeline_test.dart` | P2 任务菜单 | 已接线有测试 |
| AIUI-6 | 回答里的确认卡流程接上 REG-4 | 确认卡控件在；`businessActions` 默认空 | 路由测试自己注入映射 | 见 4.3 | 已实现仅测试可达 |
| AIUI-7 | 引用卡、阅读器工作区、结果对比 | 未实现。资料 PDF 预览不是这三项 | 无 | 无 | 未实现 |
| AIUI-9 | 按本体生成新建、编辑、关联、批量卡；询价先做 | 只有询价只读卡，提交禁用 | `aiui9_ontology_card_test.dart` | 仅测试可达。任务书写明未接 shell | 已实现仅测试可达 |
| REG-4c | 四个通用写工具，复用校验器，覆盖清单登记 | `inquiry_record_tools.dart:324`；`coverage.dart:41-64` | `inquiry_general_write_tools_test.dart` `registers four generic writes with the seven ontology types` | P7 | 已接线有测试 |
| REG-4c | 宿主模式隐藏 Folio 自带助手 | `inquiry_module` `shell.dart:63`、`:71-74`：`isHosted` 时不进入询问页 | `assistant_permission_hosted_test.dart` `hosted settings are hidden and compatibility AskPage hides bypass` | 打开询价模块页时 `isHosted` | 已接线有测试 |
| AIUI-8 | 三档可视化 | 未实现 | 无 | 无 | 未实现 |
| AIUI-8 | 助手权限页 | 只读页已接，见 4.1。权限编辑未做 | `aiui8_assistant_control_test.dart` | P2 → 设置 | 已接线有测试 |
| AIUI-8 | 数据去向 | 打开既有 `DataFlowPage`，见 4.1 | `aiui8_assistant_control_test.dart` `loading then empty records and existing ledger entry` | P2 | 已接线有测试 |

AIUI-5 这一行的状态按「harness 已接上」计。模板和流式编译器已在 5.1 单独记为未实现和仅测试可达，这里不重复计数。

### 编辑重算验收 §3：14 个未来场景

`docs/fixtures/aiui-edit-recompute/scenarios.future.json` 仍是 `future-only` / `not-run`。这 14 个测试名在 `*.dart` 里不存在。邻近代码不能代替整段场景。

| 测试名 | 实现 | 测试 | 生产调用链 | 状态 |
|---|---|---|---|---|
| edit_recompute_publish_checkpoint_restore | 适配器能准备 30/40（`aiui_edit_recompute_acceptance_test.dart` `adapter_prepares_fixed_30_40_with_new_ref_and_extracted_2`）。没有同一次发布、CAS、返回、SQLite 重开和业务写入为 0 的整段 | 无 | 适配器仅测试可达 | 未实现 |
| old_event_and_confirmation_rejected_after_publish | 未实现 | 无 | 无 | 未实现 |
| concurrent_edit_discards_captured_batch | 未实现 | 无 | 无 | 未实现 |
| late_result_does_not_replace_latest | 未实现 | 无 | 无 | 未实现 |
| invalid_formula_preserves_draft_without_old_success | 适配器有单位冲突用例 `adapter_real_unit_mismatch_keeps_legal_manual_qty_and_no_candidate`。不是本场景的整段（oops / 恢复后仍可读 / 封住 confirm） | 无 | 仅测试可达的适配器 | 未实现 |
| unavailable_and_zero_keep_distinct_states | 适配器有 `adapter_unavailable_prepares_null_candidate_without_old_success`。没有本场景要求的零值、未核验不升级和领域拒绝零保存 | 无 | 仅测试可达的适配器 | 未实现 |
| permission_change_blocks_publish_and_dispatch | 未实现 | 无 | 无 | 未实现 |
| revoked_source_blocks_current_projection | 未实现 | 无 | 无 | 未实现 |
| competing_sqlite_cas_keeps_winner_and_loser_draft | 工作区存储有 CAS 测试 `ui_workspace_store_test.dart`，不是两个真实 store 竞争且败者只读的本场景 | 无 | 无 | 未实现 |
| unknown_versions_preserve_raw_checkpoint | 未实现 | 无 | 无 | 未实现 |
| stable_row_detail_survives_sort_and_return | 未实现。`aiui5_library2_renderer_test.dart` 有稳定行导航用例，不覆盖本场景的业务 collection、返回保稿和错 scope 零导航 | 无 | 无 | 未实现 |
| read_only_form_blocks_descendant_inputs | `form_read_only_test.dart` `read-only form blocks ready child inputs and semantics actions` 盖住只读表单。本场景还要求 Stepper、Choice、Date 的真实 tap 和写调用不变，场景清单仍标 not-run | 无 | 无 | 未实现 |
| collection_null_and_fact_states_survive_roundtrip | 未实现 | 无 | 无 | 未实现 |
| approved_quantity_write_once_and_recovery_reads_receipt | `inquiry.set_item_qty` 工具有 `inquiry_write_tools_test.dart`。没有「已审 mapping → 确认一次 → 重开不重放」这条 AIUI 场景 | 无 | 工具在 P7。场景未接 | 未实现 |

## 2. 仅测试可达的公开类型

扫描范围：`apps/muyon/lib` 与 `packages/*/lib` 里和 AIUI、本体卡、快照、规划相关的公开类和顶层函数。判定：除定义文件和纯 `export` 行以外，`lib/` 没有引用，测试有引用。同一文件内部使用的辅助类型不单列。

| 位置 | 名字 | 测试 | 说明 |
|---|---|---|---|
| `assistant/ontology_cards/inquiry_ontology_card_adapter.dart:14` | `InquiryOntologyCardAdapter` | `aiui9_ontology_card_test.dart` | 有意。AIUI-9 写明未接对话和 shell |
| `assistant/ontology_cards/ontology_card.dart:8` | `OntologyCard` | 同上 | 有意。提交禁用 |
| `assistant/ontology_cards/ontology_card_snapshot.dart:24` | `OntologyCardSnapshot` | 同上 | 有意。只随适配器被测试构造 |
| `platform/ui_recompute_adapter.dart:27` | `UiLiveFormulaRecomputePort` | `aiui_edit_recompute_acceptance_test.dart` `live_port_reads_current_accepted_bundle_for_each_real_evaluation` | 有意。验收文档写明不注册生产入口 |
| `platform/ui_recompute_adapter.dart:61` | `UiFormulaRecomputeAdapter` | 同文件 `adapter_prepares_fixed_30_40_with_new_ref_and_extracted_2` | 有意。同上 |
| `platform/ui_formula_registry.dart:187` | `UiFormulaRegistry` | `ui_formula_registry_test.dart` | 有意留在协议/公式层。唯一的 `lib/` 使用方是上一行适配器，适配器本身没有生产引用，所以从 shell 追不到 |
| `muyon_module_api/.../stream_compiler.dart:63` | `UiStreamCompiler` | `ui_stream_test.dart`、`ui_stream_v2_test.dart`、`ui_collection_test.dart`、`aiui5_library2_renderer_test.dart`、`aiui5_f5a_contract_fixture_test.dart` | 有意。AIUI-1 只做协议层；`catalog.dart:167` 写明尚未接到规划器 |
| `muyon_ui/.../surface.dart:556` | `renderUiPlan` | `dynamic_surface_test.dart` | 看不出业务理由。它只是 `DynamicUiSurface` 的一行包装。生产用的是控件本身（`conversation_workspace_pane.dart:387`），不经过这个函数 |

`UiFormulaDefinition`、`UiFormulaSlot`、`UiFormulaLimits`、`UiFormulaDecimalPolicy` 和流协议上的操作类型跟注册表 / 编译器同一条边界，不另计条数。`OntologyCardField` 只被同目录快照使用。

下面这些曾经看起来像「只有测试」，实际不是：

- `AssistantControlPage` 从 `platform_shell_personal.dart:221` 进入。
- `StoredNavigationAnchor` 被 `dynamic_workspace.dart:11` import。
- `encodeUiPresentation` 在 `workspace.dart:233` 被同文件的持久化使用。
- `uiDateText`、`UiPanel` 只被同文件控件使用，那些控件在 P3 上。

## 3. 开关、模式、默认值

| 名字 | 定义 | 默认 | 持久化 | 重启后 |
|---|---|---|---|---|
| `uiPlanningEnabled` | 构造参数 `personal_agent.dart:59`，生产传入 `bootstrap.dart:328` | `false`（类默认值其实是 `true`，被 bootstrap 盖掉） | 否。`configureUiPlanning`（`personal_agent.dart:243-245`）只改内存。界面在 `assistant_page.dart:600-608`，标题是「回答后规划交互页面」，不在设置页 | 回到 `false` |
| `uiPlanningMode` | `packages/muyon_module_api/lib/src/ui/planning.dart:6` 两个值：`intelligent`、`motivation` | 生产 `motivation`（`bootstrap.dart:327`）。类默认是 `intelligent` | 否。下拉只在规划打开时出现：`assistant_page.dart:611-626` | 回到 `motivation` |
| 界面与可视化三档（自动 / 少用 / 只用文字） | 无 | 方案写自动，代码没有这项 | 无 | 无 |
| `DynamicWorkspace.textOnly` | `dynamic_workspace.dart:34` | `false` | 否，调用方传入 | 不保留 |
| `reduceMotion` | 设置开关 `platform_shell_personal.dart:237-243` | 未设置时视为关（`== true` 才开启） | 是，`workspaces.setSetting` | P1 读回，并进 `disableAnimations` |
| 本体卡提交 | `ontology_card.dart:32` `FilledButton(onPressed: null)` | 永远不可用 | 不适用 | 不适用 |
| `businessActions` | `dynamic_workspace.dart:31` | 空 map | 否 | 助手页不传入，所以一直是空 |
| Folio `assistant_permission` / bypass | `app_state.dart:451-463` | 未设置时 `confirmWrites` | 设置值会留下 | 宿主模式把已存的 `bypass` 读成 `confirmWrites`，不删除存储值 |
| Folio 询问页 | `shell.dart:63` | 宿主模式下不能进入 `Section.ask` | 由 `isHosted` 决定，不是用户开关 | 宿主里继续隐藏 |
| 外观 `ThemeMode` | `platform_shell_personal.dart:227` | 跟随应用已有主题状态 | 由外壳 `onTheme` 保存（本行不改那条存储实现） | 会保留 |
| 生产规划目录 | `ui_planning_source.dart:77` | `dynamicUiCatalog`（dynamic-1） | 写死在代码里 | 不变 |

## 4. 要让对话里直接出现本体卡片，还要补的接线

按依赖排序。每条对应还没接上的那一段，不是再做已经接上的外壳。

1. AIUI-8：先做持久的「界面与可视化」三档，并规定「自动」是否打开规划。现在一重启规划就是关的（`bootstrap.dart:328`）。
2. AIUI-5：生产规划源改用能发出库组件的目录，并接上 `UiStreamCompiler`。现在源被钉在 `dynamicUiCatalog`（`ui_planning_source.dart:77`），编译器没有生产调用。
3. AIUI-9：回答渲染调用 `InquiryOntologyCardAdapter.read`。现在只有测试 import。
4. AIUI-9：在只读快照之外做出新建、编辑、关联、批量四张卡。编辑卡的字段折叠、修订冲突、关联选择、批量 `BatchConfirmCard` 都还没有。
5. AIUI-9：卡片提交调用已经接上的 `inquiry.create_record` / `update_record` / `delete_record`（P7），经确认卡或授权，成功只认回执。现在按钮是禁用的。
6. AIUI-9：提交前和执行时各跑插件校验器，非法字段就地标红并且不发请求。
7. AIUI-6：`assistant_page.dart:742` 打开 `DynamicWorkspace` 时传入询价业务动作。否则确认卡到了路由器也会因为空映射失败。
8. AIUI-6：比价（数量、含税）和预算（加价率、毛利、阶梯价）接到公式注册表。注册表和重算适配器现在都没有生产入口，阶梯价公式也没有。
9. AIUI-8：默认打开之后，仍能回到只用文字；固定页面保持可从资料进入。三档没有之前，不要把规划默认改成开。
10. 不变量 3：动态确认卡要带上外部内容标志。`surface.dart:871` 现在不传 `externalContent`，宿主回答不会走 Folio 询问页那条隐藏放行按钮的路径。

## 5. 未能静态确认

- `Choice.allowCustom` 的实现在 `inputs.dart:213`。没有一条测试名能对上「自填值结构化回传模型」。
- `registerBusinessTools`（`business_tools.dart:46`）没有调用点。询价工具从 `InquiryModule.registerTools` 进入。ADR-0004 仍写 bootstrap 旧行号调用 `registerBusinessTools`，和当前文件不一致。
- `knowledge_preview.dart:17` 的 PDF 预览是否算 AIUI-7 的阅读器工作区。从回答卡片追不到它，本表不算作已交付。
- 14 个未来场景旁边的只读表单测试、适配器 30/40 测试，父任务是否视为场景已覆盖。场景文件自己仍标 `not-run`，本表按整段场景记未实现。
- 设置里的模型下拉和「接口与工具」有生产入口。本轮没有找到只覆盖这两个控件的测试名，所以状态是已实现无测试，不是「没有入口」。
- 流编译器拒绝公式这一条，没有标题直接写「拒绝公式」的测试。代码上编译器不调用公式注册表。

## 6. 疑似缺陷（只列位置，不评价对错）

- `bootstrap.dart:328` 与 `personal_agent.dart:59`：类默认打开规划，生产构造关掉，而且关的是内存。
- `assistant_page.dart:742` 与 `dynamic_workspace.dart:31`：打开交互页不传业务动作。
- `ui_planning_source.dart:77` 与 `catalog.dart:167`：规划目录和库渲染不是同一套组件。
- `ui_formula_registry.dart:117-125`：`inquiry.markup_unit_price` 的实现注释说它不是加价率预览。
- `surface.dart:871`：动态 `ConfirmCard` 不传 `externalContent`。
- `app_state.dart:456-458`：宿主模式把已存 `bypass` 读成确认，枚举和存储值还在。
- `ontology_card.dart:32`：提交恒为不可用。这是 AIUI-9 任务书里的边界，列在这里是免得把它看成已经能写。

## 7. 本轮测试

命令在 `apps/muyon` 与相关 package 下执行。代理保持为环境里的 `HTTP_PROXY` / `HTTPS_PROXY`（`127.0.0.1:10808`）。另设 `NO_PROXY=localhost,127.0.0.1,::1`。没有导出 `MUYON_EVAL_REAL`。原始日志在 `/tmp`，不进仓库。

未跑全量 `scripts/ci.sh`。没有导出 `MUYON_EVAL_REAL`。失败的两条没有改产品代码。

| 范围 | 结果 |
|---|---|
| `apps/muyon` 下 22 个相关测试文件。日志 `/tmp/grok8-host-test.log` | 通过 224，失败 2，跳过 0 |
| 失败 1：`ui_formula_registry_mutation_test.dart` `source mutation is killed: sum_decimal_exact_and_unit_checked` | 45 秒超时 |
| 失败 2：`inquiry_import_pipeline_test.dart` `production_context_entry_reaches_real_review_and_resumes_without_parse` | `tap` 找不到 key `select-r0` |
| `packages/muyon_module_api`：`ui_stream_test.dart`、`ui_stream_v2_test.dart`、`ui_collection_test.dart`。日志 `/tmp/grok8-module-api.log` | 通过 80，失败 0，跳过 0 |
| `packages/muyon_ui`：`ui_components_test.dart`、`confirmation_test.dart`、`component_library_goldens_test.dart`、`component_goldens_test.dart`、`aiui5_library2_renderer_test.dart`、`aiui5_f5a_contract_fixture_test.dart`。日志 `/tmp/grok8-muyon-ui.log` | 通过 344，失败 0，跳过 0 |
| `packages/inquiry_module`：`assistant_permission_hosted_test.dart`。日志 `/tmp/grok8-inquiry.log` | 通过 5，失败 0，跳过 0 |
