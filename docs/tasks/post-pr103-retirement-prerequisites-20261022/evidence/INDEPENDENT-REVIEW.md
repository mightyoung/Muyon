# Post-PR103 退役前置修复独立复审

日期：2026-10-22。只读候选 `/workspace/Muyon-post-pr103-retirement-20261022`，source `50ce62bf7033f63e4632e362ecd95fa7524c3ee0`，直接 parent `4d15b990f725d41a43b86fcd2b170b2219a6f766`，tree `e6c4469a6d32804e51dffc76f1e3eaacc9781ea9`。三者已通过本地 Git 实际核实。开始工作树 clean；报告写在源码树外，未改源或旧 2283/3f479 候选。

结论：本次范围 **Critical 0 / Important 0 / Minor 0**，三项旧 Important 修复仍成立。源审不阻止父线程按已有授权推独立分支；本报告不授权或执行 PR、merge、delete，也不构成 hosted CI 或整体退役完成声明。

## 本次实际执行

- `python3 -B scripts/test_retirement_prerequisites.py`：15 tests / 2.857s / OK。原 8 项契约保留，未减少测试。运行包含实际 Bash guard 在 ci/verify 各 success、failure、cancelled、skipped、空、unknown 六种状态下的比较，以及 runner 子进程失败传播；没有启动真实 Flutter/Laya 测试体、HTTP host、Rust suite 或模型。
- `python3 -B scripts/check_legacy_schema_reference.py`：`PASS (frozen bytes only; no Dart execution)`。
- 静态比较全部 11 个 delta 文件与旧受审 `2283acf175c8f0ab37de8a6d1135d3fde2d27314` 的 Git bytes：除两份 workflow 与 `scripts/test_retirement_prerequisites.py` 中完整 `c130008bbc40d78e85d10058030da9da4aca38f0` 替换为完整新 parent SHA 外，逐字一致。所有 11 项均 MATCH，未沿用旧结果替代新候选运行。
- 枚举 parent/candidate 的完整 `git ls-tree -rz --full-tree`：parent 5596 项，candidate 5604 项；11-path delta 以外每项 mode/type/blob 完全相同，无额外新增或删除。候选只有该 11-file delta。因此 parent 中 Office/Bot/UI/aeb 的文件均未被本补丁回退或删除；本结论是完整树一致性，不是运行这些模块的测试声明。

## 三项 Important 核查

1. **ci/verify fail-closed。** 原 job id 保持，`needs: [laya-offline]`、job `always()` 与 guard step `always()` 均保留，guard 只接受 `needs['laya-offline'].result == success`。上述六状态实际执行通过；无 job/step `continue-on-error`。独立 Laya job 不需要 Flutter；其任何 fetch/check/test 失败不能变成原 gate success。原 Flutter 分析测试命令及 `${PIPESTATUS[0]}` 未变，summary/artifact 的 always 不会清除已有失败。

2. **source/gate baseline 分离且保留活动主体。** `SOURCE_PIN` 仍为 `214b4031deb38ca7dfd35ee86396089eb48157d5`；`GATE_BASE` 现为新 parent `4d15b990…`，不是历史 214 或旧 c130。契约实际将本候选 on 配置及原 job 主体与新 parent 精确比较，只排除获准的 Laya 提取与显式 dependency/guard。CI/verify shell、coverage thresholds、lab selector、aeb 测试/diagnostic、模型/许可/包体门槛及生产 Rust path dependencies 均在 11-path delta 之外，完整保留 parent bytes。`supplier_store.rs` 在 delta 内仅改两处冻结 fixture include 路径，原断言保持。

3. **固定见证及 CI 自动负向 provenance。** checker 两份 schema12 的固定 size/SHA256/Git blob 与旧已审源码逐字一致，独立按真实字节计算并匹配；manifest 不得重定义见证。新跑的同步 fixture+manifest 篡改、blob 篡改、缺 manifest、缺文件/损坏反例均被拒绝。完整 23 refs manifest 固定 SHA256 `da274faeb9bb67790a68bf56d08a0c6380c8d2e05719bfa7ab7e28c026f9a119`，再逐项核对实际历史 Git bytes、size、SHA256、blob；删除全部 refs 的反例失败。两份独立 job 都先显式 fetch 恰四个固定完整 pins：214、01e56、8c599、新 parent 4d15，再执行 checker 和全部 15 契约；缺历史对象反例明确失败且不 skip。固定 manifest 和 checker 的 trusted literals 不随本次换 base 改变。

## 边界与剩余证据

本次是固定 source 的本地源码审查和限定 Python 运行。实际 GitHub fresh-head ci/verify、网络 fetch、取消注入、真实 Laya29、Rust workspace/strict/supplier 均未由本审查执行或认证，记为 NOT_RUN；父线程另行记录的当前 source 运行结果不得混用旧 576/旧候选结果。

job/step `always()` 解决 upstream 非 success 导致的默认 needs skip 路径；整条 workflow 被用户、并发策略或平台强制取消时，排队 job 仍可能未执行而呈 cancelled，不能声称 guard 必然执行或最终必然为 failure。非 success 不等于成功；本次未读取或更改 branch protection，也没有 hosted 调度实验证据。

固定见证抵御 fixture/manifest 自述篡改；同时改 verifier 固定值或移除 workflow 校验属于新的待审源码变更，不是当前机制的防篡改签名边界。仍在使用旧 apps `selection_set.json` 的 Laya 路径没有在本次迁移；删除旧 apps 仍需另行授权和迁移验证。

未运行 I04/task.db/HTTP/reopen、旧 host suite、403 artifact、模型、网络或凭据操作；未安装依赖、改权限或切模型；无被拒或审批挂起操作。没有当前源审 blocker。独立分支推送后的 hosted 状态应继续明确记录；后续 source 改动须重新审查。

## 正式 commit 的 metadata-only 映射复核

2026-10-22，应父线程要求追加只读核实：正式 source `974a7fcd65d29a7d31c5b6a12f9eb5e79e918679` 与原 local-review source `50ce62bf7033f63e4632e362ecd95fa7524c3ee0` 的直接 parent 均为 `4d15b990f725d41a43b86fcd2b170b2219a6f766`，tree 均为 `e6c4469a6d32804e51dffc76f1e3eaacc9781ea9`。实际执行 `git show -s --format='%H%n%P%n%T'` 分别核对，并执行两者 `git diff --exit-code`，exit 0、无文件差异。因此本报告的源码审查结论适用于正式 source 的相同树；本追加没有重跑测试，前述 15 契约及 checker 的实际执行 source 仍为 50ce，不冒称在 974a 直接执行。

复核时新 worktree HEAD 为 974a 且 clean；旧 `/workspace/Muyon-retirement-review-fix-20261022` HEAD 为 `3f4793e9790c8e18e967e847d60b368783b42dac` 且 clean。本复核未移动任何 ref、未改动旧候选、未调用 GitHub connector 或创建远端分支；关于远端对象创建和当前源 Rust/Clippy 运行的父线程报告，不作为本次独立执行声明。974a 的直接 source 测试记录由作者另行补齐；本追加没有新增 Critical/Important/Minor 或源码阻塞。
