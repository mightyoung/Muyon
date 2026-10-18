# 通用CI终态：独立轻量审计

结论：**通用CI范围C0，无新增阻断。** 本次只读核原件/哈希/本地Git tree，没有构建、重跑suite或修改源码。当前范围完成，停止本方实质writer；不扩HY/production任务。

[CI39097188758](https://github.com/mightyoung/Muyon/actions/runs/39097188758) 的run.json实际head API字段为产品F2 `3f1be180bb009a91e659c113ba5b1916e5360332`，event pull_request，completed/success。jobs.json为ci success，全部steps success，没有把skip当成功。

**实际执行checkout是G `6a9c4da11e39375c6b6eba43cf138417287cc65e`，不能重标为F2执行。** job.log记录fetch refs/remotes/pull/86/merge、checkout该ref、HEAD at6a9c4da Merge F2 into develop0ab2c4f、git log -1输出完整G；下载coverage summary.source_sha也为G。独立本地git rev-parse核G与F2 tree都为`30ccb7d1ceda6fe66baeee0266ce961a57fd3e2e`，与final-state/GENERIC-CI-TREE-PROVENANCE.json一致。因此该通用CI认证G执行环境下相同源码tree的通用行为，不冒称G就是产品commit。Rust/Android专用jobs显式checkout产品SHA，身份分别保留。

实际原件目录 `/workspace/batch4/evidence/ci/f2-generic/`：run.json、jobs.json、job.log、downloads/ci-log/ci.log及coverage-summary。独立验证结果：

- ci.log实际8条analyze ok、8个suite test ok，与CI SUMMARY analyze8/8、test8/8相符。
- suite-summary.json逐suite exit0，summary原文与ci.log逐项匹配。独立求和4199 passed、207 skipped；skip原因维持unknown，未将全部207归因为平台/字体/model。
- Doctor实际`test_doctor: ok all 23 scenarios passed`；verification gates成功。
- coverage实际SUMMARY OK；DA-details控制5通过、coverage合同控制9通过。job.log嵌入COVERAGE_SNAPSHOT解压后actions_run_id=39097188758，suite_outcomes和下载原summary逐字段完全匹配。
- Laya独立step实际在scripts/laya执行四脚本test_stage1_contract/test_stage2_data/test_stage2_threshold/test_kaggle_submit；日志依次Ran8/4/8/9并四个OK，step success。不是仅信step名称。

Coverage仅为Linux/Flutter3.47.5加载的executable-line分母，各package仍有unloaded source files、whole-package percentage unknown；未输出全仓覆盖率或将skipped计为通过行为。通用Flutter/Laya/coverage通过不证明Android设备运行、真实模型或M03/public API冻结。

独立结果与原件SHA索引：`GENERIC-CI-AUDIT.json`。父/root后续final seal/safehandoff可引用本scope结论；本报告不代替A独立报告或整套merge决策。I04仍按此前父/root报告的平台possiblecyberrisk拒绝而未执行，不重试/换代理。没有本review待完成构建/子进程/writer，未commit/push/merge。
