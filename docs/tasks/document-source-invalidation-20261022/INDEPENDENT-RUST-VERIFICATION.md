# 来源失效 hook 独立实际 Rust 验证：旧 patch 仍阻断

交付 `36b1e76382a1e1883dcdfd8f337759cb0156007e`，实现patch提交 `b9b18149604bb96d4c3c531e2283764ac4030015`。本次实际运行作者12项、Artifacts41项及完整core727次执行均通过；**新增三项真实故障注入均RED，旧patch不能验收**。这些结果仅适用下述精确overlay，不适用作者后续修复。

## 固定交付组合

按HANDOFF逐字执行prepare_validation.py，在新隔离工作树 `/workspace/Muyon-source-invalidation-verification` 准备：

- 基线 `b4940ddc1600acced5e268053450b48395df93f6`。
- 真实Artifacts/Evidence依赖 `0e85c6e98c4e32efc8008092e480626f342a701d`，使用该commit目录下全部实际blob。
- CORE-SOURCE-INVALIDATION.patch SHA256 `b6ddc8a034e318ef02b641044c19b8b41497bd64a4b3622ec64b148cbf7833a9`。
- UNAPPLIED-B-HARNESS-DEPENDENCIES.patch SHA256 `e94558f71bf732a9ae68fd6eb130c83a8920329f7fdd61c4369a6cd7fa8e064f`。

两个patch均先check再apply成功，四个结果文件hash全部符合交付manifest。lib.rs字节仍与B基线相同，测试后全源码hash重查未变；没有在owner分支应用生产代码。实际SOURCE-INVALIDATION-MANIFEST、准备命令和原始stdout/stderr、交付patch及HASH均保存在[证据目录](independent-verification/)。查找未发现AGENTS.md。

## 实际命令和结果

| 命令范围 | 实际结果 |
|---|---|
| --lib documents::source_notification_tests | exit0，12/12 |
| --lib artifacts:: | exit0，41/41 |
| -p muyon-core，全包 | exit0，727通过/0失败/0忽略 |
| 独立正常路径补充 | 编译exit0，4/4 |
| 独立触发器故障注入 | 编译exit0，执行exit101，0通过/3失败 |
| 作者四路径 scoped rustfmt | exit1，四路径均需格式化 |
| --workspace | exit101，离线缺anyhow1.0.104，未编译执行workspace测试 |

```sh
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::source_notification_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib artifacts::
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core
rustfmt --check --edition 2021 --config skip_children=true crates/muyon-core/src/documents/mod.rs crates/muyon-core/src/documents/storage.rs crates/muyon-core/src/documents/source_notifications.rs crates/muyon-core/src/documents/source_notification_tests.rs
cargo test --offline --locked --manifest-path crates/Cargo.toml --workspace
```

实际工具路径前缀 `/tmp/muyon-rust/bin`，Rust/Cargo1.99.1，CARGO_HOME=/tmp/muyon-cargo，CARGO_TARGET_DIR=/tmp/muyon-document-cargo-target，RUSTFLAGS=-L native=/tmp/muyon-native-libs。只用既有工具链/依赖缓存及SQLite动态库alias，不下载软件或依赖、不配置凭据/扩权限。原warning保留，未修改基线lint。实际UTC起止、完整argv/cwd/exit、源码和工具二进制hash见original/manifest.json、各probe/commands.json、final-provenance.json。

727是29个test binary的成功执行数，另doc-test0；library147、worker113及group_runtime_store160内有嵌入同源码模块的重复测试，不能当727个独立场景。library还输出被故意kill的真实子进程“running 1 test”，没有独立成功result，不另加1；JUnit按每个实际成功/失败result与binary对应。派生JUnit不是cargo原生JUnit，没有杜撰时间。targeted重复检查不再另算独立场景。

## 三个实际RED：触发器改写提交尾部事实

准确SQL注入和Rust测试完整源在original/independent-probes/probe-source.rs.txt；实际模块均以绝对path引用本次overlay，不是SQL重写业务逻辑或假hook。临时crate仅新增合成fixture与测试，用cargo实际依赖artifact的rlib编译；原模块源码不改。三个测试分别真实调用 `revoke_document_grant_trusted`，以下均为原stdout事实：

1. AFTER INSERT ON document_source_notifications_v1 执行 `UPDATE document_grants SET active=1 WHERE grant_id='source-grant'`。实际 `revocation_ok=true grant_active=[[Some("1")]] source_active=0 queue_pending=1 authorized_read_ok=true`。撤权被恢复且授权读取成功，但原撤权返回Ok；“应Err并rollback”断言失败。
2. AFTER INSERT 按NEW.project_id/actor_id/object_id删除该notification。实际 `revocation_ok=true source_active=0 queue_pending=0`。源失效已提交而必须的通知丢失，拒绝断言失败。
3. AFTER INSERT 按NEW主键将pending=0。实际同为 `revocation_ok=true source_active=0 queue_pending=0`，没有Runtime投递就被预先ack，拒绝断言失败。

三个都是编译成功后真正运行至业务返回/数据库检查的失败，非harness编译失败或不适用schema。原12 PASS不能覆盖末尾事实被改写的问题。父已告知owner修复；本轮不修改行为，也不将后续修复推测为GREEN。修复必须锁新SHA复跑相同三个原RED及关联套件。

## 四个独立正常路径补充

另一个独立测试文件4/4实际通过：

- BEFORE INSERT通知故障RAISE(ABORT)，真实撤权返回Err，原grant仍可读、source active1、手工字段原字节不变、队列为空，事务回滚完整。
- 同项目另一真实Text文档有独立grant及resolver proof；原grant ID改绑新文档后，旧文档来源失效并排队，新文档独立grant来源保持active1/可读，不误伤无关有效授权。
- clone事务未提交时另一连接不可见通知，trusted poll嵌套调用拒绝；drop事务无队列或源失效。正式撤权提交后可poll，第一次ack后重新绑定/撤权生成更高generation，旧ack返回0且新事件仍pending。
- 全未初始化namespace保持兼容且不创建通知表；安装marker后source缺失或畸形schema拒撤权，原授权事实保持，区分未初始化与损坏。

这些只是正常错误传播、身份和outbox边界补充，不能抵消上述提交尾部RED。没有运行实际Runtime投递、发送真实消息或模拟exactly-once。

## Reader组合阻断与剩余项

HANDOFF的精确B基线不含Reader模块，故此727不能继承旧Reader PASS。在另一新隔离工作树以作者指定Reader `4c9072af48d7a6eceb9abb70594b03ab4bc412be` + 相同真实依赖blob准备补充组合，core patch check/apply成功；harness patch --check exit1，确切输出：`error: crates/muyon-core/tests/group_runtime_store.rs: No such file or directory`。

整个harness patch未应用，Reader组合未编译/运行；部分准备状态保留在 `/workspace/Muyon-source-invalidation-reader-verification`，原check日志在reader-composition/。没有手工挑hunk、绕冲突、增加导出或移植无关B文件。早先进度提及两个harness目标，最终实际错误仅是上述缺失文件，不能记为business_worker冲突。需owner提供匹配Reader基线的准确依赖/组合交接后继续。

没有纯格式提交：当前行为RED仍开放；原四文件格式门槛也保留失败。workspace离线依赖缺口保留，不反复下载或放宽限制。Host/Runtime提交后poll/deliver/ack消费、真实Reader组合、B整体接线与最终合入均未验收；Leader B仍唯一develop合入者。main/develop/owner/group工作区不动，没有引擎、真实模型/搜索或用户文件操作。此次没有被拒或不确定的写操作。

原输出/标准patch逐字节保存，full staged diff-check exit2（原日志尾部空行、patch空白）；报告/JSON/JUnit单独check exit0，见evidence-checks.json。
