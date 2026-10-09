# AIUI-5 规划、绑定适配与共享运行链路接入（草案）

状态：**任务书草案，待唯一合入任务审查**。用户已授权并行推进开发，可先进行不变更正式契约的诊断、映射与fixture片；typed/collection正式方案采纳前不能启用相应新能力。本文件不表示正式契约已修改、代码已实现或验收已通过。

分支建议：`task/aiui-5-planning-integration`。依据：[AI 原生界面方案](../design/ai-native-ui-redesign-2026-10-09.md) §5.1～5.4、§6；[流式契约](../design/aiui-stream-contract.md)；[UI-4b](UI-4b.md)、[UI-3b](UI-3b.md)。目标是让模型生成的组件片段通过同一条宿主链路成为可验证、可操作、可保存恢复的界面。

## 1. 基线与范围

任务说明草案基于 develop `01404ae472451f55af5baa6ce76c95af72b0cbfc`。既有审计冻结 AIUI-1 `276b29146d3eb902380cceac708209cc6ef344c0`、AIUI-2 `3f739035385b7640d1fcec497dc33a85d3553ffe`；AIUI-2 后续远端 `4e45836efcb85c86f5c8de57e6b07795aab6166a` 修复 Tabs，应另作复核，不能覆盖旧审计结果。开工时重新获取 develop 和实际依赖完整 SHA，记录合入状态与对应 CI。未合分支不得称为主线能力。

复用现有 `UiPlanningPort`、`UiPlanningHarness`、Motivation/Fixture Provider、`PersonalAgent`/ModelGateway/HostModelAuthorization、`UiStreamCompiler`、`validateUiPlan`、`UiSessionState`、`UiSurfaceController`/`DynamicUiSurface`、`UiWorkspaceController`/Store、`UiPlanningEventRouter`。扩展这些边界或增加其薄适配器；不建第二个 runtime、validator、模型网关、事件路由或存储内核。保持 UI-4b 自动/显式去重、完整问答、状态复核及授权门禁。

交付只覆盖展示规划与本地交互适配。业务确认和授权不改；新组件注册不是业务写入授权。AIUI-6 宿主业务接入、REG-4c 实际领域工具 mapping 未就绪时，只读或明确 disabled，不造假的成功回执、临时 grant 或猜测工具名。依赖矩阵由本批索引统一维护。

## 2. 契约变更建议：先审查，后实施

现行 validator 对事实/计算/状态仅接受 scalar；local editField 还要求事件和输入状态是 String。Toggle 注册 boolean change，却不能通过该规则；CompareTable 的 rows 模式与 detail 要求 value 也不兼容。禁止为过测试全局放宽 `isUiScalar`、删拒绝断言或把非法输入转为“合法默认值”。

先交单独可审查的契约增补建议，列出旧行为、拟新增类型、版本策略、生产/消费方、拒绝规则和迁移用例；正式采纳前，新能力不得成为默认生产 schema。该关口是对实现的门禁，不要求仅撰写本草案就确认变更。

- **Typed edit**：组件允许的 payload 与目标 state 类型必须一致。建议保留 string 编辑，并显式支持 boolean、有限 number、规范日期值、稳定 item ID 集合；日期优先采用有格式约束的 ISO date String 加显式 adapter，必须说明日期/时区/空值规则；集合 wire/persistence 使用确定顺序且去重的 ID 列表，不直接存 Dart Set。number 是否扩展现有 `UiValueType`、integer/浮点/范围与 step 的处理必须明确，不能让 Slider 的正常小数静默截断。
- **宿主 collection codec**：单列结构化集合契约，不把任意 List/Map 视为合法 fact。至少定义 collection ID、带宿主 identity 的稳定 row/item ID、字段/列 schema、数据版本、绑定来源与 ObjectRef、可编辑状态投影；Chart 数值来源必须是事实/宿主计算。配置行数、列数、项数、嵌套深度、字符串/总字节限额；常量与边界测试共用。拒绝重复/空 ID、类型错误、非有限数、未知字段或引用、版本不匹配、超额和畸形内容；不丢坏项后声称整份合法；保存超限时错误必须可读，保留旧checkpoint与当前可读草稿，不清空状态。
- **Row detail**：CompareTable 每行需要宿主可信 `rowObjectRef`，明确点击行 payload 的 ID/schema，以及该 ID 如何解析到当前快照 ObjectRef。不得把标题或模型自报 ObjectRef 当成宿主引用。未实施的 tap 可按正式后续任务移除并同步文档；重新提供 tap 时，目录、校验、Widget、路由、恢复均须有一致消费方。
- **版本**：说明上述变更属于目录/纯UI契约的哪个版本；如果改变 `aiui-stream/1` 的行格式或既定禁止项，必须另提协议版本。元信息、action route、draft revision 仍由宿主提供；模型只引用宿主已声明数据与状态。

建议承载文件：新增 `docs/design/aiui-binding-adapter-contract.md`（契约建议）；视采纳方案新增 `packages/muyon_module_api/lib/src/ui/collection.dart`、`edit_contract.dart` 和相应纯契约测试，经现有 `ui_contract.dart` 导出。这些是拟新增文件，不能当作已有实现；已有 `plan.dart`、`snapshot.dart`、`validation.dart`、`state.dart`、`workspace.dart` 的修改范围以采纳方案为准。

### 2.1 共享文件归属与本地重算接线

AIUI-5 独占跨任务共享接线：`muyon_module_api/lib/src/ui/plan.dart`、`validation.dart`、`state.dart`、`workspace.dart`；`muyon_ui/lib/src/dynamic/surface.dart`、`workspace.dart`；`apps/muyon/lib/assistant/ui_planning.dart`。AIUI-3 只新增纯公式 registry/evaluator、业务薄适配与测试，禁止双方同时改共享controller。AIUI-5负责唯一controller的 recompute、不可变snapshot生成、plan重新验证与状态兼容钩子，调用AIUI-3纯接口。

现有 `UiSessionState.snapshot` 为 final，接受计划要求 same snapshot identity；computed resolve 只读取原快照的结果，编辑UI state并不会自动重新计算。任务必须显式扩展这一条共享链路：合法typed edit→冻结输入/来源版本→宿主公式评估→新不可变snapshot与新计算结果→依据当前语义构造匹配新snapshotRef的新intent/plan并与catalog重新validate→原controller协调兼容状态后原子发布。计算失败、版本竞争或计划失效保留旧可读界面/人工覆盖并给出降级原因；不得原地改fact、伪造计算值或另建session替身。新snapshot保留稳定节点/集合项identity，重新核对actionContext/draft修订，旧待确认动作不能继续用过期计算版本。

宿主 `computationId` 是当前计算实例/结果绑定的标识，registry `formulaId` 是登记公式定义的标识；请求、结果、重算和恢复必须区分两者，不能把模型给的公式名当成已有可信结果。公式结果仍由宿主计算，并由AIUI-3声明来源/inputVersion与错误；typed编辑、finite-number和collection方案依采纳关口实施，不在草案锁定新版schema字符串。

测试文件边界：既有 `apps/muyon/test/dynamic_workspace_return_test.dart` 和 `apps/muyon/test/ui_workspace_store_test.dart` 的唯一修改owner为AIUI-4；本任务只读复跑，新目录/typed/集合恢复断言放独占拟新增 `apps/muyon/test/ui_bound_workspace_recovery_test.dart`，确需补旧文件则交AIUI-4顺序应用。

追加拟新增 `packages/muyon_ui/test/ui_recompute_integration_test.dart`：`typed_edit_recomputes_through_registered_formula_and_revalidates_plan` 断言实际唯一controller编辑后产生新不可变snapshot、结果inputVersion正确、绑定显示更新；`stale_formula_result_and_failed_revalidation_preserve_readable_overrides` 断言晚到结果/失败不覆盖人工编辑、不能启用旧业务确认；`formula_definition_id_is_not_computation_instance_id` 断言不混用两个ID。该专项用公开host输入与纯AIUI-3 evaluator，无模型调用。

拟新增纯接口 `packages/muyon_module_api/lib/src/ui/recomputation.dart`（同样须采纳，不是假定已实现）：`UiRecomputePort.rebuild(UiRecomputeInput input) -> Future<UiRecomputeResult>`。输入固定为`previousSnapshot:DataSnapshot`、`currentUiState:Map<String,Object?>`、`observedDraftRevision:int`；输出为`baseSnapshotRef:SnapshotRef`、`observedDraftRevision:int`、`nextSnapshot:DataSnapshot?`及`errors:List<String>`。接口不接受formula表达式、工具名、路由或新权限。host adapter调用AIUI-3 `UiFormulaRegistry.evaluate`、由宿主revision allocator构造nextSnapshot，纯UI包不依赖apps/supplier/research。现有`UiSurfaceController.dispatch(UiEvent) -> Future<UiDispatchOutcome>`签名保持；可选注入recompute port，在同一dispatch后处理输入变化，发布前比较输入快照/草稿修订、重验证intent/catalog/整树并撤销过期能力。旧provider和无port模式保持原行为；需要跨snapshot更换session时在同controller里显式迁移经过校验的覆盖/视图值，而不是修改final字段或复制一个竞争runtime。

### 2.2 F5a同版本构造责任与最小例子

F5a契约提案必须把以下宿主职责写成一个原子发布批次；正式采纳后由AIUI-5的host adapter实现，AIUI-3只提供纯evaluate，模型不能分配版本或构造intent。宿主先冻结事实来源版本、当前允许state和observedDraftRevision，分配nextSnapshot.ref，**用该新版本的真实输入快照重新计算**；`ComputedValue.inputVersion`必须等于最终nextSnapshot.ref。宿主再从当前scope/permissions和必显要求构造匹配 `snapshotRef` 的新InteractionIntent，并重建匹配snapshotRef/intentRef且surface revision递增的新UIPlan，整树validate后才迁移兼容现场、原子替换能力。actionContext/operation必须由宿主重新核对；新intent不扩大allowedActionRefs，不复用过期授权。发布前若baseSnapshotRef、draftRevision或权限已改变，该整批结果作stale丢弃。

最小只读例子（fixture中的数值来自宿主）：旧S7=`SnapshotRef('quote-view',7)`，facts.price='10'、state.qty='2'，computed.total='20'/inputVersion=S7；I7.snapshotRef=S7，P11.snapshotRef=S7、intentRef=I7.id、revision=11。用户合法把qty改成'3'后，宿主建立输入S8=`SnapshotRef('quote-view',8)`（保持price真实来源版本、带当前qty='3'），调用AIUI-3重新求积得到'30'；最终S8.computations.total='30'/inputVersion=S8。随后构造I8.snapshotRef=S8、P12.snapshotRef=S8/intentRef=I8.id/revision=12，用(S8,I8,原目录) validate P12。只把旧'20'的inputVersion改成S8，或S8搭配I7/P11，均不算重算，不能发布为当前成功界面。

在 `ui_recompute_integration_test.dart` 增加 `next_snapshot_computation_intent_and_plan_are_one_versioned_projection`：实际编辑2→3后断言30、新snapshot/inputVersion/intent.snapshotRef/plan.snapshotRef完全一致、plan.intentRef匹配新intent、surface revision递增且原source版本不伪造；`relabelled_old_result_or_mixed_version_intent_is_not_published`：携旧qty=2输入fingerprint的缓存20仅重标inputVersion=S8，以及混配I7，分别拒绝、无新动作能力，原人工草稿仍保留。公式失败后的当前发布策略严格按AIUI-3状态表，不保留旧成功计算值冒充当前值。

collection建议初版常量（待采纳，非现行正式schema）：200行/项、32列、深度4、单字符串4KiB、单集合64KiB UTF-8；编码后的大小也受限。复用边界常量作N-1/N/N+1测试，slot与scope失效整组拒绝。总surface规模仍同时遵守stream/1及plan已有上限，较严格者优先；不能因允许host集合扩大模型行上限。

建议按可审查切片推进：契约建议/拒绝用例→typed/collection与codec→共享映射与重算钩子→planning/stream final能力→保存恢复。每片保持旧目录回归；切片顺序是建议，不表示未经采纳的schema决定已经生效。

## 3. 33 组件生产消费映射

以实际最终 catalog 枚举为准，检查下列33个组件，产出机器可复算 manifest；每项包含 catalogVersion、schema 属性及必填项、children、bindings 的数据形状/来源、事件 payload、动作/路由、Widget 参数映射、文字等价、状态、fixture、测试与恢复处理。不能只统计名字或用直接 Widget 样例代替 UIPlan 消费测试。

| 组件组 | 必须实现/核对的映射 |
|---|---|
| PageScaffold、MasterDetail、Heading、Prose、Section、Columns、Tabs、Disclosure | props/children 与真实 Widget 对齐；Tabs labels 与 children 一一对应、稳定 ID、空组/畸形拒绝；Disclosure 子节点数量及展开状态持久化明确；Heading 层级约束不能只接受任意整数。 |
| Field、Choice、NumberStepper、Slider、Toggle、DateField、Form | typed value/options/selected、单/多选和自填语义、日期与数值边界；事件只更新声明的 UI state；Form readOnly 对后代真实输入有效，不能仅禁 submit；提交仍经过既有 business 路由。 |
| Table、KeyValue、Metric、CompareTable、Chart | 标题/列名/行/项/单位/差值来源；集合映射、Chart bar/line/pie 与数据表、CompareTable 标记与可信行详情；排序仅改 view，不增加业务 draft revision，不影响真实事实。 |
| SourceList、SourceCard、ObjectChip、FileCard、StatusBadge、ScopeChip、WarnBanner | 来源 digest/version、事实 state、ObjectRef 与文件引用；未知或已撤销引用安全降级；打开详情/来源只用宿主受支持能力，不让模型路径变成文件权限。 |
| ConfirmCard、BatchConfirmCard、ProgressCard、Checklist、Timeline | confirm/cancel、进度/步骤、稳定 checklist item ID 与 checked 投影、timeline event ID/version；保留 mandatory state、授权/receipt关联和未知操作锁定。 |

扩展已有 `packages/muyon_ui/lib/src/dynamic/catalog.dart` 与 `dynamic/surface.dart`，消费已有 `ui_components/{layout,data,inputs,business,state}.dart`；可新增 `dynamic/component_adapter.dart` 作为这一个 renderer 的适配表。若正式后续已改变33组件清单，manifest对完整SHA据实更新并列差异。复制/读屏的文字等价与 state/fallback 同用解析后的可信绑定值。

## 4. 规划、提示、流式与最终能力

在已有 `UiPlanningPort` 完整结果接口上保持兼容，提出可选流进度适配方案，避免为 streaming 另造一个规划体系。已实现 `stream_protocol.dart`、`stream_compiler.dart` 是依赖文件；新增薄适配 `apps/muyon/lib/assistant/ui_planning_stream.dart` 可将当前 Provider 产出交给宿主建立的 session/compiler。具体 API 须在实施前说明如何与既有 Future/result、取消、去重和超时协作。

提示序列化继续从 actual request.catalog、allowedActionRefs、DataSnapshot/Intent、question+answer+conversation/currentView 生成；不要硬编码第二份目录。补模型可读的节点/binding/action 数据形状、typed payload、collection引用和合法完整样例，明确 textOnly/supplement/replacePresentation 与流终止关系。样例固定 catalog/protocol version 和 public fixture snapshot，实际编译到 end 并验证；不可沿用未经目录验证的示意 CompareTable 行。

预览仅展示 compiler 接受的安全节点及占位状态；不能将候选 UIPlan 包装成 `ValidatedUiPlan`。预览所有动作不可用。只有 `UiStreamView.finalPlan` 非空且当前宿主 snapshot/intent/catalog/权限/表面版本重新核对通过，才能替换当前 surface 并启用动作。bad line、无end、中断、超时、限额、unknown component/action、最终required_binding/mandatory_state失败均保存完整文字，走可信模板 fallback；禁止“删错误节点后通过”。重规划使用既有修订号和稳定节点 ID，不覆盖人工编辑。

两模式共用上述 pipeline。本地 provider 未就绪时明确 provider_unavailable，不暗切在线；模型不支持流式界面时使用既有完整计划或宿主模板退路并如实标记。真实在线调用必须继续走原 gateway、预算/授权/外发审查，去重不产生双模型调用。此任务默认只用公开 fixture/loopback；不安装/下载模型、不触发付费调用。真实模型延迟、成本与效果后续在已有授权下单列，fixture零成本不当真实成绩。

## 5. 保存恢复与旧版迁移

沿现有 `encodeUiPresentation`/`decodeUiPresentation`、`StoredUiWorkspace`、`UiWorkspaceController`、`HostUiWorkspaceStore` 和同口浏览器fixture存储扩展。保留 CAS、task/surface/scope、人工覆盖与提取分层、stable IDs、状态/事实版本、patch history、滚动焦点、确认operation refs；不能新增平行数据库或持久批准/秘密。

若采纳集合/typed状态，codec必须有纯JSON确定格式与限额，并往返保持类型/ID/版本。只有最终validated presentation可保存成可继续界面；预览/中断不保存为已完成可操作计划。恢复按当前 snapshot/intent/catalog重新验证，不重放 business/semantic/model调用。旧minimal-1/dynamic-1项目仍可读；library升版未知字段、形状变化、删除节点/绑定变化时保留旧值、只读/提示，不静默丢用户覆盖。迁移建议须有原始bytes保留、幂等、失败/权限变化处理；不猜历史授权。

## 6. 可执行验收：先失败复现，再实现

以下文件名是已有文件或明确标注拟新增；测试名为本任务需新增/补强的名称，不宣称现存。每项必须断言实际共享入口/输出，而不是复刻实现或仅断言fake次数。

| 文件 | 测试名与最少行为断言 |
|---|---|
| 拟新增 `packages/muyon_module_api/test/ui_edit_contract_test.dart` | `typed_edit_accepts_declared_bool_number_date_and_item_ids`：用采纳目录构建plan→实际validate→UiSessionState.dispatch→读取typed状态，draftRevision只在编辑时递增；`typed_edit_rejects_payload_type_range_and_undeclared_state`：wrong型、NaN/Infinity、无效日期、重复/未知ID与未声明状态均拒绝、原值/修订号不变；旧string编辑仍通过。 |
| 拟新增 `packages/muyon_module_api/test/ui_collection_contract_test.dart` | `collection_codec_preserves_stable_ids_sources_and_versions`：host集合编码/解码等价、乱序不改变ID引用；`collection_codec_rejects_malformed_duplicate_stale_and_over_limit`：各拒绝路径分别断言具体错误与全体拒绝；限额-1/限额/限额+1测试；列表不能通过旧scalar路径。 |
| 拟新增 `packages/muyon_ui/test/component_plan_mapping_test.dart` | `every_catalog_component_renders_from_validated_bound_plan`：枚举实际catalog全部组件，用完整UIPlan/可信snapshot校验并进入同一个DynamicUiSurface，逐项断言真实绑定值/props/children/语义和4态，manifest覆盖等于catalog集合；`tabs_and_disclosure_children_preserve_ids_and_restore_selection`；`form_readonly_blocks_descendant_changes_and_submit`：真实Toggle/Choice/Field及submit输入均不改变状态或调用port。 |
| 上述mapping测试＋已有 `apps/muyon/test/ui_planning_events_test.dart` | `compare_row_detail_resolves_current_host_object_ref`：点击指定row ID打开该宿主ObjectRef，不是整表node；`compare_row_detail_rejects_unknown_stale_and_forged_row`：未知/过期/伪造ID零路由；`collection_sort_does_not_change_facts_or_business_draft`。未有真实业务映射时详情只读且不调用write tool。 |
| 拟新增 `apps/muyon/test/ui_planning_stream_test.dart` | `stream_preview_has_zero_action_capability_until_valid_end`：最后end前点击任何local/business/semantic均零状态变化/零sink；有效end及当前状态复核后才通过共享surface；`bad_line_incomplete_limit_and_unknown_contract_use_trusted_fallback`：逐种错误无final capability、原答案完整、required/mandatory可信绑定保留；`stale_host_state_at_end_rejects_final_capability`。 |
| 已有 `apps/muyon/test/ui_planning_harness_test.dart` | `planning_prompt_examples_compile_against_actual_catalog`：抓取loopback prompt并实际编译随附公共样例，与请求目录完整匹配；`auto_and_explicit_stream_share_one_provider_and_budget`：同时自动/显式仅一个实际fixture/loopback发送、完整问答/目录仍在请求；`missing_local_provider_never_sends_online`；`both_modes_use_same_bound_plan_renderer_and_router`；既有planner failure/current authority变化用例继续通过。 |
| 已有 `packages/muyon_module_api/test/ui_workspace_test.dart`、`packages/muyon_ui/test/workspace_controller_test.dart` | `typed_collection_state_roundtrips_without_losing_user_overrides`：编辑→patch→save/load→当前validate→restore后类型、IDs、manual覆盖与draft修订保持；`old_catalog_upgrade_preserves_readable_draft_and_disables_incompatible_events`：旧版本/未知新版/绑定变化不丢字节；`incomplete_preview_is_not_restored_as_actionable_final_plan`。 |
| 拟新增 `apps/muyon/test/ui_bound_workspace_recovery_test.dart`（AIUI-5独占） | `native_bound_plan_reopen_preserves_ids_and_rechecks_scope_receipts`：真实临时SQLite重开/CAS冲突/保存失败保旧值，scope变化不恢复权限；unknown operation恢复零invoke、零model；返回/重开保持编辑位置。 |
| 已有 `apps/muyon_ui_preview/test/planning_preview_test.dart`、`workspace_restore_test.dart`；已有 `scripts/ui_preview/workspace_smoke.mjs` | `public_stream_plan_and_restore_use_same_contract`：公开fixture调用与生产同一适配入口；实际浏览器刷新/返回若可用另记证据，fixture recreation/widget不替代浏览器或原生SQLite；浏览器保存失败显示可读错误且不重放事件。 |
| 已有 `packages/muyon_ui/test/component_library_goldens_test.dart`、`ui_components_test.dart` | 新增bound-plan映射回归与旧直接Widget金样并列；200%字体、48点击区、语义标签仍成立。不能仅更新PNG使失败消失；不同平台漂移按既有规则记录。 |

批准契约后至少做4个有效变异：跳过typed payload检查、丢stable item ID、预览启用action、恢复跳过current catalog验证；分别由以上指定行为测试检出，记录实际失败断言。禁止削弱既有validator/stream拒绝测试。

## 7. 命令与交付证据

各命令从注明包目录执行；新文件在实现后才存在。不得导出 `MUYON_EVAL_REAL`，清除无关真实模型评测开关；使用公开临时数据。Flutter不存在时明确未运行，核查已有精确SHA CI并报告，不能把静态核对冒充测试。

```sh
# packages/muyon_module_api
flutter analyze --fatal-infos
flutter test test/ui_edit_contract_test.dart test/ui_collection_contract_test.dart test/ui_workspace_test.dart test/ui_contract_test.dart
flutter test

# packages/muyon_ui
flutter analyze --fatal-infos
flutter test test/component_plan_mapping_test.dart test/ui_recompute_integration_test.dart test/workspace_controller_test.dart test/dynamic_events_test.dart test/dynamic_patch_test.dart
flutter test

# apps/muyon
flutter analyze --fatal-infos
flutter test test/ui_planning_stream_test.dart test/ui_planning_harness_test.dart test/ui_planning_events_test.dart test/ui_bound_workspace_recovery_test.dart
# AIUI-4拥有下列两个既有文件，AIUI-5仅只读复跑，新增断言交owner补丁：
flutter test test/ui_workspace_store_test.dart test/dynamic_workspace_return_test.dart
flutter test

# apps/muyon_ui_preview
flutter analyze --fatal-infos
flutter test test/planning_preview_test.dart test/workspace_restore_test.dart
flutter test
flutter build web --release
```

同时从 `packages/muyon_module_api` 运行 `flutter test test/ui_stream_test.dart`（该文件来源于实际AIUI-1依赖；开工如路径变更须先核对并记录）；真实云端SQLite与无模型loopback证据单列。真实浏览器仅在已有可用云/回环环境下运行已有smoke脚本，缺环境登记未运行；原生进程终止/锁屏、真实模型质量与业务写入仍按对应任务补验，不因此无限阻断能够判定的代码切片。

交付：完整依赖/审查/代码SHA与准确CI；契约建议与采纳记录；33组件或正式更新后完整清单的机器manifest；每个生产消费层路径/行号；有效RED与修复后的专项/全量通过、失败、skip、未运行计数；4变异摘要；公共生成样例及实际编译测试；旧目录升级/恢复证据；仍需AIUI-6/REG-4c的实际tool mapping清单。原始日志、模型业务数据及构建大产物不进仓库；测试摘要与可复算脚本可进任务交付。

审查通过后由唯一合入任务处理，执行者不合develop/main。纯协议、组件库通过不等于全链路通过；按实际边界声明可接入能力和仍disabled能力。

## 分片执行检查表

- [ ] 先交typed/collection/row身份提案和失败最小fixture；明确采纳记录，未决定时保持原validator及只读退路。
- [ ] 实现纯契约类型/codec负例与33组件bound-plan映射专项RED，再在原validator/state/renderer做最小增量。
- [ ] 接AIUI-3纯evaluate与上述recompute port，在唯一controller测试原子快照更新、晚到结果/旧operation失效及覆盖保留。
- [ ] 在原harness/provider/gateway接stream final能力、两模式去重和可信fallback，实际编译prompt金样并跑三路事件负例。
- [ ] 完成旧/新catalog codec、真实SQLite CAS重开及返回恢复，运行规定4变异和全量门禁，交完整组合SHA及能力未接入清单。
