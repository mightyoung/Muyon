# COPY-only hook实际验证与独立纯格式补修

原固定源：`a27f04aa2460971940d4bdf2c8263bdf81f381c2`，已与远端task/document-core-contracts-20261022核对。其crates代码与生产提交`f6ab7fd78f46319cf46e9754d80c7cf0f6781205`相同。已读COPY-CLONE-REPORT/INTERFACE，worktree未找到AGENTS.md。

使用本任务现有Rust工具链、依赖缓存和临时SQLite linker alias，测试均`--offline --locked`，不下载软件/依赖、不配置凭据或扩权限，不触真实用户文件/业务、文档引擎、真实模型/搜索或历史unknown。测试仅使用自建临时夹具和原始合成字节。

## 原固定源先实际运行

在隔离worktree `/workspace/Muyon-document-copy` 原detached a27f源上，实际执行：

```sh
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib clone
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::storage_tests
/tmp/muyon-rust/bin/rustfmt --edition 2021 --check crates/muyon-core/src/blobs.rs crates/muyon-core/src/documents/anchor.rs crates/muyon-core/src/documents/annotation.rs crates/muyon-core/src/documents/capability.rs crates/muyon-core/src/documents/identity.rs crates/muyon-core/src/documents/mod.rs crates/muyon-core/src/documents/storage.rs crates/muyon-core/src/documents/storage_tests.rs crates/muyon-core/tests/document_storage.rs crates/muyon-core/tests/documents.rs
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core
```

环境选取字段、完整argv、实际UTC起止、退出码、工具/源/锁文件哈希见 [original/manifest.json](independent-verification/copy-20261022/original/manifest.json)。原始stdout/stderr原样保存：新增COPY **6/6通过**；document hooks **9/9通过**（已含这6项）；core **189项测试执行通过**；scoped fmt **exit1**，仅`blobs.rs`、`documents/storage.rs`、`documents/storage_tests.rs`三文件有差异。没有编译或行为失败需要代修，原格式失败输出完整保留，不用格式补修后的通过覆盖。

## 本轮明确授权下的纯格式提交

本轮允许“仅格式问题在独立验证分支生成纯格式patch，不改逻辑/测试预期，不写作者分支”。在确认原源所有行为运行通过、唯一失败是fmt后，创建独立源码分支：

`task/document-core-copy-format-20261022`

唯一纯格式提交：`93de8ad99fad105bc3ca32036de30803d87fd6c7`，父提交为原固定a27f；只改上述三个文件，没有文档、依赖、数据库schema、API设计或测试预期变更。可供core作者**仅cherry-pick这一提交**，本验证者不写作者分支、不自行合入任何集成分支。

证明方式不是仅宣称“format-only”：从Git原a27f取全部10文件到`/tmp/muyon-copy-format-expected`，实际运行现存同一rustfmt。仅3文件输出不同；将其准确输出用于独立分支，所有10文件均逐字节等于rustfmt(a27f)。见 [expected-format.json](independent-verification/copy-20261022/format/expected-format.json) 和 [applied-format-proof.json](independent-verification/copy-20261022/format/applied-format-proof.json)，含每文件前后SHA256、实际命令/时间与提交身份；[标准format-patch](independent-verification/copy-20261022/format/format-commit.patch)也保留。

## 对纯格式固定提交重新编译/运行

新固定源为上述`93de8ad99fad105bc3ca32036de30803d87fd6c7`，没有用原a27f测试结果代替补修后的新源复验。使用同一原始命令、现有工具链和缓存重新运行。实际日志与新源哈希见 [formatted/manifest.json](independent-verification/copy-20261022/formatted/manifest.json)，stdout/stderr分开保存；新旧source哈希均在各轮结束后核实，工作树干净。

**补修固定源实际结果：COPY 6/6、document hooks 9/9、完整core 189项执行全部通过，0失败/忽略；10文件scoped fmt exit0，stdout/stderr均为空。** 只有对纯格式提交真实重跑完成后，才关闭本批格式门槛。原源a27f的fmt失败保留，不宣称作者原提交本身已通过fmt。

## 严格COPY边界与未完成项

COPY只是在**同一文档**上增加元数据revision，内容digest、字节和format与原源相同；不等于另外复制一个原格式文件，不是编辑、转换或渲染。不允许把edited candidate塞进source-only API，未接入任何引擎，也没有从本次formatter补修增加候选编辑能力。

六项新增测试实际覆盖相同字节/format及递增revision、无上传/pin/staging变化、合成回执约束失败回滚、错误digest/length/旧base/外连接事务、跨project/非ready/缺引用/重复reference、合成源文件hash损坏/缺失以及metadata晚失败/版本溢出回滚。这里的回执约束是合成表，不是生产gateway journal，不能当作网关组合原子性已验收。

新6项已包含于hooks9与core189；targeted重复执行、新旧source重复运行和任何filtered-out均不相加成新的独立业务场景。原始NOT_RUN/TDD历史保留，新通过不追认旧RED/GREEN。既有read/write C声明和未接线crate-local hook警告原样保留，不抑制lint。

workspace旧anyhow离线缺口未重试，全FFI workspace、其他workspace格式与实际网关组合仍未验收。actor/group来源、字节交付/缓存授权、总历史/Blob配额、引擎安全/许可/格式保真均保持原边界。main/develop、原group与core作者分支不变，不部署、不付费、不释放预占；Leader B仍唯一develop合入者。

## 封存与空白检查

新目录SHA256SUMS覆盖所有其他本批证据文件（自身除外），可在目录执行sha256sum -c SHA256SUMS。原始日志、标准git format-patch的空白/邮件签名保持原字节：全staged diff-check exit2；仅排除.log仍exit2，来源为原始patch空白上下文及标准签名；排除原始.log和该patch后编写文件检查exit0。独立纯格式提交本身git show --check exit0。三个区别及实际命令/输出均保存，不以修剪证据制造全绿。
