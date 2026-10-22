# 持久化七文件格式补修独立复验

固定新源码：`f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac`，与远端task/document-core-contracts-20261022核对一致。固定旧源码：`f043c6b9b8d850acb590a9a3e567d1f2634a95cd`，旧验证提交为`0035845b5e9fedf8bf3cddd24da050b231500858`，其真实格式失败、测试输出和历史记录全部保留。

本次在新detached worktree `/workspace/Muyon-document-persistence-formatted` 只读运行；未发现AGENTS.md，已读作者PERSISTENCE-FORMAT-FOLLOWUP。仅向原独立验证分支task/document-core-verification-20261022追加报告。没有改作者代码、group分支、原工作区、main/develop或先前证据，不进行合并、业务真实写入、凭据/权限变化、下载、引擎运行、真实模型/搜索或用户文件操作。

## 先核仅格式变化

旧源到新源恰好七个Rust文件变化：documents/{annotation,capability,identity,mod,storage,storage_tests}.rs、tests/document_storage.rs；另三文件仅为作者补修说明与证据。

独立从Git提取旧源的全部七个documents .rs和两项集成测试共九文件到临时目录`/tmp/muyon-persistence-format-expected`，使用现有同一rustfmt实际格式化临时副本，再与新固定源逐字节对比。九文件全部相同，其中七个修改、两个不变。没有对任何源码worktree做改写式格式化。精确路径、命令、时间及每文件预期/新SHA256见 [format-only-proof.json](independent-verification/persistence-format-20261022/format-only-proof.json)，不只采信作者的“仅格式”声明。

## 新源实际复验

现有工具链与依赖缓存保持不变：PATH前缀`/tmp/muyon-rust/bin`，CARGO_HOME=`/tmp/muyon-cargo`，CARGO_TARGET_DIR=`/tmp/muyon-document-cargo-target`，RUSTFLAGS=`-L native=/tmp/muyon-native-libs`。测试全部使用`--offline --locked`，不下载依赖。测试业务写入仅发生在各测试自己新建的临时合成夹具，不是真实业务存储。

```sh
/tmp/muyon-rust/bin/rustfmt --edition 2021 --check crates/muyon-core/src/documents/anchor.rs crates/muyon-core/src/documents/annotation.rs crates/muyon-core/src/documents/capability.rs crates/muyon-core/src/documents/identity.rs crates/muyon-core/src/documents/mod.rs crates/muyon-core/src/documents/storage.rs crates/muyon-core/src/documents/storage_tests.rs crates/muyon-core/tests/document_storage.rs crates/muyon-core/tests/documents.rs
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test document_storage
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::storage_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test documents
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core
```

**新固定源实际结果：scoped fmt exit0（stdout/stderr均为空）；持久化15/15、尾hook 3/3、旧合同18/18和core全套183/183均exit0，0失败/忽略。** core全套是17个测试二进制的183次测试执行，已包含上述targeted用例，重复执行不相加成独立场景。转换脚本核对所有targeted测试名均在full-core中。原有read/write声明及未接线hook的dead_code警告保留在stderr，没有改lint或代码。七文件格式门槛现由实际成功复验关闭。

第一行完整九路径argv及每进程UTC起止、退出码、cwd、工具/源/锁文件哈希见 [新manifest](independent-verification/persistence-format-20261022/manifest.json)，原始stdout/stderr同目录完整保存；新JUnit只从本次原始libtest stdout派生，非原生runner XML。旧输出不被当作新源结果。

## 保留的门槛

本报告仅关闭实际复验通过的本批documents格式门槛，不意味着网关整合已经执行或通过。该固定新源可交父侧作为受控组合验证的输入；网关授权、回执、取消、崩溃恢复和并发组合仍需其独立证据，不由本报告代替。

不重试既有全workspace的anyhow离线缓存缺口，不代表完整FFI workspace或全仓fmt通过；前次52个未改workspace格式路径保持原记录。没有总历史/Blob磁盘限额、引擎、真实格式编辑、actor/group可信来源、字节交付/缓存授权等生产接线完成声明。旧NOT_RUN/TDD历史不变，不把当前通过追认为旧RED/GREEN。没有解除任何原unknown/费用/拒绝/HOLD，Leader B仍唯一执行develop合入。

本批新证据由新分目录SHA256SUMS独立封存（不含自身），可在该目录执行sha256sum -c SHA256SUMS。全量staged diff-check exit2只来自原始libtest stdout末尾空行；保留原字节，排除本批原始.log后的编写文件检查exit0。精确命令和输出保留在新whitespace-check.json。前次证据清单与原输出不变。
