# RD-P05 实际 Rust 合成内核与双端 adapter 接线

用户2026-10-14 08:56「继续下一步」明确授权实际接线，不止计划。唯一集成人B；临时接口、Android NOT_RUN与M03 blocked_contract保留。
前置四路已合入f2a1e9a66303ca35cfdc18a5cbca2855b3156783；合后CI38536875390在启动本片时仍in_progress，失败须先诊断，未将其当完成。
旧只读预览draft扩为明确授权的Rust合成记录/回执/恢复链；不接真实用户库、授权、模型、设备。两端均通过本机进程桥接验证，非Android native或Electron运行验收。

## 所有权和独立分支

核119 worktrees与远端无core-port-lab/RD-P05占用；旧四路作者工作区保持干净，原设计/合同/fixtures不改。
- B：core-port-lab/CONTRACT.md、fixtures/、根组合tests/与本文；task/device-deferred-bridge-plan-20261014。
- device_deferred_rust_domain：core-port-lab/core/、RD-P05A任务文档；task/device-deferred-core-bridge-20261014。
- device_deferred_desktop_mock：core-port-lab/desktop-adapter/、RD-P05B任务文档；task/device-deferred-desktop-adapter-20261014。
- device_deferred_android_mock：core-port-lab/jvm-adapter/、RD-P05C任务文档；task/device-deferred-jvm-adapter-20261014。
各工作区/workspace/Muyon-device-deferred-<lane>-20261014，独立/tmp target/output，原始日志仓库外。

## 可实施接缝和判据

以[实验v0协议](../../experiments/redesign/device-deferred/core-port-lab/CONTRACT.md)为临时共享接缝，最终Rust serde定义为唯一业务/协议源。
领域name/candidate/CAS、稳定intent和合成receipt、RD-P02恢复均在Rust。两端只编码原raw/命令、校验传输绑定并呈现，不另写normalize/trim/CAS/提交计数。
同一原始命令/读取/name edit需实际调用core，得合成回执和两端状态；各用独立同seed进程，比较actual后才读oracle，不声称跨端同步。
错误、冲突、sameintent重复、sameintent异payload、drop-response后的unknown只读核对、旧epoch真回执/新投影及跨域为必要负例。
先真实RED，后实现/GREEN，至少必要语义变异检出；不得拿expected响应表驱动DUT。unknown lookup零新效果，invalid/冲突无半写，reply不能把预览当成功。
Root实际组合两端driver和Rust结果差分、固定SHA非作者review，候选CI终态通过后才唯一合入。作者可自己task分支正常push，不merge develop/main。
所有新增依赖仅已安装缓存离线使用；不增加安装、许可、安全权限、账户、付费、模型、设备或部署。M03/schema/真实授权/持久事务、真实双端生命周期与发布门均未冻结/未验收。
