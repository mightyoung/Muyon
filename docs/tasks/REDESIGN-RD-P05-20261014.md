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

## 固定交付与组合验证（本报告提交时）

前置f2a合后CI38536875390已于2026-10-14 09:02:00Z completed/success，不重复触发。09:14断连提示后原writer安全暂停并保留现场；收到明确恢复后继续原三分支，无替代writer。

| lane | 固定源码SHA（远端回读一致） | B组合树实际重跑 |
|---|---|---|
| Rust core | 37848f123d2a51f7fb0c7af2b28837bd6ba66a5f | 独立target build及24项进程测试通过 |
| Node/Desktop adapter | 28a13656732e8b5b88852404da17e8c8d401d1cf | 26项通过，无安装 |
| Kotlin/JVM adapter | f639f3814c4e9aa735efb39c575b8c89bbe8f716 | 独立输出6 codec+5 projection+12实际进程+7回归，共30项通过 |

三个input-only场景分别13/8/8回复，由Rust直跑、Node进程和独立编译JVM driver实际生成；比较器运行后29条回复完全相等，并断言重复intent不二写、异payload冲突、unknown只读核对、旧回执不回滚新投影。端测试另核真实展示状态，未以回复相等替代UI断言。Rust端用B独立build；Node/JVM端用固定可信路径的作者binary，SHA256 eb697e57d445f2b437bd16877177be56a6c5d6b8c9dc5ee9f2f205597e8efa40，对应已独立复验的相同Rust源码，未替换作者binary。

非作者复审检出并交原作者修复：Node缺seed静默baseline；JVM失绑定回执未入账却显示committed、decoder接受矛盾kind/payload。保留真实RED与修后GREEN，未弱化断言。JVM旧测试stderr曾硬编码共享临时目录，B首次独立输出测试可能覆盖该临时诊断文件；作者源码及外部原始报告未动。修后stderr随独立harness/driver输出目录隔离。

核实报告位于仓库外`/workspace/reports/rd-p05{a,b,c}-independent-20261014/`及`rd-p05-combination-independent-20261014/`；核心5项独立逆变异、Node4项逆变异及JVM原3项/修复3项逆变异均以编译成功后的预期断言失败检出，恢复源码与固定blobs相等。组合代码head280cc2e335b11096c7fc6a479a5fe1f5d1e7c59a广审为限定实验C0；2251个前置文件全部原blob不变，作者子树与上述SHA相等。

B实际命令：`python3 experiments/redesign/device-deferred/core-port-lab/tests/compare_actual.py --binary /tmp/rd-p05-root-target/debug/rd-p05-core --jvm-jar /tmp/rd-p05-root-fixed-driver-output/rd-p05-driver.jar --java /tmp/muyon-spike01-toolchain/jdk/jdk-17.0.20.1+1/bin/java --output /workspace/reports/rd-p05-combination-20261014/fixed-actual`。JVM脚本使用`RD_P05_OUTPUT`独立目录。原始日志、输出jar/binary与实际observations均不入仓库。

本报告只登记候选前证据；新候选CI及合入尚待终态，不能由旧CI或本地测试代替。现有GitHub CI覆盖原Flutter/Laya宿主回归，实验Rust/Node/JVM进程测试由上述独立本地验证覆盖，未声称现有CI自动运行它们。Android actual load/Compose/Electron runtime仍NOT_RUN，M03 blocked_contract；真实数据库/授权/跨进程耐久恢复/发布验收未覆盖。
