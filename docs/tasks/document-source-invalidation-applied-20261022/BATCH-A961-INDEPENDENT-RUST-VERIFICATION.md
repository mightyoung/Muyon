# a961 同批ABA修复独立实际验收

固定源码 `a961bb58c08ce77b559ce0d021d2ed50a857bb9e`，交接报告输入 `b7d5a7a21c4fd28064b916f984aec081c721f3bc`（crates差异为空）。原同批ABA探针和此前三项RED均未改变断言/故障SQL，在本源真实GREEN。24项、关联library全部实跑通过。原源四文件fmt失败，独立纯格式补修 `0fda32e4d41d8e5524d6f7c4d35c467cbb1ba200` 后同范围全部复跑及fmt通过。

| 实际固定源 | authored | Artifacts | Reader | presentation | library全套 | 原ABA | 原三RED | 补充6 | 旧Reader6 | scoped fmt |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| a961原源 | 24 | 41 | 17 | 10 | 186 | 1 | 3 | 6 | 6 | exit1，四文件 |
| 0fda纯格式 | 24 | 41 | 17 | 10 | 186 | 1 | 3 | 6 | 6 | exit0 |

表内各测试命令均exit0、0失败/忽略，分别实际执行；targeted、外部探针与library重复覆盖，不能相加当独立场景。186仅library，不是完整core；没有借旧e3fa182、旧overlay727或此前Reader计数。旧真实RED日志/失败JUnit保持历史状态。

## 独立执行与证据

新工作树 `/workspace/Muyon-source-invalidation-batch-verification`，初始干净检出a961，未发现AGENTS.md；仅在该隔离树新建独立格式分支。main/develop、owner/core/gateway分支及原group工作区不改。

实际Rust/Cargo1.99.1来自既有 `/tmp/muyon-rust/bin`，CARGO_HOME=/tmp/muyon-cargo，CARGO_TARGET_DIR=/tmp/muyon-document-cargo-target，RUSTFLAGS=-L native=/tmp/muyon-native-libs，使用已有SQLite alias和缓存。cargo均--offline --locked。未访问/重试作者/root工具拒绝、下载软件或依赖、配置凭据或扩权限。

```sh
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::source_notification_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib artifacts::
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::reader_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::presentation_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib
/tmp/muyon-rust/bin/rustfmt --check --edition 2021 --config skip_children=true crates/muyon-core/src/blobs.rs crates/muyon-core/src/documents/mod.rs crates/muyon-core/src/documents/storage.rs crates/muyon-core/src/documents/source_notifications.rs crates/muyon-core/src/documents/source_notification_tests.rs
```

两组完整argv/cwd/UTC起止/exit、stdout/stderr、工具二进制和源码/锁文件hash、外部rustc测试源码及实际rlib依赖hash、派生JUnit、SHA256SUMS见[batch-a961证据](independent-verification/batch-a961/)。完整source前后哈希核对成功；原源用a961 Git blob再核对，格式源用实际工作树再核对且干净。JUnit由实际Rust stdout派生，没有杜撰原生JUnit或耗时。

## 原探针原样RED到GREEN的适用范围

final-provenance.json分别核对原ABA、原三触发器、补充六项及Reader六项附加源码SHA，与8caf实际证据相同。probe-source.rs.txt保存每次精确临时crate；这些crate引用当前实际源码模块或当前cargo rlib，没有假hook、SQL重写业务实现或production行为改动。

原ABA仍建立object/object-z两个真实resolver来源；第一轮gen1/ACK后reissue/rebind；object第二轮更新时触发器删除z墓碑，再用旧z/gen1 ACK检测新事件。原先e3fa实际结果是second revoke Ok、z复用gen1、旧ACK计数1；本轮a961及0fda同一个原探针各1/1通过，接受的路径是操作拒绝且完整回滚，或保留更高generation且旧ACK为0。没有弱化为只检查revoke返回值或删掉旧ACK步骤。现有探针的拒绝分支断言队列为空、source active1；通过关闭原已复现同批ABA边界，不声称全部触发器组合被穷举。

原三项恢复授权/删除事件/预ACK注入均得到revocation_ok=false、source_active1、queue_pending0，真实拒绝并回滚，授权原状态未被当作撤权成功。补充六项仍检查blob引用尾部损失时publish和core内COPY拒绝回滚、忽略ACK写不丢墓碑、旧ACK不能吞高代际新事件、事务可见性/回滚、旧新grant来源及未初始化与损坏schema区分。

旧Reader六项中one-shot与raw EOF cleanup两回归仍拒bytes，grant/epoch/lease/revision/held-file失效亦通过。Reader17和presentation10本轮分别执行，包括真实synthetic snapshot成本测试；本报告不另推测手机吞吐、RSS或宿主缓存生命周期。

作者24项也真实运行，包括更早grant/source/binding触发器删除墓碑、同批ABA、publication token后续写破坏队列/source/blob/head时拒绝、同transaction成功和foreign transaction拒绝。opaque token这里只是core事务后置条件接口实测，不等于真实gateway receipt路径已经接通。

## 独立纯格式交付

分支 `task/document-source-invalidation-batch-format-20261022`，提交 `0fda32e4d41d8e5524d6f7c4d35c467cbb1ba200`，唯一父a961。只改documents/mod.rs、storage.rs、source_notifications.rs、source_notification_tests.rs四文件；blobs在本轮scope内本已通过，未修改。

先在旧源的临时副本对相同五路径运行同一rustfmt（skip_children=true），再逐字节应用准确输出。五个文件before/expected/after SHA及全部其他core源/测试字节不变证明、标准format-patch均在format/。未改逻辑/断言/依赖/导出/harness。全部本轮行为套件和旧探针都在该格式commit重新运行，通过后才关闭此补修源格式门槛。owner可仅cherry-pick该独立style commit；原a961 fmt失败仍保留，不追认原源通过。

## 剩余门槛

本轮按父指示不重复执行三套嵌入harness的完整core：business_worker/group_runtime_store/group_runtime_bridge缺实际Artifacts/Evidence组成仍由B接线验收；完整core本轮NOT_RUN，旧e3fa的E0432/E0433/E0599原输出保留。没有删除/关闭test或临时塞导出来制造全绿。

workspace和strict workspace Clippy本轮NOT_RUN；已知离线anyhow1.0.104缺口不反复尝试下载/放宽限制。对应当前source不能借旧失败当作本轮实际命令结果，更不能宣称workspace通过。

真实gateway COPY在clone后仍有receipt/journal写；其owner尚未提供最终固定源，本轮该路径NOT_RUN/HOLD。core24的token末检不能替代gateway消费token后的真实receipt-trigger RED→GREEN；等gateway固定源再组合验证。Host/Runtime提交后poll/deliver/ack、实际通知/缓存清除与产品整合仍待各owner。没有运行真实模型/搜索、引擎或业务文件，没有发布、合入或实际消息发送。

原日志/标准format-patch逐字节保留；full staged whitespace check exit2，报告/JSON/JUnit单独check exit0，原输出见evidence-checks.json。
