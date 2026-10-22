# Provider NULL修复独立Rust复验

精确owner新源：`3160208247c5257b6382106d69f2028f5ad8ccab`，已核远端task/local-workspace-bot-provider-20261022一致。原源7ca2的14项真实失败、FFI缺缓存、格式失败及原manifest/JUnit/SHA清单都保留；未用新绿覆盖旧RED，也不追认作者原NOT_RUN的RED/GREEN/TDD。

本次在同独立验证分支`task/local-workspace-bot-provider-verification-20261022`普通merge新owner固定源，保留先前唯一导出及验证历史，没有写作者分支或整体集成分支。**实际测试组合commit：`f0ef760ba7253f38be8e26989ca99b82a76acf8b`**，两父为上次验证`fda22f1876393b390e73591ffbf5991e686c8ef6`与owner修复`3160208247c5257b6382106d69f2028f5ad8ccab`。

`git diff 3160208 f0ef760 -- crates`恰好core lib.rs新增一行`pub mod bot_drafts;`；provider实现/FFI/测试均与owner3160208逐字节一致，没有验证者行为修改。该导出仍仅用于本次消费编译验证，不等于core owner整合或UI can_save已启用。固定依赖保持UI98baa979223d96094f11a56c3ac6d48f9b84c0eb与coref4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac，没有带入其他COPY/网关组合。

已读NULL-PROJECTION-FIX.md。使用原worktree、现有Rust工具链/依赖缓存/临时SQLite链接配置，无安装/下载/凭据/权限变化；测试仅操作其自建合成临时业务数据库与原始夹具，不读写真实用户文件或业务。

## 新组合的实际命令

```sh
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test bot_drafts
/tmp/muyon-rust/bin/rustfmt --edition 2021 --check crates/muyon-core/src/bot_drafts.rs crates/muyon-core/tests/bot_drafts.rs crates/muyon-android-ffi/src/lib.rs
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core
```

本轮实际stdout/stderr、UTC起止/退出码、完整argv/cwd、显式环境、工具二进制与源码/锁文件哈希见 [新manifest](independent-verification/null-fix-20261022/original/manifest.json)。PATH前缀`/tmp/muyon-rust/bin`，CARGO_HOME=`/tmp/muyon-cargo`，CARGO_TARGET_DIR=`/tmp/muyon-document-cargo-target`，RUSTFLAGS=`-L native=/tmp/muyon-native-libs`。

新输出在`independent-verification/null-fix-20261022/original/`，与父目录原14失败的`independent-verification/original/`严格分开。派生JUnit不是原生runnerXML，不伪造缺失的FFI结果。没有复跑已知离线anyhow依赖缺口，也不把旧FFI退出101当成本新源已执行FFI。

## 新组合结果

- Provider targeted：**exit0，19 passed / 0 failed / 0 ignored**，实际Rust编译和行为执行。
- Scoped fmt：**exit0**，三个文件stdout/stderr均为空，无需也未创建纯格式补修。
- 完整muyon-core package：**exit0，202 passed / 0 failed / 0 ignored**，18个测试二进制，另0项doc-test；19项已包含其中，重复执行不相加成独立业务场景。
- 所有provider/FFI源码、测试与锁文件在运行后哈希不变，仍精确对应owner316加唯一export。旧警告原样保留，未改lint。

因此原初始NULL投影阻断在这个固定Rust组合上闭合，三文件格式门槛通过；旧14项真实失败留作历史，不改成当时已通过。对FFI没有新执行/成功声明。

## 关闭范围与保留的门槛

本次验证的是owner316修复源加唯一导出的Rust行为和scoped格式，不是完整产品/FFI/Kotlin/Android或Leader B整体组合。即使本轮Rust全绿，canonical Kotlin恢复语义、宿主晚回执/同editor匹配、真实scope adapter及native bridge仍需整合验收；不能据此打开can_save。

旧14个失败的来源是初始NULL投影，修复后新增回归覆盖空archive/read/重启、NULL与非TEXT/字节超限/嵌入NUL、回执digest/JSON存储类型和大UTF8 canonical archive。实际新测试结果仅支持已断言的路径，不证明全数据库对抗性回滚或数据认证。provider仍为local_workspace、editing_only，不发任务、不创建已运行Bot或外部授权。

FFI旧缓存缺口、workspace未完整测试、原NOT_RUN/TDD历史、真实模型/搜索/费用unknown以及生产能力边界不变。没有真实请求、历史unknown重试、预占释放、部署/付费、main/develop或group改动；Leader B唯一合入职责保持。

新证据由本分目录SHA256SUMS独立封存（自身除外），可在目录执行sha256sum -c SHA256SUMS；原14失败批次的20份hash再次验证不变。全量staged diff-check exit2仅因新原始libtest stdout末尾空行；原字节保留，排除新原始.log后的编写文件检查exit0。精确命令/输出在新whitespace-check.json。
