# 下一片：真实 Rust Agent 注册只读链（待父级确认的私有合同）

2026-10-15。基线 develop `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`，tree `bca71d8794edab6c63989f6cdfebbca32d059c03`。本文是可审查方案，不是已实施、已验收或已冻结的公开 M03。源代码尚未修改。

## 目标与范围

一次实际调用沿现有 `Agent::run_with_runtime_ports → 同一 drive → RuntimePorts → NativeSession → 已注册 PhysicalReadHandler → 原始 NativeStore 回执 → Catalog accept_result → PurposeReview → ModelGateway 最终当前权检查/出站账本 → 第二轮实际编码载荷`。复用现有四套映射（含 seed0x7631 改名），Rust 私有实验目录内的真实合成记录，以及显式 offline-fixture endpoint。独立检查读取值确实进入正确的第二轮载荷，私有 canary 留在原始回执。

Kotlin 不接收业务值、raw/history/answer、授权快照、任意声明、模型响应脚本或用户输入；仅呈现实际 Rust 终态和 opaque 原回执身份/结果。通用聊天/模型/附件/业务执行保持未接线。本片证明离线合成数据上的真实 Agent 运行及 Android 编译打包，不称产品业务读取、自然语言 Agent 或 Android 运行验收完成。

## 已有方案与本片新增的约定

既定方向见已合入 ANDROID-RUST-OFFLINE-BRIDGE-20261015.md 的 Subsequent full native read slice：私有 ContractTransport、保留 Linux child、进程内 Catalog、同一驱动/授权/回执、Rust worker 独占 non-Send、独立取消、真实 close/drain。本片沿用这些方向。

三个选项：推荐原宿主增加进程内 adapter + Rust 单 worker；Android 打包 child 尚缺 exec/SELinux/生命周期证据，保留为 Linux 对照；全面 Send/Sync 或服务框架会扩大改动，后置。新增待定案仅为本片 one-shot FFI/控制终态、可信根与限额、明确离线合成数据/provider 范围及原宿主所有权扩展。业务投影 UI-display 规则、真实网络/凭据、产品 DB、任意插件隔离、自动恢复/重放不纳入。

## 传输与信任边界

NativeSession 内部小型 request/close seam，child 原路径保留；一个新 adapter 持有一个会话期 Catalog，复用现有有界 wire parser/serializer，request 与 reply roundtrip，64KiB 帧、深度/节点/数字语法限制、fatal-envelope 终止锁存和宿主 close 后拒绝保持。不能每次重建 Catalog，也不能裸调 handle 绕过 main 的 envelope/fatal 语义。wire command close 与宿主 transport.close 的差异须由配对测试钉住。

不改变 metadata/schema/授权/票据/原始回执规则，不在 Kotlin 实现它们；不降级 child 失败到进程内。进程内是受信编译代码，不承诺 child 崩溃隔离、kill/reap 或中断任意挂起代码。异常 unwind 后废弃该会话，不能继续使用部分变更 Catalog。

## 私有 FFI 候选（本片 protocol1；既有 diagnostic API 不变）

- `open_read_runtime({protocol, private_root}) -> ReadRuntime | SetupError`。仅 App bootstrap 从 context.filesDir.canonicalFile 取根；文本页面、模型均不能提供路径。root 是平台位置输入，不是授权证明。
- `run_once({protocol, request_id, variant}) -> ReadRunReport | AdmissionError`。ID 为内部 ASCII `[A-Za-z0-9_-]{1,64}`，不进入目录名；variant 仅四个 Rust 已安装合成场景。每 handle 只受理一次。
- `request_cancel(request_id) -> Requested | AlreadyTerminal | NotRunning | ControlError`；`close() -> Closing | Closed`。独立控制不排进繁忙工作队列，不借用忙碌 Rc、不等待其 mutex。Requested 仅请求已记录。
- Report 只含 protocol/request/typed variant echo/build identity、实际 task/attempt 成对可选身份、terminal、闭合 reason、原始 opaque receipt 可选身份及 receipt outcome。task/attempt 未建立或无法确认时不能编造；缺失身份不证明零执行。receipt outcome 为 `NotStarted | Unknown | RecordedSuccess | RecordedFailure`，Unknown 包含已知 running 或无法核实的状态。NotStarted 仅在 Rust 有确定证据时可用。shipping 不导出正文或计数；实测 handler 入口/计费 attempt 等只在非 shipping 证据面核对。
- Terminal 为 `Completed | Cancelled | Failed | BudgetExhausted | OutcomeUnknown`。闭合 reason 为 None/Cancelled/AuthorityDenied/PurposeDenied/ContractRejected/StorageFailure/ProviderFailure/DeadlineExceeded/BudgetExceeded/Interrupted/InternalFailure。无 raw reason、栈或路径。
- Setup/admission 错误使用独立类型，取 UnsupportedProtocol/InvalidRequestId/InvalidRoot/Busy/Closed/RecoveryRequired/InternalFailure 的适用子集；控制错误仅 InvalidRequestId/RequestMismatch/Closed/InternalFailure。实际受理后普通失败形成 report，不能只靠现有 native_host_refused 字符串判定。

优先级：未知原始结果/持久化不确定 => OutcomeUnknown，不能因 cancel/close 改写为 Failed/Cancelled；已记录成功的原始读取可与 Cancelled 运行终态同时存在，取消不回滚读取。只有实际驱动终态与回执/任务事实一致才 Completed。worker panic/join 失败且无法确认事实时保留 Unknown，不能凭丢失返回值推断未执行。

## 线程、受理、关闭与呈现

ReadRuntime 是 Send/Sync 的小控制壳，Rc/RefCell/session/trait objects 全在唯一 Rust worker 构造、使用、drop。同步 run_once 从 Kotlin 后台线程调用，持强控制/JoinHandle 所有权；join 在锁外执行，不能 unsafe Send/Sync 会话。

App 使用诊断与 Agent 共享的工作槽，页面/Activity/holder 重建共享同一 owner。native 另有进程级 runtime slot 防止直接 FFI 多运行；现有无状态诊断函数的 ABI/错误集不改成任务权限接口。取消/关闭控制不占该工作槽。

New→Running→Finished；close(New) 可在确认没有资源时 Closed；close(Running) 置永久禁新受理并请求取消，仅 Closing；实际 worker/drop/join 完成才 Closed、释放 runtime slot。Finished 不再受理第二个 run，cancel 为 AlreadyTerminal；Closed 控制报 Closed。New 的 cancel 为 NotRunning，不阻止未来 run；request mismatch 不影响其他任务。close 与 start 在同一短锁下线性化，UI 本地 Accepted 与 Rust 受理不同，NotRunning 不能释放 UI 槽。

handle cleaner/Drop 只发信号，不能在 cleaner 线程 join，也不能提前释放槽。运行调用/worker 保持资源强所有权至真实结束。页面 detach/timeout 仅停止呈现，迟到结果校验 lease/build/request 身份后才显示，无自动重试、补发、恢复。控制信号与 deadline 必须到达 host admission、provider poll/endpoint、handler 前、原始结果保留后、最终模型发送前。OS syscall 不返回时仍 Busy/Closing，不声称强制停止或固定 join 上界。

## 固定预算与私有存储候选

显式 Agent limits：steps2、model calls2、context32768、output16384、total65536（沿用现有计费单位，非真实 token）；host 独立 read admission budget1。第一轮只广告选中操作，读取后第二轮 tools 为空，dispatch 再拒第二次读取；正例实际2次 endpoint admissions/1次 handler 入口，失败路径不可猜数。协作 deadline5s，无任意文件 I/O 的硬终止保证。

Rust 在固定 namespace `native-agent-v1` 下初始化合成记录，host 生成目录身份、原子新建，request_id 不作路径。保留 UID/0700/0600、祖先 symlink 检查、独占锁、严格历史读取、atomic/fsync。不是 hostile same-UID 的 openat 沙箱证明；Android 文件系统行为仍未验收。

raw/bootstrap 编码/物理读取<=8KiB 是新增限制；native.db<=64KiB 为既有；task.db<=128KiB 是新 façade 路径的 encoded 限制（Core 全局1MiB primitive 不变）；outbound.db<=512KiB 仅序列化文件上限，单 payload/ledger body<=64KiB 不变。每个新限制须有真实 bounded read/prewrite 和有效负例，不截断冒充成功。

根上限8个 run 目录、总8MiB（所有 source/native/task/outbound/lock/temp/失败/残留均计入），扫描数有上限。跨控制器/进程在同一个 root lock 下扫描、预留、mkdir。**本稿建议每 active run 预留2MiB 事务高水位**，不能沿用未经证明的1MiB：旧/候选 outbound、task、native/temp 共存已可能超过1MiB。实现须给出文件布局的高水位推导；预留不足拒绝而非越限。原有记录不覆盖/删除/reset；未知项、symlink、非正常文件、未完成标记、容量不足进入 RecoveryRequired，无自动清理/重放。开始前持久化 pending 标记；终态交接须与真实 worker/锁释放和证据一致。root lock 使用有界非阻塞受理，控制信号不获取该文件锁；预留只能在 worker 真正 join 且剩余 footprint 已验证后释放。目录项数量与 temp 共存数量也必须有界；8目录是上限，不保证有容量运行8次。

## 测试先行、独立审查与所有权

原 native owner 独占 host crate 与 bridge crate 运行 surface；原 UI owner 独占现有 Compose/state/app/generated Android source；原 checker 独占新增 checks/workflow；root 文档/组合/推送。Core/Plugin 不默认转移所有权，本片优先无需改它们的公开规则；若必须改 Core，由 root 先恢复原 owner 或明确 carve-out。非作者 reviewer 固定源复审，无并发竞争 writer。

先固定场景与具名验收、编译可达的拒绝 stub，取得真实 Rust+生成 JVM 的语义 RED，再 GREEN。有效证明至少包含：

1. child/进程内配对的 wire/fatal/close/单 Catalog/ticket-generation/replay 负例，区分普通业务拒绝。
2. 四映射真实 physical read/原始 receipt/同一 drive/实际第二轮编码载荷，canary 不泄漏；非 shipping probe 与 shipping 库/绑定身份分离。
3. 缺权限、错误 scope/ref/revision、handler 前撤销、原始回执后/历史投影/最终发送撤销、purpose/ledger/persistence 失败，保留回执且不多发/多读。
4. 两轮/一次读取预算、第二轮工具拒绝、root 锁/限额、取消到达、实际 join/cleaner/drop、开始/关闭竞态、Unknown 优先级；用屏障而非 sleep 排序。
5. 基线 GREEN 后施加精确可编译逆变异，证明 final-authority、one-read、独立 cancel、提前释放、Unknown 改写等目标断言失败；保留日志但不入仓。
6. 原 Rust/metadata/UI 回归、真实 Linux JVM 新 FFI、fresh API24 双 ABI cross-link/ELF/import、绑定 bytecmp、APK 六库身份/16KiB/zipalign/lint/正常无原生输入构建；全部固定完整 source SHA 后审查与 CI，再草稿 PR/按既有门槛正常合入 develop。

不预报尚未执行的测试数量。Android ART/JNI/真实 fsync/lock/生命周期/进程死亡/页面与4/16KiB运行、真实模型数据、产品恢复、业务值 UI 展示均 NOT_RUN/未纳本片。无设备不妨碍离线开发与 host/JVM 验证；不能用编译证据改写为设备验收。

## 来源与下一步

同目录 next-agent-native-feasibility.md、next-agent-ui-feasibility.md（以最终 addendum 为准）、next-agent-plugin-feasibility.md、next-agent-checker-feasibility.md 含固定0ab路径行号和原 owner 确认。独立 contract review 随本稿固定版本复核。待父级确认此有限 one-shot/数据/provider/控制/存储合同后，由 root 固定仓库 spec/实施计划、激活原 owner；当前没有新产品代码或实施 PR。
