# 独立 Service Rust Agent：当前修订与决策摘要

**用户已决定：只接可信内置插件；不进行绕开。B（整个 Rust Agent 进入系统管理的独立 Service）是当前必做，A（UI 进程内 Agent）首片/过渡路线已取消。** 用户最新进一步授权“设计完成后开发”：具体设计完成、独立审查无阻断后直接测试先行实施，无A审批或泛化开工确认。此docs提交本身仅交付设计/计划，不包含运行时产品代码。

此前建议 A 是为了减少首次平台接线，并非 Android 不支持多进程；这项工程取舍已按用户决定撤销。官方支持 [android:process 独立 Service](https://developer.android.com/guide/topics/manifest/service-element)。不要求先完成 A 或批准旧 A 文档。

## 本次如何做

UI 只经有界 Binder/AIDL 发请求、查状态和取消；同一 Rust Agent 内核、实时授权、注册 handler、原始回执、投影与最终载荷检查全部在 `:agent` 的 Rust worker 内。Service 承担独立进程适配，不把现有 Linux pipes/exec 不加验证地搬到 Android。

| 方案 | 边界与当前地位 |
| --- | --- |
| A：UI 内 worker | 只有线程分离，UI 与 Agent 共担 native 进程故障；已取消 |
| B：普通独立 Service | UI 与整个 Agent 地址空间/故障域分离；同应用 UID，**不是文件/凭据权限沙箱**；当前必做 |
| C：isolatedProcess | 额外 isolated UID、无自身权限；现 app 私有 store 需要 FD/存储/授权 broker，当前不纳入 |

[完整可实施修订](ANDROID-AGENT-SERVICE-SLICE.md) 明确：

- **通信与准入：** 短 submit 返回 Queued 不表示已执行；Rust 持久 request→run 身份后才能 DurablyAdmitted。单活动运行、零等待运行队列，4KiB请求/8KiB快照为拟实现上限；Binder缓冲不是每调用1MB额度。
- **线程与控制：** Rc 会话只在 Service 的唯一 Rust worker 构造/运行/drop；Binder线程不执行 Agent 或文件I/O。取消走独立客户端和服务端控制通道；真实 worker/drop/join 前仅 Closing，不以 timeout 假称停止。
- **死亡与回执：** 失联、丢回复、持久化不确定保留 Unknown；已记录读取不会因取消被回滚。重连先 current/lookup 原始 request/run；UI进程死亡丢ID也可查到唯一在途记录，不补发 submit，不恢复旧授权或自动重放。
- **存储与生命周期：** Service 是唯一运行存储 owner；私有 RootLease、原始单回执、严格恢复与有界配额保留。先做可见UI发起的有限 bound 工作；不暗加后台常驻、FGS权限、真实模型或凭据。无真机不改回A，可继续离线Rust/JVM与AIDL/编译打包开发。
- **明确验收：** 实际同一驱动/物理读取/原始回执/两轮载荷；撤权、重复准入、独立取消、旧epoch、死亡unknown及不重派负例/有效逆变异；API24双ABI与APK来源验证。真正不同PID、同UID、Binder调度、Service死亡UI存活、Android存储/生命周期须另外实际设备执行，当前 NOT_RUN。不能以host/JVM或编译替代。

## 不混淆两层边界

现有 Linux child 仅负责 **Catalog元数据/票据**，业务 handler 原本就在 host。B 是把整个 Agent/host/handler/store 从 UI 移到独立 Service；不等于只把 Catalog 单独放一个进程。

内部Catalog后端在本次设计中明确选定：按最新设计后开发授权，本片明确选定可信 persistent Catalog 与 Agent 同在 `:agent`，保留 Linux child 对照；这会少掉 Catalog 相对host的 child 地址空间边界，但整个Agent仍在独立Android Service。该取舍已显式纳入合同；后续如要求Catalog自身也独立，则另行设计contract Service，不使用未经支持验证的exec。**没有先做A的路线。**

## 依据、审查与状态

源码固定 `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`；产品代码未变。原owner并行只读报告：[NativeSession与执行链](process-options-native.md)、[Service/UI及Binder](process-options-ui.md)、[隔离与权限](process-options-security.md)、[验证矩阵](process-options-checker.md)。其中早期候选与最终修订不同处，以完整修订为准。

[独立合同复审](process-service-contract-review.md)与[固定输入哈希](process-service-contract-review-inputs.json)同目录交付；[实施计划](B-SERVICE-IMPLEMENTATION-PLAN.md)、[精确ABI](B-SERVICE-ABI.md)、[ABI复审](process-service-abi-review.md)及[checker计划](B-SERVICE-CHECKS-PLAN.md)约束原owner测试先行。官方资料证明平台机制可用，不是当前APK已运行成功。原有 PR84 声明诊断可留UI且不作为B执行证据。此前 [c0e20c5f文档](https://github.com/mightyoung/Muyon/tree/c0e20c5f1dc68bbd1bae6404586be96bac138d1e/docs/design/android-agent-read-20261015) 为已被新方向替代的历史方案，不等待A审批。实施授权来源是用户最新“设计完成后开发”，父级意见/审查C0不冒充用户发言；具体合同和ABI无阻断后，root直接协调原owner实施。新后台常驻/权限/真实模型凭据或额外资源仍先报告。
