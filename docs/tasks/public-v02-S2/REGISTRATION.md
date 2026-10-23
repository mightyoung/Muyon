# Skills 公共库登记报告

2026-10-23。状态：离线底层候选，待 B 审查合入；本次登记不等于完整 S1 / S2 生产服务验收。

## 固定输入与 ancestry

- 已登记 Connector 的候选 HEAD：`2993477f91ed536917dafef9abe7235b4006e881`，保留在原独立分支。
- Skills 最终候选：`64db72168a8fceafe43756fe31f17ea9ab4aba3f`，源码审查点 `047ab7869ec280020588710c2564f883786f0b7f`。已阅读该候选的 REVISION.md 与先前报告；新签名为 `list_skills(&SkillRegistrySnapshot) -> Result<Vec<SkillRef>, ServiceError>`。
- 两候选 merge-base 为 `4d49a580cb518d9b0b80c9df3df1ff564194a639`，没有复制第二份公共合同。
- 在独立分支 `task/public-v02-skills-registration-20261023` 正常合成；合成基线 `e3597d77a6cc83003f1c712834ad48f7c4a6f5f7` 双亲为上述 Connector / Skills 候选，未改写任何原候选历史。
- 登记提交：`9417e68333d0127e52f0eca5e96dd9cb4851f2bd`。最终验证源码：`88b375b969a61f6027f486f771bb022073c26fed`，后续仅移除测试中不再使用的 documents import。

产品登记差异严格限三文件：services/mod.rs 导出 skill_runtime / skills；public_skills.rs 与 public_skill_runtime.rs 去掉 test-local #[path]，改为实际 muyon_core::services 导入。测试主体与断言未变。两份模块源码和 fixture 与 owner 最终审查点逐字一致，未编辑 workflow、core lib.rs、FFI lib.rs 或 Cargo.lock。

## 已执行的验证

加载此前获准且校验过的 `/workspace/muyon-contracts-tools/env.sh`，使用 Rust / Cargo 1.93.1，所有 Cargo 命令为 offline / locked。本轮没有下载或安装依赖。

- 登记前 test-local 基线：catalog 5 / 5、runtime 9 / 9，退出码 0。
- 测试改为公共库导入、尚未导出时：退出码 101，unresolved import skills / skill_runtime。此为结构性 RED，不是行为断言 RED；该临时状态未保存为不可变 RED 提交。
- 登记后的真实库 scoped GREEN：catalog 5 / 5、runtime 9 / 9，退出码 0，包含 Ok(empty) 与 Err(malformed) 的原断言。
- 初次完整 workspace 回归：646 passed / 0 failed / 0 ignored，40 组结果，退出码 0。随后严格 Clippy 发现测试的 documents import 在去掉本地模块后已无用途，退出码 101；没有抑制警告，在普通后续提交移除该 import。

最终固定源码的完整回归与独立审查结论见下方最终证据段。本报告保留初次 Clippy 失败事实，不将先前 GREEN 冒充最终源码结果。

命令（仓库根目录）：

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skills --test public_skill_runtime
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-core/src/services/mod.rs crates/muyon-core/tests/public_skills.rs crates/muyon-core/tests/public_skill_runtime.rs
```

## 未完成范围与回退

本次只把已审阅纯函数候选加入库，未提供 requestRun、SkillRunSnapshot / getRunSnapshot、生产 HostCommandPort、原 workflow / RunLedger 接线、持久注册及绑定命令、真实取消排空、原子派发前重验或 X2 连接身份 / 授权代次的运行接线。完整剩余范围仍见 [REVISION.md](REVISION.md)。D2 / Documents 的后续候选不在本次集成中。

没有脚本执行、parser / SDK 安装、生产 dispatch、真实模型或外部连接；这些效果仍为 NOT_RUN。Reader gate、历史真实请求 unknown 与费用未知保持。库导出没有扩大权限或创建执行账本。

仅 B 合入 develop。本任务未改 main / develop、未强推、删除分支或部署。普通回退提交可移除两行 Skills 登记并恢复 test-local 导入；不回退既有 Connector 登记，不涉及数据迁移或回执删除。

## 最终证据与独立审查

固定最终源码 `88b375b969a61f6027f486f771bb022073c26fed` 的完整 workspace / all-targets 命令退出码 0：**646 passed / 0 failed / 0 ignored，40 组结果**。该计数包含原有 overlapping targets，不表示 646 个互异业务场景。同一最终源码的 workspace all-targets Clippy `-D warnings` 退出码 0；三份变更 Rust 文件格式检查及 git diff --check 通过。

独立只读审查者 `/root/skills_registration_review` 核对 ancestry、实际库类型身份、列表 Result 签名、空目录与坏目录分流、测试断言未变与模块源码一致性。初审指出的 unused documents import 已修复；最终复核无剩余发现。

审查者使用独立 target `/workspace/muyon-contracts-tools/review-skills-export-target`，在固定最终源码运行以下命令，测试退出码 0（5 + 9 + 17 + 7 = 38 passed / 0 failed），严格 Clippy 退出码 0、无警告。未修改工作树。

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skills --test public_skill_runtime --test agent_workflow --test agent_tools
cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skills --test public_skill_runtime --test agent_workflow --test agent_tools -- -D warnings
```

原始日志在工作区 `/workspace/muyon-contracts-evidence/`，不入 git；SHA256 如下：

| 日志 | SHA256 |
| --- | --- |
| skills-registration-baseline.log | `888ba0743d10200d2b08f67cc54f9cb973a94f39c0a6247cbe4dd2f72b0c22d5` |
| skills-registration-red.log | `2ce0779c0ccd89df055f52b0fa472c95258b41aab2bf6f819c7663dd6cd730cc` |
| skills-registration-green.log | `e1a82dcc58bbd190c78b13bd8bb33dc419971e9c0f1d108bbe6a11d365936f94` |
| skills-registration-workspace.log | `4760a94bdd09cc2f8a5e0cbc87bc7b2173fb909e89bf79553cc1278acbfe5964` |
| skills-registration-clippy.log | `561ef9d01cec9950727ea681d18f871b8e89ea26952bed9bcc3ae1560c3cc9a9` |
| skills-registration-workspace-final.log | `a3a3a2bed2f3f657e0981b150bd681c4190a2a192fd77fc6115d1ae1768148de` |
| skills-registration-clippy-final.log | `6acb228ad29d5ac6cd76d8dc4ed8f2f19368e59ac078d8ab511f84b364cae506` |

Cargo.lock SHA256 保持 `d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`；Skills fixture SHA256 保持 `7acc6c66f41ab2b35709fdf93fc0b6677a3eeee35ad4f74d3b7f23b6ac367e63`。
