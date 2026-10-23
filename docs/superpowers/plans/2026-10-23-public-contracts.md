# 公共合同与原意图回执 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供公共序列化事实与原命令的受限适配，不替换已有执行权威。
**Architecture:** Rust serde 定义是首批事实源，共享 JSON fixture 校验 Kotlin 消费；暂不选 IDL 或新增 TypeScript runtime。执行仍调用 ProductCore 原方法。
**Tech Stack:** muyon-core、muyon-android-ffi、现有 serde/serde_json；无新增依赖。
**Spec:** [v0.2](../specs/2026-10-23-public-services-ui-design.md) §2–4、6、10。
**Baseline:** 完整 SHA、并行边界和证据协议见[总索引](2026-10-23-public-services-index.md)，其 Global Constraints 全部适用。

## Global Constraints

- IntentId 继续由既有宿主机制管理；JobId 仅关联执行任务。
- revision / expectedRevision 使用规范十进制字符串，不转成 JavaScript Number，不跨对象比较大小。
- 模型、卡片或插件不能自报 approved=true；确认卡只能从可信 prepared 状态生成。
- DraftPort 仅保存草稿，不等于提交业务对象。
- 本文所有新增接口均为待实施候选，未宣称已接通。

## Review Focus

- 9007199254740993、u64 上限与溢出：C1 精确 roundtrip，现有 Revision 保持 u64 上限，不擅自放宽。
- 重复 JSON key 和授权相关未知字段：C1 拒绝；未知可选展示字段只能在显式允许的位置忽略。
- lookup 返回 not_submitted：C2 不强行反序列化为 ExecutionResult。
- 丢失回执或取消后未停：C2 保持原身份与未知，不制造终态。
- 保存旧草稿的 ack：C3 不能标新草稿已保存。

## 已核实的路径与差异

`crates/muyon-core/src/contract.rs` 已有 Revision/Scope/AuthorityBinding/Operation/CommandEnvelope/ExecutionResult/Receipt；
`crates/muyon-android-ffi/src/lib.rs:754` 原签名如下，返回 String 为既有 JSON 传输，不是新公共任意方法入口：

```rust
ProductCore::prepare(&self, operation_json: String, project_id: Option<String>,
    expected_revision: String) -> Result<String, ProductError>
ProductCore::confirm_user_plan(&self, plan_id: String) -> Result<String, ProductError>
ProductCore::lookup_original(&self, intent_id: String) -> Result<String, ProductError>
ProductCore::cancel_original(&self, intent_id: String) -> Result<String, ProductError>
```

prepare 返回 CommandEnvelope；confirm/cancel 返回 ExecutionResult。lookup_json 另有 status=not_submitted、error=confirmation_not_received、recovery_action=edit_new_draft 的封套，不能套用统一 ExecutionStatus 枚举。原 ExecutionStatus 仅 Pending/Unknown/Committed/Rejected/Cancelled，没有统一 Job 枚举；AgentOwner::Observation 是另一 owner 的快照，不能把两个状态域混为一谈。

`bot_drafts.rs` 的 read/save/lookup_save/prepare_save 和 Android `chat/persistence/HostDraftSaveState.kt` 已实现特定 Bot 草稿行为，不能直接命名为泛领域存储。

## C1：公共类型、兼容规则与共享 fixture

**Owner:** Contracts。**Files:** 新增 `crates/muyon-core/src/services/types.rs`、`services/mod.rs`、`crates/muyon-core/tests/public_service_types.rs`、`docs/contracts/public-services-v02/fixtures/types.json`；修改 `crates/muyon-core/src/lib.rs` 仅登记 services。依赖：无产品候选合入；独立审查边界是纯编解码，禁止数据库或网络接线。

**Interfaces，新增且由 C1 完整定义：**

- 复用 `contract::{Revision, Scope, AuthorityBinding, ContractError, Receipt, ExecutionResult, Operation, CommandEnvelope}`、`documents::{DocumentRef, DocumentFormat}`，不复制。
- `ResultId/JobId/IntentId` 分别为私有 String 字段 newtype；`parse(raw: &str) -> Result<Self, ServiceError>` 拒绝空串、NUL、超过 128 UTF-8 字节；不把新 IntentId 解析器当签发器。
- `Digest(String)`：64 位小写 hex；`UnixMs(String)`：规范有符号 i64 十进制，无 +、-0、前导零。
- `ScopeRef { scope: Scope, account_id: Option<String>, scope_generation: Revision }` 是选择/展示投影，不是权限。当前宿主不提供账户绑定时 account_id=None；要求账户级能力的命令拒绝 capability_unavailable，不能信任调用方补账号。
- `ResultRef { result_id: ResultId, input_document_ref: DocumentRef, input_result_refs: Vec<ResultId>, content_digest: Digest, producer_version: String, parameters_digest: Digest }`；直接上游仅 ID，解析必须按 scope 回查完整结果，不把它当全局可读 ID。
- `Coverage { state: CoverageState, processed: u64, total: Option<u64>, failed_units: Vec<u32> }`；状态 Complete/Partial/Failed/Unknown；wire 的 processed/total 使用十进制字符串，total=None 不算百分比。
- `ServiceError { code: ErrorCode, phase: String, retryability: Retryability, effect_knowledge: EffectKnowledge, original_intent_id: Option<IntentId>, safe_message: String, details_ref: Option<String> }`。
- ErrorCode 固定 InvalidArgument/UnsupportedVersion/CapabilityUnavailable/PermissionDenied/StaleRevision/ScopeChanged/ResourceExpired/PartialResult/Cancelled/UnknownOutcome；Retryability 为 Never/AfterLookup/AfterReprepare；EffectKnowledge 为 NotStarted/Confirmed/Unknown。wire 全为 snake_case；不能只看 retryability 自动重试。
- `negotiate(contract_major: u32, schema_major: u32) -> Result<(), ServiceError>`：新公共合同 major=1、schema major=1；v0.2 是设计版本，不能改既有 PROTOCOL_VERSION=1。
- `decode_strict<T: DeserializeOwned>(raw: &str) -> Result<T, ServiceError>` 复用 contract::decode_json 后类型化转换，重复 key/额外安全字段拒绝；单条上限复用 MAX_COMMAND_BYTES。导出类型不得携带 secret、数据库句柄或路径。

- [ ] 写 `revision_and_time_are_exact`：断言 "9007199254740993" 往返相等、"01"/"-0"/u64 溢出拒绝；"9223372036854775807" UnixMs 成功，超 i64 拒绝。
- [ ] 写 `unknown_safety_field_is_rejected` 与 `coverage_unknown_is_not_zero`：重复 key、major=2 拒绝；total=null 保留，processed=0 不能推出 Complete。
- [ ] RED：`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_service_types`；先记录结构 RED，再用无副作用 stub 取得行为断言失败。
- [ ] 实施以上类型与 strict codec；fixture 含正反例并逐一声明预期；金额维持十进制字符串+币种，不能用 f64。
- [ ] GREEN：重跑相同命令，预期全部通过；再跑 `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test contract`，旧版本拒绝规则不退化。
- [ ] 提交 `feat: define public service value contracts`，附 fixture SHA256 与实际输出；失败不提交通过声明。

## C2：HostCommandPort 与回执/任务只读投影

**Owner:** Contracts。**Files:** 新增 `services/commands.rs`、`tests/public_service_commands.rs`、`docs/contracts/public-services-v02/fixtures/commands.json`；C1 owner 登记 mod.rs。FFI 接线仅在 B 审查完成、核对新 develop 后由 Contracts 修改原 lib.rs。依赖 C1。本片先提供类型与解码器，真实 dispatch 不因模块存在自动开放。

**Interfaces：**

```rust
enum OriginalLookup {
    Execution(ExecutionResult),
    NotSubmitted { intent_id: IntentId },
}
enum ReceiptPhase {
    WaitingForConfirmation, Accepted, Running, Succeeded, Failed,
    UnknownOutcome, CancelRequested, Cancelled,
}
struct ReceiptView {
    intent_id: IntentId, phase: ReceiptPhase,
    receipt: Option<Receipt>, cancellation_requested: bool,
}
fn decode_original(raw: &str, expected: &IntentId) -> Result<OriginalLookup, ServiceError>;
fn project_execution(command: &CommandEnvelope, result: &ExecutionResult,
    cancellation_requested: bool) -> Result<ReceiptView, ServiceError>;
trait HostCommandPort {
    fn prepare(&self, operation: Operation, project_id: Option<String>,
        expected_revision: Revision) -> Result<CommandEnvelope, ServiceError>;
    fn confirm(&self, plan_id: &str) -> Result<OriginalLookup, ServiceError>;
    fn lookup_original(&self, intent_id: &IntentId) -> Result<OriginalLookup, ServiceError>;
    fn cancel_original(&self, intent_id: &IntentId) -> Result<ExecutionResult, ServiceError>;
}
```

project_execution 从 command.intent_id 投影原身份，成功前调用 Receipt::validate_for(command)；不能仅凭 Committed 字符串显示成功。C2 新增上述类型；适配器闭包/具体 owner 只能由可信宿主持有，模型不能实现并注入。confirm 可在重复调用时进入 lookup_json，故返回 OriginalLookup 而非假定永远 ExecutionResult。NotSubmitted 仅在严格匹配特例封套时产生；intent_id 来自所查询原身份。错误映射仅是投影，不能改底层 ContractError：InvalidRevision→invalid_argument，RevisionConflict→stale_revision，ScopeMismatch→scope_changed，Unknown/StorageIo 且效果未核清→unknown_outcome，其余按下表编码并测试，不能默认 permission_denied。

| 原 ContractError 分组 | code / retryability / effectKnowledge |
| --- | --- |
| InvalidJson/InvalidIdentity/InvalidRevision/InvalidPayload/InvalidXml/RawLimit/Required/TextLimit/InvalidDigest | invalid_argument / never / not_started |
| InvalidVersion | unsupported_version / never / not_started |
| UnsupportedOperation/Unsupported | capability_unavailable / never / not_started |
| InvalidAuthority | permission_denied / after_reprepare / not_started |
| BindingMismatch/IntentConflict | stale_revision / after_lookup / unknown；不得重发同动作 |
| RevisionConflict | stale_revision / after_reprepare / not_started，仅原 owner 明确拒绝执行时 |
| ScopeMismatch | scope_changed / after_reprepare / not_started，仅原 owner 明确拒绝执行时 |
| Cancelled | cancelled / never / confirmed，仅原终态证据存在时 |
| NotFound/Unknown | unknown_outcome / after_lookup / unknown |
| Storage/StorageBusy/StorageConstraint/StorageCorrupt/StorageIo | unknown_outcome / after_lookup / unknown；不给数据库错误详情到 UI |

上述 not_started 是错误发生在可信 preflight 且原 owner 确认未派发时的投影。相同原因若从 post-dispatch/IPC 丢失路径观察到，一律 effectKnowledge=unknown、retryability=after_lookup；不能仅凭错误枚举证明未发生。C2 加参数化测试逐枚举覆盖此表，未知未来变体 fail closed 并记录 detailsRef，不猜成功。无效输入但原 pending 已存在也不能再次 prepare。

| 原状态 | 展示 |
| --- | --- |
| 可信未确认 CommandEnvelope | waiting_for_confirmation |
| Pending | accepted；没有 owner running 证据不升 running |
| Unknown 或 lookup not_found | unknown_outcome，lookup 原身份 |
| Committed + Receipt::validate_for 原命令成功 | succeeded |
| Rejected | failed |
| Cancelled | cancelled |
| 仅记录取消请求、原结果非终态 | cancel_requested；保留原未知信息 |
| 可信任务 owner 的运行快照 | running，只在 D2 对该 owner 显式接线后可用 |

TaskPort P1 仅原意图查询/取消适配；JobId 查询与进度由 D2 所属模块定义。按 JobId 取消子任务、JobId 生成新意图、取消即撤销外部效果一律不实现。

- [ ] 写 `lookup_special_case_preserves_identity`：精确特例得到 NotSubmitted，拼错 error/recovery_action 拒绝；unknown/not_found 仍 Unknown，绝不据未找到判定从未发生。
- [ ] 写 `pending_and_cancel_are_not_success`：Pending→Accepted、Unknown+取消请求→CancelRequested、无可信 committed receipt 拒绝成功；原 intent 不变，fake host confirm 次数在重复查询时仍为 0。
- [ ] RED/GREEN 命令均为 `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_service_commands`，先见上述断言失败再实施；保持原查询封套不变。
- [ ] 最小实现 decode_original/project_execution 和 fake-host 合同；不在这里给新 Skill/Connector 请求编造 Operation。
- [ ] 回归 `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test business`；待原 FFI owner 交接后才执行 FFI 适配测试，证据需区分纯类型测试与实际 ProductCore。
- [ ] 提交 `feat: adapt original command receipts for public services`；审查重复确认、not_submitted、费用未知与取消目标。

## C3：公共草稿封套、保存确认与订阅恢复合同

**Owner:** Contracts。**Files:** 新增 `services/drafts.rs`、`tests/public_service_drafts.rs`、`docs/contracts/public-services-v02/fixtures/drafts.json`；Android 公共 codec 属 U1，原 Bot 草稿产品文件不在本片修改。依赖 C1/C2；独立审查边界仅封套与纯 CAS 校验，不新建业务数据库。

**Interfaces，新增：**

```rust
struct DraftRef { owner_plugin_id: String, draft_id: String, scope: ScopeRef, revision: Revision }
struct DraftEnvelope { draft_ref: DraftRef, schema_version: u32, content: serde_json::Value }
struct SaveAck { draft_ref: DraftRef, original_intent_id: IntentId, content_digest: Digest }
fn validate_save_ack(current: &DraftEnvelope, expected_revision: &Revision,
    pending_intent: &IntentId, ack: &SaveAck) -> Result<(), ServiceError>;
struct SubscriptionLease { scope: ScopeRef, cursor: String, capacity: u32, expires_at_unix_ms: UnixMs }
enum ResumeAction { ReadSnapshot, ContinueCursor }
fn resume_action(expected_scope: &ScopeRef, lease: &SubscriptionLease,
    cursor_valid: bool) -> Result<ResumeAction, ServiceError>;
```

content 是所属插件 schema 校验后的封套内容，不是任意命令。ack.revision 应等于 expected_revision.next() 且必须绑定保存内容摘要；current.draft_ref.revision 必须等于 expected_revision（存储基线）；current.content 摘要必须匹配待存内容。UI 的本地编辑修订由 U2.UiState 单独追踪：若 ack 返回时本地内容已变，只保留历史 ack，不设当前 saved。公开 create/save/discard 后续均经原 prepare/confirm；P1 不虚构泛领域 Operation。每插件 owner 后续为自己的持久草稿加入原 owner 支持，Bot save 特例由 Contracts 显式适配，不能用 LocalSaveReceipt 充当业务 Receipt。

- [ ] 测试 `stale_ack_does_not_save_current_draft`：错 intent、改内容、旧 revision、scope 变更拒绝；当前精确 ack 接受。测试 `cursor_expiry_only_reads_snapshot`：失效游标返回 ReadSnapshot；不同 scope 返回 ScopeChanged；恢复函数调用业务命令次数始终 0。
- [ ] RED：`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_service_drafts`，预期指定断言失败。
- [ ] 实施纯校验与 fixture；capacity 只校验 1..=256 的 P1 测试限制，不宣称生产配额已批准。生产缓冲、丢弃/断流策略由 D3 工程 gate 决定。
- [ ] GREEN：同命令全部通过；原 `--test bot_drafts` 回归通过且旧保存身份不变。
- [ ] 提交 `feat: define draft acknowledgements and resume semantics`，附未接通的 createDraft/saveDraft/discardDraft 与生产订阅清单。

## 回退与验收

按总索引正常 revert 本片，保留原 Receipt；纯 codec 回退不迁移原数据库。验收需要共享 fixture 摘要、旧合同回归及 ProductCore 实际适配证据分别列出。新领域写命令、账户级宿主绑定、泛领域草稿持久化尚未授权实施，不得因为本计划存在而启用。
