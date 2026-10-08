# AUTH-1b production loaded-input proof

从已审 B3 `b795778` 的独立 `task/auth-1b-production` 继续。parent 于2026-10-08明确授权继续生产 clean proof、automatic grant 与 C，但新代码仍须独立审查，本文件只记录第一基础子片。旧 B3 已另树普通合 develop `bea855df7a4f4a310b70b8a7aea06ec7940587ad`，本子片不进入该合并。

## 实际生产路径与边界

AgentTaskFactory 只载入一次 memory/experience 集合，使用同一集合构造 memoryDigest 和实际系统消息，并读取真实 history。FoundationRepository 基于实际 owner DB 完整上下文视图签发不可 JSON 重建的 HostLoadedInputProof；没有 history、可见memory/experience、前序任务或旧conversation authority 的 fresh宿主用户请求才可能证明clean。并非从空references/模型clean声明推断。

证明绑定真实 DB owner、task ID、完整 frozen payload、对话 scope。PersonalTask.withEvents 保留初始证明，copy及磁盘JSON重建不保留。owner createTask 同一事务重新检查实际输入视图；排队期间新增memory/history、另task/另DB不能借用证明。历史与来源链尚未被证明的 memory/experience/historical task 仍 unknown；verified 标记不等于可信来源。证明是窄 fresh-input lane，不声称全部历史内容都已完成provenance认证。

来源污染与新clean任务保持单调：markSourceExternal 的 owner事务对实际affected任务/对话 union 持久taint；global保守包含所有，selected按稳定module/project/object，workspace按真实绑定。queued源标记尚未运行时 readTask 已收紧，写入失败本会话拒绝门闩不回退。unknown/损坏source metadata不能upgrade为clean。历史DDL与数据不改写，未增迁移。

## 行为证据

真实 public PersonalAgent + SQLite 的fresh clean RED后最小实现；三个unknown/损坏source与conversation RED、实际late source global RED及selected损坏metadata RED后修复。早期补丁匹配失败导致测试未写入，随后旧17条重跑不计新RED。最终新18条包含实际history/memory/experience、二次对话unknown、owner写入前输入变化、task/DB owner借用、持久及queued/失败来源、稳定project匹配；既有facts/Agent review与取消回归另行核实。无真实provider/真机声明。

六个编译有效行为mutants（DB owner、task绑定、载入视图复核、unknown保留、持久late-taint、排队late-taint）全部杀死并逐字节恢复。恢复 strict `No issues found! (ran in 5.8s)`；宿主 full `+1039 ~3: All tests passed!`（1:46）。新18专项通过；之前facts/Agent review/取消专项合跑37通过。独立审查及exact-head CI仍是接纳门禁。原始logs/driver只在/tmp，不提交。

## 后续仍需交付

生产GrantStore/grantContext、已核实实际local-write intent producer与自动sign/有序混合调度、类别policy，以及C主模型/摘要/兼容重发/撤销在途流仍待实现；这份fresh-input子片不代表automatic或C已完成。Bootstrap、UI、main/release本子片未改。输入proof未知时保守回人工卡。

## 28b9231 独立 BLOCK 与边界修复

固定 `28b9231ad6cf4bad70297eeb45123ab289681640` 的 exact-head CI 37744473860 success；独立 strict clean（10.2s）及77通过并未覆盖完整边界。审查追加三条真实 public Agent / SQLite 探针均行为失败，故保留“不接纳”结论：selected ObjectRef 缺少 project identity、workspace 来源 project 为 null 时外部来源被错误排除；workspace 精确绑定 source key 的损坏记录被 JSON valid 过滤错误忽略。

修复将缺失项目身份视为可能相关，已知完整双方身份才允许排除；初始来源继承、排队 read、owner 持久化 scan 均保守处理。workspace 精确绑定记录存在却不能读取时为 unknown；任何无法分类的来源元数据不能通过 SQL 过滤证明与 scope 无关。粗身份和 revision 仍分离，没有补造 project ID。旧 schema/data 不改。

三个独立探针先在作者树正式复现 RED，再修复 GREEN。扩展正式16条边界回归覆盖：标记先于任务、标记晚于任务、owner 队列 barrier、真实 StorageManager 磁盘重开，另含已知 outside project 保持 clean 对照。专项与既有事实/scope/Agent/cancel/manual 合跑88通过。扩展夹具的类型/重复关闭错误不计行为 RED；已修复且重跑。

四个新增有效行为 mutants（selected 缺身份排除、workspace null 比较、损坏元数据忽略、磁盘继承过滤）均被杀死；六个原有 mutants 重新核实均杀死并逐字节恢复。新增分类检查使旧 unknown-source 夹具提前收紧；将其身份字段补全，让该测试单独验证有效分类的 unknown 状态不能提升为 clean，并保留独立 unclassifiable 回归。原始记录仅 /tmp。

修复变异恢复后 strict `No issues found! (ran in 5.5s)`；宿主 full `+1055 ~3: All tests passed!`（2:33）。本修复提交仍须固定HEAD独立复审和新exact-head CI，不以旧28b成功替代；未合 develop。
