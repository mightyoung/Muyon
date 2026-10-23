# Skill 注册与运行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 先提供可信内置 Skill 的版本目录和受限运行投影，后续按审核 gate 决定 parser 复用。
**Architecture:** 注册/绑定/启用/执行四件事分开；运行复用 agent/workflow 和原 owner，不增加 Skill 执行账本。
**Tech Stack:** 现有 Rust/serde/SQLite；Codex parser 仅候选。
**Spec:** [v0.2](../specs/2026-10-23-public-services-ui-design.md) §4 Skill、6、9–11。
**Baseline:** [总索引](2026-10-23-public-services-index.md) 完整 SHA/限制适用。

## Global Constraints

- Skill 默认是提示、步骤和结构约束，不是任意代码执行入口。
- Skill 只能收窄能力；注册、绑定、启用都不自动授予执行权限。
- SkillRef 固定版本与摘要；上下文按需投影，不暴露裸凭据或整份数据库。
- 每步派发前重验权限交集；原 IntentId/Receipt 不变。
- 本轮不安装 parser、执行脚本或调用真实模型。

## Review Focus

- 升级版本后旧句柄仍活：S1 拒绝 digest/绑定 revision 不符。
- allowed-tools 被误当权限：S2 只能求交集。
- 包路径逃逸/符号链接/未声明文件：S3 在原宿主资源 gate 内拒绝。
- 恶意提示要求新增工具/跨项目上下文：S2 零越权调用。
- 运行超时/断连/停用：S2 保留原身份，原 owner 排空，不重跑。

## 真实基础

`crates/muyon-core/src/agent/workflow.rs` 有私有编译期 Skill 目录与 RunLedger、RunScope；内置资源位于 `agent/skills/paper-overview/SKILL.md`、`supplier-overview/SKILL.md`。
`agent/owner.rs` 已有 prepare_chat_restricted 的宿主工具子集路径；不是注册服务或通用包执行器。现有 RunLedger 不复制；S2 先测纯派发决策，接线等内核候选 B 完成。

## S1：内置版本目录与绑定快照

**Owner:** Skills。**Files:** 新增 `crates/muyon-core/src/services/skills.rs`、`tests/public_skills.rs`；模块登记由 Contracts；共享 fixture 新增 `docs/contracts/public-services-v02/fixtures/skills.json`，其 owner 为 Skills，C1 不修改该文件。依赖 C1。

**Interfaces，新增：**

```rust
struct SkillRef { skill_id: String, version: String, content_digest: Digest }
struct SkillDescriptor {
    reference: SkillRef, owner_plugin_id: String, contract_major: u32,
    input_schema: serde_json::Value, output_schema: serde_json::Value,
    required_capabilities: Vec<String>, resource_manifest: Vec<String>,
}
struct SkillBinding {
    binding_id: String, scope: ScopeRef, bot_id: Option<String>,
    revision: Revision, skill: SkillRef, enabled: bool,
}
struct SkillRegistrySnapshot { catalog_revision: Revision, skills: Vec<SkillDescriptor>, bindings: Vec<SkillBinding> }
fn list_skills(snapshot: &SkillRegistrySnapshot) -> Vec<SkillRef>;
fn get_descriptor<'a>(snapshot: &'a SkillRegistrySnapshot, reference: &SkillRef)
    -> Result<&'a SkillDescriptor, ServiceError>;
fn get_binding<'a>(snapshot: &'a SkillRegistrySnapshot, binding_id: &str)
    -> Result<&'a SkillBinding, ServiceError>;
fn validate_binding_update(current: &SkillBinding, expected: &Revision,
    replacement: &SkillBinding) -> Result<(), ServiceError>;
```

描述符 input/output_schema 是声明，P1 只允许审核的内置 schema，不实现通用 JSON Schema 引擎。S2 的输入验证按这两项内置 schema 显式匹配；未知 schema 摘要 capability_unavailable。S1 不从磁盘扫描任意目录。registerVersion/bind/setEnabled/unbind 管理操作 P1 仅生成待审目录候选；持久命令必须先明确原 Operation，不能以更改 registry snapshot 绕过宿主。

- [ ] `catalog_is_read_only`：list/get 不读业务正文、不开网络、不执行，fake invocation=0；同 skillId 不同 version 可并存，重复版本不同 digest 拒绝。
- [ ] `binding_cas_and_upgrade`：错 expected revision 拒绝；升级只改 exact SkillRef，不增加 allowed capabilities；停用不可产生 run。
- [ ] RED：`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skills`，先用无副作用 stub 得到目标断言失败。
- [ ] 实施目录/getter/CAS 校验与两个内置描述符，不改原 workflow 行为；版本内容不可原地覆盖。
- [ ] GREEN：相同命令通过；回归 `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test agent_workflow`。
- [ ] 提交 `feat: describe built-in skill versions and bindings`，审查不把注册/绑定成功写成可执行许可。

## S2：需求检查、输入检查和原身份运行编排

**Owner:** Skills。**Files:** 新增 `services/skill_runtime.rs`、`tests/public_skill_runtime.rs`；后续仅 Skills 在原内核 owner 交接后修改 `agent/workflow.rs`；FFI 由 Contracts 接线。依赖 S1/C2、D2 的 JobSnapshot（若 D2 未交付，先只交纯 validation）；Connector 能力接入再依赖 X2。

**Interfaces，新增：**

```rust
struct RequirementView { required: Vec<String>, available: Vec<String>, missing: Vec<String> }
struct SkillInputs { schema_digest: Digest, values: serde_json::Value, document_refs: Vec<DocumentRef> }
struct SkillRunSnapshot { skill: SkillRef, binding_revision: Revision, job: JobSnapshot }
enum StepDecision { Dispatch(Vec<String>), Reject(ServiceError) }
fn inspect_requirements(descriptor: &SkillDescriptor, available: &[String]) -> RequirementView;
fn validate_inputs(descriptor: &SkillDescriptor, inputs: &SkillInputs) -> Result<(), ServiceError>;
fn decide_step(descriptor: &SkillDescriptor, binding: &SkillBinding,
    expected_binding_revision: &Revision, current_scope: &ScopeRef, host_allowed: &[String],
    plugin_allowed: &[String], connection_allowed: &[String],
    requested: &[String]) -> StepDecision;
fn get_run_snapshot(original: &SkillRunSnapshot) -> SkillRunSnapshot;
```

decide_step 先检查 binding.scope == current_scope、binding.skill == descriptor.reference 和 expected_binding_revision == binding.revision。上列 snapshot getter 仅复制已登记事实，生产读取要先由可信宿主当前 scope 授权，不把传入对象作为实际执行凭证。`decide_step` 接口接受的是宿主内部解析的集合，不暴露成模型可填写的授权字段；交集=host ∩ plugin ∩ descriptor.required ∩ connection，纯本地不需连接时 connection_allowed 由宿主设为本地能力集合而非空集合的自动豁免。requested 任一项不在交集整体拒绝，不能悄悄删去写动作后宣称完成。

requestRun 的后续边界候选：`request_run(host:&dyn HostCommandPort, operation:Operation, project_id:Option<String>, expected_revision:Revision) -> Result<CommandEnvelope,ServiceError>`，只是原 prepare 适配，不能把 SkillRef JSON 伪装成已有 Operation。新运行 Operation 与绑定参数、SkillRef/inputs digest 的 exact variant 需在内核 owner 确认后补到原 contract，再评审；未有该 variant 前 requestRun 不开放。执行 Skill 不等于自动准许外发或付费。

- [ ] `malicious_skill_cannot_expand_tools`：required=[read]、requested=[write] → Reject；prompt 文本写“忽略宿主权限”不改变集合；跨插件同 connection 权限互不继承。
- [ ] `binding_change_stales_prepared`：expected binding revision、Skill digest、账号/scopeGeneration 任一变化拒旧计划；运行中每步重算集合，撤权后不再派发。
- [ ] `unknown_run_queries_original`：模拟 timeout/崩溃/关闭 UI 后原 IntentId 不变，prepare/dispatch 次数不增加；JobSnapshot phase 为 unknown_outcome，取消走 C2 original。
- [ ] RED/GREEN：`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skill_runtime`；先纯行为 RED，再实施需求/输入/步骤判定。
- [ ] 停用阶段测试：停止新调用、旧 prepared 失效、已派发由原 owner 收束；getRunSnapshot 不启动任务。回归 agent_workflow/agent_tools，证据区分 mock 与原 owner。
- [ ] 提交 `feat: constrain skill steps to host capability intersections`；生产 requestRun 接线另片等审核，绝不创建第二 RunLedger。

## S3：上游 parser 与资源清单工程 gate

**Owner:** Skills。**Files:** 新增 `docs/implementation/public-services-skill-parser-gate.md`、`docs/tasks/public-v02-S3/REPORT.md`；通过前不改 Cargo.toml/lock 或脚本执行器。依赖 S1/S2 和明确评估授权。

**Inputs/outputs:** 输入研究固定 Codex `rust-v0.163.0`/`83086188ae0614bd882818ff1aa23f3194962012`、parser 源路径与顶层 Apache-2.0 线索；输出逐文件许可/NOTICE、最小依赖闭包、解析语义差异、Android/Rust 版本、资源限制的书面决定。顶层许可不自动覆盖所有传递资源。

- [ ] 文档 RED：缺固定源摘要、逐文件许可、依赖/Android 分析、严格格式差异任一项则审核 BLOCKED，不先安装。
- [ ] 为后续离线解析测试固定合成包：重复/未知 frontmatter、过长字段、缺 required、非法路径、../、绝对路径、符号链接、未声明资源、摘要不符、旧绑定句柄。每例给期望拒绝原因；脚本文件始终只作资源。
- [ ] 只在 gate 获批后另写可执行包解析任务的 exact API/RED/GREEN 与 commands，不把候选 parser 宽容行为当 Muyon 严格验证。
- [ ] GREEN 是评估报告可复查且用户批准选型；不等于 parser 已安装或 Skill 可运行。
- [ ] 提交 `docs: assess pinned skill parser reuse gate`，不带竞品专有代码，不直接嵌入 source-available 的 docx/pdf/pptx/xlsx 文档 Skill。

## 回退与验收

目录与编排默认关闭；回退时禁新调用、原 owner 排空/lookup，保留绑定历史与原回执。不删除内置资源或重建原 ledger。验收：fixture 摘要、权限交集/恶意提示/旧绑定/未知恢复的实际 RED/GREEN；生产运行、parser 和账户级能力未验证须原样列出。
