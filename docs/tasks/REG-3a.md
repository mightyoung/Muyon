# REG-3a 科研 / 原型契约 v2、工具与本体

日期：2026-10-09。用户委派执行；只推任务分支，集成由父任务决定。
分支 `task/reg-3a-module-v2`；独立工作树 `/workspace/Muyon-reg-3a`；
真实最新 develop 基线 `b87a22b202cf0c3ce1c98aebb4df32af8d08d847`。
原 `/workspace/Muyon` 的 `work@cc7c8d1` 保留不改。

依据：ADR-0004 §10.2、§10.3、Q10；REG-2b 审查的工具可用性后续；
GROK-1 已确认清单和 GROK-2 覆盖初稿。REG-2 / AUTH 已合；
UI-2a / UI-4c 已合。索引与旧交接时间线不代替实际 Git 基线。

## 有界交付

- 两模块实现 BusinessModuleV2，声明本体、覆盖清单与 registrar 工具。
- 三个原读工具 ID、描述、结果、排序保留；读工具支持选中范围。
- 跨项目 scope session 返回当前 canonical 引用；科研 project 可解析；
  文档摘要按当前磁盘 bytes 算，旧摘要失效。原型 page/version/feedback
  校验所属页及钉住摘要，无绑定对象页可开。
- 本机写入经宿主 prepare / 一次审批 / invoke / 回执；先实现 ADR 点名的
  saveNote / addOutline / assessRun / acceptRun 及 prototype.add_feedback。
  其余真实操作面逐项入覆盖清单，未开放要写理由与后续任务，不能假称覆盖完成。
- 保留科研宿主导航、已接受导入对账、工作区导入恢复桥接与所有旧交换、
  索引、询价守护。REG-3b 单列 ExchangeCapable 与 searchSources 搬迁。
- 不建 REG-5 的通用 module_api/testing.dart / analyzer 全仓套件；测试落点
  `apps/muyon/test/reg3a_module_v2_test.dart`，复用已有范围差分、对象页、
  module_lifecycle、导入恢复与 inquiry / north-star suites。

## 需明确的契约缺口

REG-2 的 v2 knowledge/models scoped facade 尚未实现；保持 optional 请求且
policy 拒绝，绝不授予完整 gateway/ToolRegistry。撤销任何请求都应持续阻止
模块重新激活；宿主合法重新授予只能清除撤销并重算既有策略，不能提升权限。

Q10 已批准本机 exportReport/exportClaimDrafts，但当前 ExternalToolSpec 的
DestinationRule/NetworkPolicy 只接受有 host 的网络 URI；本机路径的目标
选择与允许根目录契约缺失。本片不猜 destination、不伪装为 write，也不改成
网络请求；覆盖清单保持 deferred，交父任务明确本机 export 门面后续。
其余本机写工具按已批准方向逐步补齐，不把 GROK 草稿的建议 ID 当成已注册。

## 验证与门禁

运行 `bash scripts/ci.sh`（所有 analyze / package tests）；重点新增测试核对
契约、原 descriptor、范围外参数拒绝、无确认不写、单次确认回执、撤销立即 /
重启拒绝、合法重授权恢复、磁盘变化与范围差分。保持 ADR §10.3 既有测试。
若旧测试断言 v1 授予整 gateway，只更新为 v2 明确拒绝的安全断言，记录原因。

环境初探：Git 可读远端；GitHub HTTPS 200；无 Flutter/Dart；官方 storage
下载端点 HTTP 403；gh token 无效。不绕过下载限制，不把静态检查称为运行测试。
本地失败如实记录；已授权任务分支 push 触发远端 CI，核 exact SHA / 终态。
若远端认证失败，保留提交并报告具体动作阻塞；原始日志仅 /tmp，不提交。

## 后续与交接

REG-3b：交换接口及检索迁移（不擅自补设备收发）。REG-3a 后续：其余本机
写入、Q10 本机导出门面。REG-5：源码枚举与完整通用契约覆盖门禁。
独立审查由非作者按 REVIEW.md 执行；父任务决定是否集成，不能自授批准。

## 恢复后的有界偏离与验证说明

父任务已确认 AIUI-1 独占 `module_api/src/ui/`，本任务允许继续
`module.dart` / `module_v2.dart` 两项可选接口；不修改公共导出或 AIUI 测试。
最新 fetched develop `33783cf` 相对建分支基线仅文档变化，尚未合入本任务。

为准确报告 saveNote 的真实新增对象，补 `note` 类型（非 global），
回执返回 note canonical 引用；同事务记 ModuleChangeLog，不改已发 schema-9。
为保持 ADR §10.3 的原型既有保护测试，原型保留 v1 `/` route；v2 宿主仍只消费
sections，这是兼容偏离，未修改 prototype tests。

撤销后 optional capability 也保持模块 unavailable，直到宿主显式 reconsider；
更新 `module_host_test.dart` 的旧 optional 自动重激活断言为更严格的失败/无 runtime
断言。reconsider 只撤掉 withdrawal，重新应用静态策略，不授予 raw models。
原 v1 legacy grants 断言也改为 v2 对 scoped facade 拒绝，均须独立审查。

测试 `reg3a_scope_candidates_test.dart` 使用恶意身份和非 global 类型夹具；
`reg3a_module_v2_test.dart` 使用真实宿主库、模块写入与审批回执。
旧 scope 差分夹具仅将原 prototypeScopeRefs 逐字搬入 fixture，使其与新实现独立。
所有原始 CI 日志留 /tmp，不进入仓库。

## 首个完整实现门禁失败后的局部修复与保护测试例外

`faf3766` / CI 37950154964 到 failure：analyze 8/8、test 7/8；
宿主 +1257、3 skips、4 failures。新增 REG-3a 行为测试没有失败；
四项为菜单顺序回归及三条旧 v1/撤销断言，均非环境失败。

- 科研 section 的 order=1 保持原菜单「记事本、询价、科研」顺序；
  不改 module_declared_ui_test 的期望。
- module_lifecycle_regression / assistant_scope_authority 原有的持久撤销失败
  注入与 pending/failed 拒绝断言保持；撤销重试成功后也必须拒绝，
  直到宿主 explicit reconsider。增加多项撤销不能被单项重新授予抹掉的断言。
- **ADR §10.3 保护测试例外：prototype_tools_test.dart**。原工具 ID、读取
  结果与两读工具 read-only 断言保留；原「整个模块只有两读工具」inventory
  断言与已批准的 add_feedback 新写工具不可同时成立，改为同时验证旧读集合
  与精确新 inventory、唯一新增 write、没有 external。批准前不写、批准后
  单次回执仍由 REG-3a 新行为测试检查。此例外须 leader 审查才能集成；
  非作者静态复核或 CI 绿不代替 leader 对受保护测试变更的批准。

原始日志不提交；最终精确 SHA 与门禁结果在交付回复中统一登记，不为了
运行状态反复推送文档取消 CI。仍不合 develop/main。

## 获授权的阻断修复（5ef48b7 后）

用户已批准恢复修复，与 AIUI-2 各自分支并行；不合 develop。
独立审查发现：v1 research/tools 的持久撤销在 v2 manifest 移除 tools 后，
原 record 整模块替换会清除旧撤销并自动恢复模块。保留 revoked 墓碑，
激活检查全部持久撤销；当前请求和真实历史撤销均可由宿主显式 reconsider，
已移除能力只清除旧 withdrawal，不生成新 grant。保持原静态策略/权限架构。

page_detail 异步取得 runtime 后同步复核 page 及返回候选的 version/feedback
归属与摘要，检查和读取之间不 await。此为受控 DB 变化下的防御性一致性修复，
不声称普通 UI 路径漏洞；旧 ID、描述、正常返回结果与保护 inventory 测试不改。

测试落点 reg3a_upgrade_read_guard_test.dart：真实 v1 ModuleHost 固定 grants、
真实旧同库 v2 升级、连续重启保持拒绝、宿主显式恢复后仍无 raw tools，
旧数据保留；陈旧授予决策不能覆盖撤销；Completer 屏障控制 runtime await
期间的 page 删除、version digest、feedback body/owner 变化，拒绝旧快照，
并确认合法新 feedback 摘要可重新读取。无 sleep，不提交原始日志。

固定正式要求 002aef4e 已批准科研内容、文献作者与机器标记 author 为 none；
当前声明符合。未来 author 存真人姓名须 personal，不再列作待确认阻断。
