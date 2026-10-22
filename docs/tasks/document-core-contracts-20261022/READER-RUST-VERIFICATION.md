# Reader独立实际验证 — 两项cleanup-tail RED，不能接受原候选

精确完整源：`ff3cc928311afc12bee3205f28b662c6b7499b34`；源码`b3592e9bc1b0d9c3c52800e5ec1f566e36b8a297`与其crates树相同。只在隔离detached worktree `/workspace/Muyon-reader-core-verification` 验证，没有加export或合其他组合，不借旧Reader/candidate/provider/B405结果。未发现AGENTS.md，已读READER-FACADE-REPORT；作者源码/测试、main/develop、group、provider分支未修改。

## 实际结果

使用已有Rust1.99.1工具链与缓存；PATH前缀/tmp/muyon-rust/bin、CARGO_HOME=/tmp/muyon-cargo、CARGO_TARGET_DIR=/tmp/muyon-document-cargo-target、RUSTFLAGS=-L native=/tmp/muyon-native-libs。cargo均--offline --locked，没有下载、凭据/权限变化、引擎、模型/搜索、外部服务或用户文件。只有各测试自建临时合成目录/SQLite/原始字节被操作。

| 命令 | 实际结果 |
|---|---|
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::reader_tests` | **exit0，13 passed / 0 failed** |
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core` | **exit0，266次测试执行passed / 0 failed** |
| scoped `rustfmt --edition 2021 --check`，完整argv见manifest | **exit1**；路径别名归一后4文件：blobs.rs、documents/mod.rs、reader.rs、reader_tests.rs |
| 独立公共Reader API探针（工作树外编译，原15项storage夹具测试过滤不执行） | **编译exit0，执行exit101，4 passed / 2 failed**，两项为真实cleanup-tail预期拒交付RED |

原始命令、UTC起止/退出码、环境、工具/源/锁文件哈希见[original/manifest.json](independent-verification/reader-20261022/original/manifest.json)。所有stdout/stderr原样保存，独立探针的cargo artifact JSON、实际extern rlib路径/hash、源码文本和rustc/test命令也保留。JNI/FFI、Kotlin、Android/PFD未在本轮验收；没有把SQL检查或formatter解析当Rust执行。

**现有套件虽绿，独立RED阻断接受。** 266包含library61与worker61完全相同的源码函数集，不能说266个独立业务场景；单独Reader13也已经重复包含其中。外部六探针是附加诊断，不相加为产品覆盖承诺。派生JUnit保留两个failure节点，按实际binary classname记录，非原生runnerXML，不虚构时长。

## Important：cleanup期间授权失效后仍成功返回字节

两个真实探针都使用准确表结构和同一个真实SQLite触发器：

```sql
CREATE TRIGGER independent_expire_on_cleanup
BEFORE DELETE ON blob_pins WHEN OLD.kind='reader'
BEGIN UPDATE document_grants SET expires_at_ms='0'; END;
```

每个测试都先断言外部连接实际读到grant expires_at_ms='0'、reader pin数=0，再断言应拒交付，避免把不适用的trigger/setup错误当复现。实际结果：

- `independent_one_shot_cleanup_expiry_must_withhold_returned_bytes`：with_document_source回调返回真实合成文件字节；清理使grant过期并删pin，方法仍`Ok`返回**59字节**。预期Err，实际断言失败。
- `independent_eof_cleanup_expiry_must_withhold_returned_chunk`：open后安装trigger；一次EOF读取结束，清理使grant过期并删pin，仍返回**Ok、eof=true、59字节**。预期Err，实际断言失败。

原始[probe stdout](independent-verification/reader-20261022/original/probes/probe-tests.stdout.log)明确打印success、bytes、expiry与pin结果，[stderr](independent-verification/reader-20261022/original/probes/probe-tests.stderr.log)保留两个最终安全断言panic。不是编译/私有API/setup失败，也不是返回了0字节或伪文件。

代码依据：reader.rs的one-shot在最终view.resolve_current之后执行pin DELETE，再COMMIT/Ok；DELETE本身可以改变live grant却没有再次检查。EOF分支在read_chunk内校验/commit成功后，调用release删除pin，再原样Ok。有效授权在cleanup期间失效，最终对外成功没有覆盖这个尾窗口。

验证者没有修改生产语义或采取格式补修；owner已报告修复的事实不能用于追认原ff3cc关闭，本报告仅锁原代码真实表现。需要新的固定修复源实际复跑这两个RED及完整检查后才可关闭。

## 其他四项独立失效探针通过

- 首块4字节成功后，分别撤权、更换grant generation/epoch、expiry置0、删除project；后续read被拒、session失效、pin清理。
- 未颁发session ID、实际pin丢失，以及首块后同长度修改held source最后一个字节；后续不交付，原session失效。
- 首块后实际owner发布新revision；旧handle/旧access不替换为最新，拒绝交付；新精确revision+新grant可读取新的合成字节，旧handle仍拒绝。
- reader pin INSERT时同owner事务触发grant过期；one-shot callback不执行、方法不成功且pin回滚；移除该独立fault后原合成源可正常处理。此项不是cleanup-tail，所以它通过并不关闭上面两项RED。

不使用sleep伪造idle/absolute期限。独立探针验证真实持久grant expiry；owner13对15s/30s session限制用其内部测试时钟hook，未声称独立实测整个真实时长。可信local callback不是沙箱，本次未在callback内做任何文件/外发操作。

## 探针与获取过程中的诚实失败记录

初次独立探针误用crate-private root_dir，rustc返回E0624，**零测试执行**；原源码/编译日志保留在original/probes-initial-private-api。只修正外部探针到fixture数据库路径+.blobs（与BusinessStore实际命名一致）后重新编译；未改生产/作者测试。修正说明在probe-harness-correction.json，该初次失败不算漏洞证据。

初次只读fetch遇HTTP503，目标对象/工作树不存在；核git对象和worktree状态后同一只读fetch成功，才建立固定源工作树。不是权限拒绝，不绕过保护；当时没有测试完成或采用旧源。setup-notes.json为会话工具输出摘要，不冒称原始文件日志。

## 封存与HOLD

原始author13/core266绿色、原fmt失败、外部4绿/2红分开保存，含完整命令和哈希；不因绿色占多数或静态复审就弱化尾授权失败。既有编译警告不隐藏，没有改lint/运行cargo fix。证据SHA256SUMS独立封存，可在本分目录执行sha256sum -c SHA256SUMS；只为实际运行测试派生JUnit。

当前不满足“仅fmt问题”的条件，**没有生成纯格式补修提交/分支**。原candidate publish仍硬拒，无真实validator或Office引擎。生命周期/PFD、reader/evidence consumer、缓存与实际外发/格式解释仍待组合验收。历史NOT_RUN/TDD、未知费用、原拒绝与Leader B唯一合入职责保持；无合入/部署/付费/真实模型请求/历史unknown重试或预占释放。

封存全量staged diff-check exit2来自原始libtest/formatter输出空白；保留字节，排除本批原始.log后的编写文件检查exit0，精确命令/输出见whitespace-check.json。不能把证据空白检查与四文件源码fmt失败或两个真实RED混为一谈。
