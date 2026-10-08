# AUTH-1b B1 checkpoint 独立复核

固定实施 HEAD `2dc89ecc54dd2f8afabcb9d04c02a882b06924c2`，基线 `e473b9c205a215b440b56e465b5e357b21c8eff4`。独立核实代理在 `review/AUTH-1b-B1` 工作树亲读 production diff、正式任务书、B 最小计划和 ADR，并执行验证；不是此改动作者，不提交代码。默认指定 Sonnet 不在平台可调用模型列表，按 REVIEW.md 允许的非作者交叉核实执行。

结论：建议接纳 B1 checkpoint，无阻断/应改。不代表 B2/B3/C 或完整 AUTH-1b 完成。17 个改动文件在来源事实、真实范围证明、专项及文档范围内，未改权限 UI、历史迁移或既有测试。

| 核对项 | 结果 / 依据 |
| --- | --- |
| 单调事实、snapshot/模型不能清除 | 满足：host_authorization_facts union，foundation 创建同事务；普通 snapshot 不写事实 |
| 失败同步拒绝跨服务实例 | 满足：owner Expando 门闩在写排队前设置，失败不撤销 |
| 重开 / 同源 / previousAttempt 间接旧对话 | 满足：读取当前对话、previous 完整事实，global/workspace 包含稳定源和失败门闩；revision 不改变源身份 |
| 接纳前持久化 | 满足：dispatch、import、knowledge 在 handler/域库接纳前标记；失败接纳为零 |
| 真 DB / 文件 proof | 满足当前声明覆盖：total_changes/data_version、owner/producer、实际字节，非 catalog/cursor |
| queue / exclusive / closing / permission / mixed snapshot | 满足：owner pending、workspace 范围写版本、双轮跨源复核、ModuleHost admission/epoch |
| pending/failed revocation | 满足：即刻 null，失败撤销不能借 activation 恢复 |
| 保守边界 | 满足：普通任务 unknown；生产仅 prototype + knowledge producer；无自动签发接线 |
| 完整最终任务 | 部分：本复核未跑 full、变异、CI；B2/B3/C 和实机未完成 |

独立亲跑摘要：strict analyze `No issues found! (ran in 7.4s)`；facts/provenance/scope 三份专项 `00:03 +40: All tests passed!`；diff check 无输出。初次 native sqlite 下载失败不计测试运行；验证官方 dylib 完整 SHA 后仅复用该库缓存，没有复制构建或测试输出。

可选：host_scope_authority 的 `listSync(recursive: true)` 在检查 1024 entries 前先扫描完整目录；超大目录可能同步扫描较久。当前超限 null 正确，不阻塞。后续可改计数上限遍历，不能用截断清单冒充完整 proof。

作者另行验证（不冒充独立重跑）：61 项关键回归、宿主全量 +978 ~3、strict、6 facts +7 scope 行为变异杀死且逐字节恢复。固定 HEAD 与 lsremote 相等；精确提交 CI [37720821949](https://github.com/mightyoung/Muyon/actions/runs/37720821949) completed/success。原始 logs/probes 仅 /tmp。本分支未合 develop，父 leader 仍可按最终 B 整体交付另做独立集成复核。
