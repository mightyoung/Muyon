# T-3 验收关联修复：研究提议的接收完成边界

基线：`53089c4a36b025f7097b9556131782c1e630382c`，独立分支
`task/t-3-metadata-scope`。用户授权处理直接阻断本片验收的最小修复；
生产 bootstrap 仍 OFF，不合并，不扩展 UI 或授权范围。

## 已有失败证据

- push CI [38009715380](https://github.com/mightyoung/Muyon/actions/runs/38009715380)
  已终态 failure：analyze 8/8，host `1395 ~3 -1`；唯一失败是
  `research_task_flow_test.dart:137`，Expected true / Actual false。
- 同 SHA 的 PR CI
  [38009717666](https://github.com/mightyoung/Muyon/actions/runs/38009717666)
  已终态 success：analyze 8/8、test 8/8，host `1396 ~3`。
- 原红灯保留，不使用盲目重跑选绿。没有该失败运行的逐边界时序追踪；
  下述定位依据源码，新增停点测试将提供可重复的动态边界证据。

## 产品语义与根因

原 D5 需求（`docs/superpowers/plans/2026-10-04-w1-agent-prompts.md`）定义
`offered → accepted-by → running → terminal` 为任务所有权状态。
`TaskCoordinator.offer` 的附件参数可选，既有 coordinator 测试也验证无附件的
任务进入 offered；没有“offered 即附件持久化完成”的承诺。

接收 `TaskCoordinator.receive` 先 await `_insertOffer` 提交 offered，
之后才 await `onOfferAttachment`。`ResearchTaskBridge.saveOfferAttachment`
保存经过种类、长度、digest 检查的包；`_write` 异步创建目录、写临时文件并 rename。
`isResearchTask` 只检查最终 ZIP 存在。

因此等待 `stateOf == offered` 只能证明所有权记录可见，不能证明研究包存在。
不应为测试改变通用生产状态提交顺序、引入新状态或附件授权语义。

已有 `TransferService.itemsSettled` 是当前接收队列完成 Future。
该队列 await task handler，handler 又 await 附件保存，故完成时该次保存已结束。
必须在观察到 offered 后取得并等待该 Future，避免取得尚未入队时的旧完成 Future。
随后仍保留实际文件存在、无导入/执行及业务结果断言；不能只把队列完成当保存成功。

## 最小变更与确定性证据

只修改 `research_task_flow_test.dart`：

1. 三个既有研究包流程在等待 offered 后 await 现有 itemsSettled；保留全部原断言。
2. 新增一个配对 loopback 停点测试，注入真实 coordinator 的附件回调，
   以 Completer 暂停在真实保存之前：确认 offered 可见而最终 ZIP 不存在。
3. 取得现有队列完成 Future；只推进已调度 microtask，不增加 wall-clock sleep，
   确认它仍未完成；释放停点，await 完成后确认 ZIP 存在、状态仍 offered，
   工作区为空、科研模块未激活、executor 调用为 0。

停点测试刻画已有语义，不将新测试声称为曾独立运行的 RED。
原失败用例的实际 RED 是上面的 push CI；修正与新增证据的动态结果待精确 SHA CI。
无生产代码、UI、状态迁移、权限或 T-3 bootstrap 变更。

## 验证边界

本地无 Flutter/Dart，未执行本地动态验证；使用现有全库 Actions 门禁，
analyze info 仍失败。独立审查最终差异后推送，同 SHA 的 push 与 PR 运行均跟至终态，
保留实际结果和失败历史；原始日志不入库，摘要放提交说明和 PR。
