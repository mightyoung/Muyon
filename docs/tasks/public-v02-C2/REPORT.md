# C2 原意图/回执纯适配交付

候选源码：`b626c18a5dff184519e59bb866e5ed37362ac84e`；后续模块声明格式整理在 `bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9`。依赖 C1 `6e7f774b1559a0a9693eeb195ba13c9ded561993`，当前执行基线 fd26dcdabcdac996bc2881e8141cac2b519966fc。均待 B 合入，不是 develop 已交付。

## 实际范围

新增 HostCommandPort 类型声明、OriginalLookup 解码、ReceiptView 原状态投影和 unphased_host_error。没有该 trait 的真实 ProductCore/FFI dispatch 实现，不修改 ProductCore ABI、provider、凭据、权限、原账本或 Reader。无可信派发证据时始终 unknown_outcome/Unknown/AfterLookup，保留原 IntentId。

not_submitted 仅接受原 owner 的精确四字段封套；unknown/not_found 仍 Unknown；缺/拼错字段拒绝。成功要求原 ExecutionResult 合法，并以原 CommandEnvelope 验证 Receipt 的 intent、scope、authority、binding digest、target、revision。Pending 只是 Accepted；取消请求不证明停止或撤销。

## TDD 与独立审查

测试/fixture先写，结构RED为缺 commands 模块。最小桩第一次尝试暴露测试自身的移动后使用编译错误；修正为借用后才实际行为RED（0 passed/5 failed），不把编译错误记成行为RED。实现后5 passed。

独立只读审查者 c23_draft_review 实际重跑当时 C2 5/5、C3 4/4，发现中等问题：Pending+cancel 与 Unknown+cancel 的 ReceiptView 完全相同，丢失原未知信息。已追加回归 cancel_requested_retains_original_unknown_fact，实际RED（Pending != Unknown），再保留现有类型 ExecutionStatus 为 execution_status，GREEN后C2 6/6；没有新增权威枚举或改原业务状态。该修复按原规格保留四轴信息，无需重建执行协议。

OriginalLookup::Execution 使用 Box<ExecutionResult> 消除 large_enum_variant 的严格Clippy失败；独立审查确认只改变Rust内存布局/构造，无wire/FFI ABI暴露。未用 allow 降低Clippy门禁。

在干净detached工作树精确检出 b626c18a 后，运行 offline/locked 的 public_service_types、public_service_commands、business 回归，全部通过，具体计数见下方。Money/Quantity、phase枚举和结果ID迁移的新规范仍单独待父裁定；现phase保持String调用点标签，不能证明派发。

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_service_types --test public_service_commands --test business
```

固定C2回归：3个二进制，26 passed/0 failed/0 ignored。

## 仓库外证据摘要

| 日志 | SHA256 |
| --- | --- |
| c2-structural-red.log | `3a0de7d7498bcd59be73081f277bdf0e95f0b7fe7aaf6ac54a8fe11baa648d9e` |
| c2-behavior-red.log | `c2c0c18117fbdfa0f1a327aa9cd2c937d632091b28801f9c268be4dc91dfcea1` |
| c2-behavior-red-fixed-test.log | `ca8a01ba5ae626cfefc15706bb30a02d91f92c858cb805d76f92ce548839bab0` |
| c2-green.log | `aba8a4ddf69f869a62076cfba650770e4cb3b75fd5bb54aaa3de4aac846fad86` |
| c2-cancel-review-red.log | `afd712a62d350682cd03b3523220413a70b371d32894aa74cf823f8143fa725b` |
| c123-focused-final-draft.log | `fd070726ed352965cb55a1f7b655961d89f33769ec6a3232d6766e8bdef5ac8d` |
| c2-fixed-source-regression.log | `60edf9b4c951ba3ecef1ed7d4307409baf769dd6b17d3c55537866f40ee37b26` |

原始日志及红桩源保留于 /workspace/muyon-contracts-evidence，不入库。C2红桩源摘要：`7f0db94cec9392a13282a89b0e33c5a9a1400cc37aaf0f36d28180139bf1a7b1`。

回退只移除公共新入口/登记，保留原 Receipt、IntentId 与原 owner；没有生产入口需要启用或关闭。未验证 Android、真实外部效果、线上恢复或真实费用。

最终组合源码 bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9 的完整回归为36二进制619通过/0失败，严格Clippy/格式通过；见 ../public-v02-C3/REPORT.md 的最终固定日志摘要。这是待合入候选验证，不是develop或生产验收。
