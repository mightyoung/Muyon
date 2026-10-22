# Provider独立实际Rust验证 — BLOCKED/FAIL，交回owner

精确provider：`7ca2bd4e9edf9cd0952ce784d3f85561583537db`，远端核对一致。其固定依赖UI=`98baa979223d96094f11a56c3ac6d48f9b84c0eb`、document core=`f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac`；已核实二者均为provider祖先。provider合依赖的merge为`4285e509e2228a846a1961f293458b1e0a1c1b79`，父提交恰为上述UI/core，不引入其他新core/COPY或Bot组合。

本次仅为消费者验证，在新worktree `/workspace/Muyon-bot-provider-verification`、独立分支`task/local-workspace-bot-provider-verification-20261022`进行。未发现AGENTS.md；已读作者REPORT/INTERFACES/PLAN/CORE-EXPORT.patch。作者分支、主分支、group和原document验证分支未修改；整体组合仍归Leader B。

## 验证专用唯一导出组合

原provider不导出bot_drafts，本次依照明确授权先对其原CORE-EXPORT.patch执行`git apply --check`，再原样应用，唯一差异为core lib.rs添加`pub mod bot_drafts;`。

验证专用导出提交：`1e81e19c170bf65aa01923b082a2175f5009490c`，唯一父提交是固定provider7ca2。实际编译/运行的source正是此完整提交，而非裸provider。这个导出只用于本验证，不是core owner已集成、UI can_save已可用或宿主canonical adapter已完成的声明。

没有改provider实现、测试预期、FFI实现、documents、依赖或锁文件。因为出现真实行为失败，不满足“仅fmt差异”的条件，本轮**没有创建纯格式补修，也没有擅修行为或写作者分支**。

## 实际命令与结果

仅使用已有Rust1.99.1工具链（含Cargo/rustfmt）和缓存。精确版本以[manifest](independent-verification/original/manifest.json)为准；现有Rust高于1.91，不能把实际FFI缺缓存误说成Rust版本不足。PATH前缀`/tmp/muyon-rust/bin`，CARGO_HOME=`/tmp/muyon-cargo`，CARGO_TARGET_DIR=`/tmp/muyon-document-cargo-target`，RUSTFLAGS=`-L native=/tmp/muyon-native-libs`。均离线、锁依赖，不安装/下载、不扩权限。

| 实际命令 | 实际结果 | 原始输出 |
|---|---|---|
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test bot_drafts` | **FAIL exit101**，实际编译后执行15项：1 passed、14 failed | [stdout](independent-verification/original/provider-targeted.stdout.log)、[stderr](independent-verification/original/provider-targeted.stderr.log) |
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-android-ffi --lib local_draft_bridge_tests` | **BLOCKED exit101**，缓存缺anyhow1.0.104，未编译/执行FFI测试 | [stdout](independent-verification/original/ffi-targeted.stdout.log)、[stderr](independent-verification/original/ffi-targeted.stderr.log) |
| scoped `rustfmt --edition 2021 --check`（bot_drafts.rs、tests/bot_drafts.rs、FFI lib.rs） | **FAIL exit1**，三文件都有格式差异 | [stdout](independent-verification/original/scoped-fmt.stdout.log)、[stderr](independent-verification/original/scoped-fmt.stderr.log) |
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core` | **FAIL exit101**，到失败处实际执行118项：104 passed、14 failed；后续套件没有执行 | [stdout](independent-verification/original/core-full.stdout.log)、[stderr](independent-verification/original/core-full.stderr.log) |

每进程实际UTC起止、完整argv、cwd、退出码、显式环境字段、工具二进制/源码/锁文件哈希均已保存。targeted15已包含在partial core118内；同14个失败重跑一次不算28个独立失败。不把之前document core183通过、未运行的后续套件、FFI依赖失败或Python SQL smoke当作这个组合通过。

## 阻断发现：新空草稿首次resolve被误判corrupt

14个失败均在第一次`resolve`遇到`Err("local_draft_corrupt")`而unwrap panic。通过的仅是partial_schema_never_resets_or_imports负例，不能据此接受provider保存功能。

定位依据（代码未修改）：

- `bot_drafts.rs:196–207`为新draft插入stored_revision='0'、archive_hex=NULL、archive_digest=NULL，随后调用record。
- `bot_drafts.rs:156`的有界投影`CASE WHEN LENGTH(archive_hex)<=65536 THEN archive_hex ELSE 'oversize' END`在archive_hex=NULL时条件不是true，返回字符串oversize。
- `bot_drafts.rs:169–174`仅接受revision0时archive/digest同时None；实际投影为Some("oversize")/None，进入corrupt分支，导致所有正常resolve初始路径失败并回滚。

附加[只读内存SQL诊断](independent-verification/null-projection-diagnostic.json)实际得到`["oversize", null, 0]`，支持上述定位；它是Python SQLite3.53.1语义诊断，**不替代真实Rust失败、也不代表FFI/端到端接受**。回原owner修复新空草稿NULL投影/解码语义，并保留真实oversize与tamper fail-closed边界；验证者没有应用任何逻辑修正或改测试期望。

由于初始化即失败，多数保存、回执、CAS、scope、容量和canonical archive断言尚未走到；不能从本次失败外推这些后续路径已通过或已发现另一个具体缺陷。owner修复后需新固定源重新实际验证。

## 封存和边界

所有实际stdout/stderr保留在新目录independent-verification/original；JUnit由原始libtest输出派生，保留14个failure节点，不是原生runnerXML。FFI没有虚构JUnit或成功。转换脚本/摘要也保存，记录core提前终止。证据SHA256SUMS独立封存，排除自身；从目录运行sha256sum -c SHA256SUMS。

原代码source哈希在运行后不变。仅原来的导出验证提交改core lib.rs一行；后续提交只加报告。原始工具输出及补丁字节不改，空白检查单独记录。现有编译警告保留，没有禁用lint。

没有SQL smoke代替Rust、没有实际业务/用户文件写入、第三方引擎、真实模型/搜索、历史unknown重试、预占释放、main/develop操作或部署/付费。所有持久化测试只用临时合成夹具。作者NOT_RUN/TDD历史仍保留，真实运行的新FAIL不能被静态复审或旧证据覆盖。总体HOLD，不能启用can_save、声明FFI/Kotlin/Android集成或自动保存已验收。

JUnit转换器首轮对并行测试输出做了失败名列表顺序比较，因两次运行顺序不同而assert失败；已保留其实际stderr/退出码，改为集合相等后生成摘要。原Rust测试/预期/日志未改变；该转换器修正不掩盖14项真实失败。

封存后的全量staged diff-check exit2来自原始测试/formatter日志空白，保留原字节；排除本批原始.log后的编写文件检查exit0，精确命令/输出在whitespace-check.json。导出验证提交本身仅一行且diff-check通过。
