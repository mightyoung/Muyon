# LeaderB 最小 Service 生命周期交接

- Draft [PR93](https://github.com/mightyoung/Muyon/pull/93)，基于 PR92；唯一 LeaderB 集成，所有实现 writers、只读 CI monitor 均已停止。
- 验证源码 **a971b4f6742eed9aaf93f7ddb9e956278dd7f75c**；[CI39130933732](https://github.com/mightyoung/Muyon/actions/runs/39130933732) 四 job 全成功：精确 Rust6+1、双 API26 ABI、真实 binding 对比、APK/build/lint、唯一 API26 instrumentation。
- 实际链：测试变体 Application → 实际私有 AgentRuntimeService bootstrap/slot → 持有 ServiceHostLease → genuine generated withHost/UniFFI → Rust prepare/final_admit → 同一 Kotlin durable owner → Context 私有 muyon-admission-v1.sqlite。普通 debug/release UI 保持 SyntheticLab，没有生产 allow；没有真实网络或模型。
- 取消只把 held→expired，防重放 tombstone 保留；consumed 不退款。native handle 清理后才关 owner/释放 slot；不确定 native 构造保留到进程退出。
- API26 **模拟器**实际 :agent PID4592→4653；正常退役/重绑、Activity 重建、新进程零探针（phase3/probe_attempts0）通过。同一 admission aa6b36ed-2133-47bb-abee-8a825858ff88，consumed1/expired1/held0。固定持久 started 标记只抑制测试调度，不授予权限。
- 保留先前 f8d3bfea3606d187479ed6d16621b342eca74760 / CI39129510104 成功，以及 afbed6dc6639f72e3356c3b2156cd335c802685d / CI39130222418 Kotlin编译失败（设备未运行）。公开 SDK 缺失 O_DIRECTORY 的独立编译复现与修正证据已存。两次403分别属于原交接归档与本次失败新归档；旧归档未重试，本次新归档仅尝试一次后也未重试或换路。
- 尚缺：注入 setup/不确定 native 构造失败、native 未决结算时 onDestroy、在途崩溃/中断标记故障注入、reserve 后凭据撤销竞态的 Android 实证。已清理进程重建不等于这些场景；下一片优先固定合成 failure/retention 测试。
- 生产来源/profile/reviewer/总 token 与费用证明、真实 credential handle 身份/轮换与保留政策仍待确定，不从合成 fixture 推导授权。
- **PR86 与依赖组合 HOLD 持续**；PR90/8 Dart 不动、不跑。I04 旧 script task.db→HTTP→原状态重开及隐含 suite 均未执行；新测试仅清理后的新测试 App 自有 :agent、新 schema。无合并、部署、强推、删分支、付费或凭据读取/配置。

详细证据见 [RESULTS.md](RESULTS.md)、[INDEPENDENT-REVIEW.md](INDEPENDENT-REVIEW.md) 与各 run-id evidence；最后归档提交仅 docs，执行源码保持上述 SHA。
