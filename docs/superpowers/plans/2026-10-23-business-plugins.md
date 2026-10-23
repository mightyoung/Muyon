# 三业务插件公共接口迁移与研发闭环承接 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 科研、询价先复用已有 Rust 领域与公共投影；研发管理先承接独立提案的公共依赖和阶段验收，不冻结尚待评审的全领域代码。
**Architecture:** 公共服务拥有资料与来源，领域模块拥有业务规则；三者使用同一 UI/草稿/Skill/Connector/原回执。Workspace 身份和权限归宿主，研发 Team 只是业务配置。
**Tech Stack:** 已有 Rust research/business，Kotlin 公共 UI；研发产品模型和桌面页面待独立设计评审。
**Spec:** [已认可公共 v0.2](../specs/2026-10-23-public-services-ui-design.md) §9；[研发独立设计提案](https://chatgpt.com/space/page_c3e02abcc00c8191a4353c4338faa0ea)（2026-10-23，未实施、待评审）。
**Baseline:** [总索引](2026-10-23-public-services-index.md) 的完整 SHA、owner 和约束适用。

## Global Constraints

- 业务插件不复制 OCR、embedding、索引或文档真源。
- 公共合同不得引用某个插件的业务类型；跨插件访问仍重验 scope。
- Agent 完成不等于任务验收、PR 合入或发布；发布记录不等于自动部署。
- 新研发设计提案尚未获用户评审通过；本轮只设计/规划，不编码、不扩外部写入授权。
- 旧 Linear 研究的独立 operationId/账本建议以 v0.2 原 IntentId/Receipt 为准。

## Review Focus

- 领域附件 BlobRef 无公共 DocumentRef：B1 显示未绑定，不能猜 documentId。
- 提取报价文本被当成交承诺：B2 领域规则保留币税运/有效期校验。
- PR force push 或新 commit：B3 旧 SHA 的 CI/review 只作历史，不能验收新版本。
- 开发 Agent 自签验收：B3 拒绝，执行事实与人工业务判定分开。
- 项目/任务统计、收件箱、搜索泄露不可读对象：B4 所有结果都受宿主 scope 限制。

## 已有路径，不误认功能完成

`crates/muyon-core/src/research.rs` 有 PaperRecord/DocumentRecord/PaperBinding、BusinessStore::papers/project/attachment 相关受控接口；
`business.rs` 有 SupplierRecord 及 `supplier(&self,id:&str)->Result<SupplierRecord,ContractError>`、`suppliers(&self,limit:u32,offset:u32)->Result<Vec<SupplierRecord>,ContractError>`。
`agent/workflow.rs` 现有两项内置 Skill；
Android `product/research/ResearchScreen.kt`、`product/supplier/SupplierScreen.kt` 与 `product/ui/cards/` 已有部分读取/卡片；
`packages/research_module`、`packages/inquiry_module` 仅供旧领域语义参考，不恢复 Flutter。
当前没有可声称完整研发全周期的 Rust 公共业务模块，计划明确以“拟新增”标识。

## B1：科研/询价领域快照与公共引用适配

**Owner:** Domain。**Files:** 新增 `crates/muyon-core/src/domains/mod.rs`、`domains/research_projection.rs`、`domains/inquiry_projection.rs`、`tests/public_domain_projections.rs`；C1 owner 修改 lib.rs 登记 domains，Domain 拥有 domains/mod.rs。依赖 C1/C2/D1。本片只读投影，原 business/research DB 不迁移。

**Interfaces，新增并完整定义：**

```rust
enum DocumentBindingView { Bound(DocumentRef), Unbound { reason: String } }
struct ResearchView {
    paper_id: String, project_id: String, revision: Revision,
    title: String, documents: Vec<DocumentBindingView>,
}
struct SupplierView {
    supplier_id: String, scope: ScopeRef, revision: Revision, name: String,
    documents: Vec<DocumentBindingView>,
}
fn project_paper(paper: &PaperRecord, documents: &[DocumentRef]) -> Result<ResearchView, ServiceError>;
fn project_supplier(supplier: &SupplierRecord, scope: &ScopeRef, documents: &[DocumentRef]) -> Result<SupplierView, ServiceError>;
```

DocumentBindingView 是领域展示类型，不进入公共 services/types.rs；禁止裸路径/BlobRef 伪装 DocumentRef。documents 输入由宿主当前授权映射取得；投影检每引用 scope/project 与领域对象一致，实际打开走 D1 重验。无映射产生 Unbound(reason="document_binding_unavailable")，保留附件存在事实，不声明全文已读。SupplierRecord 已核实字段为 id/payload/revision/deleted，name 取 payload.name；它不含 project_id，scope 必须来自宿主已有供应商读取上下文，不能从 supplier 猜测。deleted=true 拒绝投影为当前可用。projection 不复制 raw_json/无关备注到 UI。

- [ ] `shared_documents_are_references_only`：一份文档在科研/询价有各自权限投影，引用不复制 bytes；无法授权映射→Unbound；不同 project 的 document 拒绝。
- [ ] `domain_revision_is_exact`：领域 revision 字符串原样往返；raw_json/secret/内部 DB/path 不出现在序列化 view。
- [ ] RED：`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_domain_projections`；先结构 RED，再行为 RED。
- [ ] 实施纯投影与合成 PaperRecord/SupplierRecord fixture，不改既有导入逻辑；生产调用方必须宿主获取真实 record。
- [ ] GREEN：同命令通过；回归 `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test research --test business`。
- [ ] 提交 `feat: project existing domain records through public references`；不接 UI Shell 现有页面。

## B2：两既有插件的合同验收与逐片接入

**Owner:** Domain；PublicUI 拥有通用卡片，Contracts 拥有原命令适配。**Files:** 新增 `crates/muyon-core/tests/public_plugin_conformance.rs`、`docs/contracts/public-services-v02/fixtures/plugins.json`、`docs/tasks/public-v02-B2/REPORT.md`；领域语义后续修改由 Domain 独占 `research.rs/business.rs`，页面接入等 Shell owner 交接。依赖 B1/U1/C3/D2，Skill/Connector 接入另依赖 S2/X2。

**Inputs/outputs:** 输入 B1 ResearchView/SupplierView、C2 OriginalLookup、D2 JobSnapshot、U1 的共享 fixture；输出 `PluginConformance { owner_plugin_id: String, passed_cases: Vec<String>, failed_cases: Vec<String> }`（新增测试内数据类型，非产品合同）。测试入口 `run_conformance(owner_plugin_id:&str, fixture:&serde_json::Value)->PluginConformance` 仅在本测试文件定义，两个受信内置插件运行同一批断言，研发后续使用同 fixture 扩展，不改预期。

- [ ] 科研测试：提取成功≠纳入研究；SourceLocator 只定位原文，ClaimSupport=Unassessed 不标可信；纳入/排除须领域原命令，不从 ResultList 点击自动提交。
- [ ] 询价测试：币种、数量单位、税/运口径、有效期缺失保留 unknown，金额不经 f64；提取文本/embedding 相似度不能把报价标可成交。
- [ ] 共同测试：局部编辑不写业务库/外发；草稿 ack 只承认精确修订；重复点击沿原身份；unknown 先原查询；取消不显示停止；共享连接仍按插件隔离。
- [ ] RED/GREEN：`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_plugin_conformance`；不得 mock 出业务成功以消除门禁失败。
- [ ] 实施仅必要适配；现有支持以外的领域动作返回 unavailable。插件 data/relation、operation、view 声明是版本元数据，登记不迁库/不授权/不跑脚本。
- [ ] 每插件单独提交 `test: verify research public service conformance` / `test: verify inquiry public service conformance`；只有依赖合入且接口稳定才另写页面接入小任务，避免顺手修改全站。
- [ ] UI 交付要求由 U0/U3 跟踪：组件存在、具体页面接入、视觉/交互验收分别标状态；配置连接复用 FormCard/Confirmation/Receipt。

## B3：研发完整生命周期提案承接 gate（文档，禁止提前编码）

**Owner:** Domain。**Files:** 计划未来新增 `docs/design/2026-10-23/dev-management-domain-review.md`、`docs/implementation/dev-management-public-service-map.md`、`docs/tasks/public-v02-B3/REPORT.md`。本轮仅本实施计划引用提案；不把提案存成已批准规格。依赖独立设计页面评审、C1/C2/U0。

**Inputs/outputs 的精确文档签名：**

`reviewDevelopmentProposal(proposalUrl, proposalReadSequence, publicSpecPath, baselineSha) -> {status: proposed|changes_requested|approved, domainDictionary, transitionTable, commandCapabilityMatrix, publicDependencyMap, scenarioEvidence, unresolvedDecisions}`。

输入 proposalUrl 固定为上方 page_c3e02abcc00c8191a4353c4338faa0ea，baselineSha 用实施时重新核对的完整 develop SHA。该签名是文档评审封套，不是拟议 Rust/IPC API；不得据它创建执行入口。只有用户实际评审可写 approved。需要原始 DTO/持久 schema 的代码计划在设计获批后另交审阅，不在本轮替用户冻结。

| 领域链路与关系 | 一期最小闭环 | 后置与公共依赖 |
| --- | --- | --- |
| Intake 来源/分诊 → Issue | 手工/对话草稿，保留原文；接受/补充/延后/拒绝/重复与明确目标；一需求可拆多个任务 | Connector 自动收集后置；C3 草稿、D1 来源、C2 原命令 |
| Project/Milestone/Cycle → Issue | 基本项目目标、边界、负责人；Issue 有修订和验收条件 | 里程碑可验收成果、周期时间盒/容量独立对象，完整排程 P2；不互相冒充 |
| 任务/关系 → 开发交接 | 指派人与执行 Agent 分开；任务包含需求修订、完整基线 SHA、允许动作/预算；开发可外部完成 | 子任务/阻塞/重复/项目依赖环规则与完整周期规划 P2；S1/S2、C2 |
| 开发成果 → PR/Review/CI | 人工关联仓库、PR、完整 head SHA、目标基线、受测 SHA、核验时间/来源/未知；一任务多 PR、一 PR 多任务 | 已授权 GitHub/GitLab/Gitee 信息同步再依赖 X2/X3/X4；merge synthetic commit 另记 parent SHA；外部写入 P3 |
| 固定需求/代码版本 → Acceptance | 人工逐项验收、验收人/结果/证据；旧 SHA CI 与旧验收标过期 | 自动辅助只给建议；Agent 无自签验收权；同新 commit 重判覆盖项 |
| 已验收项 → ReleaseRecord | 本地发布记录草稿、待核验、记录完成；目标 commit、说明、已知问题 | 外部发布事实来源/时间独立；部署不在首轮授权 |
| 发布/旧验收 → Feedback/Bug | 反馈绑具体版本，生成 Intake 或重开，保留旧验收/回归历史 | webhook/跨端/聚合收件箱 P2，真实同步须 Connector 与订阅 gate |

Workspace/scope/身份/权限只引用宿主；Team 仅研发业务设置，不创建另一成员授权库。保存视图只存查询不复制 Issue，跨团队项目统计/通知不可泄露不可读对象。

- [ ] 文档 RED：用虚构“Android 断网编辑丢内容”样例逐格走查，任一节点缺输入版本、owner、输出证据或失败状态即 changes_requested，不虚构软件测试日志。
- [ ] 列正常与反例断言：新 head SHA 后旧 CI 不能绿；AgentRun completed 不改 Issue=完成；无人工 Acceptance 不进已验收；ReleaseRecord 完成不等于 deployed；反馈重开不抹旧验收；重复提交沿原 IntentId 查询。
- [ ] 列四个主要工作入口及详情页的公共组件需求：我的工作/分诊/项目/收件箱，Issue 详情含原需求、关系、执行、代码证据、验收、活动；Android 单列与桌面多栏只是提案，尺寸/组合仍交 U0 审阅。
- [ ] GREEN 是用户认可领域字典、状态转换、完成定义、离线边界、证据保留与GitHub/GitLab/Gitee 三方各自的只读能力集（能力不要求完全同构）；在无认可前明确 status=proposed。
- [ ] 正常文档提交 `docs: map proposed development lifecycle to public services`，不改 Cargo/lib.rs/schema，不发外部请求、不合 PR。

### B3 补充：对话渐进建项、离散补充与持续仓库事实

这是新增的领域设计输入，仍未实施、待评审。Muyon Agent 可在多轮对话渐进形成项目草稿，任意轮次加入需求、Bug、问题、链接与附件。草稿保存依赖 C3，原话/消息修订/文档来源依赖 D1，白名单卡片/差异确认依赖 U1/U2，候选整理依赖 S1/S2；明确提交沿 C2，UI/Skill 没有新执行入口。

- [ ] 在 B3 设计走查加入精确候选封套字段：conversationId/messageId/messageRevision、sourceRanges、draftRef/draftRevision、candidateId、candidateKind（Project/Intake/Issue/Question/Link）、proposedProjectRef、ambiguityChoices、duplicateCandidateRefs、baseEntityRevision、proposedDiff、userLockedFields、originalIntentId（未提交为空）。这是领域候选封套，正式 Rust 类型签名待领域评审后由 B4 定义，不能当已冻结公共类型。
- [ ] 同一句可拆多个候选；不同轮次的上下文不自动成为项目事实。项目归属不明确先 ChoiceCard 消歧；重复候选可关联/合并/忽略，合并须展示差异，不能自动吞掉新内容或覆盖 userLocked。
- [ ] 草稿保存/候选接受/业务提交分别确认；每次改项目、参数或 baseEntityRevision 使旧 prepared 失效。重启恢复草稿不恢复授权、不自动提交历史消息。明确提交每个对象可给独立结果，部分接受不伪装全成功。
- [ ] 反例走查：新对话提到旧项目名称但有同名项目、重复发同一需求、冲突描述、两项目附件混入、保存中断、撤权、一次消息多对象且只确认一个；期望无误归属、无隐式写入、无权限扩大，原意图未知先查询。

持续仓库信息同步由公共 Connector/X4 拥有连接、能力、来源事件与断线对账；Domain 拥有 Issue/Project 关联、证据过期与可配置进度规则。commit/push/branch/PR或MR/CI/issues 都作为外部事实输入，不按 provider 私有状态文本直接驱动“完成”。每个 provider 的能力可用/缺失/未知独立显示；自动规则提交仍走宿主原命令/回执，不能新增业务执行账本。发布记录、实际发布、验收、PR 合入和 Agent 完成五种事实分开。

## B4：获批后编写研发一期执行计划与 P2/P3 gate

**Owner:** Domain。**Files:** 仅在 B3 获批后新增 `docs/superpowers/plans/<评审日期>-dev-management-phase1.md` 和后续任务说明。拟产品父目录为 `crates/muyon-core/src/domains/development/`，当前不创建、不冻结内部文件或类型。依赖 B3 approved、B1/B2、C3/D1/U2；真实只读代码证据还依赖 X2 的宿主授权链。

**Inputs/outputs:** `planDevelopmentPhase1(approvedDomainReview, actualPublicInterfaces, baselineSha) -> {fileOwners, exactRustSignatures, operationVariants, additiveMigration, redGreenCases, commands, acceptanceMatrix, rollback}`。仍是文档输出，需列确切实际签名后另审实施。

- [ ] 一期任务必须覆盖手工 Intake → Project/Issue/验收条件 → 外部开发交接 → 人工证据关联 → 人工验收 → 发布记录 → Bug 回流；不能只交看板便宣称闭环。
- [ ] 固定证据测试预期：head=A/CI=A 可评估，head=B/CI=A 标 stale；syntheticMerge=M 必须记录 parents=[A,base]；review/CI 未核验不等于 fail 或 pass；无权数据不进入统计/通知。
- [ ] 将 shared conformance 扩展到研发，沿 B2 fixture 和 C2 身份；新原 Operation 由 Domain 设计、Contracts 接线、原 owner 持久化，绝不新建 operationId 账本。
- [ ] 每片写 exact 单测文件、行为 RED/GREEN 命令、恢复/冲突/重启草稿证据与唯一 schema owner；工具缺失记录 BLOCKED，不下载。
- [ ] P2 gate 列出 Milestone/Cycle、完整依赖/父子/重复关系、保存视图、收件箱、跨端冲突；循环/自环拒绝，旧计划历史保留。
- [ ] P3 gate 分别评审建 PR、评论、请求 review、合并、tag；每类独立授权/预览/回执/未知对账；不含部署，不把“推进任务”当万能命令。
- [ ] 交用户审阅新执行计划，批准前维持未实施。新计划 RED/GREEN 是未来要求，当前不报告任何产品通过。

## 回退与验收

科研/询价快照适配可关闭，原 Rust 领域继续 owner；不回滚原数据和回执。未来研发用加法 schema/feature gate，停用保留业务历史与原未决意图，禁止丢表或覆盖旧验收。当前验收只检查文档依赖映射完整、已有路径真实和未批准项显式标识；研发一期真实闭环、三方仓库同步、Connector 核验和跨端均尚未实现。
