# Durable save preparation独立真实Rust验证

Owner固定源：`098d9aca214e6642c1b3ffde64921ebedbae335d`。普通merge到原独立验证分支后的实际组合：`b0d3d952355e4f0ed6547b5a25acd7f8787b64a8`。组合对owner的生产代码差异仅core lib.rs已有的一行`pub mod bot_drafts;`；旧19/202、原14失败证据与历史都保留，不用于本次新状态机验收。

源仍锁定owner的UI98baa979223d96094f11a56c3ac6d48f9b84c0eb与document coref4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac，不含B405/新candidate/Host的整体组合。已读SAVE-PREPARATION-REPORT和单数文件名SAVE-PREPARATION-INTERFACE.md，未发现AGENTS.md。只在task/local-workspace-bot-provider-verification-20261022开发验证材料/授权纯格式补修，未写owner、main/develop、group或原document验证分支。

## 两轮实际命令/结果

使用已有Rust1.99.1工具链与缓存，所有cargo均--offline --locked，无软件/依赖下载、凭据或权限变化。PATH前缀/tmp/muyon-rust/bin，CARGO_HOME=/tmp/muyon-cargo，CARGO_TARGET_DIR=/tmp/muyon-document-cargo-target，RUSTFLAGS=-L native=/tmp/muyon-native-libs。

| 实际命令 | 原组合b0d3 | 纯格式组合111e（下节） |
|---|---|---|
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test bot_drafts` | exit0，26/26 | exit0，26/26 |
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-android-ffi --lib local_draft_bridge_tests` | exit101，缺anyhow1.0.104离线缓存，未编译/执行 | 同一精确缓存阻断，未编译/执行 |
| scoped rustfmt --edition2021 --check（bot_drafts.rs、其tests、FFI lib.rs） | exit1，三文件差异 | exit0，stdout/stderr空 |
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core` | exit0，209次执行通过、0失败/忽略 | exit0，209次执行通过、0失败/忽略 |
| 工作树外独立core-API探针3项 | exit0，3/3 | exit0，3/3 |

精确argv/cwd、实际UTC起止/退出码、环境与工具/源/锁文件哈希见[original manifest](independent-verification/save-preparation-20261022/original/manifest.json)、[formatted manifest](independent-verification/save-preparation-20261022/formatted/manifest.json)。FFI是实际尝试后缺缓存，不是Rust1.91不足；现有1.99.1未克服未缓存依赖。未用SQL检查、formatter解析或core通过冒充两个新native consumer测试通过，也没有生成其成功JUnit。

209是full-core执行数，已含provider26，不相加成235。library/worker直接编入的18个同源测试也在其中重复执行；各轮binary-overlap.json及按binary classname的派生JUnit明确记录。新旧轮次和3项外部诊断也不能叠加成更多独立业务场景。原始stderr保留既有警告，未禁用lint或执行cargo fix。

## 纯格式提交与交回方式

确认原组合26/core209和外部探针3项均通过、只有格式问题与既有FFI环境缺口后，按本轮授权生成唯一纯格式提交：

`111e51178645bdcf147a8a24a0caf3a76755db39`

父为b0d3，只改core bot_drafts.rs、其测试文件与FFI lib.rs，准确等于在/tmp临时副本运行原工具链rustfmt的输出；无逻辑/测试预期/ABI设计/核心export变更。前后SHA、命令时间与三文件逐字节对应在[format-proof.json](independent-verification/save-preparation-20261022/format/format-proof.json)，标准format-patch原样保留。owner可只cherry-pick这一提交；验证者不写owner分支。它不含B负责的export或host/bindings适配。

对该精确提交重新编译、运行26/core209与独立探针3项，并实际scoped fmt exit0后，才关闭补修组合的Rust行为/格式门槛。owner裸098原格式失败仍是原事实，不追认为098自身已过fmt。

## Lookup是和解写入：竞争/迟到的独立探针

除实际owner26项外，在/tmp复制其原fixture源码，追加3个诊断函数；没有修改owner实现或测试期望。直接链接cargo离线生成的真实muyon_core rlib及sha2/serde_json，保留artifact-build原始JSON、精确extern路径/二进制hash、探针源码文本、rustc命令与实际输出。

1. Lookup先到：先断言SQL journal=prepared，调用lookup后另一个真实连接读到not_committed；原始save（不经自动prepare helper）返回local_draft_terminal，stored_revision仍0、无save receipt；重复lookup稳定。它是修改终态的事务，**不是纯read**。
2. Save先到：原始save先提交，lookup得到完全相同的原回执；以后新B save后，查询旧A仍是export17/editor42，不替换为新18/43、也无saved布尔值。
3. 两线程Barrier同时起跑，在同一Arc<Mutex<BusinessStore>>消费者序列化边界竞争save与lookup，32次/轮。只允许committed+同一回执，或not_committed+save被terminal拒绝，且重复lookup稳定、迟到save不能跨越terminal fence。原轮观察committed0/fenced32；格式轮committed3/fenced29，两轮全部断言通过。

前两项确定性探针分别覆盖两个顺序，第三项是真实有限线程竞争；调度分布不是formatter效果、性能结论或穷尽所有交错。该mutex/core API诊断**不等于未编译的ProductCore/UniFFI或Android消费者验收**。host仍必须以同一reducer/scope/export/editor快照匹配回执，不能把此证据当作UI晚回调已正确处理。

新core26实际覆盖冷启save_attempt精确指针、未prepare拒绝、prepared时新attempt阻断、旧save迟到封口、legacy无journal回执、receipt/pointer/terminal journal故障回滚等。原schema1和原unknown/reserved合成账本断言通过；不触真实两次unknown/预占。

## 仍未闭合

FFI2、第五方法真实binding生成、Host strict codec/prepare-before-save/discovery/outcome消费者、晚回调UI、Android与Leader B整体组合均未由本任务验收。verified/can_save不能因本轮core通过开启。lookup返回not_committed后只允许新的显式用户保存；不重放发现的旧attempt，也不以missing receipt单独推定未提交。

没有用户文件、实际业务存储、文档引擎、模型/搜索、部署/付费、权限/凭据、历史unknown重试或预占释放。所有SQLite/fs操作仅原创临时测试夹具。原NOT_RUN/TDD历史不改，不把新绿追认为原先RED/GREEN。Leader B仍唯一合入执行者。

证据在新save-preparation-20261022分目录独立封存，原始stdout/stderr按字节保留，JUnit只是实际libtest输出派生，FFI不虚构结果。SHA256SUMS不含自身；旧14失败和19/202证据清单保持有效。

封存空白检查：全staged diff-check exit2；仅排除原始.log仍因标准format-patch空白上下文/邮件签名exit2；排除原始.log与该patch后的编写文件检查exit0，纯格式提交本身git show --check也exit0。原字节保留，不修剪证据制造全绿，四项原命令/输出在whitespace-check.json。
