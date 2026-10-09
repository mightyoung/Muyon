# AIUI-3/4/5 下一批任务与契约依赖矩阵（草案）

日期：2026-10-09 · 状态：**待唯一集成负责人审查的任务书草案**，不是正式契约修订、已派发状态或产品验收结论。
文档分支：`docs/aiui-next-batch-contracts`。本分支只新增本矩阵和 [AIUI-3](AIUI-3.md)、[AIUI-4](AIUI-4.md)、[AIUI-5](AIUI-5.md)，不修改产品实现、ADR、正式 schema、已有任务索引或验收账本。用户已授权并行开发，执行分支和正式集成由唯一合入任务统一，不能在此文档分支编码或自行合入 develop。

## 0. 去重与冻结来源

拟稿前 fetch 并检查远端全部106个唯一分支 head 的 `docs/tasks/AIUI-{3,4,5}.md`，均不存在；develop 索引仅有待派占位，因此补齐三份任务书而非另造编号。复算：

```sh
git fetch origin '+refs/heads/*:refs/remotes/origin/*'
git for-each-ref --format='%(refname) %(objectname)' refs/remotes/origin
# 对上述每个唯一完整 SHA：
git ls-tree -r --name-only <SHA> docs/tasks/AIUI-3.md docs/tasks/AIUI-4.md docs/tasks/AIUI-5.md
```

| 来源 | 完整 SHA | 用途/边界 |
|---|---|---|
| 本文档分支基线 develop | `01404ae472451f55af5baa6ce76c95af72b0cbfc` | 已读 HANDOVER-LEADER A～D、REVIEW、ADR-0001现行决定、产品总览及设计；根无AGENTS.md、无仓库`.agents/skills` |
| 原审计 AIUI-1 | `276b29146d3eb902380cceac708209cc6ef344c0` | 正式stream/共享validator来源，原审计未发现新增协议回归 |
| 原审计 AIUI-2 | `3f739035385b7640d1fcec497dc33a85d3553ffe` | 33组件清单、Form修复、已声明接线阻断；不能冒称D已有实现 |
| 拟稿时 AIUI-2后续head | `4e45836efcb85c86f5c8de57e6b07795aab6166a` | 含Tabs shrink修复；本任务只看到提交源码/标题，不以其替换原审计或声称新CI通过。正式集成负责人按最终SHA核验 |
| GROK-7走查 | `18ae5127474d6841ad331ca2251076ecca431a81` | `docs/reviews/2026-10-09-research-walkthrough.md` §4逐条9公式；§0残留8的汇总不作依据，仍是未合静态建议 |

独立全库审计附件：Library `libfile_2ab1313f0ee48191a4205a73087b624a` version0；文件 `Muyon-component-contract-audit-2026-10-09.zip`，SHA256 `9e2412dadb690ec9a8f2ac3e9e22920ebea7df3997c0c8c23ef02c4354eae969`。原始日志不入库。后续合入更新基线后，执行者在任务回报冻结新完整SHA，不改写上述历史证据。

## 1. 已有实现复用，不新造运行时

| 已有实现 | 文件 | 新任务允许的增量 |
|---|---|---|
| UIPlan/UiNode/目录/绑定/快照 | `packages/muyon_module_api/lib/src/ui/{plan,snapshot,validation}.dart` | AIUI-5集中评审所需typed/collection变化，保持未知拒绝；AIUI-3使用ComputedValue而不改事实语义 |
| stream session/parser/compiler | AIUI-1 `.../ui/{stream_protocol,stream_compiler}.dart` | AIUI-5薄接现有finalPlan和预览，不重写解析/校验；模型仍只输出id引用 |
| 本地状态/动作 | `.../ui/state.dart`、`packages/muyon_ui/lib/src/dynamic/surface.dart` | AIUI-5扩展同一UiSessionState/UiSurfaceController，不造第二dispatch或业务grant |
| 两模式planning/harness | `.../ui/planning.dart`、`apps/muyon/lib/assistant/ui_planning.dart` | AIUI-5接现有UiPlanningPort、同版本去重、ModelGateway/授权路径，非新模型网关 |
| 保存恢复 | `.../ui/workspace.dart`、`apps/muyon/lib/platform/ui_workspace_store.dart`、`packages/muyon_ui/lib/src/dynamic/workspace.dart` | AIUI-5增量codec/新目录恢复；AIUI-4调用现有CAS/checkpoint/返回协议，不再建表或重写Store |
| 导航/对象/子对话 | `apps/muyon/lib/platform/{ui_navigation_anchors,object_pages,assistant_subconversations}.dart` | AIUI-4换外壳保持实际ObjectRef/ArtifactRef、lease、taint与返回；任务/对话库不重建 |
| 询价计算 | `packages/supplier_core/lib/src/{pricing,budget,compare}.dart` | AIUI-3薄适配已有金额/税/单位/阶梯规则；无模型算数、无重写定价引擎 |

重要现状：UiSessionState持有final snapshot，computed解析只读snapshot；UiSurfaceController.acceptPlan仅接受同snapshot/intent/catalog identity。**已有runtime并不自动支持编辑后重算或跨快照换plan**。AIUI-3提供纯计算；AIUI-5在唯一runtime中实现版本化快照替换、重校验、旧动作失效与人工覆盖迁移，不能忽略此接口依赖。

## 2. 并行分片、文件所有权与集成顺序

| 分片 | 建议负责人/任务 | 可立即独立推进 | 必须等待的门槛 | 交给下游的可审交付 |
|---|---|---|---|---|
| F3a | AIUI-3 / junior或被派执行者 | 公式来源核对、纯registry/evaluator、询价薄适配和确定计算测试 | 不依赖新renderer；科研集合结果先scalar投影 | 有版本的公式定义/实例、输入依赖与ComputedValue输出，不包含业务效应 |
| F4a | AIUI-4 / engineer | 四导航/响应式布局、任务资料入口、现有现场返回与不可用退路 | 最终采用已审AIUI-2；R-1实机另排，云端片不冒称完成 | 同一harness/store/navigation接入新壳，旧工作区行为保持 |
| F5a | AIUI-5 / Codex或被派执行者 | 33组件映射表、harness fixture/模板退路、待采纳契约建议与负例 | typed/collection/row身份正式决定前只提交建议和诊断，不改正式schema | 契约差异、兼容/拒绝矩阵、合法完整snapshot/plan金样 |
| F5b | AIUI-5 | 采纳后在同runtime实现typed编辑、codec、renderer、stream/provider | AIUI-1/2精确已审基线；F5a正式决议 | 全33组件生产消费/事件/坏流可执行测试及最小失败记录 |
| F3b+F5c | AIUI-3纯计算 + AIUI-5编排 | 计算缓存/依赖失效与新快照联调 | F3a输出协议＋F5a决定 | 本地编辑→重算→新plan→CAS保存/返回，不调用模型/业务工具 |
| F4b | AIUI-4联调 | 新壳接F5输出，移动/桌面完整返回 | F5b/c、新catalog恢复就绪 | 导航、编辑、详情、刷新、pending receipt、插件失效闭环 |
| 后续业务/设备 | AIUI-6/7/9、REG-4c、R-1 | 工具/本体与实机证据按独立任务 | 上述接口与真实模块工具 | 正式tool mapping/授权/真实回执，设备golden/读屏/模型结果单列 |

文件所有权：AIUI-3独占拟新增公式registry/evaluator与业务薄适配文件及其测试；AIUI-4独占 `screens/platform_shell.dart` 等外壳与导航widget测试；AIUI-5独占共有 `plan/validation/state/workspace`、`dynamic/surface/workspace`、`assistant/ui_planning` 的契约接线与测试。`lib/ui_contract.dart` export等共有文件由唯一集成负责人顺序合入，其他分支以小补丁交接，不共享工作树并发改写。AIUI-4调用稳定store/navigation接口；需要新增恢复字段时由AIUI-5接收测试用例后实施。

## 3. 已确认缺口逐项负责人及可执行验收

| 缺口 | 当前证据 | 负责分片 | 必须落地的验收行为（详细测试名/命令见任务书） |
|---|---|---|---|
| Toggle boolean edit拒绝 | L catalog:291、C validation:219 | F5a/b | false→true保持bool，非bool拒绝；state声明/intent/operation检查仍有效；序列化重开不变string |
| Stepper/Slider数字、Date、Choice事件 | L inputs:24/284/366/489 | F5a/b | double精度/上下界、date明确格式/时区、多选稳定id有正反例；不是直接传原生对象给string事件 |
| CompareTable detail无value/rowcallback | L catalog:217、data:156 | F5a/b，AIUI-2目录Widget适配归此片协同 | 排序后点击同stable row仍打开同ObjectRef；删除/错scope/旧rev不能打开；返回保持现场；无对象行不可点击 |
| KeyValue/Choice/Chart/Table/Timeline集合 | scalar validator与保存硬边界 | F5a/b/c | 宿主来源/版本、codec形状/数量大小、未知版本、重复itemid/超限/畸形数据拒绝或只读文字退路；模型不能构造数据 |
| Checklist index,bool与fact edit | L boundary:95–132 | F5a/b/c | fact只读；可编辑项必须host声明uiState与stable itemid，重排后编辑同项；删除项/跨scope拒绝；保存恢复语义不漂移 |
| 新21组件未接renderer | L surface:562 | F5b | 33组件各一合法原始plan通过validator→真实renderer与semantic等价物；所有事件实测，不用直接Widget样例代替 |
| 本地公式不自动重算 | current snapshot final/identity | F3a/b+F5c | edit只影响host声明参数；公式输出绑定新投影版本，旧computed/旧action不可再派发；未提交业务值不变 |
| 新目录与typed/集合恢复 | scalar workspace、局部Tabs/Disclosure State | F5c，F4b消费 | 新plan往返CAS重开+导航返回保人工覆盖/稳定节点；未知codec/catalog/schema可读旧稿，不重放已成功动作 |
| 动作真实业务mapping为空 | UiBusinessAction仅测试实例 | AIUI-6/REG-4c，F5保持路由边界 | 模型只引用已登记动作；宿主选择tool/参数，审批与实际receipt决定成功，旧operation/replay/taint拒绝；F5夹具不得称实业务 |
| Tabs shrink | 审计L layout:214/271；后续4e45836修复 | AIUI-2收尾已在别分支，F5/F4加集成回归 | third→one→empty→again同State不越界；F5稳定nodeid更新后选择按host状态政策恢复。此分支不重复修产品 |
| 文档JSONL非合法library金样 | stream§2缺label/fact rows/highlight/select | F5a/b | 固定完整catalog version+host session/snapshot的合法JSONL及每个坏例；上位示意不当可执行fixture |

## 4. 必要契约变更建议关口（未采纳，不静默生效）

下面是审计产生的**建议议题**，不是本分支对ADR/stream/schema的修改或开发者可自行放宽的授权。

1. **Typed edit**：现有UiValueType已有boolean/integer，edit gate仍string-only。建议按宿主状态声明和事件schema精确匹配bool/number，finite number是否扩展UiValueType、整数/小数/界限/精度如何表达由契约负责人决定；日期优先明确ISO日历日期字符串codec而非把DateTime对象持久化。批准后AIUI-5同时更新sharedvalidator、dispatch、restore与拒绝测试，旧版本string行为不变。
2. **集合/行/项**：建议使用宿主登记、版本化、带稳定id及ObjectRef/来源version的collection codec；模型仍只给BindingRef(kind,id)。选择保留scalar承载受限host编码并实施完整codec校验，或正式扩展快照集合类型，需决议写清。仅JSON stringify过scalar gate不算实现；不得接受模型填encoded payload、任意JSON/公式/新状态键。数据规模、缺值、行身份、readonly、错误与升级行为由F5a草案精确提出。
3. **组件事件/children**：CompareTable必须明确selected-row/value身份与Widget callback；Checklist stable itemid、Tabs labels/selected、Disclosure多children组合、Slider step到divisions有统一host映射。删掉未实现事件也是正式目录能力变化，应有审查记录及保留只读形态，不能为过测试偷偷删合法未来能力。
4. **Computed实例与恢复版本**：formula registry name/version和host computation instance id分离；宿主维护输入SnapshotRef及uiState依赖fingerprint，新参数下旧结果不可冒充当前。新快照/状态迁移与pending operation失效复用现runtime；缓存不写事实、不授予确认能力。新增持久化版本须可读旧数据，不能同名字段静默改类型。

F5a交付上述建议差异和可执行负例后，由唯一集成负责人组织契约所有者采纳；若尚未决定，允许先交纯公式/外壳/诊断片，功能维持只读或文字宿主模板退路。用户授权并行推进不等于任何草案schema已经成为正式契约。

## 5. 共同门禁与回报

- 开工冻结develop及依赖分支完整SHA；已审分支未合时可独立临时组合，记录tree/冲突，不声称主线通过。一个任务一个分支，原始日志留云端。
- 先新增行为测试取得有效失败，再最小增量实现，运行各任务指定test文件、受影响包analyze和最终 `bash scripts/ci.sh`；已有坏值、未知组件/动作、权限、快照版本和scalar拒绝不能削弱。
- 不触发付费模型、不外传业务数据；fixture明确模拟。Provider缺失/不支持/超时/坏流均保完整回答与可信模板，不自动切远端扩大外发。
- Flutter缺失/SDK403时记录未运行，不寻找受限路线绕过；引用现有精确SHA CI时明确并非本次重跑。Linux golden skip不算Mac或设备验收。实机、golden、模型质量进入R-1末次清单，不能假称已完成。
- 每片交付完整SHA、允许文件diff、每个验收测试名与通过/失败/跳过/未运行计数、最小失败输入、已采纳契约差异、未实现/实机清单及下游接口说明；交叉审查按REVIEW，由唯一集成任务顺序合入。
