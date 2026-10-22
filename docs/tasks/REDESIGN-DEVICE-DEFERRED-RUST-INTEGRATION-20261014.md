# RD-P01 / RD-P02 可逆 Rust 实验组合

唯一集成人 B。环境已实测 exec、Git远端与GitHub CI请求成功；SPIKE已合入1bbba1fa73ab95e66168bc75e8a2d07d4c6384b9，不重复合入。
本候选基于此精确develop，保留已授权设备后置计划；仅加入Rust领域/恢复实验、任务说明与脱敏复核摘要。
桌面/Android两个失败presenter分支不在本候选，作者分别保留真实RED修复并等待独立复核。

| 任务 | 固定原作者SHA | 非作者结论 | 独立实际验证 |
| --- | --- | --- | --- |
| RD-P01 | bb0c77cb83684e5e8e053465f463fe4d887d342c | [C0有界实验](device-deferred-20261014/reviews/rd-p01.md) | Rust12、2语义变异检出、恢复12、Dart32 paired=30一致+2rawguard差异 |
| RD-P02 | 44b54efd7ebcf2f3221f8509ad331ad98a42e779 | [C0有界实验](device-deferred-20261014/reviews/rd-p02.md) | Rust19、3语义变异各检出、恢复19 |

B在独立组合工作区实跑 Rust12+19、既有D01a33/D03a24均exit0；
[精确命令和脱敏日志hash](device-deferred-20261014/rust-combination-proof.json)不把历史fixture或oracle抬升为PASS。
原始日志只在仓库外。新源crate unpublished；read/edit为不可变候选，memory checkpoint与ledger为合成验证，均不具真实授权或生产持久效果。
四路所有权与待冻结项见[设备后置计划](REDESIGN-DEVICE-DEFERRED-PLAN-20261014.md)，原设计包checksum字节保留。

候选将推 review/device-deferred-rust-combination-20261014，等待精确SHA CI终态后才合入。
SPIKE合入后CI38530399778仍待终态；新候选失败不得绕过或改产品/测试掩盖。
main不改、不强推/删分支/部署；许可偏差保留，不再接受新条款。
Android actual load NOT_RUN，Compose/Electron真实运行缺口保留；M03 blocked_contract，设备/发布验收门不取消。
