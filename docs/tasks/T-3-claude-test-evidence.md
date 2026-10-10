# PR 14：Claude 测试证据意见核查

审查基线：`0f13ea46ee7295d9a05d5748e8b801303d9c7bf5`。
父任务确认真实 Claude 已完成五个局部审查；本记录只回应已收到的具体证据问题，
不把内部独审替称 Claude，也不根据概述推断生产缺陷。

## 已确认并处理

- 完成重放用例中相邻两个 `[1, 1]` 审计断言确实重复。保留一个，
  另一个换为实际登记 handler 调用次数为 1 的独立断言。
- 原取消、关闭及重放用例有状态/数据库/source 计数证据，但缺少直接 handler 计数。
  测试增加透明 `_ObservedRegistry`，只覆盖公开 register，原样转发全部登记参数，
  在调用原登记 handler 之前递增每个 toolId 的计数。
  计数边界位于 registrar 的 lifecycle await **之前**，因此即使内部 wrapper 提前拒绝，
  错误 dispatch 仍会被记录；不是用“没有 query/写库”间接代替没有 dispatch。
- 参数/预取消、首次异步重核、dispatch 二次重核、宿主撤权、binding/key 丢失
  路径明确断言 handler 计数为空，包含 cancellation 和 registry close。
- 四工具正常首次 invoke 分别断言 1；同进程已完成 replay 仍为 1；
  并发重复只执行 1 次；重开 host 后沿用同一个计数 map，回放及冲突拒绝仍为 1。
  正向用例证明计数器实际工作；没有重开后把它清零来掩盖重复执行。

所有已有收据、数据、授权和恢复断言保留，无生产代码或 bootstrap 变更。
新增断言尚待当前精确 SHA 的 Actions；不声称新增证据曾独立运行 RED。

## 附件用例疑问：可核实边界及最小加强

已核源码：保存回调先 await 显式 release gate，再调用真实附件保存；
观察 offered 时 handler 已进入接收队列。itemsSettled await 该 handler 及文件删除，
handler await 创建目录/写文件/rename。最后的文件存在断言仍保留。

原 `Future<void>.value()` 是一个 microtask 检查点，不应解释成对任意 Future
延迟的通用“未完成证明”。现加已完成 Future 的正向对照：在观察真实 queue
完成标志之前，同样注册完成回调并 await 对照，断言其标志为 true、真实 queue 为 false。
这验证该观察点能识别已完成的信号，而不是所有标志都因调度尚未发生而为 false。
最后真实 queue 完成及最终文件存在仍是独立证据，未被负向标志替代。
目前没有复现“当前 itemsSettled 提前完成而测试通过”；不据此概述修改生产顺序。

原 finally 释放 gate 并 drain；若主体断言与 drain 同时失败，Dart finally 的异常
可能替换主体异常。这是可核实的诊断边界，尚无具体失败复现。
现 finally 只同步释放 gate，drain 注册为 addTearDown，由测试框架单独处理清理错误，
不在主体失败传播路径用第二个 await 替换其异常，也不 catch/吞掉清理错误。
[test API](https://pub.dev/documentation/test/latest/test/addTearDown.html)
明确该回调先于 tearDown，故仍在 host.close 之前 drain；未改变宿主生命周期。
新断言和清理动态证据待当前精确 SHA CI；父任务已补回逐条详细意见。

本地没有 Flutter/Dart；使用既有全库 CI，不改代理设置、不提交原始日志，
摘要写提交说明及 PR；不合并 develop/main，不强推，不部署。

## 详细意见补充整改

- registry 独立拒绝：强制 callback 声称 metadata lane，而不调用 binding。
  schema/category/supportedScopes 均合法，分别仅改变 provider、module、第五 ID、
  workspace scope；精确 invalid_scope_resolution、callback 到达一次、fallback/SQL/handler 为零。
  非 global 的单项差分用 workspace：selectedObjects 的公开构造器要求返回原选择对象，
  因而还会触及 objects 非空检查，不能称单项违规。已有工具 scope 拒绝包含两种非 global。
- lane 参数伪造：精确 invalid_parameters，并直接断言 resolutionCalls/fallback 为零。
- 通过公开 foundation.notify 改变数据，已完成通知调用回放旧结果且额外 handler 为零；
  新 invocation 读到新通知且 handler 总计为二。原并发与重开 host 的额外零调用仍保留。
- B3：测试运行时提供带 revision/digest 的真实非空 ObjectRef，经实际 host resolver 和
  workspace binding，分别比较 workspace/selectedObjects 的 resolvedScope、identityDigest、
  parameterDigest 与无 callback 的旧 registry。global 原对照保留。此为本片必需范围；
  未扩写未变更审批协议的 expires/state/一次消耗可选对照。
- 附件新增受控回调故障：在 release 前挂 itemsSettled 错误观察，分别核对同一主体错误
  与保存错误，以及 body-failure→gate-released→save-failure、host 关闭前 drain。
  无 sleep、不吞保存错误；不宣称真实文件系统故障或 runner 两个未处理失败的报告方式。

以上仅新增测试证据，未经当前精确 SHA CI 前不算通过。已驳回的生产契约疑问不改代码。
父任务确认最终真实 Claude 窄审已完整结束，仅剩下述 B1 同宿主顺序验收缺口，非生产缺陷。

## 最终 Claude 窄审：B1 同宿主顺序验收

核对任务书 B1：必须在同一个 host 先读平台元数据，再走普通业务 global 解析。
原正常恢复控制与元数据隔离测试属于不同 setUp，不能共同证明该顺序。
现只在原正常恢复控制的业务 prepare 前 invoke 四个元数据工具，核对成功、
intent 仍 pending、workspace_module_bindings/notifications 全行快照不变，
fallback、模块 activation、scope source prepare/enumerate/resolve/knowledge、
receiptReads/commitImport 均为零，原 receipt 实例和数量保留。
随后原 complete、正确 project 绑定、receipt 未变、commitImport 为零、首次 activation 为一
以及重复正常解析不重复效果的断言全部保留。无生产或 bootstrap 修改。
本机仍无 Flutter/Dart；该最小补充待新固定提交的 push/PR 全套 Actions 动态验证，
不以先前 head 的成功替代，也不提交原始日志。
