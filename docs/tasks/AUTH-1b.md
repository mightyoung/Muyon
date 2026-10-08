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


## 后续授权与 A 集成结果（2026-10-08）

leader B 后续批准 A 独立复核后普通合入 develop，并持续实施 B1/B2/B3；仍不触碰 main/release。A 实施提交 `994cd6f2fde0841996adaf83c9ce3fee5a16200f`，审查文档提交 `5e94f643b7a1784545ee654633a5dcac157c79e6`。文档 HEAD CI [37713777910](https://github.com/mightyoung/Muyon/actions/runs/37713777910) completed/success；普通 merge `e473b9c205a215b440b56e465b5e357b21c8eff4` 的 tree 与文档 HEAD 完全相同，合入前 strict 与宿主全量 +938 ~3 通过；remote develop 全 SHA 核对相同。postmerge CI [37714945075](https://github.com/mightyoung/Muyon/actions/runs/37714945075) completed/success。

## B1 持久来源事实子片

独立工作树 `task/auth-1b-tools` 从 A merge 开始。宿主 settings 的版本化命名空间保存 task/conversation/source 三类事实，不加迁移、不改历史数据。普通任务默认 unknown；所有 clean/knownEndpoint/grantId 等 payload 声明不参与判定。宿主来源身份摘要仅含 module/project/type/object，修订是证据字段；task/conversation/source 集合只 union，不提供清除接口。任务创建与事实初始化、继承同 owner 事务；读取已有任务也合并当前对话及内存拒绝事实。previousAttemptId 继承完整事实，包括来自旧对话的间接 taint，恢复后的新对话继续继承。

可识别 MCP/network/export/legacy inquiry/knowledge/research 调用先持久标记，再 invoke；返回的稳定 objectRefs 再标记，完成后才接纳内容。结果或摘要中的 false 不清除事实。导入协调器先标记项目再提交模块，恢复绑定事务也补标记；knowledge 在宿主 DB 先提交 original/document 两种来源，再接纳另一 DB 的文件记录。域提交后失败可留更严 taint。写失败维持同 owner 跨服务实例的同步拒绝；不承诺失败写跨进程持久，失败时未接纳的内容也不能说成已接纳。

保守范围规则：workspace 按真实绑定继承源项目/对象；global 将全部已记录来源视为可能加载，不依赖滞后 catalog 判 clean。来源失败门闩也进入这些范围。普通任务仍未知，不实现 clean 证明；trusted scope stamp、grant 自动签发、本地内容 review、B2/B3 完整接线尚未交付，不因本子片的污染接纳钩子声称自动授权上线。旧 UI 供应商直接导入用 legacy inquiry 保守外部分类，不改 UI。

独立静态审查先发现三个继承缺口，均以有效行为 RED 复现后修复：已有 sibling 重开后的对话事实、失败来源 workspace/global 门闩、跨对话间接 previousAttempt 继承。末次独立静态复查 CLEAR，仅覆盖本子片，不代替 leader 最终复核或后续范围证明。B1 两份专项最终 +26 All tests passed，strict analyze No issues found；其余全量/变异/提交 CI 在子片提交证据中记录。


## B1 真实范围证明子片

`HostScopeAuthority.stamp` 同步读取源库 `total_changes()/data_version`、owner/producer 身份、宿主真实 workspace/binding 权限版本、ModuleHost 权限/可用性/epoch 和受管文件实际 SHA。两輪源证明一致才返回摘要；不从 catalog/cursor、模型字段或全 host DB total_changes 推断。源 owner 的 queued write / exclusiveAsync / closing 返回 unknown，失败恢复后可重新证明。宿主范围写单独排队版本覆盖 create/bind/import activate，不让审批/review/audit 写使签发本身失效。

生产首个 producer 只为已核对的 PrototypeStore 注册，另证明 public_knowledge DB 与 files 上下文；未证明完整来源/文件覆盖的其他模块仍 null，不能自动签发。受管文件 namespace 固定，链接或 namespace 改到外部（即使字节相同）拒绝；完整目录 proof 超过 1024 entries / 8MiB 时 null，不假造版本。创建/重开 DB 的 owner 身份不同，原 stamp 不复用。只提供基础生产证明，不启用自动调用。

有效 RED→GREEN：真实 producer 缺失、source exclusive 在途仍有 stamp、证明后源变化混合视图、workspace 绑定排队仍有旧 stamp、受管祖先 namespace 换外部同字节目录。还验证 foreign SQLite connection、同大小/恢复 mtime 文件改动、普通 grant/audit 写不影响 scope、真实 ModuleHost pending/failed revocation 即刻失去权威且 activation 不能恢复失败撤销。

最终范围专项 14 条；B1 facts + scope + owner/module/import/binding 关键回归共 +61 All tests passed。七项范围行为变异杀死并逐字节恢复：源 DB version、foreign data_version、文件字节改成 mtime、源 pending、binding pending、跨源复核、namespace pin。strict analyze No issues found；恢复后宿主全量 +978 ~3 All tests passed，exact SHA CI 见提交/执行回报。clean 输入证明继续留给 B3 实际载入历史/memory/source 的消费者；不能把空 references 当 clean，也不在 B1 提前伪造清洁事实。B2/B3、C、真机仍未完成。


## B2 基础审查/签发/transport 检查点（整片仍执行中）

新增 HostEffectIntent、HostToolAuthorization 与真实宿主专项。intent 由宿主注册的 producer 创建，不接受 JSON 可信反序列化；完整 URI/config 身份、冻结正文、generation、实时 facts/scope 与最终审批绑定。allow 不补授；Noop reviewed=false；block 独立记录，零审批和真实请求；异常/超时转人工，持久 reason 只保存固定码。规则审批与真实 grant 消费共事务，签发失败全回滚；人工来源 grantId=null，审批/回执/真实请求关联同一 review。一次 transport capability 在同 owner 账本事务排队后及实际边界复核，正文/端点改变和重复提交拒绝。旧 standalone 无12关联字段时不伪造迁移事实。

MCP 已固定 RPC id 与实际正文，完整端点 preflight 在审批前拒绝 origin/其他路径/查询；实际 post 发送审查同 bytes，credentials wait 后与连接后重查。trustedEffects 保持默认 false，直到 B3 card/review 消费者接通。web/hub 宿主 channel 以私有 invocation->intent 表先本地审查，block 在 UI/审批/receipt/transport 前停止；无实际 task 的 UI-only channel taskId 保持 null，不以 session 捏造任务。生产全 schema 默认 Noop 本地链；不加远程审查。

独立 transfer RED 证明真实配对 TLS push 等待账本后撤销宿主权限仍发送。将既有 checkBeforeEffect 传入 LAN push，在 ledger 等待、TLS连接后与流入字节前重查；修复后真实 TLS 专项+状态/聊天后台10条通过。不改变协议、不承诺撤回字节。完整 TLS fingerprint/body/link producer、Agent自动调度、真实输入 clean 证明与 C 仍待交付；不把此安全护栏当完整 transfer 自动授权。

当前合法 WIP 的独立快照用于变异，避免共享源改变。快照基线34条，9项有效行为 mutants 全杀死并逐字节恢复：完整端点身份、body不可变、无授权allow、最终reviewproof、transport字节、MCPorigin、审查后改RPC、block降级、TLS撤销重查。编译无效和冗余单护栏移除的早期 mutant 不算杀死。恢复后 strict No issues found；宿主全量+1006 ~3 All tests passed。额外 web/hub、对应夹具和审查文档作为合法已有工作保留继续核实，不删除、不重置；当前快照逐文件SHA与提交前源一致。原始logs与driver仅/tmp。仍未合develop/main/release；最终整片独立review和父集成门禁不由此checkpoint替代。

### B2 paired TLS producer extension (2026-10-08)

TransferService.prepareSendIntent now derives an immutable actual managed outbox body and the full HTTPS /push endpoint plus the verified paired peer certificate fingerprint. It rejects HTTP display origins, unpaired/revoked peers, changed body hashes, unapproved members and message-bearing packages; over 8MiB remains unsupported/manual. HostTransferLedger carries the host capability into the actual push ledger; LanNode pushes the frozen reviewed bytes. Legacy traffic keeps its own ledger. Production public-tool/Agent wiring is still pending and automatic calls remain off.

Valid RED: null producer fails the non-null trusted-intent assertion (fixture schema setup failures excluded). GREEN: real paired TLS body equals reviewed bytes, receipt/ledger has manual source/null grant ID/exact review decision/body hash/byte count, forged model identity ignored; modifying package after review rejects approval and writes zero transport rows. Existing transfer state/chat plus new regressions +11. Three isolated valid behavior mutants (remove paired fingerprint, change review body, drop ledger link) killed and byte-restored. Restored strict clean; full host +1007 ~3 passed. Raw logs/drivers remain /tmp. Foundation independent review and exact-head successful CI are documented in AUTH-1b-B2-foundation-review.md; this extension requires its own independent review.

### B2 TLS independent blockers repaired

The independent b3a7de4 review found actual paired-certificate substitution at the same URI and missing mandatory byte-boundary capability checks when the optional caller callback was omitted. The review is recorded as failed, not overwritten by author results. HostAuthorizationLink now binds actual endpointIdentity; TransferService.send owns an unconditional capability/pair/live-peer guard used through freeze, queue, connection and chunks. Actual paired certificate B cannot use A's review; deadline expiry after TLS connect sends zero bytes without any caller callback. Two real regression fixtures retained, +36 focused passed; two isolated behavior mutants killed/restored; strict clean and restored full +1009 ~3 passed. Independent repair re-review and exact-head CI remain gates before acceptance. B3 consumer WIP is separate and not part of this checkpoint.


### B12 broader independent review reopened the gate

Parent review of fixed `af352970d8477f29e6b0ee04ebcbd4fde7539c34` reproduced two additional windows: positive TLS progress callback expiry before chunk delivery, and first/reopened scope proof trusting an already swapped ancestor. Earlier focused green/CI did not cover them; the baseline remains blocked until repair review. `task/auth-1b-b12-fixes` isolates both fixes from B3 partial commits and WIP. Details and final validation are recorded in [AUTH-1b-B12-boundary-repair.md](AUTH-1b-B12-boundary-repair.md). Production automatic calls remain off, historical databases are retained, and develop integration is reserved for the parent after independent review.
