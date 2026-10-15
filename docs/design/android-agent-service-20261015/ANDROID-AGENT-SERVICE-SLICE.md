# Android 独立 Service：Rust Agent 当前片修订合同

2026-10-15。**B 为用户已确定的当前方向；A（UI 进程内 Agent）作为首片及过渡路线已取消。** 可信内置插件范围已确定。用户随后明确“设计完成后开发”，授权设计完成、独立审查无阻断后直接测试先行实施，不再等待泛化开工确认。本稿具体化 B 的执行、通信和恢复合同；源码尚未实施。root据此设计明确选定可信Catalog与整个Agent同在独立Service，不把父级意见冒充用户额外发言，不扩后台/权限/真实模型资源。

源码基线 `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`，tree `bca71d8794edab6c63989f6cdfebbca32d059c03`。此前 c0e20c5f 文档保留为历史方案，不是本片前置审批。以下区分官方平台事实、固定源码事实与本片拟实现的约定；全部新运行结果均 NOT_RUN。

## 1. 修订范围与两个进程边界

整个 `Agent::drive / RuntimePorts / NativeSession / AuthoritySource / PurposeReview / PhysicalReadHandler / NativeStore / ModelGateway` 放在系统管理的、非导出的普通 `android:process=":agent"` bound Service。UI 只持 Binder proxy 和展示状态；不在 UI 构造 Agent、执行 handler 或打开运行存储。Kotlin/Java 仅做 Android 生命周期、AIDL 编解码与控制转发，业务、授权、回执和最终载荷判断仍在 Rust。无需先交付 A。

**外层 B 为用户要求；本片内部后端作为设计明确选定。** 现 Linux child 仅运行 Catalog 元数据/票据协议；真正 handler、授权、回执和模型网关本来就在 host（host lib.rs:337–445，read_registry.rs:73–119，model_gateway.rs:31–76）。保留现 Linux child 路径及回归，不直接把 std::process/pipe/fcntl/exec 当 Android 适配。

本片选定的内部后端：一个 persistent Catalog 在 :agent 的 Rust worker 内，经私有 ContractTransport 复用严格 wire parser、64KiB 边界、fatal latch、close/generation/ticket 语义。这样 Agent 全部仍在独立 Service，**Catalog 自身相对 host 的 child 地址空间边界不再存在**。这是在最新“设计完成后开发”授权下明确披露的内部设计，不是恢复A；不增加第二个Android contract Service。若后续要求保留Catalog自身额外Android进程，再单独设计第二Service的协议/死亡/生命周期，不假称当前Linux executable已可用。不得静默切换后端或缺后端时返回成功。

官方明确支持 Service 独立进程；Android10 的 writable app-home exec 限制是特定限制，不能说成 Android 不支持多进程。[进程与线程](https://developer.android.com/guide/components/processes-and-threads)；[Service manifest](https://developer.android.com/guide/topics/manifest/service-element)；[Android10 exec 限制](https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission)。

## 2. A/B/C 对照与推荐

| 方案 | 隔离对象与 UID/资源 | 当前结论与增量 |
| --- | --- | --- |
| A：UI 内 Rust worker | 仅线程，Agent 与 UI 共享内存、UID 和进程故障 | 用户已取消；只作对照，不实施或作为 B 前置 |
| B：普通 :agent Service | 整个 Agent 与 UI 地址空间/故障域分离；仍为同应用 UID、既有文件与权限范围 | 当前必做；新增 Binder/lifecycle/准入/查询/死亡处理，保留同一 Rust 业务链 |
| C：isolatedProcess | 额外 isolated UID、无自身权限；不能假设访问 app 私有目录/凭据 | 暂不纳当前片；现 UID/路径型 store 需 Rust FD/存储/授权 broker，范围更大 |

B 提供故障分离，不是新的文件/网络/凭据权限沙箱，也不保证系统内存压力下 UI 永存。C 的 FD/socket/broker 会重新赋予能力，必须限制范围，不能发任意路径/载荷/凭据代理。当前均不访问真实凭据或模型。[UID 沙箱](https://source.android.com/docs/security/app-sandbox)；[隔离 Service](https://developer.android.com/guide/topics/manifest/service-element#isolated)；[FD 所有权](https://developer.android.com/reference/android/os/ParcelFileDescriptor)。

A→B 原则上能复用 Rust 内核和 worker，但 UI Arc 对象、同步长 run API、Application singleton、无死亡处理的本地状态都要改。因此现在直接设计 B；不声称零返工，也不给无依据精确工期。isolatedProcess 不作为普通 B 的同义词。

## 3. Service、线程与控制所有权

- manifest 明确 private `:agent`、exported=false、isolatedProcess=false，显式 Intent 绑定。仅 UI 可见时显式发起有限离线任务；不新增权限、started/foreground Service、常驻、自动重启任务或真实模型资源。
- Service 内唯一 Rust 控制壳（Send/Sync、小型控制字段/不可变快照/根租约），全 Service 的 Binder clients 共用。初始化/运行最多一个 Rust worker，零等待运行队列；New submit 若占用就 Busy。Rc/RefCell/session/provider/handler 全在该 worker 构造、使用和 drop，无 unsafe Send/Sync 或第二 Agent loop。
- Binder pool 可并发，Service lifecycle 在其主线程；**都不运行 Agent、文件 I/O 或 join**。Binder handler 仅有界校验并调用短控制接口；Service-owned 后台工作执行初始化/持久化/运行。UI的Binder调用也在后台，run不成为同步长RPC。Rust控制壳尚未建立时只返回TransportInitializing，不编造Rust epoch/lease/Ready，也不受理操作。平台bootstrap保留自己的Service/连接generation；初始化期间close、最后client死亡或Service销毁须使旧generation失效，迟到构造结果立即close并后台drain，不能发布Ready/lease。进程内native runtime gate和跨进程根锁阻止旧初始化/清理未结束时再启动第二worker。
- Service有至多一个专用后台join/drain waiter，调用Rust内部await_settled/join_worker（不暴露AIDL）；正常Terminal和close都由Rust在真实worker join与资源drop后分类/发布，Kotlin不判断业务终态。不得在Binder/main/admission锁内join。
- cancel/close/ClientGone 直接发相关控制信号，不排在运行 worker 后，不借用忙碌 Rc、不获取根文件锁。实际信号须到 provider poll、handler 前、原始结果保留后及最终载荷发送前；Requested 仅是请求。
- UI Application 在各进程有各自实例，不能作跨进程单例。现有 by-lazy metadata diagnostic 可留在 UI：fresh Catalog 无运行 store，既不是 Agent 执行，也不计 B 证明；不为了本片扩迁移其接口。

[AIDL 线程/oneway](https://developer.android.com/develop/background-work/services/aidl)；[Service 与 bound 生命周期](https://developer.android.com/develop/background-work/services/bound-services)。

## 4. 有界 IPC 与受理状态机（私有 protocol1）

方法名是 owner 对齐的语义签名，实际 AIDL/UniFFI 拼写在实施计划中固定；不导出 Arc、指针、原始 Catalog frame、授权 JSON、数据路径、草稿、模型脚本或业务正文。SDK Java/Kotlin AIDL 作平台封装，Rust 仍经既有 UniFFI/JNA；不引入需要更高 API 的平台 Rust Binder 后端。

| IPC | 输入 / 返回与约束 |
| --- | --- |
| connect | protocol + UI 进程 liveness Binder；返回 source build identity、当前 service_epoch、服务 Ready/Initializing/RecoveryRequired、bounded client lease。最多2个 client lease；额外返回 Busy。每 UI 进程共享一个 liveness token；同一存活token在同epoch重复connect幂等返回原lease，不消耗第二额度；初始不可见，须visibility控制生效才可submit |
| set_visibility / release_client | 当前epoch、lease、单调client observation_generation、visible或release；同generation同值幂等，旧generation/冲突拒绝。release失效该lease且不释放正在运行槽；原owner死亡/release请求取消原run。最后可见lease变false禁止新受理并请求取消/关闭，控制路径独立 |
| submit | expected_service_epoch、request_id、四选一 builtin variant、client lease；返回 QueuedVolatile / Existing(snapshot) / Busy / Rejected；Queued 不等于持久受理、授权、执行或完成 |
| status/current | 当前 epoch + lease；current 返回唯一在途/待核对运行或最新终态的原始 request/run 身份，最多一个快照；UI 丢失 request ID 后必须先调用它，不重建 ID 来补发 |
| lookup/result | 原始 request_id 或 host run_id + 当前连接身份；只读读取原始记录/不可变快照；跨 epoch 可以核对历史，绝不运行 Agent、重签授权或恢复会话 |
| cancel | 当前 epoch + 原始运行绑定 + lease；Requested / AlreadyTerminal / NotRunning / NotActive / Rejected。仅匹配活动原始绑定时置标；旧 epoch 不得控制新运行，NotRunning 不证明零执行或取消成功 |
| close | 当前 epoch + lease；禁止新受理并请求合作停止；Closing / Closed。Closed 仅表示本 runtime 的 worker/drop/join、存储与锁已结清，不表示 Android PID 必已消失 |

request_id 为 `[A-Za-z0-9_-]{1,64}`，只作相关身份；host 生成 service_epoch/run_id（有界32hex）不作授权。run summary 回显 protocol/request/variant/build identity、原受理 epoch 与当前观察 epoch、成对可选实际 task/attempt、闭合 terminal/reason、可选 opaque 原 receipt identity 与 outcome。实际 State 尚未建立时不能编造 task/attempt。shipping 无计数、raw/history/answer/projection；字段缺失不作成功或未执行默认值。每个快照/RPC回复带当前service_epoch与单调server_snapshot_revision；发布状态变化才递增，查询只复制。revision/client generation为非负且不超Long.MAX_VALUE的checked整数，不回绕；溢出拒新受理并保留独立停止信号。

请求/control Parcel 应用上限4KiB，snapshot/result8KiB；固定字段/枚举/身份长度，单客户端最多一个 status RPC 在途，独立于 status/submit 的有界客户端控制执行通道（不能共用被卡住的客户端队列）；无 streaming callback/无 oneway 运行队列。服务快照仅复制小型不可变状态，不能扫描磁盘或等待 worker。超限/协议/身份/epoch 不符明确拒绝，无自动 retry。客户端与服务端检查实际 Parcel/字段边界，限额不是 Binder 保证。

Binder 的当前1MB是**进程所有在途事务共享缓冲**，不是每个请求可用预算；oneway 也不是业务 ACK。TransactionTooLargeException 不能区分请求未达与响应丢失，DeadObjectException 也可能是队列/缓冲失败；均先记观察不确定并重建连接，不推断未执行或已取消。[容量/部分失败](https://developer.android.com/reference/android/os/TransactionTooLargeException)；[DeadObjectException](https://developer.android.com/reference/android/os/DeadObjectException)；[Binder 调度](https://source.android.com/docs/core/architecture/ipc/binder-threading)。

### 持久准入、相同请求与终态

短 submit 只预约一个 volatile 槽。Rust worker 在开始现有 Agent 链前，获得根租约、检查配额并 durable 写入 request→run/variant/source/原受理 epoch 的索引与 pending 标记，之后才能发布 DurablyAdmitted。此 ACK 证明 run 身份已入账，不证明权限或实际 task 已创建。实际 task/attempt 在 State 创建后成对记录，再进入相同 drive；原有 running receipt 仍须在 physical handler 前写入。

相同 request_id、相同不可变输入绑定只返回 Existing；改变 variant/protocol/source 绑定为 RequestConflict，不创建运行。任何重新连接、onServiceConnected/onStartCommand、查询、轮询或状态缺失均不能调用 submit 重派。volatile 槽在取消/出错/Closed 时须有确定状态；丢失 volatile 记录可能显示 Unresolved，不推断 NotStarted。

Terminal 为 Completed/Cancelled/Failed/BudgetExhausted/OutcomeUnknown；安全 reason 采用取消、权限/purpose/contract/storage/provider/deadline/budget/interrupted/internal 的闭合枚举，无异常文本/路径。receipt outcome 为 NotStarted/Unknown/RecordedSuccess/RecordedFailure。Unknown 可没有可恢复 ID；NotStarted 需正面证据。已确认原始读取成功即保持 RecordedSuccess，即使整体任务取消/中断；未提交/running/持久化不确定优先为 OutcomeUnknown。持久 terminal 与原回执/任务事实一致并完成真实清理后，才返回 Terminal。B 的 host/receipt 仍是唯一业务真相；准入索引是有界生命周期索引，不是第二份业务回执。

## 5. UI、进程死亡、重连与可见生命周期

UI 保留本地connection/lease/display generation与每个选中run的已应用revision；晚到回复须校验这些本地generation、当前service_epoch、原request/run/variant/build。相同epoch且revision较旧的回复丢弃，Terminal禁止回退Queued/Running；同一观察key（run身份+快照类型）的重复同revision仅同一权威快照值可接受；不比较cancel ACK与status等不同RPC外壳。新epoch先做current/lookup核对；显式历史lookup单列展示，不能覆盖新的活动运行或抹除已确认原终态。观察层TransportLost/ObservationUnknown与Rust实际terminal分开，查询查明原终态不等于重新执行。新连接先 connect/current/lookup；持久终态已在 Service 崩溃前提交，则查询回报原终态；只知 running/原始结果而无可信终态则回报明确 Unknown/Interrupted，无自动执行。

UI process death 可丢失本地 request ID；Service current 必须能返回唯一 outstanding 原始绑定。liveness Binder death 对原 owner 的 run 发 ClientGone，Rust 请求合作取消；新 UI 只能先核对原证据，不自动接管、继续或重开。页面面板detach只撤销观察，不改变Application可见租约；Application经set_visibility/release_client显式通知真正可见性变化。最后可见lease=false时停止新受理、请求当前运行取消/关闭，允许已有有界连接仅用于核对和drain，不承诺后台完成业务。正常 Terminal 后只允许新的显式用户操作提交新 request；lookup/恢复不提交。close 后同一 runtime 永久拒绝新 submit，全部解绑后重建 Service/runtime 须新 epoch 并先核对。配置重建保持原request/run身份与观察相关性，不自动发新请求；首片不承诺旋转不中断：若期间最后可见lease变false，就按同一规则合作取消，随后visible=true不能清除已发取消/自动恢复。其实际Android时序须测试。下次可见须先核对，无自动重新 submit。该可见租约是平台生命周期信息，不是业务授权。

纯 bound Service 最后 unbind 可被系统销毁，系统也可随时回收；不依赖 onDestroy/Rust Drop 被调用。close 在活进程中只有实际 worker/drop/join/锁释放后为 Closed；进程死亡/断连是 TransportLost/HostDied 观察，不能伪造 graceful Closed、Cancelled 或回执。OS 证实 PID 消失也不说明死亡前没有读取。

minSdk24 不能仅依赖 API26 onBindingDied 或 API28 onNullBinding；使用 API24 的连接/DeathRecipient/有界建连超时路径并 guard 新回调。断连可能重连原绑定，dead binding 需要解绑重绑；连接可恢复不等于任务可以重试。[ServiceConnection](https://developer.android.com/reference/android/content/ServiceConnection)；[进程生命周期](https://developer.android.com/guide/components/activities/process-lifecycle)。

后台常驻或跨 UI 死亡持续执行需另行合同/资源决定；本片不自动增加 foreground-service 权限或类型。普通 bound 规则不等同 background started-service 规则，也不保证永存。[后台限制](https://developer.android.com/about/versions/oreo/background)；[FGS 启动限制](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)。

## 6. Service 存储所有权和执行上限

Service bootstrap 从自身 Context 获取 canonical filesDir，Rust 在 `native-agent-service-v1` 下维护私有实验布局；UI 不传路径、不打开运行库。UID/0700/0600、祖先 symlink 检查、strict restore/atomic fsync/rename、原始 NativeStore 单回执所有权保留。普通同 UID 不阻止其他受信 app 组件访问，不能称为 hostile same-UID 沙箱。

Service 控制壳持唯一 RootLease（仅有 Send 文件租约，不含 Rc），初始化后台 worker 完成有界 inventory/恢复读取后才能 Ready；根锁为非阻塞独占，冲突 Busy/RecoveryRequired。该租约覆盖本 Service runtime 的索引、扫描、配额预留和 run mkdir，并保持至全部 worker 真正 join/关闭；控制路径不等待此文件锁。OS 死亡释放锁是待平台验证的恢复前提，不能用连接异常假定它已释放。

最多8个 run 目录、总8MiB，计入 source/native/task/outbound/admission index/summary/locks/temp/残留；bounded entries/temp multiplicity。新 active run 预留2MiB事务峰值，包含新准入索引旧/候选/临时文件；owner 须给布局推导，超出该预留先拒绝，不放宽。全局索引编码<=64KiB（最多8条），旧/候选/temp均计账。8目录是独立上限，不保证8次均有空间；无自动删除/reset/replay。

raw/bootstrap<=8KiB，native.db既有64KiB；新 façade 的 task.db<=128KiB、outbound.db外层<=512KiB，内层 model body/ledger<=64KiB仍保持。新限制须真实 bounded read/prewrite 与 valid sibling。未知文件/损坏/index与receipt不一致/未完成证据为 RecoveryRequired，保留原始证据；只读核对不恢复权限、驱动或隐式重试。

Agent显式 steps2/calls2/context32768/output16384/total65536（沿用现有计费单位）；独立 read admission budget1，第一轮只广告选中操作，第二轮 tools为空且 dispatch再拒第二读。正例实际两次离线载荷、一次 handler、唯一回执，不从预算推算结果。合作 deadline5s，无任意 syscall 硬中断承诺。四种 Rust 固定合成映射/seed0x7631、offline-fixture endpoint；不访问真实业务库、模型、凭据或新网络资源。

## 7. 实施所有权与具名验收门槛

原 native owner：host + bridge crates 的 transport、控制/准入/索引/worker/FFI；原 UI owner：现 Compose/state/app 的 private Service、AIDL/proxy、liveness/visible lease、状态显示及生成 Android bindings；原 checker：checks/workflow/独立 oracles；root：固定合同、组合与推送。Core/Plugin 公开规则不默认重新分工；必要 carve-out 先由 root 明确。只保留同一 drive 与原有授权/handler/receipt/projection/final-byte gate。实施原作者与非作者审查分离。

先固定具名目标和输入，取得可编译、可达、明确拒绝的 Rust/生成 JVM semantic RED，再实现。编译/绑定/load/超时不是行为 RED。不得以 A 产品实现作为中间交付；Linux/JVM 的 engine harness 是 B 的内核验证，不是 UI 进程 Agent 运行路线。

| 门槛 | 必须证明 | 证据限制 |
| --- | --- | --- |
| Rust/真实生成 JVM | 新控制入口→同一 drive/注册 physical read/原回执/actual第二轮安全载荷；四映射、私有canary、严格 transport；准入索引/重复键/Unknown/control/join/quota 负例 | 非 Android Binder 证明；probe 与 shipping source/library/binding 分离，probe 不换 permissive policy 或 driver |
| Android build/package | fresh API24 arm64+x86_64 新host依赖、AIDL/Service、manifest非导出独立进程、绑定bytecmp/ELF/import/六JNI身份/16KiB/zipalign/lint/普通无native构建 | 无 PID/UID/Binder、ART、fsync/lock、生命周期、真实隔离验收 |
| Android 真实进程 gate（待另行允许的设备执行） | 实际不同UI/Service PID、预期同UID、真实Binderproxy、Service加载并运行同一Rust链；在明确阶段屏障杀**真实Service**，观察UI存活、原回执/锁/新epoch、status不新增attempt/handler；UIdeath、replyloss、低层Bindererror、cancel、lastvisible/unbind分开 | 模拟异常、静态manifest、host SIGKILL不能冒充Android进程/调度/存储证据；无设备不阻碍前两层开发，但该层继续NOT_RUN |

死亡屏障至少：准入入账前/后；durable running receipt 后 handler前；真实read后 rawfinish前；durable raw后 terminal前；durable terminal后 reply前。健康 sibling、仅丢reply不杀进程、旧epoch回复/控制、两client并发、Busy零排队、slow/deadclient、root锁释放/损坏、current恢复遗失requestID与不重派必须独立断言。原有Rust/metadata/UI回归保持。

新 guard 需 baseline GREEN 后有效逆变异：准入去重/重连误submit、最终授权、第二读预算、旧epoch相关、忽略独立cancel、提前Closed/释放、running结果误报失败/取消。记录精确可编译变异与首个目标断言，不把setup/timeout当KILLED；不预报未来测试数量。原始日志外置。

## 8. 当前状态与剩余决定

B方向、可信内置范围及设计完成后开发的授权均已定；A首片/过渡终止，不需要A审批或泛化开工确认。本文明确选定Catalog与整个Agent同在:agent Rustworker，Linuxchild保留；本文及独立复审锁定本片实施接口/验收，设计无阻断后直接激活原owner测试先行。C、后台常驻/FGS、新权限/凭据、真实模型、业务数据库、公开M03及不可信动态插件均超出本片。

截至此合同固定时仅完成分析文档，未实施、未跑新测试/设备/构建。原所有writer/分支保留；独立复审无阻断后直接按实施计划激活原owner，root唯一组合/推送/集成develop。授权来源记录为用户最新“设计完成后开发”，不是先前追问或原A文档审批；新权限、后台常驻/FGS、真实模型/凭据或额外资源仍先报告。
