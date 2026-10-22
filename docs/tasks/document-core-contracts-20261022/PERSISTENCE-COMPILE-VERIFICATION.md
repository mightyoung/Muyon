# 持久化与尾授权hook独立实际验证 — 测试通过，格式HOLD

精确验证源：`f043c6b9b8d850acb590a9a3e567d1f2634a95cd`（远端task/document-core-contracts-20261022核对一致）。对应生产/测试源：`4c6b706f8cf071b14227c5093f0e0b1d65109f43`；两提交的crates树没有差异，f043仅追加交接/证据文档。

在新detached worktree `/workspace/Muyon-document-persistence` 验证，未找到AGENTS.md。已读PERSISTENCE-REPORT及TAIL-HOOK-HANDOFF。报告仅追加到task/document-core-verification-20261022，没有修改作者生产/测试代码、锁文件、group分支或前验证历史。原工作树及固定源码哈希在所有运行后保持不变。没有真实文档引擎、真实用户文件或业务存储操作；Rust持久化测试只对自己创建的临时目录、合成字节和SQLite夹具执行。

## 实际命令与结果

使用已有工具链与依赖缓存，无下载/安装/凭据/权限变化。PATH前缀`/tmp/muyon-rust/bin`，CARGO_HOME=`/tmp/muyon-cargo`，CARGO_TARGET_DIR=`/tmp/muyon-document-cargo-target`，RUSTFLAGS=`-L native=/tmp/muyon-native-libs`。精确argv、UTC起止、退出码、工具/源/锁文件哈希及原始输出见 [manifest](independent-verification/persistence-20261022/manifest.json)。所有cargo测试均`--offline --locked`。

| 命令（共同前缀cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core） | 实际结果 | 原始输出 |
|---|---|---|
| `--test document_storage` | PASS exit0；15 passed，0 failed/ignored | [stdout](independent-verification/persistence-20261022/storage-targeted.stdout.log)、[stderr](independent-verification/persistence-20261022/storage-targeted.stderr.log) |
| `--lib documents::storage_tests` | PASS exit0；3 passed，18 filtered out | [stdout](independent-verification/persistence-20261022/tail-hook-targeted.stdout.log)、[stderr](independent-verification/persistence-20261022/tail-hook-targeted.stderr.log) |
| `--test documents` | PASS exit0；18 passed，0 failed/ignored | [stdout](independent-verification/persistence-20261022/contracts-targeted.stdout.log)、[stderr](independent-verification/persistence-20261022/contracts-targeted.stderr.log) |
| 完整muyon-core package（无额外过滤） | PASS exit0；17测试二进制，共183 passed，0 failed/ignored，另0项doc-test | [stdout](independent-verification/persistence-20261022/core-full.stdout.log)、[stderr](independent-verification/persistence-20261022/core-full.stderr.log) |
| `/tmp/muyon-rust/bin/rustfmt --edition 2021 --check`（documents目录全部7个.rs及documents.rs/document_storage.rs共9文件） | FAIL exit1；7个不同文件有格式差异 | [stdout](independent-verification/persistence-20261022/scoped-fmt.stdout.log)、[stderr](independent-verification/persistence-20261022/scoped-fmt.stderr.log) |

183是这次full-core运行的测试执行数，不是183个独立业务场景。15项集成、3项hook与18项旧合同已包含其中，targeted重复执行不相加；hook过滤掉的18项也不计为执行通过。转换脚本实际核对各targeted测试名均被full-core覆盖。没有嵌套测试binary在本报告中另计成新的场景。

## 结论与交回作者项

1. 当前固定源实际编译成功、所有上述行为测试通过，没有复现此前sha2 digest整体LowerHex编译问题。本结论仅证明本次新源的实际编译/测试，不能抹掉父侧曾捕获的旧编译失败，也不能追认作者NOT_RUN时的RED/GREEN或TDD。
2. **格式门槛未关闭，交回作者处理；本验证者未代修。** 失败文件：`documents/annotation.rs`、`capability.rs`、`identity.rs`、`mod.rs`、`storage.rs`、`storage_tests.rs`、`tests/document_storage.rs`。两文件anchor.rs与旧tests/documents.rs在本次scoped检查中没有差异。原始完整formatter diff与[去重路径列表](independent-verification/persistence-20261022/format-diff-paths.json)均保存。
3. 新增三个尾授权unit测试实际执行：自身CAS后原grant可尾检查而旧head读取被拒；撤权/过期/generation/epoch/项目删除/错误operation被拒；外连接事务及错误文档绑定被拒。集成测试的save/delete尾过期触发器回滚测试通过，不能因此宣称完整网关回执原子性已组合验收。
4. 保留编译警告：既有core-agent-lab的read/write C声明两条警告，以及本slice的`document_access_in_transaction`/`document_grant_in_transaction`在普通lib构建未被生产调用的dead_code警告。没有抑制lint、加`allow`或修改文件。未接线事实不能由unit测试使用hook替代。
5. 按授权没有重试workspace旧anyhow离线依赖缺口、没有下载依赖或改权限。本次full只指muyon-core package，不是完整FFI workspace；此前52个未改workspace格式问题不被本报告豁免。作者新源格式问题需新SHA再验。

## 证据与剩余能力边界

所有本次原stdout/stderr均保存在独立新目录 [persistence-20261022](independent-verification/persistence-20261022/)，JUnit是从原始libtest输出派生的XML，非原生runner结果。旧合同及前两轮证据/哈希清单不变。本批新`SHA256SUMS`独立覆盖所有其他新证据文件（自身除外）；从该目录执行`sha256sum -c SHA256SUMS`。原始工具输出空白按字节保留；全量和排除原始.log后的diff检查分别留证。

仍没有文档引擎、native格式编辑/渲染、真实用户文件、可信actor/group来源适配、字节交付/派生缓存授权接线、总磁盘配额、历史压缩/保留政策或端到端网关回执组合证据。行/JSON读取限额不等同总存储有界。持久化单元/集成夹具通过不使这些门槛自动关闭。

main/develop未改、无合并/部署/付费/真实模型或搜索请求/历史unknown重试/预占释放；现有Leader B仍是唯一develop合入者。当前结论是“新源编译和测试通过，格式仍HOLD，生产集成未验收”。

## 后续七文件格式补修闭环

本页f043固定源的格式失败历史保留。作者新源 `f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac` 已独立确认只含预期七文件格式变动，并实际复验scoped fmt exit0、持久化15/15、hook3/3、旧合同18/18、完整core183/183通过。仅关闭本批格式门槛，可作为父侧网关组合验证输入，不能当作已整合。见 [PERSISTENCE-FORMAT-RECHECK.md](PERSISTENCE-FORMAT-RECHECK.md) 及其新分目录原始证据/SHA256SUMS。既有workspace、TDD历史和生产边界不变。
