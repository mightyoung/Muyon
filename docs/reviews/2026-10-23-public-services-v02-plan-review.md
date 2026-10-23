# Muyon v0.2 公共服务整体计划审查意见

- 日期：2026-10-23
- 审查人：Claude（静态审查，独立于计划作者）
- 审查对象：分支 `docs/public-services-v02-plans-20261023`，提交 `64900d4a6a46a9ef2919bcf922fb059413b1ce82`（设计 1 份、分计划 6 份、总索引 1 份）
- 比对基线：develop `fd26dcdabcdac996bc2881e8141cac2b519966fc`（PR #107 合入后）
- 审查方式：阅读全部 8 份文档，并与 develop 源码做接口/路径比对。**未编译、未运行任何测试**；下文“事实”指可在上述 SHA 中复查的内容，“推断”指审查判断。

## 结论

方向正确（复用原 IntentId/Receipt、不建第二账本、只读不触发工作、能力取交集等安全边界清楚），但计划**当前无法推进**，且有几处与已定方向不一致、结构上会导致返工。建议先完成下列 4 项再继续执行：

1. 解除工具链阻断：固定 Rust 版本并允许执行环境一次性安装（**已获用户批准，见“已决定事项”**）。
2. 将六份计划按 `fd26dcd` 刷新，补 Office（含 PDF）独立交付线与 Electron 桥接任务。
3. UI 计划校验改为 Rust 单一实现、经 FFI 暴露；P1 内决定类型生成方案。
4. P1 增加一条端到端纵向切片；外部评审记录与提案落库。

## 已决定事项（2026-10-23 用户确认）

- 采用推荐方案：仓库固定 Rust `1.93.1`（与 `.github/workflows/muyon-product.yml` 现用版本一致），执行环境允许一次性安装该工具链及 `cargo fetch --locked` 依赖缓存，其后测试仍按 `--offline --locked` 运行。
- 本分支同时在仓库根提交 `rust-toolchain.toml`（计划命令均从仓库根以 `--manifest-path crates/Cargo.toml` 运行，rustup 按当前目录向上查找，故放在根目录）。这只是工具链固定，不是 C1 产品交付；C1 仍需从真实 RED 开始。
- 计划中“本轮不安装依赖”的约束相应修订为：除上述固定工具链和锁定依赖外，不安装其他依赖、不下载模型。

## 发现

### F1 执行阻断：关键路径全部停在 C1（事实，高）

- `task/public-contracts-v02-20261023` 的 `docs/tasks/public-v02-C1/REPORT.md` 记录 cargo 不存在，状态 BLOCKED；所有分计划依赖 C1。
- 仓库此前没有 `rust-toolchain.toml`，各环境版本不统一；而 `task/office-rust-boundary-fix-20261023` 的证据中有 `toolchain-install.log`，说明其他任务装过工具链，环境策略前后不一致。
- 处理：见“已决定事项”。

### F2 与已定方向的偏差（事实 + 推断，高）

- **Office/PDF**：已定方向是 Office（Word/PPT/Excel/PDF 阅读 + 适度编辑）由 Rust 引擎在各前端本地运行，手机端必须可用。计划中 Office 只出现在 D3 工程 gate（P3、另行授权）；设计 §2 写“OCR、PDF 或向量引擎可按平台选择成熟实现，不要求全部改写为 Rust”，与该方向不完全一致。develop 已有的 `crates/muyon-office` 只覆盖 OOXML，**PDF 没有任何交付线**；`task/office-rust-boundary-fix-20261023` 仍有 6 个提交未合入。
  - 建议：新增独立“Office/PDF 引擎”计划，作为 DocumentPort 的平台实现，在 P1/P2 有明确交付；设计 §2 对 Office/PDF 的表述改为“Rust 本地引擎”，OCR/向量仍可按平台选型。
- **Electron 桌面**：已定为目标平台，但六份计划全部面向 Android/Kotlin，桌面只写“框架未选、后置”，没有 Rust→Node 桥接（如 napi-rs）与 TS 类型的任何任务。
  - 建议：P1 增加桌面桥接 spike（选型 + 最小只读调用），否则公共合同只在 Android 上被验证。

### F3 安全校验多语言重复实现（推断，高）

- U1 计划用 Kotlin 手写 `PresentationModels.kt` / `PlanValidator.kt`，靠 C1 JSON fixture 与 Rust 对齐；桌面落地后还需 TS 再写一套。UIPlan 白名单、`approved` 字段拒绝、深度/大小限制、来源绑定属于安全边界，多份实现必然漂移。
- 已有 UniFFI（`crates/muyon-android-ffi`）。建议：`validatePlan` 及公共值解析（revision、UnixMs、页码转换）放在 Rust，Kotlin/Electron 经 FFI 调用，前端只保留渲染与局部状态。
- 设计 §10 要求“schema、编解码与 fixture 来自同一事实定义”，但计划把 IDL/生成器推到工程 gate。建议在 C1 内决定（候选：UniFFI 覆盖 Kotlin；schemars 导出 JSON Schema 或 ts-rs/specta 生成 TS），避免先手写后迁移。

### F4 计划基线已过期（事实，中）

- 计划基于 `7aa852ab`；PR #107（`fd26dcd`）修改了 `crates/muyon-core/src/agent/workflow.rs`（+3）与 `crates/muyon-android-ffi/src/lib.rs`（+100），正是 C2、S1、S2 引用的文件；设计中 `workflow.rs#L95-L122` 等行号链接需复核。
- 总索引“FFI 接线等 B 内核审查完成”的前置已满足（#107 已合入），C2 的 FFI 接线 gate 可相应更新。

### F5 交付节奏缺少用户可见闭环（推断，中）

- P1/P2 全是纯类型、投影与 fake host 测试，生产入口默认关闭；端到端全部在 P3，而 P3 又全是“另审 gate”。合同在无真实消费方时冻结，返工风险高，也难以对照产品目标“完成用户任务、易用”衡量进展。
- 建议：P1 增加一条纵向切片并作为 C1–C2、D1、U1 的验收消费方，例如科研场景：本地 UTF-8/Office 文档导入 → 版本绑定文本读取 → 来源锚点 → SourceCard → 原回执展示，在 Android 真机跑通（可不含 OCR/向量）。

### F6 合同细节缺口（事实，中）

1. **C2 错误阶段不可判定**：映射表依赖“可信 preflight 拒绝”与“派发后丢失”区分 not_started/unknown，但现有 `ProductCore::prepare/confirm_user_plan/lookup_original/cancel_original`（`crates/muyon-android-ffi/src/lib.rs` 约 765–821 行）返回 `Result<String, ProductError>`，不携带阶段信息。适配层无法判断时只能一律 unknown。建议：要么由 ProductCore 增加显式 phase/dispatch 标记（需原 owner 评审），要么 C2 明确默认 unknown + after_lookup，并删去依赖阶段的分支。
2. **缺金额/数量类型**：设计 §3 要求“金额用十进制与币种、数量带单位”，C1 只有一句说明，没有 `Money`/`Quantity` 定义；B2 询价直接依赖。建议在 C1 定义（十进制字符串 + ISO 4217 币种；数量 + 单位码）并加 fixture。
3. **`ServiceError.phase` 为自由字符串**：建议改为枚举（如 preflight/prepare/confirm/dispatch/lookup/cancel），否则无法稳定测试与映射。
4. **D1 以 `receipt_id` 充当 `ResultId`**：两个 ID 空间混用，需在合同中显式说明或给出转换规则，避免日后 ResultId 与 Receipt 被误比较。
5. **ID 长度上限 128 字节**：需核对现有 IntentId/plan_id 实际生成格式不超限，并加反例 fixture。

### F7 过程与仓库卫生（事实，低）

- 远端约 413 个分支，大量 lab/review/handoff 已过期；建议按日期批量归档（tag 后删除）。
- 证据协议要求“原始日志保留仓库外”，但同期分支（如 `task/office-rust-boundary-fix-20261023`、`task/bot-core-continuation-20261023`）提交了数百行 log，口径不一致。
- 设计认可记录、研发独立设计提案、Connector/Skill 研究均在外部 ChatGPT 页面，仓库内不可复查。建议导出为 `docs/design/2026-10-23/` 下的 Markdown 并在计划中改链。
- 六个 owner 角色“尚未指派人员”；Contracts 独占 `services/mod.rs`、`muyon-core/src/lib.rs`、FFI `lib.rs` 串行登记，将成为瓶颈。建议各模块自带 `mod` 声明、Contracts 只审不独写，或一次性预登记空模块。

## 建议的计划修订清单

| # | 修订 | 涉及文件 |
| --- | --- | --- |
| 1 | 工具链约束改为“固定 1.93.1 + 锁定依赖可安装一次” | 总索引 Global Constraints、执行与证据协议 |
| 2 | 基线改为 `fd26dcd`，复核 workflow.rs/FFI 引用与行号 | 总索引、contracts、skill-runtime、设计 §4 |
| 3 | 新增 Office/PDF 引擎计划；设计 §2 表述修正 | 新计划文件、设计 §2/§4 |
| 4 | 新增 Electron 桥接 spike 任务 | 总索引分期表、intelligent-ui |
| 5 | U1 校验迁 Rust + FFI；C1 决定类型生成方案 | intelligent-ui U1、public-contracts C1 |
| 6 | P1 增加端到端纵向切片及验收 | 总索引分期表 |
| 7 | C2 错误阶段处理、Money/Quantity、phase 枚举、ResultId 说明 | public-contracts C1/C2、document-pipeline D1 |
| 8 | 外部评审记录落库、分支归档、证据口径统一 | docs/design、docs/tasks/README.md |

## 未覆盖范围

- 未运行任何 Rust/Kotlin 构建或测试，未验证 CI 现状。
- 未审查 Shell 在途任务与 Office 未合入提交的代码质量。
- 未访问外部 ChatGPT 评审页面，相关结论仅依据仓库内文字。
