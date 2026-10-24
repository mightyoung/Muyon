# PR119：prepared plan 生命周期补修

2026-10-24（UTC）。状态：独立 Rust 补修候选，未合入或部署；不替代原 PR119 的 Android、视觉或真实 provider 验收。

## 基线、环境与并行隔离

- Git fetch 及 GitHub PR119 查询核实其仍为 Draft / open，head 为 `b08b00bd5c5f0886f3c3c42d573b24e2526804b3`，没有已完成的相同修复。
- 本分支 `task/pr119-plan-lifecycle-fix-20261024` 从该 head 创建，worktree `/workspace/muyon-pr119-lifecycle-20261024`。原 owner 分支 `codex/muyon-production-gaps-20261023` 未被修改。
- B1 同时在 `/workspace/muyon-b1-20261024` 独立源码 / target 执行，未与本片共享源码写入。本片 target 为 `/workspace/muyon-contracts-tools/pr119-target`。
- 现有获准 Rust / Cargo 1.93.1、103 个锁定 registry 缓存全摘要匹配；crates/Cargo.lock SHA256 `d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`。未安装、下载或升级依赖。

## 行为与修复

原 mutate 成功持久化编辑会清除 submission，却留下原 owner 的 prepared map 条目；重复 prepare → 编辑可耗尽全局 128 上限。prepare_project 创建新 plan 后，review_prepared 的持久化失败也会漏掉新 plan。原保存 envelope / intent 被丢掉时，重复点击可能直接产生更多 plan。

只改 development_host.rs 和 development_session.rs，新增私有 pending 保存状态及只读原 SaveAck 查询转发；不改公共 ABI、Operation、全局 discard_plan 语义、数据库 schema 或业务执行账本。

1. 同一个 owner state 临界区核对完整 CommandEnvelope 相等且 !dispatched，才删除该 exact preparation；不按全局清空或仅按猜测身份删除，不删除原回执。
2. mutate 捕获 active 与 restore 后两份可能不同的旧 command；只有成功保存或成功恢复当前 draft 后才判断哪些已过时，保留当前 command。action 在保存前失败不查询一个尚未发起的保存。
3. 保存前保留原 envelope / save intent；失败先查询这一次 SaveAck。None 只能提前释放确定未保存的 fresh review plan；编辑旧 plan 仍需当前 draft 读成功后判断。Some 先验证 owner/scope/revision/intent/digest，再恢复当前快照；不覆盖后续编辑。
4. lookup、ack 校验或 restore 不明时保留 pending，prepare / mutate / confirm / select_saved 先完成原查询，不能盲建新准备或重发业务命令。只有原保存结果及当前快照读清后才清屏障。
5. 已派发命令不被本清理 helper 删除，原 IntentId / receipt 留在原 owner。冷启动 cancel 问题已撤回，本片未修，也未改变原 revoke/cancel 行为。

这里的 pending 只是当前 host 内存中的原草稿保存身份，不是新增持久执行账本。进程内查询失败期间它阻止重复准备；未知效果不能被强行当作未执行或释放成另一请求。

## RED / GREEN 与额外覆盖

固定 RED 提交 `daa0ace72d32f3e02216f41137abde56d5c96aa6`：编译成功后新增6项中 **5 failed / 1 passed**，Cargo exit101。失败分别复现129循环容量耗尽、局部编辑未释放、review CAS失败新plan泄漏、save失败泄漏、未知lookup时重复准备。原派发回执保留用例已通过，不冒称全红。

首轮实现实测5 passed / 1 failed。剩余失败来自测试故障恢复：ALTER TABLE 改回原名会改变 sqlite_master SQL 引号，而原 DraftStore 严格校验精确 DDL。测试改为创建原始精确表、复制原行、删除临时表；没有弱化生产 schema、断言或期望。该次不是新的产品问题，原始日志保留。

最终固定代码 / 测试提交 `a12efa637b01462ed4dfad2d395c2b8777b288f4`：10项生命周期测试全部通过，包含4项补充回归：stale edit保留另一编辑者当前review、真实保存后completion丢失的ack Some恢复、编辑保存未知时confirm屏障、加载后出现review的清理。这些补充覆盖直接通过，不伪造另一次产品RED。

lost-completion 用例先执行真实 review 保存，再回退 host 内存完成边界并保留 exact pending，确定性进入 Some恢复；不是实际断电或真实进程崩溃。

## 实际验证

命令先加载 `/workspace/muyon-contracts-tools/env.sh`，再覆盖 CARGO_TARGET_DIR 为本 worktree 专用 target；全部 Cargo offline / locked。

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-android-ffi --offline --locked --lib development_host::tests::lifecycle_ -- --test-threads=1
cargo test --manifest-path crates/Cargo.toml -p muyon-android-ffi --offline --locked --lib -- --test-threads=1
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-android-ffi/src/development_host.rs crates/muyon-android-ffi/src/development_session.rs
```

| 验证 | 最终结果 |
| --- | --- |
| 新生命周期测试 | 10 / 10，exit0 |
| 完整 FFI lib（包括 development_host/session、command_port、重复点击/恢复回归） | 45 / 45，exit0 |
| workspace / all-targets | 781 passed / 0 failed / 0 ignored，49组结果，exit0 |
| workspace / all-targets 严格 Clippy | exit0 |
| 两份变更 Rust 文件格式与 diff check | 通过 |

计数包含既有跨 targets 重复执行，不表示781个独立产品场景。原 b08b00bd 的 hosted CI 成功不覆盖本修复 SHA；本候选 CI 须按实际 push SHA 另查。

## 独立审查

Fresh-context reviewer `/root/pr119_lifecycle_final_review` 审查 b08b00bd..a12efa63 固定差异，无必须修复项；独立 target `/workspace/muyon-contracts-tools/pr119-review-target` 实际完整 FFI lib **45 / 45**、lib Clippy `-D warnings` 和 diff check均exit0。完整审查artifact在 `/workspace/muyon-contracts-evidence/pr119-independent-review-a12efa63.md`。

审查核对锁序 active→owner、同锁 exact/dispatched 判断、跨host CAS、None/Some/unknown恢复与原回执保留；历史RED只核日志，不冒称独立重现。其declined-to-judge保持：没有线程压力/loom/TSan/真实断电矩阵；ack mismatch和restore-only失败部分分支为静态核验而非全动态注入；没有代验远端状态、外部审批、设备/视觉/provider或整个仓库安全。新source不改ABI，但本轮未重跑Android双架构/生成桥/Gradle/设备，不能继承原候选结果关闭门槛。

## 发布与限制

本候选准备正常push独立分支。建议作为基于PR119的补修独立审阅，原PR119 owner分支由B处理，root不覆盖或合入。可供后续Draft PR使用的问题描述：编辑或保存失败后原prepared准备未收束；本补修通过exact未派发清理与原SaveAck恢复屏障保持原身份，并防止129次编辑耗尽准备容量。

B1 Draft PR创建已经被自动审批审核拒绝，理由错误沿用最初“仅文档”范围；本批后来明确获准B1/PR119实现、push及Draft PR。PR119的Draft创建尚未尝试，不通过换工具或目标绕过同一审批范围问题；待父会话处理澄清后再创建。本轮没有隐瞒或冒称PR已创建。代码/测试/独审与正常分支推送独立完成。

未改main/develop，未merge、强推、删除、部署、配置凭据或付费；未运行真实模型/provider。生产预算、OAuth/WebHook、Skill/Connector执行、Reader/FD、U2和完整视觉/设备门槛保持。普通回退可撤销两个FFI文件补修，不删除已有草稿、SaveAck或业务intent/receipt。

## 真实日志摘要

原始日志与精确argv/返回码JSON在工作区 `/workspace/muyon-contracts-evidence/`，不提交大日志。

| 文件 | SHA256 |
| --- | --- |
| pr119-lifecycle-fixed-red.log | `50327ffca4a7d4c6e13eb72fec58cdc49db66882ee1108ab8141dfea4845ff75` |
| pr119-lifecycle-fixed-red.json | `b0834a4adfd77acf5b94a41a6a68e69bcb74ed2fee5078d111d90cc91a3c47ec` |
| pr119-lifecycle-green.log | `365b3a808001fca74390a7006af895de04f721e8701542a52ea4b65bfd7d2923` |
| pr119-lifecycle-green-ten.log | `7c4d5bd392bb978ee7401959005ed16c6c3aee214d3587bddee3d1966c080a40` |
| pr119-focused-final.log | `fa3ae3b2411043f873f48997e10a380c5f9ec33f6cf823e5ea9f716f3b215b34` |
| pr119-focused-final.json | `52f9ea04dc18234d810e89625199ce89623e39f165d2fb39d215a806f0794c92` |
| pr119-workspace.log | `0eb93c6bd5a4973f97ba0c71c83ce4347491c803f22802c47364e94a29ed0a50` |
| pr119-workspace.json | `fc2df29b9d67c130de369ca0020d14593cd49f36cb539986ee8a2b37ba1b33eb` |
| pr119-clippy.log | `6d2be5c70e4dc3bd3a6fdea135d68e1dc6542cb58d75adcd774e4173cdc54af6` |
| pr119-clippy.json | `f8eecd0f3bf89a9d378c3ff260de52b99c333c0b6dfde9fe19944b1bca73676c` |
| pr119-independent-review-a12efa63.md | `2c49c4d11578e57b0fd41420facda957fb14e64f32d016d7951ea0056f5dd204` |
