# Connector X1 / X2 公共库登记报告

日期：2026-10-23。状态：离线候选，待 B 审查合入；不代表生产 Connector 已接通。

## 固定输入与范围

- 当前远端 develop 核对为 `fd26dcdabcdac996bc2881e8141cac2b519966fc`。
- 原 Connector 候选：`38d094518e495b4296e42483fcb58c0d5de87524`，含已交付 Contracts HEAD `4d49a580cb518d9b0b80c9df3df1ff564194a639`；源码独审点 `86534f4126835b46af3c7ec818de184491128be9`。
- 隔离候选分支：`task/public-v02-connector-registration-20261023`。未改写原候选历史。
- 登记源码提交：`efc710b5db269a1e29c644fc87c1d2f55c6537cd`；最终验证源码：`60186eef3332936c7f85325852b35c7bba981c15`（后者仅修正测试导入格式）。

本次产品差异只有三文件：`services/mod.rs` 新增 `pub mod connections;` / `pub mod connectors;`；`public_connections.rs` 与 `public_connectors.rs` 移除 `#[path]` 本地模块副本，改用真实 `muyon_core::services` 导出。既有测试主体和断言保持，模块源码与 fixture 未变。没有修改 core lib.rs 或 FFI lib.rs。

## 实际验证

使用此前获准、校验过的工作区 Rust / Cargo 1.93.1 与 Cargo.lock 缓存，加载 `/workspace/muyon-contracts-tools/env.sh`。所有 Cargo 命令均为 `--offline --locked`，未安装依赖或升级锁文件。

1. 原候选直接编译模块的基线：X1 7 / 7、X2 6 / 6，退出码 0。
2. 两测试改为公共库导入但尚未登记：退出码 101，`unresolved import muyon_core::services::connectors/connections`。这是结构性 RED，不冒称行为断言 RED，也未保存为不可变 RED 提交。
3. 完成登记后的公共库 GREEN：X1 7 / 7、X2 6 / 6，退出码 0。
4. 固定最终源码 `60186eef3332936c7f85325852b35c7bba981c15`：完整 workspace / all-targets 回归退出码 0，38 组结果、632 passed / 0 failed / 0 ignored。计数含原有重叠 targets，不表示 632 个互异产品场景。
5. 同一固定源码的 core all-targets Clippy `-D warnings` 退出码 0；三份变更 Rust 文件的 rustfmt --check、git diff --check 通过。首次格式检查报告导入排序差异，已通过上述普通后续提交修正，未改写历史。

命令（仓库根目录）：

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connectors --test public_connections
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --all-targets --offline --locked -- -D warnings
rustfmt --edition 2021 --check crates/muyon-core/src/services/mod.rs crates/muyon-core/tests/public_connections.rs crates/muyon-core/tests/public_connectors.rs
```

原始日志保存在工作区 `/workspace/muyon-contracts-evidence/`，本报告只提交摘要与 SHA256：

| 日志 | SHA256 |
| --- | --- |
| connector-registration-baseline.log | `fd0212091a4e8fddc71e10487834304013de8cbc7f893e34096b4565101f33e1` |
| connector-registration-red.log | `468adc649df5084de7ad3ec58cb7a7217279e187031f773f8550856c6661e302` |
| connector-registration-green.log | `3c3d653664100f490b83658fa31c25856fd36edec87d7878e4d6e5b7d2d664c1` |
| connector-registration-workspace.log | `4353f7212f306d67569cb6556a06cb61f566a6de43b8a4fdc4b38466c4f949c4` |
| connector-registration-clippy.log | `07460fbf17de96062c25c2f9c6fc410d5f192f6ab4a219838ea9ad850187bddf` |

Cargo.lock SHA256 保持 `d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`；Connector fixture SHA256 保持 `bc8930b884475f8bf4d6c02413ac3c4d3a3e13618ababd69f32596cb160dff59`。

## 独立审查

只读审查者 `/root/connector_registration_review` 比较固定基线与最终源码，确认差异限三文件、测试断言未削弱、共享类型来自真实库、没有新增 dispatch / 网络 / 凭据 / 持久化路径；无阻断缺陷。

审查者在单独的 `/workspace/muyon-contracts-tools/review-connector-export-target` 执行上述 scoped test 命令，实际退出码 0，X1 7 / 7、X2 6 / 6。审查后 HEAD 不变、工作树干净。此结论只覆盖导出登记与离线契约。

## 边界与回退

真实外部连接、远端授权与撤权、MCP transport、生产 dispatch 和生命周期效果仍未实现 / NOT_RUN，沿原 X1 / X2 报告限制。Skills 等其他 owner 候选未纳入本登记；其最终修订交付后另立提交。Reader 阻断、历史真实请求 unknown 与费用未知保持。

仅 B 可合入 develop。本次未改 main / develop、未强推、未删分支或部署。回退可在普通提交中移除两行登记，并将测试导入恢复到原候选方式；无数据迁移、业务回执删除或新执行账本。
