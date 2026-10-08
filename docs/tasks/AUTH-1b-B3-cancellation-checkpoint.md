# AUTH-1b B3 取消与 native 工具提议 checkpoint

分支 `task/auth-1b-b3` 从 `6c05bdf` 创建，并以普通 merge `44e30d8` 吸收已审 B12 `d4ece4a`。原 auth-1b-tools 及备份取消 WIP 保留；本分支不合 develop。B12 集成另在独立工作树，不包含此 checkpoint。

## 当前交付与限界

这是 optional/manual consumer 的修复：PersonalAgent 仍须显式注入 toolReviewer 才走本地 tool review；bootstrap 尚未注入，完整生产消费者尚待后续。review block 零效应／审批，Noop reviewed=false、未知事实走原人工卡，人工确认绑定实际 review。不能将可注入接口或本轮 fixture 成功称为自动 grant 路径完成：没有可信输入 clean proof、生产 grantContext／GrantStore 接线、自动 sign／有序混合执行，仍未完成真正 automatic grant path。C 主模型／摘要授权与在途 model cancellation 保持独立；本轮 agent_model_turn 仅解码 native 工具的目的地提议，未改变模型请求 gate。

## 行为修复

真实脚本模型发出 read/send 混合步骤，在 post-read reviewer barrier 内调用公开 PersonalAgent.cancel，确认真实 active-tool 信号分支把 stage 写成 cancelling。旧代码在 review 返回后仍发布等待确认卡；修复在异步边界复核取消，并以最终 owner 事务 canCommit fence 禁止发布卡。审查记录 INSERT 失败路径也先复核取消，避免把已请求取消改写为 failed。两种路径最后 cancelled、效应 handler=0、approval=0；不承诺撤回已发送字节。

native ToolCallComplete.arguments 的 destination 以前未进入 Planned，带完整目的地的真实调度在 prepare 前失败。现在传递该仍不可信的提议，schema、宿主 preflight 与完整 actual intent 继续核验，不接受 grantId/clean/endpointIdentity 声明作权限。

## 作者验证

有效 RED：隔离 driver waitingConfirmation vs cancelled；公开 cancel API 的同窗口；review INSERT 失败后 failed vs cancelled；native 调用已带 destination 但实际任务提前 failed。早期缺 dart:async 的编译失败及诊断用 timeout 不计 RED。

52 项取消／本地阻断／人工确认／批次失败／事件回归通过。独立 /tmp 副本三项行为变异均失败且编译有效：移除取消 fence 组合、移除 review 失败出口取消复核、丢 native destination；逐字节恢复，strict `No issues found! (ran in 7.0s)`。恢复后全量 `+1017 ~3: All tests passed!`；三份恢复源码/回归与提交前分支逐字节一致。原始 logs/driver 只在 /tmp。固定提交独立复审与 exact-head CI 仍是接纳门禁，不能将作者绿灯冒称独立通过。
