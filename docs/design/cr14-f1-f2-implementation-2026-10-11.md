# CR-10 F1/F2 实施方案（CR-14，ChatGPT）

基线：AIUI 交接点 `b6e185611a81853c99548d4528cd91cc8be36172`。云端只读，未运行测试；「已覆盖」指有源码机制与测试定义，不代表取得运行 PASS。原稿由用户转交，leader A 整理入库，代码位置以原稿为准。依据：`docs/tasks/CR-14.md`、`docs/reviews/2026-10-11-external-content-postmerge-audit.md`（F1/F2、第 5 节）。

**结论：** F1 已有旧捕获、来源集合、路由复查的主体机制，但「真实污染写入 → 界面刷新」通知链未闭合；需补不可回退的失效序号，与子任务实际 INSERT 前的最后复查。F2 推荐宿主把可独立提交的操作降为多张单项 `ConfirmCard`；禁用「逐项决定」保留为没有拆项能力时的兜底，不能当作 F2 完成。

## 1. F1 现状
| 核对项 | 结论 | 依据 |
|---|---|---|
| 挂载后仅真实 `markExternal` 使 clean→tainted，卡片自动刷新 | **未覆盖** | `markExternal` 锁存后直接写库，不发通知；`FoundationRepository` 只有手动 `refresh()`（`host_authorization_facts.dart:62-96`、`foundation_repository.dart:238-242`）。测试 `taint updates live confirmation…` 第 240 行手调 `repo.refresh()` |
| 旧 clean 确认在真实污染后失效 | 核心机制已覆盖；挂载组合缺 | capture 冻结 `externalContent`、`provenanceStamp`，dispatch 前比较（`surface.dart:64-78,360-385`）；缺「保存挂载回调→标记→不 pump 调用→零新 pending」 |
| 已 tainted 再加来源，旧确认失效 | 路由层已覆盖；挂载组合缺 | stamp 含 task、conversation、taint、排序来源集合（`ui_planning_events.dart:176-181`）；`mapper changes source identity…` 已测 |
| unknown/缺失不放行 | 主要宿主路径已覆盖 | `host_authorization_facts.dart:249-276`；`unknown host facts reject even a custom workspace business sink` |
| 探针缺失/抛错不放宽 | 缺失已测；抛错缺独立测试 | `surface.dart:122-137` |
| 故障后恢复原 clean，旧确认不复活 | **未覆盖（静态推导缺口）** | 刷新不推进失效序号，恢复后 stamp 回到原值，旧票据可能再次匹配 |
| flush 后、mapper 后、建子任务前复查 | 前两处已有；**SQL 排队窗口缺** | `createTask` INSERT 要等 DB 队列，INSERT 前无 admission guard（`foundation_repository.dart:1039-1063`、`storage_manager.dart:31-46`） |

交接声明「污染变化刷新已显示卡片」应收窄为：收到 repository 通知会刷新，但真实污染标记未主动发通知。注意导入 coordinator **另建 `HostAuthorizationFacts` 实例**（`import_coordinator.dart:98-102,180-190`），只给 repository 那个实例加回调会漏掉真实导入。

## 2. F1 最小方案
- **通知**：按同一 `ManagedDatabase` 共享事实变化通道（沿用拒绝锁、来源锁的共享方式）。`markExternal` / `markSourceExternal` / `markSourceExternalInTransaction` 内存锁存时**同步**推进失效状态并发布；通知可合并到 microtask；写库失败不回退锁存。`FoundationRepository` 订阅一次转发；`DynamicWorkspaceSession`、`UiPlanningEventRouter` 沿用现有订阅；`UiSurfaceController.refreshExternalContent()` 按「读者身份＋失效序号＋stamp」去重，先更新已通知快照再通知，避免重复 flush。不用通用 `onCommit`（提交后触发、单槽且已被投影服务占用）。
- **可比较版本**：宿主提供一次读取的不可变快照：taskId、conversationId、taintState、排序去重的 sourceDigests、**单调失效序号**、宿主读者身份。由宿主事实投影维护，不进 UIPlan / uiState / 事件 payload；首次观察到 unknown/缺失/异常即推进，重复读同一失败状态不再推进；恢复后只有新捕获有资格，已锁 operation 仍按真实回执处理；进程内保存，无需新持久表。`externalContent` 与 `provenanceStamp` 从同一快照派生。
- **复查点**：旧回调进 dispatch 前；workspace flush 后、宿主 sink 前（自定义 sink 同门禁）；mapper 后、startTool 前；**`createTask` 事务内第一条 INSERT 前新增宿主同步只读 admission guard**，false/抛错 → 零 task、timeline、message、prepare。授权、人工确认、审批、防重放、账本、回执顺序不变。
- **pending 两种情况**：污染后才点旧回调 → 建 pending 前拒绝；clean 时已建 pending、flush 中被污染 → 阻止后续路由和子任务，但不清已有 pending/锁，提示需重新生成确认。

## 3. F2：降为多张单项 ConfirmCard（推荐）
现适配器只建一个 `ConfirmItem`、展示整个 `actionContext.draft`（`surface.dart:932-984`），`items.length == 1` 不等于只有一条业务操作。不得：把批卡换成一张单项卡、把整批草稿复制成多张卡、把 `onIndividual` 接到整批 confirm。

- 宿主私有拆项投影，只处理模块明确声明可独立准备/提交/回执的操作（先用 `inquiry.set_item_qty` 的 A/B 两条记录验证），不切原子批量工具。
- 每项冻结：稳定 `itemId`、真实父任务与呈现身份、宿主给的目标/旧值/新值/记录引用、独立 `operationKeyRef`、单项 `DataSnapshot`/`UiActionContext`、稳定 `surfaceId`、宿主固定的工具与参数映射。每项独立 snapshot/context/plan/workspace/controller/router，由固定宿主列表排列。拆项与执行绑定不交给远程 UIPlan。
- 行为：A once 只建 A 的 `waitingConfirmation` 子任务；宿主确认后只执行 A，成功显示来自 A 的真实回执；B 拒绝零副作用；A 的失败/未知不解锁 B；同一尝试恢复原键，无法可信恢复保持只读；新尝试用新命名空间（取消状态按 `node.id` 保存，`state.dart:364-369,722-723`）。
- 禁用「逐项决定」（`batch individual control is disabled without an individual route`）保留为无拆项能力分支；此时仍须保留真实本地拒绝——不能把 `onEvent` 置空，`onReject` 也受 `active` 控制（`surface.dart:970-987`）。F2 关闭证据必须是「确认 A、拒绝 B、真实执行与恢复不串项」。

## 4. CR-10 第 5 节组合测试
- **主测试 `human_import_restricts_mounted_clean_cards_without_manual_refresh`**：真实 `MuyonHost`/`ManagedDatabase`/inquiry；`InquirySnapshotFixture` 建 project_item（数量 2）；宿主 start 建任务并断言 clean；挂载真实 DynamicWorkspace；保存 `onDecision`、`onAllowAll`、capture 并断言非空；在 ImportReviewView 点 `select-r0` 和「确认导入」（不手动 refresh、不重挂、不换 plan）；断言 parent tainted、来源含目标 digest、警告出现、「全部允许」消失、plan revision 不变；调旧回调 → capture stale、零新 pending/子任务/审批/回执/出站、数量仍 2；导入本身成功且不重复。
- **正对照 `human_import_preserves_individual_once_and_reject`**：导入后新渲染 A 卡 once → 只准备 A，宿主确认 A 的 requestDigest 后只改 A；B 拒绝零副作用；不增会话或持久 grant。不得借 F2 重建证明 F1 通知已成立。
- **时序负例**：标记后不 pump 调旧回调；导入来源未落盘（占住写队列）；workspace flush 等待中导入（经 `UiWorkspaceController.open(store:)` 包装真实 store 暂停 save）；子任务 INSERT 排队中污染（含事实不变正对照）；tainted 后新增第二来源（P1→P2，同项目新文件或新 revision 不算新来源）；unknown/缺失/抛错后恢复旧回调仍无效；标记持久化失败仍收紧；单项恢复不串项。可复用 `pending and failed marker deny across service instances…`（`assistant_authorization_facts_test.dart:240-278`）。
- 断言口径：比较旧回调造成的增量，导入本身的合法新增不算；先证明前提成立（工具已注册、回调有效、进入暂停点）；已有行为的测试可能直接 GREEN，如实记录。

## 5. 实施任务（每项 ≤1 天，测试先行，可独立合入）
「依赖 PR42」指包含 b6e1856 交接修复（及 SN-4/SN-5）的最终集成结果。
| 任务 | 内容 | 依赖 |
|---|---|---|
| CR14-01 事实变化共享通知 | 跨 Facts 实例通知、锁存先于提交、失败不回退、不同 DB 隔离、重复标记去重；Foundation 订阅/解绑 | **不依赖 PR42，可先做** |
| CR14-02 一致快照与失效序号 | 来源新增、unknown/缺失/抛错及恢复后旧 capture/pending 拒绝 | PR42、01 |
| CR14-03 已挂载卡自动刷新回归 | 真实 markExternal、无手动 refresh；不 pump 旧回调、新来源、dispose、通知/保存次数稳定 | PR42、01-02 |
| CR14-04 等待窗口与 INSERT 前 admission | flush 等待、INSERT 排队中污染及不变正例 | PR42、02 |
| CR14-05 宿主单项操作投影 | A/B 目标、draft、记录引用、操作键、surface 隔离；纯投影，不开放业务 UI | **不依赖 PR42，可先做** |
| CR14-06 单项持久会话与固定列表 | once/reject、无全部允许；无拆项或 unknown 仍能真实拒绝；受控端口验证 | PR42、02、05 |
| CR14-07 两项真实执行与恢复隔离 | 真实 `inquiry.set_item_qty`，A 只执行 A、B 拒绝零副作用，重开不串项不重放 | PR42、04、06 |
| CR14-08 真实人工导入主组合 | 第 4 节主测试与正对照 | PR42、03-04、07 |
| CR14-09 导入时序与第二来源组合 | 落盘前、flush 中、落盘失败、P1→P2 | PR42、08 |

合入顺序：01、05 先并行；PR42 交接修复合入后做 02，再并行 03/04/06；07 真实逐项；08-09 真实导入闭环。
