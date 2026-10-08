# AUTH-1b 宿主分级授权接线

分支 `task/auth-1b-wiring` · 执行 Codex（Mac）· 审查 leader B · 依据 ADR-0002/0004/0005、AUTH-1a 与其审查。2026-10-08 leader B 批准保守工程默认；基线 develop `b95d6f9de1f1b50cadcd8c8092cd3edf9beeef72`。本任务分 A/B/C 提交，当前只实施 A，不能把基础接口说成 Agent 自动授权已经上线。开发期间 UI 合入 develop 后，分支快进集成基线 `965d9130d15379476d8f4ac3bacb830d61be16df`；A 无 UI 修改。

## 不变量与设计裁定

授权只能来自宿主可信 UI，模型、资料、规则、SOUL、模块不能创建或扩大。类别、工具、范围身份、目的地必须全部相同。粗粒度范围身份按 ADR-0004 §5.4：范围种类、工作区/稳定对象/项目身份及模块边界排序编码；逐对象修订和内容摘要仍绑定一次性审批，不扩大选中范围。写入最长 always，外传最长本次对话，新端点逐次询问；只读不消费授权。类别开关只能收紧，模式与端点可信度不因接线自动扩大。

污染来源包括 L2 结果、网页、导入供应商文本（已采纳 Q11）；宿主维护单调污染事实，恢复和摘要继承，写/外传逐次确认。任何来源文本不能清除标记或签发授权。

审查在授权解析后、签发前，只能收紧；allow 不补授授权，confirm 回人工确认，block 零执行零发送；异常/超时 confirm，Noop 明确未审查。leader B 裁定主模型请求和摘要都接本地 ReviewerChain；不新增远程 reviewer 外传。

撤销同步阻止新使用，并在副作用前重新核验来源；在途模型流按 ADR-0005 §7.2 用既有 cancellation 中止、账本 cancelled，不承诺撤回已发字节。已消费 once 的审批不因它自己的消费而失效，但仍受撤销/期限/绑定限制。审批提交后取消或入账失败不自动退款，重放不再次消费；同一次兼容协议重发复核并各自入账，恢复不能沿用已消费的一次许可。

端点身份由宿主 transport/config 提供，包含完整 scheme/host/port/path/query 与 endpointIdentity；按 host 合并不合法。凭据仅传输使用，不持久明文 token，必要绑定安全摘要；遮盖展示串不能用于授权匹配。cloudProxy 按 remote。无可信人工证据端点逐次询问；已撤销授权不能作为自动放行依据。

## A：基础接口、迁移与原子签发（本轮）

1. 原样登记 GrantStore.migration 11；新增 12 为审批/回执及两个出站账本增加 nullable grant/source/review 关联。审查决定独立记录，与真实 transport 状态分开；不虚构已发请求，不写旧 CHECK 不支持的 blocked。
2. 显式扩展 HostSchemaCompatibility 的 12 target、迁移链、版本范围、canonical/repaired 字面指纹。冻结旧夹具不改，新增独立冻结 v12 夹具。真实历史库升级、重开、数据保留、兼容事实/历史不改写、失败事务回滚、未知结构拒绝。磁盘夹具额外填充旧审批、回执、模型/工具真实账本和既有授权/审计行，逐列验证升级、重开、回滚不改值。
3. approval/receipt INSERT 改显式列名，兼容旧表与新增 nullable 字段。验证人工审批、读回执、效应回执、重放。
4. 基础宿主授权接口：同一事务重新核验当前请求、消费次数、used 审计并签发一次性审批；任一写失败全部回滚，不嵌套 ManagedDatabase.write。来源关联只来自宿主，不从模型参数取。
5. ToolGrantContext 必须提供可信 scopeRevision，覆盖对象修订、工作区绑定与范围可见性变化；解析前取样、消费事务内再比对，排队期间变化拒绝签发且不消费。B/C 不得用常量或模型字段伪造此版本。避免在 owner write queue 内 await 范围解析，防止激活/投影写死锁。
6. 真实宿主集成测试：最后一次并发竞争、解析后撤销/到期、签发后撤销/到期、撤销排队及失败、重放、粗范围键与实际审批修订复核、工具/范围/目的地/污染变化。实际 effect handler 次数为关键断言，不以返回 resolver 结果代替。
7. 不接 Agent 自动调用开关，不改权限 UI，不接 transport 自动许可。A 的 APIs 可独立测试，默认行为保持现有确认路径。

## B/C：后续独立提交

B 接 Agent 工具调度、持久污染、类别关闭与本地 ReviewerChain；精确展示内容绑定，review await 后再次核验撤销/污染/绑定。C 接模型主/摘要/恢复/流式/兼容重发，保留 gateway beforeSend→ledger→send 与摘要暴露面限制；订阅撤销取消在途流。

GateAllowed 扩展明确 authorizationSource 与可选 grantId：模式本机/本人设备许可不造假 grant，规则许可必须关联真实 grant。MCP 当前目的地校验是 endpoint.origin，接线须改可信完整权限 identity，并测试同 origin 不同 path/query 不互用授权。主模型与摘要均本地审查；Noop 未审查必须进入审计关联。以上 B/C 不因 A 完成而声称已交付。

## 验证与审查

每切片先观察有效失败测试再实现。新增测试不依赖 sleep、实际网络或仅 mock 回传；升级验证用冻结历史 SQL，不能只用待测 migration 自生成唯一预期。迁移必需的窄测试适配限五个文件：host_schema_compatibility_test 冻结旧 v10/v11 目标；module_grants_test/task_events_test 更新当前 schema 12 并保留历史迁移位置断言；agent_resume_test/data_flow_page_test 的旧夹具 INSERT 加显式列名。业务行为断言与冻结历史 SQL 不改，不以放宽断言换取通过；独立审查须核对该例外。

A 变异：移除范围/目的地比对、移除签发事务消费、审批 INSERT 出错却保留消费、移除副作用前撤销检查、忽略最后一次耗尽、审批修订不复核、12 未扩兼容验证；对应行为测试必须失败，编译错误不算杀死。补充 handler await 期间可信 scopeRevision 改变的真实效应 barrier 及移除效应前修订 fence 变异。每次恢复，最后 analyze 和测试复跑。B/C 另加污染清洗、审查异常 allow、MCP origin 合并、伪造模式 grant、在途流不取消、每实际出站未先入账变异。

宿主 `flutter analyze --fatal-infos --fatal-warnings`（info 失败）、新增测试、宿主全量 `flutter test`。保留所有失败原始输出在 /tmp，不提交日志。独立审查与最终 SHA 的实际 CI 是合入门禁；不合 develop、不推 main/release、不强推。

回报分支/完整 SHA、文件列表、迁移号、逐接口 file:line、验证原始摘要行、变异矩阵、未做/不确定、执行位置、实际 CI；普通 push 后 ls-remote 必须等于 HEAD，不一致回报完整 push 输出/退出码。

## A 本机执行证据（2026-10-08）

在上述隔离工作树、develop `965d9130d15379476d8f4ac3bacb830d61be16df` 基线上完成 A；B/C 尚未接线。保留有效失败测试后实现，独立只读复审发现 handler await 期间修订变化未复核；新增 barrier RED 实际 succeeded、预期 failed，随后补效应前可信 scopeRevision fence，复审未发现剩余代码阻断。

最终 `flutter analyze --no-pub --fatal-infos --fatal-warnings`：`No issues found!`；两份 A 专项测试：`+48: All tests passed!`；宿主全量：`+938 ~3: All tests passed!`（三个既有跳过项）。10 项变异全部行为杀死，逐个恢复：粗范围、目的地、消费遗漏、事务拆分、效应前撤销、最后一次次数限制、精确修订、排队修订、handler 等待修订 fence、兼容目标 12。恢复后 strict analyze 与全量重跑通过。

新增磁盘库测试验证 DDL 后失败、schema_migrations 与 host_schema_state 两类元数据失败均全事务回滚。旧审批、回执、模型/工具账本、既有授权及审计字段值保留。冻结历史 SQL 未改；不迁移或清空用户实库。Flutter 生成的 macOS 文件退出提交范围。

原始日志与变异副本仅留 /tmp；提交说明保留摘要。首次新环境测试启动曾因 shell 代理干扰本机 WebSocket 失败，关闭代理后重跑通过；不将该失败作为行为 RED。父 leader 的最终提交独立运行审查与 CI 是后续合入门禁；本轮不合 develop。真机、持久污染维护、transport 完整可信端点提供、ReviewerChain 与 model 在途撤销订阅均留 B/C/后续实机验证。
