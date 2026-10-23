# Connector / Skills 第二片：真实库组合验证

2026-10-23。状态：离线组合候选，待 B 审查合入。原候选历史未修改；不代表生产 Connector 生命周期或全 Skill 服务已接通。

## 基线与精确组合

- 本轮 fetch develop 为 `456effb553315026ccf7432889e9785426418427`（PR #112，已登记 Connector / Skills）。
- 为保留已交付 Documents 登记及 Skills 所需 D2 真实 JobSnapshot，组合起点为 `f2a3c21fcbb0ef6bd6c84e8c1fca750a990933f7`（既有全登记候选）。先正常 merge 上述 develop，再只挑入两线新增片。Documents 仍是候选依赖，不冒称它已在该 develop 中。
- 独立分支 `task/public-v02-service-followups-integration-20261023`；最终产品 / 测试源码 `8bc947c6f63b318c5a78e173572e045a31ada9eb`。
- C4 是另一独立候选，没有混入本组合。没有整分支覆盖或复制旧公共类型 / 原始 test-local headers。

| 输入 | 原提交 | 本组合提交 |
| --- | --- | --- |
| Connector 新测试 / unavailable 桩 | e1bbeadfa2800bd64bf58aad199279c8e110c8f4 | 75c98402 |
| Connector 最终实现 | 1afb93e47114b052411b7ccac1fbf175380cdedb | c8094237 |
| Connector 生命周期报告 | d8a1740d（原候选 3caa77a043e99a55d81d8b3a406bb1cc06735045 内） | 43de8512 |
| Skills 原意图取消测试 / 桩 | 574ac1d5528d99ae7519d7a1b9f940c6d09885ae | 98a9e4ca |
| Skills 原意图取消实现 | 97a199c3d956eaecc7b8009daa4e61fa5b73cb88 | 1c455dd4 |
| Skills 文档步骤投影测试 / 桩 | 669263f504ea09bf02419c3b0987b53007835648 | a923f763 |
| Skills 最终实现 | 4ce50debd39c6dc4ca39dae7f76fd113b5856047 | 4a0be74d |
| Skills 报告 | ee9ebcac22bba0417c97c813344c1d8b55078f10 | 8bc947c6 |

Skills 原分支引入 Documents 的 merge 未重复挑入，已有相同源码 / fixture。669263f5 的唯一冲突在 public_skill_runtime.rs 导入区：保留实际库的 services 导入，只新增 pipeline 别名；拒绝恢复 #[path] 本地模块及旧 documents 别名。新 tests 的主体与断言保持。两线原 TDD 源与结果保存在各自报告；本轮集成只重跑最终实现，不把历史测试提交当本轮观察到的 RED。

connections.rs 与原固定 1afb93e4 逐字相同；skill_runtime.rs 与原固定 4ce50deb 逐字相同。skills.rs 的 Result 列表签名保持。services/mod.rs 与既有全登记候选相同，Documents 三模块和 pipeline fixture 未变。Connector、Skills 与 pipeline 测试全部通过实际库导出；D1 专用源码 spy 的原有限定边界继续保留。

## 受限语义核验

- LocalDisconnect 只约束 network / availability，并保留 auth 认知；不证明服务器令牌撤销。Disable 不制造撤权完成；RevokeUnknown 保持 Unknown。
- 生命周期候选要求 authorization_generation 精确前进一次，溢出拒绝；旧 prepared binding 不因重连或可用状态恢复而复活。此处仅验证快照变化，不应用 / 持久化 / 发送动作。
- 生命周期拒绝保持 Unknown / AfterLookup 与可用的原 IntentId，不把旧远端效果判作 NotStarted。Admission 的成功只是局部前置条件，不替代原授权、scope、预算、披露或原子派发重验。
- cancel_original_run 调既有 HostCommandPort 的原 cancel_original，保留原 Pending / Unknown / Committed / Rejected / Cancelled 事实；错误或不匹配回包保留请求的原 IntentId，转原 C2 unknown 封套，不自动 prepare / confirm / replay。
- get_run_snapshot 只复制传入的既有文档步骤 JobSnapshot 与 Skill / binding 引用，不创造或推进任务，不把文档 Parse 阶段显示为完整 Skill 进度。可信快照提供、真实权限和原 owner 取消排空仍未接通。

## 本轮实际验证命令

使用此前获准且已校验的 Rust / Cargo 1.93.1，加载 `/workspace/muyon-contracts-tools/env.sh`；复用 Cargo.lock 缓存与工作区原生链接。本轮无工具 / SDK 安装、依赖下载或锁文件升级。

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connectors --test public_connections --test public_skills --test public_skill_runtime --test public_documents --test public_pipeline --test agent_workflow --test agent_tools
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-core/src/services/connections.rs crates/muyon-core/src/services/skill_runtime.rs crates/muyon-core/tests/public_connections.rs crates/muyon-core/tests/public_skill_runtime.rs
```

聚焦命令的首次日志 76 项全部通过，但外层会话最终返回 1；未把该次外层状态记为命令成功。随后 Python subprocess 直接记录实际 Cargo argv / 返回码 / 固定 SHA：实际 Cargo exit0，76 passed / 0 failed / 0 ignored（8 targets）。这次确认不是更改测试换通过。

workspace all-targets 严格 Clippy exit0，变更四份 Rust 文件格式检查与 git diff --check 通过。完整 workspace 和独立审查结论在下方最终证据段。

## 未运行 / 阻断与回退

X3 固定 SDK 评估稿只读核为 HOLD；原候选后续 e68479fa / 3caa77a0 仅 SDK gate 文档未纳入本次最小实现增量。没有安装 SDK、运行 MCP transport、配置凭据、授权 / 连接真实服务或调用模型。X3 的包分发校验、依赖 / 许可证 / Android 平台及凭据 owner gate 均不因这次组合而放行。

真实远端 disconnect / revoke / OAuth / token 效果、生产 dispatch / FFI、真实停止 / 回滚、完整 Skill 进度 / requestRun / workflow / RunLedger 接线仍未验。没有新增执行账本、Money / Quantity / phase 语义或权限。Kotlin 仅保留依赖候选中的原测试规范，不运行 / 实现；Reader / FD、历史真实请求 unknown 与费用未知保持。

B 唯一决定 Documents 候选依赖及本组合的合入；本任务没有改 main / develop、强推、删分支或部署。普通回退可撤销本次新增 helpers / tests / 报告，保留先前登记与原回执 / unknown；没有迁移或删除数据。

## 固定源码最终验证与独立审查

固定源码 `8bc947c6f63b318c5a78e173572e045a31ada9eb` 的完整 workspace / all-targets 命令退出 0：**671 passed / 0 failed / 0 ignored，42 组结果**。计数包括原有跨 targets 重叠执行，不表示 671 个独立业务场景。没有把单线 638 / 652 或另一 C4 候选结果当本组合证据。

两路只读独立审查均核验同一固定源码：

- `/root/connector_followup_integration_review`：确认 connections.rs 与 owner 逐字一致，真实库测试导入、完整登记保持，断开 / 撤权认知 / generation / unknown 边界成立。独立 target `review-connector-followup-target` 实际执行 public_connectors + public_connections：19 / 19、exit0；同 targets 严格 Clippy exit0。未发现必须修问题。
- `/root/skills_followup_integration_review`：确认 skill_runtime.rs 与 owner 逐字一致、使用真实公开 JobSnapshot，Result 列表签名及登记保持；原取消只保留原结果、不自动停止或重发，get_run_snapshot 不成为全 Skill 进度。独立 target `review-skills-followup-target` 实际执行 public_skills / public_skill_runtime / public_pipeline / agent_workflow / agent_tools：50 / 50、exit0；同 targets 严格 Clippy exit0。未发现问题。

两审查者均加载已有工具环境，offline / locked；没有改文件、安装或外连。以上不构成生产授权 / 远端效果 / 设备验收。

原始日志在工作区 `/workspace/muyon-contracts-evidence/`，不入 git；摘要 SHA256：

| 日志 / 元数据 | SHA256 |
| --- | --- |
| followups-focused.log | `e739ec695bb9c2ecebc0d22cf730666966f41605e2ddafe0d388ca8307e7e4f7` |
| followups-focused-confirmed.log | `13f20dae15255b0803ccb4f3d24ef8c75985f3387d5f2f46eb544bd82cd19cea` |
| followups-focused-confirmed.json | `4671445f100a2b0aa72aa60cba5395133e3bec88ad07e230cc7d62431ebf2037` |
| followups-workspace.log | `434d1bcac82cbeca149eaf7099b863b091b4685a183771be7bf2ad13e3fd04af` |
| followups-clippy.log | `6e6cc9179205ea70a79a0616dbbf435a3f0d94451b66349b47d58324560082ed` |

Cargo.lock SHA256 保持 `d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`；pipeline.rs SHA256 保持 `34bd53d3d3dcf1d02f046d404b2210f50eee024e1ec0cf098edf6c1536042e8f`。
