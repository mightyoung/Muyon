# PR49 / PR50 独立组合复验（2026-10-11）

本阶段只候选验证，不授权合入。独立 worktree `/workspace/Muyon-review-pr49-pr50`，分支 `review/pr49-pr50-independent-20261011`。无作者分支修改、无 develop/main 推送、无强推/删除/部署；未运行真实模型/Android，未导出 MUYON_EVAL_REAL，全部活动 writer 保留。原始日志仅 /tmp 与 Actions artifacts。

## 固定输入与可审查候选

- develop `f8cbd321d9607e8abe24b53f0b83c0911eaf9649`。
- PR49 `task/reg3f-reg3d-integration-repair-20261011` = `ee831084cf45a41dc5156a126ee821c6215d361d`。
- PR50 `task/wcd-receipt-integrity-20261011` = `01fbed450796dd3268fbb76fb32a2c098de39b8f`，收到独立复核放行后才合进候选。
- PR49 完整 F `2aee00530b363f83398a788204626d11b3ab88b7`、D `99bb4ff0279a4f94b3cf742404aec36de5a159cb` 均为祖先；保留 RED `89d870b4`、`884ebc2`、F→D 依赖和两父合并 `da12cf3d534e90eef581996def044c4907a2d92a`，没有顶层 cherry-pick 丢依赖。
- 第一组合 merge `a968c9e28fcac45eaaa6e5fac6f1994e71dbbdff`，父为 f8 + ee；第二组合 merge `5b837f6ebb74da9ce1efe7f6db5bb89e47e7aa71`，父为 a968 + 01fbed。两次均无冲突。
- 增加独立验收测试的精确代码候选 `f6519fd26dcfa808d0f53fd7c460936a00f84068`；仅 `apps/muyon/test/reg3d_receipt_snapshot_test.dart` 增 56 行，永久产品改动仅来自固定交付。本文后续文档提交与代码候选的 CI 身份分开列明。

已复读 REG-3c-F / REG-3d / WC-D 任务、F/D 组合复审、GB-2 写入契约与 GB-3 日志覆盖；沿用 REVIEW、invariants 与 ADR-0001/0002/0004。仓库及相关 source tree 未发现 AGENTS.md 或本地 .agents/skills；工作流使用 verification-before-completion / using-git-worktrees / test-driven-development。技能附录 writing-good-tests.md 资源读取未成功，不作为已读取材料。

## 独立验收及静态边界

1. 五写工具 × B 更新/删除的 10 个真实交错测试，在 B 提交后经 `receiptFor` 重新解码持久 result_json，精确比较 A 的 objectRefs（含 digest/revision）并比较整个序列化结果。无“只看返回内存值就声称持久正确”。
2. 注入 SQLite AFTER UPDATE trigger：领域 UPDATE 完成后把 title 变为 BLOB，随后 `_report` 的同步 resolve 映射抛错；精确比较项目全行、完整 muyon_change_log 回到调用前，检查 autocommit 与持久状态。宿主保守返回 `interrupted`，没有伪称 failed/无效果。恢复旧事务外 resolve 的逆变异导致持久业务行为断言失败，实际行保留 report-fault / BLOB，证明测试能检出不回滚。
3. 持久 changes/ChangeOp 仍不序列化，已由 CR13 N-3 明确后置；本次验证 objectRefs 快照，不宣称闭合 N-3。新增测试只是此两个 Minor 的有界证据，不宣称所有故障点均注入覆盖。
4. WC-D 先验证回执完整性，再调用身份比对：缺 version/deleted、错 type/id、错 version/revision 与请求 A/结果 B 均 unreadable；实际 Store 四操作和历史回执合法路径保留。只查持久历史回执，不拿当前业务行重新裁定历史版本；读路径不写、不审批、不通知。
5. 已合入 host authorization facts、单项投影、bootstrap 与 host taint probe 接线无 delta；inquiry adapter 自动合并仅增加 businessReceipts 特征/接口/只读方法，原 hostTaintProbe 传递保留。生产 activate 仍未传 task/conversation，unknown→强制确认是安全退路，不能夸称完整身份接线。RED12 的清理超时连锁不作 12 个独立行为证据。
6. 原 F supplier HTTP200→400 deadline/flush 时间窗口未由本次复现或修复；供应产品/测试无 delta。不能把 later green 当成根因修复。此前 host2380基线误报已由上一批 PR46 固定，未重复改其断言。

## 本地验证

官方 Flutter 3.47.5 / Dart 3.13.4；SDK/cache/analyzer state 在 /workspace，未改 HOME。pub get 自动配置已恢复。

- 专项与保护回归：147 pass / 0 skip / 0 fail（F、D 原写入合同/交错、WC-D lookup38+characterization5 项、host taint、授权 facts、单项投影及其两项编译成功的源变异、OC14）。
- WC-D 独立完整目标（lookup38+characterization5+general-write20）：63 pass / 0 fail。
- D 领域：11 pass / 0 fail；额外期望/范围/日志逆变异恢复后 D 写入合同 24 pass / 0 fail。
- 临时产品变异全部恢复后：63 pass / 0 fail（F14+D11+WC38）；源码 diff 为零。
- module_api 全量：250 pass / 0 fail，覆盖当前合同，未沿用旧198计数。
- host/research/inquiry 三包 strict analyze 均 No issues found。
- research 全量：231 pass / 0 skip / 0 fail。
- inquiry 按 CI 入口（apps/muyon → ../../packages/inquiry_module/test）：302 pass / 47 skip / 0 fail。
- 额外直接在 inquiry 包目录启动的全量：292 pass / 47 skip / 10 fail，`ui_workspace_test.dart` 的 `navigation stays usable at Size(1100.0, 420.0) with enlarged text` 出现 RenderFlex overflow；仓库 scripts/ci.sh 明确该 suite 需宿主 asset keys，从正确入口的结果单列，不掩盖原失败，也不改源码/断言。
- 早先一次测试依赖下载 exit69、首次附加断言过度要求持久 changes / failed 状态的 11 项失败均不计产品行为证据；按既定 N-3 与 interrupted 契约修正测试期望后独立重跑通过，没有改变产品掩盖失败。


直接包目录入口的全部失败名（正确宿主入口同一源码全部通过）：
- `ui_workspace_test.dart: navigation stays usable at Size(1100.0, 420.0) with enlarged text`
- `app_test.dart: project budget shows groups, totals, warnings and unpriced lines`
- `app_test.dart: quote page shows upcoming expiry and stale products`
- `app_test.dart: editing a line quantity updates totals`
- `app_test.dart: a price that needs a larger order is not used for 2 units`
- `app_test.dart: refresh prices moves a line to a cheaper valid quote`
- `app_test.dart: inline cells save quantity and turn a changed cost into an estimate`
- `app_test.dart: budget cells: Enter saves and moves down, digits start editing`
- `app_test.dart: quote comparison marks the lowest valid price`
- `generated_icon_sources_test.dart: review all generated vectors at production sizes in both themes`

## 临时逆变异

所有编译/加载成功后观察真实测试结果；mutant 源码恢复到候选完全相同字节。原始 logs 不入仓库。

| 变异 | 结果 |
|---|---|
| D 恢复 ee 父提交事务外 resolve | 0 pass / 11 fail：五工具×2交错 + 新 report 回滚 |
| 持久写入丢掉 objectRefs | 1 pass / 10 fail（已进入行为测试，持久引用 single 为空，不是启动/编译失败） |
| 持久写入清空 digest/revision | 1 pass / 10 fail，精确 A 摘要断言检出 |
| D 删除期望值 / entry 范围 / v10 project-note 日志 | 5 / 2 / 2 fail |
| F 在事务外重新 resolve | 2 fail |
| F 恢复旧边界摘要 | 4 fail |
| F 放宽为裸类型只需存在 | 3 fail（同号/未接受证据） |
| WC 请求 type / target 守卫删除 | 3 / 3 fail |
| WC deleted 与操作关系守卫删除 | 3 fail |
| WC 期望基线版本校验删除 | 4 fail |
| WC 引用 revision / target 守卫删除 | 2 / 1 fail |
| WC 缺失 version / deleted 补默认值 | 2 / 2 fail |
| WC 损坏当 notFound | 33 fail |
| WC lookup 插入 meta 行 | 29 fail |
| WC 仅删除 version<1 | 38 pass：存活，不计 killed；create精确=1，其他操作expectedVersion>=1且version=expected+1仍拒绝非正版本，属于重叠守卫，无新放行路径 |

独立 WC11 变异：10 killed / 1 redundant survivor，与作者“11mutation”分开，不冒充独立复现作者全部变异。

## 精确 CI

- PR49 source push [38138476277](https://github.com/mightyoung/Muyon/actions/runs/38138476277)：ee83108 success。
- PR49 PR run [38138500685](https://github.com/mightyoung/Muyon/actions/runs/38138500685)：独立读原始 checkout 完整 `2a5d3008545e5838612e81512a0ba9fdde855341`（旧522 + ee），success，不覆盖 f8。
- PR50 source run [38138528174](https://github.com/mightyoung/Muyon/actions/runs/38138528174)：独立读原始 checkout `01fbed450796dd3268fbb76fb32a2c098de39b8f`，success；source green 不替代组合。
- 本组合 [38140327555](https://github.com/mightyoung/Muyon/actions/runs/38140327555)：completed/success，job `114472707821` 完成于 2026-10-11 13:01:59 UTC；8/8 strict analyze 与 8/8 test 成功，总计 3539 pass / 207 skip / 0 fail。原始 checkout 与 metadata 都精确 f6519fd26dcfa808d0f53fd7c460936a00f84068；Laya 四组、doctor23场景与 coverage/artifact 步骤全部成功。checkout 必须精确 f6519fd26dcfa808d0f53fd7c460936a00f84068。

组合 CI suite 数字：

| Suite | Pass | Skip | Fail |
|---|---:|---:|---:|
| module_api | 250 | 0 | 0 |
| muyon_ui | 380 | 152 | 0 |
| prototype | 39 | 1 | 0 |
| research | 231 | 0 | 0 |
| supplier_core | 498 | 4 | 0 |
| host | 1824 | 3 | 0 |
| ui_preview | 15 | 0 | 0 |
| inquiry | 302 | 47 | 0 |

## 结论

当前固定候选未发现新增阻塞（C0/I0）；PR49 两项 Minor 已补有界验收与逆变异证据，PR50 原 I1 修复在最新 f8 组合中独立通过。可供 root 决定合入；现阶段未合入，所有分支保留。已知 N-3 / probe 身份未完整接线 / 原 supplier 未复现根因边界继续保留，不能被本次绿状态扩张为已修复。

交付没有越权合入。若 root 放行，唯一 integrator 可按固定候选（含本文 docs-only 后继）与未变的 develop 做正常 no-ff merge，并另验合后精确 SHA/CI；若基线或作者 head 漂移先重新评估，不能复用本次绿状态。
