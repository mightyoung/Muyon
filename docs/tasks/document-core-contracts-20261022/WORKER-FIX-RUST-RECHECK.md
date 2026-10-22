# Candidate worker修复独立实际复验

固定完整候选：`faeef3aec3a9407d7c15490dcdb33866413e7453`，远端task/document-core-contracts-20261022核对一致。生产/测试源为`cab23b69b2aa56f55f3b44e0fe248f026da9c08d`，两提交crates树相同。原8802bf及验证263dfe40上的实际E0599/格式失败完整保留，不以静态复审或原作者NOT_RUN替代新运行。

本线程仅在新detached worktree `/workspace/Muyon-document-worker-fixed` 验证此固定树，没有合txn/B405/provider/其他源；txn组合结果仍需对应owner独立验证。未发现AGENTS.md，已读WORKER-COMPILE-FIX-HANDOFF。新结果只追加原task/document-core-verification-20261022证据分支；作者分支、main/develop、group和provider分支未修改，不自行合入。

## 实际运行与门槛裁定

全部使用现有工具链/缓存，不下载或扩大权限；PATH前缀/tmp/muyon-rust/bin，CARGO_HOME=/tmp/muyon-cargo，CARGO_TARGET_DIR=/tmp/muyon-document-cargo-target，RUSTFLAGS=-L native=/tmp/muyon-native-libs。

| 实际命令 | 结果 |
|---|---|
| `cargo check --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --bin business_worker` | **PASS exit0**，普通worker真实编译检查，无原E0599 |
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --bin business_worker` | **PASS exit0，48 passed / 0 failed / 0 ignored** |
| scoped `rustfmt --edition 2021 --check`（原13文件加business_worker，共14个显式目标，完整argv见manifest） | **PASS exit0**，stdout/stderr均为空 |
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core` | **PASS exit0，240次执行passed / 0 failed / 0 ignored**；17个测试二进制，另0项doc-test |

精确argv、实际UTC起止、每进程退出码、cwd、选取环境、版本与工具/源/锁文件哈希见[新manifest](independent-verification/candidate-worker-20261022/manifest.json)，全部原始stdout/stderr同目录保存。源哈希与源worktree在结束后核实未变。没有代修、打补丁、禁用lint或运行cargo fix。

**原缺失两个helper的编译门槛，仅对本固定源真实关闭；本批格式门槛也实际通过。** library-only的旧通过不被冒充为该结论，真实ordinary-worker check、worker test和full package都已运行成功。旧作者127/NOT_RUN与原E0599保持其历史事实，不追认为当时已过或已验证TDD。

## 重复编译测试的计数说明

worker按原harness模式直接编入完整documents模块，因此其cfg(test)包含相同源测试。对原始输出按stderr中实际Running顺序和stdout各running/result块对齐，得到：

- full-core的library unit48与worker unit48，测试函数名集合**完全相同**；两次编译/执行是两个binary上下文，不是96个独立业务场景。
- 单独worker48又重复包含在full-core240内，不能相加成288个独立场景。
- candidate13、history8（含Text label1）及分页1均在这两个unit binary里执行。分页1本就是candidate13之一，不再额外累计；同一源码回归被不同binary执行不扩大场景覆盖声明。

[原始输出摘要与48项交集](independent-verification/candidate-worker-20261022/test-summary.json)保留每binary测试名。派生JUnit使用真实binary作为classname、保留raw hash，明示其为执行计数而非独立覆盖；不是原生runnerXML，不虚构时长。

## 修复与安全边界核对

worker只新增真实`#[path="../documents/mod.rs"] mod documents;`及既有模式的allow(dead_code)，没有dummy helper、放行default或关闭candidate保留/GC。它在自己的真实BusinessStore类型上获得完整documents实现，实际worker tests包含跨128页160reservation、restart retention、未知状态保留、无关orphan回收和生产publish拒绝等回归。

原13文件与本环境此前对8802bf计算的rustfmt预期值再次独立比对，**13/13字节hash相同**；worker是新增第14个实际格式目标。见[format-equality.json](independent-verification/candidate-worker-20261022/format-equality.json)。这只是附加来源证明；真正的编译/格式关闭依据是上面实际exit0。

保留所有实际警告：既有read/write C声明、低层未接线hook dead_code，以及worker的CandidateState/CandidateStatus未使用import。未改警告等级或执行formatter之外的自动修复。没有引擎、真实用户文件/业务、模型/搜索请求、历史unknown重试或预占释放；测试只在其自建临时合成目录写入，不在用户文件上做crash/GC。

没有真实validator，production candidate publication仍为UnsupportedOperation；新bytes准备、SealedUnvalidated或unknown均不是可发布/可读权限。行/项目配额不是总磁盘配额。txn整体回执/最终授权组合、FFI/Android、reader/cache、actor/group来源、engine安全/许可/保真和全workspace仍不因此验收。Leader B仍唯一develop合入者，本报告不授权合入/部署。

新分目录SHA256SUMS覆盖其余全部证据文件（不含自身），可在该目录运行sha256sum -c SHA256SUMS。全量staged diff-check exit2仅为原始libtest输出末尾空行；保留原字节，排除新原始.log后的编写文件检查exit0，实际命令/输出已存whitespace-check.json。
