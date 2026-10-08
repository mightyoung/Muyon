# AUTH-1b 一页总结

## 已交付的授权范围

- A：历史数据库保留；迁移11原样注册，12添加授权关联和独立审查记录；授权消费、审计、一次性审批在同一事务中完成。旧库升级、回滚、最后一次并发、撤销、期限、范围和重放均有行为回归。
- B：宿主事实和输入来源接线，粗范围身份与逐对象revision分离；持久taint及恢复继承；本地审查链只能收紧，Noop不能冒充已审查。
- Production/automatic：真实宿主工具调用使用这些事实和审批；实际加载的原生/JSON工具目录保留来源事实；人工和自动来源明确，不伪造grantId。
- C1：standard/readOnly/custom类别策略，可信宿主更新入口和版本绑定；候选、确认、审批、执行与网关复核策略变化。
- C2：真实主模型、摘要和兼容重发绑定完整profile/endpoint身份、实际wire及独立review；规则授权原子消费；恢复只信当前真实配置；同DB owner撤销取消在途流和等待凭据读取。

A/B/production/automatic此前已合develop。C1/C2源7c1dd63000b81043f0f51774175cf9ef7bc7e850已获leader批准、独立审查通过、精确任务CI成功；本次集成的宿主全量1136通过/3既有跳过。用户已接受本次限定截图基线例外，批准集成检查点ffe6be31发布；[验证备忘录](VERIFICATION-MEMO.md)记录46项完整对照和后续回归。Mac全量仍失败，不记为全绿。

## 保持的不变量

完整可信endpoint身份不按origin合并；对象revision不代替粗范围身份。每次实际wire先审查/入账再发送；blocked只有review记录，不伪装transport状态。grant/audit/approval或ledger失败全部事务回滚，提交后发送失败不自动退次数。local mode_auto可以没有grantId，但来源必须真实。撤销拒新使用并取消在途，已经发送的字节无法撤回。历史数据不清库。

## 可用性证据与剩余工作

真实Host/SQLite/Inquiry Store完成数量10→12，有成功receipt和引用；Research实际导入并检索文档、形成引用，纯读流程无需逐轮人工卡。模型答复来自loopback脚本，不代表真实模型理解能力。

剩余：按[验证备忘录](VERIFICATION-MEMO.md)回归并排查已有Inquiry截图失败，本次精确postmergeCI37792414130已成功；UI/profile设置和授权入口由UI任务接线；其他模块业务闭环、真实云模型和实机验证另行任务化。共享owner撤销不保证跨独立连接/进程；终态map清理等原WATCH保留。本轮不继续扩大安全范围，不删除远端任务分支，不碰main/release。

C1/C2已发布到develop00dbd6cf722ddd4b5f7e8c65ec378ee4150fada9，发布CI精确成功；后续可用性改造任务见[下一批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)，本摘要不声称UI/三端已完成。
