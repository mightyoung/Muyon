# RD-P03 / RD-P04 双端临时界面与 mock 组合

唯一集成人 B；本候选依赖已审[RD-P01/02 Rust组合](REDESIGN-DEVICE-DEFERRED-RUST-INTEGRATION-20261014.md)
`1f10e8a006b066b305b96abb4c33aa951fb07872`，只加入双端实验、任务文档与脱敏复审摘要，不接产品权限或数据库。
原失败分支已先保留真实RED再修；不会以只通过原作者弱测试宣称缺口闭合。

| 路线 | 当前固定作者SHA | 非作者结论 | 真实实测 |
| --- | --- | --- | --- |
| RD-P03桌面 | e80d5077d4d41366336d59fd1b143ed5af04f55a | [有界C0](device-deferred-20261014/reviews/rd-p03.md) | fresh Node27、独立补测7、三mutants assertion exit1并恢复 |
| RD-P04 Android mock | 97274f9ff8c4960e5b5ccede4673d2863ae20500 | [有界C0，R1/R2闭合](device-deferred-20261014/reviews/rd-p04.md) | fresh JVM38、原回执/快照负probe现在通过、三mutants assertion exit1并恢复 |

桌面unknown经load/普通edit不能新造提交意图；原lookup保留原command，非法ID/版本/计划回执不成功。
显式isolateUnresolved临时用户意图另存原unknown，不当生产用户身份或授权证明。
Android Command绑定expected/result mock counter关系；迟到真实r5回执保留原账本且不能覆盖r8当前投影/草稿，展示generation与效果账本分轴。
mock数值版本布局是暂行接缝，不冻结M03表示或opaque产品版本排序。

B在新组合工作区实跑Node27和JVM38均exit0；Rust及原合同依赖沿精确1f10e8a已核字节复用，不冒称本轮重跑。
[脱敏组合proof](device-deferred-20261014/ui-combination-proof.json)记录作用范围与原始日志hash；原始新日志均在仓库外。
桌面有限Chromium DOM/字体烟测为作者实测，非作者读其证据、不重复启动；Electron runtime NOT_RUN。
Compose编译/渲染、TalkBack/旋转/进程死亡与Android actual load NOT_RUN，M03 blocked_contract。
四路mock/纯领域/内存恢复不具生产授权、事务、持久回执、可信桥接能力；设备/发布门保留。

本候选将推review/device-deferred-ui-combination-20261014，精确SHA CI与上游Rust候选门禁均通过后才可合入。
任何失败暂缓，不改断言/产品去掩盖；不修改main、不强推/删分支/部署，不新增许可/安装/账号/付费。
设备后置与各writer范围仍按[原实施补充计划](REDESIGN-DEVICE-DEFERRED-PLAN-20261014.md)，原设计checksum与历史fixture不升级。
