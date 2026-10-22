# LeaderB Service failure lifecycle 交接

- Draft [PR94](https://github.com/mightyoung/Muyon/pull/94)，堆叠 PR93；未合 main/develop。验证完整源 **c1f57af047671ec3c3f2b2d73d20ac6ece4bcc32**；最后归档仅 docs。
- [CI39141540456](https://github.com/mightyoung/Muyon/actions/runs/39141540456) 终态 SUCCESS，11/11 job：genuine binding、双 API26 ABI、8 个固定 APK build/lint 和各自点名 API26 instrumentation 均通过。
- 实际 Application→private Service→genuine UniFFI/Rust→durable owner SQLite 链覆盖 setup、setup+owner cleanup 失败、构造后发布不确定、owner cleanup、native close 前失败、native 在途/onDestroy、onReady 失败和构造/onDestroy。修复平台线程 native retire 阻塞、启动退役与 executor 关闭竞态、onReady 清理及失败 close 保留。最终独立双审，无剩余源码阻断。
- 保留 [首轮 CI39140979633 FAILURE](https://github.com/mightyoung/Muyon/actions/runs/39140979633)，源 **489178b0c5c80979156ad4ee0b2eba8955465191**：binding/ABI 通过，7 APK 因 Gradle DSL 编译错误失败，设备全部 NOT_RUN；未重跑或取消。
- **新权限阻断**：仅尝试一次读取 CI39141540456/job117717160270 直接日志，重定向存储 HTTP403，已停止，无重试/归档/别路下载。run/jobs/steps 元数据已归档；原始日志/fixture JSON 未归档，不编造 PID/receipt。见 LOG-READ-BLOCKED.json 与 RESULTS.md。
- 故障边界明确：Unknown 在 genuine 构造成功后抛错；Native 在 native.close 前抛错；Owner 在 durable.close 前抛错。实际 foreign 构造/析构异常、SQLite.close 失败仍 NOT_RUN。
- 真实使用仍缺生产 source/profile/reviewer/payload authority、完整 token/费用证明、真实 credential handle 身份/撤销/轮换及保留政策、在途崩溃/标记故障、真实设备与单独授权的 provider/model 验收。普通 UI 仍 SyntheticLab；合成通过不授予生产权限。
- PR86/依赖 I04 HOLD 保留。PR90/Dart8/UI 未动未跑；被拒旧 task.db→HTTP→原状态重开及隐含 suite 均未执行/重试/改写/换路。旧403 archive 从未访问。无凭据、付费、真实模型请求、部署、强推、删分支或合并。
- 所有实现/审查 writers 已停止；两次专项 CI 均已终态，monitor 已退出。当前仅原始日志访问阻断；交付和精确合成验收已完成。详见 RESULTS.md、两份独立审查与分 run 证据。
