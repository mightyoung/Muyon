# 本地 Bot 创建事务末验修复（取代旧依赖放行结论）

2026-10-22 UTC。父审指出1f9e的Important成立：原confirm仅在事务外检查项目存活，pending提交后的effect事务及receipt最后写入后没有完整复验。不能以旧8项通过或前次独审“未见缺陷”覆盖此问题。

## 固定源与最新协议

- 测试先行/切换最新协议：`32232b770805d19fc2b29f3d7aba708da9965524`。
- effect入点与末验修复：`74040cea77af6c5e82857d560ce6cca63f59e38e`（曾因来源registry校验缺失被独审阻断，非最终候选）。
- 来源registry DDL与meta补修：`00b042ea7748c315d7c3ab9f4c8b9b02fdd4660d`（曾因BLOB隐式转换被独审阻断，非最终候选）。
- 来源/回执/定义存储类型测试先行：`b123aac6aaf6803a3f70e40ab4d8203515b3ed5b`。
- 最终源码：`a132ebe5447fc65f9bc2a0c7afbc3ce1e23a3d17`。
- **唯一当前组合依赖：`098d9aca214e6642c1b3ffde64921ebedbae335d`** 的bot_drafts.rs。它已采用prepare_save冷启状态机；所有fixture现在先 `prepare_save(SaveRevisions)` 再save。原15c及其8项通过仅为历史，不可带回B组合降级。

仍只修改本作者的新增bot_definitions模块及自身测试/报告/复现脚本，不改bot_drafts、documents、正式lib.rs、FFI、Runtime/Service/UI或main/develop。runner只在/tmp克隆副本组合最新固定依赖并追加临时模块导出。

## 修复机制

1. 保留prepared原intent的冻结快照跨越durable pending提交，effect不能采用触发器改写后的新快照冒充原审查。
2. prepared事务内、effect事务入点、定义INSERT和receipt UPDATE后的最后一步，均通过 `verify_current` 重新读取持久状态。
3. 检查BusinessStore真实meta workspace/schema version、当前项目存活/归属；来源registry三表精确DDL及唯一meta的id/schema/workspace/namespace；草稿generation/storedRevision/lifecycle/scope_key、实际archive bytes及digest。
4. 检查原intent身份、draft_key、scope_key、冻结配置、digest、ownerEpoch、状态；末验还读取精确receipt和真实definition的scope_key/draft_key/序列化内容，不用内存返回值替代数据库事实。
5. 与最新草稿owner对齐：archive_hex/digest拒绝SQLite BLOB→TEXT隐式转换，按字节长度而非字符长度限额；自己的冻结JSON、receipt JSON、definition JSON也要求真实TEXT并有字节上限。
6. pending之后任何校验/存储失败统一返回 `bot_query_original`。effect与receipt在同一事务回滚，第一事务durable pending不清除；不能换intent重建。项目已经撤销时普通lookup仍服从当前scope，可能无法显示详情，但底层pending保留，绝不因此自动恢复项目权限。

私有 `confirm_create_with_boundary` 只是让测试在真实pending commit后、effect BEGIN前执行确定性合成变更；公开confirm只传no-op，没有向UI/模型开放任意回调、SQL或执行能力。

来源registry schema常量逐字来自固定098d的只读消费合同，只负责校验；不初始化/迁移/写入第二套registry。owner未来schema变更必须重新组合核实，不静默兼容未知格式。

## RED→GREEN证据（不覆写中间结果）

- 初始父审反例，在旧依赖下8过9失败；只作问题重现历史。
- 切换098d后第一次23项中10过13失败；其中两个scope_key测试误触多行UNIQUE约束，不能当作该保护通过。
- 把scope变更限定目标草稿后，精确行为RED为 **8过15失败**，见precise-scope-red输出。
- 第一修复24项全过，但独审另外复现source registry workspace/version变更仍Committed；补三项正式RED为 **24过3失败**（另含两事务间registry ALTER TABLE）。
- registry补修27项全过，但独审又复现archive/digest BLOB仍Committed；补六项正式RED为 **27过6失败**。此RED工作树相当于b123测试提交，未拿编译错误当行为检出。
- 最终a132在最新098d下 **33 passed / 0 failed / 0 ignored**；原8项重新按新prepare_save协议执行，不复用旧依赖的成功。

新增反例包括：精确两事务间project删除、pending UPDATE trigger删除project；definition INSERT与receipt UPDATE trigger修改draft revision/lifecycle/scope；receipt尾修改project、物理workspace、ownerEpoch、原intent身份、定义字段/identity、回执；来源registry workspace/version/DDL；archive/digest/definition/receipt/frozen JSON的BLOB存储类型及两事务间类型改变。

每个receipt/INSERT尾拒绝都用独立只读SQLite核零definition、原pending及NULL回执，并验证相关草稿/项目/epoch原值回滚；移除触发器后重复确认仍Unknown、新intent仍拒绝。pending事务内或两事务间已发生的外部撤销本身保持生效，不因回滚effect撤销用户的项目删除。

## 当前复现与证据

```sh
python3 docs/tasks/bot-setup-draft-20261022/run-creation-checks.py
```

最终作者新捕获及负变异：`capture-tail-release.py`；其metadata记录a132、098d实际源码hash、所有命令/UTC/exit和日志hash。旧capture-creation driver已加精确历史HEAD护栏，防止新协议运行误标15c元数据。

新原始证据目录 `tail-recheck-evidence/` 保留每轮RED/GREEN、独审新增反例、最终独立输出和SHA256清单。原始Cargo进度行有尾随空格/末尾空行，完整diff空白检查因此可能非0；不修剪原始日志，代码/测试限定diff及rustfmt另验。旧lab的read/write ABI lint警告仍保留，不冒称零警告。

此前未带完整UTC元数据的手动中间运行，仅保留真实日志，不补造历史时间；最终作者/非作者重新按固定源码和依赖完整捕获。

## 交付限制

必须由B组合最新098d、导出并接正式host路径后再做同候选设备验证。本次不合入、不修改公共路径、不发真实模型/搜索、不创建账户/配置凭据/授予grant；所有SQL触发与进程测试仅原创合成临时BusinessStore。旧两次unknown、¥0.002620预占和I04拒绝不变。


## 最终独立裁定

固定a132、依赖098d：非作者正式33/33 PASS，另有5项/tmp独立探针PASS（两meta、两来源BLOB、effect入口被撤销后INSERT trigger试图恢复project）；此前漏口全部闭合。删除effect-entry检查的变异被恢复project探针检出；删除receipt末验的变异被18个尾部负例检出。逐行复核通过，无剩余阻断/应改，可交B固定组合，不构成合入授权或产品接线证明。

独立主metadata SHA256：`0c7afaebecbe46c7c029a24ee7d16095678dcc49b36b8906be4e6a8c33e2918a`；独立额外探针及变异metadata SHA256：`a53c4be2c1430438ddfe7cfac19954dc3bee04b2a30f4ec5366c1290dc061bd8`。

作者固定a132最新依赖的33项新复跑与8项临时变异均成功完成：每项变异先编译，再因行为断言失败，未用编译错误算检出。规则和完整原始输出见author-release。原author-final属于00中间候选，连同所有被阻断的独审结果保留，不能替代release。
