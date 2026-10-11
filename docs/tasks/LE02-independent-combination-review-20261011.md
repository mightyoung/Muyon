# LE02 独立组合验证（等待新组合 CI，未合入）

固定作者源 `cb3852d2a13947e59b2bb3bcb745a64bb78f5336`；最新 develop `ffc1f9d1d56956ec699c8b5c6f939a4fefc491ef`，正常合入独立组合 `08619f465375f541ef1ec41c04ca48f753eee49c`，无冲突。作者分支未改。Parent 独立静态 C0/I0/M1、可组合；本验证不是完整 claim_drafts/模型导出闭环验收，不给工具/文件目标/模型新权限。

## 实际动态证据

- 原准备器6例全部通过；独立补充2例通过：可变 ObjectRef getter/id/digest 与 caller list 改动不影响冻结sources/manifest/bytes；只读观察连接覆盖全部业务表，正向准备及跨project拒绝后同连接total_changes、另一连接所有表、文件路径集合均不变。该只读fixture首次遗漏project必需question/next_step导致Null/String设置错误，已补完整字段；不计作产品行为RED。
- 从不可变 develop git blob逐字提取旧exportReport函数体到仓库外临时类，在相同中文/笔记/重复引用/已接纳run fixture上实际执行旧writer。新准备、兼容writer、实际旧writer、固定golden字节四者完全相同，1例exit0；不是只依赖旧输出注释。生成时间由调用方固定，不从文件名或UUID推导正文。
- 三项任务规定逆变异均由原断言检出：按读取数量计数（entry3/run2而非1/1）、重复引用不去重（note2/entry2/run2）、Uint8List不复制（首字节0而非35）。每项7pass/1fail、exit1，恢复source逐字节一致。
- 两项独立补充敏感性验证：不快照source值，仅外层list不可变 →原补充Expected entry/Actual replaced；加入同值UPDATE隐藏写 →total_changes Expected2/Actual3。各7pass/1fail、exit1，均已恢复，不提交变异。
- 恢复及清理弃用API修正后 research_module 全量244pass/0skip/0fail、exit0、coverage实测已采集；research与host strict analyze --no-pub --fatal-infos均零问题。全量host及八套组合最终门禁由新组合CI覆盖，此刻未终态，不借旧源CI或本地部分coverage冒称全库通过。

## 冻结修复与覆盖门槛

LE01冻结修复完整保留：本组合的整个module_api lib树与develop完全相同，tree `d46e4198fba09b949a8288bab0920a640c42387a`。`scripts/coverage/baseline.json`与develop逐字相同；没有修改门禁/checker/measurement。现有API gate库存38个源文件、36个loaded文件、2514个DA、2387hit旧floor；models751/778、transfer827/882及各文件旧floor不下调。新八套CI完成后按实际artifact重新核源库存/DA identity及全loaded source hash；这里不把本地research-only覆盖当全库gate，也不把旧baseline顶层历史source_sha改写成新组合快照。

## M1 登记（保持未修，非阻断）

source摘要entry仅data不含title，document仅sha不含relativePath；整体bytes/hash/manifest仍变化。Parent评为M1，不视作审批偷换。本组合没有修这两处，不称M1关闭。源码只输出纯report准备与旧兼容writer；仍不实现claim_drafts/模型导出闭环。

原始日志、暂时旧方法、变异diff/结果、LCOV及source散列留在工作树外 `/tmp/le02-evidence/`，不入Git。候选完整SHA及CI run/终态以独立组合分支回读；CI绿后供Parent复审，未经授权不合develop。LE04/LE05及REG3e-a另有已登记静态阻断，不随本链混入或以旧源绿放行。
