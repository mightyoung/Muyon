# CR18 I1：旧规划的打开入口拥有关系

固定原候选 `2456eb138b6a39f9f25ecc3baa6e5e50e38d9a68` 保留；两份 CR18 独审的相同问题合并记作一个 I1。本文记录集成人的独立动态复现和修补，不替代原两位审查者的修复复审。

RED 提交 `ac74890ec52605d5fb0c1d7f438b0fcfcbd18cb5`：原产品上三个测试自然退出，0 passed / 3 failed / 0 skipped，5.488 秒，exit 1，未触发外部进程保护。B2 source 未释放时 B1 request 已非 current，旧 validated 仍被 getter 返回，新 session 显示 B1 并将测试标记写入真实 SQLite，revision 3。另以 Completer 阻塞 A.close 的 save，B2 在释放 close 前完成；排队的同 surface B1 widget 被晚构造 session 重新授权，显示并保存 revision 1。close barrier 包装真实 HostUiWorkspaceStore.save 的入口，释放后仍执行原 SQLite/CAS，不伪造保存结果。

早期编译/测试夹具和清理未完成的外部保护退出均未计作行为 RED；最终使用已有 workspaceOperation 按完成条件排空真实与假时钟。没有延长原测试超时、加入 sleep 或删减原断言。模型请求与 tool history 始终为零；本证据证明旧内容显示及持久化越界，没有证明业务执行绕过，生产打开入口仍未传 businessActions。

修补把 host 创建的 plan / presentation request / identity / issuer 在 DynamicWorkspace 创建时冻结。Session 使用该早期拥有关系，不在 A.close 后重新捕获现在的身份。打开前、close 后、load 前后和持久化回调均检查同一关系；stale getter 返回空，规划 request 在无三档 preference 的旧 host 接口上也绑定真实 identity。取消的合法只读 fallback 保留原边界，未新增业务执行接线。

无规划请求及三档策略的 host 手工 validated plan 保留现有接口；仍冻结其 host identity，不把它冒称模型规划能力。生产三档入口必须对应当前 validated plan/request。stored draft 没有 generated plan，保留原恢复界面和实时检查。新增 owner 为 final class、构造器私有、issuer 必须匹配，不能在其他 agent 下复用。

修补目标回归 17 passed / 0 skipped / 0 failed：三个新负例，加 SN5 的正常 native detach 保存、真实数据库排队取消/身份替换拒绝、CAS 拒绝及原 retained callback/custom sink 负例。原 SN5 测试与断言未修改；新负例额外断言失效 session 无呈现资格。host strict analyze 零 info/warning。恢复旧 getter 逆变异为 2 pass / 1 fail（6.002 秒）；移除 owner current-request 检查为 2 pass / 1 fail（7.036 秒），均自然 exit 1，无外部超时，源码逐字节恢复。

扩大的 SN4/SN5/SN6、规划 harness/event 和真实 pane 回归以及新 develop 组合全量 CI 仍需完整终态；不要把上面的目标回归或旧候选 CI 当作新组合通过。修复固定提交交原两位 CR18 审查者只读复审；只有新组合 CI 与复审均通过后才可提议 AIUI 合入。

原始 JSONL、变异 diff、ZIP、CI 原始日志仅保留在工作树外 `/workspace/reports/AIUI-chain-independent-evidence-20261011` 和 `/tmp/cr18-fix-evidence`，不入仓库。不修改作者分支，不合 AIUI/develop/main，不运行真实模型或 Android。
