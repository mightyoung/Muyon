# 云端 B1 / PR119 补修：发布与 CI 记录

2026-10-24（UTC）。只记录已完成工作与固定候选证据，不合入或部署。此补记在独立文档分支，不改产品候选 head 或因写报告反复触发其 CI。

## 实际并行与固定源码

| 工作 | 隔离 worktree / 分支 | 代码审查点 | 已推送候选 |
| --- | --- | --- | --- |
| B1 | /workspace/muyon-b1-20261024；task/public-domain-projections-b1-20261024 | 18a4e8b7d831c5bb6b1fb2e6b24e97dbe1e113e1 | e5ca78cb49cfaa641e5d0e8aa73a7e406e2bbefc |
| PR119 生命周期补修 | /workspace/muyon-pr119-lifecycle-20261024；task/pr119-plan-lifecycle-fix-20261024 | a12efa637b01462ed4dfad2d395c2b8777b288f4 | a88b5abaf22590c57d745b6ad1383d0309bc864b |

两棵 worktree 和各自 target 实际同时执行，不是仅派发未启动；未共享源码写入。B1 root 串行登记仅追加 domains/mod.rs 两行。工具复用 /workspace/muyon-contracts-tools/env.sh：已获准 Rust/Cargo1.93.1，103/103 锁定缓存摘要匹配，SQLite工作区链接仍可用；本地没有重新安装、下载依赖、改锁或配置凭据。

B1：结构 / 行为 RED 分列（不可用桩0/4）；真实公共导出4/4、research/business回归30项、workspace724 passed /0 failed /0 ignored，严格Clippy通过。独审无Critical/Important，另跑4项通过；报告minor已修正。新增可信 ScopeRef 输入只校验一致性，不签发权限；Unbound不是附件读取或存在证明。

PR119补修：原head b08b00bd5c5f0886f3c3c42d573b24e2526804b3已只读核实未修；固定RED daa0ace72d32f3e02216f41137abde56d5c96aa6编译后5失败/1通过。修复后10/10新增、45/45完整FFI lib、workspace781 passed /0 failed /0 ignored，严格Clippy通过。独审另跑45项/Clippy无必修。仅retire exact未派发plan，保存未知先查原SaveAck，保留原intent/receipt；未修已撤回的冷启动cancel。

本地 workspace 计数含既有跨 targets 重复执行，不是独立产品场景总数。完整原始证据摘要及未验边界分别见：

- [B1报告 @ e5ca78cb](https://github.com/mightyoung/Muyon/blob/e5ca78cb49cfaa641e5d0e8aa73a7e406e2bbefc/docs/tasks/public-v02-B1/REPORT.md)
- [PR119补修报告 @ a88b5aba](https://github.com/mightyoung/Muyon/blob/a88b5abaf22590c57d745b6ad1383d0309bc864b/docs/tasks/pr119-plan-lifecycle-20261024/REPORT.md)

## Draft PR 与此前审批拒绝的收束

首次创建 B1 Draft PR 被自动审批审核拒绝，理由误沿用最初“仅文档”阶段，工具返回 isError，没有PR URL。root未换工具或隐瞒拒绝。父任务后来补充用户明确要求推送、组织PR、并行推进开发及转云端继续的相关历史证据，并要求先核结果、仅重试一次。

root只读查两head的所有PR，均为[]，确认先前创建未执行。随后同一GitHub创建工具对B1重试一次成功；PR119也仅建立自己的独立修复Draft。此前产品报告中的“创建阻断 / 尚未尝试”是该次发布时快照，此处明确其已解除，不改写历史失败记录。

- [B1 Draft PR #121](https://github.com/mightyoung/Muyon/pull/121)：base=develop，head=e5ca78cb49cfaa641e5d0e8aa73a7e406e2bbefc。
- [PR119补修 Draft PR #122](https://github.com/mightyoung/Muyon/pull/122)：base=codex/muyon-production-gaps-20261023，head=a88b5abaf22590c57d745b6ad1383d0309bc864b。stacked diff只审本补修；创建PR没有向原owner分支写提交。原[PR119](https://github.com/mightyoung/Muyon/pull/119)仍是b08b00bd，未被覆盖或合入。

## CI 来源与验收限制

GitHub connector的fetch_commit_workflow_runs只列PR事件第一页，不能用空数组断言push CI不存在。为查push状态，root和只读监控子任务使用已有gh API读取workflow/job/log，不配置凭据、不取消、dispatch或重跑任务。

B1该head观察到原push通用CI、PR通用CI和产品CI。产品workflow显式checkout PR head；通用PR测试GitHub临时merge commit，须分别记录tested source与parents，不能把merge SHA当head。

PR122的base为原候选分支，不满足现有product/通用workflow的PR base过滤；其task分支push触发通用CI。没有为了补这个CI状态修改workflow、改base或手动触发外部运行。原PR119 b08的hosted成功不覆盖新补修。

最终CI结果另附下节，只接受对应固定SHA的真实终态。编译、合成测试、打包、lint或CI成功均不关闭视觉/设备/provider、Reader/FD、生产预算/费用、OAuth/WebHook、Skill/Connector执行的原门槛。B仍为唯一合入者；root未merge、强推、删分支、部署或改变付费/凭证范围。

## 01:35 UTC 阶段记录（CI 尚未全部终态）

Draft 创建已成功，没有待解除的创建审批阻断。创建前确认两条head均无PR；B1按新增历史证据仅重试一次，PR119补修单独创建，均保持Draft。

| 固定候选 / 运行 | 当前结果 | 已确定证据 |
| --- | --- | --- |
| B1产品 [40049205757](https://github.com/mightyoung/Muyon/actions/runs/40049205757) | completed / success | rust-and-checkers、android-product、required-product全success；实际source=e5ca78cb，47组Rust结果724 passed/0 failed/0 ignored、Clippy和Python17通过；双ABI native、桥生成、实际编译、清理后离线assembleDebug/AndroidTest编译/lint通过 |
| B1 PR通用 [40049205779](https://github.com/mightyoung/Muyon/actions/runs/40049205779) | in_progress | laya-offline success，主job执行包分析/测试；merge对象4d137ab66c4c52e5fe21f71a70fa1f277739dcb4，API父链为develop e16af808及候选e5ca78cb；完成后仍需核实际checkout日志 |
| B1 push通用 [40048770932](https://github.com/mightyoung/Muyon/actions/runs/40048770932) | in_progress | 同分支旧head dbb42f20的run40048508732被系统自行cancelled后，当前run已脱离pending；不把旧head结果算本候选 |
| PR119补修 push通用 [40049039732](https://github.com/mightyoung/Muyon/actions/runs/40049039732) | in_progress | source=a88b5aba，laya-offline success，主job仍执行Analyze and test every package |

截至此阶段未有已报告失败步骤，未手动取消/dispatch/重跑。进行中通用job日志正常读取返回BlobNotFound时只记录可观察性限制，不重复强取，也不把404当CI测试失败。B1已完成Rust job日志通过现有GitHub connector正常读取，避免从artifact文件名中的merge SHA误判实际head checkout。

以上是阶段快照，不把in_progress、编译或Linux自跳过计为完成验收。两路只读监控仍在继续，最终终态将追加记录；产品分支head不会为更新这份报告而改变。
