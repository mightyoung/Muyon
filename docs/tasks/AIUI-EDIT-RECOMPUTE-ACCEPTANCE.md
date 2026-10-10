# F5c / F3b / F4c 编辑重算验收与切分（阶段 1）

状态：**待父任务审查；仅验收设计，不启用生产**。F5a binding adapter 仍为 draft；本文件没有采纳 stream/2、library-2、typed/collection 或持久化接口的权限。另一真实 Claude 任务负责 F5 契约与组件适配，父任务确认其精确接口/文件边界后才开始阶段 2。

冻结远端 develop：`cf672164e4f6c3e7beea8029c8be735e33c3bf19`，2026-10-10 fetch；上一已核基线 `b8a9a52308112c9eb2e3a0d2a2f52c87c37b46b9` 是其祖先，新增 PR #15 Dream consistency merge。隔离工作树 `/workspace/aiui-edit-recompute-acceptance`，分支 `task/aiui-edit-recompute-acceptance`。不改 Dream/resume/LAN，不合 develop/main，不强推、删分支、部署、付费或使用新凭证。

已查 `/workspace` 与仓库：无 AGENTS.md / 仓库 SKILL.md。依据 HANDOVER-LEADER、ADR-0001～0005、REVIEW、正式 [stream/1](../design/aiui-stream-contract.md)、全文 [binding adapter draft](../design/aiui-binding-adapter-contract.md)、AIUI-3/F3a report/review、AIUI-4/review、AIUI-NEXT-BATCH-CONTRACTS。使用 writing-plans / using-git-worktrees；本阶段不执行实现计划。

## 1. 现在的实际入口与阻断

路径与行为均针对冻结 SHA，不把历史任务书中的建议签名当生产接口。

| 入口 | 已有行为 / 此片用途 | 尚未完成 |
|---|---|---|
| `apps/muyon/lib/platform/ui_formula_registry.dart` | `UiFormulaDefinition.product(...)`；`UiFormulaInvocation.forDefinition(definition, ref)`；`UiFormulaRegistry.evaluate(invocation, snapshot, completeFrozenState)`；真实调用 supplier_core `multiply` | 纯计算，无编辑监听、发布、IO；fingerprint 是 opaque 诊断，尚非正式缓存/持久化能力 |
| `packages/muyon_module_api/lib/src/ui/{snapshot,state,validation}.dart` | `ComputedValue`、`validateUiPlan`、`UiSessionState.dispatch/resolve` | `snapshot` final；编辑 string-only；computed 不随 edit 自动变；无新批次迁移接口 |
| `packages/muyon_ui/lib/src/dynamic/surface.dart` | `UiSurfaceController.eventFor/dispatch/acceptPlan`、`DynamicUiSurface`；真实事件、旧 rev/操作锁 | acceptPlan 要求 snapshot/intent/catalog identity 相同；renderer build 只接受 minimal/dynamic，library-1 整棵 fallback |
| `packages/muyon_ui/lib/src/dynamic/workspace.dart` | `UiWorkspaceController.open/flush`；持久化队列、失败 readOnly、恢复查 receipt 并锁操作 | 新 typed/集合编码、同 session 原子换批次、focus/view 迁移待 F5c |
| `apps/muyon/lib/platform/ui_workspace_store.dart` | `HostUiWorkspaceStore.save(value, expectedRevision: n)`，真实 settings SQLite CAS | 存储 CAS 不是业务写入 CAS，不能混称 |
| `apps/muyon/lib/screens/{dynamic_workspace,conversation_workspace_pane}.dart` | `DynamicWorkspaceSession`、已有单 controller route/pane、checkpoint、对象 lease | F4 旧 snapshot 刷新是卸载重开，不证明同 session 热替换 |
| `apps/muyon/lib/assistant/ui_planning_events.dart` | `UiPlanningEventRouter`、`recoverUiPlanningOperation`，宿主动作→PersonalAgent→真实工具审批/receipt | 默认 businessActions 空；没有询价场景生产映射，不能把 callback 计数叫真实业务 |
| `apps/muyon/lib/platform/inquiry_write_tools.dart` | 已登记 `inquiry.set_item_qty`：item_id/from_qty/to_qty，核对当前数量、选中范围、effect guard，领域 Store.save | AIUI 对该工具的正式 mapping/operation 构造由 AIUI-6/REG-4c owner 提供；本片不创建任意模型 tool ID |

可复用测试：`ui_formula_registry_test.dart`（真实公式、指纹、输入失败），`ui_formula_registry_mutation_test.dart`，`inquiry_write_tools_test.dart`（真实领域写与审批），`ui_workspace_store_test.dart`（两 store CAS/SQLite），`dynamic_workspace_return_test.dart`（返回重开），`packages/muyon_ui/test/{dynamic_events,workspace_controller,library_contract_boundary,form_read_only,tabs_update}_test.dart`。旧两个 host 恢复测试只读，不抢 AIUI-4 owner 的修改权。

## 2. 最小闭环：询价项目预算行数量预览

选已有 `project_item.qty` 与 `unit_cost`；报价/预算数量、单位和 CNY 来自真实 supplier Store 的项目/行。第一片只编辑数量，单价先保真实事实只读；单价编辑属于后续同结构参数，不扩大成双业务写任务。示例种子 qty=`2`、unit_cost=`10`、unit=`件`、currency=`CNY`、markup=`0`，对应领域 `Store.budget(projectId).lines` 行成本 `20`。

首片合法 typed 参数是 **decimal String**（F3a 与真实领域所要求的 unsigned 十进制文本、12 位整数/6 位小数），用当前 Field 事件也可表达；不是把 num 擅自传给 F3a。新 NumberStepper/Slider 的有限数字到领域 decimal codec 必须由 F5 owner 冻结精度与映射，不能自行 toInt/toString、浮点相乘或改 evaluator。完整新组件验收仍以采纳后的 catalog/typed 入口为准，旧 Field 成功不证明 library 可用。数量零可本地预览但不代表业务保存合法；领域保存约束仍适用。

期望链路（阶段 2 新接口尚不存在，不在阶段 1 伪造）：

1. 真实 renderer 接收最终 validated plan；用户合法编辑 `qty`，只改宿主声明 uiState/userOverrides 与 draftRevision。业务 DB、fact、formula identity、scope 不变。
2. 宿主捕获 base SnapshotRef、draftRevision、来源/object revision/digest、permission/host generation、完整冻结状态。分配新输入 ref S8，创建无旧目标 computed 的不可变输入快照；不得先把旧值改 inputVersion。
3. 使用固定实例 `budget-line-cost:item-a`、`UiFormulaDefinition.product(quantity: UiFormulaSlot.uiState('qty', unit:'件'), unitPrice: UiFormulaSlot.fact('unit_cost', object:当前项目行引用, field:'unit_cost', unit:'CNY/件'), currency:'CNY', quantityUnit:'件', decimalPolicy:supplierCoreUnsigned)` 调用真实 evaluate。limits 由宿主明确提供，沿用测试配置 32/256/16384 仅作 fixture 配置。
4. qty=`3` 必须真实得到 `30`、ready、inputVersion=S8、非空且变化的 inputFingerprint；stable computationId 保持，formulaId/version 保持。result.value 写入 ComputedValue，fingerprint/依赖身份放 owner 确认的旁路元数据，不能私自加正式字段。
5. 构造完整 S8/I8/P12（同 ref/intentRef，plan revision 递增），当前权限重建 allowedActionRefs，整树 validate。发布前再次核捕获 tuple；任何一项变化则整批丢弃。
6. 通过 **owner 提供的唯一 controller 原子发布入口** 热替换；observer 不得看到 S8+I7/P11 或旧 total 冒充当前。同 workspace/surface/controller/session 身份（以采纳接口的 session 保持政策为准），保 stable node focus/override/view/scroll；不靠 unmount/remount 过测试。此前事件、confirm/pending capability 立即不能派发，历史真实 receipt 留审计，不能重复业务。
7. 通过真实 HostUiWorkspaceStore CAS 保存一致 checkpoint。详情→返回及 storage close/reopen 后保人工 qty、版本、选中/步骤/定位与完整原回答；重新校验 source/scope/catalog，恢复只查真实 receipt，不自动模型调用/写入。
8. 业务确认 gate 单列：AIUI-6/REG-4c 提供已审 mapping 后，通过现有 router/PersonalAgent/ToolRegistry 执行 `inquiry.set_item_qty` 一次；Store 行 qty=3、Store.budget 行成本=30、持久真实 succeeded receipt。返回/重启/重复 confirm 业务变化日志与 receipt 数保持一次。不用 fixture 内直接 Store.save 充当确认成功。

重算及 checkpoint 期间业务写入次数必须 0。只有步骤 8 的工具链证明后才称“业务闭环”；步骤 1～7 成功仅称“编辑重算持久化闭环”。

## 3. 独立夹具设计与有效 RED

未来文件暂只规划，不占用其他 owner 已指定 `ui_bound_workspace_recovery_test.dart`：

- `apps/muyon/test/support/aiui_edit_recompute_fixture.dart`：从现有 supplier_core `test/fixtures.dart` 建临时项目/行/供应商/报价，真实 supplier Store 与 StorageManager/FoundationRepository/WorkspaceRepository.schema + HostUiWorkspaceStore；使用现有 task scope 种子。按当前领域读取构造 SnapshotFact（完整 ObjectRef/field/unit/source/state），不得抄公开金样的假总价。
- `apps/muyon/test/aiui_edit_recompute_acceptance_test.dart`：导入真实 F3a registry、正式 validator、DynamicUiSurface、UiWorkspaceController。可用受控 Completer 阻断调用**外层调度**以控制到达顺序；释放时仍调用真实 evaluate，禁止覆盖 evaluator 返回 `qty*price`。记录监听器观察到的完整批次 tuple 检出非原子状态。
- `apps/muyon/test/aiui_edit_recompute_restore_test.dart`：真实 SQLite 两 store、返回、关闭重开、unknown bytes 与 receipt 查询，消费现有导航 fixture/lease，不新 runtime/store/router。
- `docs/fixtures/aiui-edit-recompute/scenarios.future.json`：本阶段的未来场景清单；不是 stream/codec payload、schema 或测试 runner，不被生产导入，所有条目 future-only / not-run。

对每个新行为先在已采纳接口组合上获得断言失败（例如当前总价仍20/acceptPlan false、子输入仍能改变、旧confirm到达工具），不是 loader/缺方法/SDK错误。未来测试不得一开始跳过或写反向断言把缺口当通过。使用受控 completion、仓库 idle/flush 与现有 workspaceOperation，不依赖固定 sleep。纯计算同步无需改成假异步 evaluator。

| 测试名（拟新增） | 操作 / 核心断言 | 切片 |
|---|---|---|
| edit_recompute_publish_checkpoint_restore | 2→3；真实 evaluator=30、fingerprint变化、inputVersion=S8；listener tuple一致；同 mounted controller；CAS/返回/SQLite重开qty=3；业务0 | F3b/F5c/F4c |
| old_event_and_confirmation_rejected_after_publish | 发布前捕获 edit/confirm，发布后重放；session不变、旧operation零router/tool调用；真实历史receipt不抹除 | F5c |
| concurrent_edit_discards_captured_batch | 冻结qty=3后qty=4；第一批被丢弃；第二批真实evaluate=40；override=4，不能倒退30 | F3b/F5c |
| late_result_does_not_replace_latest | 两批受控外层completion逆序；最新发布一次，迟到结果不改snapshot/checkpoint/动作能力；dispose/host换代同样拒绝 | F3b/F5c |
| invalid_formula_preserves_draft_without_old_success | 合法typed string='oops'进入领域公式失败（不是合格业务数字）；invalid/null及原因，人工文本保留，目标槽不回填20，confirm封住；恢复后仍可读 | F3b/F5c |
| unavailable_and_zero_keep_distinct_states | price=null/notDisclosed、readFailed/conflict/notApplicable→unavailable及具体原因；unverified值不升级verified；合法0预览为0非null；zero业务保存仍按领域拒绝 | F3b/F5c |
| permission_change_blocks_publish_and_dispatch | freeze后撤销工具权限/改scope；整批丢弃、旧confirm拒绝；不扩大allowedActionRefs，不换授权generation重标旧批次 | F5c |
| revoked_source_blocks_current_projection | freeze后source撤销/digest或对象revision改变；拒绝publish/detail/confirm；保原稿、标过期，不展示旧computed为当前成功 | F5c/F4c |
| competing_sqlite_cas_keeps_winner_and_loser_draft | 两真实HostUiWorkspaceStore同revision写；仅一胜，loser保内存输入并只读；DB不覆盖，禁止pop丢错、业务0 | F5c/F4c |
| unknown_versions_preserve_raw_checkpoint | 对schema/catalog/typed/collection版本分别造未知值；保settings原字节与人工稿、只读原因；不自动改写、无迁移猜测/工具调用 | F5c/F4c |
| stable_row_detail_survives_sort_and_return | 真实业务collection同名label不同stableID；排序后点item-a仍解析同ObjectRef，返回保稿/focus；删行/错scope/旧collection rev/无ObjectRef零导航 | F5b/F4c |
| read_only_form_blocks_descendant_inputs | 在真实renderer→Form后代Field/Toggle/Stepper/Choice/Date输入与submit上实际tap/type；值/revision/写调用均不变，semantics disabled；不能只测submit按钮 | F5b/F4c |
| collection_null_and_fact_states_survive_roundtrip | null/空字符串/0/false分离；每cell完整state/missingReason/sourceRefs往返；读屏/复制文字保状态；不能用空串或0补缺失 | F5b/F5c |
| approved_quantity_write_once_and_recovery_reads_receipt | 已审mapping→真实inquiry.set_item_qty；确认一次领域row及预算真实改变；成功/失败/unknown receipt分别重开，均不重放；竞改from_qty拒绝 | AIUI-6/REG-4c + F4c |

额外 unit_price 编辑复用第一用例结构：host声明独立 decimal String 参数、真实product definition两个uiState槽；不改真实业务事实。未有正式单价写映射时保存仅checkpoint，不声称修改报价。金额舍入用 F3a 已有微量半值样例与真实 Store.budget 对照，绝不另写乘法 oracle。

## 4. 文件责任与最短执行顺序

1. **Claude/F5 owner 先交接口冻结包**：正式采纳 commit、catalog/stream/state/codec version、唯一 atomic publication 方法签名及session identity政策、依赖fingerprint旁路语义、typed decimal映射、permission/source generation检查、stable row resolver、readOnly递归策略、restore未知bytes策略。包括精确允许文件与RED入口；父任务审查后才使用。不在本文替其发明API。
2. **F3b（本执行者，获父任务放行后）**：先写独立 `aiui_edit_recompute_acceptance_test.dart` 获有效RED；只在父任务分配的新宿主adapter文件实现冻结/调用/候选批次/竞态丢弃，薄调用现有F3a，不改公式/共享runtime。准确新文件名由冻结包指定后补进计划，当前未分配，不提前创建生产文件。跑formula+新增定向与host analyze，提交独立切片。
3. **F5c（Claude owner）**：共享 snapshot/state/validator/controller/workspace/codec 的原子发布与迁移、旧操作失效；以第3节对应测试审查。F3b只提交接口问题/独立测试，不与owner同写正式核心。发布和持久化若接口耦合不能拆成两个未经一致性门禁的生产开关。
4. **F4c（本执行者，边界确认后）**：新增独立restore测试，消费F5c已冻结接口；同session route/pane/focus、真实lease详情返回、CAS与重启。两个旧恢复测试仍由AIUI-4 owner独占；必要产品修改作为单独补丁交owner顺序应用。跑新测试及现有F4回归。
5. **业务确认 gate（AIUI-6/REG-4c owner）**：给宿主动作映射和真实 receipt fixture，复用现有工具与领域校验；本执行者补第14项独立验收，不写第二审批路径。

每切片独立commit/任务分支、父任务统一交叉审查/组合CI；阶段1 PR不是上线许可。无限公式DAG、科研9项、33组件全量、模型质量、真机强杀/读屏/golden不属于此最小闭环，将已有owner的必要集成结果作为输入。

## 5. 可跑与不可跑（固定基线口径）

当前环境无 Flutter/Dart，不下载SDK；gh CLI token无法调API（403），git fetch可用，GitHub连接器read已成功。现有Actions `.github/workflows/ci.yml` 用Flutter3.47.5，在task/** push与PR上跑 scripts/ci.sh；优先该入口，不加workflow。

**现有代码可跑的回归（有SDK/Actions）**：

```bash
cd apps/muyon
flutter test test/ui_formula_registry_test.dart test/ui_formula_registry_mutation_test.dart test/inquiry_write_tools_test.dart test/ui_workspace_store_test.dart test/dynamic_workspace_return_test.dart
flutter analyze --fatal-infos
# 仓库根目录
bash scripts/ci.sh
```

UI包可跑 `flutter test test/dynamic_events_test.dart test/workspace_controller_test.dart test/library_contract_boundary_test.dart test/form_read_only_test.dart test/tabs_update_test.dart`；API包可跑 `flutter test test/ui_stream_test.dart`。当前拒绝typed/collection与library退路测试通过，只证明旧边界维持，**不证明新版Widget/业务验收**。

**当前本环境可执行**：`python3 scripts/aiui5/check_artifacts.py` 与新JSON解析/场景完整性检查、`git diff --check`。仅产物一致性，无 Widget/evaluator/runtime 验收含义。

**当前不可运行的新验收**：第3节14个future-only用例没有Dart runner，且同session原子批次、typed/collection renderer/codec及业务mapping接口未实现/未冻结。记录为 NOT IMPLEMENTED / NOT RUN（非PASS、非SKIP、非有效RED）。不能以卸载重开替代同session热替换，不能以Python检查替代Widget。

原始日志留 `/tmp` / Actions artifact 不入仓。摘要必须记完整提交SHA、run URL、实际merge tree SHA与对应源tree、pass/fail/skip/not-run分类；新未来场景仍单独14项not-run，即使当前全仓CI绿也不改成已通过。基线连接器workflow查询仅返回PR-triggered第一页且为空，不据此认定该SHA无CI或已通过。

父任务下一步仅需审查本文范围，并在Claude冻结包正式采纳后派阶段2；本分支未改stream/catalog/schema/surfacecontroller、验收账本或生产开关。


## 6. F5c 固定接口后的独立候选切片

父任务后来允许消费 PR21 固定 HEAD `97a2e8263a5f38b5659b4123b78fadea90eb35f9`。该未合入依赖的两个提交按顺序 cherry-pick；仅三个 F5c 依赖文件与固定 HEAD 完全一致，没有引入其 develop 上 Dream/resume 的无关变化。第1—5节是阶段1历史基线，不代表后来接口仍未获技术采纳；也不代表生产启用获批准。

本切片仅新增宿主 `apps/muyon/lib/platform/ui_recompute_adapter.dart` 和扩展自己的独立测试。适配器消费 `UiRecomputePort/Input/Result/Token/VersionBatch`，真实调用 F3a registry；对全部展示 computed 实例重算并保存诊断 fingerprint，重新生成 snapshot/intent/plan 并调用真实 validator。它不做 publish、CAS、调度或业务 IO，不注册生产入口。共享 schema/stream/catalog/state/controller/renderer/workspace/export 均由原 owner 管理。PR21 尚无 public export，暂用带说明的单行 implementation_imports 抑制，待 H2 替换。

当前只支持既有 minimal/dynamic 标量预览；非 view 参数集合来自可信宿主声明，未冒充新版 editSpecs/collection/library-2 验收。下一版 snapshot.initialUiState 保留提取值2，冻结 currentUiState 独立为3/4。金额固定断言30/40；另一个无数量依赖的展示实例以旧值999作为污染输入，要求实际重算到固定20。合法 typed 数量3配事实单位冲突触发真实 F3a unit_mismatch；参数不改写，候选不产生。不可用事实生成 null computed，保留事实状态和诊断，不能沿用20；未声明/view或非 String 槽位在 evaluator 前拒绝。候选不继承旧业务 actionContext，删除 business 事件和 allowed refs，真实业务映射仍关闭。

原 `edit_qty_3_publishes_fixed_total_30` / `edit_qty_4_publishes_fixed_total_40` 保留同 mounted controller 与独立常量断言。固定接口没有原子发布/rebase 实现，不能新建 controller 或手动替换 computed 来把两条 RED 变绿。候选测试通过也只证明 adapter，14个未来场景仍 not-run；并发/迟到/权限/来源/恢复/CAS/稳定行/readOnly 都待真实 owner 接口组合。

后续 guard 测试必须分别冻结 snapshot、plan 和 draft revision 的旧回调，禁止用 eventFor 动态重映射伪造旧事件。数量 `oops` 应被 decimal spec 拒绝且 accepted draft 不变，不把 raw buffer 当参数；另保留合法3的公式失败。恢复验收增加 edit→publish→save→reopen→adoptExtracted 后回到2，提取值不随候选变3。H3 详情导航在 checkpoint 和 page lease 每次 await 后复核冻结 token，最后检查和 push 连续同步执行；失效 lease 必须释放。以上尚未实现，不计为通过。


## 7. H1b apps 端注入交接（核心 owner 接线中）

父任务明确共享 state/surface/publication/ui_contract 唯一 writer 为 F5b 原任务 `01a123ce-35cd-7572-9999-7eda8935801d`，从固定 `480b0e0bd34b28a6a1e124c87d042ac0677223af` 继续。已完整读该 head 的 prepared-rebase 报告与 H1b core patch；没有应用共享 patch，也没有 merge develop。报告中的 controller `recomputePort` / `publishTokenProbe` 仍是 proposed，待 owner 提供精确接线签名和实现 SHA。

apps 新增 `UiLiveFormulaRecomputePort`，实现既有 `UiRecomputePort`，每次请求从调用方读取唯一 current accepted plan，薄调用真实 adapter，不注册 listener、scheduler 或第二 runtime。固定 adapter 仍可独立用，但不得作为整个 mounted session 的永久 base：第二次编辑必须从 S8 真实计算到 S9；旧 S7 输入在当前 base 为 S8 时明确拒绝。本独立 port 测试只推进 validated fixture 引用、验证真实连续30/40、extracted2及旧输入拒绝，不声称该引用推进是发布或 mounted 验收。

必须与 owner 对齐的一点：固定 `UiRecomputeResult` 无 plan 字段；apps `prepare()` 已产生真实验证的 `UiVersionBatch`。请 owner 确定该 batch 的宿主回调通道，或明确 controller 由哪个唯一流程生成/验证配套 plan。UI 不得丢掉 adapter 对业务事件/allowed refs 的过滤，也不得另读可变缓存拼成混版本结果。apps 不擅自扩展正式接口。

核心 patch 到位后的接线：原两条 mounted Widget 的同一 controller 注入本 live port；host probe 同步读该 controller 当前 snapshot/draft 加 host/source/permission generation 和逐字 scope，完整六字段返回。编辑触发 owner 的唯一调度/原子事务；apps 不监听 controller 再运行平行发布。保留固定30/40和无业务写断言，追加同 controller/session 与 S/I/P/inputVersion 一致；真实 `prepareRebase` 保留 extracted/override/view/selection 各层。消费新版 snapshot 时 apps 候选需保留 editSpecs/collections 等 host metadata，公式 uiState 需 UiStringEdit 且 !view；此项待实际依赖固定后修改，当前不冒充 library-2 支持。

目前 mounted 两条仍是有效 RED；当前端口测试未核 Actions 前保持 NOT RUN。完整 H1b 组合结果待核心 owner patch，不能把 detached port 测试通过算作 mounted GREEN。
