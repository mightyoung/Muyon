# AIUI-6 首片：有界询价只读宿主快照

2026-10-10；执行者为云端 Codex（真实 Claude/本地 engineer 工具不可调用）。用户授权继续并行开发。独立分支 `task/aiui-6-readonly-snapshots-20261010`，基线 `055a8cbd1e82a63ef632abb013bfc9b2f180172d`，消费已审 PR37 只读本体卡适配；PR37 当时未合 develop，此依赖不写成已发布。

依据：HANDOVER A–D（历史状态按新授权/快照修订）、REVIEW、ADR0001 用户决定、ADR0004 本体与敏感度、NEXT-DELIVERIES-v1 AIUI6/F3b/F4c/F5/REG4c、最新总体设计与 aiui-stream-contract。未发现 AGENTS.md；本云无 Flutter/Dart，SDK受限不绕过。

## 可验收范围

一次读取一个宿主已 pin 的询价单 `inquiry`、报价 `quotation` 或预算行 `project_item`。仅接受 selectedObjects 范围，最多5个明确引用；对象必须在该范围中。复用 PR37 `InquiryOntologyCardAdapter` 的真实 DB/public scope/pin/digest/lifecycle 校验与本体敏感字段投影，既有组件模板保持只读。场景标题分别为询价单、报价、预算行；事实、建议值（尚未写入）与来源对象/修订明确分开。没有模型产值、网络、模块自动激活、授权签发、写工具或提交路径。

这个5引用上限是宿主首片显示/解析预算，与现有导入预览5行规模一致，不改变领域规则或权限。一次只交一个同步投影的快照；不以异步逐对象读取伪称原子聚合快照。已有本体卡的 commercial/personal 遮盖及 credential 不投影规则保持，不为展示价格而削弱。

新增文件独占 `apps/muyon/lib/assistant/inquiry_snapshots/`、`apps/muyon/test/aiui6_readonly_snapshot_test.dart` 和本任务书。不修改 shared API/codec/validator/components/gates/CI、领域金额校验、F4外壳、旧保护测试/2380。

## 验证

先写行为测试，真实宿主 SQLite 显式由测试激活/创建三类业务夹具。验证对象身份/修订、建议分离与保存值/版本不变、非active/错误type/未pin/范围外/超过预算/旧revision拒绝、组件可读及敏感文字/语义遮盖、无业务回执或额外模块激活。完整 analyze 与8套 CI 对固定源 SHA 验证；非作者独立复审后由 root 决定组合，执行者仅正常 push/draft PR。无SDK的专项 exit127不称有效RED或PASS；原始日志留临时工具存储，不进仓库，覆盖基线不自动改。

## 明确未交与后片问题

- 不称完整预算/比价聚合、交互编辑重算、导入复核审批/回执、F4导航恢复或 North Star/live/真机完成。
- `supplier_core.budget/compareQuotes` 当前枚举全部关联记录，没有带 resolved scope + 分页预算 + 全来源 pins 的有界聚合公共接口。推荐由领域owner交此read接口后复用既有预算/税价公式；不能选中少量对象却扫描并展示其余报价。
- 导入 `resumeImport` 可能恢复持久化检查点，本片不把它当作纯读。后片需明确只读导入draft分页/当前revision/sourceDigest公共read接口与敏感字段投影，之后才接现有人工审批与回执。

## 独审修订

针对cd50来源不可定位及正向语义断言P2：owner从已验宿主card.object生成来源module/type/objectId/revision文字，不采信模型来源标签。selected refs元数据各UTF8≤UiCollectionLimits.idBytes=128，来源标签≤labelBytes=256，来源和字段投影总文字≤UiStreamLimits.v1.textBytes；超限拒绝而非截断/丢对象身份。补128/129字节和多字节边界，呈现owner补来源/修订、已保存事实/建议标签的正Text及Semantics验证，既有敏感遮盖不放宽。
