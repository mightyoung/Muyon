# Reader presentation 独立实际 Rust 验收

固定原源 `ee184fc1dd90faf2c3cdd48d735f47274de6d418` 实际行为检查全部通过，scoped fmt 原失败；独立纯格式提交 `dfa63451c0d65417b425f5bf1e92a3b43e0b6052` 全部复跑通过，才关闭该补修源的格式门槛。交接报告输入为 `3ff95947337c85f15ef1f9edcf5d47ad49e14999`，已查其 crates 与固定原源无差异；不借此前版本 PASS 或作者 NOT_RUN。

| 实际源 | presentation | Reader | 完整 core 执行数 | 原六探针 | 新独立探针 | cost | scoped fmt |
|---|---:|---:|---:|---:|---:|---:|---|
| ee184fc1 原源 | 10/10 | 17/17 | 294/294 | 6/6 | 4/4 | 1/1 | exit1，三个文件 |
| dfa63451 纯格式补修 | 10/10 | 17/17 | 294/294 | 6/6 | 4/4 | 1/1 | exit0 |

每组完整 core 为17个测试 binary 加0项 doc-test。library75与worker75的测试名逐项相同，worker嵌入同一源码，不能称为150个独立场景；targeted、cost、external probes也不另算新的产品场景。本轮测试实际UTC为2026-10-22；精确时间、argv、cwd、exit、环境、工具和源码哈希见各 manifest。

## 执行与证据

隔离工作树 `/workspace/Muyon-reader-presentation-verification`，未发现 AGENTS.md。原源干净检出后才测试；全部检查核源码哈希未变。已有 Rust/Cargo1.99.1、已有依赖缓存，SQLite只使用既有临时 linker alias。没有下载、扩大权限、凭据配置、引擎、真实模型/搜索请求或用户文件操作；测试仅其新建临时合成目录。main/develop及owner/group工作树不改。

```sh
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::presentation_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::reader_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::reader_tests::thirty_mib_stream_hash_cost_is_linear_and_chunk_bytes_are_exact -- --exact --nocapture
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core
/tmp/muyon-rust/bin/rustfmt --edition 2021 --check <17个明确源路径，见manifest>
```

环境：PATH前缀 `/tmp/muyon-rust/bin`，CARGO_HOME=`/tmp/muyon-cargo`，CARGO_TARGET_DIR=`/tmp/muyon-document-cargo-target`，RUSTFLAGS=`-L native=/tmp/muyon-native-libs`。外部探针从 cargo `--message-format=json` 确定实际 rlib，经 rustc --test 链接真实core和SQLite；完整源码、extern路径/哈希及每条命令原输出均保存。没有用SQL替代Rust测试。

原输出和标准format-patch逐字节保留，包括尾部空行/context空白；因此full staged diff-check exit2，单独检查报告、JSON、JUnit和harness正文exit0，原结果见evidence-checks.json。

全部原输出、派生JUnit、完整manifest及SHA256SUMS在 [reader-presentation-20261022](independent-verification/reader-presentation-20261022/)。JUnit由实际stdout按binary派生，没有伪造原生JUnit或耗时；fmt失败原diff完整保留。`execution-summary.json`提供执行分解；harness目录保存可审计驱动和探针文本。

## 原两个真实RED仍为GREEN

两组各自真实运行原六个不可删探针。源码补片和synthetic fixture seed的SHA与旧ff3cc实际RED证据逐字节一致，见regression-source-equivalence.json；原59字节成功交付的两条旧日志及此前tail/performance全部哈希均重新核对未变。

BEFORE DELETE ON blob_pins / OLD.kind='reader' 触发真实 grant expires_at_ms='0'；one-shot和raw EOF均断言expiry0、pin0，并真实输出success=false、bytes0，拒交付断言通过。其余grant/epoch/lease/revision/held-file失效四探针仍通过。presentation未把raw EOF改成保留会话。

## 新的四个独立公开API探针

- EOF后推进frame，旧ticket不能read/check/advance/close当前frame；新ticket仍Ready且pin1。同ref重新选择得到新ID，旧ID关闭不会影响新selection。
- 使用真实约1.2秒Render grant，EOF、frame和status均不续grant；35ms后valid_for下降，数据库原expiry逐值不变；睡到原deadline后真实拒check/read、清pin并发失效通知。没有只用手改expires来代替时间到期。
- 连续26次selection，pin始终1；通知溢出clear_all=true、列表≤8，drain后归零且不清除当前合法session，close_all清pin后产生最后通知。
- Loading和Ready两阶段，legacy read_chunk/is_current/close都拒presentation ID，保留合法pin/session；显式presentation关闭才释放。

原作者10项也实际通过：EOF同lease/snapshot、raw兼容、旧generation、授权/epoch/过期/删除、scope/selection、旧revision、idle/absolute期限、短grant、cleanup失败poison重试和通知溢出。四个外部探针是补充失效验证，不声称穷举并发或实际host缓存行为。

## 成本与边界

两组cost原输出均为 `source_bytes=31457280 open_hash_bytes=94371840 backup_open_hash_bytes=94371840 stream_hash_bytes=0`。30MiB原始合成数据480个64KiB chunk逐块相等；真实hash-update计数显示open为3n，stream whole-source hash输入0。原测试实开2个30MiB snapshot、第三个因64MiB单host总payload预算拒绝，pins仍2，随后释放至0。presentation EOF/status/frame检查的无重hash断言亦实际通过。预算67,108,864 bytes是snapshot payload，不是RSS/Android缓存上限，也不是跨host全局上限。

纯格式分支 `task/document-reader-presentation-format-20261022` 的唯一父为ee184fc1。只改documents/mod.rs、reader.rs、presentation_tests.rs；临时旧源运行同一rustfmt，17个显式路径均逐字节比较，只有上述三路径变化。原fmt失败证据、标准format-patch、前后hash/证明在original/format，可由owner仅cherry-pick此纯格式提交；未写owner分支，未改行为或测试预期。

格式后首轮外部探针驱动误共用了临时source/binary路径，两条输出都跑了四项presentation，而不能证明六项transport。两套原日志/manifest完整保留在`*-harness-collision-not-evidence`，明确排除验收和JUnit。修正驱动临时路径后，两套重新编译并依次真实运行6/6及4/4，通过才入上表。没有将该harness错误当产品缺陷或借旧PASS；生产代码不受影响。

## 剩余阻断

本轮没有发现需owner修复的编译/行为错误。core源经独立纯格式补修后通过；owner裸ee184fc1仍有原fmt失败，须owner采用补修或等价格式提交。仅完成core验收，presentation的FFI/native ticket registry、Android PFD/bitmap/cache清除、定时器与后台/scope切换、实际引擎渲染和产品接线仍待各owner实施及整体验收，不称产品可运行。raw桥现有EOF语义不因此改变。

本轮没有运行workspace/FFI全套，也未借旧结果；既有workspace/FFI离线缺anyhow1.0.104缓存阻断保留，不反复下载。没有真实执行网关或exactly-once、自动运行群组等声明。Leader B仍是唯一develop合入执行者。
