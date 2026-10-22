# GR-01 / GR-02 / GR-03 最小离线底座交接

2026-10-22，云端 `/workspace/Muyon-group`；分支 `task/group-governance-20261022`。

本批交付可独立测试的纯 Rust 治理校验模型和接线计划。GR-01/02/03 均为部分基础交付，不标为完整功能完成。没有生产群组 schema 迁移、持久调度队列、模型计划生成、leader 移交执行、UI 或自动运行群组。没有真实执行网关，`Eligible` 只是校验建议，不能当授权或 exactly-once 保证。

## 基线与授权边界

- 远端 `codex/muyon-android-refactor` 已经 `git ls-remote` 核实：`f4781e16ddf4e542b983fbd77f266a0071148255`，本分支直接基于该提交。
- 初始已保存工作区 `/workspace/Muyon` 是干净 `work`，HEAD 为 `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`；保留原工作区，在新 worktree 开发，未覆盖用户修改。
- `/workspace` 与本候选未找到 AGENTS.md。已读任务索引、HANDOVER-LEADER、leaderb-continuation-20261018/HANDOFF、REVIEW-REPAIR-20261021 以及现有 workflow 实现。旧任务索引的本地执行限制由本次明确云端委派更新；Leader B 唯一 develop 合入职责不变。
- 已完整读取 Library 群组规格 `libfile_1dc39497fd788191913071611441fa0f` 与总纲 `libfile_d1ffab06dfa4819180f0affb933237bf`。其旧“仅设计”时态由本次具体最小实现委派限定更新，不扩大其他工程授权。
- 初核远端 main=`cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`，develop=`0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`；本任务不修改两分支、不合入、不强推、不删除、不部署、不付费、不配置凭据或扩权限。
- 历史两次真实请求 unknown、预占 ¥0.002620 未结清保持原状，未查真实供应商、重试、结算、释放或修改原账。测试中的 2620 是整数微元夹具，非真实账务操作。

## 实现与现有模型对齐

新增 `crates/muyon-core/src/group_governance/mod.rs`，测试在 `crates/muyon-core/tests/group_governance.rs`，lib.rs 仅增加模块导出。没有改 workflow.rs、数据库 schema、Cargo 依赖或 UI。

1. `Principal::Human` 与 `Principal::Member` 分开；owner/admin 可校验原成员 grant 的收窄，不能扩权；coordinator 不获得管理权。模式显式表示 host_only/fixed/per_task，未知字符串 fail closed；版本仅支持 1，无 owner 或非法配置拒绝。fixed/per_task 的执行校验始终 UnsupportedMode。
2. 所有成员/节点权限是用户、群、任务、工具四层政策与成员能力的交集；scope 是宿主解析后的精确身份，不解释路径前缀/通配符。无成员、跨 scope、越能力、缺政策层拒绝。
3. `HostSnapshot.children` 是现有 root 的完整历史 child 投影，排除 root 行，不是新账本。现有 `RunLedger::children` 查询包含 root；原 `children.len() > 8` 正是 root+8 后拒绝第9 child。模型直接从 child 行得出深度1、活跃2、累计8，不维护可重置的旁路计数。queued/running/waiting_confirmation/unknown 占活跃槽；failed/cancelled 仍占累计名额。
4. 计划仅为未接纳节点的只读提案。完整 DAG 检查循环/缺依赖/重复身份/跨 root/深度2后，以 node ID 的稳定字典序选择下一可接纳节点；依赖必须已经 completed。它不生成模型调用，也不把全部提案直接写为现有账本 queued 行。
5. 命令身份绑定 workspace、host owner_epoch、run、配置/政策/计划 revision、coordinator_epoch；对当前可信宿主快照的任一不匹配都拒绝。无 leader 切换实现；版本比较不能替代 live host lease。
6. 重复命令完整绑定相同时仅返回原 request_id 与状态，变参数冲突拒绝；重复 request_id 或命令记录拒绝。停止后仍可得到原查询提示，但不能继续派发。旧 epoch 的查询仍须由原宿主回执路径完成，不能借本校验重新执行。
7. unknown 预算标识、Submitted/Unknown 请求记录、单个 unknown child 均阻断新提案；保留传入预占，不修改任何状态。预算使用同一宿主定义的整数币种单位、checked_add 防溢出；缺实际费用必须由原账务投影保留 unknown，不能填零。
8. 轮次上限显式非零；从原宿主完整命令/意图记录数派生，Prepared 也保守消耗轮次，失败/取消/重开不退款轮次。不能用截断为256条的展示事件流作为生命周期记录源。接线前没有可靠完整来源就保持关闭，不新增旁路计数。

## 测试与独立复审

工具链原不在 PATH。仅在 `/tmp/muyon-rust` 解包使用官方 stable 元数据所列 Rust/Cargo/rustfmt 1.99.1，四个组件下载包 SHA256 与官方元数据核对；没有写系统目录或变动项目依赖/锁文件。依赖首次按原 lock 下载到临时 CARGO_HOME，之后均 locked/offline。

测试先行：先写17项行为测试，模块尚不存在时编译失败；补齐接口空实现后真正行为 RED 为 **3 passed / 14 failed**。实现后17/17通过；再加3项状态边界成为20/20。独立审查发现 unknown child 漏标边界后，新增真实回归先见 `Eligible` 对 `ReconcileOriginal` 的失败（exit101），修复后最终21/21。没有把编译缺失当作行为 RED 或把派发当测试完成。

独立审查由非作者只读子代理完成，报告见 [INDEPENDENT-REVIEW.md](INDEPENDENT-REVIEW.md)。其重编译重跑最终21项无警告通过，单独复现探针也从失败变通过；无剩余阻断代码发现。R2（政策层具名/来源验证）保留为生产接线前要求。报告保留修前发现与修后裁定，未声称 Android/真实执行验收。

验证命令（从本 worktree 根执行）：

```sh
/tmp/muyon-rust/bin/rustc --edition=2021 -D warnings --test crates/muyon-core/tests/group_governance.rs -o /tmp/muyon-group-tests
/tmp/muyon-group-tests
/tmp/muyon-rust/bin/rustfmt --edition 2021 --check crates/muyon-core/src/group_governance/mod.rs crates/muyon-core/tests/group_governance.rs
git diff --check
PATH=/tmp/muyon-rust/bin:$PATH CARGO_HOME=/tmp/muyon-cargo CARGO_TARGET_DIR=/tmp/muyon-cargo-target RUSTFLAGS='-L native=/tmp/muyon-native-libs' cargo test --manifest-path crates/Cargo.toml -p muyon-core --locked --offline
```

standalone 21/21（exit0，无警告）；fmt 与 diff 检查通过。最终源码的 Cargo 全套 `muyon-core` 验证 exit0：16个测试二进制共168 passed、0 failed、0 ignored，另有0项 doc-test。修前20项群组版本的先前全套为167 passed；不将旧版本结果替代最终168项复验。Cargo 首次缺 PATH 中 rustc（exit101），设置 PATH 后 offline 缺缓存 serde（exit101）；依照现有 lock 获取缓存后首次链接缺 `-lsqlite3`（exit101）。系统已有 `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0`，仅在 `/tmp/muyon-native-libs/libsqlite3.so` 建链接名后复验；没有更改项目链接配置。依赖中的两个 `suspicious_runtime_symbol_definitions` 警告来自既有 core-agent-lab/host_session.rs 的 read/write C 声明，本批不修改。

六项临时副本变异均被真实测试检出，不改仓库源：累计 cap 8→9、活跃 cap 2→3、移除 epoch 比较、移除 unknown 预算检查、移除四层权限交集、跳过 DAG 循环检查。分别命中容量、旧身份、unknown、权限、DAG 的命名测试。原始临时日志留 `/tmp/muyon-group-*`，不把原始验证日志加入仓库。

最终代码 SHA256：
- module `0cea48fe4e01a95c0980e0d77d4ece899f6aa86adc58c4c43a8d2b068a2b0099`
- tests `1487f996311cd8d9a65970d6f02cc135f36ee5cd35b39fe790e57d119a477076`

## 接线顺序与剩余阻断

1. 由既有 owner 从当前 RunLedger/原请求与根预算 owner 产生不可变、完整、一致的快照。验证 workspace/project/root 身份、原配置版本与所有 scope 来源；移除 root 行，不能漏 unknown 或历史 child/attempt。请求记录和 children 都仍只属于既有宿主系统。
2. 将四层政策改成具名宿主输入并证明其来源，绑定 canonical digest、精确 payload/接收方/费用边界/政策版本。不能用模型 JSON 构造 trusted snapshot 或以管理身份代替必要人类批准。
3. 在唯一宿主动作网关的同一原有事务内重查版本/epoch/live lease、scope、容量、完整历史、预算/原回执和费用证明，再持久 intent/reserve/claim。当前函数结果不能跨事务作执行票据；并发批准、崩溃窗口与无幂等外部系统须另验。没有实际生产费用证明时保持外发关闭。
4. 仅在该接线完成后才讨论持久队列恢复、期限/超时/取消、schema 迁移、固定/每任务 coordinator、安全检查点原子增 epoch、有限 handoff 和来源最小交接包；本批没有完成这些功能。旧 leader 只能归档迟到证据，不能恢复派发。
5. 由 Leader B 在独立组合候选上审查与验证；本分支只独立提交并推送，不自行合入。PR100/既有设备与费用门槛、旧两次 unknown、I04 原拒绝及依赖 HOLD 均不因本批测试而解除。没有触碰或重试原被拒动作。

本批无网关、数据库迁移、Android/设备验收、CI终态或真实群组运行证据；不宣称这些完成。没有自动审批拒绝、未决变更操作或不确定副作用需要重试。
