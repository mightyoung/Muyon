# 公共服务计划历史评审的事实附记

日期：2026-10-23。对应原评审提交 `8a3064b207ee5a02374b5cbcb179e419580a56bf`，集成基线 `fd26dcdabcdac996bc2881e8141cac2b519966fc`。原评审保持原样；本附记区分历史观察、后续核查与尚未批准的建议。

- **Office 提交关系不等于功能缺失。** ahead 6 / behind 50 是 ancestry。父任务独立核对当前 develop 的 `edit.rs`、`xml.rs`、`tests/boundaries.rs`，归一化后与 Office 分支相同；不得重复 cherry-pick 已集成修复。产品并非因此具备全部 Office fidelity 或编辑能力。
- **已有有界 PDF 阅读入口。** Android `NativeDocumentPreview` 已使用有界 `PdfRenderer`；不能称完全没有 PDF 交付。完整 Rust PDF 引擎、PDF 编辑与跨平台交付仍需独立设计和验证。
- **F1 是历史环境状态。** 三条依赖工作线已恢复批准的固定工具链。本次隔离验证也恢复官方 Rust 1.93.1，根目录、`crates/` 与 `crates/muyon-core/` 实际解析均由根文件覆盖；fmt/clippy 组件可运行。这不是 C1 合同交付，亦不代表所有环境已安装。
- **F4 的当前基线有效。** PR #107 已合入，`fd26dcd` 是本轮有效基线；引用行号和依赖仍须由对应 owner 按固定版本维护。
- **F6 进入原 Contracts 工作线。** 未能证明阶段时保留保守 `unknown` / `after_lookup`；`ProcessingReceipt` 不等同业务回执；原 ID 文法兼容性应通过 fixture 明确。此附记不声称这些合同实现已完成。
- **架构建议不是自动批准。** 全 Rust PDF、napi-rs、全部 UI 校验迁 Rust 等仍是独立架构选择；本次工具链固定不实施这些建议，不创建第二账本、第二 authority 或第二合入者。
- **不按日期批量删分支。** 仅按明确授权处理相应组合验证分支；本次不删除任何分支、提交或工作目录。PR #108 的用户视觉 HOLD 独立保留。

## 根工具链的验证范围

固定 `1.93.1 / minimal / clippy / rustfmt` 与现有产品工作流版本意图一致。根文件约束 rustup 代理的目录解析，不代表工具已经安装，也不覆盖显式 `+version`、`RUSTUP_TOOLCHAIN` 或直接工具链二进制的选择。

现有产品 `product_paths` 原先不含根文件。本候选仅补 `rust-toolchain.toml` 一项，push/PR 共用原别名；所有 Rust、双 ABI、绑定、Android、模型许可与包体 gate 保持原样。精确候选须接受实际 hosted CI，不能借 PR #107 的结果。

历史 lab 若仅执行 `rustup default 1.99.0` 后调用普通代理，检出根文件后会选择 1.93.1；例如 `frontend-service-loop.yml` 的原 1.99.0 校验可能拒绝。原校验与 target 要求不变，本轮不执行或改环境绕过这些实验。更近的 `spike01-native-lab/rust-toolchain.toml` 仍独立生效。若以后确需继续某条旧 lab，须另核其固定版本与授权；不能用本次生产验证冒充旧 lab 通过。

本次不调用真实模型、搜索、凭据或付费接口，不恢复 Reader/I04 停止操作。原评审中的未测试声明和其他未验收边界仍然保留。
