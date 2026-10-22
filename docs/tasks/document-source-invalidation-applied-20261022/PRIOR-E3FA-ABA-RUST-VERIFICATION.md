# 已应用来源失效修复：旧三项GREEN，同批generation复用新RED

实际锁定源码 `e3fa0ee71f071bb8cff667d50ee1c0da6827a7c9`，报告输入 `d646e3412063e6e30901cfc6257719a3f3256850`，基线 `662aeec6d6462cabfcc317e855ae23797dd88d51`。报告提交与源码的crates差异为空；本轮直接编译真实已应用源码，不再应用旧docs patch或拼接缺失owner模块。

旧三项触发器RED原样在新源真实GREEN；新20项和关联library测试通过。**同批通知generation复用已真实复现新RED，旧ACK能吞新事件；完整core另exit101编译失败，scoped fmt exit1，workspace离线缺依赖。整体不能验收。** 作者尚未运行的旧test-only源ed1c4eff，本线程没有运行，不追认blob/ACK新增测试为旧源实测RED。

| 实际检查 | 结果 |
|---|---|
| --lib documents::source_notification_tests | 20/20，exit0 |
| --lib artifacts:: | 41/41，exit0 |
| --lib documents::reader_tests | 17/17，exit0 |
| --lib documents::presentation_tests | 10/10，exit0 |
| --lib 全套 | 182/182，exit0 |
| 旧三RED原样重跑 | 3/3 GREEN，真实编译/执行均exit0 |
| 补充独立正常路径及blob/ACK探针 | 6/6，真实编译/执行均exit0 |
| 新独立同批通知ABA探针 | 编译exit0，执行exit101，0通过/1真实失败 |
| 旧Reader六探针 | 6/6，exit0，含两项cleanup-tail回归 |
| -p muyon-core 全包 | exit101，嵌入harness编译失败，无完整套件执行 |
| 五路径 scoped fmt | exit1，mod/storage/source_notifications/source_notification_tests四路径失败；blobs未失败 |
| --workspace | exit101，离线缺anyhow1.0.104；workspace测试未执行 |

各target和library全套有重复执行，不能相加为独立场景数；182是library，不是完整core。旧patch727计数不跨源借用。

## 精确环境及执行命令

新隔离工作树 `/workspace/Muyon-source-invalidation-applied-verification` 干净检出，未发现AGENTS.md。验证前后全部core源码hash重查一致，工作树仍干净。基线到新源仅5生产/测试文件变化，未改lib.rs、owner artifacts/evidence、harness或其他分支；真实resolver local_sources.rs SHA256为 `52b3a4e9eda179d43535218da7452dc68ad98a8c6635e582678399d0b6b3e364`。

仅使用本验证环境已有Rust/Cargo1.99.1和缓存。PATH前缀=/tmp/muyon-rust/bin，CARGO_HOME=/tmp/muyon-cargo，CARGO_TARGET_DIR=/tmp/muyon-document-cargo-target，RUSTFLAGS=-L native=/tmp/muyon-native-libs。没有访问或重试作者被拒的/root/.cargo/bin，没有扩权限、配置凭据、安装/下载软件或依赖。

```sh
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::source_notification_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib artifacts::
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::reader_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::presentation_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib
cargo test --offline --locked --manifest-path crates/Cargo.toml --workspace
rustfmt --check --edition 2021 --config skip_children=true crates/muyon-core/src/blobs.rs crates/muyon-core/src/documents/mod.rs crates/muyon-core/src/documents/storage.rs crates/muyon-core/src/documents/source_notifications.rs crates/muyon-core/src/documents/source_notification_tests.rs
```

原始argv/cwd/UTC起止/exit、完整stdout/stderr、源码和工具哈希、实际rlib路径与hash、探针完整文本和驱动均在[证据目录](independent-verification/)。派生JUnit仅记录实际执行的测试；core/workspace失败命令以0项测试和exit101/NOT_RUN properties及原stderr保留，不制造测试失败或把未执行算PASS。原先67337d3f证据61项哈希均重新核对不变。

## 原三RED原样到GREEN

`final-provenance.json`核对原三项附加探针SHA与旧实际RED证据完全相同，无改期待结果、删断言或放行stub。与旧批次相同的真实SQLite schema和原API，在新源输出：

- 恢复grant触发器：revocation_ok=false，grant_active1、source_active1、queue_pending0、authorized_read_ok=true。active1和仍可读来自**完整回滚至原授权**，不是撤权成功后被触发器恢复。
- 删除notification触发器：revocation_ok=false，source_active1，queue_pending0。
- pending置0触发器：revocation_ok=false，source_active1，queue_pending0。

这三项真实拒绝关闭对应旧patch的已复现漏洞；不能代替完整core接线验收。旧67337d3f三个失败原输出仍保留，不改为历史PASS。

## 新RED：同批generation必须写前全冻结

真实resolver绑定object和object-z，第一轮revoke两者均生成generation1，ACK后保留两墓碑。重新issue grant并bind两者后，安装AFTER UPDATE通知触发器：WHEN NEW.object_id='object'时按同project/actor删除object-z墓碑。第二轮revoke的object更新为gen2时触发删除，后续object-z重新使用gen1，提交尾部检查仍允许成功。

独立Rust探针已编译成功并实际输出：`second_revoke_ok=true old_z_generation=1 new_z_generation=1 stale_z_ack_count=1 pending_after=[("object", 2)]`。旧object-z/gen1 ACK吞掉新object-z事件，期望ACK计数0的断言真实失败。原stdout/stderr和完整source在original/aba-probe，派生JUnit含该真实失败；不是编译失败、SQL模拟业务或不适用schema。此项尚未修复，不能用旧三GREEN、owner20 PASS或library182关闭。需要owner对同批全部目标状态在任何写入前冻结并另锁新SHA复验，本线程未改语义。

父另指出gateway在clone检查后写committed receipt，其触发器可能删通知或预ACK；该真实gateway路径由另一owner验证，本线程NOT_RUN，不能据本次core内COPY通过认定跨gateway事务尾部安全。

## 独立blob/ACK与关联失效探针

新增独立blob探针在真实outbox AFTER INSERT删除 `blob_references WHERE target_id='text-source'`，分别调用真实publish和同事务COPY：二者都拒绝，head仍1/source active1，blob_references全行与原值一致，pending队列为空。没有只查head而漏掉引用事实。

新增独立ACK探针在BEFORE UPDATE按原主键DELETE notification后RAISE(IGNORE)。真实ack返回Err，原pending token/代际完整保留，pending_after=1。另一独立探针实测原事件ack后重新grant/bind/revoke产生更高generation，旧ack返回0且新event仍pending，不能吞新事件。

其余四项正常路径继续实际验证通知SQL错误整体回滚、改绑旧新文档不误伤独立授权来源、事务未提交对另一连接不可见/回滚无事件、未初始化与已安装后缺失或畸形schema区分。测试全部运行真实Rust模块与真实resolver proof，仅合成临时fixture的SQL注入故障，不用SQL代替业务实现。

旧Reader六探针从实际cargo rlib编译执行，one-shot及raw EOF两个触发器cleanup回归仍拒返回bytes，其他grant/epoch/lease/revision/held-file失效通过。Reader17和presentation10本轮分别执行，不借旧计数。未运行引擎、真实模型/搜索/业务文件或Runtime发送。

## 完整core编译阻断及其他剩余项

实际 `cargo test ... -p muyon-core` 编译时，business_worker、group_runtime_store、group_runtime_bridge三套同源码嵌入harness缺少crate::artifacts/crate::evidence：source_notification_tests.rs:3报E0432/E0433；生产source_notifications.rs调用真实invalidate_local_evidence_sources_in_transaction报E0599。各类initialize/resolve/bind方法随之缺失。完整原输出保留，未按编译器提示替换为其他方法或把这些cfg(test)模块关掉。

与旧Reader基线“文件不存在”冲突不同，本源存在group文件，但嵌入crate模块组成尚不完整；library自有真实模块可编译且182通过。需owner/B补准确harness接线后锁新SHA复验，不把library182冒称完整core通过。

独立外部探针首轮准备脚本未识别lib.rs已有的group_runtime_bridge显式path，在rustc之前停止，未运行探针。原artifact-build/commands保留在*-harness-preparation-not-run，脚本仅修正临时映射为实际group_runtime/bridge.rs后重新编译运行，未改生产源码。该harness脚本错误与上述真实完整core编译失败分开记录。

当前全包编译门槛未通过，因此本轮没有纯格式提交；原四文件fmt失败原diff保留。workspace仍受离线anyhow缺口阻断，不下载绕过；strict workspace Clippy本轮NOT_RUN，不借用作者127或既往静态审查结果。Host/Runtime提交后poll/deliver/ack消费、B整体组合及产品接线仍未验收。main/develop、作者与原group工作树保持不动；本轮没有被拒或不确定的执行操作。

原日志和源码diff逐字节保留；full staged whitespace check exit2，报告/JSON/JUnit单独检查exit0（详见evidence-checks.json）。
