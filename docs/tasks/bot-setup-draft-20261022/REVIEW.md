# 非作者独立复审与补修记录

日期：2026-10-22 UTC。独立审查者：本次任务专门派生的非作者 `independent_review`；只读审查、独立编译执行，无源码改动/提交/推送。用户明确要求本批完成独立复审。

## 第一轮

固定实现提交：`94023ba709808fe3c6c3b379427a4e3b136c475e`，基线 `f4781e16ddf4e542b983fbd77f266a0071148255`。

审查者独立运行 Kotlin 编译 + `java -jar /tmp/bot-setup-independent.jar`：PASS 10 offline checks；`git diff --check` PASS。范围仅约定的新组件/测试。未发现模型/网络、凭据、AgentCatalog写入、正式创建或任务启动路径。

R1（应改）：更新候选时把失效选择静默删除，未公开原因；规格要求能力变更重新确认、失权说明原因。要求保留 ID+原因、确认门槛与负例。

## 补修与第二轮

固定修复提交：`f9920c75b05904ab54250c2c65cc6dca3db27390`。

先补检查，因 `invalidations` 未定义产生编译 RED；再新增 `SelectionInvalidation`、五类原因、跨 offer 更新保留，以及显式重新选择门槛。CONFIGURATION → REVIEW 和 `preview()` 受门槛保护；已在 REVIEW 的 `next()` 只是无操作，不能取得预览或开始 pending 观察。

审查者独立执行：

```sh
KOTLINC=/tmp/bot-setup-tools/kotlinc/bin/kotlinc \
  apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/run-offline-checks.sh
```

结果：PASS 11 offline checks；`git diff --check` PASS。

独立结论：R1闭合；技能移除、版本/元数据变化、不可用和资料移除、不可用均留原因；重复更新不清提示，显式选择（含空选择）才确认变化。未发现新增安全或正确性阻断，可作为独立离线内存组件交付；不构成产品可用或合入批准。

审查者要求文档更新完整SHA、11项结果和GB03失效门槛；作者在本报告提交中已更新。该最终提交仅文档，不改已复审源码/测试。

## 作者负向验证

所有变异均复制最终源码到 `/tmp`，逐一编译相同测试后执行；要求编译成功、运行因行为断言非0退出，不能拿编译错误算检出。未改工作树、没有保存原始验证日志到仓库。

| 临时变异 | 结果 |
| --- | --- |
| 接收建议时去掉 request/revision 比对 | 行为断言检出 |
| 采纳建议时去掉 userLocked 检查 | 行为断言检出 |
| editable 放开 PENDING/UNKNOWN | 行为断言检出 |
| 去掉 invalidations 重新确认门槛 | 行为断言检出 |
| 资料候选去掉原scope比对 | 行为断言检出 |

## 适用限制

`AgentProfile` 字段可复用，但当前组件未接其持久化接口；单owner内存状态不是数据库事务/真实创建幂等证明。未知结果冻结是本地合同边界，原intent的权威查询、持久恢复、Compose、正式创建和设备验收仍未接线。整体产品原有 HOLD 未解除。
