# C3 草稿确认与订阅恢复纯合同交付

语义源码：`5d3440d56aeb6b23e75fd3635eb603e7b2d30e3c`；最终模块格式整理源码：`bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9`。依赖同分支 C1/C2 候选，当前基线 fd26dcdabcdac996bc2881e8141cac2b519966fc；均待 B 决定合入。

新增 DraftRef/DraftEnvelope/SaveAck、精确确认验证、SubscriptionLease 与 ResumeAction。无泛领域业务数据库、持久写入、自动重试、命令重放或真实订阅生产接线。容量1..=256只是计划P1合同检查，不宣称生产配额已批准。

保存确认绑定原pending IntentId、完整scope/generation、owner/draft身份、当前存储基线、expected+1、内容规范摘要；schema不兼容、溢出及不匹配均拒绝。拒绝确认不能证明原保存没有发生，错误保留Unknown/AfterLookup与原身份。局部编辑/业务提交不合并到保存成功。

游标断流/过期只返回ReadSnapshot；scope变化拒绝。除可信owner的cursor_valid外，再检查真实时间到期；测试用0与i64::MAX，不sleep。恢复只选择读取动作，不自动取消或重放任何业务命令。

## TDD 与审查

先写测试/fixture，结构RED为缺drafts模块；最小桩后实际行为RED为3 failed/1 passed（已有拒绝用例已通过，不冒称4项都红），实现后4 passed/0 failed。独立c23_draft_review静态核身份/版本/摘要和恢复边界，实际重跑C3 4/4，未发现必修缺陷；可选新增owner/draft、负过期/长游标等反例保持记录，不冒称已加。

完整最终源码回归和严格检查见后续固定验证补记，实际版本以完整SHA核对，不能沿用旧阶段原始输出。

## 仓库外证据摘要

| 日志 | SHA256 |
| --- | --- |
| c3-structural-red.log | `5c1e44076ca4ae9bd9224d54afac663278e04e73fef265e240c6d77571fe033d` |
| c3-behavior-red.log | `ac0a8fd34814fc5fc34c6993b4f764373422dcf8951d3bd7e5f0a05bb8f9f5a3` |
| c3-green.log | `6b2d64aac17f56c98d268b8e8cb3bc7a15cadf55b45a9de4ec3632bb0d794e40` |
| c123-focused-final-draft.log | `fd070726ed352965cb55a1f7b655961d89f33769ec6a3232d6766e8bdef5ac8d` |

红桩源SHA256：`31e794be07c2fb97a7ca7acf67971ee52242d5f26d4eedda81ea9d3331bb5eba`。所有原始日志在 /workspace/muyon-contracts-evidence，不入库。

回退可正常revert新增模块/登记；原草稿owner、原回执和未决意图保留，不删表、不降schema、不把未知副作用改成已回滚。未进行Android/进程/真实连接验证，未启用C3生产持久化。

## 最终固定源码验证

精确源码 `bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9`，完整命令：

```sh
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-core/src/services/mod.rs crates/muyon-core/src/services/types.rs crates/muyon-core/src/services/commands.rs crates/muyon-core/src/services/drafts.rs crates/muyon-core/tests/public_service_types.rs crates/muyon-core/tests/public_service_commands.rs crates/muyon-core/tests/public_service_drafts.rs
```

完整workspace/all-targets：36个测试二进制，619 passed/0 failed/0 ignored；该数字是执行次数，包含既有跨target重叠覆盖，不等于619个独立场景。Clippy与格式检查exit0。首次模块声明顺序格式检查不通过，已正常追加style提交整理后在上述最终固定源码重跑完整回归，不把旧输出冒充新SHA。该源码包含C1 6项、C2 6项、C3 4项共享合同测试。

| 最终日志 | SHA256 |
| --- | --- |
| c3-fixed-source-workspace.log | `a0edc27c1a895b4424fa083b5d06c85a83a5be0b3b07955db77c5d284cc85434` |
| c3-fixed-source-clippy.log | `9632ccfba273aa7d9c6325d493f743e13da671de0b112aa697a0be6a4f5ce843` |

fixture SHA256：

- types.json：`af0e6170bceb8e1a12e0686ab2855353d257f1ca885b06b3e6dfbad3d81b70f5`
- commands.json：`9f7618861e7fbc33c82e53d06c2acefb06e9fe3e40129eb172085cb48d104adc`
- drafts.json：`e1012c72cccea844a65a66e3b4a7ce3ae3a5257bba476f98ee9b4983cefd1460`
