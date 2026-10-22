# Candidate/history/Text独立实际验证 — targeted通过，full core编译阻断

固定源：`8802bf555bfce1265296318d83a2f8a1fb2b787e`，远端task/document-core-contracts-20261022核对一致。分页回归固定测试源为`02db15524dc4f3a1eccbd6571fe68c56e4ab62a7`。报告所述生产行为源为`10d3aa83e2a93581107ad2e9f44331b5ea99d866`；实际运行只以完整8802bf树/哈希为准，不把早期生产/测试源与本次固定树混同。

本次在新detached worktree `/workspace/Muyon-document-candidate` 实际验证。未发现AGENTS.md，已读CANDIDATE-REPORT、CANDIDATE-PAGINATION-HANDOFF和测试夹具。没有加export、合入provider/B405或其他组合；不会把其262等计数或早期COPY/core结果用于此候选。

## 文件系统与授权范围

Fixture以std::env::temp_dir内PID+独立计数目录执行create_dir（已存在即失败），BusinessStore/objects/staging均位于该原创临时目录；测试只用合成原始字节。候选测试的直接fs写入/改坏/移除均从fixture store.root_dir派生，未读写真实用户文件或实际业务存储，也没有引擎运行、真实模型/搜索/费用请求或历史unknown操作。

仅用现有Rust/Cargo/rustfmt与依赖缓存，不安装/下载、不配凭据、不扩权限。环境为PATH前缀/tmp/muyon-rust/bin、CARGO_HOME=/tmp/muyon-cargo、CARGO_TARGET_DIR=/tmp/muyon-document-cargo-target、RUSTFLAGS=-L native=/tmp/muyon-native-libs。所有cargo test均--offline --locked。

## 实际命令与结果

完整argv/cwd、UTC起止、每进程退出码、工具/源/锁文件哈希在[manifest](independent-verification/candidate-20261022/original/manifest.json)，每项原始stdout/stderr均同目录原样保存。

| 命令（共同前缀cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core） | 实际结果 |
|---|---|
| `--lib documents::candidate_tests::candidate_gc_crosses_page_boundary_preserving_exact_objects_and_project_quotas -- --exact` | PASS exit0，1 passed，47 filtered out |
| `--lib documents::candidate_tests` | PASS exit0，13 passed，35 filtered out |
| `--lib documents::history_tests` | PASS exit0，8 passed，40 filtered out |
| `--lib documents::history_tests::text_label_roundtrips_without_default_utf8_or_reader_capability -- --exact` | PASS exit0，1 passed，47 filtered out |
| scoped rustfmt --edition 2021 --check（blobs.rs、documents全部10个.rs、tests/documents.rs及document_storage.rs，共13文件） | FAIL exit1，6个不同文件有格式差异 |
| 完整muyon-core package（无--lib限制） | **FAIL exit101：business_worker及其test构建各报两项E0599，未进入本次全套测试执行** |

四个targeted均为真实Rust编译/执行，0失败；单测过滤掉的数目不计为执行。分页1项已在candidate13中，Text label1项已在history8中，不能相加成23个独立场景。源码是`DocumentFormat::Text`（不是一个Text8变体）；history8含该label JSON roundtrip，默认reader能力仍Unknown，不默认UTF-8。派生JUnit只为实际执行的四项命令生成，full build不虚构test pass或JUnit。

## 立即交回owner的编译阻断

实际失败原输出：[core-full.stderr.log](independent-verification/candidate-20261022/original/core-full.stderr.log)；stdout为0字节，没有全套case开始。

- `crates/muyon-core/src/blobs.rs:860`调用`document_candidate_upload_retained`；在worker单独编入的BusinessStore上不存在，E0599。
- `crates/muyon-core/src/blobs.rs:896`调用`document_candidate_reserves_digest`；同样不存在，E0599。
- `src/bin/business_worker.rs:4–24`使用#[path]独立编入archive/blobs/business/contract/research/review_lifecycle/sqlite，没有documents/candidate模块。上述真实保留/GC helper实现处于documents/candidate.rs，所以library-only targeted可编译，不代表这个worker的编译组合可用。
- 普通worker与worker test重复编译而重复报告这两个缺失方法；不是四个独立缺陷。不是Rust版本或离线下载失败，本机1.99工具链已实际编译/执行library targeted。

验证者不修改harness、逻辑、测试预期或helper，不用stub/no-op/fallback绕开候选保留/GC。交回owner恢复实际依赖边界，然后必须给新固定源重新编译与运行完整core；不能以--lib过滤结果代替全包。

## 格式与未执行补修

失败文件为blobs.rs、documents/candidate.rs、candidate_tests.rs、history_tests.rs、mod.rs、storage.rs。完整formatter输出与[路径归因](independent-verification/candidate-20261022/original/format-diff-paths.json)保留。

在等待full结果时，仅对/tmp内原源临时副本计算了formatter预期值；13文件中6个需变动，命令/预期哈希在format/expected-format.json。**没有将其写回源worktree，没有生成纯格式patch提交或格式分支**。由于有真实编译失败，本轮不满足“只有fmt差异才补修”的授权条件；先交回编译阻断，不擅修。

## targeted实际支持的范围

160真实reservation分别归五项目、每项目32；第33项拒绝，第六项目仍可准备。分页回归模拟reservation-before-create与expected object-before-ledger窗口，实际跨0/127/128/159边界保存不同对象和最后partial staging；重启后原journal/upload不变，仅删无关orphan，第二轮不重复删除。它是合成局部故障夹具，不是穷尽断电测试或生产环境数据保全保证。

candidate13也实际覆盖新bytes准备/原源不变、未验证状态、重复只query、绑定冲突、reservation/late seal fault、epoch/撤权/expiry、partial tail、bounded投影、配额、missing/corrupt对象/pin和旧head拒绝。生产publish仍由现有测试确认UnsupportedOperation，没有生成真实validator、可用publish handle或字节交付许可，不能用COPY/upload路径绕过。

history8通过不等于history reader/cache接线；旧head读取须独立授权，父grant变更等路径仅按断言覆盖。source candidate未由B405整体验证，此报告不混source，不给gateway原子回执、FFI/Android、真实Office编辑、全workspace、总磁盘配额或生产发布PASS。

原始NOT_RUN/TDD与旧轮次事实保持，main/develop/group/provider/作者分支未改，未合入/部署/付费，Leader B仍唯一合入执行者。总体结论：**targeted运行通过；全包编译阻断；scoped格式失败；生产发布硬拒，需owner修复再验。**

本批证据SHA256SUMS覆盖本分目录其他所有文件（自身除外），可在目录执行sha256sum -c SHA256SUMS。全量staged diff-check exit2来自原始libtest/formatter输出空白；保留字节，排除本批原始.log后的编写文件检查exit0，命令与输出均在whitespace-check.json。未把证据空白当成源码格式已修或编译已过。
