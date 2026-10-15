# 下一片 Rust Agent 只读接线：用户决策摘要

**状态：待用户批准具体合同，未实施。** 本分支仅上传设计与独立复审。父级意见、合同 C0 与此前开发授权均不记作用户对本合同的批准；没有新产品代码或新运行时验收。

## 本次请决定什么

建议按 [完整合同](NEXT-AGENT-SLICE-PROPOSAL.md) 实施一个有限的一次性离线 Agent 读取：同一 Rust Agent 驱动调用现有注册读取、实时授权、物理 handler、原始回执、投影和最终模型载荷检查。输入仅 Rust 安装的合成数据与离线 endpoint；Kotlin 只显示真实终态和 opaque 回执身份，不返回业务正文。

- **为何进程内 Catalog、单 Rust worker：** Android 尚无插件 child 的打包、exec、SELinux 与清理证据。直接复用现有 Catalog 可避免先构造这一平台；Rust worker 在自己的线程构造、使用、销毁 Rc/RefCell 会话，无需把整个运行时改成 Send/Sync。控制信号独立送达，不能排在繁忙任务后。
- **相对已批准方案的变化：** PR84 完成的是声明注册诊断；本片会进入真正的 Agent 只读执行链。已有设计已提出私有 transport seam、进程内 Catalog 和 worker，本合同具体新增 one-shot FFI、受理/取消/关闭终态、可信实验目录与限额。不是新的 Agent 循环，不改 Rust 的业务或授权规则，不冻结公开 M03。
- **是否取消插件进程隔离：** 保留现有 Linux child 实现与回归，不自动回退到进程内。既有 child 负责 Catalog 元数据/票据处理，业务 handler 原本就在宿主。拟新增的 Android 路径中，Catalog 与宿主共享地址空间，**没有 child 崩溃隔离或 kill/reap 保证**；不把它称为沙箱。
- **是否只限可信内置插件：** 是。本片仅使用编入应用、由 Rust 安装的 Catalog/声明与可信读取 handler；不加载任意第三方插件代码，也不让 UI/模型提供代码、路径、声明或授权。未来不可信插件需要另行设计隔离。
- **崩溃、取消、未知结果：** 取消仅是请求，已记录读取不会回滚；关闭在 worker 真实结束并 join 前只能是 Closing。进程内 unwind 后废弃会话；若回执或任务事实无法确认则 OutcomeUnknown，不能改写成失败或已取消。进程死亡后不伪造终态；下次发现未完成证据须拒绝新运行并要求查核，无自动重放/删除。5秒是协作期限，不能强制终止卡住的文件系统调用。
- **明确验收与限制：** 测试先行取得可达语义 RED，再证明真实两次离线载荷、一次物理 handler、唯一原始回执、正确投影且私有 canary 不泄漏；覆盖撤权、持久化失败、独立取消、真实 join、预算与配额负例及有效逆变异。随后实际 Linux/JVM FFI、API24 双 ABI 编译链接、绑定与 APK 来源校验、独立代码复审和固定 SHA CI。Android ART/JNI、文件系统/生命周期、真机页面、真实模型、业务数据库与产品可用性仍未验收；无真机不阻止离线实施。

## 固定审查与来源

[独立合同复审](next-agent-contract-review.md)：SPEC PASS / QUALITY C0，无未关闭 Critical/Important；只审查方案可行性与合同一致性，未实施或运行新测试。复审固定输入的 SHA256 见 [输入清单](next-agent-contract-review-inputs.json)。上传的七份原文件均保持原字节。

源码基线 `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`，tree `bca71d8794edab6c63989f6cdfebbca32d059c03`。对应 PR84 合入后 CI [38740489239](https://github.com/mightyoung/Muyon/actions/runs/38740489239) success；这仅是现有基线证据，不是新合同运行证据。

原 owner 的固定源码盘点：[NativeSession/存储/线程](next-agent-native-feasibility.md)、[UI 生命周期](next-agent-ui-feasibility.md)、[Catalog/传输边界](next-agent-plugin-feasibility.md)、[验证与负例](next-agent-checker-feasibility.md)。这些报告中的 /tmp 路径是当时取证位置；本目录文件及上述固定源码 SHA 是本次仓库交付。早期选项与最终合同不同处，以完整合同为准。

原 native/UI/checker owner 与独立 reviewer 保留；root 负责组合和推送。用户批准具体合同后再固定实施计划、激活原 owner；当前无新实施 PR，不合入本 docs 分支到 develop/main。
