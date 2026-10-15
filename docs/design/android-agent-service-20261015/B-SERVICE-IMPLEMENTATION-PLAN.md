# B 独立 Service Rust Agent：实施计划与激活门槛

2026-10-15。用户已授权“设计完成后开发”。B是当前必做，A首片/过渡取消；可信Catalog在:agent内作为明确设计选定，Linuxchild原路径保留。无需A审批或泛化开工确认。原owner并行、root唯一组合/推送/正常集成develop；main不动，无强推/删除/部署。

基线0ab2c4f667681b9aacb017f8cd2eea6f576cf78e；最终合同ANDROID-AGENT-SERVICE-SLICE.md（SHA2565be6a11739f3d48153c18631ebbe9473bff7e2aa9adb7f44cc5a3ca5f8c58e18）、ABI B-SERVICE-ABI.md（SHA256b361f966ff15f92de762b47fbcfada2619bcfe086e2d7aa9bafd5aa1cd63aea4）与独立C0输入哈希随目录固定。早期author notes所引3c5 ABI仅历史对齐，最终以本版ABI为准。root先推docs提交，所有作者从其完整SHA建立新分支/工作区；保留旧a02/324/352与全部历史。实际docs SHA写入外部执行账本，避免文档提交自引用。

## 所有权

| 原owner | 独占文件 | 交付 |
| --- | --- | --- |
| rust_native_host_owner | rust-agent-host-lab/core（host语义/transport/worker/index/tests）、android-rust-bridge-lab/core（薄UniFFI/lock/config必要增量）；自有任务doc | 同一Agent链、SendSync控制壳、真实join/终态、精确源码测试及可复现生成源 |
| workbuddy_android_ui_owner | android-compose-lab/state、app（Service/AIDL/proxy/生成Android bindings/manifest/Gradle必要增量）；自有任务doc | Agent仅Service构造/运行、无UIAgent、B客户端状态、界限明确的实验面板 |
| host_checks_owner | android-rust-bridge-lab/checks 与既有 android-rust-bridge.yml；必要host checks/cases.json + test_full.py；自有任务doc | 固定输入、真实Rust/JVM RED/GREEN、独立原始物理/回执/实际载荷oracle、精确逆变异、Androidbuild/package gate |
| root + 原非作者reviewer | 本目录spec/plan/整合账本；只读审查固定作者SHA | 不在leader主线程运行/通读产品代码；非作者重跑/边界核实；root import/push/draft/最终合入 |

checker窄carve-out明确：rust-agent-host-lab/checks/cases.json + test_full.py 只添加源码固定的新service/transport group，保持native_read原25及旧94/21/44/13/17+3独立严格。现full.py通用parser无需改，native3无固定全文件hash allowlist且3anchor各唯一，无变异runner修改依据；full.sh仅在实际host身份机制需要时再报告，bridge BuildID不应强加plainhost。预检 B-SERVICE-CHECKS-PREFLIGHT.md / B-SERVICE-NATIVE3-PREFLIGHT.json 外置保留。

Core/Plugin规则不转移；默认本片无需改它们。如确实必需，先由root明确原owner/file carve-out。不得交叉修改他人目录、在作者分支修复失败或用其他任务修正掩盖结果。

## 批次1：冻结ABI、源码目标与可编译拒绝checkpoint

Native：先完成ABI review的剩余字段/状态一致性，薄控制器/DTO和具名测试；主目标 service_controller_executes_registered_read 及 reach/assert 文本由实际第一版测试冻结。拒绝实现必须可编译并确实进入新controller请求路径，初次RED不冒称已经进入Agent dispatch。host transport/控制组合后真正驱动路径另有明确GREEN reach/oracle。

UI：根据相同ABI先做纯state/codec/remote-port状态测试，覆盖epoch/revision/观察key非回退、无自动submit、可见lease/release、初始化迟到/close、独立control和Busy。先有实际可编译拒绝行为RED，再实现state。mock测试仅证明客户端状态，不当Rust/Binder证据。已有67state检查保留独立组。Service/生成adapter待真实生成源对齐，不能手写假binding。

Checker：在读取新DUT实现前按合同固定场景输入/预期、具名目标、源码blob hash、reach/断言和实际过滤数量；复用现有linux_gate/ffi_evidence/classifier，新增service-rust-red/service-jvm-red模式，原metadata RED/full模式不变。不得用输出回填golden或预测新测试计数。

root将fixed native拒绝+checker checkpoint组合到独立RED refs，实际构建默认Linux库、真实生成JVM绑定、加载并调用constructor/connect/visibility/start/settle/status。Rust/JVM两个required语义RED均须被非作者从完整普通日志确认，构建/load/timeout/skip不是RED。required目标仍非零退出；保留原失败refs/logs，不绿洗。实际checkpoint可并行推进UI自己的state TDD，但native GREEN等待两项真实RED。

## 批次2：最小GREEN实现及原owner对接

Native小提交序列：

1. private ContractTransport与持久Catalog，严格wire/fatal/close/ticket/generation负例；现child构造/语义与Linux tests不变。
2. service_types/controller/store/worker：sameRootLease、准入索引/去重/当前查询/epoch+revision、max2client/显式visibility与release、独立cancel/gone/close、startupgeneration、唯一worker+唯一后台Rustsettlement waiter；明确受理前已结清拒绝与不确定结果，不能伪造run/task身份。
3. 通过同一Agent::drive、现有注册physicalhandler/原始NativeStore/目的审查/ModelGateway实际两轮载荷；四映射+seed改名、2calls/1read、最终授权/ledger/receipt屏障原样保留。不能另写Agentloop、硬编码成功结果或让provider golden决定执行证据。
4. bridge薄UniFFI导出与普通库/独立test-only probe隔离；保持metadata API签名/字段/校验值。正常Terminal和Closed由Rust在真正join/drop后发布；Kotlin只转发。fresh Android/JVM源/config/lock/lib/hashes外部交接。

UI小提交序列：

1. pure state/observation-key/端口codec GREEN与有效负例，独立control执行通道不被status/submit队列卡住。
2. actual Service/AIDL/parcelables与Binder liveness映射；opaque client_key不由UI输入；Service-only client_gone/await_settled不出AIDL。初始化在后台，native构造迟到时close/drain，主线程不I/O/join；每进程Application不当跨进程单例。
3. 仅Service创建Rustcontroller/运行/store；UIconnect/current/lookup先核对再由显式新操作submit，lost Binder reply/未知/已确认终态不互相篡改。保留PR84无状态metadata原入口，非B执行证据。
4. UI owner复制native实际生成的Android Kotlin（保留generated/MPL标记），提交真实ServiceAdapter/设置内独立离线实验面板；通用聊天/模型/附件/业务Send仍未接线。新Object cleaner/min24/JNA/lint须重新编译验证，不继承旧stateless兼容结论，不手改生成文件或抬API floor。

Checker序列按 B-SERVICE-CHECKS-PLAN.md 执行：真实shipping controller JVM GREEN+私有物理记录/原始回执/两次实际载荷oracle，targeted source-anchored逆变异；独立观察probe不得换更宽policy/driver，shipping不导出正文/计数。source/default/probe/tool artifacts各自绑定完整SHA及hash。

## 批次3：固定源独立审查、逆变异与组合CI

各owner到小checkpoint报告完整SHA/clean状态/文件归属/reach与执行命令摘要，root检查metadata只导入授权路径。原非作者reviewer分别核host/FFI/lifecycle、UIstate/Service/AIDL、checker/workflow。Important/阻断回原owner修正并复验；root不在主线程改产品源。

必要真实负例：fatal wire/closed/ticket replay；重复key/改variant/source冲突；two client/零queue；visible/release/gone/start/close竞态；sameepoch晚旧快照/跨epoch旧控制；请求ID丢失只读current；读前撤权、raw后撤权/持久化失败/历史投影与最终发送；Unknown优先级；RootLease/配额/未知残留；同一个run真实join后Terminal/Closed才发布。使用屏障，不以sleep估时。

编译可达baseline GREEN后作少量精确逆变异：去重/重连误submit、旧epoch或revision、独立取消/提前Closed、one-read或最终权、Unknown误分类。每个变异需实际编译、命中指定reached断言和值差；SURVIVED/INVALID诚实报告，setup/timeout不能称KILLED。旧17/native3仍是回归而非新guard证据。

root创建draft PR并在最终固定组合head运行：完整bridge Linux/native/JVM/newinverse、API24 arm64/x86_64 freshlink/ELF/import/metadata+service binding compare、AIDL/manifest/Compose lint/app+testAPK六nativehash/STORED16KiB/zipalign；普通无native Compose；原core/plugin/host/physical/checker/逆变异回归；全仓CI。源component trees与作者fixedSHA严格一致，PR merge checkout若不同SHA则核相同tree。全mandatory终态success +独立C0后root才正常develop合入并核完整parents/tree/main/sourcebranches，跟完postmergeCI。

## 设备与资源限制

Android真实不同PID/同UID、Binder调度、Servicekill/UI存活、liveness/进程死亡/存储锁fsync/rebind等是单独实际设备证据门，当前NOT_RUN且本计划不安装/运行emulator/device。host/JVM、静态manifest、APK assembly不能冒称该门通过；无真机不阻止上述离线开发/审查/编译打包，产品进程运行验收继续明确保留。

只用现有批准的临时CI工具栈与pins；不装本地工具链/SDK/NDK/许可证，不扩大凭据/网络/真实模型/后台FGS/常驻/计费资源，不导出MUYON_EVAL_REAL。不清理旧worktree/branch/cache来腾空间；本地/tmp剩余约700MiB，只做可控小测试/复用既有target，实际较大编译/ABI/Gradle交正常remoteCI。raw日志/binary外置，代码只提交源/固定生成源与必要docs，root唯一pusher。新范围先报告。
