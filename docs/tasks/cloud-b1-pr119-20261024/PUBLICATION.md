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

## PR122 通用 CI 终态补记

[40049039732](https://github.com/mightyoung/Muyon/actions/runs/40049039732) 已于2026-10-24T01:38:56Z completed / success，精确head为 `a88b5abaf22590c57d745b6ad1383d0309bc864b`，该head查询到的唯一run。laya-offline及ci两个job、全部可见steps均success；没有失败、取消或重跑。

主日志 `CI SUMMARY: OK (analyze 8/8, test 8/8 suites)`；八suite合计4204次通过执行、207次skip。它不是唯一测试定义数；Linux字体/平台/模型条件自跳过不构成设备、模型运行或视觉验收。独立Laya的17项和8/4/8/9 synthetic检查不混入Flutter合计。

只读监控另核PR122仍OPEN Draft，原PR119仍为b08b00bd；没有编辑PR或原owner分支。产品workflow未触发的原因与验收限制保持上一节所述，不把通用CI成功记成产品CI成功。

终态证据保存在工作区 `/workspace/muyon-contracts-evidence/pr119-fix-ci-terminal.json` / `.md`；未提交完整大日志或下载artifact/依赖。进行中日志一次404仅为暂不可读，终态后通过现有connector正常读取，未配凭据或强取signed blob。B1的两条通用CI仍继续跟踪，阶段记录不宣称全部结束。

Evidence SHA256 `pr119-fix-ci-terminal.json`: `e0862030def84037a93e586d4f885ba16b5ef7ceb48ae647c525ae2229bb2dc2`.

Evidence SHA256 `pr119-fix-ci-terminal.md`: `35375646b47f0ae8e24bb8951527e91f99663699475725b1223ba90fc71a1d87`.

## B1 PR 通用 CI 终态补记

[40049205779](https://github.com/mightyoung/Muyon/actions/runs/40049205779) 已于01:41:15 UTC completed / success，ci与laya-offline均success。实际日志核受测对象为merge `4d137ab66c4c52e5fe21f71a70fa1f277739dcb4`，父链包含develop `e16af808620488a7be0b3b4a10b91190d18f1177` 与精确B1 head `e5ca78cb49cfaa641e5d0e8aa73a7e406e2bbefc`。

主日志CI SUMMARY OK：analyze8/8、test8/8 suites，4204次通过执行、207次skip；这是同一组既有包在该受测对象下的执行，不与PR122结果相加宣称新增场景。loaded executable coverage不代表整包分母已知，Linux自跳过/字体/平台/模型条件不构成视觉或设备验收。

至此B1产品CI与PR通用CI成功，PR122的全部已触发CI亦成功。只剩B1分支push通用run40048770932仍在执行；本记录继续将其列为非终态，未人工取消、重跑或用旧head成功替代。

## 最终收束：全部已触发 CI 终态成功

B1最后一条push [40048770932](https://github.com/mightyoung/Muyon/actions/runs/40048770932) 于01:53:03 UTC completed / success。至此：

| 候选 | 已触发运行的最终状态 |
| --- | --- |
| B1 / PR121，head=e5ca78cb49cfaa641e5d0e8aa73a7e406e2bbefc | 产品40049205757、PR通用40049205779、push通用40048770932全部success，共3 runs / 7 jobs |
| PR119补修 / PR122，head=a88b5abaf22590c57d745b6ad1383d0309bc864b | push通用40049039732 success，2 jobs；stacked base未触发产品workflow，不宣称其已跑 |

B1 push实际日志也确认精确head，analyze8/8、test8/8，4204次通过/207 skips；PR通用实际checkout merge4d137ab，产品与push实际checkout head，两者证据分别保留。没有把多个重复run的执行数加成独立场景，也没有把skip、AndroidTest APK编译、model资产校验或loaded-line coverage解释成设备/视觉/推理或全包覆盖通过。

最后只读核对PR121、PR122均open Draft、未merged，head与上表相同；原PR119仍open Draft、head=b08b00bd5c5f0886f3c3c42d573b24e2526804b3，未被本任务覆盖。两棵产品worktree干净。当前没有CI失败需要修复，也没有未决创建审批；首次拒绝已按新增相关历史证据的唯一一次重试完成。

全部只读监测结束。两路终态证据均在 `/workspace/muyon-contracts-evidence/`，GitHub链接和固定source已交叉核查；没有人为取消、dispatch或重跑。较旧不同head dbb42f20的run被系统自行cancelled，不属于本批固定head的成功证明或失败记录。

B仍为唯一合入者。没有merge、main/develop写入、强推、分支删除、部署、凭据配置或新增付费授权。本地复用原已批准工具/缓存，没有重装；真实provider、生产预算/历史费用未知、Reader/FD、视觉和设备门槛保持。下一步为B对两个独立Draft及依赖进行审查；本记录不代替合入授权。

Final evidence SHA256 `b1-ci-terminal.json`: `f596f9570f75b08210f77bc3ec4b87c125a7f8a1c6a2a68c8969c6d87b473a6a`.

Final evidence SHA256 `b1-ci-terminal.md`: `ce3dfdc8da31e7ecdb7fa300bf4afaff3224826b760407ec7f3d6961dc2dadb4`.
