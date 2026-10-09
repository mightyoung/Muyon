# AIUI-3 F3a 交接（实现与验证进行中）

冻结基线：`0466f113fd7dd41f99c38cef11eca428622a6fac`。任务书 AIUI-3 与 AIUI-NEXT-BATCH-CONTRACTS 相对 `82df0f29d9628d107d96d52795438e972ce5fefe` 无差异。开工远端无同任务分支/开放 PR；工作分支 `task/aiui-3-local-formulas`，draft PR #8。未找到 AGENTS.md；已读 REVIEW、正式 aiui-stream/1 与定价/预算/字段校验源。

## 范围与宿主接口

交付文件限定新增 `apps/muyon/lib/platform/ui_formula_registry.dart`、其测试和本报告。新接口仅为 F3a 宿主内部纯计算，不意味着任务书草案的正式契约已获采纳。没有生产接线、数据库查询、网络、业务写入、任意回调/表达式执行，也没有修改共享 export、runtime、typed edit、collection schema 或其他 owner 包。

- `UiFormulaDefinition` 由宿主通过有限 named factory 建立，固定公式名/版本、实例 id、槽名/绑定/单位及事实对象/字段身份。
- `UiFormulaInvocation.forDefinition` 从宿主定义建立请求；请求仍校验公式/版本/实例、精确槽集合与精确 BindingRef。无 JSON/模型请求 decoder；模型 formula/expr/value 拒绝沿用已有 `packages/muyon_module_api/test/ui_stream_test.dart` 的正式流负例。
- `evaluate(invocation, snapshot, currentUiState)` 只读当前快照与完整冻结 scalar 状态投影；快照必须预声明全部状态键。事实身份包括 ObjectRef 的修订与内容摘要；readFailed/conflict/notDisclosed/notApplicable 不作可信数值。unverified 可计算，旁路 `unverifiedInputs` 保留标记。
- 通用 sum/product/margin 的输入政策必须显式选择 `supplierCoreUnsigned`：复用既有 ExactDecimal 的 unsigned、12 位整数、6 位小数规则。没有采纳通用 signed/新精度规则。询价税率继续用既有 3 位整数/4 位小数且 ≤100；13 表示13%，0.13表示0.13%。数量0仅用于本地展示，不能作为允许业务保存零数量的证明。
- `UiFormulaLimits` 必须由宿主显式传入，测试配置为32槽/256 decimal UTF-8字节/16KiB总输入。这是本片的安全配置示例，不是正式快照/流/typed schema 的新默认值。总字节覆盖诊断输入记录：定义身份/输出单位、快照版本、槽及引用、typed原值、事实对象/字段/单位/状态/来源和完整状态投影。
- `inputFingerprint` 仅为私有、opaque 的输入诊断；不会缓存、持久化、授予权限或证明跨 runtime 结果可发布。其正式格式及缓存/恢复语义仍交契约 owner。`inputBytes` 用于诊断和边界验证。

## 登记与依赖

所有当前登记版本为1；下列输入都必须来自宿主已声明引用，而非模型数字。

| 登记名 | 本片交付 | 单位与舍入 |
|---|---|---|
| ui.sum_decimal | 宿主固定事实槽，缺项不跳过；空组须宿主明确允许 | 同单位/币种；micros精确加法，canonical String |
| ui.product_decimal | 宿主声明数量与单位价的量纲；不推断转换关系 | 件 × CNY/件 → CNY；supplier multiply，微量半值远离零，舍入一次 |
| inquiry.tax_price | 同一quote身份的价格/币种/税口径/税率/成交价事实，加预声明目标税口径；薄调用priceInTaxMode | 目标币种/报价单位；税转换仅一次舍入，跨币种、不明税口径、转换缺税率不可用 |
| inquiry.margin_amount | 宿主已按现有预算次序算出的销售额与成本引用 | 金额单位（CNY），精确减法，负毛利保留，不输出百分比 |
| inquiry.markup_unit_price | **已有budget.unitPrice事实的引用登记/对照** | 原预算单位价canonical String；未实现加价参数预览 |

supplier_core helper 建议（外部依赖，不在此分支实现）：提取预算现有单位加价计算为公开纯函数，输入 unitCost/markupRate/explicitUnitPrice；显式单价优先，其余保持预算现有正值舍入顺序。让 Store.budget 调用同一 helper，先单位价舍入，再乘每行数量，再求和；新增纯函数与 Store.budget 对照，包括0.1→0.1125、10.333333→11.625、显式6覆盖，以及正微量半值。AIUI-3 待 owner 完成后薄调用，不复制预算公式。

后续询价阶梯/单位/附加成本需要宿主投影；科研9项需要 AIUI-7 项目/对象/任务修订与集合事实，以及 AIUI-5 codec/正式规则采纳，当前均未登记，未用skip计作完成。科研delta/ratio负基准/精度仍待决定。

F3b / AIUI-5 仍负责编辑调度、immutable新快照、重校验、状态迁移、computed发布/移除、旧动作失效及恢复。纯evaluate结果不是已发布ComputedValue：ready为真实scalar；unavailable/invalid/stale均不返回旧成功值或伪0。AIUI-5应按任务书发布表处理不可用null、非法移除与过期整批拒绝，不能直接合并旧槽。本片的版本/状态变更用例仅证明纯计算，不证明现runtime自动刷新或恢复。

## 验证证据

待云端 RED/GREEN、变异与最终 SHA 审查后更新；原始日志不入库。

本地 SDK：Flutter/Dart 不存在，未下载或绕过限制；实际 `bash scripts/ci.sh` 停于pub get，输出 `flutter: command not found` / `CI SUMMARY: FAILED (pub get)`。本地 Flutter analyze/专项/领域/全仓未运行；既有 Actions 将在精确提交执行各包完整suite，覆盖指定pricing/unit/store/research revision回归。

辅助脚本本地执行：`scripts/test_verification_gates.py` 9通过、`scripts/test_doctor.sh` 23场景通过、Laya四文件分别8/4/8/9通过。基线已有Actions `37971444082` 对应冻结SHA，8/8 analyze、8/8 suites成功；它不是本片通过证据。
