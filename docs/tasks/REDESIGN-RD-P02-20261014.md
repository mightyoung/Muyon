# RD-P02 设备后置：临时 Rust 恢复接缝

状态：**实现和 host suite 完成，待固定 SHA 非作者审查与 root 集成**。
Android actual load **NOT_RUN**；M03 **blocked_contract**。设备后置只解除无设备
实验研发阻塞，不解除发布/设备验收门，也不证明原 M03 全出口通过。

分支 `task/device-deferred-rust-recovery-20261014`，worktree
`/workspace/Muyon-device-deferred-rust-recovery-20261014`，base
`b17ac548f7a8d2d6151cbdaf6af527722c67ee50`。单 writer
`/root/device_deferred_rust_recovery` 只写
`experiments/redesign/device-deferred/rust-recovery/` 和本文；root 唯一 develop 集成人。

已读 recovery-minimal-contract 和已有 d03a-contract 的 input-driven 接缝与边界说明。
新增 std-only publish=false crate，不读取 expected/caseID，不修改原 oracle、fixtures、
history、产品、根依赖、CI、apps 或 packages。临时类型由未来 M03 单源生成适配器替换，
不是第二套冻结 schema；seq 的 u64/字符串投影为实验内选择，不决定 wire 协议。

实际实现：完整 store/scope/stream/seq 去重，错域拒绝、相同身份异 payload 隔离；
有限事件队列缺口补拉使用提交边界，overflow 请求快照并停止增量；应用/提交 pair 分开，
重连回到内存已提交 pair 并允许未提交事件重放。epoch 只隔离展示，回执通过独立
合成 ledger 精确比对 intent/action/attempt/scope/parameters、receipt ID 与 effect；
保留既有效果，不因旧 epoch 抹回执。未知结果无执行器自动重派路径；可信合成新意图
独立登记，保留 old unknown，不派发任何业务。

真实 TDD：初始可编译 stub **12 assertion failures / 3 passed / exit101**，实现后
**15 passed / exit0**；重连 replay 补强先 **1 assertion failure / exit101**，修复后
完整 **19 passed / exit0**。三个语义逆变异分别在 named assertion exit101：移除完整域拒绝、
重连按 epoch 清除 receipt、登记 new intent 时删除 old unknown。finally 恢复原字节，
恢复后完整 **19 passed / exit0**。已有 D03a Python 完整实验回归 **24 passed / exit0**。
命令和可复现变异在 [README](../../experiments/redesign/device-deferred/rust-recovery/README.md)，
安全 hash/exit 摘要见 [evidence](../../experiments/redesign/device-deferred/rust-recovery/verification-evidence.json)；
原始日志仅 `/workspace/reports/device-deferred-rd-p02-20261014/`。root 执行产品候选组合 CI，
writer 未声称 Flutter 全库回归已跑。

待冻结/验收：真实 ledger 来源认证与摘要域、完整当前权限和用户指令来源、能力/CAS、
持久事务/故障恢复、snapshot/合法 advance proof、stream bootstrap、字节队列预算、
事件历史容量/持久去重策略、唯一 M03 DTO/wire/error/数字协议及正式 adapter。
此实验 commit 只在内存配对，不是 DB durable 证据；receipt 是合成账本记录而非真实
provider 回执；synthetic trust 是调用者接缝，不是签名或授权 token。公开状态字段只供
实验检查，不能直接暴露给不可信应用。无模型、网络业务、设备、安装、额外许可或 credentials。
原 29/77/19/72 fixture 状态保持 not_run，不升级整 scenario。
