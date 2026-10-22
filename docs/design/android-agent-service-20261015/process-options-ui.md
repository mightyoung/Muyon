# Android Agent 进程方案与 B 首片 UI 合同候选（只读）

2026-10-15。用户最新决定：**A（UI 进程内 Agent 首片/过渡）取消；B（系统管理的普通独立 Service 承载整个 Rust Agent）是当前片要求**。可信内置插件已批准；这不等于批准内部 Catalog 改为进程内。下文是供 root 固定合同/非作者审查的方案，尚未激活实现。原作者树324b25e仍 clean；无源码、构建、测试、设备、工具链、模型、真实数据、权限或 push 操作。

## 三个方案与两个独立决策轴

| 方案 | 进程/资源边界 | UI 适配与本轮结论 |
|---|---|---|
| A：UI 进程 + Rust worker | 同堆进程、同 UID；native 进程级故障可能终止 UI | Application worker/直接 FFI 最少一层 IPC；**已取消，不再作为先做步骤或回退**。它并非 B 的技术前置。 |
| B：整个 Rust Agent 在 `android:process=":agent"` 普通 Service | 独立进程/内存，但仍属同 app UID/权限域；不构成凭据/文件权限沙箱 | **本片目标**。UI 用跨进程 Binder/AIDL client；Rust runtime、authority、store、真实工作单飞都归 Service。可直接首片，无须先实现 A。 |
| C：`isolatedProcess=true` | 系统提供无自身权限的特殊隔离进程 | 不能假定继承普通 app-private 路径/认证能力；需要限定 FD/数据/认证代理和相应生命周期合同。本轮可信内置插件不必因此增加此范围，也不能称 C 不可实现。 |

冒号 process 是 Android 官方支持的 app 私有进程；isolatedProcess 是不同设置。普通分进程没有自动变更 app UID 权限，C 的“无自身权限”则使现有私有文件/认证路径不能照搬。文件/凭据代理需求是结合权限和现有路径代码的**架构推论**，不是本轮运行结论。[Service manifest](https://developer.android.com/guide/topics/manifest/service-element)、[Application Sandbox](https://source.android.com/docs/security/app-sandbox)

**外层 Agent A/B/C 与内层 Catalog transport 独立**。当前 `rust-agent-host-lab/core/src/lib.rs:102,129` 固定 PluginProcess，`src/plugin_process.rs:29,36` 用 Command/fcntl/pipe。选 B 只把整个 Agent 移到 Service，不证明这个 child 已能在 Android 打包/执行，也不自动批准改成内部 Catalog 调用。B + 保留 child、B + 另经批准的内部 Catalog seam 是两条不同候选；后者仍待单独决定。不得把“可信内置”偷换为已批准 transport。

## 官方平台约束 → B 合同要求

- **独立 Service 仍需 worker。** 组件生命周期默认在所在进程主线程执行；远端 AIDL 从 Binder pool 并发进入，同一对象同一调用线程的顺序不等于全局顺序。Service Binder 方法只校验/预约/读取小快照；实际 `run_once` 在 Service 内 Rust-owned 单 worker 执行，所有 Rc 状态在该 worker 构造/使用/销毁。独立 cancel/close 只操作 Rust 并发 control，不能借 Binder thread 访问 Rc，也不能排在阻塞 run 后。[Processes/threads](https://developer.android.com/guide/components/processes-and-threads)、[AIDL](https://developer.android.com/develop/background-work/services/aidl)
- **Binder 不是任意容量流。** 官方当前1MB是进程所有在途 transaction 共享，非单次可用额度；请求或回复失败可能无法区分，按部分失败处理。one-way 只表示异步传递，非已受理/已执行，不能靠无限 one-way 队列获得背压。[TransactionTooLargeException](https://developer.android.com/reference/android/os/TransactionTooLargeException)、[AIDL](https://developer.android.com/develop/background-work/services/aidl)
- **失联不证明零效果。** DeadObjectException 也可能来自 one-way 队列或 Binder buffer 耗尽；按连接失效恢复，但不由异常认定进程确死、任务失败、取消成功或未读过。保留原 run/request，重连只查 Rust 记录。[DeadObjectException](https://developer.android.com/reference/android/os/DeadObjectException)
- **生命周期与后台边界。** 纯 bound service 最后一个 client 解绑后会被销毁，除非另有 started 生命周期；Android8该后台服务限制不直接限制绑定本身，但绑定不是永生承诺。首片只在可见 UI 发起有限运行，Application client 跨 Activity/panel 生命周期保持 binding，直到明确结束策略；不新增 FGS、通知/唤醒权限或后台 daemon。不声称 UI 进程死后仍持续执行。[Bound services](https://developer.android.com/develop/background-work/services/bound-services)、[Background limits](https://developer.android.com/about/versions/oreo/background)、[Process lifecycle](https://developer.android.com/guide/components/activities/process-lifecycle)
- **绑定状态要分开。** bind 返回成功不等于已有 Binder，Connected 也可能永远不到；Disconnected 保留绑定，服务再次运行时可收到 Connected；BindingDied(API26)要 unbind/rebind；NullBinding(API28)不能变成可用且仍需 unbind。min24 路径须有老版本失联/超时处理，不假设新 callback 一定存在。DeathRecipient 在 Binder thread 回调，UI更新须切主线程。[ServiceConnection](https://developer.android.com/reference/android/content/ServiceConnection)、[DeathRecipient](https://developer.android.com/reference/android/os/IBinder.DeathRecipient)

B 同 UID 可访问普通 app-private 数据的权限域不等于文件可无锁多写，更不等于应把凭据传给 UI。首片没有真实凭据；未来认证按受控引用/专用通道另立合同。C 若采用代理，只给最小所需能力，不以世界可读目录或批量传秘密“解决隔离”。[Application Sandbox](https://source.android.com/docs/security/app-sandbox)

## 固定0ab源码落点与复用边界

以下路径相对 `experiments/redesign/`，均来自固定 `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`：

| 当前源码 | 对 B 的具体影响 |
|---|---|
| android-compose-lab/app/src/main/AndroidManifest.xml:3 | 注册 MuyonLabApplication；尚无 Service 声明。候选新增显式 internal Service、exported=false、`:agent`，不新增 uses-permission/FGS。当前内容从固定 Git 对象读取，不以本地旧树代替。 |
| android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/MuyonLabApplication.kt:8–13 | 当前 diagnostics 是 **by lazy**，没有 onCreate 强制 native 初始化。Application 会随 app 进程创建分别实例化；不能以“Application singleton”声称跨进程唯一。B 中 UI getter应只持 client；Service显式持唯一 runtime owner，不在 Service 再调用该 UI getter创建另一套 native coordinator。 |
| 同目录 MainActivity.kt:8–10；MuyonLabShell.kt:27,44 | Activity 才装 Compose；Shell 读取 Application diagnostics，执行端口 availability 仍是一次 remember 快照。B 的 client binding/status 需可观察；通用 RustUiPort 不因远端连接就升级业务 CONNECTED。 |
| android-compose-lab/state/.../RustDiagnosticCoordinator.kt:30–45,50–106 | lease、迟到展示隔离、实际返回前单飞可复用为纯状态规则；旧锁/slot只在一个进程，不能直接当 Service 全局锁。Service权威 gate仅管理本片 Agent工作，UI局部 gate只防重复点击。现已批准stateless诊断不共享Agent store，无依据要求迁移。 |
| android-compose-lab/app/.../DiagnosticPanel.kt:19–29 | panel detach/15s显示超时保留，仅撤观察；不能直接 unbind整个 app client、close runtime或伪造 cancel ACK。 |
| rust-agent-host-lab/core/src/lib.rs:100–116,150,298–479 | Rc/RefCell会话、注册/权威/一次原回执/物理handler/结果投影仍由 Rust持有；不可经 Parcelable传对象或让 Binder pool并发 borrow。 |
| core-agent-lab/core/src/agent.rs:209,215,229–249 | Service内仍调用同一 Agent drive/registered ports；不在 Kotlin/Binder层另造循环或判授权。 |

[Android Application 文档](https://developer.android.com/reference/android/app/Application)确认 Application 在 app/package进程创建时实例化；上表对 lazy 的说明来自当前源码，不能误写成“现 onCreate 已经启动了两个 runtime”。

## B 首片可冻结的最小接口/状态候选

仅 shipping metadata：实际 task/attempt/terminal、opaque原 receipt identity/outcome、bounded真实 steps/provider-call-attempt/read-handler-entry计数；无raw/history/businessvalue。所有权限、范围、来源、账本与操作语义在 Rust。所有以下名字/预算待 root 合同审查，并非已实现 ABI。

- UI `AgentServiceClient`：Application级一个 explicit bind；Compose仅 attach/detach观察 lease。Service为唯一 Agent runtime/store owner，UI不打开 native.db、不直接启动 Agent FFI。PR84元数据FFI保留原UI路径，不等于在UI构造Agent。
- 远端 IPC：`submit(requestRef, variant, observer)` 快速返回 Service预约状态（非 durable accepted）；Service worker执行Rust open持久化真实 runId，再在同一获准预约内部执行一次 run_once。`cancel(runRef)`/`close(runRef)`独立快控制；`lookup(requestRef|durableRunId)`只读；`attachObserver`/`detachObserver`只改订阅。可用AIDL+closed Parcelable，不能跨进程 LocalBinder cast。
- `submit` 的同 clientRequestRef/同内容只对应原预约/原run；异内容冲突。UI断线丢回复不是重新 submit 理由。实际 NativeAccepted 必须来自 Rust open记录，不能由 Binder成功/oneway返回制造。若 close/cancel 先于nativeopen，保存对应 pending-control并在run进入前处理；未登记/UnknownRun不许当Closed。精确注册竞态由Rustowner合同冻结。
- envelope携 protocol、clientRequestRef、当前serviceInstanceEpoch、真实durableRunId(受理前不存在)、task/attempt、typed状态/错误；epoch只做相等隔离。重启得到新epoch，lookup仍能按旧durable ID只读核对旧事实；不把新连接当同一live runtime，不自动重开/重跑旧工作。
- client观察状态：Unbound/Binding/ConnectedUnavailable/ConnectedReady/Disconnected；请求区分ReservedLocally/Opening/NativeAccepted/Running/Closing/Terminal/ObservationUnknown。CancelRequested不等于Cancelled，Closing不等于Closed。UI/Service死亡、回执未知不覆盖Rust已知效果；旧callback不覆盖新lease，但原回执仍由Rust保全/查询。
- 回调在UI主线程按当前lease+serviceepoch+request/run identity复核再呈现。Service端不持Activity；慢/死 observer不能卡住Rust worker、cancel或close。断开清proxy/观察，连接恢复只lookup，零重提。

**可审预算候选**：Service全局1个active/opening工作、等待工作队列0（否则Busy）；每IPC请求Parcel≤4KiB、metadata快照≤8KiB；一个app client一个observer，进度最多保留1个最新快照，终态先由Rust持久记录再通知/可查询；无无限token流或one-way积压；显示等待沿15s后标等待超时而不释放runtime slot。它们是刻意远低于Binder共享buffer的提案，不是实测容量/延迟或Android保证。具体预算需契约校验与反例验证，Rust原有运行/transport/cleanup预算继续独立生效。

独立控制不能使用与run相同的阻塞串行队列；close回包先可为Closing，只有实际worker join/所需资源清理完成才Closed。Binder线程不执行长run/join；可由独立控制确认/状态回调完成。普通无.so构建仍编译且Service报告Unavailable，不回退到UI进程执行。

## 直接做 B 与返工判断

B 可直接作为第一实现片：用 Service worker复用私有Rust同步函数，外层IPC做异步受理/观察；并不要求先建A或另建Agentloop。若先把新runtime绑进UI Application，之后仍得移动native/store/admission所有权并补Binder状态机、序列化、死亡恢复和进程启动控制；因此**当前不应再做A**。纯state/安全文案/lease测试、Rust核心/FFI函数与生成源仍可复用，但A→B不是只改manifest就完成。此为源码/平台约束推论，不给未经测量的工期承诺。

B预计新增 owned UI范围：Service wrapper、AIDL/Parcelable、Application bind client、runtime panel/state与打包配置；既有页面/本地草稿/发送禁用语义保留。本片 Agent执行只走Service唯一gate。原Settings诊断创建fresh Catalog register/inspect、无Agent store，不迁移、不扩Binder诊断API，也不计为B执行证据。若未来确有资源冲突或父合同另选共享门，才评估诊断Service路由。Rustowner仍唯一写runtime/core，checker仍唯一写独立证据；本轮没有创建新writer。

## 后续证据边界（均未执行）

需在固定合同后TDD：Binder并发双submit只一native run；blocked run时cancel/close可达；callback慢/死与Activity重建不释放工作；bind失败/无Connected/NullBinding/BindingDied/异常/旧epoch隔离；回复丢失、服务死亡后按原身份只读核对、零自动重跑；队列/Parcel边界负例；server唯一store锁/ledger/原回执与真正物理registered-read链由独立Rust/JVMprobe证明。构建/source-only instrumentation不能证明真实跨进程Binder、Service生命周期、Android加载/后台/死亡行为；这些仍NOT_RUN。

**当前只交可审B方案。** 用户已明确选择B，不等待A批准、不以A绕行；本报告未执行实现，仍待root固定合同、非作者审查和Task activation。内部Catalog transport决策单列，可信内置插件的批准不替代它。


补充原owner对齐：native候选为快速 submit→ServiceReserved/Queued（非durable accepted；单槽无无限队列），worker在可信root锁/目录/admission index持久化后才发DurablyAdmitted(runId/task/attempt/admissionEpoch)。status/result读不可变快照；queued控制独立atomic，close必须核当前epoch；lookupOriginal按原requestId只读，不自动重放，notFound也不是零执行证明。最终名称/持久事务和边界由root合同冻结，本报告不另造第二套authority/ledger。

B验收必须具体证明：UI Compose/client调用图没有Agent构造、run_once或Agent store打开；这些只在Service worker路径。保留UI元数据library加载/声明检查本身不违反此边界。Application的每进程lazy对象不是全局Agent单例，Service不得借UIgetter意外构造另一个Agent。该调用路径检查与隔离进程运行测试仍未执行。
