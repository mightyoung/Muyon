# AUTH-1b B 最小接线实施计划与 source inventory

> **For agentic workers:** 使用 superpowers:executing-plans 逐项实施；A 已由 leader B 后续授权普通合入 develop，merge e473b9c205a215b440b56e465b5e357b21c8eff4 的 postmerge CI37714945075 completed/success。按此最小计划继续 B；基础子片不打开自动调用生产行为。

**Goal:** 将真实 Agent 工具调度接入宿主授权、单调污染事实与本地内容审查，维持逐次审批、回执、撤销、范围及先入账后发送。

**Architecture:** Agent 只提交工具意图。宿主授权服务读取独立持久事实、可信范围版本与 transport 构建的实际内容；命中授权后审查只能收紧，最终调用 A 的同事务签发入口。任务 payload、模型参数、网页及导入内容均不能提供 clean、knownEndpoint、grantId、reviewDecisionId 或 authorizationSource。

**Tech Stack:** 既有 Dart/Flutter、ManagedDatabase、SQLite、GrantStore、ReviewerChain、ToolRegistry、两类出站账本；不加依赖、不调用远程 reviewer。

**Spec:** `docs/tasks/AUTH-1b.md`、ADR-0002 §3/4、ADR-0004 §5.4/§7.3、ADR-0005 §6.3/6.6/7.2；A `994cd6f2fde0841996adaf83c9ce3fee5a16200f`，基线 develop `965d9130d15379476d8f4ac3bacb830d61be16df`。

## Global Constraints

- 只做 B；模型主/摘要请求的自动 gate、在途 model cancellation 与逐请求账本是 C。B 要先交付两者读取的 taint/source 接口，并证明摘要不会清除它。
- A 审查未无阻断前只写文档，不改生产代码、既有测试或开启自动调用。
- 旧迁移、历史 DB/夹具/旧行为保持；复用 A 的 12 关联列和独立 review 表，不把 block 写进 transport CHECK。
- grants 只来自宿主已确认 UI；不增加用户授权页，不伪造 localmode grant，不让工具/模型签发。
- scopeRevision 不得常量、仅投影 cursor、模型字段或时间戳替代。不能建立可信同步复核时该工具继续逐次确认，不进入 grant 自动签发。
- 无 grant、类别关闭、来源未知/污染、新端点、无法生成实际出站内容的工具，不能因 reviewer allow 自动放行。
- 实际 body 由 transport 建造；审查/展示/签发绑定同一份 immutable bytes/sourceRefs/端点权限身份。headers 凭据不存库，URI 凭据的完整绑定只持久摘要，显示使用 masked destination。
- B 全程无实际远程服务测试；loopback 是协议 fixture，不能说成真实模型或实机证据。原始 logs/tmp 不入库。

## 已核对的 source inventory

行号是 A 提交的定位入口，实施后重新生成准确行号。

| 入口 | 当前事实 | B 最小修改/验证归属 |
|---|---|---|
| `assistant/agent_dispatch.dart:82-157` dispatch | 模型 `Planned.destination` 直接进入 request；全步 prepare 后先并行读，效应调用 disposition=card | 模型只能提请求，宿主解析实际端点；自动许可判定放在读结果污染已持久化之后。保留 frozen candidates、maxCalls/maxCardCalls 和全步 prepare 失败零执行 |
| `agent_dispatch.dart:219` _openCard / `:440-569` executeCard | 人工逐项再次 prepare、比对 identity、approve、invoke，失败即停 | 共用实际内容审查与最终签发 helper；手动确认仅认可卡上的内容与范围，内容变化重新询问；block 不给“确认后绕过”入口 |
| `agent_dispatch.dart:324-421` _invokeOne / `:620-697` _complete | 回执结果进入 step/message/reference；data 中没有可信 provenance 标记 | 结果来源由宿主 tool metadata 和源对象库认定；可识别外部/L2 调用在 invoke 前先持久标记，失败零 handler；其他结果接纳与污染同事务。失败/取消也可能已有外部内容，不能仅 succeeded 才处理 |
| `assistant/agent_task_factory.dart:29` chatTask / `:106` toolTask | 新 task 含 previousAttemptId，chat 会带历史消息和 memories | 创建时宿主初始化事实；previousAttemptId、同对话历史污染和引入的外部源均继承。新 conversation 使用同源仍污染；旧事实缺失时未知，不是 clean |
| `assistant/personal_agent.dart:129,160,365` start/startTool/resume | 新任务/恢复多条入口 | 创建事实必须覆盖每条；不能只在模型工具流设置污染 |
| `assistant/agent_resume.dart:54,276,393` _manual/_carry/dispatch | 新 attempt 复用已有回执/历史 messages/references/compaction，不能复用审批 | 权威事实继承在 createTask 同事务内；回执 reuse 的 provenance 仍污染，不能靠 result.data['taskTainted'] 判断 |
| `assistant/agent_compaction_flow.dart:160-217,320-430` | 摘要只改 messages view 和 compaction 状态；payload snapshot 可能来自早先 | taint 不存 summary，不从摘要“干净”声明清除。B 测摘要更新与 stale payload 覆盖都不能降为 clean；C 接主/摘要 reviewer |
| `platform/foundation_repository.dart:867-925` createTask/updateTask | 宿主唯一 task 落库；updateTask 以新 snapshot 替换大部分 payload，仅 events 保留 | 独立持久事实放在宿主 settings 命名空间；普通任务 update 不接触事实。显式宿主 mark/inherit 方法与 task create 组合 owner 事务，单调、失败闭合 |
| `app/bootstrap.dart:245,293` | ToolRegistry 无 GrantStore/grantContext；PersonalAgent 无授权服务 | A 通过后注入宿主服务，默认禁用自动直到支持真实事实/可信 intent；已有测试 rig 可注入同服务 |
| `platform/scope_resolver.dart:62,145` / `projection_service.dart:105` | async resolve 会激活模块/等待投影；catalog 派生，onCommit 已被 projection 占用 | 同步权限 stamp 必须来自实际 source DB/绑定/可见性/文件内容；不能替换 projection callback，不能在 owner write queue await resolve |
| `platform/mcp_adapter.dart:149,219,324-361` | config 有完整 URI；_call 却只比 origin；_post 按完整 config URI 发送，并在 rpc 内构造 body/id | 先由宿主 config 构建完整 identity 与 immutable RPC intent；相同 origin 不同 path/query/config 身份不能互用；reserve RPC id 后审查与发送复用 bytes，禁止事后重建 |
| `app/host_tool_registrar.dart:171-219,277-321` | network host policy 是上限；HostChannel 有本人确认闭包；channel 非 modelSelectable | host policy 校验不能等同 grant 端点身份。通道复用审核/来源关联，但保留现有本人确认；没有可信 intent 的 generic external 禁止自动 |
| `app/inquiry_web_authority.dart:60-139` | 私有 pending closure、完整 URL、DNS 后 guard；GET body=[] | 实际 endpoint/method 由闭包保管；审查空 body+URL 与来源，零 body 不表示无外部暴露；网络结果权威 external |
| `app/inquiry_hub_authority.dart:80-142` | 已有 hubDigest、encodedBody、onBodySent 和 actual ledger | 审查 encodedBody immutable snapshot，签发后 body/端点改变拒绝；真实 ledger 来源按调用关联 |
| `services/knowledge/public_tools.dart:360-474` / `services/transfer/transfer_service.dart:705-744` | transfer.export/import/listen/stop/send 使用本人操作、peer 地址和既有 paired TLS；send 冻结 outbox 文件，实际 LAN ledger 在 transport 内 | peer fingerprint + 实际 TLS endpoint/path 是权限 identity；旧 http 地址展示不能冒充实际 endpoint。冻结归档 bytes/sourceRefs 进入审查；listen 保留逐次本人许可，不自动开启。Chat send 与 task envelope 另记 inventory，不能声称工具接线覆盖它们 |
| `platform/outbound_tool_ledger.dart:28,77,101` | 实际 pending/begin → operation → finish，安全显示 URI 去 query；尚不写 A 关联 | 每真实请求写 grant/source/review id；ledger.begin 失败零 operation。block 只存 assistant_review_decisions，零真实账本 |
| `app/accepted_research_imports.dart:158,214,226` / `app/research_task_bridge.dart:168-205` | 本人接纳资料后通过 ImportCoordinator 提交/恢复 | import commit 前保守标记来源 scope，失败可保留更严标记；reconcileCommitted 不跳过 provenance。接纳资料不能变成授权 |
| `workspace/import_coordinator.dart:21,75,168` / `app/app_shell.dart:360,430,493` | host import routes 记录 prepared/receipt、绑定；还有手动导入入口 | 不修改页面；在协调器统一记外部来源，未声明可信本地生成的数据按外部/未知 |
| `services/knowledge/knowledge_service.dart:233-300` / `services/knowledge/public_tools.dart:189` | 本地文件进入 knowledge_documents，存源/内容摘要；也由 search adapter 自动导入 | importFile 持久记外部 source facts；knowledge/read 后进入任务即污染。摘要、索引摘要不变 clean |
| `packages/inquiry_module/.../quotes/quotes_page.dart:225`、`.../inquiries/inquiry_page.dart:86` | 供应商报价/回填在模块内部直接导入，未必经过 host ImportCoordinator | 保持 UI 不动；legacy inquiry 读结果保守 external，防漏覆盖。不在 B 宣称已精准区分本人输入与供应商文本 |
| `packages/muyon_module_api/src/context.dart:61`、`tool_registrar.dart:31`、`tools.dart:48` | 当前 descriptor/spec/result 没有 resultProvenance；有 resultSensitivity，但它不是污染事实 | backward-compatible 可选声明只可收紧；host 强制 MCP/network/L2/legacy inquiry/knowledge 导入来源 external，不信 handler 自报 internal |

所有 `assistant/`、`platform/`、`app/` 等短路径相对 `apps/muyon/lib/`。供应商 UI 两条路径明确属于未知来源缺口，采用保守 external 可闭合，不抢 UI WIP。

## 最小分片和接口决定

B 拆三个可独立审查的提交。B1/B2 的基础接口默认不自动；B3 只为拥有可信 scope stamp + intent 的已注册宿主工具启用。其余工具人工确认；不能用缺接口当已完成全通道审查的证据。

### B1 宿主单调事实与范围版本

**Create:** `platform/grants/host_authorization_facts.dart`、`test/assistant_authorization_facts_test.dart`。
**Modify:** `foundation_repository.dart`、`agent_task_factory.dart`、`personal_agent.dart`、`agent_resume.dart`、`import_coordinator.dart`、`knowledge_service.dart`，适量 host 注册/legacy 元数据。只改 import 的宿主服务，不改页面。

**Interfaces (proposed internal):**
- `HostSourceFact`：宿主构造的 sourceKind（network/l2/import/unknown）、稳定 module/project/object 身份摘要或 invocation id、可选 ObjectRef/内容摘要；不提供清除标记的方法。`HostTaskFacts` 中 sourceDigests 是只增集合。
- `HostAuthorizationPolicy`：宿主只读快照 `readOnly/enabledCategories`；默认标准模式，不存在的规则不自动，readOnly 或类别关闭先拒绝 effect 自动许可。模型不能写 policy；本轮不做设置 UI。
- `HostAuthorizationFacts(ManagedDatabase database)`；`HostTaskFacts readTask(String taskId)`，包含 `taskId/conversationId/taintKnown/taskTainted/sourceDigests`；缺记录返回 unknown，自动效应按 tainted 拒绝；只在宿主完整证明所加载历史/memory/source 为 internal 时初始化 clean，不能把空 sourceRefs 当无外部来源。
- `initializeTaskInTransaction(Database db, PersonalTask task, {required Iterable<HostSourceFact> sources})` 与宿主 createTask 共事务；继承 previousAttemptId 和本次加载历史的对话来源。
- `Future<void> markExternal(String taskId, HostSourceFact source)`：同步内存 deny 门闩后排队持久化，只 union，失败维持 deny。已知外部工具在 invoke 前完成此写，失败不得消费外部内容；未知来源不得先确认 clean。跨进程不能承诺失败写持久化，因此外部内容接纳必须以标记提交为先决条件。
- `Future<void> markSourceExternal(HostSourceFact source)`：稳定 module/project/object identity 摘要（revision 另存证据），新任务引用同源继承。settings 键 `auth1b:task:<id>`、`auth1b:conversation:<id>`、`auth1b:source:<identityDigest>` 保存版本化 JSON，只宿主服务写；不需要迁移 13。
- `HostScopeAuthority.stamp(AssistantScope scope, Set<String> allowedModuleIds) -> String?`：null 表示无法证明，禁止自动。实现同步绑定/模块可用性摘要、相关 source 真实 SQLite total_changes + data_version（不以异步投影代替），并对受管文件提供实际内容证明；存在异步 exclusive 工作或无法覆盖文件变化时返回 null。投影 cursor 不作为唯一事实。不以 host 全库 total_changes 作 stamp（自身审批/审查写会使其永远失效）。未受管理文件无可信 proof 时 null。

- [ ] RED：外部结果后 task payload 明写 false、旧 snapshot update、resume/new attempt、摘要状态更新、重新打开 DB，都仍 tainted；同来源新 conversation 仍 tainted；旧任务无事实记录不自动；mark 写失败保持本地 deny、handler=0/外部内容未接纳；重启不从已失败接纳推导 clean。
- [ ] Run `flutter test --no-pub test/assistant_authorization_facts_test.dart`，观察语义失败后实现上述接口；再同命令 GREEN。
- [ ] RED：模块真实源已变化但 catalog/cursor 未推进，或 workspace 重绑定/可见性撤回，stamp 改变/unknown；不能基于滞后 projection 自动；追加范围证明测试后实现 stamp。
- [ ] Commit B1 摘要与行为证据；不接 Agent 自动许可。

### B2 可信 transport intent、review 与来源关联

**Create:** `platform/grants/host_tool_authorization.dart`、`platform/grants/host_effect_intent.dart`、`test/assistant_outbound_authorization_test.dart`。
**Modify:** `tool_registry.dart`、`mcp_adapter.dart`、`host_tool_registrar.dart`、`outbound_tool_ledger.dart`、`inquiry_web_authority.dart`、`inquiry_hub_authority.dart`；transfer 在 `services/knowledge/public_tools.dart` 与 `services/transfer/transfer_service.dart` 的已存在宿主 transport adapter 处接同 helper，不改 LAN 协议；不把 peer 的 http 展示地址当 TLS identity。

**Interfaces (proposed internal):**
- `HostEffectIntent`：宿主私有构造，immutable body bytes、完整 URI+endpointIdentity 权限摘要、masked display、sourceRefs、scope stamp、tool generation、invocationId、payloadDigest；不能通过 JSON 反序列化为可信 intent。
- `HostToolAuthorization.review(PersonalTask task, PreparedToolCall call, HostEffectIntent intent) -> Future<HostReviewOutcome>`；注入本地 `ReviewerChain`，默认 `NoopReviewer` 明确 reviewed=false；先解析可用授权，再审查，allow 不能补授。
- `HostReviewOutcome` 含 action/reviewDecisionId/immutable intent digest；review 表只存摘要、fixed reason code、reviewed、task/invocation；审查器任意 reason 先脱敏再持久化。不保存 body/URI query credential。
- `ToolRegistry.approveWithGrant` 增宿主私有来源证据入参；最终消费事务内同时比对 facts、scope stamp、generation、intent digest，审批关联 review id；manual approve 接同证据但不消费规则 grant。
- `HostAuthorizationLink`：规则源必须有真实 grantId，人工源 grantId=null；ledger.begin/run 接可选宿主 link，每真实 transport 请求各一条并先入账，standalone 非12 schema 不伪造字段或迁移事实。
- MCP intent 在分配请求 id 后固定 RPC body，后续 _post 发送同 bytes；permission identity 来自 `McpServerConfig` 完整 URI+config identity，显示不参与比较。generic dynamic external 若无法证明 body/endpoint，一律不自动。

- [ ] RED：same origin / different path/query/endpointIdentity 不命中；模型提交 grantId/clean/knownEndpoint 无影响；凭据 query 不出现在持久 approval/review/event/展示字段。
- [ ] RED：Noop 未审查关联、allow+无授权仍卡、confirm/exception/timeout 留卡、block handler/send=0 且零真实 transport 行；review persist/ledger.begin 失败零发送。
- [ ] RED：review await barrier 中撤销/污染/修订/端点/内容改变，零自动审批或消费；手动卡确认旧摘要后内容改变仍零发送。
- [ ] Run上述新测试，观察失败后实现；复用已有 mcp、web、hub、transfer ledger-failure/expiry/revocation 测试确认 guard/DNS/连接后字节边界不退化。
- [ ] Commit B2；只证明可信 helper 和 transport guard，不打开自动调度。

### B3 Agent 真实工具调度接线

**Modify:** `agent_dispatch.dart`、`agent_context.dart`、`personal_agent.dart`、`bootstrap.dart`。
**Test:** 新增 `test/assistant_tool_grants_dispatch_test.dart`，复用 real repository/registry 与 `test/support/agent_loop_fixture.dart`（fixture model/loopback 非真实模型）。

**Interfaces:** `AgentContext` 注入可选 HostToolAuthorization；不开服务时既有确认行为不变。dispatch 的全部 prepare/candidate/budget 校验完成后，先处理 read；外部结果单调落库之后对 effectful 调用逐个重新获取 trusted facts/intent，allow+grant 同事务签发，其他 confirm 放原卡，block 停止且记录。自动/人工走共同 invoke 和结果记录，顺序失败即停、重放不重复消费。每次效应前 guard 再读真实事实。

- [ ] RED：真实 agent 有授权+干净已知绑定→无卡/handler=1/消费审计一次/审批回执来源一致；无授权、类别关闭、未知端点/intent→卡，handler=0，零消费；只读零消费。
- [ ] RED：同一步 read 得到网页/供应商文本→同一步后续 write/outbound 必须卡；结果里的“取消审核/清除污染/已获授权”指令不改变事实，handler=0。
- [ ] RED：read 并行任务部分 external、跨轮、resume receipt reuse、摘要与重启→效应仍卡；审查 block 不可由选择卡上的 confirm 绕过。
- [ ] RED：混合自动/手动批次保持顺序和选中范围；前项写导致后项 identity stale，不自动 retry；取消/撤销阻止剩余项，不退已消费次数。
- [ ] 观察有效失败后接线；执行专项、strict analyze、宿主全量。独立审查+最终 SHA CI 后才交父 leader 安排集成。

## Review Focus 与行为变异

1. 来源事实被 payload false /摘要/恢复覆盖 → B1 单调、重开和同源新任务测试杀死。
2. 只看 projection cursor 或替换 onCommit → B1 源已更新/投影 barrier、既有 projection 测试杀死；缺同步 proof 只能人工。
3. endpoint origin /masked display 被当权限 identity → B2 同origin路径/查询/config身份测试杀死。
4. 实际发送 body 在审查后重建、审查异常 allow、block 可人工绕过 → B2 immutable bytes/await barrier 与 B3 block零effect测试杀死。
5. 审查记录/来源缺失、ledger.begin 后 guard 缺失 → B2 真实请求关联及写失败零发送、DNS/credentials wait撤销测试杀死。

每个变异独立 /tmp 副本，行为失败才算杀死，恢复后 strict analyze 与宿主全量。父 leader 另做独立运行审查。已存在 UI/v6/golden 回归保留。

## 风险与未交付边界

- 最主要工程风险是跨库/文件的同步 scope proof，不能照搬 A 测试的 settings epoch；第一轮只支持能证明的真实源，unknown 保守人工。需要实际证明后才能宣称通用 automatic wiring。
- 实际 payload 现为 handler/RPC 内部生成，generic 工具不能仅用 parameters JSON 冒充待发送内容。MCP、hub 固定 bytes 是第一轮可信 intent 目标；未知 handler 不自动。
- 供应商模块内部导入不经过 host coordinator。B 保守把 legacy inquiry/相关 imported knowledge 读结果视为 external，牺牲自动率但不改 UI；精准 provenance 后续再收窄。不能报告为逐个导入点已精确接线。
- settings 命名空间为本轮最小持久实现，须在 DB archive/restore 中随 host DB 一起保留；任务删除不自动删除 taint/source 事实。若独立审查要求关系表，再新增迁移并补全兼容指纹，不能暗改12。
- A 静态复审通过不替代父实际复审；此文档无 B 生产代码、RED 执行、实现完成、CI绿或实机声明。C 的主/摘要 ReviewerChain、模式来源与 model 撤销订阅仍独立交付。


## B1 checkpoint 执行更新

来源事实 checkpoint `7b5e041b8b82e727f17d47bbd19cc33eca47fd3a` remote HEAD 相同，CI37717681126 completed/success。26 专项、strict、host +964 ~3、6 facts mutants 恢复通过。范围证明子片另有 14 专项、+61 关键回归和 7 scope mutants；其最终提交证据另记。

Ruling: clean proof 由 B3 真实 host 输入载入路径形成，再由 task owner 验证；B1 不从空 references/旧 payload 生成 clean。成本：在证明接线前所有任务仍 unknown，自动许可关闭。首个真实 file/source producer 仅 PrototypeStore 与知识上下文，其他 source 缺覆盖即 null/manual；不把局部覆盖说成全模块已自动授权。

## B2 执行中更新

已实现 host transport intent（无 JSON 可信反序列化）、本地 review 独立记录、同 owner 最终事务签发与 review 关联、人工真实空 grantId、实时 scope/facts/body/endpoint/generation 校验、一次 transport capability 与 receipt/ledger 来源。MCP prepare 分配 RPC id 并固定正文，实际 post 发送同 bytes；MCP 完整 URI preflight 拒绝 same-origin 不同路径/查询，旧调用夹具升级完整端点。web/hub 的宿主私有 invocation->intent 表在 UI review 前接本地审查，block 零 UI/approval/receipt/transport，finally 移除；生产全 schema 默认 Noop 链明确 reviewed=false。旧 standalone 没有12关联列时保持旧人工路径，不伪造迁移事实。

Ruling: 没有实际 task 的 host UI-only channel 审查与账本 taskId 保持 null；不能以 session 字符串捏造任务身份。没有输入 proof 则 unknown/manual。MCP trustedEffects 默认 false，B3 review/card consumer 连接前不启用该 prepare producer；测试显式启用仅提供 real SQLite + loopback 传输证据。generic dynamic external 仍 unknown/manual。

有效 RED：空端点身份/意图摘要、Noop 缺记录/allow 无权限/block 未拦、review 等待后的 revoke/taint/scope/body/endpoint、最终签发回滚/queue、manual/link 缺来源、same-origin preflight、web local block 未拦。初次旧 SSE fixture 没有 UTF-8 charset 导致中文响应写失败，修复字符集并保留中文 exact bytes 断言；不计行为 RED。99 项 helper+MCP/凭据/ledger/A 回归和102项 helper+MCP/web/hub回归通过，strict clean。全量/变异/最终commit/独立review尚待完成；transfer TLS/body/link 和 B3 尚未交付。


B2 基础 checkpoint 验证补记：当前源与隔离快照逐文件SHA一致；baseline34，9个有效行为 mutants 全杀死并逐字节恢复，恢复 strict clean、宿主full+1006 ~3。真实TLS ledger queue撤销 RED→GREEN +10回归；完整TLS fingerprint/body/link producer和B3/C仍pending，不宣称整片完成。早期编译无效/只去冗余block护栏的mutant未计杀死。固定SHA CI与checkpoint独立审查后续回报。
