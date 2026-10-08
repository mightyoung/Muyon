# AUTH-1b production automatic local-write slice

Parent 明确授权持续完成 production clean proof、automatic 与 C。当前隔离 `task/auth-1b-automatic` 从已独立审查修复的输入事实代码 `193eedd52c3a14755851ec676e5958ad88e0b9d4` 开始；输入事实的文档 HEAD `8592e218541493ccb5b0bf3433f6b31b5bd7c526` 已另树推送且 CI 37747572841 success。输入事实已由 parent 精确批准并普通合入 develop `640bac5b62fe331be67f729a6fa62b56d1283a90`，集成 strict8.1s/full1055~3、postmerge CI37752542394 success；本 automatic 子片尚未合 develop；不触碰 UI/main/release，不改历史迁移或用户库数据。

## 实际接线与限制

Bootstrap 使用真实 owner 的 assistant GrantStore。PersonalAgent 从私有 live invocation→task / 完整不可变 request binding 及真实 repository facts 推导 nullable grantContext；不接受模型/快照 clean、grantId 或 scopeRevision。缺真实 owner 返回 null，不造 task/conversation ID 或版本。HostScopeAuthority 从实际 Inquiry managed connection、完整 dataDir namespace/files、现有 ModuleHost 生命周期、实际 Inquiry runtime identity 取得 source stamp，并保留原 context-source proof。legacy Inquiry scope prepare 经过现有 ModuleHost.activate，使实际 scope-resolver 路径具备生命周期证明，不要求测试额外把 slot 标成 ready；不重做 REG。

新的 HostEffectIntent.localWrite 表达冻结参数与实际 resolved scope，没有假 HTTPS endpoint；destination digest 与 review endpoint 为 null。registry 只允许它匹配本机 write/null destination，禁止作为 transport capability。生产只支持已核实的 Inquiry set_item_qty：handler 仍检查实际选择、旧数量和 effect 前授权，再由同一 AppState.write/Store.save 修改本机领域数据。其返回值仅为固定摘要、记录身份/版本和真实 refs/hash；不向模型载入领域 prose。其余 Inquiry write/未核实 producers 保守人工；不会为了正例增加 Prototype 写工具或放宽外部导入。

生产链为本地 ReviewerChain，Noop 标记 reviewed=false；可注入的宿主本地 reviewer 只能收紧，不提供远程 reviewer、JSON grant issuer 或 agent 自动批准接口。完整 pending external union 在任何 review/sign/effect 前落事实；后项 block 也阻止前项效果。仅连续 allow+真实 grant 前缀可自动 sign；遇到首个人工项停止，已完成项从剩余卡移出。人工尾卡逐项 manual confirm，不跳过前项继续自动；真实来源修订变化则 stale 停止，不替换已冻结 proposal。permission 消费、审计、一次性 approval 继续沿 A 原子签发；签发后领域失败/取消/撤销不自动退次数。

schema12 的新 manual approvals 显式 authorization_source=manual，即使旧 producer 无实际 intent/review proof 也不伪造 review ID；仅 schema12 有真实列时写该字段，旧独立 registry fixture 的列结构不变。已有 Inquiry 测试中的手工批准 helper 在实际 local intent 存在时使用 HostToolAuthorization.review→confirm，保留领域结果、撤销/范围/旧值断言。没有把手工测试改成 grant 或削弱原断言。

## TDD 与行为证据

实际 MuyonHost→PersonalAgent.startTool→Inquiry Store 的授权数量写入先 RED：真实 UI capability 创建的 grant 已保存，但旧路径仍 waitingConfirmation。新路径 GREEN：自动成功、真实 grant ID / review ID 与一次消费，Noop 未审查、null destination、无 outbound 请求。随后实际 legacy activateInquiry+scope-resolve lane RED（仍人工）后修现有生命周期桥。native 混合卡出现新有效 RED：旧 producer 新审批的 manual source 为 null；修后 schema12 如实标 manual，null review ID 保留。缺 destination、类型/路径/重复关闭/strict style 类准备失败均不计行为 RED。

新增11条真实 Inquiry Store 场景：grant 自动、无 grant 人工确认、撤销、旧实际历史、持久 source taint、粗范围不匹配、签发后领域校验失败次数不退、approval INSERT 失败全回滚、次数用尽、模型参数伪造 clean/grantId 拒绝、真实文件超8MiB coverage 降人工。

新增9条真实 Host / SQLite / loopback native-model 调度场景：连续前缀及人工尾卡、人工首项不跳过、完整 external union、后项 block、review await 期间 public cancel/revoke/实际 Store source 变化，以及已消费 approval 的 handler await 期间 cancel/revoke。在 effect 前撤销/取消后 fixture counter 为零、后续不执行、真实 count 保持1。这里的 order handlers 是明确的 fixture counters；真实领域效果由上述11条单独核实，不称 counters 为领域/真机/真实 provider 证据。

新20与既有 Inquiry、Agent review/cancel、batch、ModuleHost 专项合跑76通过；strict clean（5.4s）。十个有效行为 mutants：漏生产 GrantStore、unknown→clean 绕过、常量 source version、跨人工项执行、漏 external union、自动误签 manual、重复 completed 卡、漏 manual source、绕生命周期、local write 借 transport link，均编译并产生 Expected/Actual 行为失败，逐字节恢复。原始 logs/driver/results 仅 /tmp，不提交。

## 待门禁与后续

恢复后 strict/full、固定 HEAD 独立复审、exact-head CI 是接纳门禁。本子片不代表全量 AUTH-1b 完成：类别 policy、C 的真实 wire-body review/主模型与摘要/兼容重发/撤销在途及明确 local mode-auto 来源仍需后续实现；真实 provider/真机后置。历史 unknown 内容没有被认证为 clean，unsupported adapters/producers 仍人工。终态私有 invocation/review map cleanup 仍保留既有 WATCH；不宣称通用任意嵌套 secret scrubber。

### 恢复全量发现的 consumer 回归

首轮恢复 strict clean（6.0s），宿主 full 为1070通过、3跳过、5失败，故不记通过。实际 eval consumer 另建 PersonalAgent 未带宿主 reviewer，新增 local intent 的手工批准缺 proof；领域 set_item_qty 失败让 fixture model 响应错位，后续评分回归随之失败。为这个真实 consumer 接入现有 host.personalAgent.toolReviewer，仍人工模式；评分/领域测试断言未改。专项 eval 恢复38通过、1既有real-model跳过（8s）。增加 consumer omission mutant 后重新恢复 strict/full；不以首轮绿专项掩盖失败全量。

最终11项有效行为 mutants（含 eval consumer omission）全部杀死并逐字节恢复；恢复 strict `No issues found! (ran in 5.4s)`；宿主 full `+1075 ~3: All tests passed!`（2:22）。首轮失败记录保留，不覆盖。源码/测试进入固定提交后仍需独立复审和 exact-head CI；本 automatic 子片未获 develop 集成批准。


### 独立审查 MCP catalog BLOCK 与修复

固定 `b7da55abde430fbb688eea1ebe4a46405011b0a0` 的 exact CI37751422172 success 未关闭独立审查发现：真实 McpAdapter.connect / loopback JSONRPC tools/list 返回的 description 和 schema.description 进入 native 模型 wire，但 fresh task 被视为 clean；仅有本地数量工具的真实 grant、没有 MCP invocation 时，模型提出数量修改后实际 Inquiry Store 10→12、uses=1。独立审查 strict9.6s、220通过/1既有real-model跳过仍缺这条边界，因此不接纳旧 automatic 提交。原报告及有效 driver/log 在 /tmp 保留，不混入另行已批准的输入基础切片集成。

正式 native 与 JSON 两种协议均先编译有效 RED：实际 wire 含两个 remote metadata marker，期望等待人工确认且 qty10，实际 qty12；直接 startTool（即使 registry 已登记同 MCP）不载入 catalog 的对照为 GREEN。修复从实际 task factory 本次 selected candidates 的真实 mcp: provider identity 提取输入来源，不从模型参数、仅 registry 存在或 origin 推断。owner-bound opaque proof 固定 task ID / 全 payload / actual DB owner，任务 create owner 事务读其实际来源并单调持久 source、task、conversation taint；native 与 JSON 共用这一事实入口。手工确认/历史输入仍不能认证 clean。

增加真实 Host/MCP/native/JSON 的3条回归（两条覆盖实际磁盘重开、MCP 不再登记后同对话直接工具仍 tainted/manual/uses0；一条保证独立 direct-tool clean 自动正向）与6条 opaque 外部输入 proof 边界：原样/withEvents 保留，payload 改动、copy、JSON、跨实际 owner 丢弃可信来源并降 unknown/manual。新 copy API 和误写测试路径的准备错误不计行为 RED。原57条 proof/scope/automatic重点绿色；新增 proof 整合基线27通过。

五项新增行为 mutants：漏 catalog 来源、漏 owner 事务 taint、绕 payload binding、漏 source digest evidence、漏持久 conversation taint；均须有 Expected/Actual 行为失败且逐字节恢复。最终 strict/full、固定修复提交独立复审与 exact-head CI 后另补摘要；本段不预先认定修复已获接纳。

修复最终恢复验证：27条新catalog/proof重点通过；五项新增 mutants 全部有效行为杀死、源码逐字节恢复；strict `No issues found! (ran in 5.5s)`；full `+1084 ~3: All tests passed!`（2:36）。原11项 automatic mutants 的已恢复证据保留，新增五项针对这次真实新风险；不重复声称旧 CI 已验证修复。固定修复提交、独立复审与新 exact-head CI 仍为后续门禁。
