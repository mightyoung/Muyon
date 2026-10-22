# Reader最终tail修复与snapshot独立实际验证

本报告每组都实际运行，不把作者NOT_RUN转为推测PASS，不跨版本借用。原ff3cc的两个59-byte成功交付RED及13/266旧结果不改。报告输入8d7323aab51ff76616ee196b90a7d4ee83b45d97只提供交接；性能实际源锁2e71384e，而非混称当前报告head。

## 四个独立固定源与实际结果

| 组 | 实际source commit | 原六探针 | Reader | 完整core执行数 | scoped fmt |
|---|---|---|---|---|---|
| 纯tail原源 | `fec40dc8aeec350ef6d77005d4efb79fd186eb7a` | 6/6 | 15/15 | 270/270 | exit1，四文件 |
| 纯tail纯格式补修 | `1785fd2d6e7a9d63b32341ad95b563d5c2b11365` | 6/6 | 15/15 | 270/270 | exit0 |
| snapshot原源 | `2e71384e808ecbe5bb010d05e87094e33e9cd3fd` | 6/6 | 17/17 | 274/274 | exit1，四文件 |
| snapshot纯格式补修 | `97969f9ab6728e8022b3ff7b7a069a655e94c9d8` | 6/6 | 17/17 | 274/274 | exit0 |

所有通过命令exit0、0失败/忽略。两性能组的精确cost targeted各1/1通过。普通core命令没有--lib过滤，包含真实worker；每组全包17个test binary，另0项doc-test。纯tail没有snapshot实现，**不承接性能版成本或64MiB预算结论**。

独立worktree分别是/workspace/Muyon-reader-tail-verification和/workspace/Muyon-reader-performance-verification，未发现AGENTS.md。只用已有Rust1.99.1工具链、原缓存和临时SQLite linker alias，cargo均--offline --locked，不下载软件/依赖或改权限/凭据。没有加export、合txn/B405/provider、编辑owner分支、main/develop或group；测试仅访问其自建临时合成目录，不用引擎/用户文件/模型/搜索/费用请求。

## 实际命令与原输出

每组分别保存完整argv/cwd、实际UTC起止/退出码、环境、工具二进制/源码/锁文件哈希。四组目录在[reader-tail-performance-20261022](independent-verification/reader-tail-performance-20261022/)。主要命令：

```sh
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::reader_tests
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core
/tmp/muyon-rust/bin/rustfmt --edition 2021 --check <worker、blobs、documents全部Rust及两项integration测试，16个显式路径>
# 仅性能两组，保留真实counter打印
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::reader_tests::thirty_mib_stream_hash_cost_is_linear_and_chunk_bytes_are_exact -- --exact --nocapture
```

原六探针同样从工作树外编译真实core rlib，保留cargo artifact JSON、extern路径/hash、探针源码、rustc和实际test输出。环境为PATH前缀/tmp/muyon-rust/bin、CARGO_HOME=/tmp/muyon-cargo、CARGO_TARGET_DIR=/tmp/muyon-document-cargo-target、RUSTFLAGS=-L native=/tmp/muyon-native-libs。警告保留，不执行cargo fix或降低lint。精确路径不是仅依据上面的展示缩写。

## 原两个不可删RED → 各新源真实GREEN

[regression-source-equivalence.json](independent-verification/reader-tail-performance-20261022/regression-source-equivalence.json)核对四组的added probe SHA与原ff3cc证据中六探针SHA完全相同，原synthetic fixture seed也相同。没有改“应拒交付”的断言或删除59-byte回归。

原始trigger仍为BEFORE DELETE blob_pins、OLD.kind='reader'时UPDATE document_grants expires_at_ms='0'。四组每次都先断言真实grant expiry=0、reader pin=0；one-shot及EOF均不再返回Ok或59字节。原始打印success=false、bytes=0表示方法没有返回payload，不代表内部未进行合法的预备读取。其他grant/lease/revision/hash失效四探针也都通过。

这些结果实际关闭对应固定源的cleanup-tail交付阻断。纯tail完成cleanup/commit后的新事务重新查原访问和完整metadata；EOF沿原session期限再查交付，未依赖已删除pin。source源码和真实fixture都未替换为放行stub。旧ff3cc仍保持两项真实失败历史，不能改成原先通过或追认旧TDD。

## snapshot实际成本与64MiB预算

性能两组的原始cost stdout都打印同一结果：

```text
source_bytes=31457280 open_hash_bytes=94371840 backup_open_hash_bytes=94371840 stream_hash_bytes=0
```

这是对真实hash-update/digest工作的cfg(test)计数：源30MiB，open各90MiB（3n）哈希输入，480个64KiB chunk的whole-source哈希输入合计0，并逐块比对了全部原始合成bytes。不是理论预测，也不是Android吞吐测量；没有放宽29s grant/30s session期限来使测试通过。

同一实际测试先后开两个30MiB snapshot，第三个open被TextLimit拒绝、reader pins仍为2；关backup、读完主源后pin为0，实际检查了64MiB总snapshot payload预算，而非仅8-session数量上限。上限是**单一host中的snapshot payload总和67,108,864 bytes**，不是全进程RSS或所有workspace总内存。FD/allocator/chunk以及测试原始bytes另有开销，未测Android内存压力。失败cleanup保留的session仍占预算/被poison阻断，不能据此声称已完成实际host生命周期验收。

另一真实性测试修改物理文件并经cfg(test)重采stamp后，chunk仍返回原已认证snapshot，不把变造磁盘bytes注入交付；显式is_current随后用全hash发现不一致。stamp不是密码学证明，snapshot初始hash才绑定实际bytes；scope/grant/head/lease在每次chunk仍重新检查。is_current完整hash成本保留，host若每chunk另调它可能重引高成本，其真实调用模式未在本线程测量。

[独立计数摘要](independent-verification/reader-tail-performance-20261022/snapshot-cost-summary.json)只适用于2e71384e与97969f9a；fec40dc8/1785fd2d原stream未优化，不给它们线性计数承诺。

## 两个独立纯格式提交

两原源都实际通过本组所有行为检查、只剩原四文件fmt失败后，按已有授权分别建立独立格式分支，只改blobs.rs、documents/mod.rs、reader.rs、reader_tests.rs，准确使用临时旧源副本运行同一rustfmt的输出；其他显式16文件逐字节核对无意外改变。

- `task/document-reader-tail-format-20261022`：`1785fd2d6e7a9d63b32341ad95b563d5c2b11365`，唯一父fec40dc8；只用于纯tail源。
- `task/document-reader-snapshot-format-20261022`：`97969f9ab6728e8022b3ff7b7a069a655e94c9d8`，唯一父2e71384e；只用于snapshot源。

两提交没有逻辑/测试预期变更或安全/performance源混合，可交owner按对应基线**仅cherry-pick相应纯格式提交**。完整format-proof、命令时间/前后hash及标准format-patch分别保留。每个补修commit都重新跑本组原六探针、Reader/core/fmt；性能补修还重跑实际cost打印，完成后才关闭本组格式门槛。原源fmt失败仍保留，不追认为owner裸源fmt已过。

## 计数与最终边界

270/274均为执行数，不是独立场景数。纯tail library63与worker63完全相同源测试，snapshot library65与worker65相同；Reader/cost targeted、原六探针复跑、原/格式两版本重复不能相加扩大覆盖。派生JUnit按binary classname记录、保留raw hash，非原生runnerXML，不虚构时长。未运行全FFI workspace、JNI/Kotlin/Android/PFD、txn整体回执组合或真实引擎；没有新成功publish validator，candidate生产发布仍硬拒。

Leader B仍唯一develop合入者。本报告只支持这些固定源上的真实安全/Reader/core/成本与格式结果；不授权发布、真实模型调用、用户资料外发、历史unknown重试或预占释放。原30份ff3cc证据和不可删RED原始输出保留，NOT_RUN/TDD历史不改。

## 封存与空白

本分目录SHA256SUMS覆盖所有其他新证据文件（自身除外），可在目录执行sha256sum -c SHA256SUMS。全量staged diff-check exit2为原始libtest/formatter输出；仅排除.log仍因标准format-patch空白上下文/签名exit2；排除原始.log与两个patch后编写文件检查exit0。两个纯格式提交本身git show --check均exit0。五条原命令/输出完整保留在whitespace-check.json，原字节不被修剪以制造全绿。
