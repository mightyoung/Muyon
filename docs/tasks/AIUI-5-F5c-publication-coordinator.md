# F5c 第二片：独立发布协调器与 H1 交接

父任务明确授权本独立切片，统一审查/合入仍归父任务。分支 `task/aiui-5-f5c-publish-coordinator`，草稿 PR #30。开工 fetch develop = `b142e6591ec66a5e9f0e68fb21e064ce17d0aa9f`；在任务分支普通 merge 组合未合入 PR21 固定接口 `97a2e8263a5f38b5659b4123b78fadea90eb35f9`，其三个文件逐字保留。不得把 F5b `98af2a4e4cd488806800ec20d7a8cb2958e058bb` 的 collection RED 当整体可用。

已读正式 `aiui-f5-contract-proposed.md` §4、leader 技术采纳记录、F5c 任务书/第一片交接、REVIEW 和实际 state/surface。采用 systematic-debugging、TDD 与完成前验证技能。实际缺口：现行 session.snapshot final，accept 要求 snapshot identity 相同；controller.acceptPlan 同样拒绝不同 snapshot/intent，因此独立 bundle 发布不能关闭 PR18 同 session Widget RED。

## 本片运行边界

新增生产文件仅 `packages/muyon_module_api/lib/src/ui/publication.dart`；新增独立纯运行时测试 `packages/muyon_module_api/test/ui_publication_coordinator_test.dart`。其余新增为本说明和 H1 patch artifact。未改 F5b state/surface/barrel、F3b adapter/PR18 测试、workspace/store/planning/nav。协调器不是第二套 event executor 或公式引擎，只有发布 admission、一次 validated bundle 引用切换和异步准备的生命周期；不执行 dispatch/sink/tool/模型/IO。

`UiPublicationCoordinator(ValidatedUiPlan initial)` 的 API：

- `current`：已接受的 `ValidatedUiPlan`，其 plan/snapshot/intent/catalog 同属一个 bundle。同步 `publish(UiVersionBatch, UiPublishTokenProbe)` 调现有 `validateUiPlan`，最后复核完整 token 后只作一次 bundle 指针替换，中间无 await、listener 或外部 commit callback。
- `publishedDraftRevision`：已发布 draft 的单调下界，取旧下界、冻结 token 的当前 draftRevision、候选 actionContext.draftRevision 三者最大值；**不是** live session draft 的替代 getter。真实编辑后的版本从 host probe 读取，实际 session rebase 必须另行保持 `max(old, candidate)`。
- `recomputing` / `outdated` / `publicationErrors`（不可修改）：准备生命周期与只读降级原因。invalid 只改诊断/降级，不改变 S/I/P；直接 staleToken 不改变 bundle 或诊断。
- `recompute(Future<UiVersionBatch> Function() prepare, UiPublishTokenProbe probe)`：先封 business admission，再调用准备闭包。闭包由宿主负责 F3b 的真实 evaluate / batch 构造；本协调器没有结果缓存、DAG、自动重试或内置超时。最新请求有效；取消/新请求/直接成功发布/dispose 都隔离晚到 Future。同步或异步准备异常转 `invalid` + `recompute_failed`，不暴露原始异常文本。
- `cancelRecompute()`：仅取消正在准备的 ticket，不宣称取消实际 IO/tool，也不接触 pending/receipt。晚到结果返回 staleToken；`dispose()` 后返回 disposed 且不再启动 prepare。
- `allowsDispatch(UiActionDefinition action, {required bool readOnly, required bool pending})`：**admission 决策，不分派事件**。readOnly/disposed/outdated 非重算期拒绝所有动作；recomputing 拒 business，仍允许合法参数编辑由既有 validator/session 检查；同节点 pending 拒 business 和 local cancelConfirmation。pending 必须由 owner 的真实 `_pending` 表提供，不能只看按钮状态。

publish 检查完整 token（含 base ref 与 draft 单调下界）、surface/catalog/intent 身份、plan revision 严格递增、同 snapshot id 且 snapshot revision 前进、batch 三引用一致、allowedActionRefs 不扩张，再运行唯一现有 validator。最终同步 probe 的撤权、重新入场、取消/换代/dispose 都不能越过 commit。候选值是否真实计算、nullable computed evidence 与 formula String/!view 条件仍归 F3b/F5b；单纯检查 inputVersion 不能证明 evaluate。

## H1a：只交 owner，不在本分支应用

文件 [AIUI-5-F5c-H1-admission.patch](AIUI-5-F5c-H1-admission.patch) 是对 F5b 固定 `98af2a4e4cd488806800ec20d7a8cb2958e058bb` 两个共享文件的最小 admission 桥接 diff：controller 同时在 dispatch 内和 canConfirm 检查门控；session 记住 host admission 回调，使直接 session.dispatch 也进入同一道门；dispose 关闭协调器。仅在 `/tmp` 提取的固定原文件上执行 `git apply --check`，没有修改共享工作树；这是机械可应用证据，**不是该 patch 编译/运行通过**。

owner 还需向 `ui_contract.dart` 加一行 export（H2b，独立于已接入的 recomputation H2）：

```dart
export 'src/ui/publication.dart';
```

H1a **不得单独生产启用**；本片不提供危险的 `coordinator.publish(); session.accept(...)` 接法，后者既不接受新 snapshot，也可能半更新。完整 H1b 仍需共享 owner：

1. 同一个 session 提前构造、验证全部 rebase 状态（extracted / override / view / selections 三层、source digest、draft max、不可读人工值与原因）。准备失败时不得动任一旧层。
2. 同步发布在最终 token/probe 与事务点之间无 await；发布 bundle 与上述准备后的 session 状态必须在无 callback/无可抛步骤的事务中一起安装。现独立协调器仅能原子切换自己的 bundle，不能作为已完成的跨对象事务回报；需要 owner 统一 commit 协议或单个 prepared 状态引用，完成后增加真实同 session/mounted 测试。
3. controller/session/mounted 保原实例；统一 `current`，不能让 controller._current 与 coordinator.current 两个版本源分叉；旧 render callback 捕获旧 plan revision/身份。legacy acceptPlan/applyPatch 同步纳入统一版本源。
4. 保 pending、operation locks 与 receipt 结算，不重放；新 operation key 由宿主分配。成功准备后和用户继续编辑后的 latest-wins 都要使用完整 live token。
5. F3b 薄 adapter 真正接到合法编辑与上述发布路径，PR18 qty3/4 必须在原 mounted controller 更新 computed；未完成前那两条 RED 保留，不能改用新 controller 或弱化断言。

## 验证与未测

本环境无 Dart/Flutter，未下载 SDK，使用既有 Actions `scripts/ci.sh`。最小可编译行为 RED 提交 `4a6478dda112b00278f02e333953770526d735d5`：同步 publish 应安装 validated S/I/P，scaffold 返回 invalid。必须读到该行为断言失败，编译失败不计 RED。终态/完整 GREEN SHA/远端读回写 PR body，原始日志不入仓库。

纯运行时测试实际调用本生产协调器和唯一 validator，用 Completer 驱动顺序，不 sleep。预先构造的 computed fixture 只是发布输入，不声称是真实重算。测试可证明协调器 bundle 原子性、token/epoch fence、生命周期与 admission 决策；**不能**证明实际 UI dispatch 零 sink、同 session rebase、mounted 焦点、pending/receipt 跨发布、完整 library-2/collection renderer、恢复/CAS/nav/模型/真机/macOS golden。H1 patch / H2b / PR18 与 F5b 组合 CI 均未运行。
